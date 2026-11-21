#!/bin/bash
# usage: sany.sh file.tla
cd "$(dirname "$1")"
timeout 120 java -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tla2sany.SANY "$(basename "$1")" 2>&1 | grep -v "^Parsing file\|^Semantic processing\|^Linting" 
