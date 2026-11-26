//! Specular reproduction (test-only, not part of the artifact tree).
//!
//! A Pre-Vote round started while the node is still a Candidate is not
//! cancelled when that Candidate wins its real election. A granted Pre-Vote
//! response that was computed before the new leader contacted the peer, and
//! delivered after the win, makes the freshly established Leader run
//! `elect()` at the next term.
//!
//! Network delays here only postpone the delivery of a response that the
//! target already produced (`set_vote_resp_delay`), i.e. ordinary message
//! delay/reordering. No message is forged and no node fails after the win.

use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use maplit::btreeset;
use openraft::Config;
use openraft::ServerState;
use openraft::async_runtime::WatchReceiver;
use openraft::type_config::TypeConfigExt;
use openraft_memstore::TypeConfig;

use crate::fixtures::RaftRouter;
use crate::fixtures::ut_harness;

fn config() -> Result<Arc<Config>> {
    Ok(Arc::new(
        Config {
            // Elections and heartbeats are driven explicitly so the schedule is
            // deterministic; the vote RPC timeout is `election_timeout_min`.
            enable_elect: false,
            enable_heartbeat: false,
            election_timeout_min: 2000,
            election_timeout_max: 2001,
            ..Default::default()
        }
        .validate()?,
    ))
}

/// Shared schedule. Returns (term at which node 1 became leader, whether the
/// cautious re-election trigger was issued).
async fn run(cautious_trigger: bool) -> Result<(RaftRouter, u64)> {
    let mut router = RaftRouter::new(config()?);
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;

    let n0 = router.get_raft_handle(&0)?;
    n0.wait(Some(Duration::from_secs(5))).state(ServerState::Leader, "node 0 is leader").await?;

    tracing::info!("--- the old leader becomes unreachable; wait until its leases expire");
    router.set_network_error(0, true);
    TypeConfig::sleep(Duration::from_millis(2600)).await;

    let n1 = router.get_raft_handle(&1)?;
    let t = n1.metrics().borrow_watched().current_term;

    // Node 2's real-vote reply reaches node 1 after 300ms; node 2's Pre-Vote
    // reply after 1200ms. Both are below the 2000ms RPC timeout.
    router.set_vote_resp_delay(false, t + 1, 2, 300);
    router.set_vote_resp_delay(true, t + 2, 2, 1200);

    tracing::info!("--- node 1 starts a real election at term {}", t + 1);
    n1.trigger().elect(false).await?;
    TypeConfig::sleep(Duration::from_millis(50)).await;
    assert_eq!(ServerState::Candidate, n1.metrics().borrow_watched().state);

    if cautious_trigger {
        tracing::info!("--- still Candidate: a cautious election (Pre-Vote) is triggered");
        n1.trigger().elect(true).await?;
    }

    n1.wait(Some(Duration::from_millis(1000)))
        .metrics(
            |m| m.state == ServerState::Leader && m.current_term == t + 1,
            "node 1 becomes leader at term t+1",
        )
        .await?;
    let n2 = router.get_raft_handle(&2)?;
    n2.wait(Some(Duration::from_millis(1000)))
        .metrics(|m| m.current_leader == Some(1), "node 2 follows the new leader")
        .await?;
    tracing::info!("--- node 1 is the established leader at term {}", t + 1);
    Ok((router, t + 1))
}

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specular_repro_stale_pre_vote_displaces_new_leader() -> Result<()> {
    let (router, leader_term) = run(true).await?;
    let n1 = router.get_raft_handle(&1)?;
    let n2 = router.get_raft_handle(&2)?;

    // Nothing fails from here on. Wait for the delayed Pre-Vote grant.
    TypeConfig::sleep(Duration::from_millis(1500)).await;
    let m1 = n1.metrics().borrow_watched().clone();
    let m2 = n2.metrics().borrow_watched().clone();
    // A dead RaftCore no longer accepts external commands.
    let core_alive = n1.trigger().heartbeat().await.is_ok();
    println!(
        "SPECULAR-REPRO: leader_term={} core_alive={} n1.state={:?} n1.term={} n1.vote={} n2.state={:?} n2.term={} n2.current_leader={:?}",
        leader_term, core_alive, m1.state, m1.current_term, m1.vote, m2.state, m2.current_term, m2.current_leader
    );

    // Outcome A (debug build): the stale Leader object trips
    //   debug_assert!(leader.vote >= state.vote) in Engine::try_leader_handler
    // on the next routine action and RaftCore terminates.
    // Outcome B (no debug assertions): the leader has moved to term t+1 as a
    // Candidate, i.e. it abandoned the leadership it had just won.
    let displaced = !core_alive || (m1.current_term == leader_term + 1 && m1.state != ServerState::Leader);
    assert!(
        displaced,
        "expected the stale Pre-Vote round to displace the established leader"
    );

    TypeConfig::sleep(Duration::from_millis(500)).await;
    let m1 = n1.metrics().borrow_watched().clone();
    println!(
        "SPECULAR-REPRO: +500ms core_alive={} n1.state={:?} n1.term={} n1.vote={} n2.current_leader={:?} n2.vote={}",
        n1.trigger().heartbeat().await.is_ok(),
        m1.state,
        m1.current_term,
        m1.vote,
        n2.metrics().borrow_watched().current_leader,
        n2.metrics().borrow_watched().vote
    );
    Ok(())
}

/// Control on the same revision: identical schedule without the cautious
/// trigger; the leader keeps its term and leadership.
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specular_repro_control_without_pre_vote_round() -> Result<()> {
    let (router, leader_term) = run(false).await?;
    let n1 = router.get_raft_handle(&1)?;
    TypeConfig::sleep(Duration::from_millis(2000)).await;
    let m1 = n1.metrics().borrow_watched().clone();
    println!(
        "SPECULAR-REPRO-CONTROL: leader_term={} n1.state={:?} n1.term={}",
        leader_term, m1.state, m1.current_term
    );
    assert_eq!(ServerState::Leader, m1.state);
    assert_eq!(leader_term, m1.current_term);
    Ok(())
}
