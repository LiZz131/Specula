//! Neutral, environment-gated NDJSON probes for the Specula suite (V1 rebase).
//! This module is instrumentation only and is not enabled without SPECULA_TRACE.
//!
//! V1 changes relative to the V0 writer:
//! - Engine snapshots also capture leader data (`has_leader`, `progress`,
//!   `progress_configs`, `vote_granted`) because the updated revision keeps the
//!   replication progress and its quorum set inside `RaftState.leader`.
//! - Every event carries `depth`: the number of enclosing traced Engine actions.
//!   Engine actions now call other traced Engine actions (leader_append_entries
//!   -> update_progress / update_effective_membership), so the preprocessor keeps
//!   only top-level (`depth == 0`) events of a scenario.
//! - Progress values are formatted through `SpeculaValue` so that both the
//!   unit-test `u64` progress and the Engine's `Option<LogId>` progress compile.

use std::cell::Cell;
use std::fmt::Display;
use std::fs::OpenOptions;
use std::io::Write;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::engine::Engine;
use crate::progress::Progress;
use crate::quorum::QuorumSet;
use crate::{LogId, Membership, NodeId};

static TRACE_LOCK: Mutex<()> = Mutex::new(());

thread_local! {
    static DEPTH: Cell<u32> = Cell::new(0);
}

pub(crate) fn enabled() -> bool {
    std::env::var_os("SPECULA_TRACE").is_some() && std::env::var_os("SPECULA_TRACE_FILE").is_some()
}

fn depth() -> u32 {
    DEPTH.with(|d| d.get())
}

fn quote(value: impl Display) -> String {
    let s = value.to_string();
    let escaped = s.replace('\\', "\\\\").replace('"', "\\\"");
    format!("\"{}\"", escaped)
}

fn emit(event_json: String) {
    if !enabled() {
        return;
    }

    let path = match std::env::var("SPECULA_TRACE_FILE") {
        Ok(path) => path,
        Err(_) => return,
    };
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or_default();
    let line = format!("{{\"tag\":\"trace\",\"ts\":\"{}\",\"event\":{}}}\n", ts, event_json);

    let _guard = TRACE_LOCK.lock().expect("Specula trace mutex poisoned");
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = file.write_all(line.as_bytes());
        let _ = file.flush();
    }
}

/// Value formatting for progress probes.
pub(crate) trait SpeculaValue {
    fn specula_index(&self) -> String;
}

impl SpeculaValue for u64 {
    fn specula_index(&self) -> String {
        self.to_string()
    }
}

impl<NID: NodeId> SpeculaValue for Option<LogId<NID>> {
    fn specula_index(&self) -> String {
        match self {
            None => "-1".to_string(),
            Some(l) => l.index.to_string(),
        }
    }
}

pub(crate) fn configs_json<NID: NodeId>(membership: &Membership<NID>) -> String {
    let groups = membership
        .get_joint_config()
        .iter()
        .map(|group| {
            let ids = group.iter().map(|id| quote(id)).collect::<Vec<_>>().join(",");
            format!("[{}]", ids)
        })
        .collect::<Vec<_>>()
        .join(",");
    format!("[{}]", groups)
}

pub(crate) fn option_log_parts<NID: NodeId>(log_id: Option<LogId<NID>>) -> (i64, u64) {
    match log_id {
        None => (-1, 0),
        Some(id) => (id.index as i64, id.leader_id.term),
    }
}

pub(crate) fn capture_engine<NID: NodeId>(engine: &Engine<NID>) -> Option<String> {
    if !enabled() {
        return None;
    }

    let (last_index, _) = option_log_parts(engine.state.last_log_id());
    let logs = if last_index < 0 {
        String::new()
    } else {
        (0..=last_index as u64)
            .map(|idx| engine.state.get_log_id(idx).map(|id| id.leader_id.term).unwrap_or(0).to_string())
            .collect::<Vec<_>>()
            .join(",")
    };
    let (committed_index, _) = option_log_parts(engine.state.committed);
    let (committed_mem_index, committed_mem_term) =
        option_log_parts(engine.state.membership_state.committed.log_id);
    let (effective_mem_index, effective_mem_term) =
        option_log_parts(engine.state.membership_state.effective.log_id);
    let role = match engine.state.server_state {
        crate::ServerState::Leader => "leader",
        crate::ServerState::Candidate => "candidate",
        crate::ServerState::Follower => "follower",
        crate::ServerState::Learner => "learner",
        crate::ServerState::Shutdown => "follower",
    };

    // V1 leader data: RaftState.leader = Some(Leader{vote_granted_by, progress}).
    let (has_leader, progress, progress_configs, vote_granted) = match &engine.state.leader {
        None => (false, String::new(), "[]".to_string(), String::new()),
        Some(leader) => {
            let qs = leader.progress.quorum_set();
            let progress = qs
                .ids()
                .map(|id| {
                    let (index, term) = option_log_parts(*leader.progress.get(&id));
                    format!("{{\"id\":{},\"index\":{},\"term\":{}}}", quote(id), index, term)
                })
                .collect::<Vec<_>>()
                .join(",");
            let granted = leader.vote_granted_by.iter().map(quote).collect::<Vec<_>>().join(",");
            (true, progress, configs_json(&qs.membership), granted)
        }
    };

    Some(format!(
        concat!(
            "{{\"term\":{},\"vote_node\":{},\"vote_committed\":{},\"role\":\"{}\",",
            "\"last_log\":{},\"logs\":[{}],\"committed\":{},",
            "\"committed_mem_index\":{},\"committed_mem_term\":{},",
            "\"effective_mem_index\":{},\"effective_mem_term\":{},",
            "\"committed_configs\":{},\"effective_configs\":{},",
            "\"has_leader\":{},\"progress\":[{}],\"progress_configs\":{},\"vote_granted\":[{}]}}"
        ),
        engine.state.vote.term,
        quote(engine.state.vote.node_id),
        engine.state.vote.committed,
        role,
        last_index,
        logs,
        committed_index,
        committed_mem_index,
        committed_mem_term,
        effective_mem_index,
        effective_mem_term,
        configs_json(&engine.state.membership_state.committed.membership),
        configs_json(&engine.state.membership_state.effective.membership),
        has_leader,
        progress,
        progress_configs,
        vote_granted,
    ))
}

