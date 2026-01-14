FROM python:3.10-slim

# Install system dependencies (FFmpeg is crucial)
RUN apt-get update && apt-get install -y \
    ffmpeg \
    libsndfile1 \
    git \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Work directory
WORKDIR /app

# Copy requirements first (for caching)
COPY song_manager/backend/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY . /app

# Expose ports
# 8000 = API (FastAPI)
# 8501 = Admin (Streamlit)
EXPOSE 8000
EXPOSE 8501

# Environment variables
ENV PORT=8000
ENV HOST=0.0.0.0

# Startup script
RUN chmod +x /app/entrypoint.sh

# Run
CMD ["/app/entrypoint.sh"]
