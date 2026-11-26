//! Specular reproduction (test-only, not part of the artifact tree).
//!
//! Two Pre-Vote rounds started from the same local vote share the runtime
//! correlation key (the pre-candidate leader id). If the voter set changes
//! between them, a delayed grant for the first round from a node that is not
//! a voter of the second round passes `does_pre_candidate_vote_match` and
//! reaches `Candidate::grant_by`, whose `expect("target not in quorum set")`
//! panics the RaftCore task.
//!
//! Network delays only postpone delivery of replies the target already
//! produced (`set_vote_resp_delay`). Membership change and elections use the
//! public `Raft` API.

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

/// `prober`: the node that runs both Pre-Vote rounds (0 = the leader, 1 = a follower).
async fn run(prober: u64, change_membership: bool) -> Result<bool> {
    let config = Arc::new(
        Config {
            enable_elect: false,
            enable_heartbeat: false,
            election_timeout_min: 2000,
            election_timeout_max: 2001,
            ..Default::default()
        }
        .validate()?,
    );
    let mut router = RaftRouter::new(config);
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;
    let n0 = router.get_raft_handle(&0)?;
    n0.wait(Some(Duration::from_secs(5))).state(ServerState::Leader, "node 0 is leader").await?;

    tracing::info!("--- no heartbeats: wait until the followers' leader leases expire");
    TypeConfig::sleep(Duration::from_millis(2600)).await;
    let np = router.get_raft_handle(&prober)?;
    let t = np.metrics().borrow_watched().current_term;
    let other = if prober == 0 { 1 } else { 0 };

    // Round-1 grant from node 2 is delivered after 1500ms (< 2000ms RPC timeout);
    // the other peer's Pre-Vote replies are delayed past the RPC timeout (dropped),
    // so no round reaches a quorum by itself.
    router.set_vote_resp_delay(true, t + 1, 2, 1500);
    router.set_vote_resp_delay(true, t + 1, other, 5000);

    tracing::info!("--- round 1 on node {}: cautious election (pre-vote term {})", prober, t + 1);
    np.trigger().elect(true).await?;
    TypeConfig::sleep(Duration::from_millis(100)).await;

    if change_membership {
        tracing::info!("--- the leader removes node 2 from the cluster");
        n0.change_membership(btreeset! {0,1}, false).await?;
        np.wait(Some(Duration::from_millis(1000)))
            .metrics(
                |m| m.membership_config.membership().voter_ids().collect::<Vec<_>>() == vec![0, 1],
                "prober sees the new voter set",
            )
            .await?;
    }

    tracing::info!("--- round 2 on node {}: cautious election again, same local vote", prober);
    np.trigger().elect(true).await?;

    TypeConfig::sleep(Duration::from_millis(2000)).await;
    let alive = np.trigger().heartbeat().await.is_ok();
    let m = np.metrics().borrow_watched().clone();
    println!(
        "SPECULAR-REPRO-CR2: prober={} change_membership={} core_alive={} state={:?} term={} voters={:?}",
        prober,
        change_membership,
        alive,
        m.state,
        m.current_term,
        m.membership_config.membership().voter_ids().collect::<Vec<_>>()
    );
    Ok(alive)
}

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specular_repro_stale_pre_vote_grant_follower_panics() -> Result<()> {
    let alive = run(1, true).await?;
    assert!(!alive, "expected RaftCore to terminate on the stale grant from the removed node");
    Ok(())
}

/// Control: same follower schedule without the membership change; the delayed
/// grant comes from a voter of the second round and is simply counted.
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specular_repro_control_follower_same_membership_no_panic() -> Result<()> {
    let alive = run(1, false).await?;
    assert!(alive, "the node must survive when the granter is a voter of the round");
    Ok(())
}

/// Variant: the leader runs both rounds (Trigger::elect(true) on a leader).
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specular_repro_stale_pre_vote_grant_leader_panics() -> Result<()> {
    let alive = run(0, true).await?;
    assert!(!alive, "expected RaftCore to terminate on the stale grant from the removed node");
    Ok(())
}
