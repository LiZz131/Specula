//! Specula trace harness (rebased for the Pre-Vote revision).
//!
//! This module is test-only instrumentation. It invokes the real Engine
//! transitions directly and records only source-observable abstract state.
//! Prior V0 scenarios are kept with their original setup; Pre-Vote scenarios
//! are added for the update. Between two engine events of one trace the
//! harness drains the queued commands, which is what RaftCore does after
//! every event (core/raft_core.rs: run_engine_commands); the next event's
//! `pre` state records the result.

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
use crate::raft::LogSegment;
use crate::raft::VoteRequest;
use crate::raft::VoteResponse;
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

fn parts_json(parts: &[BTreeSet<u64>]) -> Value {
    let parts = parts.iter().map(|part| part.iter().map(u64::to_string).collect::<Vec<_>>()).collect::<Vec<_>>();
    json!(parts)
}

fn config_json(m: &StoredMembershipOf<UTConfig>) -> Value {
    parts_json(m.get_joint_config())
}

fn state_json(eng: &Engine<UTConfig>, crashed: bool) -> Value {
    let candidate = eng.candidate_ref();
    let candidate_vote = candidate.map(|x| x.vote_ref()).unwrap_or_else(|| eng.state.vote_ref());
    let grants = candidate.map(|x| x.granters().map(|id| id.to_string()).collect::<Vec<_>>()).unwrap_or_default();
    let pre_candidate = eng.pre_candidate_ref();
    let pre_vote = pre_candidate.map(|x| x.vote_ref()).unwrap_or_else(|| eng.state.vote_ref());
    let pre_grants =
        pre_candidate.map(|x| x.granters().map(|id| id.to_string()).collect::<Vec<_>>()).unwrap_or_default();
    let has_command = |name| eng.output.iter_commands().any(|cmd| cmd.name() == name);
    let (last_update, lease, enabled) = eng.state.vote.lease_info();
    let lease_valid = enabled
        && last_update.is_some()
        && !eng.state.vote.is_expired(UTConfig::<()>::now(), Duration::default())
        && !lease.is_zero();
    let committed = eng.state.membership_state.committed();
    let effective = eng.state.membership_state.effective();
    // The frozen quorum set of the candidate / pre-candidate (proposer/candidate.rs).
    let candidate_config = candidate
        .map(|x| parts_json(x.progress().quorum_set().get_joint_config()))
        .unwrap_or_else(|| config_json(effective));
    let pre_candidate_config = pre_candidate
        .map(|x| parts_json(x.progress().quorum_set().get_joint_config()))
        .unwrap_or_else(|| config_json(effective));

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
        "pre_candidate_active": pre_candidate.is_some(),
        "pre_candidate_vote": vote_json(pre_vote),
        "pre_candidate_config": pre_candidate_config,
        "pre_grants": pre_grants,
        "send_pre_vote_pending": has_command(CommandName::SendPreVote),
    })
}

/// The queued SendPreVote request, if any (engine/command.rs: Command::SendPreVote).
fn send_pre_vote_req_json(eng: &Engine<UTConfig>, node: u64) -> Value {
    for cmd in eng.output.iter_commands() {
        if let Command::SendPreVote { vote_req } = cmd {
            return json!({
                "vote": vote_json(&vote_req.vote),
                "last_log": log_json(vote_req.last_log_id.as_ref(), node),
            });
        }
    }
    json!({"vote": {"term": 0, "node": node.to_string(), "committed": false},
           "last_log": log_json(None, node)})
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

/// RaftCore runs every queued command after an event (raft_core.rs run_engine_commands).
fn drain(eng: &mut Engine<UTConfig>) {
    eng.output.take_commands();
}

// ---------------------------------------------------------------------------
// Pre-Vote event helpers. Each calls exactly one real engine entry point.
// ---------------------------------------------------------------------------

/// by_timer = true replays handle_tick_election's `reset_greater_log(); pre_elect()`
/// (core/raft_core.rs:2027-2031); false replays ExternalCommand::Elect { pre_vote: true }.
fn ev_pre_elect(eng: &mut Engine<UTConfig>, by_timer: bool) -> anyhow::Result<()> {
    let id = eng.config.id;
    let pre = state_json(eng, false);
    if by_timer {
        eng.reset_greater_log();
    }
    eng.pre_elect();
    let post = state_json(eng, false);
    let req = send_pre_vote_req_json(eng, id);
    emit("PreElect", id, pre, post, json!({"by_timer": by_timer, "send_pre_vote_req": req}))
}

fn ev_handle_pre_vote_req(eng: &mut Engine<UTConfig>, source: u64, req: VoteRequest<UTConfig>) -> anyhow::Result<()> {
    let id = eng.config.id;
    let pre = state_json(eng, false);
    let before = eng.output.iter_commands().count();
    let resp = eng.handle_pre_vote_req(req.clone());
    let emitted = eng.output.iter_commands().count() - before;
    let post = state_json(eng, false);
    emit(
        "HandlePreVoteRequest",
        id,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "vote": vote_json(&req.vote),
            "last_log": log_json(req.last_log_id.as_ref(), source),
            "response_vote": vote_json(&resp.vote),
            "response_last_log": log_json(resp.last_log_id.as_ref(), id),
            "response_granted": resp.vote_granted,
            "commands_emitted": emitted,
        }),
    )
}

