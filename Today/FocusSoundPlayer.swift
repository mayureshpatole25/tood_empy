import AVFoundation
import Observation

/// Plays one procedurally generated ambient sound at a time via a real-time
/// synthesis node, no bundled audio files, nothing to decode or loop-seam.
/// Shared singleton so the status-bar menu and Home's control both reflect
/// (and control) the same playback state.
@MainActor
@Observable
final class FocusSoundPlayer {
    static let shared = FocusSoundPlayer()

    private static let volumeKey = "today.focusSoundVolume"

    private(set) var currentSound: FocusSound?
    var isPlaying: Bool { currentSound != nil }

    var volume: Float = (UserDefaults.standard.object(forKey: FocusSoundPlayer.volumeKey) as? Float) ?? 0.35 {
        didSet {
            engine.mainMixerNode.outputVolume = volume
            UserDefaults.standard.set(volume, forKey: Self.volumeKey)
        }
    }

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    private init() {}

    func play(_ sound: FocusSound) {
        stop()

        let format = engine.outputNode.inputFormat(forBus: 0)
        var generator = sound.makeGenerator(sampleRate: Float(format.sampleRate))

        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = generator.next()
                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    data[frame] = sample
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume

        do {
            try engine.start()
            sourceNode = node
            currentSound = sound
        } catch {
            engine.detach(node)
        }
    }

    func stop() {
        guard let sourceNode else { return }
        engine.stop()
        engine.detach(sourceNode)
        self.sourceNode = nil
        currentSound = nil
    }

    func toggle(_ sound: FocusSound) {
        if currentSound == sound {
            stop()
        } else {
            play(sound)
        }
    }
}
