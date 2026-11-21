//! Specula MC-1 reproduction (runtime level): a Pre-Vote round that was started
//! while the node was still a Candidate survives leader establishment; a late
//! granting Pre-Vote response then makes the freshly established leader call
//! `elect()` and abandon its leadership, although nothing failed.
//!
//! Expected (correct) behavior asserted here: once node 1 is leader at term
//! `t0 + 1` and no further fault happens, it keeps leadership at that term.
//! The test FAILS on an implementation that lets the stale round complete.
//!
//! Install: copy to tests/tests/elect/ and add `mod t90_specula_stale_pre_vote;`
//! to tests/tests/elect/main.rs; run
//! `cargo test -p tests --test elect t90_specula_stale_pre_vote -- --nocapture`.

use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use maplit::btreeset;
use openraft::Config;
use openraft::RPCTypes;
use openraft::ServerState;
use openraft::async_runtime::WatchReceiver;
use openraft::base::BoxFuture;
use openraft::errors::RPCError;
use openraft::type_config::TypeConfigExt;
use openraft::vote::RaftLeaderId;
use openraft_memstore::TypeConfig;

use crate::fixtures::RaftRouter;
use crate::fixtures::rpc_request::RpcRequest;
use crate::fixtures::rpc_response::RpcResponse;
use crate::fixtures::ut_harness;

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn stale_pre_vote_round_does_not_demote_new_leader() -> Result<()> {
    // Wide election timeout so the vote RPC ttl (= election_timeout_min) is
    // larger than the injected response delays.
    let config = Arc::new(
        Config {
            enable_pre_vote: Some(true),
            heartbeat_interval: 100,
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
    let n2 = router.get_raft_handle(&2)?;
    n0.wait(timeout()).state(ServerState::Leader, "node 0 is leader").await?;
    let t0 = n0.metrics().borrow_watched().current_term;

    tracing::info!("--- only the explicit triggers below start elections; isolate the old leader");
    for n in [&n0, &n1, &n2] {
        n.runtime_config().elect(false);
    }
    n0.runtime_config().heartbeat(false);
    router.set_network_error(0, true);
    // Let node 2's lease from node 0 expire (leader_lease = election_timeout_max).
    TypeConfig::sleep(Duration::from_millis(1500)).await;

    tracing::info!("--- delay node 2's responses to node 1: real vote 300ms, pre-vote 600ms");
    router
        .set_rpc_post_hook(RPCTypes::Vote, move |_r, req, resp, from, to| {
            let delay = match (req, resp) {
                (RpcRequest::Vote(req), RpcResponse::Vote(resp)) if from == 1 && to == 2 => {
                    let term = req.vote.leader_id().term();
                    if term == t0 + 1 && resp.vote == req.vote {
                        300 // granted real vote for the in-flight election
                    } else if term == t0 + 2 && resp.vote != req.vote {
                        600 // pre-vote answer (the responder's vote is unchanged)
                    } else {
                        0
                    }
                }
                _ => 0,
            };
            let fu: BoxFuture<'static, Result<(), RPCError<TypeConfig>>> = Box::pin(async move {
                if delay > 0 {
                    TypeConfig::sleep(Duration::from_millis(delay)).await;
                }
                Ok(())
            });
            fu
        })
        .await;

    tracing::info!("--- node 1 starts a real election at t0+1");
    n1.trigger().elect(false).await?;
    TypeConfig::sleep(Duration::from_millis(50)).await;
    {
        let m = n1.metrics().borrow_watched().clone();
        assert_eq!((t0 + 1, ServerState::Candidate), (m.current_term, m.state));
    }

    tracing::info!("--- while that election is in flight, a cautious election is requested");
    n1.trigger().elect(true).await?;

    n1.wait(timeout()).state(ServerState::Leader, "node 1 becomes leader").await?;
    let leader_term = n1.metrics().borrow_watched().current_term;
    assert_eq!(t0 + 1, leader_term, "node 1 won the election it started at t0+1");
    tracing::info!("--- node 1 is leader at term {}; no further fault is injected", leader_term);

    TypeConfig::sleep(Duration::from_millis(1000)).await;

    // The leader must still be alive and serve a write (node 2 is a reachable follower).
    let write = router.client_request_many(1, "foo", 1).await;
    let m = n1.metrics().borrow_watched().clone();
    println!(
        "--- after 1s: node 1 term={} state={:?} running_state={:?} write={:?}",
        m.current_term, m.state, m.running_state, write
    );
    assert!(write.is_ok(), "node 1 must still serve writes as leader: {:?}", write);
    assert_eq!(
        (leader_term, ServerState::Leader),
        (m.current_term, m.state),
        "a Pre-Vote round started before node 1 became leader must not make the established leader re-elect"
    );

    Ok(())
}

fn timeout() -> Option<Duration> {
    Some(Duration::from_millis(3000))
}
