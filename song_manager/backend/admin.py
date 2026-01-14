import streamlit as st
import uuid
import zipfile
import io
import shutil
from pathlib import Path

from config import FILES_DIR, DATA_DIR, setup_logging
from db import load_songs, save_songs, save_uploaded_file, delete_file, get_file_path
import audio_utils

logger = setup_logging("admin")

st.set_page_config(page_title="Song Manager Admin", page_icon="📝", layout="wide", initial_sidebar_state="expanded")

# --- CUSTOM CSS ---
st.markdown("""
<style>
    textarea { font-family: 'Courier New', monospace; }
</style>
""", unsafe_allow_html=True)

# --- SESSION STATE ---
if 'confirm_delete' not in st.session_state:
    st.session_state.confirm_delete = False

# --- UI ---
st.title("🎛️ Studio Admin Dashboard")

songs = load_songs()

# Sidebar
with st.sidebar:
    st.header("Músicas")
    st.metric("Total na Biblioteca", len(songs))
    
    # Search
    search = st.text_input("Buscar Música...")
    filtered_songs = [s for s in songs if search.lower() in s.get('title', '').lower() or search.lower() in s.get('artist', '').lower()]
    
    # Selection
    song_options = {s['id']: f"{s['title']} ({s.get('artist', '')})" for s in filtered_songs}
    selected_id = st.radio("Selecione:", options=song_options.keys(), format_func=lambda x: song_options[x]) if song_options else None

    st.markdown("---")
    if st.button("➕ Nova Música", type="primary"):
        new_id = str(uuid.uuid4())
        new_song = {
            "id": new_id,
            "title": "Nova Música",
            "artist": "",
            "lyrics": "",
            "chords_text": "",
            "audio_filename": None,
            "pdf_filename": None
        }
        songs.append(new_song)
        save_songs(songs)
        st.toast("Música criada!", icon="✅")
        st.rerun()
    
    st.markdown("---")
    # Backup Button
    if st.button("📦 Exportar Backup (.zip)"):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
            db_path = DATA_DIR / "songs_db.json"
            if db_path.exists():
                zf.write(str(db_path), "songs_db.json")
            if FILES_DIR.exists():
                for file_path in FILES_DIR.iterdir():
                    if file_path.is_file():
                        zf.write(str(file_path), f"files/{file_path.name}")
        buffer.seek(0)
        st.download_button(
            label="⬇️ Baixar Backup",
            data=buffer,
            file_name="song_manager_backup.zip",
            mime="application/zip"
        )

