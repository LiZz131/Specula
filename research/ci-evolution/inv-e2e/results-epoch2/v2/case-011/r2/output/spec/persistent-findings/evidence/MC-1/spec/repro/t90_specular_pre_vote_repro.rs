//! Specular reproduction tests for the Pre-Vote update (incremental run incr-4e410cd184be).
//!
//! Each test drives a real 3-node cluster through the public `Raft` API and the
//! test router's RPC hooks (timing assistance only), then asserts the CORRECT
//! behaviour.  On the analysed revision each test FAILS with a message starting
//! with `BUG REPRODUCED`; on a corrected implementation it is expected to pass.
//!
//! - MC-1: a Pre-Vote round started by the election timer while the node is a
//!   real Candidate survives `establish_leader`; when its quorum arrives the new
//!   Leader starts a fresh election at term+1 (self-preemption, term inflation).
//! - MC-2: a Pre-Vote round outlives a membership change that removes its node
//!   from the voters; the completed round calls `elect()` for a non-voter, and the
//!   node's own vote grant hits `Candidate::grant_by`'s `expect` (RaftCore panic).
//! - MC-3: a second Pre-Vote round at the same hypothetical vote over a smaller
//!   membership accepts a delayed grant from a node removed in between; the
//!   grant hits `Candidate::grant_by`'s `expect` (RaftCore panic).

use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::AtomicU64;
use std::sync::atomic::Ordering;
use std::time::Duration;

use anyhow::Result;
use maplit::btreeset;
use openraft::Config;
use openraft::RPCTypes;
use openraft::ServerState;
use openraft::async_runtime::WatchReceiver;
use openraft::base::BoxFuture;
use openraft::errors::RPCError;
use openraft::errors::Unreachable;
use openraft::type_config::TypeConfigExt;
use openraft::vote::RaftLeaderId;
use openraft_memstore::BlockOperation;
use openraft_memstore::TypeConfig;

use crate::fixtures::RaftRouter;
use crate::fixtures::rpc_request::RpcRequest;
use crate::fixtures::rpc_response::RpcResponse;
use crate::fixtures::ut_harness;

fn sleep_box(ms: u64) -> BoxFuture<'static, ()> {
    Box::pin(async move {
        if ms > 0 {
            TypeConfig::sleep(Duration::from_millis(ms)).await;
        }
    })
}

/// Ask RaftCore itself (not the possibly stale metrics) for its vote and server
/// state. `Err` means RaftCore is no longer running (e.g. it panicked).
async fn core_view(raft: &crate::fixtures::MemRaft) -> Result<(String, ServerState), String> {
    raft.with_raft_state(|st| (st.vote_ref().to_string(), st.server_state))
        .await
        .map_err(|e| format!("{}", e))
}

fn vote_term(req: &RpcRequest<TypeConfig>) -> Option<u64> {
    match req {
        RpcRequest::Vote(v) => Some(v.vote.leader_id().term()),
        _ => None,
    }
}

