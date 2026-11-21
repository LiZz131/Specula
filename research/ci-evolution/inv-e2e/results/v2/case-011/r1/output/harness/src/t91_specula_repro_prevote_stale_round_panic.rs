//! Specula reproduction (test-only): a granted Pre-Vote response of an earlier
//! round is accepted by a later round that probes the same leader id; after a
//! membership change removed the responder, Candidate::grant_by panics and the
//! RaftCore dies.
//!
//! Model: spec/output/mc-hunt-U4b-panic-bfs.log / mc-hunt-U4-stale-bfs.log.
//! Only public APIs (`trigger().elect(true)`, `change_membership`, runtime
//! config switches) and the RaftRouter delay/unreachable hooks are used.

use std::sync::Arc;
use std::sync::atomic::AtomicU8;
use std::sync::atomic::Ordering;
use std::time::Duration;

use anyhow::Result;
use maplit::btreeset;
use openraft::Config;
use openraft::RPCTypes;
use openraft::ServerState;
use openraft::async_runtime::WatchReceiver;
use openraft::errors::RPCError;
use openraft::errors::Unreachable;
use openraft::type_config::TypeConfigExt;
use openraft_memstore::TypeConfig;

use crate::fixtures::RaftRouter;
use crate::fixtures::rpc_request::RpcRequest;
use crate::fixtures::rpc_response::RpcResponse;
use crate::fixtures::ut_harness;

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specula_repro_stale_prevote_round_grant_from_removed_node() -> Result<()> {
    let config = Arc::new(
        Config {
            election_timeout_min: 500,
            election_timeout_max: 600,
            heartbeat_interval: 100,
            ..Default::default()
        }
        .validate()?,
    );

    let mut router = RaftRouter::new(config.clone());
    router.new_cluster(btreeset! {0,1,2,3}, btreeset! {}).await?;

    let n0 = router.get_raft_handle(&0)?;
    let n1 = router.get_raft_handle(&1)?;
    n0.wait(timeout()).state(ServerState::Leader, "node 0 is leader").await?;

    // No timer elections anywhere; the leader stops heartbeating so that the
    // followers' leader leases expire (log replication still works).
    for id in 0..4u64 {
        router.get_raft_handle(&id)?.runtime_config().elect(false);
    }
    n0.runtime_config().heartbeat(false);
    TypeConfig::sleep(Duration::from_millis(1_000)).await;

    // Network: node 1's Vote-kind RPCs to node 0 are unreachable; node 3's first
    // Pre-Vote grant to node 1 is delivered 400 ms late (below the 500 ms RPC timeout).
    router
        .set_rpc_pre_hook(RPCTypes::Vote, |_router, _req, from, target| {
            let res = if from == 1 && target == 0 {
                Err(RPCError::Unreachable(Unreachable::<TypeConfig>::from_string("unreachable")))
            } else {
                Ok(())
            };
            Box::pin(futures::future::ready(res))
        })
        .await;
    let delayed = Arc::new(AtomicU8::new(0));
    let d = delayed.clone();
    router
        .set_rpc_post_hook(RPCTypes::Vote, move |_router, req, resp, from, to| {
            let mut delay = Duration::ZERO;
            if let (RpcRequest::Vote(req), RpcResponse::Vote(resp)) = (&req, &resp) {
                let pre_vote_grant = resp.vote_granted && resp.vote != req.vote;
                if from == 1 && to == 3 && pre_vote_grant && d.swap(1, Ordering::SeqCst) == 0 {
                    delay = Duration::from_millis(400);
                }
            }
            Box::pin(async move {
                TypeConfig::sleep(delay).await;
                Ok(())
            })
        })
        .await;

    let term_before = n1.metrics().borrow_watched().current_term;

    tracing::info!("--- round A: operator Pre-Vote on node 1 over {{0,1,2,3}}");
    n1.trigger().elect(true).await?;
    TypeConfig::sleep(Duration::from_millis(30)).await;

    tracing::info!("--- leader removes node 3 (joint, then uniform {{0,1,2}})");
    n0.change_membership(btreeset! {0,1,2}, false).await?;
    n1.wait(timeout())
        .metrics(
            |m| m.membership_config.membership().voter_ids().collect::<Vec<_>>() == vec![0, 1, 2],
            "node 1 sees uniform {0,1,2}",
        )
        .await?;

    tracing::info!("--- round B: operator Pre-Vote on node 1 again, same probed vote");
    n1.trigger().elect(true).await?;

    tracing::info!("--- node 3's delayed grant of round A arrives");
    TypeConfig::sleep(Duration::from_millis(1_000)).await;

    let res = n1.trigger().heartbeat().await;
    let core_panicked = matches!(res, Err(openraft::errors::Fatal::Panicked));
    let m1 = n1.metrics().borrow_watched().clone();
    println!(
        "SPECULA_REPRO {{\"scenario\":\"stale_prevote_round_grant_from_removed_node\",\"term_before\":{},\"node1_term_after\":{},\"delayed_grant_sent\":{},\"heartbeat_result\":\"{:?}\",\"raft_core_panicked\":{}}}",
        term_before,
        m1.current_term,
        delayed.load(Ordering::SeqCst),
        res,
        core_panicked
    );

    assert!(
        !core_panicked,
        "a delayed Pre-Vote response of an earlier round crashed the RaftCore"
    );
    Ok(())
}

fn timeout() -> Option<Duration> {
    Some(Duration::from_millis(3_000))
}