# Main Area
if selected_id:
    # Find song object
    current_idx = next((i for i, item in enumerate(songs) if item["id"] == selected_id), -1)
    current_song = songs[current_idx]
    
    # Top Bar: Metadata
    c1, c2, c3 = st.columns([3, 2, 1])
    with c1:
        new_title = st.text_input("Título", current_song.get('title', ''))
    with c2:
        new_artist = st.text_input("Artista", current_song.get('artist', ''))
    with c3:
        st.write("")
        st.write("")
        if not st.session_state.confirm_delete:
            if st.button("🗑️ Excluir", type="secondary"):
                st.session_state.confirm_delete = True
                st.rerun()
        else:
            st.warning("Confirmar exclusão?")
            col_yes, col_no = st.columns(2)
            with col_yes:
                if st.button("✅ Sim"):
                    delete_file(current_song.get('audio_filename'))
                    delete_file(current_song.get('pdf_filename'))
                    del songs[current_idx]
                    save_songs(songs)
                    st.session_state.confirm_delete = False
                    st.rerun()
            with col_no:
                if st.button("❌ Não"):
                    st.session_state.confirm_delete = False
                    st.rerun()

    st.markdown("---")
    
    # Tabs for Content
    tab_editor, tab_files, tab_lab = st.tabs(["📝 Editor", "📂 Arquivos", "🎛️ ÁUDIO LAB"])
    
    with tab_editor:
        col_lyrics, col_chords = st.columns(2)
        with col_lyrics:
            st.subheader("Letra")
            new_lyrics = st.text_area("Cole a letra aqui", current_song.get('lyrics', ''), height=500)
        with col_chords:
            st.subheader("Cifra (Texto)")
            new_chords = st.text_area("Cole a cifra aqui", current_song.get('chords_text', ''), height=500)
            
    with tab_files:
        c1, c2 = st.columns(2)
        with c1:
            st.info("🎵 Áudio Principal")
            if current_song.get("audio_filename"):
                audio_path = get_file_path(current_song['audio_filename'])
                if audio_path.exists():
                    st.audio(str(audio_path))
                if st.button("Remover Áudio"):
                    delete_file(current_song['audio_filename'])
                    current_song['audio_filename'] = None
                    save_songs(songs)
                    st.rerun()
            else:
                uploaded_audio = st.file_uploader("Upload Audio (MP3/WAV/M4A) or Video (MP4/MOV)", key="admin_audio_upload")
                if uploaded_audio:
                    # Manual validation to bypass OS filter
                    valid_audio = {".wav", ".mp3", ".m4a", ".mp4", ".aac", ".flac", ".aiff"}
                    valid_video = {".mp4", ".mov", ".avi", ".mkv", ".webm"}
                    
                    file_ext = Path(uploaded_audio.name).suffix.lower()
                    
                    if file_ext in valid_video:
                        # Video -> Extract Audio
                        with st.spinner("Extraindo áudio do vídeo..."):
                            # 1. Save video to temp
                            temp_video_path = FILES_DIR / f"temp_video_{current_song['id']}{file_ext}"
                            temp_video_path.write_bytes(uploaded_audio.getbuffer())
                            
                            # 2. Define output audio path
                            output_audio_name = f"{current_song['id']}_extracted.wav"
                            output_audio_path = FILES_DIR / output_audio_name
                            
                            # 3. Extract
                            success = audio_utils.extract_audio_from_video(temp_video_path, output_audio_path)
                            
                            # 4. Cleanup and Save
                            if success:
                                current_song['audio_filename'] = output_audio_name
                                save_songs(songs)
                                delete_file(temp_video_path.name) # Clean video
                                st.toast("Áudio extraído com sucesso!", icon="✅")
                                st.rerun()
                            else:
                                st.error("Erro ao extrair áudio do vídeo.")
                                delete_file(temp_video_path.name)
                                
                    elif file_ext in valid_audio:
                         # Normal Audio Upload
                        fname = save_uploaded_file(uploaded_audio, current_song['id'], "audio")
                        current_song['audio_filename'] = fname
                        save_songs(songs)
                        st.rerun()
                    else:
                        st.error(f"Tipo de arquivo não suportado: {file_ext}")
        with c2:
            st.info("📄 PDF (Cifra)")
            if current_song.get("pdf_filename"):
                st.write(f"Arquivo: `{current_song['pdf_filename']}`")
                if st.button("Remover PDF"):
                    delete_file(current_song['pdf_filename'])
                    current_song['pdf_filename'] = None
                    save_songs(songs)
                    st.rerun()
            else:
                uploaded_pdf = st.file_uploader("Upload PDF", type=["pdf"])
                if uploaded_pdf:
                    fname = save_uploaded_file(uploaded_pdf, current_song['id'], "chords")
                    current_song['pdf_filename'] = fname
                    save_songs(songs)
                    st.rerun()

    # --- AUDIO LAB ---
    with tab_lab:
        st.markdown("### Laboratório de Processamento")
        if not current_song.get("audio_filename"):
            st.warning("⚠️ Você precisa fazer upload de um áudio na aba 'Arquivos' primeiro.")
        else:
            orig_filename = current_song['audio_filename']
            st.write(f"Arquivo Original: `{orig_filename}`")
            
            # Divide into sub-features
            lab_mode = st.radio("Ferramenta:", ["Masterização & Efeitos", "Detectar Acordes (BETA)"], horizontal=True)
            
            if lab_mode == "Detectar Acordes (BETA)":
                st.info("🤖 **IA:** Use a opção 'Deep Learning' para ver a tentativa mais avançada.")
                
                method = st.radio("Método:", ["Rapidão (Librosa)", "Deep Learning (Spotify Basic Pitch)"], horizontal=True)
                
                if st.button("🔍 Analisar Harmonia"):
                    with st.spinner("Analisando áudio... (Deep Learning pode demorar um pouco)"):
                         if "Deep Learning" in method:
                             result_text = audio_utils.detect_chords_dl(orig_filename)
                         else:
                             result_text = audio_utils.detect_chords(orig_filename)
                         
                         st.text_area("Acordes Detectados (Copie e Cole na aba Editor)", result_text, height=300)

            elif lab_mode == "Masterização & Efeitos":
                c1, c2, c3 = st.columns(3)
                with c1:
                    st.markdown("**Equalizador**")
                    low = st.slider("Low", -12.0, 12.0, 0.0)
                    mid = st.slider("Mid", -12.0, 12.0, 0.0)
                    high = st.slider("High", -12.0, 12.0, 0.0)
                with c2:
                    st.markdown("**Dinâmica/Reparo**")
                    nr_on = st.checkbox("Noise Reduction (AI)")
                    thresh = st.slider("Comp. Threshold", -60.0, 0.0, -15.0)
                with c3:
                    st.markdown("**Espaço**")
                    rev_on = st.checkbox("Reverb")
                    rev_amt = st.slider("Size", 0.0, 1.0, 0.5)

                if st.button("🔊 Processar e Ouvir Preview"):
                    with st.spinner("Masterizando..."):
                        # Temp output
                        temp_out_name = f"temp_master_{current_song['id']}.wav"
                        out_path = audio_utils.perform_mastering(
                            input_filename=orig_filename,
                            output_filename=temp_out_name,
                            apply_nr=nr_on, nr_prop=0.5,
                            low_gain=low, mid_gain=mid, high_gain=high,
                            comp_thresh=thresh, comp_ratio=2.5,
                            reverb_on=rev_on, reverb_size=rev_amt, reverb_wet=0.3
                        )
                        st.session_state['last_master'] = temp_out_name
                
                if st.session_state.get('last_master'):
                    st.audio(str(get_file_path(st.session_state['last_master'])))
                    if st.button("💾 Salvar Como Áudio Principal"):
                         # Rename temp to main
                         final_name = st.session_state['last_master'].replace("temp_master_", "mastered_")
                         shutil.move(str(get_file_path(st.session_state['last_master'])), str(get_file_path(final_name)))
                         
                         # Cleanup old
                         if current_song['audio_filename'] and current_song['audio_filename'] != final_name:
                             delete_file(current_song['audio_filename'])
                             
                         current_song['audio_filename'] = final_name
                         save_songs(songs)
                         st.toast("Áudio Masterizado Salvo!", icon="✅")
                         del st.session_state['last_master']
                         st.rerun()

    # Save Button
    st.markdown("---")
    if st.button("💾 SALVAR METADADOS", type="primary", use_container_width=True):
        current_song['title'] = new_title
        current_song['artist'] = new_artist
        current_song['lyrics'] = new_lyrics
        current_song['chords_text'] = new_chords
        save_songs(songs)
        st.toast("Alterações salvas!", icon="✅")

else:
    st.info("👈 Selecione uma música na barra lateral para editar Letras, Cifras ou acessar o **Laboratório de Áudio (Masterização e IA)**.")