/// MC-1: timer-started Pre-Vote round survives leader establishment.
///
/// Timing assistance (Level 1): node 1's `save_vote` takes 450 ms (slow disk),
/// node 1's real vote request to node 2 is delayed 100 ms, and node 2's answer to
/// node 1's term+2 Pre-Vote is delayed 250 ms. All delays are below the vote RPC
/// timeout (`election_timeout_min` = 400 ms). Nodes 0 and 2 have elections
/// disabled; node 0 (the old leader) is isolated so node 1's timer fires.
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specular_mc1_timer_pre_vote_round_preempts_new_leader() -> Result<()> {
    let config = Arc::new(
        Config {
            enable_pre_vote: Some(true),
            heartbeat_interval: 100,
            election_timeout_min: 400,
            election_timeout_max: 401,
            ..Default::default()
        }
        .validate()?,
    );

    let mut router = RaftRouter::new(config.clone());
    router.network_send_delay(0);
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;

    let n0 = router.get_raft_handle(&0)?;
    let n1 = router.get_raft_handle(&1)?;
    let n2 = router.get_raft_handle(&2)?;
    n0.wait(timeout()).state(ServerState::Leader, "node 0 is leader").await?;
    n1.wait(timeout()).state(ServerState::Follower, "node 1 is follower").await?;

    let t0 = n1.metrics().borrow_watched().current_term;
    tracing::info!(t0, "--- only node 1 may run timer elections");
    n0.runtime_config().elect(false);
    n2.runtime_config().elect(false);

    let (_log1, sm1) = router.get_storage_handle(&1)?;
    sm1.block.set_blocking(BlockOperation::SaveVote, Duration::from_millis(450));

    let real_term = t0 + 1;
    let stale_term = t0 + 2;
    let t_real_seen = Arc::new(AtomicU64::new(0));
    let stale_pre_votes_sent = Arc::new(AtomicU64::new(0));
    let events = Arc::new(Mutex::new(Vec::<String>::new()));
    {
        let t_real_seen = t_real_seen.clone();
        let stale_pre_votes_sent = stale_pre_votes_sent.clone();
        let events = events.clone();
        router
            .set_rpc_pre_hook(RPCTypes::Vote, move |_r, req, from, to| {
                let mut delay = 0;
                if let Some(term) = vote_term(&req) {
                    if from == 1 && to == 2 {
                        if term == real_term {
                            // 1st term t0+1 request is the Pre-Vote, 2nd is the real vote.
                            let n = t_real_seen.fetch_add(1, Ordering::SeqCst);
                            if n == 1 {
                                delay = 100;
                            }
                            events.lock().unwrap().push(format!("1->2 vote-rpc term={} #{} delay={}", term, n, delay));
                        } else if term == stale_term {
                            stale_pre_votes_sent.fetch_add(1, Ordering::SeqCst);
                            events.lock().unwrap().push(format!("1->2 vote-rpc term={} (timer pre-vote)", term));
                        }
                    }
                }
                let fu = sleep_box(delay);
                Box::pin(async move {
                    fu.await;
                    Ok::<(), RPCError<TypeConfig, openraft::errors::Infallible>>(())
                })
            })
            .await;
    }
    {
        let events = events.clone();
        router
            .set_rpc_post_hook(RPCTypes::Vote, move |_r, req, resp, from, to| {
                let mut delay = 0;
                if let (Some(term), RpcResponse::Vote(r)) = (vote_term(&req), &resp) {
                    if from == 1 && to == 2 && term == stale_term {
                        delay = 250;
                        events.lock().unwrap().push(format!("2->1 pre-vote resp term={} granted={} delayed", term, r.vote_granted));
                    }
                }
                let fu = sleep_box(delay);
                Box::pin(async move {
                    fu.await;
                    Ok(())
                })
            })
            .await;
    }

    tracing::info!("--- isolate leader 0; node 1's timer drives Pre-Vote and election");
    router.set_network_error(0, true);

    n1.wait(Some(Duration::from_secs(10)))
        .metrics(|m| m.current_term >= real_term && m.state == ServerState::Leader, "node 1 becomes leader")
        .await
        .ok();

    // Let any delayed Pre-Vote response arrive and be processed (RPC ttl 400 ms,
    // node 1 storage latency 450 ms), then observe a stable outcome.
    TypeConfig::sleep(Duration::from_millis(2500)).await;

    let m = n1.metrics().borrow_watched().clone();
    let ev = events.lock().unwrap().clone();
    tracing::info!(?ev, term = m.current_term, state = ?m.state, "--- outcome");
    println!("EVENTS: {:?}", ev);
    println!(
        "OUTCOME: node1 term={} state={:?} leader={:?} stale_pre_votes_sent={}",
        m.current_term,
        m.state,
        m.current_leader,
        stale_pre_votes_sent.load(Ordering::SeqCst)
    );

    assert!(
        stale_pre_votes_sent.load(Ordering::SeqCst) >= 1,
        "precondition not reached: node 1's timer did not start a Pre-Vote round while Candidate"
    );
    let core = core_view(&n1).await;
    println!("CORE: node1 {:?}", core);
    let leader_won = ev.iter().any(|e| e.contains("pre-vote resp")) && t_real_seen.load(Ordering::SeqCst) >= 2;
    let ok = matches!(&core, Ok((_, ServerState::Leader))) && m.current_term == real_term;
    assert!(
        ok,
        "BUG REPRODUCED (MC-1): node 1 won the term-{} election (real vote delivered: {}), but a Pre-Vote round its \
         election timer started while it was still a Candidate completed afterwards and started a new election \
         from the established leader; RaftCore view: {:?}; metrics term={} state={:?}",
        real_term,
        leader_won,
        core,
        m.current_term,
        m.state
    );
    Ok(())
}

