//! Specula update harness: RaftCore-level trace capture.
//!
//! Runtime-gated: does nothing unless `SPECULA_CORE_TRACE_DIR` is set. Installed by
//! `harness/apply.sh` into `openraft/src/core/` and wired into `RaftCore` at the
//! `RaftMsg::TransferLeader` arm, `handle_vote_request` and the `Notification::VoteResponse`
//! arm. Each probe captures the synchronous Engine state inside the single RaftCore task, so
//! pre/post snapshots of one handler cannot interleave with other inputs.
//!
//! A *session* is one NDJSON file per node. It starts with `Bootstrap` (pre-state) when that
//! node handles a `TransferLeader` message and continues with later instrumented events of the
//! same node only while the node's pre-state equals the last emitted post-state, i.e. no
//! uninstrumented input changed captured state in between. Otherwise the session is closed.
//!
//! Node ids are mapped to model ids `id + 1` (model `NoNode = 0`); a vote/log leader id with
//! term 0 maps to `NoNode` (it is `Vote::default()` / `LogId::default()`).

use std::collections::BTreeMap;
use std::collections::BTreeSet;
use std::fmt::Display;
use std::fs::File;
use std::io::Write;
use std::sync::Mutex;
use std::sync::OnceLock;
use std::time::SystemTime;
use std::time::UNIX_EPOCH;

use crate::engine::Command;
use crate::engine::Engine;
use crate::progress::Progress;
use crate::raft_state::LogStateReader;
use crate::LogId;
use crate::RaftTypeConfig;
use crate::Vote;

struct Session {
    out: File,
    last_state: String,
}

struct Registry {
    dir: String,
    seq: u64,
    last_ts: u128,
    sessions: BTreeMap<String, Session>,
}

fn registry() -> Option<&'static Mutex<Registry>> {
    static R: OnceLock<Option<Mutex<Registry>>> = OnceLock::new();
    R.get_or_init(|| {
        std::env::var("SPECULA_CORE_TRACE_DIR").ok().map(|dir| {
            Mutex::new(Registry {
                dir,
                seq: 0,
                last_ts: 0,
                sessions: BTreeMap::new(),
            })
        })
    })
    .as_ref()
}

/// Map an implementation node id to a model id (`id + 1`).
fn nid(id: &impl Display) -> String {
    let s = id.to_string();
    match s.parse::<u64>() {
        Ok(x) => (x + 1).to_string(),
        Err(_) => format!("\"{}\"", s),
    }
}

/// Map a leader-id node of a vote/log id; term 0 is the default id -> NoNode (0).
fn leader_node(term: u64, id: &impl Display) -> String {
    if term == 0 {
        "0".to_string()
    } else {
        nid(id)
    }
}

fn command_name<C: RaftTypeConfig>(cmd: &Command<C>) -> &'static str {
    match cmd {
        Command::UpdateIOProgress { .. } => "UpdateIOProgress",
        Command::AppendInputEntries { .. } => "AppendInputEntries",
        Command::ReplicateCommitted { .. } => "ReplicateCommitted",
        Command::SaveCommitted { .. } => "SaveCommitted",
        Command::Apply { .. } => "Apply",
        Command::Replicate { .. } => "Replicate",
        Command::RebuildReplicationStreams { .. } => "RebuildReplicationStreams",
        Command::SaveVote { .. } => "SaveVote",
        Command::SendVote { .. } => "SendVote",
        Command::PurgeLog { .. } => "PurgeLog",
        Command::TruncateLog { .. } => "TruncateLog",
        Command::StateMachine { .. } => "StateMachine",
        Command::Respond { .. } => "Respond",
    }
}

fn idx<NID: crate::NodeId>(log_id: Option<&LogId<NID>>) -> i64 {
    log_id.map(|x| x.index as i64).unwrap_or(-1)
}

fn ids<I: Iterator<Item = String>>(it: I) -> String {
    let v: Vec<String> = it.collect();
    format!("[{}]", v.join(","))
}

