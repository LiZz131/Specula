# Scenario inventory shared by run.sh and validate-traces.sh.
prior_cases=(start_election reject_stale_log grant_greater_vote establish_leader append_joint_membership commit_membership restart_follower)
update_cases=(pre_elect_multi pre_elect_single pre_vote_req_grant pre_vote_req_reject_lease pre_vote_req_reject_log pre_vote_req_reject_vote pre_vote_resp_quorum_elect pre_vote_resp_reject_greater_log pre_vote_resp_joint_no_quorum stale_pre_vote_after_establish heartbeat_cancels_pre_vote vote_grant_cancels_pre_vote)
cases=("${prior_cases[@]}" "${update_cases[@]}")