/// Common setup for MC-2/MC-3: node 0 leads, elections are disabled everywhere,
/// heartbeats from node 0 are disabled so that the followers' leader leases
/// expire (a Pre-Vote is then grantable), with an RPC timeout of 1000 ms.
async fn leader_with_expired_follower_leases() -> Result<RaftRouter> {
    let config = Arc::new(
        Config {
            heartbeat_interval: 100,
            election_timeout_min: 1000,
            election_timeout_max: 1001,
            ..Default::default()
        }
        .validate()?,
    );
    let mut router = RaftRouter::new(config.clone());
    router.network_send_delay(0);
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;
    let n0 = router.get_raft_handle(&0)?;
    n0.wait(timeout()).state(ServerState::Leader, "node 0 is leader").await?;
    for id in [0, 1, 2] {
        router.get_raft_handle(&id)?.runtime_config().elect(false);
    }
    n0.runtime_config().heartbeat(false);
    tracing::info!("--- wait for follower leases (election_timeout_max) to expire");
    TypeConfig::sleep(Duration::from_millis(1300)).await;
    Ok(router)
}

/// MC-2: Pre-Vote round outlives the node's removal from the voters; the round's
/// quorum makes a non-voter elect, and its own grant panics RaftCore.
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specular_mc2_pre_vote_round_elects_removed_voter() -> Result<()> {
    let router = leader_with_expired_follower_leases().await?;
    let n0 = router.get_raft_handle(&0)?;
    let t0 = n0.metrics().borrow_watched().current_term;

    // Delay the granted Pre-Vote answers to node 0 so they arrive after node 0
    // has removed itself from the voters (below the 1000 ms RPC timeout).
    router
        .set_rpc_post_hook(RPCTypes::Vote, move |_r, req, _resp, from, _to| {
            let delay = if from == 0 && vote_term(&req) == Some(t0 + 1) { 300 } else { 0 };
            let fu = sleep_box(delay);
            Box::pin(async move {
                fu.await;
                Ok(())
            })
        })
        .await;

    tracing::info!("--- node 0 (leader) triggers a cautious election: trigger().elect(true)");
    n0.trigger().elect(true).await?;

    tracing::info!("--- node 0 removes itself from the voters (kept as learner)");
    n0.change_membership(btreeset! {1, 2}, true).await?;

    TypeConfig::sleep(Duration::from_millis(1500)).await;
    let m = n0.metrics().borrow_watched().clone();
    println!(
        "OUTCOME: node0 term={} state={:?} running_state={:?} voters={:?}",
        m.current_term,
        m.state,
        m.running_state,
        m.membership_config.membership().voter_ids().collect::<Vec<_>>()
    );
    let core = core_view(&n0).await;
    println!("CORE: node0 {:?}", core);
    assert!(
        core.is_ok(),
        "BUG REPRODUCED (MC-2): node 0's Pre-Vote round completed after it left the voters; elect() ran for a \
         non-voter and RaftCore stopped: {:?}",
        core
    );
    Ok(())
}

