//! Specula control: operator election trigger on the current Leader (new revision API).
//! Checks whether the retained Leader object trips try_leader_handler's assertion.
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use maplit::btreeset;
use openraft::Config;
use openraft::ServerState;
use openraft::type_config::TypeConfigExt;
use openraft_memstore::TypeConfig;

use crate::fixtures::RaftRouter;
use crate::fixtures::ut_harness;

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specula_control_elect_on_leader() -> Result<()> {
    let config = Arc::new(Config { enable_heartbeat: false, enable_elect: false, ..Default::default() }.validate()?);
    let mut router = RaftRouter::new(config.clone());
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;
    let n0 = router.get_raft_handle(&0)?;
    n0.wait(Some(Duration::from_millis(3000))).state(ServerState::Leader, "node 0 is leader").await?;
    n0.trigger().elect(false).await?;
    TypeConfig::sleep(Duration::from_millis(500)).await;
    let core = n0.with_raft_state(|st| (st.vote_ref().to_string(), st.server_state)).await;
    println!("SPECULA-OBSERVE elect-on-leader (new): core={:?}", core);
    Ok(())
}
