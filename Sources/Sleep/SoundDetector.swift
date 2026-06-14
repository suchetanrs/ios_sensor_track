import Foundation
import AVFoundation
import SoundAnalysis

/// Listens to the microphone and flags snoring / breathing using Apple's built-in
/// SoundAnalysis classifier. Everything is processed on-device; no audio is recorded
/// or stored. The active audio session doubles as the overnight keep-alive — together
/// with the `audio` background mode it lets tracking continue with the screen locked.
final class SoundDetector: NSObject {
    private let engine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "com.example.sensortrack.sleep.sound")
    private var analyzer: SNAudioStreamAnalyzer?
    private var request: SNClassifySoundRequest?

    /// Delivered on the main thread for snore/breathing detections above `minConfidence`.
    var onEvent: ((SoundEvent) -> Void)?

    /// Labels we care about from the built-in classifier (`SNClassifierIdentifier.version1`).
    private let interesting: [String: SoundEventKind] = [
        "snoring": .snoring,
        "breathing": .breathing,
    ]
    private let minConfidence = 0.5

    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        let handler: (Bool) -> Void = { granted in
            DispatchQueue.main.async { completion(granted) }
        }
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: handler)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(handler)
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.mixWithOthers, .allowBluetooth])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let analyzer = SNAudioStreamAnalyzer(format: format)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 600)
        request.overlapFactor = 0.5
        try analyzer.add(request, withObserver: self)
        self.analyzer = analyzer
        self.request = request

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, when in
            self?.analysisQueue.async {
                self?.analyzer?.analyze(buffer, atAudioFramePosition: when.sampleTime)
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        analyzer?.completeAnalysis()
        analyzer = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

extension SoundDetector: SNResultsObserving {
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        for (label, kind) in interesting {
            guard let classification = result.classification(forIdentifier: label),
                  classification.confidence >= minConfidence else { continue }
            let event = SoundEvent(date: Date(), kind: kind, confidence: classification.confidence)
            DispatchQueue.main.async { self.onEvent?(event) }
        }
    }
}
