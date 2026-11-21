//! Specula reproduction (test-only): a timer-started Pre-Vote round that
//! outlives the node's own leader establishment demotes the new leader.
//!
//! Model counterexample: spec/output/mc-hunt-U2-bfs.log (TimerPreVoteElectsOnlyNonLeader).
//! Only public APIs and the existing RaftRouter fixture hooks are used; the
//! network hook only delays responses (asynchronous network), it never forges
//! or drops them.

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
use openraft::type_config::TypeConfigExt;
use openraft_memstore::BlockOperation;
use openraft_memstore::TypeConfig;

use crate::fixtures::RaftRouter;
use crate::fixtures::rpc_request::RpcRequest;
use crate::fixtures::rpc_response::RpcResponse;
use crate::fixtures::ut_harness;

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specula_repro_stale_prevote_demotes_new_leader() -> Result<()> {
    let config = Arc::new(
        Config {
            enable_pre_vote: Some(true),
            election_timeout_min: 500,
            election_timeout_max: 600,
            heartbeat_interval: 100,
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
    let t0 = n1.metrics().borrow_watched().current_term;

    // Only node 1 runs the election timer path; node 2 just answers.
    n2.runtime_config().elect(false);

    // Node 1 persists votes slowly (400 ms per save_vote, e.g. a slow fsync). SaveVote is
    // awaited before SendVote, so its vote requests leave late relative to its own
    // election timer, which runs from the moment the vote was set in memory.
    let (sto1, _sm1) = router.get_storage_handle(&1)?;
    sto1.block_config().set_blocking(BlockOperation::DelaySaveVote, Duration::from_millis(400));

    // Vote RPC responses travel back with a delay below the RPC timeout
    // (election_timeout_min = 500 ms):
    // - phase 0: no delay (the first Pre-Vote round of node 1 completes normally);
    // - the first real vote grant (resp.vote == req.vote) is delayed 450 ms, so it arrives
    //   after node 1's election timer has fired while node 1 is still a Candidate;
    // - Pre-Vote grants (the responder keeps its own vote, resp.vote != req.vote) sent after
    //   that are delayed 450 ms, so they arrive after node 1 has become leader.
    let phase = Arc::new(AtomicU8::new(0));
    let ph = phase.clone();
    router
        .set_rpc_post_hook(RPCTypes::Vote, move |_router, req, resp, _from, _to| {
            let mut delay = Duration::ZERO;
            if let (RpcRequest::Vote(req), RpcResponse::Vote(resp)) = (&req, &resp) {
                if resp.vote_granted {
                    if resp.vote == req.vote {
                        if ph.swap(1, Ordering::SeqCst) == 0 {
                            delay = Duration::from_millis(450);
                        }
                    } else if ph.load(Ordering::SeqCst) == 1 {
                        delay = Duration::from_millis(450);
                    }
                }
            }
            Box::pin(async move {
                TypeConfig::sleep(delay).await;
                Ok(())
            })
        })
        .await;

    tracing::info!("--- isolate leader 0");
    router.set_network_error(0, true);

    tracing::info!("--- let node 1 run its timer-driven elections; observe after 5 s");
    TypeConfig::sleep(Duration::from_millis(5_000)).await;

    let m1 = n1.metrics().borrow_watched().clone();
    let heartbeat = n1.trigger().heartbeat().await;
    let core_panicked = matches!(heartbeat, Err(openraft::errors::Fatal::Panicked));
    println!(
        "SPECULA_REPRO {{\"scenario\":\"stale_prevote_demotes_new_leader\",\"initial_term\":{},\"leader_term\":{},\"node1_term_after\":{},\"node1_state_after\":\"{:?}\",\"node1_vote_after\":\"{}\",\"heartbeat_result\":\"{:?}\",\"raft_core_panicked\":{},\"debug_assertions\":{}}}",
        t0,
        t0 + 1,
        m1.current_term,
        m1.state,
        m1.vote,
        heartbeat,
        core_panicked,
        cfg!(debug_assertions)
    );

    // A healthy, freshly elected leader must not abandon its term because of a
    // Pre-Vote round that started before it became leader.
    assert!(
        !core_panicked && m1.current_term == t0 + 1 && m1.state == ServerState::Leader,
        "stale Pre-Vote round demoted the new leader: term {} -> {}, state {:?}, core panicked: {}",
        t0 + 1,
        m1.current_term,
        m1.state,
        core_panicked
    );
    Ok(())
}

fn timeout() -> Option<Duration> {
    Some(Duration::from_millis(3_000))
}
