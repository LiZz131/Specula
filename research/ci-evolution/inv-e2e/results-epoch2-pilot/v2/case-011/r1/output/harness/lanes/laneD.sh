cd /work/current/.specular-output
while [ -d /dev/shm/specular-e2e-case-011/discharge-full ] || [ -d /dev/shm/specular-e2e-case-011/hunt-leader-abdication-bfs ]; do sleep 15; done
bash harness/tlc-run.sh Update MC_hunt_prevote_crash_cont.cfg hunt-prevote-crash-bfs 8 20
bash harness/tlc-run.sh Update Update_focused_cont.cfg update-focused-cont-sim 6 15 -simulate num=999999999 -depth 80
