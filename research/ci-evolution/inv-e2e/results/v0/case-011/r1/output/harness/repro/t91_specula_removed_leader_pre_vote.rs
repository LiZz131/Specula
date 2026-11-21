//! Specula MC-2 reproduction (runtime level).
//!
//! A cautious election requested on the leader (`trigger().elect(true)`) starts
//! a Pre-Vote round; the leader then removes itself with `change_membership`
//! (`removed_leader_step_down = Never`, so it keeps leading as documented). A
//! late granting Pre-Vote response makes the removed, non-voter node start an
//! election. Expected (asserted): the removed node does not start an election
//! (term unchanged) and stays operational.
//!
//! Install: copy to tests/tests/elect/ and add `mod t91_specula_removed_leader_pre_vote;`
//! to tests/tests/elect/main.rs.

use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use maplit::btreeset;
use openraft::Config;
use openraft::RPCTypes;
use openraft::ServerState;
use openraft::StepDownPolicy;
use openraft::async_runtime::WatchReceiver;
use openraft::base::BoxFuture;
use openraft::errors::RPCError;
use openraft::type_config::TypeConfigExt;
use openraft::vote::RaftLeaderId;
use openraft_memstore::TypeConfig;

use crate::fixtures::RaftRouter;
use crate::fixtures::rpc_request::RpcRequest;
use crate::fixtures::rpc_response::RpcResponse;
use crate::fixtures::ut_harness;

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn removed_leader_pre_vote_does_not_elect_non_voter() -> Result<()> {
    let config = Arc::new(
        Config {
            heartbeat_interval: 100,
            election_timeout_min: 1000,
            election_timeout_max: 1001,
            removed_leader_step_down: StepDownPolicy::Never,
            ..Default::default()
        }
        .validate()?,
    );

    let mut router = RaftRouter::new(config.clone());
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;
    let n0 = router.get_raft_handle(&0)?;
    let n1 = router.get_raft_handle(&1)?;
    let n2 = router.get_raft_handle(&2)?;
    n0.wait(timeout()).state(ServerState::Leader, "node 0 is leader").await?;
    let t0 = n0.metrics().borrow_watched().current_term;

    tracing::info!("--- idle leader: no heartbeats, followers do not campaign; let their leases expire");
    for n in [&n0, &n1, &n2] {
        n.runtime_config().elect(false);
    }
    n0.runtime_config().heartbeat(false);
    TypeConfig::sleep(Duration::from_millis(1500)).await;

    tracing::info!("--- delay the Pre-Vote answers to node 0 by 800ms (RPC ttl is 1000ms)");
    router
        .set_rpc_post_hook(RPCTypes::Vote, move |_r, req, resp, from, _to| {
            let delay = match (req, resp) {
                (RpcRequest::Vote(req), RpcResponse::Vote(resp))
                    if from == 0 && req.vote.leader_id().term() == t0 + 1 && resp.vote != req.vote =>
                {
                    800
                }
                _ => 0,
            };
            let fu: BoxFuture<'static, Result<(), RPCError<TypeConfig>>> = Box::pin(async move {
                if delay > 0 {
                    TypeConfig::sleep(Duration::from_millis(delay)).await;
                }
                Ok(())
            });
            fu
        })
        .await;

    tracing::info!("--- operator requests a cautious election on the leader");
    n0.trigger().elect(true).await?;
    TypeConfig::sleep(Duration::from_millis(50)).await;

    tracing::info!("--- leader removes itself from the voter set");
    n0.change_membership(btreeset! {1, 2}, false).await?;
    let m = n0.metrics().borrow_watched().clone();
    assert!(!m.membership_config.membership().voter_ids().any(|x| x == 0), "node 0 removed");
    assert_eq!(t0, m.current_term);

    TypeConfig::sleep(Duration::from_millis(1500)).await;
    let m = n0.metrics().borrow_watched().clone();
    let alive = n0.with_raft_state(|_| ()).await;
    println!(
        "--- after removal + late pre-vote: node 0 term={} state={:?} core_alive={:?}",
        m.current_term, m.state, alive
    );
    assert!(alive.is_ok(), "node 0 RaftCore must stay alive: {:?}", alive);
    assert_eq!(t0, m.current_term, "a removed, non-voter node must not start an election");
    Ok(())
}

fn timeout() -> Option<Duration> {
    Some(Duration::from_millis(3000))
}
