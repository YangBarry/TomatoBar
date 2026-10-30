import KeyboardShortcuts
import SwiftState
import SwiftUI

class TBTimer: ObservableObject {
    @AppStorage("overtimeEnabled") var overtimeEnabled = true
    @AppStorage("stopOnScreenLock") var stopOnScreenLock = true
    @AppStorage("stopAfterBreak") var stopAfterBreak = true
    @AppStorage("showTimerInMenuBar") var showTimerInMenuBar = true
    @AppStorage("workIntervalLength") var workIntervalLength = 30
    @AppStorage("shortRestIntervalLength") var shortRestIntervalLength = 5
    @AppStorage("longRestIntervalLength") var longRestIntervalLength = 15
    @AppStorage("workIntervalsInSet") var workIntervalsInSet = 4
    @AppStorage("overrunTimeLimit") var overrunTimeLimit = -60.0

    private var stateMachine = TBStateMachine(state: .idle)
    public let player = TBPlayer()
    private var consecutiveWorkIntervals: Int = 0
    private var notificationCenter = TBNotificationCenter()
    private var finishTime: Date!
    private var sessionStartTime: Date?
    private var currentPlannedSeconds: Int = 0
    private var timerFormatter = DateComponentsFormatter()

    @Published var currentState: TBStateMachineStates = .idle
    @Published var isOvertime: Bool = false
    @Published var timeLeftString: String = ""
    @Published var currentElapsedSeconds: Int = 0
    @Published var timer: DispatchSourceTimer?

