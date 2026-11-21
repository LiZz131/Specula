//! Reproduction for MC-1 (Specula incremental run, update revision).
//!
//! Call `Raft::transfer_leader(leader_vote, to, last_log_id)` on every node, as the API
//! documentation prescribes, with `to` = a *learner*. The learner's RaftCore runs
//! `Engine::elect()` (no voter check in the TransferLeader handler), saves its vote, and then
//! processes its own vote grant: `Candidate::grant_by(learner)` panics with
//! "target not in quorum set" because the candidate progress contains voters only.
//!
//! The test PASSES when the bug is reproduced (learner RaftCore reports Fatal::Panicked).

use std::sync::Arc;
use std::time::Duration;

use maplit::btreeset;
use openraft::error::Fatal;
use openraft::Config;
use openraft::ServerState;

use crate::fixtures::ut_harness;
use crate::fixtures::RaftRouter;

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn repro_mc1_transfer_leader_to_learner_panics() -> anyhow::Result<()> {
    let config = Arc::new(
        Config {
            election_timeout_min: 150,
            election_timeout_max: 300,
            ..Default::default()
        }
        .validate()?,
    );
    let mut router = RaftRouter::new(config.clone());
    let log_index = router.new_cluster(btreeset! {0,1,2}, btreeset! {3}).await?;

    let n0 = router.get_raft_handle(&0)?;
    let n1 = router.get_raft_handle(&1)?;
    let n2 = router.get_raft_handle(&2)?;
    let n3 = router.get_raft_handle(&3)?;
    n3.wait(Some(Duration::from_millis(1_000))).applied_index(Some(log_index), "learner caught up").await?;

    let m0 = n0.metrics().borrow().clone();
    let m3 = n3.metrics().borrow().clone();
    assert_eq!(m0.state, ServerState::Leader);
    assert_eq!(m3.state, ServerState::Learner, "node 3 is a learner before the transfer");
    assert_eq!(m3.vote, m0.vote, "the learner holds the leader's committed vote");
    assert!(n3.is_initialized().await.is_ok(), "learner core healthy before transfer");

    let leader_vote = m0.vote;
    let last_log_id = m0.last_applied;
    for n in [&n0, &n1, &n2, &n3] {
        n.transfer_leader(leader_vote, 3, last_log_id).await?;
    }

    tokio::time::sleep(Duration::from_millis(1_000)).await;

    let res = n3.is_initialized().await;
    println!("REPRO-MC-1 learner n3.is_initialized() after transfer_leader(to=learner) = {:?}", res);
    for (id, n) in [(0u64, &n0), (1, &n1), (2, &n2)] {
        let m = n.metrics().borrow().clone();
        println!("REPRO-MC-1 n{} state={:?} vote={} current_leader={:?}", id, m.state, m.vote, m.current_leader);
    }
    assert!(
        matches!(res, Err(Fatal::Panicked)),
        "expected the learner RaftCore to have panicked, got {:?}",
        res
    );
    Ok(())
}
