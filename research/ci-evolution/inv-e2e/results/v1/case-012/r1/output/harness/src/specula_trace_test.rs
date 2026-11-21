use std::sync::Arc;

use maplit::btreeset;

use crate::engine::Engine;
use crate::{EffectiveMembership, Membership};

#[test]
fn specula_trace_election_single() -> anyhow::Result<()> {
    let mut engine = Engine::<u64>::default();
    engine.id = 1;
    engine.state.membership_state.effective =
        Arc::new(EffectiveMembership::new(None, Membership::new(vec![btreeset! {1}], None)));

    engine.elect();

    assert!(engine.state.vote.committed);
    assert!(engine.state.server_state.is_leader());
    Ok(())
}