    init() {
        stateMachine.addRoutes(event: .startStop, transitions: [
            .idle => .work, .work => .idle, .rest => .idle,
        ])
        stateMachine.addRoutes(event: .startRest, transitions: [
            .work => .rest,
        ])
        stateMachine.addRoutes(event: .timerFired, transitions: [.work => .rest])
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .idle]) { _ in
            self.stopAfterBreak
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .work]) { _ in
            !self.stopAfterBreak
        }
        stateMachine.addRoutes(event: .skipRest, transitions: [.rest => .work])
        stateMachine.addRoutes(event: .screenLocked, transitions: [.work => .idle])

        stateMachine.addAnyHandler(.any => .work, handler: onWorkStart)
        stateMachine.addAnyHandler(.work => .rest, order: 0, handler: onWorkFinish)
        stateMachine.addAnyHandler(.work => .any, order: 1, handler: onWorkEnd)
        stateMachine.addAnyHandler(.any => .rest, handler: onRestStart)
        stateMachine.addAnyHandler(.rest => .any, order: 0, handler: onRestFinish)
        stateMachine.addAnyHandler(.rest => .any, order: 1, handler: onRestEnd)
        stateMachine.addAnyHandler(.any => .idle, handler: onIdleStart)
        stateMachine.addAnyHandler(.any => .any, handler: { ctx in
            logger.append(event: TBLogEventTransition(fromContext: ctx))
        })

        stateMachine.addErrorHandler { ctx in
            print("state machine warning: <\(ctx)>")
        }

        timerFormatter.unitsStyle = .positional
        timerFormatter.allowedUnits = [.minute, .second]
        timerFormatter.zeroFormattingBehavior = .pad

        KeyboardShortcuts.onKeyUp(for: .startStopTimer, action: primaryAction)
        notificationCenter.setActionHandler(handler: onNotificationAction)

        let aem: NSAppleEventManager = NSAppleEventManager.shared()
        aem.setEventHandler(self,
                            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
                            forEventClass: AEEventClass(kInternetEventClass),
                            andEventID: AEEventID(kAEGetURL))

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleScreenLocked(_:)),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreenLocked(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }

    @objc private func handleScreenLocked(_: Notification) {
        DispatchQueue.main.async { [self] in
            guard stopOnScreenLock, stateMachine.state == .work else { return }
            stateMachine <-! .screenLocked
        }
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                 withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.forKeyword(AEKeyword(keyDirectObject))?.stringValue else {
            return
        }
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              let host = url.host,
              scheme.caseInsensitiveCompare("tomatobar") == .orderedSame else {
            return
        }
        switch host.lowercased() {
        case "startstop":
            primaryAction()
        case "startrest":
            startRest()
        case "stop":
            stopToIdle()
        default:
            return
        }
    }

    /// Primary button / hotkey action:
    /// - idle -> start work
    /// - work -> finish work and start break (rest)
    /// - rest -> stop or skip rest
    func primaryAction() {
        switch stateMachine.state {
        case .idle:
            stateMachine <-! .startStop
        case .work:
            stateMachine <-! .startRest
        case .rest:
            stateMachine <-! .startStop
        }
    }

    func startStop() {
        stateMachine <-! .startStop
    }

    func startRest() {
        if stateMachine.state == .work {
            stateMachine <-! .startRest
        }
    }

    func stopToIdle() {
        if stateMachine.state != .idle {
            stateMachine <-! .startStop
        }
    }

    func skipRest() {
        if stateMachine.state == .rest {
            stateMachine <-! .skipRest
        }
    }

    private func formatSeconds(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    func updateTimeLeft() {
        guard finishTime != nil else {
            TBStatusItem.shared?.setTitle(title: nil)
            return
        }

        let now = Date()
        if let start = sessionStartTime {
            currentElapsedSeconds = max(0, Int(now.timeIntervalSince(start).rounded()))
        }

        let rawTimeLeft = finishTime.timeIntervalSince(now)
        if rawTimeLeft >= 0 {
            let secsLeft = Int(ceil(rawTimeLeft))
            timeLeftString = formatSeconds(secsLeft)
        } else {
            let overtimeSecs = Int( abs(rawTimeLeft).rounded() )
            timeLeftString = "+" + formatSeconds(overtimeSecs)
        }

        if timer != nil, showTimerInMenuBar {
            TBStatusItem.shared?.setTitle(title: timeLeftString)
        } else {
            TBStatusItem.shared?.setTitle(title: nil)
        }
    }

    private func startTimer(seconds: Int) {
        if timer != nil {
            stopTimer()
        }
        finishTime = Date().addingTimeInterval(TimeInterval(seconds))

        let queue = DispatchQueue(label: "Timer")
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer!.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        timer!.setEventHandler(handler: onTimerTick)
        timer!.setCancelHandler(handler: onTimerCancel)
        timer!.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func onTimerTick() {
        DispatchQueue.main.async { [self] in
            guard timer != nil, finishTime != nil else { return }
            updateTimeLeft()
            let timeLeft = finishTime.timeIntervalSince(Date())
            if timeLeft <= 0 {
                if stateMachine.state == .work && overtimeEnabled {
                    if !isOvertime {
                        isOvertime = true
                        player.playDing()
                        notificationCenter.send(
                            title: String(format: NSLocalizedString("TBTimer.onOvertimeStart.title", value: "已完成 %d 分钟专注目标", comment: "Overtime started title"), workIntervalLength),
                            body: NSLocalizedString("TBTimer.onOvertimeStart.body", value: "已自动继续正向计时，随时点击「开始休息」进入休息。", comment: "Overtime started body"),
                            category: .overtimeStarted
                        )
                    }
                    // Continue counting up in overtime until user manually clicks Start Break or Stop
                } else {
                    if timeLeft < overrunTimeLimit {
                        stateMachine <-! .startStop
                    } else {
                        stateMachine <-! .timerFired
                    }
                }
            }
        }
    }

    private func onTimerCancel() {
        DispatchQueue.main.async { [self] in
            updateTimeLeft()
        }
    }

    private func onNotificationAction(action: TBNotification.Action) {
        switch action {
        case .skipRest:
            if stateMachine.state == .rest {
                skipRest()
            }
        case .startRest:
            if stateMachine.state == .work {
                startRest()
            }
        }
    }

    private func onWorkStart(context _: TBStateMachine.Context) {
        currentState = .work
        isOvertime = false
        sessionStartTime = Date()
        currentPlannedSeconds = workIntervalLength * 60
        currentElapsedSeconds = 0
        TBStatusItem.shared?.setIcon(name: .work)
        player.playWindup()
        player.startTicking()
        startTimer(seconds: currentPlannedSeconds)
    }

    private func onWorkFinish(context _: TBStateMachine.Context) {
        consecutiveWorkIntervals += 1
        if !isOvertime {
            player.playDing()
        }
    }

    private func onWorkEnd(context ctx: TBStateMachine.Context) {
        player.stopTicking()
        if let start = sessionStartTime {
            let endTime = Date()
            let actualSeconds = max(1, Int(endTime.timeIntervalSince(start).rounded()))
            let reachedTarget = isOvertime || actualSeconds >= currentPlannedSeconds
            let reason: String
            if ctx.toState == .rest {
                reason = ctx.event == .timerFired ? "timer_finished" : "start_rest"
            } else if ctx.event == .screenLocked {
                reason = reachedTarget ? "screen_locked" : "aborted_screen_lock"
            } else {
                reason = reachedTarget ? "stopped" : "aborted_manual_stop"
            }
            logger.recordSession(
                type: "work",
                startTime: start,
                endTime: endTime,
                plannedSeconds: currentPlannedSeconds,
                audioMode: player.audioMode.rawValue,
                endReason: reason
            )
            if reason == "aborted_screen_lock" && actualSeconds >= 5 {
                let elapsedDisplay = logger.formattedDuration(seconds: actualSeconds)
                notificationCenter.send(
                    title: NSLocalizedString("TBTimer.onWorkAborted.title", value: "专注中断 · 时间已作废", comment: "Work aborted title"),
                    body: String(
                        format: NSLocalizedString("TBTimer.onWorkAborted.body", value: "检测到锁屏离开，本次已进行的 %@ 专注已作废并记入中断记录。", comment: "Work aborted body"),
                        elapsedDisplay
                    ),
                    category: .workAborted
                )
            }
        }
        isOvertime = false
        sessionStartTime = nil
        currentElapsedSeconds = 0
    }

    private func onRestStart(context _: TBStateMachine.Context) {
        currentState = .rest
        isOvertime = false
        var body = NSLocalizedString("TBTimer.onRestStart.short.body", comment: "Short break body")
        var length = shortRestIntervalLength
        var imgName = NSImage.Name.shortRest
        if consecutiveWorkIntervals >= workIntervalsInSet {
            body = NSLocalizedString("TBTimer.onRestStart.long.body", comment: "Long break body")
            length = longRestIntervalLength
            imgName = .longRest
            consecutiveWorkIntervals = 0
        }
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestStart.title", comment: "Time's up title"),
            body: body,
            category: .restStarted
        )
        TBStatusItem.shared?.setIcon(name: imgName)
        sessionStartTime = Date()
        currentPlannedSeconds = length * 60
        currentElapsedSeconds = 0
        startTimer(seconds: currentPlannedSeconds)
    }

    private func onRestFinish(context ctx: TBStateMachine.Context) {
        guard ctx.event == .timerFired else {
            return
        }
        player.playDing()
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestFinish.title", comment: "Break is over title"),
            body: NSLocalizedString("TBTimer.onRestFinish.body", comment: "Break is over body"),
            category: .restFinished
        )
    }

    private func onRestEnd(context ctx: TBStateMachine.Context) {
        if let start = sessionStartTime {
            let reason: String
            if ctx.event == .skipRest {
                reason = "rest_skipped"
            } else if ctx.event == .timerFired {
                reason = "timer_finished"
            } else {
                reason = "stopped"
            }
            logger.recordSession(
                type: "rest",
                startTime: start,
                endTime: Date(),
                plannedSeconds: currentPlannedSeconds,
                audioMode: "none",
                endReason: reason
            )
        }
        sessionStartTime = nil
        currentElapsedSeconds = 0
    }

    private func onIdleStart(context _: TBStateMachine.Context) {
        currentState = .idle
        isOvertime = false
        sessionStartTime = nil
        currentElapsedSeconds = 0
        stopTimer()
        TBStatusItem.shared?.setIcon(name: .idle)
        consecutiveWorkIntervals = 0
    }
}
