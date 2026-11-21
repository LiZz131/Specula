#!/usr/bin/env python3
"""One-time helper used to author the rebased probes in engine_impl.rs.
Exact-string edits; fails loudly if any anchor is missing."""
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()

def rep(old, new, count=1):
    global s
    n = s.count(old)
    if n != count:
        raise SystemExit(f"anchor count {n} != {count}: {old[:80]!r}")
    s = s.replace(old, new)

# elect
rep("""    pub(crate) fn elect(&mut self) {
        // init election
""", """    pub(crate) fn elect(&mut self) {
        let _specula_g = crate::specula_trace::enter();
        let specula_pre = crate::specula_trace::capture_engine(self);
        // init election
""")
rep("""            self.set_server_state(ServerState::Leader);
            return;
        }

        // Slow-path: send vote request, let a quorum grant it.
""", """            self.set_server_state(ServerState::Leader);
            crate::specula_trace::emit_engine("Elect", self.id, specula_pre, self, "{}".to_string());
            return;
        }

        // Slow-path: send vote request, let a quorum grant it.
""")
rep("""        // TODO: For compatibility. remove it. The runtime does not need to know about server state.
        self.set_server_state(ServerState::Candidate);
    }

    #[tracing::instrument(level = "debug", skip_all)]
    pub(crate) fn handle_vote_req""", """        // TODO: For compatibility. remove it. The runtime does not need to know about server state.
        self.set_server_state(ServerState::Candidate);
        crate::specula_trace::emit_engine("Elect", self.id, specula_pre, self, "{}".to_string());
    }

    #[tracing::instrument(level = "debug", skip_all)]
    pub(crate) fn handle_vote_req""")

# leader_append_entries
rep("""    pub(crate) fn leader_append_entries<'a, Ent: RaftEntry<NID> + 'a>(&mut self, entries: &mut [Ent]) {
        let l = entries.len();
""", """    pub(crate) fn leader_append_entries<'a, Ent: RaftEntry<NID> + 'a>(&mut self, entries: &mut [Ent]) {
        let _specula_g = crate::specula_trace::enter();
        let specula_pre = crate::specula_trace::capture_engine(self);
        let specula_old_last = self.state.last_log_id().map(|x| x.index as i64).unwrap_or(-1);
        let mut specula_membership_position: i64 = -1;
        let l = entries.len();
""")
rep("""            if let Some(_m) = entry.get_membership() {
                let log_index = entry.get_log_id().index;
""", """            if let Some(_m) = entry.get_membership() {
                let log_index = entry.get_log_id().index;
                if specula_membership_position < 0 {
                    specula_membership_position = log_index as i64 - specula_old_last;
                }
""")
rep("""        // Still need to replicate to learners, even when it is fast-committed.
        self.push_command(Command::ReplicateInputEntries { range: 0..l });
        self.push_command(Command::MoveInputCursorBy { n: l });
    }
""", """        // Still need to replicate to learners, even when it is fast-committed.
        self.push_command(Command::ReplicateInputEntries { range: 0..l });
        self.push_command(Command::MoveInputCursorBy { n: l });

        crate::specula_trace::emit_engine(
            "LeaderAppend",
            self.id,
            specula_pre,
            self,
            format!(
                "{{\\"count\\":{},\\"membership_position\\":{},\\"membership_configs\\":{}}}",
                l,
                specula_membership_position,
                entries
                    .iter()
                    .find_map(|e| e.get_membership().map(crate::specula_trace::configs_json))
                    .unwrap_or_else(|| "[]".to_string())
            ),
        );
    }
""")

