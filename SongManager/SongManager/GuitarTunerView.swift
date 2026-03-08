//
//  GuitarTunerView.swift
//  SongManager
//
//  Created by Daniela Bueno on 08/03/26.
//

import SwiftUI
import AVFoundation
import Accelerate

// MARK: - Note Data
struct NoteInfo: Equatable {
    let name: String
    let octave: Int
    let frequency: Double
    
    var fullName: String { "\(name)\(octave)" }
}

// MARK: - Guitar String Reference
struct GuitarString: Identifiable {
    let id: Int
    let name: String
    let note: String
    let octave: Int
    let frequency: Double
    
    var label: String { "\(note)\(octave)" }
}

let standardTuning: [GuitarString] = [
    GuitarString(id: 6, name: "6ª", note: "E", octave: 2, frequency: 82.41),
    GuitarString(id: 5, name: "5ª", note: "A", octave: 2, frequency: 110.00),
    GuitarString(id: 4, name: "4ª", note: "D", octave: 3, frequency: 146.83),
    GuitarString(id: 3, name: "3ª", note: "G", octave: 3, frequency: 196.00),
    GuitarString(id: 2, name: "2ª", note: "B", octave: 3, frequency: 246.94),
    GuitarString(id: 1, name: "1ª", note: "E", octave: 4, frequency: 329.63),
]

// MARK: - All Note Frequencies (chromatic)
let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

func closestNote(to frequency: Double) -> NoteInfo {
    // A4 = 440 Hz
    let semitonesFromA4 = 12.0 * log2(frequency / 440.0)
    let roundedSemitones = round(semitonesFromA4)
    
    // MIDI note number (A4 = 69)
    let midiNote = Int(roundedSemitones) + 69
    let noteIndex = ((midiNote % 12) + 12) % 12
    let octave = (midiNote / 12) - 1
    
    let targetFrequency = 440.0 * pow(2.0, roundedSemitones / 12.0)
    
    return NoteInfo(
        name: noteNames[noteIndex],
        octave: octave,
        frequency: targetFrequency
    )
}

func centsOff(detected: Double, target: Double) -> Double {
    return 1200.0 * log2(detected / target)
}

// MARK: - Pitch Detector
class PitchDetector: ObservableObject {
    @Published var detectedFrequency: Double = 0
    @Published var currentNote: NoteInfo?
    @Published var cents: Double = 0
    @Published var isListening = false
    @Published var inputLevel: Float = 0
    
    private var audioEngine: AVAudioEngine?
    private let sampleRate: Double = 44100
    private let bufferSize: AVAudioFrameCount = 4096
    
