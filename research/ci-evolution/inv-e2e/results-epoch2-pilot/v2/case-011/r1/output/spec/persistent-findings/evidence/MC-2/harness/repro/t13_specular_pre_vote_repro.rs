//! Specular reproduction tests for the Pre-Vote update (run `incr-705b7bab5f0d`).
//!
//! Both tests drive real `Raft` nodes through the public API and the test
//! router's RPC hooks (no engine internals are touched).
//!
//! - `repro_mc1_stale_pre_vote_grant_panics_core`: a granted response to an
//!   earlier Pre-Vote round of the same node at the same term is forwarded to a
//!   later round (RaftCore correlates by leader id only); the responder is no
//!   longer a voter, so `Candidate::grant_by` panics and the leader's RaftCore
//!   stops.
//! - `repro_mc2_pre_vote_round_survives_leader_establishment`: a Pre-Vote round
//!   started while the node is still a Candidate survives `establish_leader`;
//!   its quorum makes the freshly established Leader run another election.

use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::AtomicBool;
use std::sync::atomic::Ordering;
use std::time::Duration;

use anyhow::Result;
use maplit::btreeset;
use openraft::Config;
use openraft::RPCTypes;
use openraft::ServerState;
use openraft::async_runtime::WatchReceiver;
use openraft::base::BoxFuture;
use openraft::errors::NetworkError;
use openraft::errors::RPCError;
use openraft::type_config::TypeConfigExt;
use openraft_memstore::TypeConfig;

use crate::fixtures::RaftRouter;
use crate::fixtures::rpc_request::RpcRequest;
use crate::fixtures::rpc_response::RpcResponse;
use crate::fixtures::ut_harness;

/// A one-shot gate: futures wait until `open()` (or until `max` elapses).
#[derive(Clone)]
struct Gate {
    open: Arc<AtomicBool>,
}

impl Gate {
    fn new() -> Self {
        Self {
            open: Arc::new(AtomicBool::new(false)),
        }
    }
    fn open(&self) {
        self.open.store(true, Ordering::SeqCst);
    }
    async fn wait(&self, max: Duration) {
        let start = TypeConfig::now();
        while !self.open.load(Ordering::SeqCst) && TypeConfig::now() - start < max {
            TypeConfig::sleep(Duration::from_millis(5)).await;
        }
    }
}

fn slow_election_config(pre_vote: bool) -> Arc<Config> {
    Arc::new(
        Config {
            election_timeout_min: 3000,
            election_timeout_max: 3001,
            heartbeat_interval: 100,
            enable_pre_vote: Some(pre_vote),
            ..Default::default()
        }
        .validate()
        .unwrap(),
    )
}

/// MC-1 consequence: stale Pre-Vote grant from a removed voter panics RaftCore.
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn repro_mc1_stale_pre_vote_grant_panics_core() -> Result<()> {
    let config = slow_election_config(false);
    let mut router = RaftRouter::new(config.clone());
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;

    let n0 = router.get_raft_handle(&0)?;
    let n1 = router.get_raft_handle(&1)?;
    let n2 = router.get_raft_handle(&2)?;
    n0.wait(Some(Duration::from_secs(5))).state(ServerState::Leader, "n0 leader").await?;
    // Only the operator triggers elections in this scenario.
    n1.runtime_config().elect(false);
    n2.runtime_config().elect(false);
    let term = n0.metrics().borrow_watched().current_term;
    tracing::info!("--- n0 is leader at term {}", term);

    // n0 stops reaching n2 with AppendEntries, so n2's leader lease
    // (election_timeout_max) expires; n2 is still a voter.
    router
        .set_rpc_pre_hook(RPCTypes::AppendEntries, |_r, _req, _from, to| {
            let res = if to == 2 {
                Err(RPCError::Network(NetworkError::<TypeConfig>::from_string("block n0->n2")))
            } else {
                Ok(())
            };
            let x: BoxFuture<_> = Box::pin(futures::future::ready(res));
            x
        })
        .await;
    TypeConfig::sleep(Duration::from_millis(3300)).await;

    // Hold the first granted Pre-Vote response from n2 until `release` opens.
    let armed = Arc::new(AtomicBool::new(false));
    let held = Arc::new(AtomicBool::new(false));
    let release = Gate::new();
    {
        let armed = armed.clone();
        let held = held.clone();
        let release = release.clone();
        router
            .set_rpc_post_hook(RPCTypes::Vote, move |_r, req, resp, _from, to| {
                let hold = match (&req, &resp) {
                    (RpcRequest::Vote(q), RpcResponse::Vote(p)) => {
                        to == 2 && p.vote_granted && q.vote.leader_id().term == term + 1 && armed.swap(false, Ordering::SeqCst)
                    }
                    _ => false,
                };
                if hold {
                    held.store(true, Ordering::SeqCst);
                }
                let release = release.clone();
                let x: BoxFuture<_> = Box::pin(async move {
                    if hold {
                        release.wait(Duration::from_millis(2500)).await;
                    }
                    Ok(())
                });
                x
            })
            .await;
    }

    tracing::info!("--- round A: operator-triggered Pre-Vote on n0 over {{0,1,2}}");
    armed.store(true, Ordering::SeqCst);
    n0.trigger().elect(true).await?;
    TypeConfig::sleep(Duration::from_millis(200)).await;
    assert!(held.load(Ordering::SeqCst), "n2 granted round A and its response is held");

    tracing::info!("--- n0 removes n2 (joint then uniform {{0,1}})");
    n0.change_membership(btreeset! {0,1}, false).await?;
    let cur = n0.metrics().borrow_watched().membership_config.clone();
    tracing::info!("--- membership now: {:?}", cur);
    assert_eq!(term, n0.metrics().borrow_watched().current_term, "n0's term unchanged");

    tracing::info!("--- round B: same leader id (term+1, 0), quorum set {{0,1}}");
    n0.trigger().elect(true).await?;
    TypeConfig::sleep(Duration::from_millis(200)).await;

    tracing::info!("--- release the delayed round-A grant from n2");
    release.open();
    TypeConfig::sleep(Duration::from_millis(500)).await;

    let res = n0.with_raft_state(|_st| ()).await;
    tracing::info!("--- n0 core after delayed grant: {:?}", res.as_ref().map(|_| ()));
    println!("SPECULAR-REPRO MC-1: n0.with_raft_state() after stale grant => {:?}", res.as_ref().map(|_| ()));
    // Correct behavior: a response to an earlier round is ignored and n0 keeps
    // running. The test FAILS when the defect is triggered (Err(Panicked)).
    assert!(res.is_ok(), "n0 RaftCore must still be running; got {:?}", res.map(|_| ()));
    Ok(())
}

