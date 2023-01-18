#!/bin/bash

# Install Terraform
#sudo apt-get update && sudo apt-get install -y gnupg software-properties-common jq
#
#wget -O- https://apt.releases.hashicorp.com/gpg | \
#    gpg --dearmor | \
#    sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
#
#gpg --no-default-keyring \
#    --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
#    --fingerprint
#
#echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
#    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
#    sudo tee /etc/apt/sources.list.d/hashicorp.list
#
#sudo apt update && sudo apt-get install terraform -y


# Setup Live Controller & Worker Monitoring Service

cat << CTRL > ctrl-mon.service
[Unit]
Description=monitor process for ctrl deletion

[Service]
User=runner
WorkingDirectory=/mnt/runner
ExecStart=/bin/bash -c 'bash ctrl-monv2.sh'

[Install]
WantedBy=multi-user.target
CTRL

cat << WORKER > worker-mon.service
[Unit]
Description=monitor process for worker deletion

[Service]
User=runner
WorkingDirectory=/mnt/runner
ExecStart=/bin/bash -c 'bash worker-monv2.sh'

[Install]
WantedBy=multi-user.target
WORKER

sudo mv ctrl-mon.service worker-mon.service /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now ctrl-mon.service
sudo systemctl enable --now worker-mon.service

# Setup gha pubkey
cat arms/gha.pub >>  ~/.ssh/authorized_keys