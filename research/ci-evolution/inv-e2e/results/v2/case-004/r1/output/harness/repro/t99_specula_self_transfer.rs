//! Specula code observation (interaction of TransferLeader with an old consumer): the current
//! Leader is the `to` node; it calls elect() while its Leader object survives
//! (vote_handler/mod.rs:168-176), then a client write reaches leader_handler(), which
//! debug-asserts leader.committed_vote >= state.vote (engine_impl.rs:765-770).
//! Observation only: prints the outcome, asserts nothing about it.

use std::sync::Arc;
use std::time::Duration;

use maplit::btreeset;
use openraft::Config;
use openraft_memstore::ClientRequest;
use openraft_memstore::IntoMemClientRequest;

use crate::fixtures::ut_harness;
use crate::fixtures::RaftRouter;

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specula_observe_transfer_to_current_leader_then_write() -> anyhow::Result<()> {
    let config = Arc::new(
        Config {
            election_timeout_min: 150,
            election_timeout_max: 300,
            ..Default::default()
        }
        .validate()?,
    );
    let mut router = RaftRouter::new(config);
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;
    let n0 = router.get_raft_handle(&0)?;
    let m0 = n0.metrics().borrow().clone();

    // Only the leader is told (to = itself); followers keep their leases.
    let _ = n0.transfer_leader(m0.vote, 0, m0.last_applied).await;
    let w = tokio::time::timeout(Duration::from_millis(2000), n0.client_write(ClientRequest::make_request("self", 1))).await;
    println!("SPECULA_OBS self_transfer_write: {:?}", w.as_ref().map(|r| r.as_ref().map(|x| x.log_id.to_string()).map_err(|e| e.to_string())));
    tokio::time::sleep(Duration::from_millis(300)).await;
    let m = n0.metrics().borrow().clone();
    println!("SPECULA_OBS self_transfer_state: state={:?} vote={} current_leader={:?}", m.state, m.vote, m.current_leader);
    Ok(())
}
