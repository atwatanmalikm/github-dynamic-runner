#!/bin/bash

CTRL_IP=$(hostname -i)
CUR_DIR=$(pwd)

###### Setup gha-controller
DIR_ID=$(date +%N)

mkdir -p gha-ctrl-${DIR_ID}
tar -xf arms/actions-runner-linux.tar.gz -C gha-ctrl-${DIR_ID}
cd gha-ctrl-${DIR_ID}

#curl --silent -X POST -H "Accept: application/vnd.github.v3+json" -H "Authorization: token ${AUTH_TOKEN} "  https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runners/registration-token | jq -r .token > runner_token
curl --silent -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token ${AUTH_TOKEN}" https://api.github.com/orgs/${GITHUB_REPOSITORY_OWNER}/actions/runners/registration-token | jq -r .token > runner_token

#./config.sh --url https://github.com/$GITHUB_REPOSITORY --token $(cat ${CUR_DIR}/gha-ctrl-${DIR_ID}/runner_token) --name gha-controller-${DIR_ID} --labels gha-controller --unattended --ephemeral
./config.sh --url https://github.com/${GITHUB_REPOSITORY_OWNER} --token $(cat ${CUR_DIR}/gha-ctrl-${DIR_ID}/runner_token) --name gha-controller-${DIR_ID} --labels gha-controller --unattended --ephemeral
sudo bash svc.sh install
sudo bash svc.sh start

cd ${CUR_DIR}

###### Setup gha-worker

mkdir -p ${CUR_DIR}/tf-${GITHUB_REF_NAME}-${GITHUB_SHA::7}

### ctrl-monitor@.service
cat << EOF > ctrl-monitor@.service
[Unit]
Description=monitor process for deletion

[Service]
User=runner
WorkingDirectory=${CUR_DIR}
ExecStart=/bin/bash -c 'bash ctrl-monitor.sh %i'

[Install]
WantedBy=multi-user.target
EOF

sudo cp ctrl-monitor@.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start ctrl-monitor@tf-${GITHUB_REF_NAME}-${GITHUB_SHA::7}.service
sudo systemctl status ctrl-monitor@tf-${GITHUB_REF_NAME}-${GITHUB_SHA::7}.service

sed "s/name         =/name         = \"gha-worker-${GITHUB_REF_NAME}-${GITHUB_SHA::7}\"/g" arms/main.tf.template > ${CUR_DIR}/tf-${GITHUB_REF_NAME}-${GITHUB_SHA::7}/main.tf
cd ${CUR_DIR}/tf-${GITHUB_REF_NAME}-${GITHUB_SHA::7} && terraform init && terraform apply -auto-approve
cp ${CUR_DIR}/arms/* .

sleep 30

### worker.sh
cat $GITHUB_WORKSPACE/.github/workflows/*.yml | grep runs-on | grep -v -E "gha-controller|windows|ubuntu|macos" | cut -d: -f2 | tr -d " " > label
for i in $(cat label); do echo ${i}-$(date +%N); done > label_id

cat << EOF > worker.sh

#!/bin/bash

export LABEL=\${1}
export LABELID=\${2}

mkdir -p ~/\${LABELID}
tar -xf actions-runner-linux.tar.gz -C ~/\${LABELID}
cd ~/\${LABELID}

curl --silent -X POST -H "Accept: application/vnd.github.v3+json" -H "Authorization: token ${AUTH_TOKEN} "  https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runners/registration-token | jq -r .token > runner_token
./config.sh --url https://github.com/$GITHUB_REPOSITORY --token \$(cat ~/\${LABELID}/runner_token) --name \${LABELID}-${GITHUB_SHA::7} --labels \${LABEL} --unattended --ephemeral
sudo bash svc.sh install
sudo bash svc.sh start
EOF


### worker-monitor.sh
cat << EOF > worker-monitor.sh
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
		if [ \$proc2 -eq 0 ]
		then
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
EOF


### worker-monitor.service
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

gcloud compute instances describe gha-worker-${GITHUB_REF_NAME}-${GITHUB_SHA::7} --zone asia-southeast2-a --format=json | jq -r '.networkInterfaces | .[].networkIP' > ip
scp -o "StrictHostKeyChecking=no" actions-runner-linux.tar.gz label label_id worker.sh worker-exec.sh worker-rm-exec.sh gha worker-monitor.service  worker-monitor.sh gha@$(cat ip):~/

### Progress
touch PROGRESS

ssh -o "StrictHostKeyChecking=no" gha@$(cat ip) bash worker-exec.sh

cd ${CUR_DIR}
