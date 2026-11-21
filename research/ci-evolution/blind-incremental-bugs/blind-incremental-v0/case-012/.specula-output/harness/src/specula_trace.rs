//! Neutral, environment-gated NDJSON probes for the Specula V0 prior.
//! This module is instrumentation only and is not enabled without SPECULA_TRACE.

use std::collections::BTreeMap;
use std::fmt::Display;
use std::fs::OpenOptions;
use std::io::Write;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::engine::Engine;
use crate::raft_types::LogIdOptionExt;
use crate::{LogId, Membership, NodeId};

static TRACE_LOCK: Mutex<()> = Mutex::new(());

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

    Some(format!(
        concat!(
            "{{\"term\":{},\"vote_node\":{},\"vote_committed\":{},\"role\":\"{}\",",
            "\"last_log\":{},\"logs\":[{}],\"committed\":{},",
            "\"committed_mem_index\":{},\"committed_mem_term\":{},",
            "\"effective_mem_index\":{},\"effective_mem_term\":{},",
            "\"committed_configs\":{},\"effective_configs\":{}}}"
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
    ))
}

pub(crate) fn emit_engine<NID: NodeId>(
    name: &str,
    nid: NID,
    pre: Option<String>,
    post: &Engine<NID>,
    args: String,
) {
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

fn values_json<ID: Display, V: Display>(values: &[(ID, V)]) -> String {
    values
        .iter()
        .map(|(id, value)| format!("{{\"id\":{},\"value\":{}}}", quote(id), value))
        .collect::<Vec<_>>()
        .join(",")
}

fn one_group_json<ID: Display>(ids: &[ID]) -> String {
    let ids = ids.iter().map(quote).collect::<Vec<_>>().join(",");
    format!("[[{}]]", ids)
}

pub(crate) fn emit_progress<ID: Display + Copy, V: Display + Copy>(
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
            "{{\"name\":\"ProgressUpdate\",\"nid\":{},\"configs\":{},",
            "\"pre_values\":[{}],\"post_values\":[{}],",
            "\"pre_committed\":{},\"post_committed\":{},",
            "\"args\":{{\"target\":{},\"value\":{}}}}}"
        ),
        quote(ids[0]),
        one_group_json(ids),
        values_json(pre_values),
        values_json(post_values),
        pre_committed,
        post_committed,
        quote(target),
        value,
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

pub(crate) fn emit_greatest<NID: NodeId, V: Ord + Display>(
    membership: &Membership<NID>,
    values: &BTreeMap<NID, V>,
    result: Option<&V>,
) {
    if !enabled() {
        return;
    }
    let values = values
        .iter()
        .map(|(id, value)| format!("{{\"id\":{},\"value\":{}}}", quote(id), value))
        .collect::<Vec<_>>()
        .join(",");
    let result = result.map(|v| v.to_string()).unwrap_or_else(|| "-1".to_string());
    emit(format!(
        "{{\"name\":\"GreatestMajority\",\"configs\":{},\"values\":[{}],\"result\":{}}}",
        configs_json(membership),
        values,
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
