#!/bin/bash

# Check if MongoDB container is running
echo "Checking if MongoDB is running..."
if ! docker ps --format '{{.Names}}' | grep -q 'mongodb'; then
    echo "Error: MongoDB container is not running! Start MongoDB using: docker start mongodb"
    exit 1
else
    echo "MongoDB is running."
fi

# Check if auth-container is running
echo "Checking if Authentication Service is running..."
if ! docker ps --format '{{.Names}}' | grep -q 'auth-container'; then
    echo "Error: Authentication service is not running! Start it using: docker start auth-container"
    exit 1
else
    echo "Authentication service is running."
fi

# Test API Endpoints
echo -e "\nTesting User Registration..."
REG_RESPONSE=$(curl -s -o response.txt -w "%{http_code}" -X POST "http://127.0.0.1:8000/api/auth/register" \
        -H "Content-Type: application/json" \
        -d '{"username": "testuser", "email": "test@example.com", "password": "securepassword"}')

if [[ "$REG_RESPONSE" -ne 200 && "$REG_RESPONSE" -ne 201 ]]; then
    echo "User registration failed! HTTP Status Code: $REG_RESPONSE"
    cat response.txt
    exit 1
fi

echo "User registration successful!"

echo -e "\nTesting User Login..."
LOGIN_RESPONSE=$(curl -s -o response.txt -w "%{http_code}" -X POST "http://127.0.0.1:8000/api/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"email": "test@example.com", "password": "securepassword"}')

if [[ "$LOGIN_RESPONSE" -ne 200 ]]; then
    echo "User login failed! HTTP Status Code: $LOGIN_RESPONSE"
    cat response.txt
    exit 1
fi

echo "User login successful!"
