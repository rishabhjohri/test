#!/bin/bash

echo " Step 1: Installing required tools..."
sudo apt update && sudo apt install -y google-cloud-cli python3-pip bc htop

echo " Tools installed: google-cloud-cli, python3-pip, bc, htop"

echo " Step 2: Creating monitor.sh script..."
cat << 'EOF' > monitor.sh
#!/bin/bash

# Function to migrate workload to GCP if CPU exceeds 75%
migrate_workload() {
    echo " Migrating workload to GCP VM..."

    INSTANCE_NAME="autoscale-vm"
    ZONE="us-central1-a"  # Change to your preferred zone

    # Check if instance exists, if not, create it
    INSTANCE_CHECK=$(gcloud compute instances list --filter="name=${INSTANCE_NAME}" --format="value(name)")

    if [[ -z "$INSTANCE_CHECK" ]]; then
        echo " Instance does not exist. Creating a new one..."
        gcloud compute instances create "$INSTANCE_NAME" \
            --zone="$ZONE" \
            --machine-type="e2-standard-2" \
            --image-family="ubuntu-2204-lts" \
            --image-project="ubuntu-os-cloud" \
            --tags=http-server

        echo " GCP instance $INSTANCE_NAME created successfully."
    else
        echo " Instance $INSTANCE_NAME already exists."
    fi

    # Transfer compute.py to the instance
    gcloud compute scp compute.py ubuntu@$INSTANCE_NAME:~/compute.py --zone=$ZONE

    # SSH into the instance and execute compute.py
    gcloud compute ssh ubuntu@$INSTANCE_NAME --zone=$ZONE --command="python3 ~/compute.py"

    echo " Workload migrated and executed in the cloud."
}

while true; do
    # Fetch CPU Usage
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    echo "CPU Usage: $CPU_USAGE%"

    # Check if CPU exceeds threshold (75%)
    if (( $(echo "$CPU_USAGE > 75" | bc -l) )); then
        echo " CPU usage exceeded 75%. Migrating workload to GCP..."
        migrate_workload
        break  # Stop monitoring after migration
    fi

    sleep 5  # Check CPU usage every 5 seconds
done
EOF

# Make the script executable
chmod +x monitor.sh

echo " monitor.sh created successfully."

echo " Step 3: Running compute.py to generate CPU load..."
nohup python3 compute.py > compute.log 2>&1 &

echo " compute.py is running in the background."

echo " Step 4: Running monitor.sh to track CPU usage..."
nohup ./monitor.sh > monitor.log 2>&1 &

echo " Setup and monitoring started."
echo " Check logs using: cat monitor.log"
