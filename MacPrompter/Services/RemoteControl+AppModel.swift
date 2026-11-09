import Foundation

/// The only place where remote commands touch app state. Every movement goes
/// through `PrompterSession`, so `PlaybackGate` (hover, pause, countdown) keeps
/// priority over the iPhone exactly as over keys and the scroll wheel.
@MainActor
struct RemoteBridge {
    let session: PrompterSession
    let preferences: PreferenceStore
    let library: ScriptLibrary
    // The audience window belongs to AppModel's PresentationController.
    var isPresenting: () -> Bool = { false }
    var setPresenting: (Bool) -> Void = { _ in }

    /// nil while the session's script has no PDF; the iPhone then disables its slide controls.
    func slides() -> RemoteSlides? {
        session.slideStatus.map { RemoteSlides(current: $0.current, count: $0.count, isPresenting: isPresenting(),
            slide: $0.slide, slideCount: $0.slideCount, step: $0.step, steps: $0.steps) }
    }

    func status() -> RemoteStatus {
        let gate = session.gate
        let visible = gate.isVisible
        let script = visible ? session.script : library.selected
        return RemoteStatus(scriptID: script?.id, scriptTitle: script?.title ?? "", state: session.stateLabel,
            isVisible: visible, isPlaying: gate.isPlaying, isHovering: gate.isHovering, isPreparing: session.isPreparing,
            countdown: gate.countdown, mode: RemoteMode(rawValue: preferences.value.mode.rawValue) ?? .automatic,
            speed: preferences.value.speed, progress: (session.progress * 1000).rounded() / 1000,
            elapsedSeconds: session.elapsedSeconds, slides: slides())
    }

    func scripts() -> [RemoteScriptSummary] {
        library.scripts.map { RemoteScriptSummary(id: $0.id, title: $0.title) }
    }

    func perform(_ command: RemoteCommand) {
        switch command {
        case .start:
            if !session.gate.isVisible {
                guard let script = library.selected, !ScriptParser.words(in: script.body).isEmpty else { return }
                session.present(script)
            }
            if !session.gate.isPlaying && !session.isPreparing { session.togglePlayback() }
        case .pause:
            if session.gate.isPlaying || session.isPreparing { session.pause() }
        case .hide:
            session.hide()
        case .setSpeed(let speed):
            guard speed.isFinite else { return }
            preferences.value.speed = min(RemoteProtocol.speedRange.upperBound, max(RemoteProtocol.speedRange.lowerBound, speed.rounded()))
        case .setMode(let mode):
            if let mode = PlaybackMode(rawValue: mode.rawValue), preferences.value.mode != mode { preferences.value.mode = mode }
        case .nudge(let points):
            guard points.isFinite else { return }
            session.nudge(min(RemoteProtocol.nudgeLimit, max(-RemoteProtocol.nudgeLimit, points)))
        case .selectScript(let id):
            guard let script = library.scripts.first(where: { $0.id == id }) else { return }
            library.selectedID = id
            if session.gate.isVisible, session.script.id != id { session.pause(); session.present(script) }
        case .stepSlide(let delta):
            // Same path as the arrow keys: the slide changes, the text only jumps when the gate allows it.
            guard delta != 0 else { return }
            session.stepSlide(delta > 0 ? 1 : -1)
        case .startPresentation:
            if slides() != nil { setPresenting(true) }
        case .endPresentation:
            if slides() != nil { setPresenting(false) }
        }
    }
}

extension AppModel {
    var remoteBridge: RemoteBridge {
        var bridge = RemoteBridge(session: session, preferences: preferences, library: library)
        bridge.isPresenting = { [weak self] in self?.isPresenting ?? false }
        bridge.setPresenting = { [weak self] start in start ? self?.startPresentation() : self?.endPresentation() }
        return bridge
    }

    func setupRemoteControl() {
        remote.bridge = remoteBridge
        remote.setEnabled(preferences.value.remoteControlEnabled)
        #if DEBUG
        // Manual end-to-end runs only (docs/REMOTE.md): listen without touching
        // preferences and print the code, since agents cannot read the screen.
        if UserDefaults.standard.bool(forKey: "RemoteDebugPairing") {
            remote.setEnabled(true)
            remote.beginPairing()
            if let code = remote.pairing?.code { FileHandle.standardError.write(Data("REMOTE_PAIRING_CODE \(code)\n".utf8)) }
        }
        #endif
    }
}
