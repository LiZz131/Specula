cd /work/current/.specular-output
while [ -d /dev/shm/specular-e2e-case-011/hunt-prevote-panic-bfs ]; do sleep 15; done
bash harness/tlc-run.sh Update MC_hunt_prevote_panic.cfg hunt-prevote-panic-sim 8 20 -simulate num=999999999 -depth 60
bash harness/tlc-run.sh Update Update_full_mixed_cont.cfg update-full-mixed-cont 8 20
