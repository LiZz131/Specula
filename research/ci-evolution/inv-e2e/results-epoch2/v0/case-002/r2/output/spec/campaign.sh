#!/usr/bin/env bash
# Usage: campaign.sh <name> <module.tla> <cfg> <workers> <heap> [extra TLC args]
# Bounded 30-minute TLC run (outer timeout); log spec/output/<name>.log.
name=$1; mod=$2; cfg=$3; w=$4; heap=$5; shift 5
cd "$(dirname "$0")"
TLC_HEAP=$heap ./tlc.sh "$name" "$mod" "$cfg" 1800s -workers "$w" "$@"
