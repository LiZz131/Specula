//! Specula update-focused scenarios for `Raft::transfer_leader` (harness-owned).
//!
//! These drive the real public API on a real in-memory cluster. They record observations
//! (`SPECULA_OBS_FILE`, one JSON object per line) instead of asserting a protocol outcome, so
//! the same scenario serves as trace producer and as code observation for the divergence
//! evidence. RaftCore traces are written by `openraft/src/core/specula_core_trace.rs` when
//! `SPECULA_CORE_TRACE_DIR` is set.

use std::io::Write;
use std::sync::Arc;
use std::time::Duration;

use maplit::btreeset;
use openraft::Config;
use openraft::ServerState;
use openraft_memstore::ClientRequest;
use openraft_memstore::IntoMemClientRequest;

use crate::fixtures::ut_harness;
use crate::fixtures::MemRaft;
use crate::fixtures::RaftRouter;

fn observe(label: &str, line: String) {
    println!("SPECULA_OBS {} {}", label, line);
    if let Ok(path) = std::env::var("SPECULA_OBS_FILE") {
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
            let _ = writeln!(f, "{{\"label\":\"{}\",{}}}", label, line);
        }
    }
}

fn metrics_json(id: u64, n: &MemRaft) -> String {
    let m = n.metrics().borrow().clone();
    format!(
        "\"node\":{},\"state\":\"{:?}\",\"current_leader\":\"{:?}\",\"vote\":\"{}\",\"last_log_index\":\"{:?}\",\"voters\":\"{:?}\"",
        id,
        m.state,
        m.current_leader,
        m.vote,
        m.last_log_index,
        m.membership_config.membership().voter_ids().collect::<Vec<_>>()
    )
}

fn config() -> anyhow::Result<Arc<Config>> {
    Ok(Arc::new(
        Config {
            election_timeout_min: 150,
            election_timeout_max: 300,
            ..Default::default()
        }
        .validate()?,
    ))
}

/// U2: the `to` node is a learner. `transfer_leader` is called on every node, as the API
/// documentation instructs (`raft/mod.rs:641-642`).
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specula_transfer_to_learner() -> anyhow::Result<()> {
    let mut router = RaftRouter::new(config()?);
    let _log_index = router.new_cluster(btreeset! {0,1,2}, btreeset! {3}).await?;

    let n: Vec<MemRaft> = (0..4).map(|i| router.get_raft_handle(&i)).collect::<Result<_, _>>()?;
    for (i, h) in n.iter().enumerate() {
        observe("before", metrics_json(i as u64, h));
    }

    let m0 = n[0].metrics().borrow().clone();
    let leader_vote = m0.vote;
    let last_log_id = m0.last_applied;

    // Non-target nodes first (lease reset), then the target (waits for its log).
    n[0].transfer_leader(leader_vote, 3, last_log_id).await?;
    n[1].transfer_leader(leader_vote, 3, last_log_id).await?;
    n[2].transfer_leader(leader_vote, 3, last_log_id).await?;
    n[3].transfer_leader(leader_vote, 3, last_log_id).await?;

    let res = n[3]
        .wait(Some(Duration::from_millis(2_000)))
        .state(ServerState::Leader, "learner node-3 becomes leader?")
        .await;
    observe("n3_became_leader", format!("\"result\":\"{}\"", res.is_ok()));

    // Let replication and heartbeats settle.
    tokio::time::sleep(Duration::from_millis(500)).await;
    for (i, h) in n.iter().enumerate() {
        observe("after", metrics_json(i as u64, h));
    }

    // Consumer-visible consequence: where does a follower forward a client write?
    let w1 = n[1].client_write(ClientRequest::make_request("specula", 1)).await;
    observe("write_via_n1", format!("\"result\":\"{}\"", match &w1 {
        Ok(r) => format!("ok log_id={}", r.log_id),
        Err(e) => format!("err {}", e).replace('"', "'"),
    }));
    let w3 = n[3].client_write(ClientRequest::make_request("specula", 2)).await;
    observe("write_via_n3", format!("\"result\":\"{}\"", match &w3 {
        Ok(r) => format!("ok log_id={}", r.log_id),
        Err(e) => format!("err {}", e).replace('"', "'"),
    }));

    tokio::time::sleep(Duration::from_millis(500)).await;
    for (i, h) in n.iter().enumerate() {
        observe("final", metrics_json(i as u64, h));
    }
    Ok(())
}

/// U1 interaction: `transfer_leader` called on every node of a 3-voter cluster, including the
/// current leader (exercises the leader's own lease reset and its vote grant).
#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specula_transfer_all_nodes() -> anyhow::Result<()> {
    let mut router = RaftRouter::new(config()?);
    let _log_index = router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;

    let n: Vec<MemRaft> = (0..3).map(|i| router.get_raft_handle(&i)).collect::<Result<_, _>>()?;
    let m0 = n[0].metrics().borrow().clone();
    let leader_vote = m0.vote;
    let last_log_id = m0.last_applied;

    n[0].transfer_leader(leader_vote, 1, last_log_id).await?;
    n[2].transfer_leader(leader_vote, 1, last_log_id).await?;
    n[1].transfer_leader(leader_vote, 1, last_log_id).await?;

    let res = n[1].wait(Some(Duration::from_millis(2_000))).state(ServerState::Leader, "node-1 leader").await;
    observe("n1_became_leader", format!("\"result\":\"{}\"", res.is_ok()));
    let res = n[0].wait(Some(Duration::from_millis(2_000))).state(ServerState::Follower, "node-0 follower").await;
    observe("n0_became_follower", format!("\"result\":\"{}\"", res.is_ok()));

    let w = n[1].client_write(ClientRequest::make_request("specula", 1)).await;
    observe("write_via_new_leader", format!("\"result\":\"{}\"", match &w {
        Ok(r) => format!("ok log_id={}", r.log_id),
        Err(e) => format!("err {}", e).replace('"', "'"),
    }));
    for (i, h) in n.iter().enumerate() {
        observe("final", metrics_json(i as u64, h));
    }
    Ok(())
}
