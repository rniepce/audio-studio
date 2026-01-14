#!/bin/bash

echo "🚀 Starting Song Manager Cloud..."

# 1. Start API (FastAPI) on Port 8000 (Background)
# This powers the iPhone App
cd /app/song_manager/backend
echo "Starting API on port 8000..."
uvicorn api:app --host 0.0.0.0 --port 8000 > /app/api.log 2>&1 &

# 2. Start Admin Dashboard (Streamlit) on Port 8501 (Foreground)
# This is for you to manage songs via browser
echo "Starting Admin Dashboard on port 8501..."
streamlit run admin.py --server.port 8501 --server.address 0.0.0.0 --server.headless true
