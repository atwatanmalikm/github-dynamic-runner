#!/bin/bash
sudo timedatectl set-timezone Asia/Jakarta
cp gha ~/.ssh/id_rsa && chmod 600 ~/.ssh/id_rsa
chmod +x worker-monitor.sh
sudo cp worker-monitor.service /etc/systemd/system
sudo systemctl daemon-reload

chmod +x worker.sh
for i in `seq 1 $(cat label | wc -l)`; do 
	bash worker.sh $(cat label | sed -n ${i}p) $(cat label_id | sed -n ${i}p)
done

sudo systemctl start worker-monitor.service