/// Strong post-state capture; same field set as the Engine unit harness
/// (`engine/specula_trace_tests.rs::capture`), with node ids mapped.
/// `skip`: number of queued commands that predate the current handler (condition-blocked
/// commands such as `Respond` stay queued across inputs); only commands queued by the current
/// handler are reported, matching the model's per-action `commands'`.
fn capture<C: RaftTypeConfig>(id: &C::NodeId, eng: &Engine<C>, skip: usize) -> String {
    let vote = eng.state.vote_ref();
    let seen = &eng.last_seen_vote;
    let effective = eng.state.membership_state.effective();
    let committed_membership = eng.state.membership_state.committed();
    let last_index = eng.state.last_log_id().map(|x| x.index as i64).unwrap_or(-1);

    let mut logs = Vec::new();
    if last_index >= 0 {
        for i in 0..=(last_index as u64) {
            match eng.state.get_log_id(i) {
                Some(x) => logs.push(format!(
                    "{{\"term\":{},\"node\":{},\"index\":{}}}",
                    x.leader_id.term,
                    leader_node(x.leader_id.term, &x.leader_id.node_id),
                    x.index
                )),
                None => logs.push(format!("{{\"term\":-1,\"node\":-1,\"index\":{}}}", i)),
            }
        }
    }

    let configs = effective
        .membership()
        .get_joint_config()
        .iter()
        .map(|c| ids(c.iter().map(nid)))
        .collect::<Vec<_>>();
    let learners = ids(effective.membership().learner_ids().map(|x| nid(&x)));
    let granters = ids(eng.candidate_ref().map(|c| c.granters().map(|x| nid(&x)).collect::<Vec<_>>()).unwrap_or_default().into_iter());
    let matches = eng
        .leader_ref()
        .map(|l| {
            l.progress
                .iter()
                .map(|(peer, p)| format!("{{\"peer\":{},\"index\":{}}}", nid(peer), idx(p.matching.as_ref())))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let commands = eng
        .output
        .iter_commands()
        .skip(skip)
        .map(command_name)
        .collect::<BTreeSet<_>>()
        .into_iter()
        .map(|x| format!("\"{}\"", x));
    let (accepted_kind, accepted_index) = match eng.state.accepted_io() {
        None => ("none", -1),
        Some(io) => match io.last_log_id() {
            Some(l) => ("log", l.index as i64),
            None => ("vote", -1),
        },
    };

    format!(
        concat!(
            "{{\"node_id\":{},\"vote_term\":{},\"vote_node\":{},\"vote_committed\":{},",
            "\"last_seen_term\":{},\"last_seen_node\":{},\"last_seen_committed\":{},",
            "\"role\":\"{:?}\",\"logs\":[{}],\"last_index\":{},\"commit_index\":{},",
            "\"effective_index\":{},\"committed_membership_index\":{},",
            "\"effective_configs\":[{}],\"learners\":{},\"candidate\":{},\"granters\":{},",
            "\"leader\":{},\"matches\":[{}],\"accepted_index\":{},\"accepted_kind\":\"{}\",",
            "\"commands\":[{}]}}"
        ),
        nid(id),
        vote.leader_id.term,
        leader_node(vote.leader_id.term, &vote.leader_id.node_id),
        vote.committed,
        seen.leader_id.term,
        leader_node(seen.leader_id.term, &seen.leader_id.node_id),
        seen.committed,
        eng.state.server_state,
        logs.join(","),
        last_index,
        idx(eng.state.committed()),
        idx(effective.log_id().as_ref()),
        idx(committed_membership.log_id().as_ref()),
        configs.join(","),
        learners,
        eng.candidate_ref().is_some(),
        granters,
        eng.leader_ref().is_some(),
        matches.join(","),
        accepted_index,
        accepted_kind,
        commands.collect::<Vec<_>>().join(","),
    )
}

fn strip_commands(state: &str) -> &str {
    match state.find(",\"commands\":[") {
        Some(i) => &state[..i],
        None => state,
    }
}

fn now_ts(reg: &mut Registry) -> u128 {
    let observed = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    let ts = std::cmp::max(observed, reg.last_ts + 1);
    reg.last_ts = ts;
    ts
}

fn write_line(reg: &mut Registry, key: &str, name: &str, node: &str, args: &str, state: &str) {
    let ts = now_ts(reg);
    let line = format!(
        "{{\"tag\":\"trace\",\"ts\":\"{}\",\"event\":{{\"name\":\"{}\",\"node\":{},\"args\":{},\"state\":{}}}}}\n",
        ts, name, node, args, state
    );
    if let Some(s) = reg.sessions.get_mut(key) {
        let _ = s.out.write_all(line.as_bytes());
        let _ = s.out.flush();
    }
}

/// Probe at handler entry. Returns `Some(queue_len)` when the handler's post-state may be
/// emitted. `start` = the handler may open a new session (only the TransferLeader arm does).
pub(crate) fn pre<C: RaftTypeConfig>(id: &C::NodeId, eng: &Engine<C>, start: bool) -> Option<usize> {
    let reg = registry()?;
    let mut reg = reg.lock().unwrap();
    let key = nid(id);
    let queued = eng.output.iter_commands().count();
    let state = capture(id, eng, queued);
    // `commands` is the queue left by the previous handler; RaftCore drains it between inputs
    // (modeled by PersistVote / SendVoteRequests / Submit..., which change no other captured
    // field), so it is excluded from the contiguity comparison.
    let contiguous = reg.sessions.get(&key).map(|s| strip_commands(&s.last_state) == strip_commands(&state)).unwrap_or(false);
    if contiguous {
        return Some(queued);
    }
    // Uninstrumented input changed captured state (or no session yet): close.
    reg.sessions.remove(&key);
    if !start {
        return None;
    }
    reg.seq += 1;
    let path = format!("{}/transfer-n{}-{:03}.ndjson", reg.dir, key, reg.seq);
    let Ok(out) = File::create(&path) else { return None };
    reg.sessions.insert(key.clone(), Session {
        out,
        last_state: state.clone(),
    });
    write_line(&mut reg, &key, "Bootstrap", &key, "{}", &state);
    Some(queued)
}

/// Probe at handler exit: emit the post-state if the session is live.
pub(crate) fn post<C: RaftTypeConfig>(id: &C::NodeId, eng: &Engine<C>, skip: usize, name: &str, args: String) {
    let Some(reg) = registry() else { return };
    let mut reg = reg.lock().unwrap();
    let key = nid(id);
    if !reg.sessions.contains_key(&key) {
        return;
    }
    let state = capture(id, eng, skip);
    write_line(&mut reg, &key, name, &key, &args, &state);
    if let Some(s) = reg.sessions.get_mut(&key) {
        s.last_state = state;
    }
}

pub(crate) fn transfer_args<NID: crate::NodeId>(from: &Vote<NID>, to: &NID) -> String {
    format!(
        "{{\"from_term\":{},\"from_node\":{},\"from_committed\":{},\"to\":{}}}",
        from.leader_id.term,
        leader_node(from.leader_id.term, &from.leader_id.node_id),
        from.committed,
        nid(to)
    )
}

pub(crate) fn vote_request_args<NID: crate::NodeId>(vote: &Vote<NID>, last: Option<&LogId<NID>>) -> String {
    let (lt, ln, li) = match last {
        Some(l) => (
            l.leader_id.term,
            leader_node(l.leader_id.term, &l.leader_id.node_id),
            l.index as i64,
        ),
        None => (0, "0".to_string(), -1),
    };
    format!(
        "{{\"candidate\":{},\"term\":{},\"committed\":{},\"last_term\":{},\"last_node\":{},\"last_index\":{}}}",
        leader_node(vote.leader_id.term, &vote.leader_id.node_id),
        vote.leader_id.term,
        vote.committed,
        lt,
        ln,
        li
    )
}

pub(crate) fn vote_response_args<NID: crate::NodeId>(peer: &NID, vote: &Vote<NID>) -> String {
    format!(
        "{{\"peer\":{},\"term\":{},\"owner\":{},\"committed\":{}}}",
        nid(peer),
        vote.leader_id.term,
        leader_node(vote.leader_id.term, &vote.leader_id.node_id),
        vote.committed
    )
}

#[allow(dead_code)]
/// Drop every session (called by the scenario at the end; files are already flushed).
pub(crate) fn close_all() {
    if let Some(reg) = registry() {
        reg.lock().unwrap().sessions.clear();
    }
}
