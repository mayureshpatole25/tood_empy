import Foundation

/// A procedurally generated ambient sound for focus time. Everything here
/// is synthesized in real time by `FocusSoundPlayer`, not a bundled audio
/// track or a real recording, so there's nothing to license or ship as an
/// asset. Mostly nature-leaning by design, one plain noise option for
/// masking rather than a whole family of them.
enum FocusSound: String, CaseIterable, Identifiable {
    case rain
    case birds
    case ocean
    case campfire
    case wind
    case brownNoise

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rain: return "Rain"
        case .birds: return "Birds"
        case .ocean: return "Ocean Waves"
        case .campfire: return "Campfire"
        case .wind: return "Wind"
        case .brownNoise: return "Brown Noise"
        }
    }

    var icon: String {
        switch self {
        case .rain: return "cloud.rain"
        case .birds: return "bird"
        case .ocean: return "water.waves"
        case .campfire: return "flame"
        case .wind: return "wind"
        case .brownNoise: return "waveform"
        }
    }

    func makeGenerator(sampleRate: Float) -> any NoiseGenerator {
        switch self {
        case .rain: return RainGenerator(sampleRate: sampleRate)
        case .birds: return BirdsGenerator(sampleRate: sampleRate)
        case .ocean: return OceanGenerator(sampleRate: sampleRate)
        case .campfire: return CampfireGenerator(sampleRate: sampleRate)
        case .wind: return WindGenerator(sampleRate: sampleRate)
        case .brownNoise: return BrownNoiseGenerator()
        }
    }
}

/// One audio sample at a time, called once per frame from the real-time
/// render thread. Kept as tiny structs (not classes) so there's no
/// allocation or reference counting on that thread.
protocol NoiseGenerator {
    mutating func next() -> Float
}

/// A single leaky integrator over white noise: deep and rumbly, the
/// "brown"/"red" noise popular for masking and focus.
struct BrownNoiseGenerator: NoiseGenerator {
    private var last: Float = 0

    mutating func next() -> Float {
        let white = Float.random(in: -1...1)
        last = (last + 0.02 * white) / 1.02
        return last * 1.8
    }
}

/// A steady low-pass "wash" (the background hiss of a downpour) plus
/// sparse, randomly-timed decaying impulses layered on top for individual
/// droplets.
struct RainGenerator: NoiseGenerator {
    private var wash: Float = 0
    private var dropletEnvelope: Float = 0
    private let dropletsPerSecond: Float = 45
    private let sampleRate: Float

    init(sampleRate: Float) {
        self.sampleRate = max(sampleRate, 8000)
    }

    mutating func next() -> Float {
        let white = Float.random(in: -1...1)
        wash = wash * 0.97 + white * 0.03

        var sample = wash * 1.4
        if dropletEnvelope > 0.0005 {
            sample += dropletEnvelope * Float.random(in: -1...1)
            dropletEnvelope *= 0.90
        } else if Float.random(in: 0...1) < dropletsPerSecond / sampleRate {
            dropletEnvelope = Float.random(in: 0.15...0.35)
        }
        return sample * 0.55
    }
}

/// A very quiet forest-noise bed with short randomly-pitched sine "chirps"
/// layered on top, each with its own frequency sweep and attack/decay
/// envelope. An approximation, not a recording, but a recognizable one.
struct BirdsGenerator: NoiseGenerator {
    private var bed: Float = 0
    private let sampleRate: Float

    private var chirpActive = false
    private var chirpPhase: Float = 0
    private var chirpFreqStart: Float = 0
    private var chirpFreqEnd: Float = 0
    private var chirpTotalSamples: Int = 1
    private var chirpSamplesRemaining: Int = 0
    private var chirpAmplitude: Float = 0

    init(sampleRate: Float) {
        self.sampleRate = max(sampleRate, 8000)
    }

    mutating func next() -> Float {
        let white = Float.random(in: -1...1)
        bed = bed * 0.98 + white * 0.02
        var sample = bed * 0.45

        if chirpActive {
            let t = Float(chirpTotalSamples - chirpSamplesRemaining) / Float(chirpTotalSamples)
            let freq = chirpFreqStart + (chirpFreqEnd - chirpFreqStart) * t
            chirpPhase += 2 * .pi * freq / sampleRate
            if chirpPhase > 2 * .pi { chirpPhase -= 2 * .pi }
            let envelope = sin(.pi * min(max(t, 0), 1))
            sample += sin(chirpPhase) * chirpAmplitude * envelope
            chirpSamplesRemaining -= 1
            if chirpSamplesRemaining <= 0 { chirpActive = false }
        } else if Float.random(in: 0...1) < 2.5 / sampleRate {
            chirpActive = true
            chirpPhase = 0
            chirpFreqStart = Float.random(in: 1800...3200)
            chirpFreqEnd = chirpFreqStart + Float.random(in: -700...900)
            let duration = Float.random(in: 0.06...0.18)
            chirpTotalSamples = max(1, Int(duration * sampleRate))
            chirpSamplesRemaining = chirpTotalSamples
            chirpAmplitude = Float.random(in: 0.14...0.24)
        }

        return sample * 0.6
    }
}

/// Filtered noise with a slow rhythmic swell standing in for waves rolling
/// in and breaking, rather than a flat, constant wash.
struct OceanGenerator: NoiseGenerator {
    private var filtered: Float = 0
    private var wavePhase: Float = 0
    private let sampleRate: Float

    init(sampleRate: Float) {
        self.sampleRate = max(sampleRate, 8000)
    }

    mutating func next() -> Float {
        let white = Float.random(in: -1...1)
        filtered = filtered * 0.96 + white * 0.04
        wavePhase += (2 * .pi * 0.15) / sampleRate
        if wavePhase > 2 * .pi { wavePhase -= 2 * .pi }
        let swell = pow((sin(wavePhase) + 1) / 2, 2)
        return filtered * 1.8 * (0.25 + 0.75 * swell)
    }
}

/// A warm low rumble (a gentler brown noise) plus sparse, sharply-decaying
/// pops for individual crackles.
struct CampfireGenerator: NoiseGenerator {
    private var rumble: Float = 0
    private var crackleEnvelope: Float = 0
    private let cracklesPerSecond: Float = 6
    private let sampleRate: Float

    init(sampleRate: Float) {
        self.sampleRate = max(sampleRate, 8000)
    }

    mutating func next() -> Float {
        let white = Float.random(in: -1...1)
        rumble = (rumble + 0.015 * white) / 1.015
        var sample = rumble * 1.6

        if crackleEnvelope > 0.001 {
            sample += crackleEnvelope * Float.random(in: -1...1)
            crackleEnvelope *= 0.80
        } else if Float.random(in: 0...1) < cracklesPerSecond / sampleRate {
            crackleEnvelope = Float.random(in: 0.2...0.5)
        }
        return sample * 0.5
    }
}

/// Heavier low-pass than rain's wash (breathier, less hissy) with a slow
/// gust cycle modulating the amplitude up and down.
struct WindGenerator: NoiseGenerator {
    private var filtered: Float = 0
    private var gustPhase: Float = 0
    private let sampleRate: Float

    init(sampleRate: Float) {
        self.sampleRate = max(sampleRate, 8000)
    }

    mutating func next() -> Float {
        let white = Float.random(in: -1...1)
        filtered = filtered * 0.985 + white * 0.015
        gustPhase += (2 * .pi * 0.07) / sampleRate
        if gustPhase > 2 * .pi { gustPhase -= 2 * .pi }
        let gust = 0.6 + 0.4 * sin(gustPhase)
        return filtered * 2.2 * gust
    }
}