# follower_commit_entries
rep("""        entries: &[Ent],
    ) {
        tracing::debug!(
            leader_committed = display(leader_committed.summary()),
            prev_log_id = display(prev_log_id.summary()),
        );
""", """        entries: &[Ent],
    ) {
        let _specula_g = crate::specula_trace::enter();
        let specula_pre = crate::specula_trace::capture_engine(self);
        let specula_args = format!(
            "{{\\"leader_commit\\":{},\\"prev_log\\":{},\\"last_entry\\":{}}}",
            crate::specula_trace::log_id_json(&leader_committed),
            crate::specula_trace::log_id_json(&prev_log_id),
            crate::specula_trace::log_id_json(&entries.last().map(|x| *x.get_log_id())),
        );
        tracing::debug!(
            leader_committed = display(leader_committed.summary()),
            prev_log_id = display(prev_log_id.summary()),
        );
""")
rep("""                upto: committed.unwrap(),
            });
        }
    }

    /// Follower/Learner appends `entries[since..]`.""", """                upto: committed.unwrap(),
            });
        }

        crate::specula_trace::emit_engine("FollowerCommit", self.id, specula_pre, self, specula_args);
    }

    /// Follower/Learner appends `entries[since..]`.""")

# update_committed_membership
rep("""    pub(crate) fn update_committed_membership(&mut self, membership: EffectiveMembership<NID>) {
        tracing::debug!("update committed membership: {}", membership.summary());
""", """    pub(crate) fn update_committed_membership(&mut self, membership: EffectiveMembership<NID>) {
        let _specula_g = crate::specula_trace::enter();
        let specula_pre = crate::specula_trace::capture_engine(self);
        let specula_new_index = membership.log_id.map(|x| x.index as i64).unwrap_or(-1);
        let specula_new_term = membership.log_id.map(|x| x.leader_id.term).unwrap_or(0);
        let specula_new_configs = crate::specula_trace::configs_json(&membership.membership);
        tracing::debug!("update committed membership: {}", membership.summary());
""")
rep("""        self.state.membership_state = mem_state;

        self.update_server_state_if_changed(server_state);
    }

    #[tracing::instrument(level = "debug", skip_all)]
    pub(crate) fn update_effective_membership""", """        self.state.membership_state = mem_state;

        self.update_server_state_if_changed(server_state);

        crate::specula_trace::emit_engine(
            "UpdateCommittedMembership",
            self.id,
            specula_pre,
            self,
            format!(
                "{{\\"new_term\\":{},\\"new_index\\":{},\\"new_configs\\":{}}}",
                specula_new_term, specula_new_index, specula_new_configs
            ),
        );
    }

    #[tracing::instrument(level = "debug", skip_all)]
    pub(crate) fn update_effective_membership""")

# update_effective_membership: wrapper around unchanged body
rep("""    pub(crate) fn update_effective_membership(&mut self, log_id: &LogId<NID>, m: &Membership<NID>) {
        tracing::debug!""", """    pub(crate) fn update_effective_membership(&mut self, log_id: &LogId<NID>, m: &Membership<NID>) {
        let _specula_g = crate::specula_trace::enter();
        let specula_pre = crate::specula_trace::capture_engine(self);
        self.specula_update_effective_membership_body(log_id, m);
        crate::specula_trace::emit_engine(
            "UpdateEffectiveMembership",
            self.id,
            specula_pre,
            self,
            format!(
                "{{\\"log_term\\":{},\\"log_index\\":{},\\"configs\\":{}}}",
                log_id.leader_id.term,
                log_id.index,
                crate::specula_trace::configs_json(m)
            ),
        );
    }

    fn specula_update_effective_membership_body(&mut self, log_id: &LogId<NID>, m: &Membership<NID>) {
        tracing::debug!""")

# update_progress: wrapper around unchanged body
rep("""    pub(crate) fn update_progress(&mut self, node_id: NID, log_id: Option<LogId<NID>>) {
        tracing::debug!""", """    pub(crate) fn update_progress(&mut self, node_id: NID, log_id: Option<LogId<NID>>) {
        let _specula_g = crate::specula_trace::enter();
        let specula_pre = crate::specula_trace::capture_engine(self);
        self.specula_update_progress_body(node_id, log_id);
        crate::specula_trace::emit_engine(
            "UpdateProgress",
            self.id,
            specula_pre,
            self,
            format!(
                "{{\\"target\\":\\"{}\\",\\"value\\":{}}}",
                node_id,
                crate::specula_trace::log_id_json(&log_id)
            ),
        );
    }

    fn specula_update_progress_body(&mut self, node_id: NID, log_id: Option<LogId<NID>>) {
        tracing::debug!""")

p.write_text(s)
print("ok")
