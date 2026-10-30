import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

extension KeyboardShortcuts.Name {
    static let startStopTimer = Self("startStopTimer")
}

private struct VolumeSlider: View {
    @Binding var volume: Double
    var maxVolume: Double = 1.5

    var body: some View {
        Slider(value: $volume, in: 0...maxVolume) {
            Text(String(format: "%.1f", volume))
        }.gesture(TapGesture(count: 2).onEnded({
            volume = 0.7
        }))
    }
}

private struct IntervalsView: View {
    @EnvironmentObject var timer: TBTimer
    @EnvironmentObject var player: TBPlayer
    private let minStr = NSLocalizedString("IntervalsView.min", comment: "min")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $timer.workIntervalLength, in: 1 ... 120) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.workIntervalLength.label",
                                           comment: "Work interval label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(minStr, timer.workIntervalLength))
                        .monospacedDigit()
                }
            }
            Stepper(value: $timer.shortRestIntervalLength, in: 1 ... 60) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.shortRestIntervalLength.label",
                                           comment: "Short rest interval label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(minStr, timer.shortRestIntervalLength))
                        .monospacedDigit()
                }
            }
            Stepper(value: $timer.longRestIntervalLength, in: 1 ... 60) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.longRestIntervalLength.label",
                                           comment: "Long rest interval label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(minStr, timer.longRestIntervalLength))
                        .monospacedDigit()
                }
            }
            .help(NSLocalizedString("IntervalsView.longRestIntervalLength.help",
                                    comment: "Long rest interval hint"))
            Stepper(value: $timer.workIntervalsInSet, in: 1 ... 10) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.workIntervalsInSet.label",
                                           comment: "Work intervals in a set label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(timer.workIntervalsInSet)")
                        .monospacedDigit()
                }
            }
            .help(NSLocalizedString("IntervalsView.workIntervalsInSet.help",
                                    comment: "Work intervals in set hint"))

            Divider().padding(.vertical, 2)

            HStack {
                Text("背景音:")
                Picker("", selection: $player.audioModeRaw) {
                    Text("Brown Noise").tag(BackgroundAudioMode.brownNoise.rawValue)
                    Text("Lofi Radio").tag(BackgroundAudioMode.lofiRadio.rawValue)
                    Text("无").tag(BackgroundAudioMode.none.rawValue)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if player.audioMode != .none {
                HStack(spacing: 6) {
                    Text("音量:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    VolumeSlider(volume: $player.musicVolume, maxVolume: 1.5)
                    if player.audioMode == .brownNoise {
                        Button(player.customBrownNoisePath.isEmpty ? "换文件..." : "默认") {
                            if player.customBrownNoisePath.isEmpty {
                                player.chooseCustomBrownNoiseFile()
                            } else {
                                player.resetToDefaultBrownNoise()
                            }
                        }
                        .controlSize(.mini)
                        .help(player.customBrownNoisePath.isEmpty ? "选择本地自定义音频" : "恢复内置 Academic Brown Noise")
                    } else if player.audioMode == .lofiRadio {
                        Button("下一首") {
                            player.nextLofiTrack()
                        }
                        .controlSize(.mini)
                        .help("切换下一首")
                        if player.lofiSource == .appleMusic {
                            Button("打开歌单") {
                                player.openAppleMusicLofiPlaylist()
                            }
                            .controlSize(.mini)
                            .help("在 Apple Music 中打开 Lofi Girl 官方歌单")
                        } else {
                            Button("目录") {
                                player.revealLofiFolderInFinder()
                            }
                            .controlSize(.mini)
                            .help("打开 ~/.tomatobar/lofi 文件夹添加或管理离线曲目")
                        }
                    }
                }
                if player.audioMode == .lofiRadio {
                    HStack(spacing: 6) {
                        Text("Lofi源:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Picker("", selection: $player.lofiSourceRaw) {
                            Text("Apple Music").tag(LofiSourceMode.appleMusic.rawValue)
                            Text("本地离线 (54m)").tag(LofiSourceMode.offline.rawValue)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.mini)
                    }
                }
            }

            Spacer().frame(minHeight: 0)
        }
        .padding(4)
    }
}

