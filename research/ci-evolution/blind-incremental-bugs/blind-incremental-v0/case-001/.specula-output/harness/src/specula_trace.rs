//! Low-overhead, opt-in transition tracing used by the Specula V0 harness.
//!
//! The module is inert unless `SPECULA_TRACE` names an output file and
//! `SPECULA_EVENT_FILTER` contains the event name.  It deliberately uses only
//! `std` so the probe does not alter OpenRaft's feature surface.

use std::fmt;
use std::fs::OpenOptions;
use std::io::Write;
use std::sync::Mutex;
use std::sync::OnceLock;
use std::time::SystemTime;
use std::time::UNIX_EPOCH;

use crate::RaftTypeConfig;
use crate::engine::Engine;
use crate::raft_state::LogStateReader;
use crate::vote::RaftLeaderId;
use crate::vote::RaftVote;

static WRITE_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

#[derive(Clone, Debug)]
pub(crate) struct Snapshot {
    nid: u64,
    term: u64,
    vote_node: u64,
    vote_committed: bool,
    role: &'static str,
    log_len: u64,
    commit_len: u64,
    candidate: bool,
    grants: u64,
    voters: u64,
    self_voter: bool,
    io_accepted: u64,
    io_submitted: u64,
    io_flushed: u64,
    io_accepted_term: u64,
    io_submitted_term: u64,
    io_flushed_term: u64,
}

#[derive(Clone, Debug, Default)]
pub(crate) struct Args {
    pub(crate) incoming_term: u64,
    pub(crate) incoming_node: u64,
    pub(crate) entry_count: u64,
    pub(crate) prev_len: u64,
    pub(crate) target: u64,
    pub(crate) granted: bool,
}

fn as_u64(v: impl fmt::Display) -> u64 {
    v.to_string().parse::<u64>().unwrap_or(0)
}

fn role_name(role: &crate::core::ServerState) -> &'static str {
    match role {
        crate::core::ServerState::Learner => "Learner",
        crate::core::ServerState::Follower => "Follower",
        crate::core::ServerState::Candidate => "Candidate",
        crate::core::ServerState::Leader => "Leader",
        crate::core::ServerState::Shutdown => "Shutdown",
    }
}

fn io_len<C: RaftTypeConfig>(io: Option<&crate::raft_state::IOId<C>>) -> u64 {
    io.and_then(|x| x.last_log_id()).map(|x| x.index() + 1).unwrap_or(0)
}

fn io_term<C: RaftTypeConfig>(io: Option<&crate::raft_state::IOId<C>>) -> u64 {
    io.map(|x| as_u64(x.as_ref_vote().leader_id.term())).unwrap_or(0)
}

pub(crate) fn snapshot<C: RaftTypeConfig>(eng: &Engine<C>) -> Snapshot {
    let vote = eng.state.vote_ref();
    let effective = eng.state.membership_state.effective();
    Snapshot {
        nid: as_u64(&eng.config.id),
        term: as_u64(vote.leader_id().term()),
        vote_node: as_u64(vote.leader_id().node_id()),
        vote_committed: vote.is_committed(),
        role: role_name(&eng.state.server_state),
        log_len: eng.state.last_log_id().map(|x| x.index() + 1).unwrap_or(0),
        commit_len: eng.state.committed().map(|x| x.index() + 1).unwrap_or(0),
        candidate: eng.candidate_ref().is_some(),
        grants: eng
            .candidate_ref()
            .map(|x| x.granters().count() as u64)
            .unwrap_or(0),
        voters: effective.voter_ids().count() as u64,
        self_voter: effective.is_voter(&eng.config.id),
        io_accepted: io_len(eng.state.log_progress().accepted()),
        io_submitted: io_len(eng.state.log_progress().submitted()),
        io_flushed: io_len(eng.state.log_progress().flushed()),
        io_accepted_term: io_term(eng.state.log_progress().accepted()),
        io_submitted_term: io_term(eng.state.log_progress().submitted()),
        io_flushed_term: io_term(eng.state.log_progress().flushed()),
    }
}

fn selected(name: &str) -> Option<String> {
    let path = std::env::var("SPECULA_TRACE").ok()?;
    let filter = std::env::var("SPECULA_EVENT_FILTER").unwrap_or_default();
    if filter.split(',').any(|x| x.trim() == name) {
        Some(path)
    } else {
        None
    }
}

fn snapshot_json(s: &Snapshot) -> String {
    format!(
        "{{\"term\":{},\"voteNode\":{},\"voteCommitted\":{},\"role\":\"{}\",\"logLen\":{},\"commitLen\":{},\"candidate\":{},\"grants\":{},\"voters\":{},\"selfVoter\":{},\"ioAccepted\":{},\"ioSubmitted\":{},\"ioFlushed\":{},\"ioAcceptedTerm\":{},\"ioSubmittedTerm\":{},\"ioFlushedTerm\":{}}}",
        s.term,
        s.vote_node,
        s.vote_committed,
        s.role,
        s.log_len,
        s.commit_len,
        s.candidate,
        s.grants,
        s.voters,
        s.self_voter,
        s.io_accepted,
        s.io_submitted,
        s.io_flushed,
        s.io_accepted_term,
        s.io_submitted_term,
        s.io_flushed_term,
    )
}

pub(crate) fn emit(name: &str, before: Snapshot, after: Snapshot, args: Args) {
    let Some(path) = selected(name) else { return };
    let _guard = WRITE_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
    let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
    let line = format!(
        "{{\"tag\":\"trace\",\"ts\":\"{}\",\"event\":{{\"name\":\"{}\",\"nid\":{},\"before\":{},\"state\":{},\"args\":{{\"incomingTerm\":{},\"incomingNode\":{},\"entryCount\":{},\"prevLen\":{},\"target\":{},\"granted\":{}}}}}}}\n",
        ts,
        name,
        before.nid,
        snapshot_json(&before),
        snapshot_json(&after),
        args.incoming_term,
        args.incoming_node,
        args.entry_count,
        args.prev_len,
        args.target,
        args.granted,
    );
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = file.write_all(line.as_bytes());
        let _ = file.flush();
    }
}

fn scalar(v: Option<String>) -> u64 {
    v.and_then(|x| x.parse::<u64>().ok()).unwrap_or(0)
}

pub(crate) fn emit_io(
    name: &str,
    accepted_before: Option<String>,
    submitted_before: Option<String>,
    flushed_before: Option<String>,
    accepted_after: Option<String>,
    submitted_after: Option<String>,
    flushed_after: Option<String>,
) {
    if selected(name).is_none() {
        return;
    }
    let mk = |accepted, submitted, flushed| Snapshot {
        nid: 1,
        term: 0,
        vote_node: 0,
        vote_committed: false,
        role: "Follower",
        log_len: 0,
        commit_len: 0,
        candidate: false,
        grants: 0,
        voters: 1,
        self_voter: true,
        io_accepted: accepted,
        io_submitted: submitted,
        io_flushed: flushed,
        io_accepted_term: 0,
        io_submitted_term: 0,
        io_flushed_term: 0,
    };
    emit(
        name,
        mk(
            scalar(accepted_before),
            scalar(submitted_before),
            scalar(flushed_before),
        ),
        mk(
            scalar(accepted_after),
            scalar(submitted_after),
            scalar(flushed_after),
        ),
        Args::default(),
    );
}
