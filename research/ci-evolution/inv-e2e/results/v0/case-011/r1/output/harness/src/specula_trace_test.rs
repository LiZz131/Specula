//! Specula incremental trace harness (rebased from the V0 exact-old harness).
//!
//! Test-only instrumentation. It invokes the real updated `Engine` transitions
//! directly and records source-observable abstract state before and after each
//! transition. Multi-event scenarios hand the queued engine commands to the
//! runtime boundary between events (as `RaftCore::run_engine_commands` does,
//! core/raft_core.rs:1110-1160) and record that hand-off as a `RunCommands`
//! event naming the commands.
//!
//! Changes versus the V0 harness:
//! - new state fields: `pre_candidate_*`, `pre_grants`, `send_pre_vote_pending`;
//! - `candidate_config` / `pre_candidate_config` read the real frozen quorum set
//!   (`Candidate::progress().quorum_set()`), no longer a proxy via effective
//!   membership;
//! - `seen_greater_log` reads `Engine::is_there_greater_log()` instead of a
//!   constant `false`;
//! - new Pre-Vote scenarios derived from the `update` diff.

use std::collections::BTreeSet;
use std::fs::OpenOptions;
use std::io::Write;
use std::sync::Arc;
use std::time::Duration;
use std::time::SystemTime;
use std::time::UNIX_EPOCH;

use maplit::btreeset;
use serde_json::Value;
use serde_json::json;

use crate::Membership;
use crate::MembershipState;
use crate::Vote;
use crate::core::ServerState;
use crate::engine::Command;
use crate::engine::CommandName;
use crate::engine::Engine;
use crate::engine::LogIdList;
use crate::engine::testing::UTConfig;
use crate::engine::testing::log_id;
use crate::entry::payload::EntryPayload;
use crate::progress::Progress;
use crate::raft::VoteRequest;
use crate::raft::VoteResponse;
use crate::raft::message::LogSegment;
use crate::raft_state::LogStateReader;
use crate::type_config::TypeConfigExt;
use crate::type_config::alias::StoredMembershipOf;
use crate::utime::Leased;

type UTVote = Vote<crate::engine::testing::UTLeaderId>;

fn membership(parts: Vec<BTreeSet<u64>>) -> Membership<u64, ()> {
    Membership::new_with_defaults(parts, [])
}

fn stored(index: u64, parts: Vec<BTreeSet<u64>>) -> Arc<StoredMembershipOf<UTConfig>> {
    Arc::new(StoredMembershipOf::<UTConfig>::new(
        Some(log_id(1, 1, index)),
        membership(parts),
    ))
}

fn base_engine(id: u64, parts: Vec<BTreeSet<u64>>, membership_index: u64) -> Engine<UTConfig> {
    let mut eng = Engine::testing_default(id);
    eng.state.enable_validation(false);
    eng.config.id = id;
    let membership = stored(membership_index, parts);
    eng.state.membership_state = MembershipState::new(membership.clone(), membership);
    eng.state.log_ids = LogIdList::new(None, [log_id(1, 1, membership_index)]);
    eng.state.server_state = ServerState::Follower;
    eng.output.clear_commands();
    eng
}

fn vote_json(v: &UTVote) -> Value {
    json!({
        "term": v.leader_id.term,
        "node": v.leader_id.node_id.to_string(),
        "committed": v.committed,
    })
}

fn log_json(log: Option<&crate::type_config::alias::LogIdOf<UTConfig>>, node: u64) -> Value {
    match log {
        Some(x) => json!({
            "present": true,
            "term": x.leader_id.term,
            "node": x.leader_id.node_id.to_string(),
            "index": x.index,
        }),
        None => json!({"present": false, "term": 0, "node": node.to_string(), "index": 0}),
    }
}

fn joint_json(parts: &[BTreeSet<u64>]) -> Value {
    let parts = parts
        .iter()
        .map(|part| part.iter().map(u64::to_string).collect::<Vec<_>>())
        .collect::<Vec<_>>();
    json!(parts)
}

fn config_json(m: &StoredMembershipOf<UTConfig>) -> Value {
    joint_json(m.get_joint_config())
}

