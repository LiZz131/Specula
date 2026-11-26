//! Specular MC-1 reproduction: a Pre-Vote round survives leader
//! establishment and makes the freshly established Leader start a new
//! election (term bump) — no external trigger after establishment, healthy
//! reachable peer.
//!
//! Mechanism (updated revision):
//! - Engine::pre_elect runs while the node is still a Candidate and leaves the
//!   running real election (`candidate`) untouched;
//! - Engine::establish_leader consumes only `candidate`, not `pre_candidate`;
//! - RaftCore forwards the later PreVoteResponse (same leader id) and
//!   Engine::handle_pre_vote_resp calls elect() without checking the role;
//! - do_elect keeps the Leader object, so `leader.committed_vote < state.vote`.
//!
//! Two entry points are exercised:
//! - Level 1 (public API only): the Pre-Vote round is started on the Candidate
//!   by `trigger().elect(true)`; only response delivery is delayed by the
//!   router post-hook (below the RPC ttl).
//! - Level 3 (timer path, no admin call): vote persistence on node 1 is slowed
//!   by a test-storage hook (`BlockOperation::SaveVote`, memstore only) so the
//!   Candidate's election timer fires (RaftCore::handle_tick_election ->
//!   pre_elect) before its own election traffic is processed.

use std::sync::Arc;
use std::sync::Mutex;
use std::sync::Once;
use std::time::Duration;

use anyhow::Result;
use maplit::btreeset;
use openraft::Config;
use openraft::RPCTypes;
use openraft::ServerState;
use openraft::async_runtime::WatchReceiver;
use openraft::type_config::TypeConfigExt;
use openraft_memstore::BlockOperation;
use openraft_memstore::ClientRequest;
use openraft_memstore::IntoMemClientRequest;
use openraft_memstore::TypeConfig;

use crate::fixtures::RaftRouter;
use crate::fixtures::rpc_request::RpcRequest;
use crate::fixtures::rpc_response::RpcResponse;
use crate::fixtures::ut_harness;

static PANICS: Mutex<Vec<String>> = Mutex::new(Vec::new());
static HOOK: Once = Once::new();

/// Record every panic (location + message) while keeping the previous hook.
fn capture_panics() {
    HOOK.call_once(|| {
        let prev = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            let msg = info
                .payload()
                .downcast_ref::<String>()
                .cloned()
                .or_else(|| info.payload().downcast_ref::<&str>().map(|s| s.to_string()))
                .unwrap_or_default();
            let loc = info.location().map(|l| format!("{}:{}", l.file(), l.line())).unwrap_or_default();
            PANICS.lock().unwrap().push(format!("{} | {}", loc, msg));
            prev(info);
        }));
    });
    PANICS.lock().unwrap().clear();
}

/// The MC-1 oracle: the Leader handler assertion fired with a committed leader
/// vote behind the local (re-elected) vote.
fn leader_vote_assertion_fired() -> bool {
    let p = PANICS.lock().unwrap();
    for x in p.iter() {
        println!("specular: captured panic: {}", x);
    }
    p.iter().any(|x| x.contains("engine/engine_impl.rs") && x.contains("leader.vote(") && x.contains(">= state.vote("))
}

fn config_with(pre_vote: bool) -> Result<Arc<Config>> {
    Ok(Arc::new(
        Config {
            enable_pre_vote: Some(pre_vote),
            election_timeout_min: 500,
            election_timeout_max: 501,
            heartbeat_interval: 100,
            ..Default::default()
        }
        .validate()?,
    ))
}

#[allow(dead_code)]
fn config() -> Result<Arc<Config>> {
    Ok(Arc::new(
        Config {
            enable_pre_vote: Some(true),
            election_timeout_min: 500,
            election_timeout_max: 501,
            heartbeat_interval: 100,
            ..Default::default()
        }
        .validate()?,
    ))
}