/// Delivers a Pre-Vote response the way RaftCore does after its correlation check
/// (core/raft_core.rs:1815-1816): only when a pre-candidate with the same probed
/// leader id exists. `candidate_vote` is the probed vote the response answers.
fn ev_handle_pre_vote_resp(
    eng: &mut Engine<UTConfig>,
    source: u64,
    candidate_vote: UTVote,
    resp: VoteResponse<UTConfig>,
) -> anyhow::Result<()> {
    let id = eng.config.id;
    let matches = eng.pre_candidate_ref().map(|pc| pc.vote_ref().leader_id() == candidate_vote.leader_id()).unwrap_or(false);
    anyhow::ensure!(matches, "harness only delivers correlated pre-vote responses");
    let pre = state_json(eng, false);
    eng.handle_pre_vote_resp(source, resp.clone());
    let post = state_json(eng, false);
    emit(
        "HandlePreVoteResponse",
        id,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "candidate_vote": vote_json(&candidate_vote),
            "vote": vote_json(&resp.vote),
            "last_log": log_json(resp.last_log_id.as_ref(), source),
            "granted": resp.vote_granted,
        }),
    )
}

fn ev_handle_vote_resp(eng: &mut Engine<UTConfig>, source: u64, response: VoteResponse<UTConfig>) -> anyhow::Result<()> {
    let id = eng.config.id;
    let pre = state_json(eng, false);
    eng.handle_vote_resp(source, response.clone());
    let post = state_json(eng, false);
    emit(
        "HandleVoteResponse",
        id,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "vote": vote_json(&response.vote),
            "last_log": log_json(response.last_log_id.as_ref(), source),
            "granted": response.vote_granted,
        }),
    )
}

fn ev_handle_vote_req(eng: &mut Engine<UTConfig>, source: u64, req: VoteRequest<UTConfig>) -> anyhow::Result<()> {
    let id = eng.config.id;
    let pre = state_json(eng, false);
    let resp = eng.handle_vote_req(req.clone());
    let post = state_json(eng, false);
    emit(
        "HandleVoteRequest",
        id,
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

/// Engine::append_entries with an empty segment whose prev_log_id is the local
/// last log: the vote update / following transition without log mutation.
fn ev_handle_append_entries(eng: &mut Engine<UTConfig>, source: u64, vote: UTVote) -> anyhow::Result<()> {
    let id = eng.config.id;
    let prev = eng.state.last_log_id().cloned();
    let pre = state_json(eng, false);
    let res = eng.append_entries(&vote, LogSegment::new(prev.clone(), vec![]));
    let post = state_json(eng, false);
    emit(
        "HandleAppendEntries",
        id,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "vote": vote_json(&vote),
            "prev_log": log_json(prev.as_ref(), source),
            "accepted": res.is_ok(),
        }),
    )
}

// ---------------------------------------------------------------------------
// Prior V0 scenarios (rebased; setup unchanged).
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
    let req = VoteRequest {
        vote: Vote::new(3, 2),
        last_log_id: Some(log_id(1, 2, 3)),
        leadership_transfer: false,
    };
    ev_handle_vote_req(&mut eng, 2, req)
}

#[test]
fn specula_trace_grant_greater_vote() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 1));
    eng.state.log_ids = LogIdList::new(None, [log_id(2, 1, 3)]);
    eng.state.server_state = ServerState::Candidate;
    eng.new_candidate(*eng.state.vote_ref());
    eng.output.clear_commands();
    let req = VoteRequest {
        vote: Vote::new(3, 2),
        last_log_id: Some(log_id(2, 1, 3)),
        leadership_transfer: false,
    };
    ev_handle_vote_req(&mut eng, 2, req)
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
    ev_handle_vote_resp(&mut eng, 2, response)
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
// Update (Pre-Vote) scenarios.
// ---------------------------------------------------------------------------

/// U1: timer Pre-Vote on a follower of a 3-voter cluster. The greater-log flag
/// is set beforehand to observe the timer's reset; vote/role/lease unchanged.
#[test]
fn specula_trace_prevote_timer_multi() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    eng.set_greater_log();
    ev_pre_elect(&mut eng, true)
}