fn state_json(eng: &Engine<UTConfig>, crashed: bool) -> Value {
    let effective = eng.state.membership_state.effective();
    let committed = eng.state.membership_state.committed();

    let candidate = eng.candidate_ref();
    let candidate_vote = candidate.map(|x| x.vote_ref()).unwrap_or_else(|| eng.state.vote_ref());
    let grants = candidate
        .map(|x| x.granters().map(|id| id.to_string()).collect::<Vec<_>>())
        .unwrap_or_default();
    // Real frozen quorum set of the candidate (falls back to effective when absent).
    let candidate_config = candidate
        .map(|x| joint_json(x.progress().quorum_set().get_joint_config()))
        .unwrap_or_else(|| config_json(effective));

    let pre = eng.pre_candidate_ref();
    let pre_vote = pre.map(|x| x.vote_ref()).unwrap_or_else(|| eng.state.vote_ref());
    let pre_grants = pre
        .map(|x| x.granters().map(|id| id.to_string()).collect::<Vec<_>>())
        .unwrap_or_default();
    let pre_config = pre
        .map(|x| joint_json(x.progress().quorum_set().get_joint_config()))
        .unwrap_or_else(|| config_json(effective));

    let has_command = |name| eng.output.iter_commands().any(|cmd| cmd.name() == name);
    let (last_update, lease, enabled) = eng.state.vote.lease_info();
    let lease_valid = enabled
        && last_update.is_some()
        && !eng.state.vote.is_expired(UTConfig::<()>::now(), Duration::default())
        && !lease.is_zero();

    json!({
        "role": match eng.state.server_state {
            ServerState::Learner => "Learner",
            ServerState::Follower => "Follower",
            ServerState::Candidate => "Candidate",
            ServerState::Leader => "Leader",
            ServerState::Shutdown => "Follower",
        },
        "vote": vote_json(eng.state.vote_ref()),
        "last_log": log_json(eng.state.last_log_id(), eng.config.id),
        "committed_config": config_json(committed),
        "committed_config_index": committed.log_id().as_ref().map(|x| x.index).unwrap_or(0),
        "effective_config": config_json(effective),
        "effective_config_index": effective.log_id().as_ref().map(|x| x.index).unwrap_or(0),
        "lease_valid": lease_valid,
        "candidate_active": candidate.is_some(),
        "candidate_vote": vote_json(candidate_vote),
        "candidate_config": candidate_config,
        "grants": grants,
        "leader_active": eng.leader_ref().is_some(),
        "save_vote_pending": has_command(CommandName::SaveVote),
        "send_vote_pending": has_command(CommandName::SendVote),
        "append_pending": has_command(CommandName::AppendEntries),
        "seen_greater_log": eng.is_there_greater_log(),
        "crashed": crashed,
        "pre_candidate_active": pre.is_some(),
        "pre_candidate_vote": vote_json(pre_vote),
        "pre_candidate_config": pre_config,
        "pre_grants": pre_grants,
        "send_pre_vote_pending": has_command(CommandName::SendPreVote),
    })
}

fn emit(name: &str, nid: u64, pre: Value, post: Value, args: Value) -> anyhow::Result<()> {
    let path = std::env::var("SPECULA_TRACE_PATH")?;
    let mut out = OpenOptions::new().create(true).append(true).open(path)?;
    let ts = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos().to_string();
    let record = json!({
        "tag": "trace",
        "ts_unix_ns": ts,
        "event": {
            "name": name,
            "nid": nid.to_string(),
            "pre": pre,
            "post": post,
            "args": args,
        }
    });
    serde_json::to_writer(&mut out, &record)?;
    writeln!(&mut out)?;
    Ok(())
}

/// Hand all queued commands to the runtime boundary and record which ones.
fn run_commands(eng: &mut Engine<UTConfig>, nid: u64) -> anyhow::Result<()> {
    let pre = state_json(eng, false);
    let cmds = eng.output.take_commands();
    let names = cmds.iter().map(|c| format!("{:?}", c.name())).collect::<Vec<_>>();
    let post = state_json(eng, false);
    emit("RunCommands", nid, pre, post, json!({ "commands": names }))
}

/// The queued SendPreVote request, if any.
fn send_pre_vote_args(eng: &Engine<UTConfig>, nid: u64) -> Value {
    for cmd in eng.output.iter_commands() {
        if let Command::SendPreVote { vote_req } = cmd {
            return json!({
                "req_vote": vote_json(&vote_req.vote),
                "req_last_log": log_json(vote_req.last_log_id.as_ref(), nid),
            });
        }
    }
    json!({
        "req_vote": vote_json(eng.state.vote_ref()),
        "req_last_log": log_json(eng.state.last_log_id(), nid),
    })
}

fn emit_pre_elect(eng: &mut Engine<UTConfig>, nid: u64) -> anyhow::Result<()> {
    let pre = state_json(eng, false);
    eng.pre_elect();
    let post = state_json(eng, false);
    emit("PreElect", nid, pre, post, send_pre_vote_args(eng, nid))
}