/// One traced Engine action: pre-state captured on entry, nesting depth
/// recorded, depth restored on drop (also on early returns without emission).
pub(crate) struct Scope {
    pre: Option<String>,
    depth: u32,
}

impl Drop for Scope {
    fn drop(&mut self) {
        DEPTH.with(|d| d.set(self.depth));
    }
}

pub(crate) fn scope<NID: NodeId>(engine: &Engine<NID>) -> Scope {
    let d = depth();
    let pre = capture_engine(engine);
    DEPTH.with(|x| x.set(d + 1));
    Scope { pre, depth: d }
}

impl Scope {
    pub(crate) fn emit<NID: NodeId>(&self, name: &str, nid: NID, post: &Engine<NID>, args: String) {
        let pre = match &self.pre {
            Some(pre) => pre,
            None => return,
        };
        let post = capture_engine(post).expect("trace enabled after pre-state capture");
        emit(format!(
            "{{\"name\":\"{}\",\"depth\":{},\"nid\":{},\"pre\":{},\"post\":{},\"args\":{}}}",
            name,
            self.depth,
            quote(nid),
            pre,
            post,
            args
        ));
    }
}

fn values_json<ID: Display, V: SpeculaValue>(values: &[(ID, V)]) -> String {
    values
        .iter()
        .map(|(id, value)| format!("{{\"id\":{},\"value\":{}}}", quote(id), value.specula_index()))
        .collect::<Vec<_>>()
        .join(",")
}

fn one_group_json<ID: Display>(ids: &[ID]) -> String {
    let ids = ids.iter().map(quote).collect::<Vec<_>>().join(",");
    format!("[[{}]]", ids)
}

pub(crate) fn emit_progress<ID: Display + Copy, V: SpeculaValue + Copy>(
    ids: &[ID],
    target: ID,
    value: V,
    pre_values: &[(ID, V)],
    post_values: &[(ID, V)],
    pre_committed: V,
    post_committed: V,
) {
    if !enabled() || ids.is_empty() {
        return;
    }
    emit(format!(
        concat!(
            "{{\"name\":\"ProgressUpdate\",\"depth\":{},\"nid\":{},\"configs\":{},",
            "\"pre_values\":[{}],\"post_values\":[{}],",
            "\"pre_committed\":{},\"post_committed\":{},",
            "\"args\":{{\"target\":{},\"value\":{}}}}}"
        ),
        depth(),
        quote(ids[0]),
        one_group_json(ids),
        values_json(pre_values),
        values_json(post_values),
        pre_committed.specula_index(),
        post_committed.specula_index(),
        quote(target),
        value.specula_index(),
    ));
}

pub(crate) fn emit_quorum<NID: NodeId>(membership: &Membership<NID>, granted: &[NID], result: bool) {
    if !enabled() {
        return;
    }
    let granted = granted.iter().map(quote).collect::<Vec<_>>().join(",");
    emit(format!(
        "{{\"name\":\"QuorumCheck\",\"depth\":{},\"configs\":{},\"granted\":[{}],\"result\":{}}}",
        depth(),
        configs_json(membership),
        granted,
        result
    ));
}

pub(crate) fn emit_replication_lag(matched_index: i64, last_index: i64, threshold: u64, result: bool) {
    if !enabled() {
        return;
    }
    emit(format!(
        concat!(
            "{{\"name\":\"ReplicationLagCheck\",\"depth\":{},\"matched_index\":{},",
            "\"last_index\":{},\"threshold\":{},\"result\":{}}}"
        ),
        depth(),
        matched_index,
        last_index,
        threshold,
        result
    ));
}
