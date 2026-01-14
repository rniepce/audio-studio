"""
Shared database utilities for Song Manager.
Centralizes file I/O and JSON handling.
"""
import json
import html
from pathlib import Path
from typing import Optional

from config import DATA_DIR, DB_FILE, FILES_DIR, setup_logging

# Setup logger
logger = setup_logging("db")


def load_songs() -> list[dict]:
    """Load all songs from the JSON database, sorted by title."""
    if not DB_FILE.exists():
        return []
    try:
        data = json.loads(DB_FILE.read_text(encoding="utf-8"))
        return sorted(data, key=lambda x: x.get('title', '').lower())
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse songs_db.json: {e}")
        return []
    except OSError as e:
        logger.error(f"Failed to read songs_db.json: {e}")
        return []


def save_songs(songs: list[dict]) -> None:
    """Save all songs to the JSON database."""
    DB_FILE.write_text(
        json.dumps(songs, indent=4, ensure_ascii=False),
        encoding="utf-8"
    )
    logger.info(f"Saved {len(songs)} songs to database")


def save_uploaded_file(uploaded_file, song_id: str, suffix: str) -> str:
    """Save an uploaded file and return its filename."""
    ext = Path(uploaded_file.name).suffix.lower()
    filename = f"{song_id}_{suffix}{ext}"
    file_path = FILES_DIR / filename
    file_path.write_bytes(uploaded_file.getbuffer())
    logger.info(f"Saved uploaded file: {filename}")
    return filename


def delete_file(filename: Optional[str]) -> None:
    """Safely delete a file from the files directory."""
    if filename:
        file_path = FILES_DIR / filename
        if file_path.exists():
            file_path.unlink()
            logger.info(f"Deleted file: {filename}")


def escape_html(text: Optional[str]) -> str:
    """Escape HTML special characters to prevent XSS attacks."""
    if text:
        return html.escape(text)
    return ""


def get_file_path(filename: str) -> Path:
    """Get the full path to a file in the files directory."""
    return FILES_DIR / filename
