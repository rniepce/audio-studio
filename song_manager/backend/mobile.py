"""
Mobile-optimized interface for Song Manager.
Clean light theme UI, optimized for iPhone.
"""
import streamlit as st
from pathlib import Path

from config import setup_logging
from db import load_songs, escape_html, get_file_path

logger = setup_logging("mobile")

st.set_page_config(
    page_title="Setlist",
    page_icon="🎸",
    layout="centered",
    initial_sidebar_state="collapsed"
)

# === CLEAN LIGHT THEME CSS ===
st.markdown("""
<style>
    /* === IMPORTS === */
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');
    
    /* === ROOT VARIABLES === */
    :root {
        --bg-primary: #ffffff;
        --bg-secondary: #f5f5f7;
        --bg-card: #ffffff;
        --border-color: #e5e5e5;
        --accent-primary: #007aff;
        --accent-secondary: #5856d6;
        --text-primary: #1d1d1f;
        --text-secondary: #86868b;
        --text-muted: #aeaeb2;
        --shadow-card: 0 2px 8px rgba(0, 0, 0, 0.08);
        --radius-sm: 8px;
        --radius-md: 12px;
        --radius-lg: 16px;
    }
    
    /* === BASE STYLES === */
    .stApp {
        background: var(--bg-secondary) !important;
        font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif !important;
    }
    
    /* Hide Streamlit Chrome */
    header, footer, #MainMenu, .stDeployButton { display: none !important; }
    .block-container { 
        padding: 1.5rem 1rem 5rem 1rem !important; 
        max-width: 100% !important;
    }
    
    /* === SAFE AREAS (iPhone Notch & Home Indicator) === */
    .stApp > div:first-child {
        padding-top: env(safe-area-inset-top, 20px) !important;
        padding-bottom: env(safe-area-inset-bottom, 20px) !important;
    }
    
    /* === TYPOGRAPHY === */
    h1, h2, h3 {
        font-family: 'Inter', sans-serif !important;
        font-weight: 700 !important;
        color: var(--text-primary) !important;
        letter-spacing: -0.02em !important;
        line-height: 1.3 !important; /* Improved line height */
    }
    
    h1 { font-size: 1.75rem !important; margin-bottom: 1.5rem !important; }
    h2 { font-size: 1.25rem !important; margin-bottom: 0.75rem !important; }
    
    p, span, label, .stTextInput label {
        font-family: 'Inter', sans-serif !important;
        color: var(--text-secondary) !important;
        line-height: 1.6 !important; /* Improved readability */
    }
    
    /* === SEARCH BAR === */
    .stTextInput > div > div {
        background: var(--bg-card) !important;
        border: 1px solid var(--border-color) !important;
        border-radius: var(--radius-md) !important;
        box-shadow: var(--shadow-card) !important;
    }
    
    .stTextInput > div > div:focus-within {
        border-color: var(--accent-primary) !important;
        box-shadow: 0 0 0 3px rgba(0, 122, 255, 0.15) !important;
    }
    
    .stTextInput input {
        color: var(--text-primary) !important; /* Ensure high contrast */
        font-size: 1rem !important;
        padding: 0.75rem 1rem !important;
    }
    
    .stTextInput input::placeholder {
        color: var(--text-muted) !important;
    }
    
    /* === SONG CARDS === */
    .stButton > button {
        width: 100% !important;
        background: var(--bg-card) !important;
        border: 1px solid var(--border-color) !important;
        border-radius: var(--radius-md) !important;
        padding: 1.2rem 1rem !important; /* More breathing room */
        margin-bottom: 0.75rem !important;
        text-align: left !important;
        color: var(--text-primary) !important;
        font-family: 'Inter', sans-serif !important;
        font-size: 1.05rem !important;
        font-weight: 500 !important;
        transition: all 0.2s ease !important;
        box-shadow: var(--shadow-card) !important;
        min-height: auto !important;
        line-height: 1.4 !important;
        white-space: normal !important; /* Allow wrapping */
        height: auto !important;
    }
    
    .stButton > button:hover, .stButton > button:active {
        background: var(--bg-secondary) !important;
        border-color: var(--accent-primary) !important;
    }
    
    /* Back button */
    .back-btn button {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        padding: 0.5rem !important;
        font-size: 1.5rem !important;
        color: var(--accent-primary) !important;
        line-height: 1 !important;
    }
    
    /* === TABS === */
    .stTabs [data-baseweb="tab-list"] {
        background: var(--bg-card) !important;
        border-radius: var(--radius-md) !important;
        padding: 4px !important;
        gap: 8px !important;
        border: 1px solid var(--border-color) !important;
        box-shadow: var(--shadow-card) !important;
        margin-top: 1.5rem !important;
    }
    
    .stTabs [data-baseweb="tab"] {
        background: transparent !important;
        border-radius: var(--radius-sm) !important;
        color: var(--text-secondary) !important;
        font-family: 'Inter', sans-serif !important;
        font-weight: 500 !important;
        font-size: 0.95rem !important;
        padding: 0.75rem 1rem !important;
        flex: 1 !important; /* Distribute space */
    }
    
    .stTabs [aria-selected="true"] {
        background: var(--accent-primary) !important;
        color: white !important;
    }
    
    .stTabs [data-baseweb="tab-border"], 
    .stTabs [data-baseweb="tab-highlight"] {
        display: none !important;
    }
    
    /* === AUDIO PLAYER === */
    audio {
        width: 100% !important;
        border-radius: var(--radius-md) !important;
        margin: 1rem 0 1.5rem 0 !important;
    }
    
    /* === CONTENT BOXES === */
    .lyrics-box {
        font-family: 'Inter', sans-serif !important;
        font-size: 1.15rem !important;
        line-height: 2.0 !important; /* Increased line height */
        color: var(--text-primary) !important;
        white-space: pre-wrap !important;
        padding: 1.5rem !important;
        background: var(--bg-card) !important;
        border-radius: var(--radius-md) !important;
        border: 1px solid var(--border-color) !important;
        box-shadow: var(--shadow-card) !important;
        margin-top: 1rem !important;
    }
    
    .chords-box {
        font-family: 'SF Mono', 'Menlo', 'Courier New', monospace !important;
        font-size: 1.05rem !important;
        line-height: 1.8 !important;
        color: var(--accent-secondary) !important;
        white-space: pre-wrap !important;
        padding: 1.5rem !important;
        background: #f8f8fc !important;
        border-radius: var(--radius-md) !important;
        border: 1px solid var(--border-color) !important;
        box-shadow: var(--shadow-card) !important;
        margin-top: 1rem !important;
        overflow-x: auto !important; /* Handle wide chords */
    }
    
    /* === EXPANDER (Controls) === */
    .streamlit-expanderHeader {
        background: var(--bg-card) !important;
        border-radius: var(--radius-md) !important;
        border: 1px solid var(--border-color) !important;
        color: var(--text-secondary) !important;
        font-family: 'Inter', sans-serif !important;
        box-shadow: var(--shadow-card) !important;
        padding: 1rem !important;
    }
    
    .streamlit-expanderContent {
        background: transparent !important;
        border: none !important;
        padding-top: 1rem !important;
    }
    
    /* === SLIDER === */
    .stSlider > div > div > div {
        background: var(--accent-primary) !important;
    }
    
    .stSlider [data-baseweb="slider"] [role="slider"] {
        background: var(--accent-primary) !important;
        border: 2px solid white !important;
        box-shadow: var(--shadow-card) !important;
    }
    
    /* === STATS / COLUMNS === */
    div[data-testid="column"] {
        background: transparent !important;
    }
    
    /* === INFO/WARNING BOXES === */
    .stAlert {
        background: var(--bg-card) !important;
        border: 1px solid var(--border-color) !important;
        border-radius: var(--radius-md) !important;
        color: var(--text-secondary) !important;
        box-shadow: var(--shadow-card) !important;
    }
    
    /* === DIVIDER === */
    hr {
        border: none !important;
        height: 1px !important;
        background: var(--border-color) !important;
        margin: 1.5rem 0 !important;
    }
    
    /* === DOWNLOAD BUTTON === */
    .stDownloadButton > button {
        background: var(--bg-card) !important;
        border: 1px solid var(--border-color) !important;
        border-radius: var(--radius-md) !important;
        color: var(--accent-primary) !important;
        font-family: 'Inter', sans-serif !important;
        font-weight: 500 !important;
        box-shadow: var(--shadow-card) !important;
        padding: 0.75rem 1rem !important;
    }
    
    .stDownloadButton > button:hover {
        background: var(--accent-primary) !important;
        color: white !important;
    }
    
    /* === CAPTION === */
    .stCaption, small {
        color: var(--text-muted) !important;
        font-size: 0.9rem !important;
    }
    
    /* === SCROLLBAR === */
    ::-webkit-scrollbar {
        width: 6px;
        height: 6px;
    }
    ::-webkit-scrollbar-track {
        background: transparent;
    }
    ::-webkit-scrollbar-thumb {
        background: #d1d1d6;
        border-radius: 10px;
    }
</style>
""", unsafe_allow_html=True)

