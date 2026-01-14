"""
AI Audio Studio - Standalone Mastering and Stem Separation Tool.
Professional audio processing using Pedalboard and Demucs.
"""
import io
import sys
import subprocess
from pathlib import Path
from typing import Tuple

import streamlit as st
import numpy as np
import soundfile as sf
from song_manager.backend.audio_utils import process_audio_data, load_audio_file

# === Constants ===
TEMP_DIR = Path("temp_input")
OUTPUT_DIR = Path("separated_stems")

# === App Setup ===
st.set_page_config(page_title="AI Audio Studio", page_icon="🎹", layout="wide")

st.title("🎹 AI Audio Studio")
st.markdown("Professional Mastering, Effects, and AI Track Separation.")

# Tabs
tab_master, tab_stem = st.tabs(["🎛️ Mastering & Effects", "🎻 AI Track Separator"])


def load_audio(file) -> Tuple[np.ndarray, int]:
    """Load audio file and return audio data with sample rate."""
    with st.spinner("Loading audio..."):
        audio_input, sample_rate = load_audio_file(file)
    return audio_input, sample_rate


def audio_to_bytes(audio_data: np.ndarray, sample_rate: int) -> io.BytesIO:
    """Convert audio data to WAV bytes for playback/download."""
    buffer = io.BytesIO()
    # Transpose back if necessary for writing: (channels, samples) -> (samples, channels)
    if audio_data.ndim > 1 and audio_data.shape[0] < audio_data.shape[1]:
        audio_data = audio_data.T

    sf.write(buffer, audio_data, sample_rate, format='WAV')
    buffer.seek(0)
    return buffer


# --- TAB 1: MASTERING ---
with tab_master:
    st.header("Mastering Chain")

    uploaded_file_master = st.file_uploader("Upload Mix for Mastering", key="master_upload")

    if uploaded_file_master is not None:
        # Manual validation to bypass OS filter issues
        valid_exts = {".wav", ".mp3", ".m4a", ".mp4", ".aac", ".flac", ".aiff"}
        file_ext = Path(uploaded_file_master.name).suffix.lower()
        
        if file_ext not in valid_exts:
            st.error(f"Unsupported file type: {file_ext}. Please upload audio (wav, mp3, m4a, etc).")
        else:
            audio_input, sample_rate = load_audio(uploaded_file_master)

            # Ensure format for Pedalboard: (channels, samples)
            if len(audio_input.shape) == 1:
                audio_input = audio_input[np.newaxis, :]  # Mono
            else:
                audio_input = audio_input.T  # Stereo

        st.subheader("1. Audio Repair")
        col_nr1, col_nr2 = st.columns(2)
        with col_nr1:
            apply_nr = st.checkbox("Apply Noise Reduction (AI)", help="Removes static background noise/hiss.")
        with col_nr2:
            nr_prop = st.slider("Noise Reduction Strength", 0.0, 1.0, 0.5)

        st.subheader("2. Creative Controls")
        col1, col2, col3 = st.columns(3)

        with col1:
            st.markdown("**Equalizer**")
            low_gain = st.slider("Low (Bass)", -12.0, 12.0, 0.0, 1.0)
            mid_gain = st.slider("Mid", -12.0, 12.0, 0.0, 1.0)
            high_gain = st.slider("High (Treble)", -12.0, 12.0, 0.0, 1.0)

        with col2:
            st.markdown("**Dynamics**")
            comp_thresh = st.slider("Compressor Threshold", -60.0, 0.0, -15.0)
            comp_ratio = st.slider("Ratio", 1.0, 10.0, 2.5)

        with col3:
            st.markdown("**Ambience**")
            reverb_on = st.checkbox("Enable Reverb")
            reverb_size = st.slider("Room Size", 0.0, 1.0, 0.5)
            reverb_wet = st.slider("Wet Level", 0.0, 1.0, 0.3)

        if st.button("Process Audio", type="primary"):
            with st.spinner("Processing... This may take a moment."):
                final_audio = process_audio_data(
                    audio_input, sample_rate,
                    apply_nr, nr_prop,
                    low_gain, mid_gain, high_gain,
                    comp_thresh, comp_ratio,
                    reverb_on, reverb_size, reverb_wet
                )

                # Output
                st.success("Processing Complete!")
                st.audio(audio_to_bytes(final_audio, sample_rate), format='audio/wav')

                st.download_button(
                    "Download Mastered File",
                    data=audio_to_bytes(final_audio, sample_rate),
                    file_name="mastered_remix.wav",
                    mime="audio/wav"
                )

# --- TAB 2: STEM SEPARATION ---
with tab_stem:
    st.header("AI Track Separation (Demucs)")
    st.markdown("Separates the audio into 4 stems: **Vocals, Drums, Bass, Other**.")
    st.info("⚠️ This process is resource intensive and requires downloading models (~300MB) on the first run.")

    uploaded_file_stem = st.file_uploader("Upload Song for Separation", key="stem_upload")

    if uploaded_file_stem is not None:
        # Manual validation
        valid_exts = {".wav", ".mp3", ".m4a", ".mp4", ".aac", ".flac", ".aiff"}
        file_ext = Path(uploaded_file_stem.name).suffix.lower()

        if file_ext not in valid_exts:
             st.error(f"Unsupported file type: {file_ext}. Please upload audio (wav, mp3, m4a, etc).")
        else:
            if st.button("Separate Stems", key="btn_sep"):
                # Save uploaded file temporarily
                TEMP_DIR.mkdir(exist_ok=True)
                temp_path = TEMP_DIR / uploaded_file_stem.name

                temp_path.write_bytes(uploaded_file_stem.getbuffer())

                # Run Demucs
                cmd = [sys.executable, "-m", "demucs", "-n", "htdemucs", "--out", str(OUTPUT_DIR), str(temp_path)]

                output_display = st.empty()
                output_display.text("Initializing AI Model... (check terminal for download progress)")

                try:
                    process = subprocess.run(cmd, capture_output=True, text=True)

                    if process.returncode == 0:
                        output_display.success("Separation Complete!")

                        # Structure of demucs output: separated/htdemucs/{filename_no_ext}/{stem}.wav
                        filename_no_ext = temp_path.stem
                        result_path = OUTPUT_DIR / "htdemucs" / filename_no_ext

                        stems = ["vocals", "drums", "bass", "other"]
                        cols = st.columns(4)

                        for i, stem in enumerate(stems):
                            stem_file = result_path / f"{stem}.wav"
                            if stem_file.exists():
                                with cols[i]:
                                    st.markdown(f"**{stem.capitalize()}**")
                                    st.audio(str(stem_file))
                                    with open(stem_file, "rb") as f:
                                        st.download_button(
                                            f"⬇️ {stem}",
                                            f,
                                            file_name=f"{stem}.wav",
                                            mime="audio/wav"
                                        )
                    else:
                        st.error("Error during separation.")
                        st.code(process.stderr)

                except FileNotFoundError as e:
                    st.error(f"Demucs not found: {e}")
                except subprocess.SubprocessError as e:
                    st.error(f"An error occurred: {e}")
