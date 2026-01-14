"""
Audio processing utilities for Song Manager.
Provides mastering, stem separation, and chord detection functions.
"""
import os
import sys
import subprocess
from pathlib import Path
from typing import Optional

import numpy as np
import soundfile as sf
from pedalboard import (
    Pedalboard, Compressor, HighpassFilter, Limiter,
    Reverb, NoiseGate, LowShelfFilter, HighShelfFilter, PeakFilter
)
import noisereduce as nr
import librosa
import scipy.signal

from config import (
    FILES_DIR, AUDIO_DEFAULTS, CHORD_LABELS, CHORD_ROOTS_ENHARMONIC,
    setup_logging
)

logger = setup_logging("audio_utils")


def get_file_path(filename: str) -> Path:
    """Get the full path to a file in the files directory."""
    return FILES_DIR / filename



def load_audio_file(file_or_path) -> tuple[np.ndarray, int]:
    """
    Load audio from a file path or file-like object.
    Returns (audio_data, sample_rate).
    audio_data shape: (channels, samples) or (samples,)
    """
    # 1. Try SoundFile first (Fastest)
    try:
        # If it's a file-like object, make sure we are at the start
        if hasattr(file_or_path, 'seek'):
            file_or_path.seek(0)
        
        audio, sr = sf.read(file_or_path)
        return audio, sr
    except Exception as e:
        logger.warning(f"SoundFile failed to load audio: {e}. Trying Librosa...")

    # 2. Fallback to Librosa (Slower but supports more formats like M4A/AAC via ffmpeg)
    try:
        # Librosa generally needs a file path. 
        # If input is a file-like object, we might need a temp file.
        path_to_load = file_or_path
        is_temp = False

        if not isinstance(file_or_path, (str, Path)):
             # It's a file-like object (BytesIO, SpooledTemporaryFile)
             # We create a temp file to pass to librosa
            import tempfile
            import shutil
            
            # Reset pointer
            if hasattr(file_or_path, 'seek'):
                file_or_path.seek(0)
                
            suffix = ".tmp"
            # Try to guess extension if possible (e.g. from streamlit uploaded_file)
            if hasattr(file_or_path, 'name'):
                suffix = Path(file_or_path.name).suffix

            with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
                shutil.copyfileobj(file_or_path, tmp)
                path_to_load = tmp.name
                is_temp = True

        # Load with librosa (preserve SR and formatting)
        # librosa loads as (channels, samples) but mono=False ensures we get channels
        # sr=None preserves original sampling rate
        y, sr = librosa.load(path_to_load, sr=None, mono=False)
        
        # Librosa returns (channels, samples). SoundFile returns (samples, channels).
        # We generally want what the caller expects. 
        # app.py's audio_to_bytes expects (samples, channels) usually, but pedalboard handles both.
        # Let's standardize to (samples, channels) to match sf.read default behavior for compatibility.
        if y.ndim > 1:
            y = y.T

        if is_temp:
            os.remove(path_to_load)

        return y, sr

    except Exception as e:
        logger.error(f"Failed to load audio with Librosa: {e}")
        raise RuntimeError(f"Could not load audio file: {e}")


def extract_audio_from_video(input_video_path: str, output_audio_path: str) -> bool:
    """
    Extracts audio from a video file using ffmpeg.
    Saves as WAV/MP3 depending on output extension.
    Returns True if successful.
    """
    logger.info(f"Extracting audio from video: {input_video_path} -> {output_audio_path}")
    
    cmd = [
        "ffmpeg", 
        "-y", # Overwrite output
        "-i", str(input_video_path),
        "-vn", # No video
        "-acodec", "pcm_s16le", # WAV standard
        "-ar", "44100", # 44.1kHz
        "-ac", "2", # Stereo
        str(output_audio_path)
    ]
    
    try:
        process = subprocess.run(cmd, capture_output=True, text=True)
        if process.returncode == 0:
            logger.info("Audio extraction complete")
            return True
        else:
            logger.error(f"FFmpeg extraction failed: {process.stderr}")
            return False
    except FileNotFoundError:
        logger.error("FFmpeg not found in PATH")
        return False
    except Exception as e:
        logger.error(f"Error extracting audio: {e}")
        return False


