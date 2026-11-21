//! Neutral, environment-gated NDJSON probes for the Specula incremental run.
//! This module is instrumentation only and is not enabled without SPECULA_TRACE.
//!
//! Rebased from the V0 prior harness. Changes relative to the prior module:
//! - every event carries a `depth` field (nesting level of instrumented calls on
//!   the current thread) so the preprocessor can keep only the outermost call;
//! - VecProgress values / quorum sets are rendered through `Any` downcasting,
//!   so no production trait bound is changed (the prior `Display` bounds no
//!   longer compile because the leader progress uses `Option<LogId<NID>>`);
//! - Engine snapshots include the leader `VecProgress` (vector order, cached
//!   committed value, quorum set) introduced by the update.

use std::any::Any;
use std::cell::Cell;
use std::fmt::Debug;
use std::fmt::Display;
use std::fs::OpenOptions;
use std::io::Write;
use std::sync::Arc;
use std::sync::Mutex;
use std::time::SystemTime;
use std::time::UNIX_EPOCH;

use crate::engine::Engine;
use crate::quorum::Joint;
use crate::EffectiveMembership;
use crate::LogId;
use crate::Membership;
use crate::NodeId;

static TRACE_LOCK: Mutex<()> = Mutex::new(());

thread_local! {
    static DEPTH: Cell<usize> = Cell::new(0);
}

/// RAII nesting guard. Create one at the entry of each instrumented function.
pub(crate) struct Enter;

pub(crate) fn enter() -> Enter {
    DEPTH.with(|d| d.set(d.get() + 1));
    Enter
}

impl Drop for Enter {
    fn drop(&mut self) {
        DEPTH.with(|d| d.set(d.get().saturating_sub(1)));
    }
}

fn depth() -> usize {
    DEPTH.with(|d| d.get()).saturating_sub(1)
}

pub(crate) fn enabled() -> bool {
    std::env::var_os("SPECULA_TRACE").is_some() && std::env::var_os("SPECULA_TRACE_FILE").is_some()
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
    let ts = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or_default();
    let line = format!(
        "{{\"tag\":\"trace\",\"ts\":\"{}\",\"depth\":{},\"event\":{}}}\n",
        ts,
        depth(),
        event_json
    );

    let _guard = TRACE_LOCK.lock().expect("Specula trace mutex poisoned");
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = file.write_all(line.as_bytes());
        let _ = file.flush();
    }
}

pub(crate) fn configs_json<NID: NodeId>(membership: &Membership<NID>) -> String {
    let groups = membership
        .get_joint_config()
        .iter()
        .map(|group| {
            let ids = group.iter().map(quote).collect::<Vec<_>>().join(",");
            format!("[{}]", ids)
        })
        .collect::<Vec<_>>()
        .join(",");
    format!("[{}]", groups)
}

/// Render a progress value. `u64` values come from the VecProgress unit tests;
/// `Option<LogId<u64>>` values come from the Engine leader progress.
pub(crate) fn value_json<V: 'static>(v: &V) -> String {
    let any = v as &dyn Any;
    if let Some(x) = any.downcast_ref::<u64>() {
        return format!("{{\"kind\":\"raw\",\"raw\":{}}}", x);
    }
    if let Some(x) = any.downcast_ref::<Option<LogId<u64>>>() {
        return log_value_json(x);
    }
    "{\"kind\":\"unknown\"}".to_string()
}

fn log_value_json(x: &Option<LogId<u64>>) -> String {
    match x {
        None => "{\"kind\":\"none\"}".to_string(),
        Some(l) => format!(
            "{{\"kind\":\"log\",\"t\":{},\"n\":{},\"i\":{}}}",
            l.leader_id.term,
            quote(l.leader_id.node_id),
            l.index
        ),
    }
}

/// Render a quorum set as a list of groups.
pub(crate) fn qs_json<QS: 'static>(qs: &QS) -> String {
    let any = qs as &dyn Any;
    if let Some(v) = any.downcast_ref::<Vec<u64>>() {
        let ids = v.iter().map(quote).collect::<Vec<_>>().join(",");
        return format!("[[{}]]", ids);
    }
    if let Some(j) = any.downcast_ref::<Joint<u64, Vec<u64>, Vec<Vec<u64>>>>() {
        let groups = j
            .children()
            .iter()
            .map(|g| format!("[{}]", g.iter().map(quote).collect::<Vec<_>>().join(",")))
            .collect::<Vec<_>>()
            .join(",");
        return format!("[{}]", groups);
    }
    if let Some(em) = any.downcast_ref::<Arc<EffectiveMembership<u64>>>() {
        return configs_json(&em.membership);
    }
    "[]".to_string()
}

pub(crate) fn vector_json<ID: Debug, V: 'static>(vector: &[(ID, V)]) -> String {
    vector
        .iter()
        .map(|(id, v)| format!("{{\"id\":{},\"value\":{}}}", quote(format!("{:?}", id)), value_json(v)))
        .collect::<Vec<_>>()
        .join(",")
}