/// MC-2: Pre-Vote round started as Candidate survives leader establishment.
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn repro_mc2_pre_vote_round_survives_leader_establishment() -> Result<()> {
    let config = slow_election_config(true);
    let mut router = RaftRouter::new(config.clone());
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;

    let n0 = router.get_raft_handle(&0)?;
    let n1 = router.get_raft_handle(&1)?;
    let n2 = router.get_raft_handle(&2)?;
    n0.wait(Some(Duration::from_secs(5))).state(ServerState::Leader, "n0 leader").await?;
    n1.runtime_config().elect(false);
    n2.runtime_config().elect(false);
    let t0 = n0.metrics().borrow_watched().current_term;

    tracing::info!("--- isolate the old leader n0 and let leases expire");
    router.set_network_error(0, true);
    TypeConfig::sleep(Duration::from_millis(3300)).await;

    // Hold n2's granted responses to n1: the real vote (term t0+1) and the
    // Pre-Vote (term t0+2), released in a chosen order.
    let vote_gate = Gate::new();
    let pre_gate = Gate::new();
    let seen: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(vec![]));
    {
        let (vote_gate, pre_gate, seen) = (vote_gate.clone(), pre_gate.clone(), seen.clone());
        router
            .set_rpc_post_hook(RPCTypes::Vote, move |_r, req, resp, from, to| {
                let gate = match (&req, &resp) {
                    (RpcRequest::Vote(q), RpcResponse::Vote(p)) if from == 1 && to == 2 && p.vote_granted => {
                        seen.lock().unwrap().push(format!("{} granted={}", q.vote, p.vote_granted));
                        if q.vote.leader_id().term == t0 + 1 {
                            Some(vote_gate.clone())
                        } else if q.vote.leader_id().term == t0 + 2 {
                            Some(pre_gate.clone())
                        } else {
                            None
                        }
                    }
                    _ => None,
                };
                let x: BoxFuture<_> = Box::pin(async move {
                    if let Some(g) = gate {
                        g.wait(Duration::from_millis(2800)).await;
                    }
                    Ok(())
                });
                x
            })
            .await;
    }

    tracing::info!("--- n1 starts a real election (term t0+1); n2's grant is held");
    n1.trigger().elect(false).await?;
    n1.wait(Some(Duration::from_secs(2)))
        .metrics(|m| m.current_term == t0 + 1 && m.state == ServerState::Candidate, "n1 candidate")
        .await?;

    tracing::info!("--- while still Candidate, n1 starts a Pre-Vote round (term t0+2)");
    n1.trigger().elect(true).await?;
    TypeConfig::sleep(Duration::from_millis(300)).await;

    tracing::info!("--- release the real vote: n1 establishes leadership at t0+1");
    vote_gate.open();
    n1.wait(Some(Duration::from_secs(2)))
        .metrics(|m| m.state == ServerState::Leader && m.current_term == t0 + 1, "n1 leader")
        .await?;
    let led = n1.metrics().borrow_watched().clone();
    println!("SPECULAR-REPRO MC-2: n1 established: state={:?} term={} vote={}", led.state, led.current_term, led.vote);
    TypeConfig::sleep(Duration::from_millis(300)).await;

    tracing::info!("--- release the Pre-Vote grant of the earlier round");
    pre_gate.open();
    TypeConfig::sleep(Duration::from_millis(500)).await;

    let alive = n1.with_raft_state(|_st| ()).await;
    println!("SPECULAR-REPRO MC-2: n1.with_raft_state() after pre-vote grant => {:?}", alive.as_ref().map(|_| ()));
    let m = n1.metrics().borrow_watched().clone();
    println!(
        "SPECULAR-REPRO MC-2: after pre-vote grant: state={:?} term={} vote={} seen={:?}",
        m.state,
        m.current_term,
        m.vote,
        seen.lock().unwrap()
    );
    // Correct behavior: the established leader keeps leading at t0+1 and its
    // RaftCore keeps running. The test FAILS when the defect is triggered.
    assert!(alive.is_ok(), "n1 RaftCore must keep running; got {:?}", alive.map(|_| ()));
    assert_eq!(ServerState::Leader, m.state, "the established leader must keep leading");
    assert_eq!(t0 + 1, m.current_term, "the established leader must not inflate its term");
    Ok(())
}