def process_audio_data(
    audio_input: np.ndarray,
    sample_rate: int,
    apply_nr: bool,
    nr_prop: float,
    low_gain: float,
    mid_gain: float,
    high_gain: float,
    comp_thresh: float,
    comp_ratio: float,
    reverb_on: bool,
    reverb_size: float,
    reverb_wet: float,
    defaults: dict = AUDIO_DEFAULTS
) -> np.ndarray:
    """
    Apply the complete mastering chain to audio data (numpy array).
    Returns processed audio data.
    """
    processed_audio = audio_input.copy()

    # 1. Noise Reduction
    if apply_nr:
        try:
            processed_audio = nr.reduce_noise(
                y=processed_audio,
                sr=sample_rate,
                prop_decrease=nr_prop,
                stationary=True
            )
            logger.info("Applied noise reduction")
        except ValueError as e:
            logger.warning(f"Noise reduction failed (invalid audio): {e}")
        except RuntimeError as e:
            logger.error(f"Noise reduction runtime error: {e}")

    # 2. Pedalboard Chain
    board = Pedalboard([
        HighpassFilter(cutoff_frequency_hz=defaults["highpass_cutoff_hz"]),
        NoiseGate(
            threshold_db=defaults["noise_gate_threshold_db"],
            ratio=defaults["noise_gate_ratio"],
            release_ms=defaults["noise_gate_release_ms"]
        ),

        # EQ
        LowShelfFilter(cutoff_frequency_hz=defaults["low_shelf_freq_hz"], gain_db=low_gain),
        PeakFilter(cutoff_frequency_hz=defaults["mid_peak_freq_hz"], gain_db=mid_gain),
        HighShelfFilter(cutoff_frequency_hz=defaults["high_shelf_freq_hz"], gain_db=high_gain),

        # Dynamics
        Compressor(
            threshold_db=comp_thresh,
            ratio=comp_ratio,
            attack_ms=defaults["compressor_attack_ms"],
            release_ms=defaults["compressor_release_ms"]
        ),

        # Effects
        Reverb(
            room_size=reverb_size,
            wet_level=reverb_wet if reverb_on else 0.0,
            dry_level=1.0
        ),

        # Safety Limiter
        Limiter(threshold_db=defaults["limiter_threshold_db"])
    ])

    return board(processed_audio, sample_rate)


def perform_mastering(
    input_filename: str,
    output_filename: str,
    apply_nr: bool,
    nr_prop: float,
    low_gain: float,
    mid_gain: float,
    high_gain: float,
    comp_thresh: float,
    comp_ratio: float,
    reverb_on: bool,
    reverb_size: float,
    reverb_wet: float
) -> str:
    """
    Applies the mastering chain to the input file and saves to output file.
    Returns the filename of the output file.
    """
    input_path = get_file_path(input_filename)
    output_path = get_file_path(output_filename)

    logger.info(f"Starting mastering: {input_filename}")

    # Read Audio
    audio_input, sample_rate = load_audio_file(str(input_path))

    # Ensure (channels, samples) format for pedalboard
    if len(audio_input.shape) == 1:
        audio_input = audio_input[np.newaxis, :]
    else:
        audio_input = audio_input.T

    # Process
    final_audio = process_audio_data(
        audio_input, sample_rate,
        apply_nr, nr_prop,
        low_gain, mid_gain, high_gain,
        comp_thresh, comp_ratio,
        reverb_on, reverb_size, reverb_wet
    )

    # Transpose back for writing: (samples, channels)
    if final_audio.ndim > 1 and final_audio.shape[0] < final_audio.shape[1]:
        final_audio = final_audio.T

    sf.write(str(output_path), final_audio, sample_rate, format='WAV')
    logger.info(f"Mastering complete: {output_filename}")

    return output_filename


def perform_separation(input_filename: str) -> bool:
    """
    Runs Demucs on the input file.
    Returns True if successful.
    """
    input_path = get_file_path(input_filename)
    out_dir = FILES_DIR / "separation_output"
    out_dir.mkdir(exist_ok=True)

    logger.info(f"Starting stem separation: {input_filename}")

    cmd = [sys.executable, "-m", "demucs", "-n", "htdemucs", "--out", str(out_dir), str(input_path)]

    try:
        process = subprocess.run(cmd, capture_output=True, text=True)
        if process.returncode == 0:
            logger.info("Stem separation complete")
            return True
        else:
            logger.error(f"Demucs error: {process.stderr}")
            return False
    except FileNotFoundError as e:
        logger.error(f"Demucs not found: {e}")
        return False
    except subprocess.SubprocessError as e:
        logger.error(f"Demucs subprocess error: {e}")
        return False


def get_separated_stems(input_filename: str) -> dict[str, Path]:
    """
    Returns a dict of paths for the separated stems if they exist.
    Expected path: FILES_DIR/separation_output/htdemucs/{filename_no_ext}/{stem}.wav
    """
    filename_no_ext = Path(input_filename).stem
    base_path = FILES_DIR / "separation_output" / "htdemucs" / filename_no_ext

    stems: dict[str, Path] = {}
    for stem in ("vocals", "drums", "bass", "other"):
        stem_path = base_path / f"{stem}.wav"
        if stem_path.exists():
            stems[stem] = stem_path
    return stems


