//! Old-revision control for finding MC-1 (baseline d86101c7 has no `transfer_leader`).
//! The closest pre-update way to ask a learner to elect is `trigger().elect()`
//! (ExternalCommand::Elect), which checks `is_voter` (core/raft_core.rs ExternalCommand::Elect).
//! Asserts the learner neither elects nor panics, i.e. the panic path is unreachable before the update.

use std::sync::Arc;
use std::time::Duration;

use maplit::btreeset;
use openraft::Config;
use openraft::ServerState;

use crate::fixtures::ut_harness;
use crate::fixtures::RaftRouter;

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn control_old_trigger_elect_on_learner() -> anyhow::Result<()> {
    let config = Arc::new(Config { election_timeout_min: 150, election_timeout_max: 300, ..Default::default() }.validate()?);
    let mut router = RaftRouter::new(config);
    let log_index = router.new_cluster(btreeset! {0,1,2}, btreeset! {3}).await?;
    router.wait_for_log(&btreeset! {0,1,2,3}, Some(log_index), Some(Duration::from_millis(3000)), "caught up").await?;
    let n3 = router.get_raft_handle(&3)?;
    n3.trigger().elect().await?;
    tokio::time::sleep(Duration::from_millis(1000)).await;
    let res = n3.is_initialized().await;
    let m = n3.metrics().borrow().clone();
    println!("SPECULA_CONTROL old: learner3.is_initialized = {:?}, state = {:?}, vote = {}", res, m.state, m.vote);
    assert!(res.is_ok(), "learner RaftCore died: {:?}", res);
    assert_eq!(m.state, ServerState::Learner);
    Ok(())
}
