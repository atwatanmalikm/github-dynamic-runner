#!/bin/bash

CUR_DIR=$(pwd)

while :
do
  proc=$(pgrep Runner.Worker | wc -l)
  dir=$(ls | grep gha-ctrl | wc -l)
  #echo "Cek terus bro"
  if [ $proc -eq 0 ] && [ $dir -ge 1 ]
  then
    #echo "proc 0, tpi ada dirnya bro, cek dulu"
    for chk in {1..10}
    do
      proc=$(pgrep Runner.Worker | wc -l)
      if [ $proc -ge 1 ]
      then
        #echo "proc 1 skrng nih, lanjut wae"
        break
      fi
      sleep 6
    done
    
    proc=$(pgrep Runner.Worker | wc -l)

    if [ $proc -eq 0 ]
    then
      #echo "proc msh 0 bro, otw copot ctrl runner"
      for i in $(ls | grep gha-ctrl)
      do
        cd ${i}
        sudo bash svc.sh stop
        sudo bash svc.sh uninstall
        ./config.sh remove --token $(cat ${CUR_DIR}/${i}/runner_token)
        cd ${CUR_DIR}
        rm -rf ${i}
      done
    fi
  fi
  sleep 10
done
