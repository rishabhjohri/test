from flask import Flask, render_template, jsonify
import psutil
import numpy as np
import subprocess

app = Flask(__name__)

# GCP Instance Details
GCP_INSTANCE = "autoscale-vm"
GCP_ZONE = "us-central1-a"
GCP_USER = "ubuntu"

# Function to get CPU usage
def get_cpu_usage():
    return psutil.cpu_percent(interval=1)

# Function to run heavy computation (to increase CPU usage)
def cpu_intensive_task():
    print("🚀 Running heavy computation...")
    
    size = 4000  # Large matrix size for high CPU load
    matrix_a = np.random.rand(size, size)
    matrix_b = np.random.rand(size, size)

    result = np.matmul(matrix_a, matrix_b)
    
    print("✔ Computation completed!")

# Function to migrate workload to GCP
def migrate_to_gcp():
    print("⚠️ High CPU detected! Migrating workload to GCP...")

    # Check if the instance exists, create if not
    instance_check = subprocess.run(
        f"gcloud compute instances list --filter='name={GCP_INSTANCE}' --format='value(name)'",
        shell=True, capture_output=True, text=True
    )

    if not instance_check.stdout.strip():
        print(f"⚠️ Instance {GCP_INSTANCE} does not exist. Creating it now...")
        subprocess.run(
            f"gcloud compute instances create {GCP_INSTANCE} --zone={GCP_ZONE} "
            f"--machine-type=e2-standard-2 --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud",
            shell=True
        )

    # Transfer Flask App to GCP
    subprocess.run(f"gcloud compute scp -r . {GCP_USER}@{GCP_INSTANCE}:~/webapp --zone={GCP_ZONE}", shell=True)

    # SSH to GCP and install dependencies before running app
    subprocess.run(
        f"gcloud compute ssh {GCP_USER}@{GCP_INSTANCE} --zone={GCP_ZONE} --command="
        f"'sudo apt update && sudo apt install -y python3-flask python3-psutil python3-pip && pip install flask psutil paramiko && cd ~/webapp && python3 app.py'",
        shell=True
    )

    print("✔ Workload successfully migrated to GCP!")

# Flask Route: Web Dashboard
@app.route('/')
def index():
    return render_template("index.html")

# Flask Route: API to get CPU usage
@app.route('/cpu_usage')
def cpu_usage():
    usage = get_cpu_usage()
    
    if usage > 75:
        migrate_to_gcp()

    return jsonify({"cpu_usage": usage})

# Flask Route: Start Heavy Computation
@app.route('/start_compute')
def start_compute():
    cpu_intensive_task()
    return jsonify({"status": "Computation started!"})

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5000, debug=True)
