import streamlit as st
import numpy as np
import soundfile as sf
import io
import os
import subprocess
import shutil
import sys
from pedalboard import (
    Pedalboard, 
    Compressor, 
    HighpassFilter, 
    Limiter, 
    Reverb, 
    NoiseGate,
    LowShelfFilter,
    HighShelfFilter,
    PeakFilter
)
import noisereduce as nr

# App setup
st.set_page_config(page_title="AI Audio Studio", page_icon="🎹", layout="wide")

st.title("🎹 AI Audio Studio")
st.markdown("Professional Mastering, Effects, and AI Track Separation.")

# Tabs
tab_master, tab_stem = st.tabs(["🎛️ Mastering & Effects", "🎻 AI Track Separator"])

def load_audio(file):
    with st.spinner("Loading audio..."):
        audio_input, sample_rate = sf.read(file)
    return audio_input, sample_rate

def audio_to_bytes(audio_data, sample_rate):
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
    
    uploaded_file_master = st.file_uploader("Upload Mix for Mastering", type=["wav", "mp3"], key="master_upload")

    if uploaded_file_master is not None:
        audio_input, sample_rate = load_audio(uploaded_file_master)
        
        # Ensure format for Pedalboard: (channels, samples)
        if len(audio_input.shape) == 1:
            audio_input = audio_input[np.newaxis, :] # Mono
        else:
            audio_input = audio_input.T # Stereo
            
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
                processed_audio = audio_input.copy()
                
                # 1. Noise Reduction using noisereduce
                if apply_nr:
                    # noisereduce expects (channels, samples) or (samples,)
                    # We are in (channels, samples)
                    processed_audio = nr.reduce_noise(
                        y=processed_audio, 
                        sr=sample_rate, 
                        prop_decrease=nr_prop,
                        stationary=True # Assumes constant noise floor
                    )

                # 2. Pedalboard Chain
                board = Pedalboard([
                    # Pre-cleaning
                    HighpassFilter(cutoff_frequency_hz=30),
                    NoiseGate(threshold_db=-60, ratio=4, release_ms=250),
                    
                    # EQ
                    LowShelfFilter(cutoff_frequency_hz=100, gain_db=low_gain),
                    PeakFilter(cutoff_frequency_hz=1000, gain_db=mid_gain),
                    HighShelfFilter(cutoff_frequency_hz=5000, gain_db=high_gain),
                    
                    # Dynamics
                    Compressor(threshold_db=comp_thresh, ratio=comp_ratio, attack_ms=15, release_ms=200),
                    
                    # Effects
                    Reverb(room_size=reverb_size, wet_level=reverb_wet if reverb_on else 0.0, dry_level=1.0),
                    
                    # Layout
                    Limiter(threshold_db=-1.0)
                ])
                
                final_audio = board(processed_audio, sample_rate)
                
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
    
    uploaded_file_stem = st.file_uploader("Upload Song for Separation", type=["wav", "mp3"], key="stem_upload")
    
    if uploaded_file_stem is not None:
        if st.button("Separate Stems", key="btn_sep"):
            # Save uploaded file temporarily
            temp_dir = "temp_input"
            os.makedirs(temp_dir, exist_ok=True)
            temp_path = os.path.join(temp_dir, uploaded_file_stem.name)
            
            with open(temp_path, "wb") as f:
                f.write(uploaded_file_stem.getbuffer())
            
            # Output directory
            out_dir = "separated_stems"
            
            cmd = [sys.executable, "-m", "demucs", "-n", "htdemucs", "--out", out_dir, temp_path]
            
            output_display = st.empty()
            output_display.text("Initializing AI Model... (check terminal for download progress)")
            
            try:
                # Run Demucs via subprocess
                process = subprocess.run(cmd, capture_output=True, text=True)
                
                if process.returncode == 0:
                    output_display.success("Separation Complete!")
                    
                    # Structure of demucs output: separated/htdemucs/{filename_no_ext}/{stem}.wav
                    filename_no_ext = os.path.splitext(uploaded_file_stem.name)[0]
                    result_path = os.path.join(out_dir, "htdemucs", filename_no_ext)
                    
                    stems = ["vocals", "drums", "bass", "other"]
                    cols = st.columns(4)
                    
                    for i, stem in enumerate(stems):
                        stem_file = os.path.join(result_path, f"{stem}.wav")
                        if os.path.exists(stem_file):
                            with cols[i]:
                                st.markdown(f"**{stem.capitalize()}**")
                                st.audio(stem_file)
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
                    
            except Exception as e:
                st.error(f"An error occurred: {e}")
            
            # Cleanup (Optional: remove temp files to save space)
            # shutil.rmtree(temp_dir)