/// U3: an operator Pre-Vote on a single voter proceeds straight to elect().
#[test]
fn specula_trace_prevote_external_single_voter() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(1, 1));
    ev_pre_elect(&mut eng, false)
}

/// U1: responder holds a live committed leader lease: rejected, nothing changes.
#[test]
fn specula_trace_prevote_req_reject_lease() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(
        UTConfig::<()>::now(),
        Duration::from_millis(500),
        Vote::new_committed(2, 2),
    );
    let req = VoteRequest::new(Vote::new(3, 3), Some(log_id(2, 3, 5)));
    ev_handle_pre_vote_req(&mut eng, 3, req)
}

/// U1: candidate log is behind the responder: rejected, nothing changes.
#[test]
fn specula_trace_prevote_req_reject_log() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 1));
    eng.state.log_ids = LogIdList::new(None, [log_id(2, 1, 3)]);
    let req = VoteRequest::new(Vote::new(3, 2), Some(log_id(1, 2, 3)));
    ev_handle_pre_vote_req(&mut eng, 2, req)
}

/// U1: grant without any mutation: the responder keeps its (expired) committed vote.
#[test]
fn specula_trace_prevote_req_grant() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(2, 3));
    let req = VoteRequest::new(Vote::new(3, 2), Some(log_id(2, 3, 4)));
    ev_handle_pre_vote_req(&mut eng, 2, req)
}

/// U1/U3: a rejection with a longer responder log sets the greater-log flag,
/// then a grant completes the quorum and the real election starts at the probe.
#[test]
fn specula_trace_prevote_resp_reject_then_quorum() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    ev_pre_elect(&mut eng, true)?;
    drain(&mut eng);
    let probe = Vote::new(2, 1);
    ev_handle_pre_vote_resp(
        &mut eng,
        3,
        probe,
        VoteResponse::new(Vote::new_committed(1, 2), Some(log_id(1, 2, 4)), false),
    )?;
    drain(&mut eng);
    ev_handle_pre_vote_resp(&mut eng, 2, probe, VoteResponse::new(Vote::new_committed(1, 2), Some(log_id(1, 1, 1)), true))
}

/// U6: a granted real vote request of another node cancels the Pre-Vote round
/// (become_following clears pre_candidate).
#[test]
fn specula_trace_prevote_cancelled_by_vote_grant() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    ev_pre_elect(&mut eng, true)?;
    drain(&mut eng);
    let req = VoteRequest {
        vote: Vote::new(2, 3),
        last_log_id: Some(log_id(1, 1, 1)),
        leadership_transfer: false,
    };
    ev_handle_vote_req(&mut eng, 3, req)
}

/// U2: the election timer fires on a Candidate whose election is still in flight
/// and starts a Pre-Vote round; the original election then wins. The trace
/// observes the round surviving leader establishment and a late Pre-Vote grant
/// starting a new election on the established Leader.
#[test]
fn specula_trace_prevote_stale_round_after_leadership() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    // Candidate at (2,1); its own vote is durable and self-granted (runtime
    // delivered the local VoteResponse after SaveVote).
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 1));
    eng.state.server_state = ServerState::Candidate;
    eng.new_candidate(*eng.state.vote_ref());
    eng.candidate_mut().unwrap().grant_by(&1);
    eng.output.clear_commands();

    // Timer: Candidate is not a Leader and is a voter -> Pre-Vote for (3,1).
    ev_pre_elect(&mut eng, true)?;
    drain(&mut eng);

    // Delayed real vote grant from node 2 for (2,1): quorum -> Leader (2,1,committed).
    ev_handle_vote_resp(&mut eng, 2, VoteResponse::new(Vote::new(2, 1), Some(log_id(1, 1, 1)), true))?;
    drain(&mut eng);

    // Node 2 granted the Pre-Vote (3,1) while it still held the uncommitted (2,1).
    ev_handle_pre_vote_resp(&mut eng, 2, Vote::new(3, 1), VoteResponse::new(Vote::new(2, 1), Some(log_id(1, 1, 1)), true))
}

/// U4: a Pre-Vote round is cancelled by the leader's AppendEntries and a later
/// round probes the identical (term+1, self) vote; a grant for the probe
/// completes the later round.
#[test]
fn specula_trace_prevote_round_reuses_probe() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    // A short leader lease so that real time can expire it between events.
    eng.config.timer_config.leader_lease = Duration::from_millis(20);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(2, 2));
    ev_pre_elect(&mut eng, true)?;
    drain(&mut eng);
    ev_handle_append_entries(&mut eng, 2, Vote::new_committed(2, 2))?;
    drain(&mut eng);
    // The leader goes silent; its lease runs out; the timer starts a new round.
    std::thread::sleep(Duration::from_millis(100));
    ev_pre_elect(&mut eng, true)?;
    drain(&mut eng);
    ev_handle_pre_vote_resp(&mut eng, 3, Vote::new(3, 1), VoteResponse::new(Vote::new_committed(2, 2), Some(log_id(1, 1, 1)), true))
}