# === SESSION STATE ===
if 'selected_song' not in st.session_state:
    st.session_state.selected_song = None
if 'font_size' not in st.session_state:
    st.session_state.font_size = 1.1
if 'auto_scroll' not in st.session_state:
    st.session_state.auto_scroll = False


def render_song_list() -> None:
    """Render the main song list view."""
    st.markdown("# 🎸 Setlist")
    
    search = st.text_input(
        "",
        placeholder="🔍  Buscar música ou artista...",
        label_visibility="collapsed"
    ).lower()
    
    songs = load_songs()
    filtered_songs = [
        s for s in songs
        if search in s.get('title', '').lower() or search in s.get('artist', '').lower()
    ]
    
    if not filtered_songs:
        st.markdown("""
        <div style="text-align: center; padding: 3rem 1rem; color: #86868b;">
            <p style="font-size: 2.5rem; margin-bottom: 0.5rem;">🎵</p>
            <p>Nenhuma música encontrada</p>
        </div>
        """, unsafe_allow_html=True)
        return
    
    st.markdown("<div style='height: 0.5rem'></div>", unsafe_allow_html=True)
    
    for song in filtered_songs:
        title = song.get('title', 'Sem Título')
        artist = song.get('artist', '')
        
        if artist:
            label = f"**{title}**\n{artist}"
        else:
            label = f"**{title}**"
        
        if st.button(label, key=song['id'], use_container_width=True):
            st.session_state.selected_song = song
            st.rerun()