/// Delay delivery (to node 1) of node 2's granted real-vote response for term 2
/// and of node 2's response to the term-3 Pre-Vote. Both delays are below the
/// vote RPC ttl (election_timeout_min = 500 ms), so nothing is dropped.
async fn install_delays(router: &RaftRouter, real_vote_ms: u64, pre_vote_ms: u64) {
    router
        .set_rpc_post_hook(RPCTypes::Vote, move |_router, req, resp, from, target| {
            let sleep_ms = match (&req, &resp) {
                (RpcRequest::Vote(q), RpcResponse::Vote(r)) if from == 1 && target == 2 => {
                    let t = q.vote.leader_id().term;
                    if t == 2 && r.vote_granted && r.vote == q.vote {
                        real_vote_ms
                    } else if t == 3 {
                        pre_vote_ms
                    } else {
                        0
                    }
                }
                _ => 0,
            };
            Box::pin(async move {
                if sleep_ms > 0 {
                    println!("specular: hook delays vote/pre-vote response {}->{} by {}ms", target, from, sleep_ms);
                    TypeConfig::sleep(Duration::from_millis(sleep_ms)).await;
                }
                Ok::<_, _>(())
            })
        })
        .await;
}

/// Watch node 1 for `secs`, optionally calling `trigger().elect(true)` once it
/// becomes a term-2 Candidate. Returns the (state, term) history.
async fn observe(router: &RaftRouter, secs: u64, admin_pre_vote_on_candidate: bool) -> Result<Vec<(ServerState, u64)>> {
    let n1 = router.get_raft_handle(&1)?;
    let mut history: Vec<(ServerState, u64)> = Vec::new();
    let mut triggered = false;
    let start = TypeConfig::now();
    while TypeConfig::now() - start < Duration::from_secs(secs) {
        let m = n1.metrics().borrow_watched().clone();
        let cur = (m.state, m.current_term);
        if history.last() != Some(&cur) {
            println!(
                "specular: t={:?} node1 state={:?} term={} vote={} leader={:?}",
                TypeConfig::now() - start,
                m.state,
                m.current_term,
                m.vote,
                m.current_leader
            );
            history.push(cur);
        }
        if admin_pre_vote_on_candidate && !triggered && m.state == ServerState::Candidate && m.current_term == 2 {
            println!("specular: node 1 is a term-2 Candidate; trigger().elect(true) (Pre-Vote)");
            n1.trigger().elect(true).await?;
            triggered = true;
        }
        TypeConfig::sleep(Duration::from_millis(2)).await;
    }
    Ok(history)
}

async fn report(router: &RaftRouter, history: &[(ServerState, u64)]) -> Result<bool> {
    let leader_at_2 = history.iter().position(|(s, t)| *s == ServerState::Leader && *t == 2);
    let later_term_3 = leader_at_2.and_then(|p| history[p..].iter().position(|(_, t)| *t >= 3).map(|q| p + q));
    println!("specular: history={:?}", history);
    println!("specular: leader_at_term2_index={:?} later_term3_index={:?}", leader_at_2, later_term_3);
    let m2 = router.get_raft_handle(&2)?.metrics().borrow_watched().clone();
    println!("specular: node2 state={:?} term={} vote={} leader={:?}", m2.state, m2.current_term, m2.vote, m2.current_leader);

    // Consumer-visible effect: a client write reaches the Leader handler.
    let n1 = router.get_raft_handle(&1)?;
    let write = TypeConfig::timeout(Duration::from_secs(3), n1.client_write(ClientRequest::make_request("specular", 1))).await;
    println!("specular: client_write on node 1 after the term bump -> {:?}", write.map(|r| r.map(|x| x.log_id().clone())));
    let m1 = n1.metrics().borrow_watched().clone();
    println!("specular: node1 final state={:?} term={} vote={} running={:?}", m1.state, m1.current_term, m1.vote, m1.running_state);
    Ok(leader_at_2.is_some() && later_term_3.is_some())
}

async fn setup(pre_vote: bool) -> Result<RaftRouter> {
    capture_panics();
    let mut router = RaftRouter::new(config_with(pre_vote)?);
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;
    let n0 = router.get_raft_handle(&0)?;
    n0.wait(Some(Duration::from_secs(3))).state(ServerState::Leader, "node 0 leader").await?;
    // Only node 1 runs timer elections, so the schedule is deterministic.
    n0.runtime_config().elect(false);
    router.get_raft_handle(&2)?.runtime_config().elect(false);
    Ok(router)
}

