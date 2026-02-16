//
//  ContentView.swift
//  SongManager
//
//  Created by Daniela Bueno on 14/01/26.
//

import SwiftUI
import AVFoundation
import Combine

// MARK: - Models
struct Song: Identifiable, Codable {
    let id: String
    let title: String
    let artist: String
    let lyrics: String
    let chords_text: String
    let audio_filename: String?
    let pdf_filename: String?
    
    enum CodingKeys: String, CodingKey {
        case id, title, artist, lyrics
        case chords_text = "chords_text"
        case audio_filename = "audio_filename"
        case pdf_filename = "pdf_filename"
    }
}

// MARK: - API Service
class SongService: ObservableObject {
    @Published var songs: [Song] = []
    
    // SEU LINK DO RAILWAY (CLOUD)
    let baseURL = "https://audio-studio-production-3c56.up.railway.app"
    
    func fetchSongs() {
        guard let url = URL(string: "\(baseURL)/songs") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let data = data {
                do {
                    let decodedSongs = try JSONDecoder().decode([Song].self, from: data)
                    DispatchQueue.main.async {
                        self.songs = decodedSongs
                    }
                } catch {
                    print("Error decoding: \(error)")
                }
            }
        }.resume()
    }
    
    func getAudioURL(filename: String) -> URL? {
        return URL(string: "\(baseURL)/files/\(filename)")
    }
    
    func updateSong(_ song: Song, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/songs/\(song.id)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(song)
            
            URLSession.shared.dataTask(with: request) { _, response, error in
                if let error = error {
                    print("Error updating song: \(error)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    DispatchQueue.main.async {
                        // Update local list
                        if let index = self.songs.firstIndex(where: { $0.id == song.id }) {
                            self.songs[index] = song
                        }
                        completion(true)
                    }
                } else {
                    DispatchQueue.main.async { completion(false) }
                }
            }.resume()
        } catch {
            print("Error encoding song: \(error)")
            completion(false)
        }
    }
}

// MARK: - Audio Player
class AudioPlayer: ObservableObject {
    var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 1.0
    @Published var isSeeking = false
    
    private var timeObserver: Any?
    
    func play(url: URL) {
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
        } catch {
            print("Audio session error: \(error)")
        }
        
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.play()
        isPlaying = true
        
        // Get duration
        Task {
            if let duration = try? await item.asset.load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite && seconds > 0 {
                    await MainActor.run {
                        self.duration = seconds
                    }
                }
            }
        }
        
        // Time observer - updates every 0.5s
        removeTimeObserver()
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isSeeking else { return }
            let t = CMTimeGetSeconds(time)
            if t.isFinite {
                self.currentTime = t
            }
        }
    }
    
    func toggle() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
    
    func seek(to time: Double) {
        let target = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func stop() {
        removeTimeObserver()
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 1.0
    }
    
    private func removeTimeObserver() {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
    }
}

// MARK: - Helper
func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite && seconds >= 0 else { return "0:00" }
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    return String(format: "%d:%02d", m, s)
}

// MARK: - Song Card
struct SongCardView: View {
    let song: Song
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(song.title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                    .bold()
                
                if !song.artist.isEmpty {
                    Text(song.artist)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .padding()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject var service = SongService()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 15) {
                    ForEach(service.songs) { song in
                        NavigationLink(destination: SongDetailView(song: song, service: service)) {
                            SongCardView(song: song)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Setlist")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "music.note.list")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .onAppear {
                service.fetchSongs()
            }
        }
    }
}

// MARK: - Detail View
struct SongDetailView: View {
    let song: Song
    @ObservedObject var service: SongService
    @StateObject var player = AudioPlayer()
    
    @State private var showLyrics = true
    @State private var fontSize: Double = 18
    @State private var sliderValue: Double = 0
    
    // Edit Mode State
    @State private var isEditing = false
    @State private var editedLyrics: String = ""
    @State private var editedChords: String = ""
    @State private var isSaving = false
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (Title & Artist)
            VStack(spacing: 4) {
                Text(song.title)
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.heavy)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                
                Text(song.artist)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 5)
            .padding(.horizontal)
            
            if !isEditing {
                // Player Card
                if let audioFile = song.audio_filename, let url = service.getAudioURL(filename: audioFile) {
                    GlassEffectContainer {
                        VStack(spacing: 8) {
                            // Play/Pause Button
                            Button(action: { player.toggle() }) {
                                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 50))
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.glass)
                            
                            // Progress Slider
                            VStack(spacing: 4) {
                                Slider(
                                    value: $sliderValue,
                                    in: 0...max(player.duration, 1),
                                    onEditingChanged: { editing in
                                        player.isSeeking = editing
                                        if !editing {
                                            player.seek(to: sliderValue)
                                        }
                                    }
                                )
                                .tint(.primary)
                                
                                HStack {
                                    Text(formatTime(sliderValue))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(formatTime(player.duration))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 20)
                            .onChange(of: player.currentTime) { _, newValue in
                                if !player.isSeeking {
                                    sliderValue = newValue
                                }
                            }
                        }
                        .padding(15)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .onAppear {
                        player.play(url: url)
                        player.player?.pause()
                        player.isPlaying = false
                    }
                } else {
                    Text("Sem áudio disponível")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 10)
                }
            }
            
            // Segmented Control
            Picker("View", selection: $showLyrics) {
                Text("Letra").tag(true)
                Text("Cifra").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            // Content
            if isEditing {
                if showLyrics {
                    TextEditor(text: $editedLyrics)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 16, design: .rounded))
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal)
                } else {
                    TextEditor(text: $editedChords)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 16, design: .monospaced))
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal)
                }
            } else {
                ScrollView {
                    Text(showLyrics ? song.lyrics : song.chords_text)
                        .font(.system(size: CGFloat(fontSize), design: showLyrics ? .default : .monospaced))
                        .foregroundStyle(.primary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)
                
                // Font Size Control
                HStack {
                    Image(systemName: "textformat.size.smaller")
                        .foregroundStyle(.secondary)
                    Slider(value: $fontSize, in: 10...40)
                        .tint(.primary)
                    Image(systemName: "textformat.size.larger")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .padding()
            }
            
            if isEditing {
                Button("Cancelar", role: .cancel) {
                    isEditing = false
                }
                .buttonStyle(.glass)
                .padding(.bottom, 10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    if isEditing {
                        saveChanges()
                    } else {
                        startEditing()
                    }
                }) {
                    Text(isEditing ? "Salvar" : "Editar")
                }
                .buttonStyle(.glassProminent)
                .disabled(isSaving)
            }
        }
        .onDisappear {
            player.stop()
        }
    }
    
    func startEditing() {
        editedLyrics = song.lyrics
        editedChords = song.chords_text
        isEditing = true
    }
    
    func saveChanges() {
        isSaving = true
        let updatedSong = Song(
            id: song.id,
            title: song.title,
            artist: song.artist,
            lyrics: editedLyrics,
            chords_text: editedChords,
            audio_filename: song.audio_filename,
            pdf_filename: song.pdf_filename
        )
        
        service.updateSong(updatedSong) { success in
            isSaving = false
            if success {
                isEditing = false
            }
        }
    }
}
