# Retained scenario inventory (prior V0 regression scenarios first).
prior_cases=(start_election reject_stale_log grant_greater_vote establish_leader
             append_joint_membership commit_membership restart_follower)
update_cases=(prevote_elect_multi prevote_single_voter prevote_req_grant
              prevote_req_reject_lease prevote_req_reject_log prevote_req_reject_vote
              prevote_quorum_elect prevote_reject_greater_log
              prevote_cleared_by_vote_request prevote_new_round_same_leader_id
              candidate_prevote_establish prevote_stale_member_panic
              grant_vote_empty_logs prevote_req_grant_empty_logs)
cases=("${prior_cases[@]}" "${update_cases[@]}")
