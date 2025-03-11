#!/bin/bash

echo " Step 1: Installing required tools..."
sudo apt update && sudo apt install -y stress bc htop google-cloud-cli python3-pip

echo " Tools installed: stress, bc, htop, GCP SDK"

echo " Step 2: Setting Up GCP SDK"
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/zone YOUR_COMPUTE_ZONE

echo " GCP SDK configured."

echo " Step 3: Creating monitor.sh script..."
cat << 'EOF' > monitor.sh
#!/bin/bash

# Function to migrate workload to GCP using SCP
migrate_workload() {
    echo " Checking if GCP instance exists..."

    # Set instance variables
    INSTANCE_NAME="autoscale-vm"
    ZONE="us-central1-a"  # Change to your preferred zone
    MACHINE_TYPE="e2-standard-2"  # Adjust machine type if needed
    IMAGE_FAMILY="ubuntu-2204-lts"
    IMAGE_PROJECT="ubuntu-os-cloud"

    # Check if instance exists
    INSTANCE_CHECK=$(gcloud compute instances list --filter="name=${INSTANCE_NAME}" --format="value(name)")

    if [[ -z "$INSTANCE_CHECK" ]]; then
        echo " Instance does not exist. Creating a new one..."
        gcloud compute instances create "$INSTANCE_NAME" \
            --zone="$ZONE" \
            --machine-type="$MACHINE_TYPE" \
            --image-family="$IMAGE_FAMILY" \
            --image-project="$IMAGE_PROJECT" \
            --tags=http-server

        echo "✔ GCP instance $INSTANCE_NAME created successfully."
    else
        echo "✔ Instance $INSTANCE_NAME already exists."
    fi

    echo " Migrating workload to GCP VM..."
    
    # Transfer compute.py to the instance
    gcloud compute scp compute.py ubuntu@$INSTANCE_NAME:~/compute.py --zone=$ZONE

    # SSH into the instance and execute compute.py
    gcloud compute ssh ubuntu@$INSTANCE_NAME --zone=$ZONE --command="python3 ~/compute.py"

    echo " Workload migrated and executed in the cloud."
}

while true; do
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    echo "CPU Usage: $CPU_USAGE%"
    if (( $(echo "$CPU_USAGE > 75" | bc -l) )); then
        echo " CPU usage exceeded 75%. Triggering auto-scaling..."
        gcloud compute instance-groups managed set-autoscaling my-instance-group \
            --max-num-replicas 5 \
            --min-num-replicas 1 \
            --target-cpu-utilization 0.75 \
            --cool-down-period 60
        migrate_workload
    fi
    sleep 10
done
EOF

chmod +x monitor.sh

echo " Step 4: Running monitor.sh..."
nohup ./monitor.sh > monitor.log 2>&1 &

echo " Setup and demonstration completed."
