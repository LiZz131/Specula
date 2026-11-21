//! Neutral, environment-gated NDJSON probes for the Specula incremental suite.
//! This module is instrumentation only and is not enabled without SPECULA_TRACE.
//! Rebased from the V0 prior onto the updated revision: the Engine snapshot
//! now includes the Engine leader state (VecProgress order/values/committed),
//! and VecProgress probes are generic over the value and quorum-set types used
//! by the updated code (u64 test values and Option<LogId>; Vec, Joint and
//! Arc<EffectiveMembership> quorum sets).

use std::fmt::Display;
use std::fs::OpenOptions;
use std::io::Write;
use std::sync::Arc;
use std::sync::Mutex;
use std::time::SystemTime;
use std::time::UNIX_EPOCH;

use crate::engine::Engine;
use crate::progress::Progress;
use crate::quorum::Joint;
use crate::EffectiveMembership;
use crate::LogId;
use crate::Membership;
use crate::NodeId;

static TRACE_LOCK: Mutex<()> = Mutex::new(());

thread_local! {
    /// Nesting depth of instrumented Engine calls on this thread.  Engine
    /// events carry the depth at which they were captured so the preprocessor
    /// can keep only outermost Engine transitions (nested calls are already
    /// contained in the outer transition's pre/post snapshots).
    static ENGINE_DEPTH: std::cell::Cell<usize> = std::cell::Cell::new(0);
}

/// Pre-state capture at the entry of an instrumented Engine method.  Every call
/// must be paired with exactly one `emit_engine` on every exit path.
pub(crate) fn capture_engine_pre<NID: NodeId>(engine: &Engine<NID>) -> Option<(usize, String)> {
    let snap = capture_engine(engine)?;
    let depth = ENGINE_DEPTH.with(|d| {
        let v = d.get();
        d.set(v + 1);
        v
    });
    Some((depth, snap))
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
    let line = format!("{{\"tag\":\"trace\",\"ts\":\"{}\",\"event\":{}}}\n", ts, event_json);

    let _guard = TRACE_LOCK.lock().expect("Specula trace mutex poisoned");
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = file.write_all(line.as_bytes());
        let _ = file.flush();
    }
}

fn groups_json<ID: Display>(groups: &[Vec<ID>]) -> String {
    let groups = groups
        .iter()
        .map(|group| {
            let ids = group.iter().map(quote).collect::<Vec<_>>().join(",");
            format!("[{}]", ids)
        })
        .collect::<Vec<_>>()
        .join(",");
    format!("[{}]", groups)
}

pub(crate) fn configs_json<NID: NodeId>(membership: &Membership<NID>) -> String {
    let groups = membership
        .get_joint_config()
        .iter()
        .map(|group| group.iter().copied().collect::<Vec<_>>())
        .collect::<Vec<_>>();
    groups_json(&groups)
}

/// Rendering of a progress value as a log id: `{"term":t,"index":i}`.
/// `None` is `{"term":0,"index":-1}`; a plain u64 test value `v` is `{"term":0,"index":v}`.
pub(crate) trait SpeculaValue {
    fn specula_json(&self) -> String;
}

impl SpeculaValue for u64 {
    fn specula_json(&self) -> String {
        format!("\"term\":0,\"index\":{}", self)
    }
}

impl<NID: NodeId> SpeculaValue for Option<LogId<NID>> {
    fn specula_json(&self) -> String {
        match self {
            None => "\"term\":0,\"index\":-1".to_string(),
            Some(l) => format!(
                "\"term\":{},\"node\":{},\"index\":{}",
                l.leader_id.term,
                quote(l.leader_id.node_id),
                l.index
            ),
        }
    }
}

/// Rendering of a quorum set as its majority groups.
pub(crate) trait SpeculaQuorum {
    fn specula_groups(&self) -> String;
}

impl<ID: Display + Copy + Ord> SpeculaQuorum for Vec<ID> {
    fn specula_groups(&self) -> String {
        groups_json(&[self.clone()])
    }
}

impl<ID: Display + Copy + Ord + 'static> SpeculaQuorum for Joint<ID, Vec<ID>, Vec<Vec<ID>>> {
    fn specula_groups(&self) -> String {
        groups_json(self.children())
    }
}

impl<NID: NodeId> SpeculaQuorum for Arc<EffectiveMembership<NID>> {
    fn specula_groups(&self) -> String {
        configs_json(&self.membership)
    }
}

