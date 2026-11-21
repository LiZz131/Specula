#!/usr/bin/env python3
"""One-time helper used to author the rebased probes in progress/mod.rs and
effective_membership.rs / replication_state.rs / lib.rs / engine/mod.rs."""
import pathlib, sys
root = pathlib.Path(sys.argv[1])

def edit(rel, pairs):
    p = root / rel
    s = p.read_text()
    for old, new in pairs:
        n = s.count(old)
        if n != 1:
            raise SystemExit(f"{rel}: anchor count {n}: {old[:70]!r}")
        s = s.replace(old, new)
    p.write_text(s)

edit("openraft/src/progress/mod.rs", [
("""    #[allow(dead_code)]
    pub(crate) fn stat(&self) -> &Stat {
        &self.stat
    }
}
""", """    #[allow(dead_code)]
    pub(crate) fn stat(&self) -> &Stat {
        &self.stat
    }

    /// Specula instrumentation: read-only view of the internal representation.
    #[allow(dead_code)]
    pub(crate) fn specula_parts(&self) -> (&Vec<(ID, V)>, &V, &QS) {
        (&self.vector, &self.committed, &self.quorum_set)
    }
}

impl<ID, V, QS> VecProgress<ID, V, QS>
where
    ID: PartialEq + Debug + Copy + 'static,
    V: PartialOrd + Ord + Copy + Default + 'static,
    QS: QuorumSet<ID> + 'static,
{
    fn specula_snapshot(&self) -> Option<String> {
        if !crate::specula_trace::enabled() {
            return None;
        }
        Some(crate::specula_trace::progress_parts_json(
            &self.vector,
            &self.committed,
            &self.quorum_set,
        ))
    }
}
"""),
("""    fn update(&mut self, id: &ID, value: V) -> &V {
        self.stat.update_count += 1;
""", """    fn update(&mut self, id: &ID, value: V) -> &V {
        let _specula_g = crate::specula_trace::enter();
        let specula_pre = self.specula_snapshot();
        self.specula_update_body(id, value);
        if let Some(post) = self.specula_snapshot() {
            crate::specula_trace::emit_progress_update(id, &value, specula_pre, post);
        }
        &self.committed
    }

    fn get(&self, id: &ID) -> &V {
        let index = self.index(id).unwrap();
        &self.vector[index].1
    }

    fn committed(&self) -> &V {
        &self.committed
    }

    fn quorum_set(&self) -> &QS {
        &self.quorum_set
    }

    fn upgrade_quorum_set(self, quorum_set: QS) -> Self {
        let _specula_g = crate::specula_trace::enter();
        let specula_pre = self.specula_snapshot();
        let specula_qs = crate::specula_trace::qs_json(&quorum_set);
        let new_qs = self.specula_upgrade_body(quorum_set);
        if let Some(post) = new_qs.specula_snapshot() {
            crate::specula_trace::emit_progress_upgrade(specula_pre, post, specula_qs);
        }
        new_qs
    }
}

impl<ID, V, QS> VecProgress<ID, V, QS>
where
    ID: PartialEq + Debug + Copy + 'static,
    V: PartialOrd + Ord + Copy + Default + 'static,
    QS: QuorumSet<ID> + 'static,
{
    fn specula_update_body(&mut self, id: &ID, value: V) -> &V {
        self.stat.update_count += 1;
"""),
("""        &self.committed
    }

    fn get(&self, id: &ID) -> &V {
        let index = self.index(id).unwrap();
        &self.vector[index].1
    }

    fn committed(&self) -> &V {
        &self.committed
    }

    fn quorum_set(&self) -> &QS {
        &self.quorum_set
    }

    fn upgrade_quorum_set(self, quorum_set: QS) -> Self {
        let mut new_qs = Self::new(quorum_set);
""", """        &self.committed
    }

    fn specula_upgrade_body(self, quorum_set: QS) -> Self {
        let mut new_qs = Self::new(quorum_set);
"""),
])

edit("openraft/src/membership/effective_membership.rs", [
("""    fn is_quorum<'a, I: Iterator<Item = &'a NID> + Clone>(&self, ids: I) -> bool {
        self.quorum_set.is_quorum(ids)
    }
""", """    fn is_quorum<'a, I: Iterator<Item = &'a NID> + Clone>(&self, ids: I) -> bool {
        let _specula_g = crate::specula_trace::enter();
        let granted = ids.copied().collect::<Vec<_>>();
        let result = self.quorum_set.is_quorum(granted.iter());
        crate::specula_trace::emit_quorum(&self.membership, &granted, result);
        result
    }
"""),
])

edit("openraft/src/core/replication_state.rs", [
("""    let distance = last_log_id.next_index().saturating_sub(my_index);
    distance <= config.replication_lag_threshold
""", """    let distance = last_log_id.next_index().saturating_sub(my_index);
    let _specula_g = crate::specula_trace::enter();
    let result = distance <= config.replication_lag_threshold;
    crate::specula_trace::emit_replication_lag(
        matched.index().map(|x| x as i64).unwrap_or(-1),
        last_log_id.index().map(|x| x as i64).unwrap_or(-1),
        config.replication_lag_threshold,
        result,
    );
    result
"""),
])

edit("openraft/src/lib.rs", [
("""mod summary;
""", """mod summary;
mod specula_trace;
"""),
])

edit("openraft/src/engine/mod.rs", [
("""#[cfg(test)] mod testing;
""", """#[cfg(test)] mod specula_trace_test;
#[cfg(test)] mod testing;
"""),
])
print("ok")
