//! Specula code observation for update Scenario U2 / finding MC-1.
//!
//! Real RaftCore runtime (RaftRouter, memstore). Node 1 starts a real election
//! (`trigger().elect(false)`), and while its vote RPC to node 2 is still in
//! flight it starts a Pre-Vote round (`trigger().elect(true)`, the same
//! `Engine::pre_elect` the election tick uses for a timed-out Candidate).
//! Node 2 answers both; its vote response is delivered after 100 ms and its
//! Pre-Vote response after 400 ms (both well inside the RPC ttl of
//! `election_timeout_min` = 1000 ms). Node 0 is unreachable.
//!
//! Requirement (docs/protocol/pre_vote.md:3-6,44-49; config.rs:402-404): a
//! Pre-Vote round is a follower's probe before it starts an election; it must
//! not make an established healthy leader abandon its term.
//! Expected: node 1 stays Leader at the term it won.
//! Observed on the update revision: the late Pre-Vote grant reaches
//! `handle_pre_vote_resp`, whose quorum branch calls `elect()` on the Leader
//! (`pre_candidate` survives `establish_leader`), so node 1 bumps its term and
//! leaves the Leader state. This test FAILS when the defect is present.
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use maplit::btreeset;
use openraft::Config;
use openraft::RPCTypes;
use openraft::ServerState;
use openraft::async_runtime::WatchReceiver;
use openraft::base::BoxFuture;
use openraft::type_config::TypeConfigExt;
use openraft_memstore::TypeConfig;

use crate::fixtures::RaftRouter;
use crate::fixtures::rpc_request::RpcRequest;
use crate::fixtures::ut_harness;

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specula_repro_stale_prevote_demotes_new_leader() -> Result<()> {
    scenario(true).await
}

/// Control: identical setup and delays, but no Pre-Vote trigger. Node 1 must
/// win and keep its term with a live RaftCore.
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specula_repro_control_without_prevote() -> Result<()> {
    scenario(false).await
}

async fn scenario(with_pre_vote: bool) -> Result<()> {
    let config = Arc::new(
        Config {
            enable_heartbeat: false,
            enable_elect: false,
            election_timeout_min: 1000,
            election_timeout_max: 1001,
            ..Default::default()
        }
        .validate()?,
    );
    let mut router = RaftRouter::new(config.clone());
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;
    let n0 = router.get_raft_handle(&0)?;
    let n1 = router.get_raft_handle(&1)?;
    n0.wait(timeout()).state(ServerState::Leader, "node 0 is leader").await?;
    let t0 = n1.metrics().borrow_watched().current_term;

    tracing::info!("--- let the leader lease expire; isolate node 0");
    TypeConfig::sleep(Duration::from_millis(1600)).await;
    router.set_network_error(0, true);

    // Delay node 2's answers to node 1: real vote (term t0+1) by 100 ms,
    // Pre-Vote (probe term t0+2) by 400 ms.
    router
        .set_rpc_post_hook(RPCTypes::Vote, move |_router: &_, req, _resp, from, to| {
            let delay = match &req {
                RpcRequest::Vote(v) if from == 1 && to == 2 => {
                    if v.vote.leader_id().term == t0 + 1 { 100 } else { 400 }
                }
                _ => 0,
            };
            let x: BoxFuture<_> = Box::pin(async move {
                TypeConfig::sleep(Duration::from_millis(delay)).await;
                Ok(())
            });
            x
        })
        .await;

    tracing::info!("--- node 1: real election, then a Pre-Vote round while the vote RPC is in flight");
    n1.trigger().elect(false).await?;
    if with_pre_vote {
        n1.trigger().elect(true).await?;
    }

    n1.wait(Some(Duration::from_millis(1000)))
        .state(ServerState::Leader, "node 1 wins the real election")
        .await?;
    let won_term = n1.metrics().borrow_watched().current_term;
    println!("SPECULA-OBSERVE won: term={} state=Leader", won_term);

    TypeConfig::sleep(Duration::from_millis(800)).await;
    // Query the live RaftCore (metrics alone freeze if the core has died).
    let core = n1
        .with_raft_state(|st| (st.vote_ref().to_string(), st.server_state))
        .await;
    let m = n1.metrics().borrow_watched().clone();
    println!(
        "SPECULA-OBSERVE with_pre_vote={} after-prevote-response: core={:?} metrics: term={} state={:?} vote={}",
        with_pre_vote, core, m.current_term, m.state, m.vote
    );
    let (vote, state) = core.map_err(|e| anyhow::anyhow!("RaftCore of node 1 is gone: {}", e))?;
    assert_eq!(
        (format!("<T{}-N1:Q>", won_term), ServerState::Leader),
        (vote, state),
        "a stale Pre-Vote round must not demote the node's own new leadership"
    );
    Ok(())
}

fn timeout() -> Option<Duration> {
    Some(Duration::from_millis(3000))
}