fn emit_vote_req(eng: &mut Engine<UTConfig>, nid: u64, source: u64, req: VoteRequest<UTConfig>) -> anyhow::Result<()> {
    let pre = state_json(eng, false);
    let resp = eng.handle_vote_req(req.clone());
    let post = state_json(eng, false);
    emit(
        "HandleVoteRequest",
        nid,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "vote": vote_json(&req.vote),
            "last_log": log_json(req.last_log_id.as_ref(), source),
            "transfer": req.leadership_transfer,
            "response_vote": vote_json(&resp.vote),
            "response_granted": resp.vote_granted,
        }),
    )
}

fn emit_pre_vote_req(
    eng: &mut Engine<UTConfig>,
    nid: u64,
    source: u64,
    req: VoteRequest<UTConfig>,
) -> anyhow::Result<()> {
    let pre = state_json(eng, false);
    let commands_before = eng.output.iter_commands().count();
    let resp = eng.handle_pre_vote_req(req.clone());
    // handle_pre_vote_req emits no command (engine_impl.rs:405-447).
    assert_eq!(commands_before, eng.output.iter_commands().count());
    let post = state_json(eng, false);
    emit(
        "HandlePreVoteRequest",
        nid,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "vote": vote_json(&req.vote),
            "last_log": log_json(req.last_log_id.as_ref(), source),
            "response_vote": vote_json(&resp.vote),
            "response_last_log": log_json(resp.last_log_id.as_ref(), nid),
            "response_granted": resp.vote_granted,
        }),
    )
}

fn emit_vote_resp(eng: &mut Engine<UTConfig>, nid: u64, source: u64, resp: VoteResponse<UTConfig>) -> anyhow::Result<()> {
    let pre = state_json(eng, false);
    eng.handle_vote_resp(source, resp.clone());
    let post = state_json(eng, false);
    emit(
        "HandleVoteResponse",
        nid,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "vote": vote_json(&resp.vote),
            "last_log": log_json(resp.last_log_id.as_ref(), source),
            "granted": resp.vote_granted,
        }),
    )
}

/// Deliver a Pre-Vote response the way RaftCore does: only while a
/// pre-candidate exists whose leader id equals the notification's
/// candidate_vote (core/raft_core.rs:1803-1820, 2067-2090).
fn emit_pre_vote_resp(
    eng: &mut Engine<UTConfig>,
    nid: u64,
    source: u64,
    candidate_vote: UTVote,
    resp: VoteResponse<UTConfig>,
) -> anyhow::Result<()> {
    let matches = eng
        .pre_candidate_ref()
        .map(|pc| pc.vote_ref().leader_id == candidate_vote.leader_id)
        .unwrap_or(false);
    assert!(matches, "harness only delivers responses the runtime filter accepts");
    let pre = state_json(eng, false);
    eng.handle_pre_vote_resp(source, resp.clone());
    let post = state_json(eng, false);
    emit(
        "HandlePreVoteResponse",
        nid,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "candidate_vote": vote_json(&candidate_vote),
            "response_vote": vote_json(&resp.vote),
            "last_log": log_json(resp.last_log_id.as_ref(), source),
            "granted": resp.vote_granted,
        }),
    )
}

// ---------------------------------------------------------------------------
// Prior V0 scenarios (rerun on the updated implementation)
// ---------------------------------------------------------------------------

#[test]
fn specula_trace_start_election() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(1, 2));
    let pre = state_json(&eng, false);
    eng.elect();
    let post = state_json(&eng, false);
    emit("StartElection", 1, pre, post, json!({"transfer": false}))
}

#[test]
fn specula_trace_reject_stale_log() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 1));
    eng.state.log_ids = LogIdList::new(None, [log_id(2, 1, 3)]);
    eng.state.server_state = ServerState::Candidate;
    eng.new_candidate(*eng.state.vote_ref());
    eng.output.clear_commands();
    emit_vote_req(&mut eng, 1, 2, VoteRequest {
        vote: Vote::new(3, 2),
        last_log_id: Some(log_id(1, 2, 3)),
        leadership_transfer: false,
    })
}

#[test]
fn specula_trace_grant_greater_vote() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 1));
    eng.state.log_ids = LogIdList::new(None, [log_id(2, 1, 3)]);
    eng.state.server_state = ServerState::Candidate;
    eng.new_candidate(*eng.state.vote_ref());
    eng.output.clear_commands();
    emit_vote_req(&mut eng, 1, 2, VoteRequest {
        vote: Vote::new(3, 2),
        last_log_id: Some(log_id(2, 1, 3)),
        leadership_transfer: false,
    })
}

