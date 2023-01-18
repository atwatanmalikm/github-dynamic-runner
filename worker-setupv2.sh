#!/bin/bash

###########################
# SETUP GHA CTRL FUNCTION #
###########################

setup_ctrl () {

# Install runner
mkdir -p RUNNING_RUNNER/${GITHUB_REF_NAME}-${GITHUB_SHA::7}-${DATE}-gha-ctrl
tar -xf arms/actions-runner-linux.tar.gz -C RUNNING_RUNNER/${GITHUB_REF_NAME}-${GITHUB_SHA::7}-${DATE}-gha-ctrl
cd RUNNING_RUNNER/${GITHUB_REF_NAME}-${GITHUB_SHA::7}-${DATE}-gha-ctrl

# Generate runner token
curl --silent -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token ${AUTH_TOKEN}" \
https://api.github.com/orgs/${GITHUB_REPOSITORY_OWNER}/actions/runners/registration-token | jq -r .token > runner_token

# Register Backup Controller Runner
./config.sh --url https://github.com/${GITHUB_REPOSITORY_OWNER} \
--token $(cat ${CUR_DIR}/RUNNING_RUNNER/${GITHUB_REF_NAME}-${GITHUB_SHA::7}-${DATE}-gha-ctrl/runner_token) --name gha-controller-${DATE} \
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

mkdir -p ${CUR_DIR}/RUNNING_RUNNER/${GITHUB_REF_NAME}-${GITHUB_SHA::7}-${DATE}-gha-worker
cd ${CUR_DIR}/RUNNING_RUNNER/${GITHUB_REF_NAME}-${GITHUB_SHA::7}-${DATE}-gha-worker

# Spawn worker VM
gcloud compute instances create gha-worker-${GITHUB_REF_NAME}-${GITHUB_SHA::7} \
--project=${PROJECT_ID} --zone=${ZONE} --machine-type=${MACHINE_TYPE} \
--network-interface=${NETWORK_SUBNET},no-address --metadata=enable-oslogin=true \
--no-restart-on-failure --maintenance-policy=TERMINATE --provisioning-model=SPOT \
--instance-termination-action=DELETE --service-account=${SERVICE_ACCOUNT} --scopes=${SCOPES} \
--create-disk=auto-delete=yes,boot=yes,device-name=gha-worker-3068,image=${IMAGE},mode=rw,size=15,type=projects/hijra-tools-stg/zones/asia-southeast2-a/diskTypes/pd-balanced \
--no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --reservation-affinity=any

cp ${CUR_DIR}/arms/actions-runner-linux.tar.gz .

sleep 45

# Get runner label list
#cat $GITHUB_WORKSPACE/.github/workflows/*.yml | grep runs-on | grep -v -E "gha-controller|windows|ubuntu|macos" | cut -d: -f2 | tr -d " " > label
WORKFLOW_FILE=$(grep -lr "name: $GITHUB_WORKFLOW" $GITHUB_WORKSPACE/.github/workflows | sed '1!D')
cat $WORKFLOW_FILE | grep runs-on | grep -v -E "gha-controller|windows|ubuntu|macos" | cut -d: -f2 | tr -d " " > label

RUNNER_NUM=$(cat label | wc -l)

if [[ $RUNNER_NUM -eq 0 ]]
then
  cat $GITHUB_WORKSPACE/.github/workflows/*.yml | grep runs-on | grep -v -E "gha-controller|windows|ubuntu|macos" | cut -d: -f2 | tr -d " " > label
fi

# Remove control M (^M)
sed -ie 's/\r//g' label

# Add unique ID for runner name
for i in $(cat label); do echo "${i}-$(date +%N)"; done > label_id

# Create register runner script
cat << EOF > register-runner.sh

#!/bin/bash

export LABEL=\${1}
export LABELID=\${2}

mkdir -p ~/\${LABELID}
tar -xf actions-runner-linux.tar.gz -C ~/\${LABELID}
cd ~/\${LABELID}

curl --silent -X POST -H "Accept: application/vnd.github.v3+json" -H "Authorization: token ${AUTH_TOKEN} " \
https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runners/registration-token | jq -r .token > runner_token

./config.sh --url https://github.com/$GITHUB_REPOSITORY --token \$(cat ~/\${LABELID}/runner_token) \
--name \${LABELID}-${GITHUB_SHA::7} --labels \${LABEL} --unattended

sudo bash svc.sh install
sudo bash svc.sh start
EOF

cat << EOF > register-runner-exec.sh
#!/bin/bash
sudo timedatectl set-timezone Asia/Jakarta

chmod +x worker.sh
for i in \`seq 1 \$(cat label | wc -l)\`; do 
	bash register-runner.sh \$(cat label | sed -n \${i}p) \$(cat label_id | sed -n \${i}p)
done
EOF

# Distribute script and service to workers
gcloud compute instances describe gha-worker-${GITHUB_REF_NAME}-${GITHUB_SHA::7} \
--zone asia-southeast2-a --format=json | jq -r '.networkInterfaces | .[].networkIP' > ip

scp -o "StrictHostKeyChecking=no" actions-runner-linux.tar.gz label label_id register-runner.sh register-runner-exec.sh gha@$(cat ip):~/

# Execute Register Runner Script
ssh -o "StrictHostKeyChecking=no" gha@$(cat ip) bash register-runner-exec.sh

cd ${CUR_DIR}
}

#################
# MAIN FUNCTION #
#################

PROJECT_ID=hijra-tools-stg
ZONE=asia-southeast2-a
MACHINE_TYPE=n2-custom-4-8192
NETWORK_SUBNET=subnet=projects/hijra-others-vpchost/regions/asia-southeast2/subnetworks/subnet-tools-stg-sea2-app
SERVICE_ACCOUNT=jenkins@hijra-tools-stg.iam.gserviceaccount.com
SCOPES=https://www.googleapis.com/auth/cloud-platform
IMAGE=projects/hijra-tools-stg/global/images/gha-worker-img
DATE=$(date +%y%m%d-%H%M%S)
CTRL_IP=$(hostname -i)
CUR_DIR=$(pwd)
GITHUB_REF_NAME=$(echo ${GITHUB_REF_NAME} | cut -d/ -f1 | tr '[:upper:]' '[:lower:]' | tr '.' '-')

# Determine Project ID
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

WORKER_ID=gha-worker-${PRJID}

# SETUP CTRL
setup_ctrl

# SETUP WORKER
setup_worker