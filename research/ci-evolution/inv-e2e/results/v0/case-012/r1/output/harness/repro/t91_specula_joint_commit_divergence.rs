//! Specula consequence probe for finding MC-1 (5 voters). Leader 3 removes
//! itself and node 5 toward goal {1,2,4}: joint [{1,2,3,4,5},{1,2,4}]. When the
//! joint entry is committed with only {2,3} holding it (no majority of either
//! component), the remaining nodes {1,4,5} can elect a leader that commits a
//! different entry at the same index. Safety requirement checked: two nodes
//! never apply different log ids at the same index.
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
async fn specula_applied_entries_never_diverge_after_joint_change() -> Result<()> {
    let config = Arc::new(Config::default().validate()?);
    let mut router = RaftRouter::new(config.clone());
    let to = Some(Duration::from_millis(5_000));

    router.new_raft_node(3);
    router.wait_for_log(&btreeset![3], None, to, "empty").await?;
    router.wait_for_state(&btreeset![3], ServerState::Learner, to, "empty").await?;
    router.initialize_from_single_node(3).await?;
    let mut log_index = 1;
    router.wait_for_log(&btreeset![3], Some(log_index), to, "init").await?;
    for id in [1u64, 2, 4, 5] {
        router.new_raft_node(id);
        router.add_learner(3, id).await?;
        log_index += 1;
    }
    router.wait_for_log(&btreeset![1, 2, 3, 4, 5], Some(log_index), to, "learners").await?;
    router.get_raft_handle(&3)?.change_membership(btreeset![1, 2, 3, 4, 5], true, false).await?;
    log_index += 2;
    router.wait_for_log(&btreeset![1, 2, 3, 4, 5], Some(log_index), to, "voters").await?;

    tracing::info!("--- isolate 2,4; entry acknowledged by 1 and 5");
    router.isolate_node(2);
    router.isolate_node(4);
    router.client_request(3, "foo", 1).await?;
    log_index += 1;
    router.wait_for_log(&btreeset![1, 3, 5], Some(log_index), to, "1,3,5 have the entry").await?;

    tracing::info!("--- isolate 1,5; restore 2; leader 3 starts change toward {{1,2,4}}");
    router.isolate_node(1);
    router.isolate_node(5);
    router.restore_node(2);
    {
        let router = router.clone();
        tokio::spawn(async move {
            let node = router.get_raft_handle(&3)?;
            node.change_membership(btreeset![1, 2, 4], true, false).await?;
            Ok::<(), anyhow::Error>(())
        });
    }
    let joint_index = log_index + 1;
    let joint_committed = router
        .wait_for_metrics(&3, |x| x.last_applied.index() >= Some(joint_index), Some(Duration::from_millis(3_000)), "joint")
        .await
        .is_ok();
    let m3 = router.get_metrics(&3)?;

    tracing::info!("--- isolate 3,2; restore 1,4,5 (a majority of the old config)");
    router.isolate_node(3);
    router.isolate_node(2);
    router.restore_node(1);
    router.restore_node(4);
    router.restore_node(5);
    let _ = router
        .wait_for_metrics(&1, |x| x.last_applied.index() >= Some(joint_index), Some(Duration::from_millis(10_000)), "new leader commits")
        .await;
    let m1 = router.get_metrics(&1)?;
    println!(
        "SPECULA_DIVERGENCE joint_index={} joint_committed_by_3={} node3.last_applied={:?} node1.last_applied={:?} node1.current_leader={:?} node1.term={}",
        joint_index, joint_committed, m3.last_applied, m1.last_applied, m1.current_leader, m1.current_term
    );
    if m3.last_applied.index() == Some(joint_index) && m1.last_applied.index() == Some(joint_index) {
        assert_eq!(m3.last_applied, m1.last_applied, "nodes 3 and 1 applied different log ids at the same index");
    }
    Ok(())
}
