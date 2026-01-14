#!/bin/bash

# Navigate to backend directory
cd song_manager/backend

# Check/Create venv
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "Virtual Environment Created."
fi
source venv/bin/activate

# Dependency Check using MD5 of requirements.txt
REQ_HASH=$(md5 -q requirements.txt)
if [ -f "installed.hash" ]; then
    INSTALLED_HASH=$(cat installed.hash)
else
    INSTALLED_HASH=""
fi

if [ "$REQ_HASH" != "$INSTALLED_HASH" ]; then
    echo "📦 Nossos requisitos mudaram. Atualizando bibliotecas..."
    pip install -r requirements.txt
    echo "$REQ_HASH" > installed.hash
    echo "✅ Bibliotecas atualizadas!"
fi

echo "---------------------------------------------------"
echo "🎵 Song Manager Studio"
echo "---------------------------------------------------"
echo "Se o IP abaixo não funcionar no iPhone, tente desativar o Firewall"
echo "ou verifique se o Mac e o iPhone estão no MESMO Wi-Fi."
echo "---------------------------------------------------"
echo "LINK DO IPHONE (Abra no Safari):"
ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print "http://"$2":8502"}'
echo ""
echo "LINK DO MAC (Admin):"
echo "http://localhost:8501"
echo "---------------------------------------------------"

# Run API Server (FastAPI) for Native App
echo "Starting API Server..."
uvicorn api:app --host 0.0.0.0 --port 8000 > /dev/null 2>&1 &
API_PID=$!

# Run Admin Dashboard in background
streamlit run admin.py --server.port 8501 --server.headless true > /dev/null 2>&1 &
ADMIN_PID=$!

# Run Mobile App in foreground (still accessible as web backup)
streamlit run mobile.py --server.port 8502 --server.address 0.0.0.0 --server.headless true

# Cleanup
kill $API_PID
kill $ADMIN_PID
