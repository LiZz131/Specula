//! Probe (U-S4 leader self-transfer): a Leader that runs Engine::elect() keeps its Leader object
//! (candidate+leader coexistence). Engine::leader_handler() debug-asserts
//! `leader.committed_vote >= state.vote`, and RaftCore calls leader_handler() every loop.
use std::sync::Arc;
use std::time::Duration;

use maplit::btreeset;
use openraft::Config;

use crate::fixtures::ut_harness;
use crate::fixtures::RaftRouter;

async fn setup() -> anyhow::Result<RaftRouter> {
    let config = Arc::new(
        Config { election_timeout_min: 150, election_timeout_max: 300, ..Default::default() }.validate()?,
    );
    let mut router = RaftRouter::new(config.clone());
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;
    Ok(router)
}

async fn observe(router: &RaftRouter, tag: &str) -> anyhow::Result<()> {
    tokio::time::sleep(Duration::from_millis(1_000)).await;
    for id in [0u64, 1, 2] {
        let n = router.get_raft_handle(&id)?;
        let m = n.metrics().borrow().clone();
        println!("PROBE-{} n{} is_initialized={:?} state={:?} vote={} leader={:?}",
            tag, id, n.is_initialized().await, m.state, m.vote, m.current_leader);
    }
    Ok(())
}

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn probe_trigger_elect_on_leader() -> anyhow::Result<()> {
    let router = setup().await?;
    let n0 = router.get_raft_handle(&0)?;
    n0.trigger().elect().await?;
    observe(&router, "TRIGGER").await
}