/// MC-3: a second Pre-Vote round at the same hypothetical vote, over a smaller
/// membership, accepts a delayed grant from a removed node and panics RaftCore.
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specular_mc3_repeated_pre_vote_round_accepts_removed_node_grant() -> Result<()> {
    let router = leader_with_expired_follower_leases().await?;
    let n0 = router.get_raft_handle(&0)?;
    let t0 = n0.metrics().borrow_watched().current_term;

    // Node 2 never answers node 0's Pre-Votes; node 1's first answer is delayed.
    let n1_answers = Arc::new(AtomicU64::new(0));
    router
        .set_rpc_pre_hook(RPCTypes::Vote, move |_r, req, from, to| {
            let block = from == 0 && to == 2 && vote_term(&req) == Some(t0 + 1);
            Box::pin(async move {
                if block {
                    return Err(RPCError::Unreachable(Unreachable::from_string("specular: block pre-vote 0->2")));
                }
                Ok(())
            })
        })
        .await;
    {
        let n1_answers = n1_answers.clone();
        router
            .set_rpc_post_hook(RPCTypes::Vote, move |_r, req, _resp, from, to| {
                let mut delay = 0;
                if from == 0 && to == 1 && vote_term(&req) == Some(t0 + 1) {
                    if n1_answers.fetch_add(1, Ordering::SeqCst) == 0 {
                        delay = 400;
                    }
                }
                let fu = sleep_box(delay);
                Box::pin(async move {
                    fu.await;
                    Ok(())
                })
            })
            .await;
    }

    tracing::info!("--- round A: node 0 probes (term+1) over {{0,1,2}}");
    n0.trigger().elect(true).await?;

    tracing::info!("--- node 0 removes node 1 from the voters (kept as learner)");
    n0.change_membership(btreeset! {0, 2}, true).await?;

    tracing::info!("--- round B: node 0 probes the SAME (term+1) over {{0,2}}");
    n0.trigger().elect(true).await?;

    TypeConfig::sleep(Duration::from_millis(1500)).await;
    let m = n0.metrics().borrow_watched().clone();
    println!(
        "OUTCOME: node0 term={} state={:?} running_state={:?} voters={:?} n1_answers={}",
        m.current_term,
        m.state,
        m.running_state,
        m.membership_config.membership().voter_ids().collect::<Vec<_>>(),
        n1_answers.load(Ordering::SeqCst)
    );
    let core = core_view(&n0).await;
    println!("CORE: node0 {:?}", core);
    assert!(
        core.is_ok(),
        "BUG REPRODUCED (MC-3): a delayed Pre-Vote grant from removed node 1 (round A) was counted by round B \
         (same leader id, membership without node 1) and RaftCore stopped: {:?}",
        core
    );
    Ok(())
}

fn timeout() -> Option<Duration> {
    Some(Duration::from_millis(3000))
}

/// MC-1 escalation Level 0: pure black-box. Pre-Vote enabled, no hooks, no
/// storage latency; repeatedly isolate the current leader and let the others
/// elect. Reports whether any node's RaftCore died or a leader was preempted
/// by a stale round (term jump without isolation). A pass here does not refute
/// MC-1: the window needs vote persistence slower than
/// `election_timeout - election_timeout_min`.
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specular_mc1_level0_black_box_attempt() -> Result<()> {
    let config = Arc::new(
        Config {
            enable_pre_vote: Some(true),
            heartbeat_interval: 50,
            election_timeout_min: 150,
            election_timeout_max: 151,
            ..Default::default()
        }
        .validate()?,
    );
    let mut router = RaftRouter::new(config.clone());
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;
    let mut dead = vec![];
    for round in 0..8 {
        let Some(leader) = router.leader() else {
            TypeConfig::sleep(Duration::from_millis(500)).await;
            continue;
        };
        router.set_network_error(leader, true);
        TypeConfig::sleep(Duration::from_millis(1200)).await;
        router.set_network_error(leader, false);
        TypeConfig::sleep(Duration::from_millis(600)).await;
        for id in [0, 1, 2] {
            let r = router.get_raft_handle(&id)?;
            if let Err(e) = core_view(&r).await {
                dead.push(format!("round {} node {}: {}", round, id, e));
            }
        }
        println!("LEVEL0 round {} isolated leader {} -> leader now {:?}", round, leader, router.leader());
    }
    println!("LEVEL0 dead cores: {:?}", dead);
    assert!(dead.is_empty(), "BUG REPRODUCED (MC-1, level 0): RaftCore died: {:?}", dead);
    Ok(())
}
