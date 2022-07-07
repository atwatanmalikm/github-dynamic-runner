#!/bin/bash

# req: gcloud config set compute/zone asia-southeast2-a

dir=$1
CUR_DIR=$(pwd)

destroy () {
  #dir=$1
  BR=$(echo $dir | cut -d- -f2)
  ID=$(echo $dir | cut -d- -f3)
  cd ${dir} && terraform destroy -auto-approve
  cd ${CUR_DIR} && rm -rf ${dir}
  if [ $(gcloud compute instances list | grep $ID | wc -l) -ge 1 ]
  then
          gcloud compute instances delete -q  gha-worker-${BR}-${ID}
  fi
}

check_status () {
  #dir=$1
  while :
  do
    STATUS=$(ls ${dir}/DONE 2> /tmp/null | wc -l)
    if [ ${STATUS} -ge 1 ]
    then
      destroy ${dir}
      break
    fi
    sleep 10
  done
}

#while :
for i in {1..10}
do
  proc=$(pgrep Runner.Worker | wc -l)
  CHECK=$(ls ${dir}/PROGRESS 2> /tmp/null | wc -l)
  if [ $proc -eq 0 ] && [ ${CHECK} -eq 1 ]
  then
     #echo "ada PROGRESS bro, lagi cek status"
     check_status ${dir}
     break
    #CHECK=$(ls ${dir}/PROGRESS 2> /tmp/null | wc -l)
    #if [ ${CHECK} -ge 1 ]
    #then
      #echo "ada worker-rm-exec.sh nya nih bro, lagi cek status"
      #check_status ${dir}
      #break
    #else
      #echo "ga ada worker-rm-exec.sh nya nih bro, otw destroy"
      #destroy ${dir}
      #break
    #fi
  fi
  sleep 15
done

CHK=$(ls -d ${dir} | wc -l)
if [ ${CHK} -eq 1 ]
then
   #echo "Ga ada PROGRESS bro, otw destroy"
   destroy ${dir}
fi
