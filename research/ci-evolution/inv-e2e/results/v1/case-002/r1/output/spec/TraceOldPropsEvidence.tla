----------------------- MODULE TraceOldPropsEvidence -----------------------
(* Evaluates the PRIOR (V0) property definitions on states of validated     *)
(* new-version traces, to obtain trace-sourced separating states.  The      *)
(* prior `recovered` variable has no counterpart; it is mapped to the data  *)
(* tree (applied), which no evaluated old property reads.                  *)
EXTENDS Trace
Old == INSTANCE OldBase WITH recovered <- applied
OldApplyRequiresCommitCertificate == Old!ApplyRequiresCommitCertificate
OldOneActiveLeaderPerEpoch == Old!OneActiveLeaderPerEpoch
OldPipelinePrefix == Old!PipelinePrefix
OldSyncCompletionJustified == Old!SyncCompletionJustified
\* New definitions evaluated in the same state (for the evidence record).
Verdicts == <<OldApplyRequiresCommitCertificate, ServingApplyCommitted,
              OldOneActiveLeaderPerEpoch, OneActiveLeaderPerEpoch,
              OldPipelinePrefix, PipelinePrefix,
              OldSyncCompletionJustified, SyncCompletionJustified>>
=============================================================================
