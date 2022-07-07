#!/bin/bash

cat << EOF > worker-rm.sh
#!/bin/bash

export LABEL=\${1}
export LABELID=\${2}

cd ~/\${LABELID}
sudo bash svc.sh stop
sudo bash svc.sh uninstall
./config.sh remove --token \$(cat ~/\${LABELID}/runner_token)
EOF

chmod +x worker-rm.sh

for i in `seq 1 $(cat label | wc -l)`; do 
	bash worker-rm.sh $(cat label | sed -n ${i}p) $(cat label_id | sed -n ${i}p)
done
