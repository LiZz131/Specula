#!/usr/bin/env bash
# Static evaluation of TypeOK/MCTypeOK on constructed states (actual definitions).
cd "$(dirname "$0")" && cp ../../base.tla ../../MC.tla . && timeout 2m java -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -metadir /dev/shm/specular-e2e-case-011/etc -config E_TypeOK_ctl.cfg E_TypeOK_ctl > tlc.log 2>&1; rm -rf /dev/shm/specular-e2e-case-011/etc base.tla MC.tla
