//! Specula reproduction for finding MC-1 (model counterexample
//! spec/output/upd-hunt-u1-consequence-bfs.log), driven through the real
//! RaftCore / LeaderState / replication-stream runtime with the in-repo router.
//!
//! Cluster {1,2,3} with leader 3 (largest id). Node 1 acknowledges the latest
//! entry while node 2 is isolated; then node 1 is isolated, node 2 restored,
//! and the leader starts removing itself (goal {1,2}): the joint config is
//! [{1,2,3},{1,2}]. Node 1 cannot receive the joint entry, so its {1,2}
//! component cannot reach a majority: the joint log must not be committed.
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use maplit::btreeset;
use openraft::Config;
use openraft::LogIdOptionExt;
use openraft::ServerState;

use crate::fixtures::init_default_ut_tracing;
use crate::fixtures::RaftRouter;

#[async_entry::test(worker_threads = 8, init = "init_default_ut_tracing()", tracing_span = "debug")]
async fn specula_joint_config_must_not_commit_without_new_component_majority() -> Result<()> {
    let config = Arc::new(Config::default().validate()?);
    let mut router = RaftRouter::new(config.clone());
    let to = Some(Duration::from_millis(5_000));

    tracing::info!("--- leader 3 forms {{1,2,3}}");
    router.new_raft_node(3);
    router.wait_for_log(&btreeset![3], None, to, "empty").await?;
    router.wait_for_state(&btreeset![3], ServerState::Learner, to, "empty").await?;
    router.initialize_from_single_node(3).await?;
    let mut log_index = 1; // 0: initial membership, 1: leader blank
    router.wait_for_log(&btreeset![3], Some(log_index), to, "init").await?;

    router.new_raft_node(1);
    router.new_raft_node(2);
    router.add_learner(3, 1).await?;
    router.add_learner(3, 2).await?;
    log_index += 2;
    router.wait_for_log(&btreeset![1, 2, 3], Some(log_index), to, "learners").await?;

    let leader = router.get_raft_handle(&3)?;
    leader.change_membership(btreeset![1, 2, 3], true, false).await?;
    log_index += 2;
    router.wait_for_log(&btreeset![1, 2, 3], Some(log_index), to, "voters 1,2,3").await?;

    tracing::info!("--- isolate 2; node 1 acknowledges a new entry");
    router.isolate_node(2);
    router.client_request(3, "foo", 1).await?;
    log_index += 1;
    router.wait_for_log(&btreeset![1, 3], Some(log_index), to, "1 and 3 have the entry").await?;

    tracing::info!("--- isolate 1, restore 2, leader removes itself: joint [{{1,2,3}},{{1,2}}]");
    router.isolate_node(1);
    router.restore_node(2);
    {
        let router = router.clone();
        tokio::spawn(
            async move {
                let node = router.get_raft_handle(&3)?;
                node.change_membership(btreeset![1, 2], true, false).await?;
                Ok::<(), anyhow::Error>(())
            }
            .instrument(tracing::debug_span!("spawn-change-membership")),
        );
    }
    let joint_index = log_index + 1;

    let m1 = router.get_metrics(&1)?;
    let res = router
        .wait_for_metrics(
            &3,
            |x| x.last_applied.index() >= Some(joint_index),
            Some(Duration::from_millis(3_000)),
            "joint log must not commit while node 1 is isolated",
        )
        .await;
    let m3 = router.get_metrics(&3)?;
    let m2 = router.get_metrics(&2)?;
    println!(
        "SPECULA_REPRO joint_index={} leader3.last_log={:?} leader3.last_applied={:?} leader3.membership={:?} node1.last_log={:?} node2.last_log={:?}",
        joint_index, m3.last_log_index, m3.last_applied, m3.membership_config, m1.last_log_index, m2.last_log_index
    );
    assert!(res.is_err(), "joint log committed although node 1 (required by component {{1,2}}) is isolated");
    Ok(())
}
