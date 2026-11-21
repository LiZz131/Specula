use std::sync::Arc;
use std::time::Duration;

use maplit::btreeset;
use openraft::Config;

use crate::fixtures::ut_harness;
use crate::fixtures::RaftRouter;

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn probe_transfer_leader_to_current_leader() -> anyhow::Result<()> {
    let config = Arc::new(
        Config { election_timeout_min: 150, election_timeout_max: 300, ..Default::default() }.validate()?,
    );
    let mut router = RaftRouter::new(config.clone());
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;
    let n0 = router.get_raft_handle(&0)?;
    let m = n0.metrics().borrow().clone();
    for id in [0u64, 1, 2] {
        let n = router.get_raft_handle(&id)?;
        println!("PROBE-XFER call n{} -> {:?}", id, n.transfer_leader(m.vote, 0, m.last_applied).await);
    }
    tokio::time::sleep(Duration::from_millis(1_000)).await;
    for id in [0u64, 1, 2] {
        let n = router.get_raft_handle(&id)?;
        let mm = n.metrics().borrow().clone();
        println!("PROBE-XFER n{} is_initialized={:?} state={:?} vote={} leader={:?}",
            id, n.is_initialized().await, mm.state, mm.vote, mm.current_leader);
    }
    Ok(())
}