def detect_chords(input_filename: str) -> str:
    """
    Analyzes audio and returns a string with detected chords over time.
    Uses Chroma CENS (Energy Normalized) + Median Filtering for stability.
    """
    input_path = get_file_path(input_filename)
    logger.info(f"Starting chord detection (Librosa): {input_filename}")

    try:
        # 1. Load audio
        y, sr = librosa.load(str(input_path), sr=22050)

        # 2. Harmonic Source Separation
        y_harmonic, _ = librosa.effects.hpss(y)

        # 3. Compute Chroma CENS
        chroma = librosa.feature.chroma_cens(y=y_harmonic, sr=sr)

        # 4. Define Chord Templates (Major and Minor triads)
        maj_template = [1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0]
        min_template = [1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0]

        templates: list[np.ndarray] = []
        labels: list[str] = []

        for i in range(12):
            templates.append(np.roll(maj_template, i))
            labels.append(f"{CHORD_LABELS[i]}")
            templates.append(np.roll(min_template, i))
            labels.append(f"{CHORD_LABELS[i]}m")

        templates_arr = np.array(templates)

        # 5. Pattern Matching
        scores = np.dot(templates_arr, chroma)

        # 6. Find best chord per frame
        best_indices = np.argmax(scores, axis=0)

        # 7. Median filter for smoothing (~1 second window)
        kernel_size = 43
        best_indices_smoothed = scipy.signal.medfilt(best_indices, kernel_size=kernel_size).astype(int)

        # 8. Generate Output Text
        last_chord = ""
        output_txt = "⏱️ TEMPO   |  🎵 ACORDE\n"
        output_txt += "------------------------\n"

        for i, idx in enumerate(best_indices_smoothed):
            if i % 10 != 0:
                continue

            detected_chord = labels[idx]

            if detected_chord != last_chord:
                time_sec = librosa.frames_to_time(i, sr=sr)
                minutes = int(time_sec // 60)
                seconds = int(time_sec % 60)
                timestamp = f"{minutes}:{seconds:02d}"

                output_txt += f"{timestamp}    ->    {detected_chord}\n"
                last_chord = detected_chord

        logger.info("Chord detection (Librosa) complete")
        return output_txt

    except FileNotFoundError as e:
        logger.error(f"Audio file not found: {e}")
        return f"Erro: Arquivo não encontrado: {e}"
    except librosa.LibrosaError as e:
        logger.error(f"Librosa error: {e}")
        return f"Erro ao analisar áudio: {e}"


def detect_chords_dl(input_filename: str) -> str:
    """
    Deep Learning version: Uses Spotify's Basic Pitch to get notes,
    then infers chords from simultaneous notes.
    """
    input_path = get_file_path(input_filename)
    logger.info(f"Starting chord detection (Deep Learning): {input_filename}")

    try:
        from basic_pitch.inference import predict
        from basic_pitch import ICASSP_2022_MODEL_PATH

        # 1. Run Deep Learning Model (Audio -> MIDI)
        model_output, midi_data, note_events = predict(str(input_path))

        # 2. Analyze MIDI to find Chords
        window_sec = 0.5
        max_time = midi_data.get_end_time()

        output_txt = "⏱️ TEMPO   |  🎹 ACORDE (via Deep Learning)\n"
        output_txt += "---------------------------------------\n"

        last_chord = ""
        current_time = 0.0

        while current_time < max_time:
            # Get notes active in this window
            notes: list[int] = []
            for instrument in midi_data.instruments:
                for note in instrument.notes:
                    if note.start <= current_time + window_sec and note.end >= current_time:
                        notes.append(note.pitch)

            # Remove duplicates and normalize to pitch class
            unique_notes = sorted(set(n % 12 for n in notes))

            # Chord Identification
            chord_name = _identify_chord_from_pitches(unique_notes)

            if chord_name and chord_name != last_chord:
                minutes = int(current_time // 60)
                seconds = int(current_time % 60)
                timestamp = f"{minutes}:{seconds:02d}"
                output_txt += f"{timestamp}    ->    {chord_name}\n"
                last_chord = chord_name

            current_time += window_sec

        logger.info("Chord detection (Deep Learning) complete")
        return output_txt

    except ImportError as e:
        logger.error(f"Basic Pitch not installed: {e}")
        return "Erro: basic-pitch não está instalado"
    except FileNotFoundError as e:
        logger.error(f"Audio file not found: {e}")
        return f"Erro: Arquivo não encontrado: {e}"
    except RuntimeError as e:
        logger.error(f"Model inference error: {e}")
        return f"Erro na IA de acordes: {e}"


def _identify_chord_from_pitches(pitches: list[int]) -> Optional[str]:
    """
    Simple heuristic to name a chord from a set of pitch classes (0-11).
    0=C, 1=C#, etc.
    """
    if len(pitches) < 3:
        return None

    roots = CHORD_ROOTS_ENHARMONIC

    for root_idx in range(12):
        relative_pitches = {(p - root_idx) % 12 for p in pitches}

        # Check Major (0, 4, 7)
        if {0, 4, 7}.issubset(relative_pitches):
            return roots[root_idx]

        # Check Minor (0, 3, 7)
        if {0, 3, 7}.issubset(relative_pitches):
            return roots[root_idx] + "m"

    return None
