#!/bin/bash
AUTH_TOKEN=
GITHUB_REPOSITORY_OWNER=alami-group
CUR_DIR=$(pwd)
ORG_RUNNER_DIR=gha-controller-org

STG=$(hostname | grep tools-stg | wc -l)
PROD=$(hostname | grep hijrabank-tools | wc -l)

if [[ $STG -ge 1 ]]
then
  PRJID=stg
elif [[ $PROD -ge 1 ]]
then
  PRJID=prod
else
  PRJID=dev
fi

# Config SSH
mkdir -p ~/.ssh/
cp arms/ssh_config ~/.ssh/config

# Register Controller Runner
mkdir -p ${ORG_RUNNER_DIR}
gcloud storage cp gs://hijra-tools-stg-runner/actions-runner-linux.tar.gz ${ORG_RUNNER_DIR}/

cd ${ORG_RUNNER_DIR}/
curl --silent -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token ${AUTH_TOKEN}" \
https://api.github.com/orgs/${GITHUB_REPOSITORY_OWNER}/actions/runners/registration-token | jq -r .token > runner_token

./config.sh --url https://github.com/${GITHUB_REPOSITORY_OWNER} \
--token $(cat ${CUR_DIR}/${ORG_RUNNER_DIR}/runner_token) --name hijra-ghrunner-${PRJID} \
--labels gha-controller-${PRJID} --unattended

sudo bash svc.sh install
sudo bash svc.sh start

cd ${CUR_DIR}

# Setup Live Controller & Worker Monitoring Service
cp arms/*-mon.sh .

cat << CTRL > ctrl-mon.service
[Unit]
Description=monitor process for ctrl deletion

[Service]
User=runner
WorkingDirectory=${CUR_DIR}
ExecStart=/bin/bash -c 'bash ctrl-mon.sh'

[Install]
WantedBy=multi-user.target
CTRL

cat << WORKER > worker-mon.service
[Unit]
Description=monitor process for worker deletion

[Service]
User=runner
WorkingDirectory=${CUR_DIR}
ExecStart=/bin/bash -c 'bash worker-mon.sh'

[Install]
WantedBy=multi-user.target
WORKER

sudo mv ctrl-mon.service worker-mon.service /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now ctrl-mon.service
sudo systemctl enable --now worker-mon.service

# Download action runner
gcloud storage cp gs://hijra-tools-stg-runner/actions-runner-linux.tar.gz arms/