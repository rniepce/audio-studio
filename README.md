# Audio Studio App (AI-Powered)

A complete Audio Mastering and Track Separation tool running locally on Streamlit.

## Features

1.  **Professional Mastering Chain**:
    *   **High-pass Filter**: Cleans up mud.
    *   **3-Band Equalizer**: Adjust Low, Mid, and High frequencies.
    *   **Compressor & Limiter**: Glues the mix and maximizes loudness.
    *   **Reverb**: Adds ambience and space.
    *   **Noise Reduction**: AI-based static noise removal.

2.  **AI Track Separation (Stem Splitter)**:
    *   Uses **Demucs** (State-of-the-art AI) to separate a song into **Vocals, Drums, Bass, and Other**.

## Local Installation (Mac)

1.  **Run the Setup Script:**
    The easiest way to start is using the provided script. Open your terminal in this folder and run:
    ```bash
    ./run_app.sh
    ```
    This script handles the virtual environment, dependencies, and launching the app.

## Manual Installation

If you prefer to run commands manually:

1.  **Install Dependencies:**
    ```bash
    pip install -r requirements.txt
    ```

2.  **Run the App:**
    ```bash
    streamlit run app.py
    ```

## ⚠️ Important Notes

*   **First Run**: When you use the "Track Separator" for the first time, the application will automatically download the AI models (approx. 300MB). This might take a few minutes depending on your internet connection.
*   **Performance**: Track separation is computationally intensive. It may take some time to process a full song, especially on machines without a dedicated GPU.
*   **Google Colab**: The Colab instructions in the original prompt are still valid, but you will need to add `demucs` and `noisereduce` to the pip install command.
