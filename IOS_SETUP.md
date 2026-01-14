# 📱 Como Criar o App Nativo (Xcode)

Este guia ensina a instalar o aplicativo nativo no seu iPhone, conectando ao seu servidor na nuvem (Railway).

## 1. Pré-requisitos
*   Um Mac com **Xcode** instalado (Grátis na Mac App Store).
*   Um iPhone com cabo para conectar no Mac.

## 2. Criar o Projeto no Xcode
1.  Abra o **Xcode**.
2.  Clique em **"Create New Project..."**.
3.  Vá na aba **iOS** (no topo) -> Selecione **App** -> Clique em **Next**.
4.  Preencha:
    *   **Product Name:** `SongManager`
    *   **Interface:** SwiftUI
    *   **Language:** Swift
    *   **Storage:** None
5.  Clique em **Next** e salve na Área de Trabalho.

## 3. Colar o Código
1.  No Xcode, na barra lateral esquerda, clique em `ContentView.swift` (ou `SongManagerApp.swift` se não achar o Content).
2.  **APAGUE** todo o código que estiver lá.
3.  **COPIE e COLE** o código abaixo:

*(Este código já usa seu link da nuvem)*
```swift
import SwiftUI
import AVFoundation

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
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
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
    @State private var fontSize: CGFloat = 18
    
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
                    .font(.system(size: fontSize, design: showLyrics ? .default : .monospaced))
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

@main
struct SongManagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## 4. Rodar no iPhone
1.  Conecte seu iPhone no Mac com o cabo.
2.  No topo da janela do Xcode, selecione seu iPhone na lista de dispositivos (onde diz "Simulator" ou "Generic Device").
3.  Clique no botão **Play ▶️** (triângulo no topo esquerdo).
4.  O app será instalado e abrirá no seu celular!
