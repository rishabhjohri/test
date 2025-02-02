#!/bin/bash

echo "Testing User Registration..."
curl -X POST "http://127.0.0.1:8000/api/auth/register" \
     -H "Content-Type: application/json" \
     -d '{"username": "testuser", "email": "test@example.com", "password": "securepassword"}'

echo -e "\nTesting User Login..."
curl -X POST "http://127.0.0.1:8000/api/auth/login" \
     -H "Content-Type: application/json" \
     -d '{"email": "test@example.com", "password": "securepassword"}'
