//! Specula code observation for D-4 (cross-round Pre-Vote grant), from the
//! model-checking diagnostic PreVoteGrantFromTrackedVoter
//! (spec/output/mc-hunt-prevote_membership-filtered-bfs.log).
//!
//! Real RaftCore runtime. Leader 0 runs Pre-Vote round 1 (`trigger().elect(true)`,
//! probe (t+1, 0), frozen voters {0,1,2}); node 2's grant is delayed 1500 ms
//! (RPC ttl = election_timeout_min = 3000 ms) and node 1's Pre-Vote RPC fails.
//! Node 2 is then removed (`change_membership([0,1], false)`), and leader 0
//! starts round 2 at the same probe (t+1, 0) with voters {0,1}. Node 2's late
//! round-1 grant matches the probe leader id (`does_pre_candidate_vote_match`)
//! and reaches `Candidate::grant_by(&2)`, which `expect`s the target to be in
//! the frozen quorum set.
use std::sync::Arc;
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
use crate::fixtures::ut_harness;

#[tracing::instrument]
#[test_harness::test(harness = ut_harness)]
async fn specula_repro_cross_round_prevote_grant() -> Result<()> {
    let config = Arc::new(
        Config {
            enable_heartbeat: false,
            enable_elect: false,
            election_timeout_min: 3000,
            election_timeout_max: 3001,
            ..Default::default()
        }
        .validate()?,
    );
    let mut router = RaftRouter::new(config.clone());
    router.new_cluster(btreeset! {0,1,2}, btreeset! {}).await?;
    let n0 = router.get_raft_handle(&0)?;
    n0.wait(Some(Duration::from_millis(3000))).state(ServerState::Leader, "node 0 is leader").await?;
    let t = n0.metrics().borrow_watched().current_term;

    tracing::info!("--- let followers' leader leases expire (heartbeat disabled)");
    TypeConfig::sleep(Duration::from_millis(3300)).await;

    // Pre-Vote (probe term t+1) from 0: to node 1 fails, to node 2 answers late.
    router
        .set_rpc_pre_hook(RPCTypes::Vote, move |_r: &_, req, from, to| {
            let res = match &req {
                RpcRequest::Vote(v) if from == 0 && to == 1 && v.vote.leader_id().term == t + 1 => Err(
                    RPCError::Network(NetworkError::<TypeConfig>::from_string("block pre-vote to node 1")),
                ),
                _ => Ok(()),
            };
            let x: BoxFuture<_> = Box::pin(futures::future::ready(res));
            x
        })
        .await;
    router
        .set_rpc_post_hook(RPCTypes::Vote, move |_r: &_, req, _resp, from, to| {
            let delay = match &req {
                RpcRequest::Vote(v) if from == 0 && to == 2 && v.vote.leader_id().term == t + 1 => 1500,
                _ => 0,
            };
            let x: BoxFuture<_> = Box::pin(async move {
                TypeConfig::sleep(Duration::from_millis(delay)).await;
                Ok(())
            });
            x
        })
        .await;

    tracing::info!("--- round 1");
    n0.trigger().elect(true).await?;
    tracing::info!("--- remove node 2 while its round-1 grant is in flight");
    n0.change_membership([0, 1], false).await?;
    tracing::info!("--- round 2 at the same probe");
    n0.trigger().elect(true).await?;

    TypeConfig::sleep(Duration::from_millis(2500)).await;
    let core = n0.with_raft_state(|st| (st.vote_ref().to_string(), st.server_state)).await;
    println!("SPECULA-OBSERVE cross-round: term_before={} core={:?}", t, core);
    let (_vote, state) = core.map_err(|e| anyhow::anyhow!("RaftCore of node 0 is gone: {}", e))?;
    assert_eq!(ServerState::Leader, state, "leader 0 should be unaffected by a stale round-1 grant");
    Ok(())
}