/// Snapshot of one VecProgress: vector (in order), cached committed, quorum set.
pub(crate) fn progress_parts_json<ID: Debug, V: 'static, QS: 'static>(
    vector: &[(ID, V)],
    committed: &V,
    qs: &QS,
) -> String {
    format!(
        "{{\"vector\":[{}],\"committed\":{},\"qs\":{}}}",
        vector_json(vector),
        value_json(committed),
        qs_json(qs)
    )
}

fn option_log_parts<NID: NodeId>(log_id: Option<LogId<NID>>) -> (i64, u64) {
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
    let (committed_index, committed_term) = option_log_parts(engine.state.committed);
    let (committed_mem_index, committed_mem_term) = option_log_parts(engine.state.membership_state.committed.log_id);
    let (effective_mem_index, effective_mem_term) = option_log_parts(engine.state.membership_state.effective.log_id);
    let role = match engine.state.server_state {
        crate::ServerState::Leader => "leader",
        crate::ServerState::Candidate => "candidate",
        crate::ServerState::Follower => "follower",
        crate::ServerState::Learner => "learner",
        crate::ServerState::Shutdown => "follower",
    };

    let (leader_some, progress) = match &engine.state.leader {
        None => (false, "{\"vector\":[],\"committed\":{\"kind\":\"none\"},\"qs\":[]}".to_string()),
        Some(l) => {
            let (vector, committed, qs) = l.progress.specula_parts();
            (true, progress_parts_json(vector, committed, qs))
        }
    };
    let granted = match &engine.state.leader {
        None => String::new(),
        Some(l) => l.vote_granted_by.iter().map(quote).collect::<Vec<_>>().join(","),
    };

    Some(format!(
        concat!(
            "{{\"term\":{},\"vote_node\":{},\"vote_committed\":{},\"role\":\"{}\",",
            "\"last_log\":{},\"logs\":[{}],\"committed\":{},\"committed_term\":{},",
            "\"committed_mem_index\":{},\"committed_mem_term\":{},",
            "\"effective_mem_index\":{},\"effective_mem_term\":{},",
            "\"committed_configs\":{},\"effective_configs\":{},",
            "\"leader_some\":{},\"vote_granted\":[{}],\"progress\":{}}}"
        ),
        engine.state.vote.term,
        quote(engine.state.vote.node_id),
        engine.state.vote.committed,
        role,
        last_index,
        logs,
        committed_index,
        committed_term,
        committed_mem_index,
        committed_mem_term,
        effective_mem_index,
        effective_mem_term,
        configs_json(&engine.state.membership_state.committed.membership),
        configs_json(&engine.state.membership_state.effective.membership),
        leader_some,
        granted,
        progress,
    ))
}

pub(crate) fn emit_engine<NID: NodeId>(name: &str, nid: NID, pre: Option<String>, post: &Engine<NID>, args: String) {
    let pre = match pre {
        Some(pre) => pre,
        None => return,
    };
    let post = capture_engine(post).expect("trace enabled after pre-state capture");
    emit(format!(
        "{{\"name\":\"{}\",\"nid\":{},\"pre\":{},\"post\":{},\"args\":{}}}",
        name,
        quote(nid),
        pre,
        post,
        args
    ));
}

/// VecProgress::update probe. `pre`/`post` come from `progress_parts_json`.
pub(crate) fn emit_progress_update<ID: Debug, V: 'static>(target: &ID, value: &V, pre: Option<String>, post: String) {
    let pre = match pre {
        Some(pre) => pre,
        None => return,
    };
    emit(format!(
        "{{\"name\":\"ProgressUpdate\",\"nid\":\"0\",\"pre\":{},\"post\":{},\"args\":{{\"target\":{},\"value\":{}}}}}",
        pre,
        post,
        quote(format!("{:?}", target)),
        value_json(value)
    ));
}

/// VecProgress::upgrade_quorum_set probe.
pub(crate) fn emit_progress_upgrade(pre: Option<String>, post: String, new_qs: String) {
    let pre = match pre {
        Some(pre) => pre,
        None => return,
    };
    emit(format!(
        "{{\"name\":\"ProgressUpgrade\",\"nid\":\"0\",\"pre\":{},\"post\":{},\"args\":{{\"qs\":{}}}}}",
        pre, post, new_qs
    ));
}

pub(crate) fn emit_quorum<NID: NodeId>(membership: &Membership<NID>, granted: &[NID], result: bool) {
    if !enabled() {
        return;
    }
    let granted = granted.iter().map(quote).collect::<Vec<_>>().join(",");
    emit(format!(
        "{{\"name\":\"QuorumCheck\",\"configs\":{},\"granted\":[{}],\"result\":{}}}",
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
            "{{\"name\":\"ReplicationLagCheck\",\"matched_index\":{},",
            "\"last_index\":{},\"threshold\":{},\"result\":{}}}"
        ),
        matched_index, last_index, threshold, result
    ));
}

pub(crate) fn log_id_json<NID: NodeId>(log_id: &Option<LogId<NID>>) -> String {
    match log_id {
        None => "{\"kind\":\"none\"}".to_string(),
        Some(l) => format!(
            "{{\"kind\":\"log\",\"t\":{},\"n\":{},\"i\":{}}}",
            l.leader_id.term,
            quote(l.leader_id.node_id),
            l.index
        ),
    }
}