// ---------------------------------------------------------------------------
// Code observations (not traces): consequences that the model cannot express.
// Results are printed as one JSON line prefixed with SPECULA_OBSERVATION.
// ---------------------------------------------------------------------------

/// U2 consequence: after the late Pre-Vote quorum the node is a Candidate that
/// still holds its Leader object, so try_leader_handler (used by heartbeats and
/// client writes) violates its `leader.vote >= state.vote` assertion.
#[test]
fn specula_observe_stale_prevote_on_leader() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 1));
    eng.state.server_state = ServerState::Candidate;
    eng.new_candidate(*eng.state.vote_ref());
    eng.candidate_mut().unwrap().grant_by(&1);
    eng.output.clear_commands();

    eng.reset_greater_log();
    eng.pre_elect();
    drain(&mut eng);
    eng.handle_vote_resp(2, VoteResponse::new(Vote::new(2, 1), Some(log_id(1, 1, 1)), true));
    let leader_established = eng.state.server_state == ServerState::Leader;
    let pre_candidate_survived = eng.pre_candidate_ref().is_some();
    drain(&mut eng);
    eng.handle_pre_vote_resp(2, VoteResponse::new(Vote::new(2, 1), Some(log_id(1, 1, 1)), true));
    let server_state_after = format!("{:?}", eng.state.server_state);
    let vote_after = eng.state.vote_ref().to_string();
    let leader_object_retained = eng.leader_ref().is_some();
    let leader_vote = eng.leader_ref().map(|l| l.committed_vote_ref().to_string()).unwrap_or_default();

    let assert_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let _ = eng.try_leader_handler();
    }));
    let try_leader_handler_panicked = assert_result.is_err();
    println!(
        "SPECULA_OBSERVATION {}",
        json!({
            "observation": "stale_prevote_on_leader",
            "leader_established_while_pre_candidate_live": leader_established && pre_candidate_survived,
            "server_state_after_late_prevote_quorum": server_state_after,
            "vote_after": vote_after,
            "leader_object_retained": leader_object_retained,
            "leader_committed_vote": leader_vote,
            "try_leader_handler_panicked": try_leader_handler_panicked,
            "debug_assertions": cfg!(debug_assertions),
        })
    );
    Ok(())
}

/// U4 consequence: a granted Pre-Vote response from a node outside the current
/// round's frozen quorum set reaches Candidate::grant_by, which panics. In
/// RaftCore such a response passes the correlation check whenever an earlier
/// round with the same probed leader id asked that node.
#[test]
fn specula_observe_prevote_grant_from_non_member() -> anyhow::Result<()> {
    // Earlier round: membership {1,2,3,4}; node 4 is asked for the probe (3,1).
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3, 4}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(2, 2));
    eng.reset_greater_log();
    eng.pre_elect();
    let first_probe = eng.pre_candidate_ref().map(|p| p.vote_ref().to_string()).unwrap_or_default();
    drain(&mut eng);
    // Leader 2 contacts node 1 (cancels the round) and node 1 learns membership {1,2,3}
    // removing node 4 (follower-side membership change through replication).
    let _ = eng.append_entries(&Vote::new_committed(2, 2), LogSegment::new(eng.state.last_log_id().cloned(), vec![]));
    let new_m = stored(2, vec![btreeset! {1, 2, 3}]);
    eng.state.membership_state = MembershipState::new(new_m.clone(), new_m);
    drain(&mut eng);
    // Lease expires again: new round with the same probe.
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(2, 2));
    eng.reset_greater_log();
    eng.pre_elect();
    let second_probe = eng.pre_candidate_ref().map(|p| p.vote_ref().to_string()).unwrap_or_default();
    let same_leader_id = first_probe == second_probe;
    drain(&mut eng);
    // Node 4's delayed grant from the earlier round.
    let res = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        eng.handle_pre_vote_resp(4, VoteResponse::new(Vote::new_committed(2, 2), Some(log_id(1, 1, 1)), true));
    }));
    println!(
        "SPECULA_OBSERVATION {}",
        json!({
            "observation": "prevote_grant_from_non_member",
            "first_probe": first_probe,
            "second_probe": second_probe,
            "probe_reused": same_leader_id,
            "handle_pre_vote_resp_panicked": res.is_err(),
        })
    );
    Ok(())
}
