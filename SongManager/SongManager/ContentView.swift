//
//  ContentView.swift
//  SongManager
//
//  Created by Daniela Bueno on 14/01/26.
//

import SwiftUI
import AVFoundation
import Combine
import UniformTypeIdentifiers

// MARK: - Sort Option
enum SortOption: String, CaseIterable, Identifiable {
    case alphabetical    = "A → Z"
    case recentlyPlayed  = "Recentes"
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .alphabetical: return "textformat.abc"
        case .recentlyPlayed: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Model
struct Song: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var artist: String
    var lyrics: String
    var chordsText: String
    var audioFilename: String?
    var lastPlayedDate: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, title, artist, lyrics
        case chordsText = "chords_text"
        case audioFilename = "audio_filename"
        case lastPlayedDate = "last_played_date"
    }
    
    init(id: UUID = UUID(), title: String, artist: String, lyrics: String = "", chordsText: String = "", audioFilename: String? = nil, lastPlayedDate: Date? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.lyrics = lyrics
        self.chordsText = chordsText
        self.audioFilename = audioFilename
        self.lastPlayedDate = lastPlayedDate
    }
    
    // Custom decoder to handle both UUID and legacy string IDs
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try UUID first, then fall back to string (generate new UUID from it)
        if let uuid = try? container.decode(UUID.self, forKey: .id) {
            self.id = uuid
        } else if let idString = try? container.decode(String.self, forKey: .id) {
            self.id = UUID(uuidString: idString) ?? UUID()
        } else {
            self.id = UUID()
        }
        
        self.title = try container.decode(String.self, forKey: .title)
        self.artist = try container.decode(String.self, forKey: .artist)
        self.lyrics = try container.decodeIfPresent(String.self, forKey: .lyrics) ?? ""
        self.chordsText = try container.decodeIfPresent(String.self, forKey: .chordsText) ?? ""
        self.audioFilename = try container.decodeIfPresent(String.self, forKey: .audioFilename)
        self.lastPlayedDate = try container.decodeIfPresent(Date.self, forKey: .lastPlayedDate)
    }
}

// MARK: - Song Store (Offline)
class SongStore: ObservableObject {
    @Published var songs: [Song] = []
    @Published var sortOption: SortOption {
        didSet {
            UserDefaults.standard.set(sortOption.rawValue, forKey: "sortOption")
        }
    }
    
    private let songsFile: URL
    private let audioDir: URL
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        songsFile = docs.appendingPathComponent("songs.json")
        audioDir = docs.appendingPathComponent("Audio")
        
        // Restore sort preference
        if let saved = UserDefaults.standard.string(forKey: "sortOption"),
           let option = SortOption(rawValue: saved) {
            sortOption = option
        } else {
            sortOption = .alphabetical
        }
        
        // Create Audio directory if needed
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        
        // First launch: seed from bundled data
        if !FileManager.default.fileExists(atPath: songsFile.path) {
            seedBundledData()
        }
        
