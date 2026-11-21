//! Specula reproduction for MC-1 (harness-owned; appended to t99_specula_transfer.rs by
//! harness/repro/run_repro.sh). Asserting tests:
//!
//! * `specula_repro_transfer_to_learner_no_panic`: `Raft::transfer_leader(from, to = learner)`
//!   called on every node as documented. Requirement (docs/data/vote.md:50-51): a learner does
//!   not try to elect itself; a panic is a fatal shutdown (error.rs:122). The test fails if the
//!   learner's RaftCore reports `Fatal::Panicked` or the learner became Candidate/Leader.
//! * `specula_control_trigger_elect_on_learner`: the pre-existing, voter-guarded path
//!   (`ExternalCommand::Elect`, raft_core.rs:1206-1214) on the same learner; must not panic.

use std::sync::Arc;
use std::time::Duration;

use maplit::btreeset;
use openraft::error::Fatal;
use openraft::error::RaftError;
use openraft::Config;
use openraft::ServerState;
use openraft_memstore::ClientRequest;
use openraft_memstore::IntoMemClientRequest;

use crate::fixtures::ut_harness;
use crate::fixtures::MemRaft;
use crate::fixtures::RaftRouter;

fn repro_config() -> anyhow::Result<Arc<Config>> {
    Ok(Arc::new(
        Config {
            election_timeout_min: 150,
            election_timeout_max: 300,
            ..Default::default()
        }
        .validate()?,
    ))
}

async fn learner_is_alive(n3: &MemRaft) -> Result<(), String> {
    let w = n3.client_write(ClientRequest::make_request("repro", 1)).await;
    match w {
        Err(RaftError::Fatal(Fatal::Panicked)) => Err("learner node-3 RaftCore panicked".to_string()),
        Err(RaftError::Fatal(f)) => Err(format!("learner node-3 fatal: {}", f)),
        _ => Ok(()),
    }
}

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specula_repro_transfer_to_learner_no_panic() -> anyhow::Result<()> {
    let mut router = RaftRouter::new(repro_config()?);
    router.new_cluster(btreeset! {0,1,2}, btreeset! {3}).await?;
    let n: Vec<MemRaft> = (0..4).map(|i| router.get_raft_handle(&i)).collect::<Result<_, _>>()?;

    let m0 = n[0].metrics().borrow().clone();
    let (leader_vote, last_log_id) = (m0.vote, m0.last_applied);

    for i in 0..4 {
        // A fixed implementation may reject the call; only the node's fate is asserted.
        let _ = n[i].transfer_leader(leader_vote, 3, last_log_id).await;
    }
    tokio::time::sleep(Duration::from_millis(500)).await;

    let st = n[3].metrics().borrow().state;
    println!("SPECULA_REPRO node-3 state after transfer: {:?}", st);
    learner_is_alive(&n[3]).await.map_err(anyhow::Error::msg)?;
    assert!(
        st != ServerState::Candidate && st != ServerState::Leader,
        "learner node-3 campaigned: {:?}",
        st
    );
    Ok(())
}

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specula_control_trigger_elect_on_learner() -> anyhow::Result<()> {
    let mut router = RaftRouter::new(repro_config()?);
    router.new_cluster(btreeset! {0,1,2}, btreeset! {3}).await?;
    let n3 = router.get_raft_handle(&3)?;

    n3.trigger().elect().await?;
    tokio::time::sleep(Duration::from_millis(500)).await;

    let st = n3.metrics().borrow().state;
    println!("SPECULA_CONTROL node-3 state after trigger().elect(): {:?}", st);
    learner_is_alive(&n3).await.map_err(anyhow::Error::msg)?;
    assert_eq!(st, ServerState::Learner);
    Ok(())
}