    func start() {
        guard !isListening else { return }
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
            return
        }
        
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }
        
        do {
            try engine.start()
            isListening = true
        } catch {
            print("Engine start error: \(error)")
        }
    }
    
    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isListening = false
        
        // Deactivate audio session so other audio can resume
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        
        // Calculate RMS level
        var rms: Float = 0
        vDSP_measqv(channelData, 1, &rms, vDSP_Length(frameCount))
        rms = sqrtf(rms)
        
        let level = rms
        
        // Noise gate – ignore very quiet signals
        guard level > 0.01 else {
            DispatchQueue.main.async {
                self.inputLevel = level
            }
            return
        }
        
        // Autocorrelation for pitch detection
        let frequency = detectPitch(data: channelData, count: frameCount, sampleRate: Float(sampleRate))
        
        guard frequency > 60 && frequency < 1200 else {
            DispatchQueue.main.async {
                self.inputLevel = level
            }
            return
        }
        
        let note = closestNote(to: frequency)
        let c = centsOff(detected: frequency, target: note.frequency)
        
        DispatchQueue.main.async {
            self.detectedFrequency = frequency
            self.currentNote = note
            self.cents = c
            self.inputLevel = level
        }
    }
    
    private func detectPitch(data: UnsafePointer<Float>, count: Int, sampleRate: Float) -> Double {
        // Autocorrelation-based pitch detection
        let minLag = Int(sampleRate / 1200)  // max freq ~1200 Hz
        let maxLag = Int(sampleRate / 60)     // min freq ~60 Hz
        
        guard maxLag < count else { return 0 }
        
        var bestCorrelation: Float = 0
        var bestLag = 0
        
        // Compute normalized autocorrelation
        for lag in minLag...maxLag {
            var correlation: Float = 0
            var energy1: Float = 0
            var energy2: Float = 0
            
            let length = vDSP_Length(count - lag)
            
            // Dot product for correlation
            vDSP_dotpr(data, 1, data.advanced(by: lag), 1, &correlation, length)
            
            // Energies for normalization
            vDSP_dotpr(data, 1, data, 1, &energy1, length)
            vDSP_dotpr(data.advanced(by: lag), 1, data.advanced(by: lag), 1, &energy2, length)
            
            let norm = sqrtf(energy1 * energy2)
            guard norm > 0 else { continue }
            
            let normalizedCorrelation = correlation / norm
            
            if normalizedCorrelation > bestCorrelation {
                bestCorrelation = normalizedCorrelation
                bestLag = lag
            }
        }
        
        // Only accept strong correlations
        guard bestCorrelation > 0.8, bestLag > 0 else { return 0 }
        
        // Parabolic interpolation for sub-sample accuracy
        if bestLag > minLag && bestLag < maxLag {
            var corrMinus: Float = 0
            var corrPlus: Float = 0
            let length = vDSP_Length(count - bestLag - 1)
            
            vDSP_dotpr(data, 1, data.advanced(by: bestLag - 1), 1, &corrMinus, length)
            vDSP_dotpr(data, 1, data.advanced(by: bestLag + 1), 1, &corrPlus, length)
            
            let delta = (corrPlus - corrMinus) / (2.0 * (2.0 * bestCorrelation - corrPlus - corrMinus))
            let refinedLag = Float(bestLag) + delta
            
            return Double(sampleRate / refinedLag)
        }
        
        return Double(sampleRate / Float(bestLag))
    }
}

// MARK: - Tuner Gauge View
struct TunerGaugeView: View {
    let cents: Double
    let isActive: Bool
    
    private var needleAngle: Double {
        // Map -50...+50 cents to -45...+45 degrees
        let clampedCents = max(-50, min(50, cents))
        return clampedCents * 0.9
    }
    
    private var tuningColor: Color {
        let absCents = abs(cents)
        if absCents <= 5 { return .green }
        if absCents <= 15 { return .yellow }
        return .red
    }
    
    var body: some View {
        ZStack {
            // Background arc
            Arc(startAngle: .degrees(-135), endAngle: .degrees(-45))
                .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                .frame(width: 250, height: 250)
            
            // Green zone indicators
            Arc(startAngle: .degrees(-94.5), endAngle: .degrees(-85.5))
                .stroke(Color.green.opacity(0.6), lineWidth: 6)
                .frame(width: 250, height: 250)
            
            // Tick marks
            ForEach(-5..<6, id: \.self) { tick in
                Rectangle()
                    .fill(tick == 0 ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: tick == 0 ? 3 : 1.5, height: tick == 0 ? 20 : 12)
                    .offset(y: -115)
                    .rotationEffect(.degrees(Double(tick) * 9))
            }
            
            // Needle
            if isActive {
                NeedleShape()
                    .fill(tuningColor)
                    .frame(width: 4, height: 100)
                    .offset(y: -40)
                    .rotationEffect(.degrees(needleAngle))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cents)
                
                // Needle pivot
                Circle()
                    .fill(tuningColor)
                    .frame(width: 16, height: 16)
                    .shadow(color: tuningColor.opacity(0.5), radius: 8)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 16, height: 16)
            }
            