        loadSongs()
    }
    
    // MARK: - Seed bundled data on first launch
    private func seedBundledData() {
        // Copy bundled songs.json (Xcode places it at bundle root)
        if let bundledJSON = Bundle.main.url(forResource: "songs", withExtension: "json") {
            try? FileManager.default.copyItem(at: bundledJSON, to: songsFile)
        }
        
        // Copy bundled audio files (m4a files at bundle root)
        if let resourcePath = Bundle.main.resourcePath {
            let bundleDir = URL(fileURLWithPath: resourcePath)
            if let files = try? FileManager.default.contentsOfDirectory(at: bundleDir, includingPropertiesForKeys: nil) {
                let audioFiles = files.filter { ["m4a", "mp3", "wav", "aac"].contains($0.pathExtension.lowercased()) }
                for file in audioFiles {
                    let dest = audioDir.appendingPathComponent(file.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: dest.path) {
                        try? FileManager.default.copyItem(at: file, to: dest)
                    }
                }
            }
        }
    }
    
    // MARK: - Sorted songs (computed)
    var sortedSongs: [Song] {
        switch sortOption {
        case .alphabetical:
            return songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recentlyPlayed:
            return songs.sorted { s1, s2 in
                switch (s1.lastPlayedDate, s2.lastPlayedDate) {
                case let (d1?, d2?): return d1 > d2
                case (_?, nil):      return true
                case (nil, _?):      return false
                case (nil, nil):     return s1.title.localizedCaseInsensitiveCompare(s2.title) == .orderedAscending
                }
            }
        }
    }
    
    // MARK: - Persistence
    func loadSongs() {
        guard FileManager.default.fileExists(atPath: songsFile.path) else {
            songs = []
            return
        }
        do {
            let data = try Data(contentsOf: songsFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            songs = try decoder.decode([Song].self, from: data)
        } catch {
            print("Error loading songs: \(error)")
            songs = []
        }
    }
    
    func saveSongs() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(songs)
            try data.write(to: songsFile)
        } catch {
            print("Error saving songs: \(error)")
        }
    }
    
    // MARK: - CRUD
    func addSong(_ song: Song) {
        songs.append(song)
        saveSongs()
    }
    
    func updateSong(_ song: Song) {
        if let i = songs.firstIndex(where: { $0.id == song.id }) {
            songs[i] = song
            saveSongs()
        }
    }
    
    func deleteSong(_ song: Song) {
        // Delete audio file
        if let filename = song.audioFilename {
            let audioFile = audioDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: audioFile)
        }
        songs.removeAll { $0.id == song.id }
        saveSongs()
    }
    
    // MARK: - Reorder (Custom mode)
    func moveSong(from source: IndexSet, to destination: Int) {
        songs.move(fromOffsets: source, toOffset: destination)
        saveSongs()
    }
    
    // MARK: - Mark played
    func markPlayed(_ song: Song) {
        if let i = songs.firstIndex(where: { $0.id == song.id }) {
            songs[i].lastPlayedDate = Date()
            saveSongs()
        }
    }
    
    // MARK: - Audio
    func audioURL(for song: Song) -> URL? {
        guard let filename = song.audioFilename else { return nil }
        let url = audioDir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    
    func importAudio(from sourceURL: URL, for song: Song) -> Song {
        let ext = sourceURL.pathExtension.lowercased()
        let filename = "\(song.id.uuidString)_audio.\(ext)"
        let dest = audioDir.appendingPathComponent(filename)
        
        // Remove old audio
        if let oldFile = song.audioFilename {
            try? FileManager.default.removeItem(at: audioDir.appendingPathComponent(oldFile))
        }
        
        // Copy new audio
        _ = sourceURL.startAccessingSecurityScopedResource()
        defer { sourceURL.stopAccessingSecurityScopedResource() }
        try? FileManager.default.copyItem(at: sourceURL, to: dest)
        
        var updated = song
        updated.audioFilename = filename
        updateSong(updated)
        return updated
    }
    
    func deleteAudio(for song: Song) -> Song {
        if let filename = song.audioFilename {
            try? FileManager.default.removeItem(at: audioDir.appendingPathComponent(filename))
        }
        var updated = song
        updated.audioFilename = nil
        updateSong(updated)
        return updated
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
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
        
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.play()
        isPlaying = true
        
        Task {
            if let dur = try? await item.asset.load(.duration) {
                let seconds = CMTimeGetSeconds(dur)
                if seconds.isFinite && seconds > 0 {
                    await MainActor.run { self.duration = seconds }
                }
            }
        }
        
        removeTimeObserver()
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isSeeking else { return }
            let t = CMTimeGetSeconds(time)
            if t.isFinite { self.currentTime = t }
        }
    }
    
    func toggle() {
        if isPlaying { player?.pause() } else { player?.play() }
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

// MARK: - Helpers
func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite && seconds >= 0 else { return "0:00" }
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    return String(format: "%d:%02d", m, s)
}

// MARK: - Song Card
struct SongCardView: View {
    let song: Song
    var isJiggling: Bool = false
    var position: Int? = nil
    
    @State private var jiggleAngle: Double = 0
    
    var body: some View {
        HStack {
            if let pos = position, isJiggling {
                Text("\(pos)")
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.blue.gradient))
                    .padding(.trailing, 4)
            }
            
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
            
