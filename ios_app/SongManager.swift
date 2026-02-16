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
    
    // LINK DO RAILWAY (CLOUD)
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
}

// MARK: - Audio Player
class AudioPlayer: ObservableObject {
    var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isSeeking = false
    
    private var timeObserver: Any?
    
    func play(url: URL) {
        // Configure for background playback
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
        
        // Observe duration once the item is ready
        item.asset.loadValuesAsynchronously(forKeys: ["duration"]) {
            DispatchQueue.main.async {
                let seconds = CMTimeGetSeconds(item.asset.duration)
                if seconds.isFinite {
                    self.duration = seconds
                }
            }
        }
        
        // Periodic time observer — update every 0.25s
        removeTimeObserver()
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isSeeking else { return }
            self.currentTime = CMTimeGetSeconds(time)
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
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func stop() {
        removeTimeObserver()
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }
    
    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
}

// MARK: - Time Formatter
func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite && seconds >= 0 else { return "0:00" }
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

// MARK: - Views
struct ContentView: View {
    @StateObject var service = SongService()
    
    var body: some View {
        NavigationView {
            List(service.songs) { song in
                NavigationLink(destination: SongDetailView(song: song, service: service)) {
                    VStack(alignment: .leading) {
                        Text(song.title)
                            .font(.headline)
                        if !song.artist.isEmpty {
                            Text(song.artist)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle("Setlist 🎸")
            .onAppear {
                service.fetchSongs()
            }
        }
    }
}

struct SongDetailView: View {
    let song: Song
    @ObservedObject var service: SongService
    @StateObject var player = AudioPlayer()
    @State private var showLyrics = true
    @State private var fontSize: CGFloat = 18
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Header: Title + Artist ---
            VStack(spacing: 4) {
                Text(song.title)
                    .font(.title)
                    .bold()
                Text(song.artist)
                    .font(.title3)
                    .foregroundColor(.gray)
            }
            .padding(.top, 10)
            .padding(.bottom, 6)
            
            // --- Audio Player Section ---
            if let audioFile = song.audio_filename,
               let url = service.getAudioURL(filename: audioFile) {
                
                VStack(spacing: 10) {
                    // Play/Pause Button
                    Button(action: {
                        if !player.isPlaying && player.player == nil {
                            player.play(url: url)
                        } else {
                            player.toggle()
                        }
                    }) {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                    }
                    
                    // --- Progress Slider ---
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { player.currentTime },
                                set: { newValue in
                                    player.currentTime = newValue
                                    player.seek(to: newValue)
                                }
                            ),
                            in: 0...(max(player.duration, 0.01)),
                            onEditingChanged: { editing in
                                player.isSeeking = editing
                            }
                        )
                        .tint(.blue)
                        
                        HStack {
                            Text(formatTime(player.currentTime))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatTime(player.duration))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 8)
                
            } else {
                Text("Sem Áudio")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.vertical, 8)
            }
            
            // --- Lyrics / Chords Toggle ---
            Picker("View", selection: $showLyrics) {
                Text("Letra").tag(true)
                Text("Cifra").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.vertical, 4)
            
            // --- Content ---
            ScrollView {
                Text(showLyrics ? song.lyrics : song.chords_text)
                    .font(.system(size: fontSize, design: showLyrics ? .default : .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // --- Font Size Control ---
            HStack {
                Button("A-") { if fontSize > 10 { fontSize -= 2 } }
                Slider(value: $fontSize, in: 10...30)
                Button("A+") { if fontSize < 40 { fontSize += 2 } }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .onDisappear {
            player.stop()
        }
    }
}

// MARK: - App Entry Point (Use this in @main)
/*
 @main
 struct SongManagerApp: App {
     var body: some Scene {
         WindowGroup {
             ContentView()
         }
     }
 }
 */
