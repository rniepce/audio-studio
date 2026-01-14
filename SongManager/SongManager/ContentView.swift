//
//  ContentView.swift
//  SongManager
//
//  Created by Daniela Bueno on 14/01/26.
//

import SwiftUI
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
}

// MARK: - Audio Player
class AudioPlayer: ObservableObject {
    var player: AVPlayer?
    @Published var isPlaying = false
    
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
    }
    
    func toggle() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
    
    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
    }
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
    @State private var fontSize: Double = 18
    
    var body: some View {
        VStack {
            VStack(spacing: 10) {
                Text(song.title).font(.largeTitle).bold()
                Text(song.artist).font(.title2).foregroundColor(.gray)
                
                if let audioFile = song.audio_filename, let url = service.getAudioURL(filename: audioFile) {
                    HStack {
                        Button(action: { player.toggle() }) {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 50))
                        }
                        .onAppear {
                            player.play(url: url)
                            player.player?.pause()
                            player.isPlaying = false
                        }
                    }
                } else {
                    Text("Sem Áudio").font(.caption).foregroundColor(.red)
                }
            }
            .padding()
            
            Picker("View", selection: $showLyrics) {
                Text("Letra").tag(true)
                Text("Cifra").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            ScrollView {
                Text(showLyrics ? song.lyrics : song.chords_text)
                    .font(.system(size: CGFloat(fontSize), design: showLyrics ? .default : .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack {
                Button("A-") { if fontSize > 10 { fontSize -= 2 } }
                Slider(value: $fontSize, in: 10...30)
                Button("A+") { if fontSize < 40 { fontSize += 2 } }
            }
            .padding()
        }
        .onDisappear {
            player.stop()
        }
    }
}


