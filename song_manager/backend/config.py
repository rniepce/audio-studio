"""
Centralized configuration for Song Manager.
Uses pathlib for all paths and configures structured logging.
"""
import logging
from pathlib import Path
from typing import Final

import os

# === Paths ===
BACKEND_DIR: Final[Path] = Path(__file__).parent.resolve()

# Check for environment variable (Cloud/Docker)
if "STORAGE_DIR" in os.environ:
    DATA_DIR: Final[Path] = Path(os.environ["STORAGE_DIR"])
else:
    DATA_DIR: Final[Path] = BACKEND_DIR / "data"

DB_FILE: Final[Path] = DATA_DIR / "songs_db.json"
FILES_DIR: Final[Path] = DATA_DIR / "files"

# Ensure directories exist
DATA_DIR.mkdir(parents=True, exist_ok=True)
FILES_DIR.mkdir(parents=True, exist_ok=True)

# === Audio Processing Defaults ===
AUDIO_DEFAULTS: Final[dict] = {
    "highpass_cutoff_hz": 30,
    "noise_gate_threshold_db": -60,
    "noise_gate_ratio": 4,
    "noise_gate_release_ms": 250,
    "low_shelf_freq_hz": 100,
    "mid_peak_freq_hz": 1000,
    "high_shelf_freq_hz": 5000,
    "compressor_attack_ms": 15,
    "compressor_release_ms": 200,
    "limiter_threshold_db": -1.0,
}

# === Chord Detection ===
CHORD_LABELS: Final[tuple[str, ...]] = (
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
)
CHORD_ROOTS_ENHARMONIC: Final[tuple[str, ...]] = (
    'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'
)

# === Logging Setup ===
def setup_logging(name: str = "song_manager") -> logging.Logger:
    """Configure and return a logger with consistent formatting."""
    logger = logging.getLogger(name)
    
    if not logger.handlers:
        handler = logging.StreamHandler()
        formatter = logging.Formatter(
            "[%(levelname)s] %(name)s: %(message)s"
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
    
    return logger

# Create default logger
logger = setup_logging()