#[test]
fn specula_trace_establish_leader() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2}], 0);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::from_millis(500), Vote::new(2, 1));
    eng.state.server_state = ServerState::Candidate;
    let candidate = eng.new_candidate(*eng.state.vote_ref());
    candidate.grant_by(&1);
    eng.output.clear_commands();
    let response = VoteResponse::new(Vote::new(2, 1), Some(log_id(1, 1, 0)), true);
    emit_vote_resp(&mut eng, 1, 2, response)
}

#[test]
fn specula_trace_append_joint_membership() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2}], 1);
    eng.state.vote = Leased::new(
        UTConfig::<()>::now(),
        Duration::from_millis(500),
        Vote::new_committed(2, 1),
    );
    eng.state.server_state = ServerState::Leader;
    eng.testing_new_leader();
    eng.output.clear_commands();
    let target = btreeset! {2, 3};
    let pre = state_json(&eng, false);
    eng.try_leader_handler()?.leader_append_entries([EntryPayload::Membership(membership(vec![
        btreeset! {1, 2},
        target.clone(),
    ]))]);
    let post = state_json(&eng, false);
    emit(
        "AppendJointConfig",
        1,
        pre,
        post,
        json!({"target_config": target.iter().map(u64::to_string).collect::<Vec<_>>() }),
    )
}

#[test]
fn specula_trace_commit_membership() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2}], 1);
    let old = stored(1, vec![btreeset! {1, 2}]);
    let joint = stored(2, vec![btreeset! {1, 2}, btreeset! {2, 3}]);
    eng.state.membership_state = MembershipState::new(old, joint);
    eng.state.log_ids = LogIdList::new(None, [log_id(1, 1, 2)]);
    eng.state.apply_progress_mut().accept(log_id(1, 1, 1));
    eng.state.vote = Leased::new(
        UTConfig::<()>::now(),
        Duration::from_millis(500),
        Vote::new_committed(2, 1),
    );
    eng.state.server_state = ServerState::Leader;
    eng.testing_new_leader();
    eng.output.clear_commands();
    let pre = state_json(&eng, false);
    eng.state.update_local_committed(&Some(log_id(1, 1, 2)));
    let post = state_json(&eng, false);
    emit("CommitMembership", 1, pre, post, json!({}))
}

#[test]
fn specula_trace_restart_follower() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::without_last_update(Vote::new(2, 2));
    eng.state.server_state = ServerState::Learner;
    eng.output.clear_commands();
    let pre = state_json(&eng, true);
    eng.startup();
    let post = state_json(&eng, false);
    emit("Restart", 1, pre, post, json!({}))
}

// ---------------------------------------------------------------------------
// Update scenarios derived from the `update` diff (Pre-Vote)
// ---------------------------------------------------------------------------

/// A follower whose leader lease expired starts a Pre-Vote round
/// (engine_impl.rs:298-322): no vote/role change, SendPreVote queued.
#[test]
fn specula_trace_pre_elect_multi() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    emit_pre_elect(&mut eng, 1)
}

/// A single voter wins its own Pre-Vote and elects at once (engine_impl.rs:308-315).
#[test]
fn specula_trace_pre_elect_single() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 1));
    emit_pre_elect(&mut eng, 1)
}

/// handle_pre_vote_req grants when lease expired, log and vote are acceptable.
#[test]
fn specula_trace_pre_vote_req_grant() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    emit_pre_vote_req(&mut eng, 1, 3, VoteRequest::new(Vote::new(2, 3), Some(log_id(1, 1, 1))))
}

/// handle_pre_vote_req honors a valid leader lease (engine_impl.rs:433-437).
#[test]
fn specula_trace_pre_vote_req_reject_lease() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(
        UTConfig::<()>::now(),
        Duration::from_millis(5000),
        Vote::new_committed(1, 2),
    );
    emit_pre_vote_req(&mut eng, 1, 3, VoteRequest::new(Vote::new(2, 3), Some(log_id(1, 1, 1))))
}

/// handle_pre_vote_req rejects a candidate with a smaller last log.
#[test]
fn specula_trace_pre_vote_req_reject_log() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 1));
    eng.state.log_ids = LogIdList::new(None, [log_id(2, 1, 3)]);
    emit_pre_vote_req(&mut eng, 1, 2, VoteRequest::new(Vote::new(3, 2), Some(log_id(1, 2, 3))))
}

/// handle_pre_vote_req rejects a probe vote smaller than the local vote.
#[test]
fn specula_trace_pre_vote_req_reject_vote() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(3, 2));
    emit_pre_vote_req(&mut eng, 1, 3, VoteRequest::new(Vote::new(2, 3), Some(log_id(1, 1, 1))))
}

