#!/bin/bash

###########################
# SETUP GHA CTRL FUNCTION #
###########################

setup_ctrl () {

# Install runner
mkdir -p gha-ctrl-${DIR_ID}
tar -xf arms/actions-runner-linux.tar.gz -C gha-ctrl-${DIR_ID}
cd gha-ctrl-${DIR_ID}

# Generate runner token
curl --silent -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token ${AUTH_TOKEN}" \
https://api.github.com/orgs/${GITHUB_REPOSITORY_OWNER}/actions/runners/registration-token | jq -r .token > runner_token

# Determine Project ID
STG=$(hostname | grep stg | wc -l)
PROD=$(hostname | grep prod | wc -l)

if [[ $STG -ge 1 ]]
then
  PRJID=stg
elif [[ $PROD -ge 1 ]]
then
  PRJID=prod
else
  PRJID=dev
fi

# Register Backup Controller Runner
./config.sh --url https://github.com/${GITHUB_REPOSITORY_OWNER} \
--token $(cat ${CUR_DIR}/gha-ctrl-${DIR_ID}/runner_token) --name gha-controller-${DIR_ID} \
--labels gha-controller-$PRJID --unattended --ephemeral

sudo bash svc.sh install
sudo bash svc.sh start

# Back to main directory
cd ${CUR_DIR}

}

#############################
# SETUP GHA WORKER FUNCTION #
#############################