/// Level 1: public API only.
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specular_mc1_level1_admin_prevote_on_candidate() -> Result<()> {
    let router = setup(true).await?;
    install_delays(&router, 250, 400).await;
    println!("specular: isolate old leader 0");
    router.set_network_error(0, true);
    let history = observe(&router, 5, true).await?;
    let _ = report(&router, &history).await?;
    let became_leader = history.iter().any(|(s, t)| *s == ServerState::Leader && *t == 2);
    let fired = leader_vote_assertion_fired();
    println!("specular: became_leader_term2={} leader_vote_assertion_fired={}", became_leader, fired);
    assert!(became_leader && fired, "BUG NOT TRIGGERED (level 1)");
    println!("SPECULAR-MC1-REPRODUCED level=1: term-2 Leader re-elected itself (vote T3) from a stale Pre-Vote round; RaftCore panicked in try_leader_handler");
    Ok(())
}

/// Level 1 control: identical schedule without the Pre-Vote round.
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specular_mc1_control_level1_no_prevote_round() -> Result<()> {
    let router = setup(true).await?;
    install_delays(&router, 250, 400).await;
    router.set_network_error(0, true);
    let history = observe(&router, 5, false).await?;
    let _ = report(&router, &history).await?;
    let became_leader = history.iter().any(|(s, t)| *s == ServerState::Leader && *t == 2);
    let fired = leader_vote_assertion_fired();
    println!("specular-control: became_leader_term2={} leader_vote_assertion_fired={}", became_leader, fired);
    assert!(became_leader && !fired, "control must elect a stable term-2 leader without the assertion");
    println!("SPECULAR-MC1-CONTROL-OK level=1");
    Ok(())
}

/// Level 3: timer path only (no admin call); slow vote persistence on node 1.
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specular_mc1_level3_timer_path_slow_vote_persistence() -> Result<()> {
    let router = setup(true).await?;
    // Pre-Vote responses for term 3 are delivered after the term-2 vote reply.
    install_delays(&router, 0, 200).await;
    let (_log1, sm1) = router.get_storage_handle(&1)?;
    sm1.block.set_blocking(BlockOperation::SaveVote, Duration::from_millis(900));
    println!("specular: node 1 save_vote takes 900ms (> election timeout 500ms); isolate old leader 0");
    router.set_network_error(0, true);
    let history = observe(&router, 8, false).await?;
    let _ = report(&router, &history).await?;
    let fired = leader_vote_assertion_fired();
    println!("specular: leader_vote_assertion_fired={}", fired);
    assert!(fired, "BUG NOT TRIGGERED (level 3)");
    println!("SPECULAR-MC1-REPRODUCED level=3: timer-driven Pre-Vote on a Candidate re-elected the established term-2 Leader; RaftCore panicked in try_leader_handler");
    Ok(())
}

/// Level 3 control: same slow storage and schedule with Pre-Vote disabled
/// (prior behavior: the timer elects directly and replaces the candidacy).
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specular_mc1_control_level3_prevote_disabled() -> Result<()> {
    let router = setup(false).await?;
    install_delays(&router, 0, 200).await;
    let (_log1, sm1) = router.get_storage_handle(&1)?;
    sm1.block.set_blocking(BlockOperation::SaveVote, Duration::from_millis(900));
    router.set_network_error(0, true);
    let history = observe(&router, 8, false).await?;
    let _ = report(&router, &history).await?;
    let fired = leader_vote_assertion_fired();
    let became_leader = history.iter().any(|(s, _)| *s == ServerState::Leader);
    println!("specular-control: became_leader={} leader_vote_assertion_fired={}", became_leader, fired);
    assert!(!fired, "control (Pre-Vote disabled) must not hit the leader-vote assertion");
    println!("SPECULAR-MC1-CONTROL-OK level=3");
    Ok(())
}
