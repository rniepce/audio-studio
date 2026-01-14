from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pathlib import Path
from typing import List, Optional
from pydantic import BaseModel

from config import FILES_DIR, setup_logging
from db import load_songs, get_file_path

logger = setup_logging("api")

app = FastAPI(title="Song Manager API")

class Song(BaseModel):
    id: str
    title: str
    artist: str
    lyrics: str
    chords_text: str
    audio_filename: Optional[str] = None
    pdf_filename: Optional[str] = None

@app.get("/")
def read_root():
    return {"message": "Song Manager API is running"}

@app.get("/songs", response_model=List[Song])
def get_songs():
    """Returns the list of all songs."""
    songs = load_songs()
    return songs

@app.get("/files/{filename}")
def get_file(filename: str):
    """Serves audio and PDF files."""
    file_path = get_file_path(filename)
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="File not found")
    
    return FileResponse(file_path)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
