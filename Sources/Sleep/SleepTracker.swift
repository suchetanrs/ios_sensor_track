import SwiftUI
import UIKit

/// Coordinates a sleep session end-to-end: accelerometer → epoch aggregator (live),
/// optional microphone snore/breathing detection, then on stop runs Cole-Kripke +
/// rescoring, computes metrics, persists the night, and writes it to Apple Health.
///
/// The in-progress session is checkpointed to disk once per epoch, so if the app is
/// terminated (memory pressure, force-quit, crash) the next launch recovers and resumes
/// the night rather than losing it. Owned at the app level so it also survives
/// navigation within the app.
@MainActor
final class SleepTracker: ObservableObject {

    // Live, observable state for the UI.
    @Published var isTracking = false
    @Published var startDate: Date?
    @Published var elapsed: TimeInterval = 0
    @Published var currentActivity: Double = 0
    @Published var liveState: SleepState = .awake
    @Published var snoreCount = 0
    @Published var micEnabled = true   // snore/breathing detection on by default
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
    private var rawEpochs: [RawEpoch] = []
    private var soundEvents: [SoundEvent] = []
    private var sessionID = UUID()
    private var latestMagnitude = 0.0
    private var uiTimer: Timer?

    init() {
        sessions = store.loadAll()
        wireCallbacks()

        // If a session was in progress when the app was last terminated, pick it back up.
        if let active = store.loadActive() {
            resume(active)
        }
    }

    private func wireCallbacks() {
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
        micEnabled = on
        if on {
            if isTracking { beginSoundDetection() }
        } else {
            sound.stop()
        }
    }

    /// Requests mic permission (no-op prompt once granted) and starts detection.
    /// On denial, turns the toggle off and explains why.
    private func beginSoundDetection() {
        SoundDetector.requestPermission { [weak self] granted in
            guard let self else { return }
            if granted {
                try? self.sound.start()
            } else {
                self.micEnabled = false
                self.statusMessage = "Snore detection off (no mic permission)"
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

        sessionID = UUID()
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

        beginCapture()
        checkpoint()   // mark the session active immediately (covers a kill in minute 1)
    }

    func stop() {
        guard isTracking, let start = startDate else { return }
        endCapture()
        isTracking = false

        if let last = aggregator?.finish() {
            appendEpoch(index: last.index, activity: last.activity, sessionStart: start)
        }
        aggregator = nil

        let session = buildSession(start: start, end: Date())
        store.save(session)
        store.clearActive()              // night finished — no recovery needed
        sessions.insert(session, at: 0)
        statusMessage = "Saved \(timeString(session.metrics.totalSleepTime)) of sleep"

        if health.isAvailable { health.write(session: session) }
    }

    func delete(_ session: SleepSession) {
        store.delete(session)
        sessions.removeAll { $0.id == session.id }
    }

    // MARK: - Recovery

    /// Restore a session that was interrupted by app termination and keep tracking it.
    /// Any time the app was dead is filled with zero-activity (still) epochs so the
    /// timeline stays continuous from the original start.
    private func resume(_ active: ActiveSleepSession) {
        guard feeder.isAvailable else { return }

        sessionID = active.id
        rawEpochs = active.epochs
        soundEvents = active.soundEvents
        snoreCount = soundEvents.filter { $0.kind == .snoring }.count
        micEnabled = active.micEnabled
        startDate = active.start

        // Bridge the gap between the last recorded epoch and now.
        let lastIndex = rawEpochs.last?.index ?? -1
        let nowIndex = max(0, Int(Date().timeIntervalSince(active.start) / epochLength))
        let baseIndex = max(nowIndex, lastIndex + 1)
        for idx in (lastIndex + 1)..<baseIndex {
            rawEpochs.append(RawEpoch(index: idx, activity: 0,
                                      start: active.start.addingTimeInterval(Double(idx) * epochLength)))
        }

        aggregator = EpochAggregator(epochLength: epochLength, startIndex: baseIndex)
        isTracking = true
        statusMessage = "Resumed your sleep session"
        liveState = classify(rawEpochs.map { $0.activity }).last ?? .awake

        beginCapture()
        checkpoint()
    }

    // MARK: - Capture helpers

    private func beginCapture() {
        feeder.start()
        if micEnabled { beginSoundDetection() }
        if health.isAvailable { health.requestAuthorization() }

        // Keep the screen awake so the app stays active even without the mic keep-alive.
        UIApplication.shared.isIdleTimerDisabled = true

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        uiTimer = timer
    }

    private func endCapture() {
        feeder.stop()
        sound.stop()
        uiTimer?.invalidate(); uiTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Internals

    private func handleSample(_ magnitude: Double, _ timestamp: TimeInterval) {
        latestMagnitude = magnitude
        guard let aggregator, let start = startDate else { return }
        let finalized = aggregator.ingest(magnitude: magnitude, at: timestamp)
        guard !finalized.isEmpty else { return }
        for epoch in finalized {
            appendEpoch(index: epoch.index, activity: epoch.activity, sessionStart: start)
        }
        liveState = classify(rawEpochs.map { $0.activity }).last ?? .awake
        checkpoint()   // persist progress every epoch (~once a minute)
    }

    private func appendEpoch(index: Int, activity: Double, sessionStart: Date) {
        rawEpochs.append(RawEpoch(index: index, activity: activity,
                                  start: sessionStart.addingTimeInterval(Double(index) * epochLength)))
    }

    private func checkpoint() {
        guard isTracking, let start = startDate else { return }
        store.saveActive(ActiveSleepSession(id: sessionID, start: start, epochLength: epochLength,
                                            micEnabled: micEnabled, epochs: rawEpochs,
                                            soundEvents: soundEvents))
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
        return SleepSession(id: sessionID, start: start, end: end, epochLength: epochLength,
                            epochs: epochs, soundEvents: soundEvents, metrics: metrics)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60
        return "\(h)h \(m)m"
    }
}
