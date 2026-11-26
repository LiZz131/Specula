#!/usr/bin/env bash
cd /work/current/.specular-output/repro
while pgrep -f run-all-bug1.sh > /dev/null; do sleep 10; done
./test_bug2_learner_initial_state_leak.sh new 2
./test_bug2_learner_initial_state_leak.sh old 1
./test_bug3_proposal_ack_before_newleader_ack.sh new 2
./test_bug3_proposal_ack_before_newleader_ack.sh old 1
