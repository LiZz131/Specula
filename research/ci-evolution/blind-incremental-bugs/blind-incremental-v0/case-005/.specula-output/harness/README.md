# Exact-old trace harness

Run `./run.sh NAME` to instrument `/work/work-source`, execute the neutral
startup/mutation/follower-restart/full-restart JUnit scenario with a bounded
outer timeout, and create `../traces/NAME.ndjson`. Run
`./validate-suite.sh` to replay every retained normalized trace. Run
`./run-checks.sh` to enforce trace-first replay followed by canonical base and
MC BFS. All runners record commands and exit codes, remove their TLC metadata
directories, and write `spec/output/validation-backedge/suite-manifest.json`.
