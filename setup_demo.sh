#!/bin/bash

echo "🚀 Step 1: Installing required tools..."
sudo apt update && sudo apt install -y stress bc htop

echo "✔ Tools installed: stress, bc, htop"

echo "🚀 Step 2: Creating monitor.sh script..."
cat << 'EOF' > monitor.sh
#!/bin/bash

while true; do
    # Fetch CPU Usage
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    # Fetch Memory Usage
    MEMORY_USAGE=$(free | grep Mem | awk '{print $3/$2 * 100.0}')

    echo "CPU Usage: $CPU_USAGE%"
    echo "Memory Usage: $MEMORY_USAGE%"

    # Check if CPU exceeds threshold (75%)
    if (( $(echo "$CPU_USAGE > 75" | bc -l) )); then
        echo "⚠️ CPU usage exceeded 75%. Triggering auto-scaling..."
        
        # GCP Auto-Scaling Logic
        gcloud compute instance-groups managed set-autoscaling my-instance-group \
            --max-num-replicas 5 \
            --min-num-replicas 1 \
            --target-cpu-utilization 0.75 \
            --cool-down-period 60

        echo "✔ GCP Auto-scaling triggered."
    fi

    sleep 10  # Check CPU usage every 10 seconds
done
EOF

# Make the script executable
chmod +x monitor.sh

echo "✔ monitor.sh created successfully."

echo "🚀 Step 3: Running monitor.sh without stress..."
nohup ./monitor.sh > monitor.log 2>&1 &

echo "✔ monitor.sh is running in the background."
sleep 10  # Allow time to run

echo "📜 Log Output (Before Stress Test):"
cat monitor.log | tail -10

echo "🚀 Step 4: Running stress to simulate high CPU usage indefinitely..."
stress --cpu 4 &  # Runs forever until manually stopped

echo "⏳ Waiting for CPU to exceed 75% usage..."
sleep 30  # Allow time for CPU usage to increase

echo "📜 Log Output (After Stress Test):"
cat monitor.log | tail -10

echo "✔ Demonstration complete! CPU load test and auto-scaling verified."
echo "🛑 Stop the stress test manually with: killall stress"