            if song.audioFilename != nil {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
                    .font(.subheadline)
            }
            
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .rotationEffect(.degrees(jiggleAngle))
        .onChange(of: isJiggling) { _, jiggling in
            if jiggling {
                withAnimation(.easeInOut(duration: 0.1).repeatForever(autoreverses: true)) {
                    jiggleAngle = 1.5
                }
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    jiggleAngle = 0
                }
            }
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject var store = SongStore()
    @State private var searchText = ""
    @State private var showAddSong = false
    @State private var editMode: EditMode = .inactive
    @State private var isReorderMode = false
    @State private var reorderTimer: Timer?
    @State private var selectedSong: Song?
    @State private var showTuner = false
    
    var filteredSongs: [Song] {
        let base = store.sortedSongs
        if searchText.isEmpty { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if isReorderMode {
                    // Reorder mode: iterate store.songs directly so indices match
                    ForEach(store.songs) { song in
                        SongCardView(
                            song: song,
                            isJiggling: true,
                            position: (store.songs.firstIndex(where: { $0.id == song.id }) ?? 0) + 1
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .onMove { source, destination in
                        store.moveSong(from: source, to: destination)
                        resetReorderTimer()
                    }
                    .deleteDisabled(true)
                } else {
                    // Normal mode: sorted + filterable, programmatic navigation
                    ForEach(filteredSongs) { song in
                        SongCardView(song: song)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSong = song
                            }
                            .onLongPressGesture(minimumDuration: 0.5) {
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()
                                enterReorderMode()
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .onDelete { offsets in
                        let songsToDelete = offsets.map { filteredSongs[$0] }
                        for song in songsToDelete {
                            store.deleteSong(song)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
            .searchable(text: $searchText, prompt: "Buscar música...")
            .navigationTitle("Setlist 🎸")
            .navigationDestination(item: $selectedSong) { song in
                SongDetailView(song: song, store: store)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isReorderMode {
                        Button("OK") {
                            exitReorderMode()
                        }
                        .fontWeight(.semibold)
                    } else {
                        Menu {
                            ForEach(SortOption.allCases) { option in
                                Button(action: {
                                    withAnimation { store.sortOption = option }
                                }) {
                                    Label {
                                        Text(option.rawValue)
                                    } icon: {
                                        if store.sortOption == option {
                                            Image(systemName: "checkmark")
                                        } else {
                                            Image(systemName: option.icon)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { showTuner = true }) {
                            Image(systemName: "tuningfork")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .disabled(isReorderMode)
                        
                        Button(action: { showAddSong = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .disabled(isReorderMode)
                    }
                }
            }
            .sheet(isPresented: $showAddSong) {
                AddSongView(store: store)
            }
            .sheet(isPresented: $showTuner) {
                GuitarTunerView()
            }
        }
    }
    
    // MARK: - Reorder Mode
    private func enterReorderMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isReorderMode = true
            editMode = .active
        }
        resetReorderTimer()
    }
    
    private func exitReorderMode() {
        reorderTimer?.invalidate()
        reorderTimer = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            isReorderMode = false
            editMode = .inactive
        }
    }
    
    private func resetReorderTimer() {
        reorderTimer?.invalidate()
        reorderTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async {
                exitReorderMode()
            }
        }
    }
}

// MARK: - Add Song View
struct AddSongView: View {
    @ObservedObject var store: SongStore
    @Environment(\.dismiss) var dismiss
    
    @State private var title = ""
    @State private var artist = ""
    @State private var showAudioPicker = false
    @State private var audioURL: URL?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Informações") {
                    TextField("Título", text: $title)
                    TextField("Artista", text: $artist)
                }
                
                Section("Áudio (opcional)") {
                    if let url = audioURL {
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundStyle(.blue)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button(role: .destructive) {
                                audioURL = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    } else {
                        Button(action: { showAudioPicker = true }) {
                            Label("Importar Áudio", systemImage: "doc.badge.plus")
                        }
                    }
                }
            }
            .navigationTitle("Nova Música")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showAudioPicker,
                allowedContentTypes: [.audio, .mp3, .wav, .aiff, UTType("public.mpeg-4-audio") ?? .audio],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    audioURL = url
                }
            }
        }
    }
    
    private func save() {
        var song = Song(
            title: title.trimmingCharacters(in: .whitespaces),
            artist: artist.trimmingCharacters(in: .whitespaces)
        )
        store.addSong(song)
        
        if let url = audioURL {
            song = store.importAudio(from: url, for: song)
        }
        
        dismiss()
    }
}

// MARK: - Detail View
struct SongDetailView: View {
    @State var song: Song
    @ObservedObject var store: SongStore
    @StateObject var player = AudioPlayer()
    
    @State private var showLyrics = true
    @State private var fontSize: Double = 18
    @State private var sliderValue: Double = 0
    
    // Edit State
    @State private var isEditing = false
    @State private var editedLyrics = ""
    @State private var editedChords = ""
    @State private var editedTitle = ""
    @State private var editedArtist = ""
    
    // Audio Import
    @State private var showAudioPicker = false
    @State private var showDeleteAudioConfirm = false
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                if isEditing {
                    TextField("Título", text: $editedTitle)
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.heavy)
                        .multilineTextAlignment(.center)
                    TextField("Artista", text: $editedArtist)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text(song.title)
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.heavy)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text(song.artist)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 5)
            .padding(.horizontal)
            
            if !isEditing {
                // Audio Player
                if let url = store.audioURL(for: song) {
                    GlassEffectContainer {
                        VStack(spacing: 8) {
                            HStack(spacing: 20) {
                                Button(action: { player.toggle() }) {
                                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 50))
                                        .symbolRenderingMode(.hierarchical)
                                }
                                .buttonStyle(.glass)
                            }
                            
                            VStack(spacing: 4) {
                                Slider(
                                    value: $sliderValue,
                                    in: 0...max(player.duration, 1),
                                    onEditingChanged: { editing in
                                        player.isSeeking = editing
                                        if !editing { player.seek(to: sliderValue) }
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
                                if !player.isSeeking { sliderValue = newValue }
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
                    .onChange(of: player.isPlaying) { _, isPlaying in
                        if isPlaying {
                            store.markPlayed(song)
                        }
                    }
                } else {
                    // No audio — import button
                    Button(action: { showAudioPicker = true }) {
                        Label("Importar Áudio", systemImage: "square.and.arrow.down")
                            .font(.system(.subheadline, design: .rounded))
                    }
                    .buttonStyle(.glass)
                    .padding(.vertical, 10)
                }
            } else {
                // Edit mode: audio management
                HStack(spacing: 12) {
                    Button(action: { showAudioPicker = true }) {
                        Label(song.audioFilename != nil ? "Trocar Áudio" : "Importar Áudio", systemImage: "square.and.arrow.down")
                            .font(.system(.caption, design: .rounded))
                    }
                    .buttonStyle(.glass)
                    
                    if song.audioFilename != nil {
                        Button(role: .destructive, action: { showDeleteAudioConfirm = true }) {
                            Label("Remover", systemImage: "trash")
                                .font(.system(.caption, design: .rounded))
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Tab Picker
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
                    Text(showLyrics ? song.lyrics : song.chordsText)
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
            }
        }
        .onDisappear {
            player.stop()
        }
        .fileImporter(
            isPresented: $showAudioPicker,
            allowedContentTypes: [.audio, .mp3, .wav, .aiff, UTType("public.mpeg-4-audio") ?? .audio],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                player.stop()
                song = store.importAudio(from: url, for: song)
            }
        }
        .alert("Remover Áudio?", isPresented: $showDeleteAudioConfirm) {
            Button("Remover", role: .destructive) {
                player.stop()
                song = store.deleteAudio(for: song)
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("O arquivo de áudio será apagado permanentemente.")
        }
    }
    
    func startEditing() {
        editedTitle = song.title
        editedArtist = song.artist
        editedLyrics = song.lyrics
        editedChords = song.chordsText
        isEditing = true
    }
    
    func saveChanges() {
        song.title = editedTitle.trimmingCharacters(in: .whitespaces)
        song.artist = editedArtist.trimmingCharacters(in: .whitespaces)
        song.lyrics = editedLyrics
        song.chordsText = editedChords
        store.updateSong(song)
        isEditing = false
    }
}