fn vector_json<ID: Display, V: SpeculaValue>(vector: &[(ID, V)]) -> String {
    vector.iter().map(|(id, v)| format!("{{\"id\":{},{}}}", quote(id), v.specula_json())).collect::<Vec<_>>().join(",")
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
    let (committed_mem_index, committed_mem_term) = option_log_parts(engine.state.membership_state.committed.log_id);
    let (effective_mem_index, effective_mem_term) = option_log_parts(engine.state.membership_state.effective.log_id);
    let role = match engine.state.server_state {
        crate::ServerState::Leader => "leader",
        crate::ServerState::Candidate => "candidate",
        crate::ServerState::Follower => "follower",
        crate::ServerState::Learner => "learner",
        crate::ServerState::Shutdown => "follower",
    };

    // Engine leader state (RaftState.leader) and its VecProgress.
    let (leader_active, vote_granted, progress_configs, progress_vector, progress_committed) =
        match &engine.state.leader {
            None => (false, String::new(), "[]".to_string(), String::new(), None::<LogId<NID>>.specula_json()),
            Some(leader) => (
                true,
                leader.vote_granted_by.iter().map(quote).collect::<Vec<_>>().join(","),
                leader.progress.quorum_set().specula_groups(),
                vector_json(leader.progress.specula_vector()),
                leader.progress.committed().specula_json(),
            ),
        };

    Some(format!(
        concat!(
            "{{\"term\":{},\"vote_node\":{},\"vote_committed\":{},\"role\":\"{}\",",
            "\"last_log\":{},\"logs\":[{}],\"committed\":{},",
            "\"committed_mem_index\":{},\"committed_mem_term\":{},",
            "\"effective_mem_index\":{},\"effective_mem_term\":{},",
            "\"committed_configs\":{},\"effective_configs\":{},",
            "\"leader_active\":{},\"vote_granted\":[{}],\"progress_configs\":{},",
            "\"progress_vector\":[{}],\"progress_committed\":{{{}}}}}"
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
        leader_active,
        vote_granted,
        progress_configs,
        progress_vector,
        progress_committed,
    ))
}

pub(crate) fn emit_engine<NID: NodeId>(
    name: &str,
    nid: NID,
    pre: Option<(usize, String)>,
    post: &Engine<NID>,
    args: String,
) {
    let (depth, pre) = match pre {
        Some(pre) => pre,
        None => return,
    };
    ENGINE_DEPTH.with(|d| d.set(depth));
    let post = capture_engine(post).expect("trace enabled after pre-state capture");
    emit(format!(
        "{{\"name\":\"{}\",\"depth\":{},\"nid\":{},\"pre\":{},\"post\":{},\"args\":{}}}",
        name,
        depth,
        quote(nid),
        pre,
        post,
        args
    ));
}

pub(crate) fn vote_resp_args<NID: NodeId>(target: NID, vote: &crate::Vote<NID>, granted: bool) -> String {
    if !enabled() {
        return String::new();
    }
    format!(
        "{{\"target\":{},\"resp_term\":{},\"resp_node\":{},\"resp_committed\":{},\"granted\":{}}}",
        quote(target),
        vote.term,
        quote(vote.node_id),
        vote.committed,
        granted
    )
}

pub(crate) fn update_progress_args<NID: NodeId>(node_id: NID, log_id: Option<LogId<NID>>) -> String {
    if !enabled() {
        return String::new();
    }
    format!("{{\"target\":{},{}}}", quote(node_id), log_id.specula_json())
}

/// Capture `configs`, `pre_vector` and `pre_committed` of a VecProgress.
pub(crate) fn capture_progress<ID: Display, V: SpeculaValue, QS: SpeculaQuorum>(
    quorum_set: &QS,
    vector: &[(ID, V)],
    committed: &V,
) -> Option<String> {
    if !enabled() {
        return None;
    }
    Some(format!(
        "\"configs\":{},\"pre_vector\":[{}],\"pre_committed\":{{{}}}",
        quorum_set.specula_groups(),
        vector_json(vector),
        committed.specula_json()
    ))
}

pub(crate) fn emit_progress_update<ID: Display, V: SpeculaValue>(
    pre: Option<String>,
    post_vector: &[(ID, V)],
    post_committed: &V,
    target: &ID,
    value: &V,
) {
    let pre = match pre {
        Some(pre) => pre,
        None => return,
    };
    emit(format!(
        "{{\"name\":\"ProgressUpdate\",{},\"post_vector\":[{}],\"post_committed\":{{{}}},\"args\":{{\"target\":{},{}}}}}",
        pre,
        vector_json(post_vector),
        post_committed.specula_json(),
        quote(target),
        value.specula_json()
    ));
}

pub(crate) fn emit_progress_upgrade<ID: Display, V: SpeculaValue + Default, QS: SpeculaQuorum>(
    pre: Option<String>,
    new_quorum_set: &QS,
    post_vector: &[(ID, V)],
    post_committed: &V,
) {
    let pre = match pre {
        Some(pre) => pre,
        None => return,
    };
    emit(format!(
        concat!(
            "{{\"name\":\"ProgressUpgrade\",{},\"new_configs\":{},\"default\":{{{}}},",
            "\"post_vector\":[{}],\"post_committed\":{{{}}}}}"
        ),
        pre,
        new_quorum_set.specula_groups(),
        V::default().specula_json(),
        vector_json(post_vector),
        post_committed.specula_json()
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
