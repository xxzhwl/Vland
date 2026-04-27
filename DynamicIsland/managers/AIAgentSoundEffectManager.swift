/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AVFoundation
import Defaults
import Foundation

final class AIAgentSoundEffectManager {
    static let shared = AIAgentSoundEffectManager()

    enum Cue: Hashable {
        case sessionStart
        case promptSubmitted
        case waitingInput
        case completed
        case replySent
        case replyCopied
        case error
    }

    private struct ToneStep {
        let frequency: Double?
        let duration: TimeInterval
        let amplitude: Float
    }

    private let queue = DispatchQueue(label: "com.vland.ai-agent-sfx", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    private var lastPlaybackDates: [Cue: Date] = [:]
    private let minimumReplayIntervals: [Cue: TimeInterval] = [
        .sessionStart: 0.18,
        .promptSubmitted: 0.10,
        .waitingInput: 0.45,
        .completed: 0.15,
        .replySent: 0.08,
        .replyCopied: 0.08,
        .error: 0.18,
    ]

    private init() {
        engine.attach(playerNode)
        if let format {
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        }
        engine.mainMixerNode.outputVolume = 0.65
    }

    func play(_ cue: Cue) {
        guard Defaults[.aiAgentSoundEffectsEnabled] else { return }

        queue.async { [weak self] in
            self?.playLocked(cue)
        }
    }

    private func playLocked(_ cue: Cue) {
        let now = Date()
        let minimumInterval = minimumReplayIntervals[cue] ?? 0.12
        if let lastPlayback = lastPlaybackDates[cue], now.timeIntervalSince(lastPlayback) < minimumInterval {
            return
        }
        lastPlaybackDates[cue] = now

        guard let format,
              let buffer = makeBuffer(for: cue, format: format) else {
            return
        }

        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            NSLog("⚠️ Failed to start AI agent sound engine: \(error.localizedDescription)")
            return
        }

        // Use .interrupts option which automatically stops current playback and starts the new buffer
        // No need to call stop() or play() separately - .interrupts handles everything
        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    private func makeBuffer(for cue: Cue, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sequence = sequence(for: cue)
        let frameCount = sequence.reduce(0) { partialResult, step in
            partialResult + Int(step.duration * sampleRate)
        }

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ),
              let channelData = buffer.floatChannelData?[0] else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        var cursor = 0

        for step in sequence {
            let stepFrameCount = Int(step.duration * sampleRate)
            guard stepFrameCount > 0 else { continue }

            if let frequency = step.frequency {
                for frame in 0..<stepFrameCount {
                    let time = Double(frame) / sampleRate
                    let rawWave = squareWave(frequency: frequency, time: time)
                    let crushedWave = round(rawWave * 7) / 7
                    let envelope = envelopeValue(frame: frame, totalFrames: stepFrameCount)
                    channelData[cursor + frame] = Float(crushedWave) * step.amplitude * envelope
                }
            } else {
                for frame in 0..<stepFrameCount {
                    channelData[cursor + frame] = 0
                }
            }

            cursor += stepFrameCount
        }

        return buffer
    }

    private func squareWave(frequency: Double, time: Double) -> Double {
        let phase = (time * frequency).truncatingRemainder(dividingBy: 1)
        return phase < 0.5 ? 1.0 : -1.0
    }

    private func envelopeValue(frame: Int, totalFrames: Int) -> Float {
        let attackFrames = max(1, Int(Double(totalFrames) * 0.08))
        let releaseFrames = max(1, Int(Double(totalFrames) * 0.30))

        if frame < attackFrames {
            return Float(frame) / Float(attackFrames)
        }

        let releaseStart = max(attackFrames, totalFrames - releaseFrames)
        if frame >= releaseStart {
            let releaseProgress = Float(frame - releaseStart) / Float(max(1, totalFrames - releaseStart))
            return max(0.0, 1.0 - releaseProgress)
        }

        return 1.0
    }

    private func sequence(for cue: Cue) -> [ToneStep] {
        switch cue {
        case .sessionStart:
            return [
                ToneStep(frequency: 740, duration: 0.045, amplitude: 0.20),
                ToneStep(frequency: 988, duration: 0.055, amplitude: 0.22),
                ToneStep(frequency: 1_318, duration: 0.08, amplitude: 0.24),
            ]
        case .promptSubmitted:
            return [
                ToneStep(frequency: 659, duration: 0.04, amplitude: 0.18),
                ToneStep(frequency: 784, duration: 0.045, amplitude: 0.20),
                ToneStep(frequency: 988, duration: 0.06, amplitude: 0.22),
            ]
        case .waitingInput:
            return [
                ToneStep(frequency: 988, duration: 0.045, amplitude: 0.22),
                ToneStep(frequency: nil, duration: 0.02, amplitude: 0),
                ToneStep(frequency: 988, duration: 0.045, amplitude: 0.22),
                ToneStep(frequency: nil, duration: 0.02, amplitude: 0),
                ToneStep(frequency: 740, duration: 0.075, amplitude: 0.20),
            ]
        case .completed:
            return [
                ToneStep(frequency: 784, duration: 0.04, amplitude: 0.19),
                ToneStep(frequency: 988, duration: 0.05, amplitude: 0.22),
                ToneStep(frequency: 1_318, duration: 0.09, amplitude: 0.24),
            ]
        case .replySent:
            return [
                ToneStep(frequency: 1_175, duration: 0.04, amplitude: 0.20),
                ToneStep(frequency: 1_568, duration: 0.06, amplitude: 0.22),
            ]
        case .replyCopied:
            return [
                ToneStep(frequency: 523, duration: 0.04, amplitude: 0.18),
                ToneStep(frequency: 659, duration: 0.06, amplitude: 0.20),
            ]
        case .error:
            return [
                ToneStep(frequency: 392, duration: 0.055, amplitude: 0.20),
                ToneStep(frequency: 330, duration: 0.06, amplitude: 0.22),
                ToneStep(frequency: 262, duration: 0.09, amplitude: 0.23),
            ]
        }
    }
}