/// A Pre-Vote quorum starts the real election (engine_impl.rs:530-541).
#[test]
fn specula_trace_pre_vote_resp_quorum_elect() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    emit_pre_elect(&mut eng, 1)?;
    run_commands(&mut eng, 1)?;
    let probe = *eng.pre_candidate_ref().unwrap().vote_ref();
    emit_pre_vote_resp(
        &mut eng,
        1,
        3,
        probe,
        VoteResponse::new(Vote::new_committed(1, 2), Some(log_id(1, 1, 1)), true),
    )
}

/// A rejection by a responder with a greater log sets the greater-log back-off
/// and keeps the round (engine_impl.rs:543-551).
#[test]
fn specula_trace_pre_vote_resp_reject_greater_log() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    emit_pre_elect(&mut eng, 1)?;
    run_commands(&mut eng, 1)?;
    let probe = *eng.pre_candidate_ref().unwrap().vote_ref();
    emit_pre_vote_resp(
        &mut eng,
        1,
        2,
        probe,
        VoteResponse::new(Vote::new_committed(1, 2), Some(log_id(1, 2, 4)), false),
    )
}

/// A grant that does not complete a joint quorum only advances the tally.
#[test]
fn specula_trace_pre_vote_resp_joint_no_quorum() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2}], 1);
    let old = stored(1, vec![btreeset! {1, 2}]);
    let joint = stored(2, vec![btreeset! {1, 2}, btreeset! {2, 3}]);
    eng.state.membership_state = MembershipState::new(old, joint);
    eng.state.log_ids = LogIdList::new(None, [log_id(1, 1, 2)]);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    emit_pre_elect(&mut eng, 1)?;
    run_commands(&mut eng, 1)?;
    let probe = *eng.pre_candidate_ref().unwrap().vote_ref();
    emit_pre_vote_resp(
        &mut eng,
        1,
        3,
        probe,
        VoteResponse::new(Vote::new_committed(1, 2), Some(log_id(1, 1, 2)), true),
    )
}

/// Interaction U1: a Candidate whose election timer fired starts a Pre-Vote
/// round, then wins its in-flight election, then receives a granting
/// Pre-Vote response for the round started before it became leader.
/// Runtime path: handle_tick_election (raft_core.rs:1959-2036) does not check
/// for an in-flight candidate; establish_leader (engine_impl.rs:855-881) does
/// not clear pre_candidate; the PreVoteResponse filter (raft_core.rs:1803-1820)
/// only checks pre_candidate.is_some() and its leader id.
#[test]
fn specula_trace_stale_pre_vote_after_establish() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 1));
    eng.state.server_state = ServerState::Candidate;
    let candidate = eng.new_candidate(*eng.state.vote_ref());
    candidate.grant_by(&1);
    eng.output.clear_commands();

    emit_pre_elect(&mut eng, 1)?;
    run_commands(&mut eng, 1)?;
    let probe = *eng.pre_candidate_ref().unwrap().vote_ref();

    emit_vote_resp(&mut eng, 1, 2, VoteResponse::new(Vote::new(2, 1), Some(log_id(1, 1, 1)), true))?;
    run_commands(&mut eng, 1)?;

    emit_pre_vote_resp(
        &mut eng,
        1,
        2,
        probe,
        VoteResponse::new(Vote::new(2, 1), Some(log_id(1, 1, 1)), true),
    )
}

/// Interaction: a heartbeat from the current leader (equal committed vote)
/// cancels the Pre-Vote round through become_following (vote_handler:244).
#[test]
fn specula_trace_heartbeat_cancels_pre_vote() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    emit_pre_elect(&mut eng, 1)?;
    run_commands(&mut eng, 1)?;

    let leader_vote = Vote::new_committed(1, 2);
    let pre = state_json(&eng, false);
    let res = eng.append_entries(&leader_vote, LogSegment::new(Some(log_id(1, 1, 1)), vec![]));
    assert!(res.is_ok());
    let post = state_json(&eng, false);
    emit(
        "HandleAppendEntries",
        1,
        pre,
        post,
        json!({"source": "2", "vote": vote_json(&leader_vote)}),
    )
}

/// Interaction: granting another candidate's vote cancels the Pre-Vote round.
#[test]
fn specula_trace_vote_grant_cancels_pre_vote() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    emit_pre_elect(&mut eng, 1)?;
    run_commands(&mut eng, 1)?;
    emit_vote_req(&mut eng, 1, 3, VoteRequest::new(Vote::new(2, 3), Some(log_id(1, 1, 1))))
}