            // Labels
            HStack {
                Text("♭")
                    .font(.system(.title2, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("♯")
                    .font(.system(.title2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200)
            .offset(y: 40)
        }
    }
}

// MARK: - Custom Shapes
struct Arc: Shape {
    let startAngle: Angle
    let endAngle: Angle
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

struct NeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let bottomLeft = CGPoint(x: rect.midX - rect.width / 2, y: rect.maxY)
        let bottomRight = CGPoint(x: rect.midX + rect.width / 2, y: rect.maxY)
        path.move(to: top)
        path.addLine(to: bottomLeft)
        path.addLine(to: bottomRight)
        path.closeSubpath()
        return path
    }
}

// MARK: - Guitar Tuner View
struct GuitarTunerView: View {
    @StateObject private var detector = PitchDetector()
    @State private var selectedString: GuitarString? = nil
    @Environment(\.dismiss) var dismiss
    
    private var displayNote: String {
        if let note = detector.currentNote {
            return note.name
        }
        return "—"
    }
    
    private var displayOctave: String {
        if let note = detector.currentNote {
            return "\(note.octave)"
        }
        return ""
    }
    
    private var displayFrequency: String {
        if detector.detectedFrequency > 0 {
            return String(format: "%.1f Hz", detector.detectedFrequency)
        }
        return "— Hz"
    }
    
    private var tuningStatus: String {
        guard detector.currentNote != nil else { return "Toque uma corda" }
        let absCents = abs(detector.cents)
        if absCents <= 5 { return "Afinado! ✓" }
        if detector.cents > 0 { return "Agudo ♯" }
        return "Grave ♭"
    }
    
    private var tuningColor: Color {
        guard detector.currentNote != nil else { return .secondary }
        let absCents = abs(detector.cents)
        if absCents <= 5 { return .green }
        if absCents <= 15 { return .yellow }
        return .red
    }
    
    private var matchingString: GuitarString? {
        guard let note = detector.currentNote else { return nil }
        return standardTuning.first { $0.note == note.name && $0.octave == note.octave }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemBackground).opacity(0.95),
                        tuningColor.opacity(0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Spacer()
                    
                    // Gauge
                    TunerGaugeView(
                        cents: detector.cents,
                        isActive: detector.currentNote != nil
                    )
                    .frame(height: 200)
                    
                    // Note Display
                    VStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(displayNote)
                                .font(.system(size: 72, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                            
                            Text(displayOctave)
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .offset(y: -20)
                        }
                        .animation(.spring(response: 0.2), value: detector.currentNote)
                        
                        Text(displayFrequency)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        
                        // Tuning status
                        Text(tuningStatus)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(tuningColor)
                            .padding(.top, 4)
                            .animation(.easeInOut, value: tuningStatus)
                        
                        // Cents display
                        if detector.currentNote != nil {
                            Text(String(format: "%+.0f cents", detector.cents))
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Guitar string reference
                    VStack(spacing: 12) {
                        Text("Afinação Padrão")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .kerning(1.5)
                        
                        HStack(spacing: 12) {
                            ForEach(standardTuning) { string in
                                let isDetected = matchingString?.id == string.id
                                
                                VStack(spacing: 4) {
                                    Text(string.note)
                                        .font(.system(.title3, weight: .bold, design: .rounded))
                                    Text(string.name)
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 48, height: 60)
                                .background {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(isDetected ? tuningColor.opacity(0.15) : Color.secondary.opacity(0.08))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(
                                            isDetected ? tuningColor : Color.clear,
                                            lineWidth: 2
                                        )
                                }
                                .scaleEffect(isDetected ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3), value: isDetected)
                            }
                        }
                    }
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    .padding(.horizontal)
                    
                    // Input level indicator
                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.15))
                                
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.green, .yellow, .red],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0, geo.size.width * CGFloat(min(detector.inputLevel * 10, 1.0))))
                                    .animation(.easeOut(duration: 0.1), value: detector.inputLevel)
                            }
                        }
                        .frame(height: 6)
                        
                        Text("Nível do microfone")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Afinador 🎸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                detector.start()
            }
            .onDisappear {
                detector.stop()
            }
        }
    }
}

#Preview {
    GuitarTunerView()
}
