//! Old-revision control for MC-1: the only pre-existing public way to make a node run
//! `Engine::elect()` on demand is `Raft::trigger().elect()` (ExternalCommand::Elect), which
//! checks `is_voter` first. On a learner it must be a no-op: no candidate, no panic.
use std::sync::Arc;
use std::time::Duration;

use maplit::btreeset;
use openraft::Config;
use openraft::ServerState;

use crate::fixtures::ut_harness;
use crate::fixtures::RaftRouter;

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn control_mc1_baseline_learner_elect_is_guarded() -> anyhow::Result<()> {
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
    let n3 = router.get_raft_handle(&3)?;
    n3.wait(Some(Duration::from_millis(1_000))).applied_index(Some(log_index), "learner caught up").await?;

    n3.trigger().elect().await?;
    tokio::time::sleep(Duration::from_millis(1_000)).await;

    let res = n3.is_initialized().await;
    let m3 = n3.metrics().borrow().clone();
    let m0 = n0.metrics().borrow().clone();
    println!("CONTROL-MC-1 baseline learner after trigger().elect(): is_initialized={:?} state={:?} vote={}; n0 state={:?} vote={}", res, m3.state, m3.vote, m0.state, m0.vote);
    assert!(res.is_ok());
    assert_eq!(m3.state, ServerState::Learner);
    assert_eq!(m0.state, ServerState::Leader);
    Ok(())
}