setup_worker () {

GITHUB_REF_NAME=$(echo ${GITHUB_REF_NAME} | cut -d/ -f1)
mkdir -p ${CUR_DIR}/tf-${GITHUB_REF_NAME}-${GITHUB_SHA::7}

# Setup Ctrl-Worker Monitoring Script
cat << MON > ctrl-worker-monitor.sh
#!/bin/bash

# req: gcloud config set compute/zone asia-southeast2-a

dir=\$1
CUR_DIR=\$(pwd)

destroy () {
  BR=\$(echo \$dir | cut -d- -f2)
  ID=\$(echo \$dir | cut -d- -f3)
  cd \${dir} && terraform destroy -auto-approve
  cd \${CUR_DIR} && rm -rf \${dir}
  if [ \$(gcloud compute instances list | grep \$ID | wc -l) -ge 1 ]
  then
    gcloud compute instances delete -q  gha-worker-\${BR}-\${ID}
  fi
}

check_status () {
  while :
  do
    STATUS=\$(ls \${dir}/DONE 2> /tmp/null | wc -l)
    if [ \${STATUS} -ge 1 ]
    then
      destroy \${dir}
      break
    fi
    sleep 10
  done
}

#while :
for i in {1..10}
do
  proc=\$(pgrep Runner.Worker | wc -l)
  CHECK=\$(ls \${dir}/PROGRESS 2> /tmp/null | wc -l)
  if [ \$proc -eq 0 ] && [ \${CHECK} -eq 1 ]
  then
     #echo "ada PROGRESS bro, lagi cek status"
     check_status \${dir}
     break
  fi
  sleep 15
done

CHK=\$(ls -d \${dir} | wc -l)
if [ \${CHK} -eq 1 ]
then
   #echo "Ga ada PROGRESS bro, otw destroy"
   destroy \${dir}
fi
MON

# Setup Ctrl-Worker Monitoring Service
cat << EOF > ctrl-worker-monitor@.service
[Unit]
Description=monitor process for deletion

[Service]
User=runner
WorkingDirectory=${CUR_DIR}
ExecStart=/bin/bash -c 'bash ctrl-worker-monitor.sh %i'

[Install]
WantedBy=multi-user.target
EOF

sudo mv ctrl-worker-monitor@.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start ctrl-worker-monitor@tf-${GITHUB_REF_NAME}-${GITHUB_SHA::7}.service
sudo systemctl status ctrl-worker-monitor@tf-${GITHUB_REF_NAME}-${GITHUB_SHA::7}.service

# Spawn worker VM
sed "s/name         =/name         = \"gha-worker-${GITHUB_REF_NAME}-${GITHUB_SHA::7}\"/g" arms/main.tf.template > ${CUR_DIR}/tf-${GITHUB_REF_NAME}-${GITHUB_SHA::7}/main.tf
cd ${CUR_DIR}/tf-${GITHUB_REF_NAME}-${GITHUB_SHA::7} && terraform init && terraform apply -auto-approve
cp ${CUR_DIR}/arms/* .

sleep 30

# Get runner label list
cat $GITHUB_WORKSPACE/.github/workflows/*.yml | grep runs-on | grep -v -E "gha-controller|windows|ubuntu|macos" | cut -d: -f2 | tr -d " " > label

# Add unique ID for runner name
for i in $(cat label); do echo ${i}-$(date +%N); done > label_id

# Create worker setup script
cat << EOF > worker.sh

#!/bin/bash

export LABEL=\${1}
export LABELID=\${2}

mkdir -p ~/\${LABELID}
tar -xf actions-runner-linux.tar.gz -C ~/\${LABELID}
cd ~/\${LABELID}

curl --silent -X POST -H "Accept: application/vnd.github.v3+json" -H "Authorization: token ${AUTH_TOKEN} " \
https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runners/registration-token | jq -r .token > runner_token

./config.sh --url https://github.com/$GITHUB_REPOSITORY --token \$(cat ~/\${LABELID}/runner_token) \
--name \${LABELID}-${GITHUB_SHA::7} --labels \${LABEL} --unattended --ephemeral

sudo bash svc.sh install
sudo bash svc.sh start
EOF

cat << EOF > worker-exec.sh

#!/bin/bash
sudo timedatectl set-timezone Asia/Jakarta
mv gha ~/.ssh/id_rsa && chmod 600 ~/.ssh/id_rsa
chmod +x worker-monitor.sh
sudo mv worker-monitor.service /etc/systemd/system
sudo systemctl daemon-reload

chmod +x worker.sh
for i in \`seq 1 \$(cat label | wc -l)\`; do 
	bash worker.sh \$(cat label | sed -n \${i}p) \$(cat label_id | sed -n \${i}p)
done

sudo systemctl start worker-monitor.service

EOF


# Setup worker monitoring script
cat << MON > worker-monitor.sh
#!/bin/bash

sleep 30

while :
do	
	sleep 90
	BR=${GITHUB_REF_NAME}
    ID=${GITHUB_SHA::7}
	proc=\$(pgrep Runner.Worker | wc -l)
	while [[ \$proc -ge 1 ]]
	do
		proc2=\$(pgrep Runner.Worker | wc -l)
        sleep 300
		if [ \$proc2 -eq 0 ]
		then
            bash worker-rm-exec.sh
			ssh -o "StrictHostKeyChecking=no" runner@${CTRL_IP} "touch ${CUR_DIR}/tf-\${BR}-\${ID}/DONE"
			break
		fi
	done

	sleep 30
        proc=\$(pgrep Runner.Worker | wc -l)
	
	chk=\$(ssh -o "StrictHostKeyChecking=no" runner@${CTRL_IP} "ls -l ${CUR_DIR}/tf-\${BR}-\${ID}/DONE | wc -l")
	if [ \$proc -eq 0 ] && [ \${chk} -eq 0 ]
	then
		bash worker-rm-exec.sh
		ssh -o "StrictHostKeyChecking=no" runner@${CTRL_IP} "touch ${CUR_DIR}/tf-\${BR}-\${ID}/DONE"
	fi
done
MON

cat << RMEOF > worker-rm-exec.sh

#!/bin/bash

cat << EOF > worker-rm.sh
#!/bin/bash

export LABEL=\\\${1}
export LABELID=\\\${2}

cd ~/\\\${LABELID}
sudo bash svc.sh stop
sudo bash svc.sh uninstall
./config.sh remove --token \\\$(cat ~/\\\${LABELID}/runner_token)
EOF

chmod +x worker-rm.sh

for i in \`seq 1 \$(cat label | wc -l)\`; do 
	bash worker-rm.sh \$(cat label | sed -n \${i}p) \$(cat label_id | sed -n \${i}p)
done

RMEOF


# Setup worker monitoring service
cat << EOF > worker-monitor.service
[Unit]
Description=monitor process for deletion

[Service]
User=gha
WorkingDirectory=/home/gha
ExecStart=/bin/bash -c 'bash worker-monitor.sh'

[Install]
WantedBy=multi-user.target
EOF

# Distribute script and service to workers
gcloud compute instances describe gha-worker-${GITHUB_REF_NAME}-${GITHUB_SHA::7} \
--zone asia-southeast2-a --format=json | jq -r '.networkInterfaces | .[].networkIP' > ip

scp -o "StrictHostKeyChecking=no" actions-runner-linux.tar.gz label label_id worker.sh worker-exec.sh worker-rm-exec.sh gha worker-monitor.service  worker-monitor.sh gha@$(cat ip):~/

# Send Progress Signal
touch PROGRESS

# Execute Worker Setup Script
ssh -o "StrictHostKeyChecking=no" gha@$(cat ip) bash worker-exec.sh

cd ${CUR_DIR}
}

#################
# MAIN FUNCTION #
#################

CTRL_IP=$(hostname -i)
CUR_DIR=$(pwd)
DIR_ID=$(date +%N)

setup_ctrl
setup_worker