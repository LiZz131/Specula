---- MODULE TraceStop ----
\* Evidence helper: stops a passing replay after a given cursor so that TLC
\* prints the validated prefix (used to extract trace states).
EXTENDS Trace
StopAt12 == l < 12
StopAt103 == l < 103
====
