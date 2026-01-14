import sys
import os

print(f"Python: {sys.executable}")
print(f"CWD: {os.getcwd()}")

try:
    print("Attempting imports...")
    import streamlit
    print("✅ streamlit")
    import pedalboard
    print("✅ pedalboard")
    import soundfile
    print("✅ soundfile")
    import demucs
    print("✅ demucs")
    import noisereduce
    print("✅ noisereduce")
    import audio_utils
    print("✅ audio_utils")
    print("ALL IMPORTS OK.")
except Exception as e:
    print(f"❌ IMPORT ERROR: {e}")
    import traceback
    traceback.print_exc()
