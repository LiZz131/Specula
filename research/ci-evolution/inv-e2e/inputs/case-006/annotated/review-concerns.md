# Model observations moved out of `note:` lines

**None were moved.** This is the result of the note check (check 5), not a skipped step.

All 7 `note:` lines in the annotated model (ElectionSafety, CommitWithinLog, LogMatching, CommittedPrefixAgreement, LeaderCompleteness, ReadDeliveryJustified, ReadyNoInvention) were read sentence by sentence. Every sentence is one of:

- a search record ("searched source and history for … and found nothing");
- a statement that a source is unavailable ("the Raft paper text is not in /work");
- a reason a source was not counted (doc.go:249-252 wording, TestReadOnlyOptionSafe, e769766, node.go:157, the isUpToDate comment);
- how the evidence relates to the intent ("the intent follows from the two tested rules").

No sentence describes how the model's actions or helpers behave, compares the model with the code, or calls the model weaker, stronger, a proxy, vacuous or a false alarm.

Keyword cross-check: `grep -i -E 'concerns|model|vacuous|proxy|weaker|stronger|false alarm|unmodel'` over the annotation fields matched only three intents of model-internal properties (TypeOK, MessagesWellFormed, TraceCanProgress) and the ctx-domain clause of ReadyNoInvention. Those are not `note:` lines, and they describe what each formula checks, as an intent should.

The model had no reference to `concerns.md` (`grep -ril concerns spec-annotated/` → 0 files), and the reviewed copy has none either.

The sentences I added to notes during review are also about evidence only: why a commit message, or one test case, was not counted.
