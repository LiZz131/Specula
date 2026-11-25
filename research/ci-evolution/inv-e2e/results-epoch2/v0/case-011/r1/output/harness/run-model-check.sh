#!/usr/bin/env bash
# Standard convergence round (MC.cfg + MC-membership.cfg), 30-minute budget each.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
printf '%s\n' "mc-standard MC MC.cfg 12 30 -coverage 10" "mc-membership MC MC-membership.cfg 6 30 -coverage 10" \
  | "$suite_root/harness/run-campaign.sh"
