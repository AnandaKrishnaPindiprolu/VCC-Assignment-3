

GCP_ZONE="us-central1-a"
LOCAL_DATA_PATH="$HOME/local/data"
REMOTE_DATA_PATH="C:/data"
GCP_USER="winadmin"
CPU_THRESHOLD=75
APP_DIR="C:/MyApp"
PORT=8080

gcloud auth activate-service-account --key-file=g24ai1112-assignment3-34049c1ef8e8.json
gcloud config set project assignment3-453515

CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
echo "CPU Usage of VM: $CPU_USAGE%"

INSTANCE_NAME=$(gcloud compute instance-groups managed list-instances win-auto-scale-group --zone $GCP_ZONE --format="value(name)" | head -n 1)

if (( $(echo "$CPU_USAGE > $CPU_THRESHOLD" | bc -l) )); then
    if [ -z "$INSTANCE_NAME" ]; then
        echo "CPU usage exceeded the threshold $CPU_THRESHOLD%. Creating a new Windows Virtual Machine in GCP..."

        gcloud compute instance-templates create win-auto-template \
            --image-family windows-2022 \
            --image-project windows-cloud \
            --machine-type e2-standard-2 \
            --boot-disk-size 50GB \
            --metadata startup-script-ps1="
                choco install -y nodejs
                Install-WindowsFeature -name Web-Server -IncludeManagementTools
                mkdir $APP_DIR
                Set-Location $APP_DIR
                npm init -y
                npm install express
                New-Item -Path app.js -ItemType File -Value @\"
                const express = require('express');
                const app = express();
                const port = $PORT;
                app.get('/', (req, res) => res.send('windows machine!'));
                app.listen(port, () => console.log('App listening on port ' + port));
                \"@
                Start-Process -NoNewWindow node -ArgumentList 'app.js'
                New-Item -Path \"C:/inetpub/wwwroot/Default.htm\" -ItemType File -Force -Value \"<html><body><h2>welcome to Node.js Application</h2></body></html>\"
                iisreset
            " \
            --tags http-server,https-server

        gcloud compute instance-groups managed create win-auto-scale-group \
            --base-instance-name win-auto-instance \
            --template win-auto-template \
            --size 1 \
            --zone $GCP_ZONE

        gcloud compute instance-groups managed set-autoscaling win-auto-scale-group \
            --max-num-replicas 5 \
            --min-num-replicas 1 \
            --target-cpu-utilization 0.75 \
            --cool-down-period 60 \
            --zone $GCP_ZONE

        GCP_VM_NAME=$(gcloud compute instance-groups managed list-instances win-auto-scale-group --zone $GCP_ZONE --format="value(name)" | head -n 1)

        echo "initialization of VM"
        sleep 60

        echo " data Transferring to Windows VM..."
        gcloud compute scp --recurse "$LOCAL_DATA_PATH" "$GCP_USER@$GCP_VM_NAME:$REMOTE_DATA_PATH" --zone="$GCP_ZONE"
        
        echo "Windows instance completed: $GCP_VM_NAME"
        
        echo "Accessing logs for verification..."
        gcloud compute ssh $GCP_VM_NAME --zone $GCP_ZONE --command "
          Get-Content C:/MyApp/logs/app.log
        "
    else
        echo "An existing Windows instance is already present upon running."
    fi

elif (( $(echo "$CPU_USAGE < $CPU_THRESHOLD" | bc -l) )); then
    if [ -n "$INSTANCE_NAME" ]; then
        echo "CPU usage is as per threshold below $CPU_THRESHOLD%. Deleting the Windows VM..."
        gcloud compute instance-groups managed delete win-auto-scale-group --zone $GCP_ZONE
        echo "Deleted the managed instance group and VMs."
    else
        echo "No active Windows instance to delete."
    fi
fi
