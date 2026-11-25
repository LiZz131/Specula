cd /work/current/.specular-output
while [ -d /dev/shm/specular-e2e-case-011/update-full-cont2 ]; do sleep 15; done
bash harness/tlc-run.sh Update Update_open_cont.cfg update-open-cont 12 30
bash harness/tlc-run.sh Update Update_full_cont2.cfg update-full-cont2-sim 8 20 -simulate num=999999999 -depth 60
