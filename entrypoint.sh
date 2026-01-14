#!/bin/bash

echo "🚀 Starting Song Manager Cloud (All-in-One)..."

# 1. Start API (FastAPI) on Port 8000 (Local Only)
cd /app/song_manager/backend
echo "Starting API on port 8000..."
uvicorn api:app --host 127.0.0.1 --port 8000 > /app/api.log 2>&1 &

# 2. Start Admin Dashboard (Streamlit) on Port 8501 (Local Only)
echo "Starting Admin Dashboard on port 8501..."
streamlit run admin.py --server.port 8501 --server.address 127.0.0.1 --server.headless true > /app/streamlit.log 2>&1 &

# 3. Start Nginx (Reverse Proxy) on Port 8080 (Public)
# This routes traffic to either API or Admin based on URL
echo "Starting Nginx on port 8080..."
nginx -g "daemon off;"
