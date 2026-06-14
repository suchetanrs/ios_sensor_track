import SwiftUI
import UIKit

/// Coordinates a sleep session end-to-end: accelerometer → epoch aggregator (live),
/// optional microphone snore/breathing detection, then on stop runs Cole-Kripke +
/// rescoring, computes metrics, persists the night, and writes it to Apple Health.
@MainActor
final class SleepTracker: ObservableObject {

    // Live, observable state for the UI.
    @Published var isTracking = false
    @Published var startDate: Date?
    @Published var elapsed: TimeInterval = 0
    @Published var currentActivity: Double = 0
    @Published var liveState: SleepState = .awake
    @Published var snoreCount = 0
    @Published var micEnabled = false
    @Published var statusMessage = "Ready"

    /// Saved nights, newest first.
    @Published var sessions: [SleepSession] = []

    /// One minute per epoch — matches the Cole-Kripke weights' validated epoch length.
    let epochLength: TimeInterval = 60

    private let feeder = AccelerometerFeeder(sampleRate: 10)
    private let sound = SoundDetector()
    private let store = SleepSessionStore()
    private let health = HealthKitWriter()

    private var aggregator: EpochAggregator?
    private var rawEpochs: [(index: Int, activity: Double, start: Date)] = []
    private var soundEvents: [SoundEvent] = []
    private var latestMagnitude = 0.0
    private var uiTimer: Timer?

    init() {
        sessions = store.loadAll()

        feeder.onSample = { [weak self] magnitude, timestamp in
            Task { @MainActor in self?.handleSample(magnitude, timestamp) }
        }
        sound.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.soundEvents.append(event)
                if event.kind == .snoring { self?.snoreCount += 1 }
            }
        }
    }

    // MARK: - Microphone opt-in

    func setMic(_ on: Bool) {
        guard on else { micEnabled = false; sound.stop(); return }
        SoundDetector.requestPermission { [weak self] granted in
            guard let self else { return }
            self.micEnabled = granted
            if !granted {
                self.statusMessage = "Microphone permission denied"
            } else if self.isTracking {
                try? self.sound.start()
            }
        }
    }

    // MARK: - Session lifecycle

    func start() {
        guard !isTracking else { return }
        guard feeder.isAvailable else {
            statusMessage = "Motion sensor unavailable on this device"
            return
        }

        aggregator = EpochAggregator(epochLength: epochLength)
        rawEpochs = []
        soundEvents = []
        snoreCount = 0
        latestMagnitude = 0
        liveState = .awake
        startDate = Date()
        elapsed = 0
        isTracking = true
        statusMessage = "Tracking…"

        feeder.start()
        if micEnabled { try? sound.start() }
        if health.isAvailable { health.requestAuthorization() }

        // Keep the screen awake so the app stays active even without the mic keep-alive.
        UIApplication.shared.isIdleTimerDisabled = true

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        uiTimer = timer
    }

    func stop() {
        guard isTracking, let start = startDate else { return }

        feeder.stop()
        sound.stop()
        uiTimer?.invalidate(); uiTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        isTracking = false

        if let last = aggregator?.finish() {
            rawEpochs.append((last.index, last.activity,
                              start.addingTimeInterval(Double(last.index) * epochLength)))
        }
        aggregator = nil

        let session = buildSession(start: start, end: Date())
        store.save(session)
        sessions.insert(session, at: 0)
        statusMessage = "Saved \(timeString(session.metrics.totalSleepTime)) of sleep"

        if health.isAvailable { health.write(session: session) }
    }

    func delete(_ session: SleepSession) {
        store.delete(session)
        sessions.removeAll { $0.id == session.id }
    }

    // MARK: - Internals

    private func handleSample(_ magnitude: Double, _ timestamp: TimeInterval) {
        latestMagnitude = magnitude
        guard let aggregator else { return }
        let finalized = aggregator.ingest(magnitude: magnitude, at: timestamp)
        guard !finalized.isEmpty, let start = startDate else { return }
        for epoch in finalized {
            rawEpochs.append((epoch.index, epoch.activity,
                              start.addingTimeInterval(Double(epoch.index) * epochLength)))
        }
        liveState = classify(rawEpochs.map { $0.activity }).last ?? .awake
    }

    private func tick() {
        guard let start = startDate else { return }
        elapsed = Date().timeIntervalSince(start)
        currentActivity = latestMagnitude
    }

    private func classify(_ activity: [Double]) -> [SleepState] {
        let raw = ColeKripkeClassifier().classify(activity)
        return SleepRescorer(epochsPerMinute: 60 / epochLength).rescore(raw)
    }

    private func buildSession(start: Date, end: Date) -> SleepSession {
        let states = classify(rawEpochs.map { $0.activity })
        let epochs = rawEpochs.enumerated().map { i, raw in
            SleepEpoch(index: raw.index, start: raw.start, activity: raw.activity,
                       state: i < states.count ? states[i] : .awake)
        }
        let metrics = SleepMetricsCalculator.metrics(epochs: epochs, epochLength: epochLength,
                                                      soundEvents: soundEvents)
        return SleepSession(start: start, end: end, epochLength: epochLength,
                            epochs: epochs, soundEvents: soundEvents, metrics: metrics)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60
        return "\(h)h \(m)m"
    }
}
