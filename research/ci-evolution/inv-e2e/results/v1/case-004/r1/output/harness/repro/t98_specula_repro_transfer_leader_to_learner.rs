//! Specula reproduction for finding MC-1 (update d7176ef9, `Raft::transfer_leader`).
//!
//! Expected (correct) behaviour asserted here: calling `transfer_leader(from = leader vote, to = L)`
//! where `L` is a learner must not kill any node's RaftCore. On the update revision the learner's
//! RaftCore panics with `target not in quorum set` (openraft/src/proposer/candidate.rs:92), so these
//! tests FAIL there. Uses only the public API; no instrumentation or feature flags.

use std::sync::Arc;
use std::time::Duration;

use maplit::btreeset;
use openraft::Config;
use openraft::ServerState;

use crate::fixtures::ut_harness;
use crate::fixtures::RaftRouter;

async fn learner_cluster() -> anyhow::Result<RaftRouter> {
    let config = Arc::new(
        Config {
            election_timeout_min: 150,
            election_timeout_max: 300,
            ..Default::default()
        }
        .validate()?,
    );
    let mut router = RaftRouter::new(config);
    let log_index = router.new_cluster(btreeset! {0,1,2}, btreeset! {3}).await?;
    router.wait_for_log(&btreeset! {0,1,2,3}, Some(log_index), Some(Duration::from_millis(3000)), "caught up").await?;
    Ok(router)
}

/// Minimal trigger: only the learner target receives the request (its vote equals `from`).
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn repro_transfer_leader_to_learner_target_only() -> anyhow::Result<()> {
    let router = learner_cluster().await?;
    let n0 = router.get_raft_handle(&0)?;
    let n3 = router.get_raft_handle(&3)?;
    let m = n0.metrics().borrow().clone();
    let (leader_vote, last_log_id) = (m.vote, m.last_applied);
    n3.wait(Some(Duration::from_millis(3000))).metrics(|x| x.vote == leader_vote, "learner has leader vote").await?;

    n3.transfer_leader(leader_vote, 3, last_log_id).await?;
    tokio::time::sleep(Duration::from_millis(1000)).await;

    let res = n3.is_initialized().await;
    println!("SPECULA_REPRO target_only: learner3.is_initialized = {:?}", res);
    assert!(res.is_ok(), "learner 3 RaftCore died after transfer_leader(to=learner): {:?}", res);
    Ok(())
}

/// Documented usage: call transfer_leader on every node with the same arguments.
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn repro_transfer_leader_to_learner_all_nodes() -> anyhow::Result<()> {
    let router = learner_cluster().await?;
    let n0 = router.get_raft_handle(&0)?;
    let n3 = router.get_raft_handle(&3)?;
    let m = n0.metrics().borrow().clone();
    let (leader_vote, last_log_id) = (m.vote, m.last_applied);
    n3.wait(Some(Duration::from_millis(3000))).metrics(|x| x.vote == leader_vote, "learner has leader vote").await?;

    for id in [0u64, 1, 2, 3] {
        router.get_raft_handle(&id)?.transfer_leader(leader_vote, 3, last_log_id).await?;
    }
    tokio::time::sleep(Duration::from_millis(1500)).await;

    let mut report = vec![];
    for id in [0u64, 1, 2, 3] {
        let n = router.get_raft_handle(&id)?;
        let alive = n.is_initialized().await;
        let x = n.metrics().borrow().clone();
        report.push(format!("n{}: alive={:?} state={:?} vote={} leader={:?}", id, alive, x.state, x.vote, x.current_leader));
    }
    println!("SPECULA_REPRO all_nodes: {}", report.join(" | "));
    let res = n3.is_initialized().await;
    assert!(res.is_ok(), "learner 3 RaftCore died after transfer_leader(to=learner): {:?}", res);
    let _ = ServerState::Learner;
    Ok(())
}
