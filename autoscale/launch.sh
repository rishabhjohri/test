#!/bin/bash

echo "🚀 Step 1: Installing required tools..."
sudo apt update && sudo apt install -y python3-flask python3-psutil python3-pip google-cloud-cli

echo "✔ Tools installed: Flask, psutil, GCP SDK"

echo "🚀 Step 2: Setting Up GCP SDK"
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/zone YOUR_COMPUTE_ZONE

echo "✔ GCP SDK configured."

echo "🚀 Step 3: Deploying Flask App Locally..."
nohup python3 app.py > app.log 2>&1 &

echo "✔ Web App is running locally at http://localhost:5000"

echo "🚀 Step 4: Monitoring CPU Usage & Migrating to GCP if needed..."
nohup python3 -c "
import time, requests
while True:
    res = requests.get('http://localhost:5000/cpu_usage').json()
    print('CPU Usage:', res['cpu_usage'])
    time.sleep(5)
" > monitor.log 2>&1 &
