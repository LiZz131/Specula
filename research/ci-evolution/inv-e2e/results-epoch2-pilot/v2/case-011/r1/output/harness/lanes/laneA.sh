cd /work/current/.specular-output
while pgrep -f "metadir /dev/shm/specular-e2e-case-011/mc-standard " >/dev/null || [ -d /dev/shm/specular-e2e-case-011/mc-standard ]; do sleep 15; done
bash harness/tlc-run.sh Update Update_focused_cont.cfg update-focused-cont 12 30
bash harness/tlc-run.sh MC MC.cfg mc-standard-sim 8 20 -simulate num=999999999 -depth 60