def render_song_detail(song: dict) -> None:
    """Render the song detail view."""
    # Header
    col_back, col_title = st.columns([1, 6])
    
    with col_back:
        st.markdown('<div class="back-btn">', unsafe_allow_html=True)
        if st.button("←", key="back"):
            st.session_state.selected_song = None
            st.session_state.auto_scroll = False
            st.rerun()
        st.markdown('</div>', unsafe_allow_html=True)
    
    with col_title:
        title = escape_html(song.get('title', ''))
        artist = escape_html(song.get('artist', ''))
        st.markdown(f"""
        <div style="padding-top: 0.25rem;">
            <h2 style="margin: 0; font-size: 1.3rem; color: #1d1d1f;">{title}</h2>
            <p style="margin: 0.25rem 0 0 0; font-size: 0.9rem; color: #86868b;">{artist}</p>
        </div>
        """, unsafe_allow_html=True)
    
    st.markdown("---")
    
    # Audio Player
    if song.get('audio_filename'):
        audio_path = get_file_path(song['audio_filename'])
        if audio_path.exists():
            # Read file and pass bytes to avoid path issues on mobile
            try:
                audio_bytes = audio_path.read_bytes()
                st.audio(audio_bytes, format='audio/mp3')
            except Exception as e:
                logger.error(f"Audio error: {e}")
                st.caption("⚠️ Erro ao carregar áudio")
    
    # Reading Controls
    with st.expander("⚙️ Controles", expanded=False):
        col1, col2 = st.columns(2)
        with col1:
            new_font = st.slider(
                "Tamanho",
                min_value=0.9,
                max_value=2.0,
                value=st.session_state.font_size,
                step=0.1
            )
            if new_font != st.session_state.font_size:
                st.session_state.font_size = new_font
                st.rerun()
        with col2:
            scroll_label = "⏹️ Parar" if st.session_state.auto_scroll else "▶️ Scroll"
            if st.button(scroll_label, use_container_width=True):
                st.session_state.auto_scroll = not st.session_state.auto_scroll
                st.rerun()
    
    # Dynamic font size
    st.markdown(f"""
    <style>
        .lyrics-box {{ font-size: {st.session_state.font_size}rem !important; }}
        .chords-box {{ font-size: {st.session_state.font_size * 0.9}rem !important; }}
    </style>
    """, unsafe_allow_html=True)
    
    # Auto-scroll
    if st.session_state.auto_scroll:
        st.markdown("""
        <script>
            setInterval(() => window.scrollBy(0, 1), 50);
        </script>
        """, unsafe_allow_html=True)
    
    # Content Tabs
    tab1, tab2 = st.tabs(["📄 Letra", "🎸 Cifra"])
    
    with tab1:
        lyrics = song.get('lyrics', '')
        if lyrics:
            st.markdown(
                f"<div class='lyrics-box'>{escape_html(lyrics)}</div>",
                unsafe_allow_html=True
            )
        else:
            st.caption("Sem letra cadastrada")
    
    with tab2:
        if song.get('pdf_filename'):
            pdf_path = get_file_path(song['pdf_filename'])
            if pdf_path.exists():
                with open(pdf_path, "rb") as f:
                    st.download_button(
                        label="📄 Baixar PDF",
                        data=f,
                        file_name=song['pdf_filename'],
                        mime="application/pdf",
                        use_container_width=True
                    )
                st.markdown("<div style='height: 0.5rem'></div>", unsafe_allow_html=True)
        
        chords = song.get('chords_text', '')
        if chords:
            st.markdown(
                f"<div class='chords-box'>{escape_html(chords)}</div>",
                unsafe_allow_html=True
            )
        elif not song.get('pdf_filename'):
            st.caption("Sem cifra cadastrada")


# === MAIN ===
if st.session_state.selected_song is None:
    render_song_list()
else:
    render_song_detail(st.session_state.selected_song)