private struct SettingsView: View {
    @EnvironmentObject var timer: TBTimer
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            KeyboardShortcuts.Recorder(for: .startStopTimer) {
                Text(NSLocalizedString("SettingsView.shortcut.label",
                                       comment: "Shortcut label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle(isOn: $timer.overtimeEnabled) {
                Text(NSLocalizedString("SettingsView.overtimeEnabled.label",
                                       value: "到点继续计时（手动进休息）",
                                       comment: "Overtime mode label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Toggle(isOn: $timer.stopOnScreenLock) {
                Text(NSLocalizedString("SettingsView.stopOnScreenLock.label",
                                       value: "锁屏离开时中断专注（未达标作废）",
                                       comment: "Stop on screen lock label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Toggle(isOn: $timer.stopAfterBreak) {
                Text(NSLocalizedString("SettingsView.stopAfterBreak.label",
                                       comment: "Stop after break label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Toggle(isOn: $timer.showTimerInMenuBar) {
                Text(NSLocalizedString("SettingsView.showTimerInMenuBar.label",
                                       comment: "Show timer in menu bar label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
                .onChange(of: timer.showTimerInMenuBar) { _ in
                    timer.updateTimeLeft()
                }
            Toggle(isOn: $launchAtLogin.isEnabled) {
                Text(NSLocalizedString("SettingsView.launchAtLogin.label",
                                       comment: "Launch at login label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Spacer().frame(minHeight: 0)
        }
        .padding(4)
    }
}

private struct StatsView: View {
    @EnvironmentObject var timer: TBTimer
    @ObservedObject var log = logger
    @State private var copiedToast = false

    private var liveTodayWorkSeconds: Int {
        log.todayWorkSeconds + (timer.currentState == .work ? timer.currentElapsedSeconds : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日累计专注")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(log.formattedDuration(seconds: liveTodayWorkSeconds))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("完成 / 超时 / 作废")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(log.todayWorkCount)次 · +\(log.formattedDuration(seconds: log.todayOvertimeSeconds)) · 断\(log.todayAbortedCount)次")
                        .font(.caption)
                        .monospacedDigit()
                }
            }
            .padding(.bottom, 2)

            Divider()

            Text("最近 7 天专注记录")
                .font(.caption2)
                .foregroundColor(.secondary)

            if log.recentDailySummaries.isEmpty {
                Text("暂无已完成记录，完成一次专注后将自动保存。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 3) {
                    ForEach(log.recentDailySummaries.prefix(5)) { day in
                        HStack {
                            Text(day.date)
                                .font(.caption2)
                                .monospacedDigit()
                            Spacer()
                            if day.abortedWorkSessions > 0 {
                                Text("断\(day.abortedWorkSessions)")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            Text("\(day.workSessions) 次")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(log.formattedDuration(seconds: day.totalWorkSeconds))
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            }

            Spacer().frame(minHeight: 0)
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("数据路径: ~/.tomatobar/sessions.jsonl & .csv")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Button(copiedToast ? "已复制路径 ✓" : "复制路径 (给 Codex)") {
                        log.copyDataPathToClipboard()
                        copiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedToast = false
                        }
                    }
                    .controlSize(.small)

                    Button("打开数据目录") {
                        log.revealDataFolderInFinder()
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(4)
    }
}

private enum ChildView {
    case intervals, stats, settings
}

struct TBPopoverView: View {
    @ObservedObject var timer = TBTimer()
    @ObservedObject var log = logger
    @State private var buttonHovered = false
    @State private var activeChildView = ChildView.intervals

    private var startLabel = NSLocalizedString("TBPopoverView.start.label", comment: "Start label")
    private var stopLabel = NSLocalizedString("TBPopoverView.stop.label", comment: "Stop label")
    private var startRestLabel = NSLocalizedString("TBPopoverView.startRest.label", value: "开始休息", comment: "Start rest label")
    private var skipRestLabel = NSLocalizedString("TBPopoverView.skipRest.label", value: "开始专注", comment: "Skip rest label")

    private var liveTodayWorkSeconds: Int {
        log.todayWorkSeconds + (timer.currentState == .work ? timer.currentElapsedSeconds : 0)
    }

    private var primaryButtonTitle: String {
        switch timer.currentState {
        case .idle:
            return startLabel
        case .work:
            if buttonHovered {
                return startRestLabel
            }
            return timer.isOvertime ? "超时 \(timer.timeLeftString) · 点击休息" : timer.timeLeftString
        case .rest:
            if buttonHovered {
                return skipRestLabel
            }
            return "休息 \(timer.timeLeftString)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    switch timer.currentState {
                    case .idle:
                        timer.startStop()
                        TBStatusItem.shared?.closePopover(nil)
                    case .work:
                        timer.startRest()
                    case .rest:
                        timer.skipRest()
                        TBStatusItem.shared?.closePopover(nil)
                    }
                } label: {
                    Text(primaryButtonTitle)
                        .foregroundColor(Color.white)
                        .font(.system(.body).monospacedDigit())
                        .frame(maxWidth: .infinity)
                }
                .onHover { over in
                    buttonHovered = over
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                if timer.currentState != .idle {
                    Button {
                        timer.stopToIdle()
                    } label: {
                        Text(stopLabel)
                            .font(.system(.callout))
                    }
                    .controlSize(.large)
                    .help("停止并回到待机状态")
                }
            }

            HStack {
                Text("今日专注: \(log.formattedDuration(seconds: liveTodayWorkSeconds)) (\(log.todayWorkCount)次\(log.todayAbortedCount > 0 ? " · 断\(log.todayAbortedCount)" : ""))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(timer.player.audioMode.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
            }

            Picker("", selection: $activeChildView) {
                Text(NSLocalizedString("TBPopoverView.intervals.label",
                                       comment: "Intervals label")).tag(ChildView.intervals)
                Text(NSLocalizedString("TBPopoverView.stats.label",
                                       value: "统计",
                                       comment: "Stats label")).tag(ChildView.stats)
                Text(NSLocalizedString("TBPopoverView.settings.label",
                                       comment: "Settings label")).tag(ChildView.settings)
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .pickerStyle(.segmented)

            GroupBox {
                switch activeChildView {
                case .intervals:
                    IntervalsView()
                        .environmentObject(timer)
                        .environmentObject(timer.player)
                case .stats:
                    StatsView().environmentObject(timer)
                case .settings:
                    SettingsView().environmentObject(timer)
                }
            }
            .frame(height: 214)

            Group {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel()
                } label: {
                    Text(NSLocalizedString("TBPopoverView.about.label",
                                           comment: "About label"))
                    Spacer()
                    Text("⌘ A").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("a")
                Button {
                    NSApplication.shared.terminate(self)
                } label: {
                    Text(NSLocalizedString("TBPopoverView.quit.label",
                                           comment: "Quit label"))
                    Spacer()
                    Text("⌘ Q").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
        }
        .frame(width: 268)
        .padding(12)
    }
}
