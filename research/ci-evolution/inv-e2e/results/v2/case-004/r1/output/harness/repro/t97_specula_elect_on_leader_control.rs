//! Attribution control for the self-transfer observation: the pre-existing path
//! `trigger().elect()` (ExternalCommand::Elect, no "already leader" check) on the Leader,
//! then a client write. Runs on both baseline and update trees.

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
async fn specula_observe_trigger_elect_on_leader_then_write() -> anyhow::Result<()> {
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
    n0.trigger().elect().await?;
    let w = tokio::time::timeout(Duration::from_millis(2000), n0.client_write(ClientRequest::make_request("ctl", 1))).await;
    println!("SPECULA_OBS trigger_elect_write: {:?}", w.as_ref().map(|r| r.as_ref().map(|x| x.log_id.to_string()).map_err(|e| e.to_string())));
    Ok(())
}
