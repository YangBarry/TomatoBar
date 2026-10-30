import AppKit
import Foundation
import SwiftUI

protocol TBLogEvent: Encodable {
    var type: String { get }
    var timestamp: Date { get }
}

class TBLogEventAppStart: TBLogEvent {
    internal let type = "appstart"
    internal let timestamp: Date = Date()
}

class TBLogEventTransition: TBLogEvent {
    internal let type = "transition"
    internal let timestamp: Date = Date()

    private let event: String
    private let fromState: String
    private let toState: String

    init(fromContext ctx: TBStateMachine.Context) {
        event = "\(ctx.event!)"
        fromState = "\(ctx.fromState)"
        toState = "\(ctx.toState)"
    }
}

struct TBSessionRecord: Codable, Identifiable {
    let id: String
    let date: String              // YYYY-MM-DD (local timezone)
    let type: String              // "work" or "rest"
    let startTime: String         // ISO-8601 with local timezone offset
    let endTime: String           // ISO-8601 with local timezone offset
    let plannedSeconds: Int
    let actualSeconds: Int
    let overtimeSeconds: Int
    let actualMinutes: Double
    let completedTarget: Bool
    let audioMode: String
    let endReason: String         // "start_rest", "stopped", "screen_locked", "timer_finished", "rest_skipped", "aborted_screen_lock", "aborted_manual_stop"

    var isAbortedWork: Bool {
        type == "work" && (endReason.hasPrefix("aborted_") || (endReason == "stopped" && !completedTarget))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case type
        case startTime = "start_time"
        case endTime = "end_time"
        case plannedSeconds = "planned_seconds"
        case actualSeconds = "actual_seconds"
        case overtimeSeconds = "overtime_seconds"
        case actualMinutes = "actual_minutes"
        case completedTarget = "completed_target"
        case audioMode = "audio_mode"
        case endReason = "end_reason"
    }
}

struct TBDailySummary: Codable, Identifiable {
    var id: String { date }
    let date: String
    var workSessions: Int
    var completedTargetSessions: Int
    var totalWorkSeconds: Int
    var totalWorkMinutes: Double
    var totalOvertimeSeconds: Int
    var totalRestSeconds: Int
    var abortedWorkSessions: Int
    var abortedWorkSeconds: Int
    var screenLockAborts: Int
    var manualStopAborts: Int

    enum CodingKeys: String, CodingKey {
        case date
        case workSessions = "work_sessions"
        case completedTargetSessions = "completed_target_sessions"
        case totalWorkSeconds = "total_work_seconds"
        case totalWorkMinutes = "total_work_minutes"
        case totalOvertimeSeconds = "total_overtime_seconds"
        case totalRestSeconds = "total_rest_seconds"
        case abortedWorkSessions = "aborted_work_sessions"
        case abortedWorkSeconds = "aborted_work_seconds"
        case screenLockAborts = "screen_lock_aborts"
        case manualStopAborts = "manual_stop_aborts"
    }
}

private let lineEnd = "\n".data(using: .utf8)!

internal let logger = TBLogger()

class TBLogger: ObservableObject {
    public let dataDirectoryURL: URL
    public let sessionsJSONLURL: URL
    public let sessionsCSVURL: URL
    public let dailySummaryJSONURL: URL
    public let eventsJSONLURL: URL

    private let encoder = JSONEncoder()
    private let prettyEncoder = JSONEncoder()
    private let isoFormatter = ISO8601DateFormatter()
    private let dateFormatter = DateFormatter()

    @Published var allSessions: [TBSessionRecord] = []
    @Published var todayWorkSeconds: Int = 0
    @Published var todayOvertimeSeconds: Int = 0
    @Published var todayWorkCount: Int = 0
    @Published var todayAbortedCount: Int = 0
    @Published var todayAbortedSeconds: Int = 0
    @Published var todayRestSeconds: Int = 0
    @Published var recentDailySummaries: [TBDailySummary] = []

    init() {
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        isoFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        isoFormatter.timeZone = TimeZone.current

        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current

        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        dataDirectoryURL = homeDir.appendingPathComponent(".tomatobar", isDirectory: true)
        sessionsJSONLURL = dataDirectoryURL.appendingPathComponent("sessions.jsonl")
        sessionsCSVURL = dataDirectoryURL.appendingPathComponent("sessions.csv")
        dailySummaryJSONURL = dataDirectoryURL.appendingPathComponent("daily_summary.json")
        eventsJSONLURL = dataDirectoryURL.appendingPathComponent("events.jsonl")

        ensureDataDirectoryAndFiles()
        loadExistingSessions()
    }

    private func ensureDataDirectoryAndFiles() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dataDirectoryURL.path) {
            try? fm.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: sessionsJSONLURL.path) {
            fm.createFile(atPath: sessionsJSONLURL.path, contents: nil)
        }
        if !fm.fileExists(atPath: eventsJSONLURL.path) {
            fm.createFile(atPath: eventsJSONLURL.path, contents: nil)
        }
        if !fm.fileExists(atPath: sessionsCSVURL.path) {
            let csvHeader = "id,date,type,start_time,end_time,planned_seconds,actual_seconds,overtime_seconds,actual_minutes,completed_target,audio_mode,end_reason\n"
            try? csvHeader.write(to: sessionsCSVURL, atomically: true, encoding: .utf8)
        }
    }

    func todayDateString(for date: Date = Date()) -> String {
        return dateFormatter.string(from: date)
    }

    func formatISO(_ date: Date) -> String {
        return isoFormatter.string(from: date)
    }

    func append(event: TBLogEvent) {
        ensureDataDirectoryAndFiles()
        do {
            let jsonData = try encoder.encode(event)
            if let handle = try? FileHandle(forWritingTo: eventsJSONLURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: jsonData + lineEnd)
            }
        } catch {
            print("cannot write event log: \(error)")
        }
    }

    func recordSession(
        type: String,
        startTime: Date,
        endTime: Date = Date(),
        plannedSeconds: Int,
        audioMode: String,
        endReason: String
    ) {
        let actualSeconds = max(1, Int(endTime.timeIntervalSince(startTime).rounded()))
        // Ignore accidental clicks shorter than 5 seconds
        if actualSeconds < 5 {
            return
        }

        let overtimeSeconds = type == "work" ? max(0, actualSeconds - plannedSeconds) : 0
        let completedTarget = actualSeconds >= plannedSeconds
        let actualMinutes = (Double(actualSeconds) / 60.0 * 100).rounded() / 100.0
        let dateStr = todayDateString(for: startTime)

        let record = TBSessionRecord(
            id: UUID().uuidString,
            date: dateStr,
            type: type,
            startTime: formatISO(startTime),
            endTime: formatISO(endTime),
            plannedSeconds: plannedSeconds,
            actualSeconds: actualSeconds,
            overtimeSeconds: overtimeSeconds,
            actualMinutes: actualMinutes,
            completedTarget: completedTarget,
            audioMode: audioMode,
            endReason: endReason
        )

        ensureDataDirectoryAndFiles()

        // 1. Append to sessions.jsonl
        if let jsonData = try? encoder.encode(record),
           let handle = try? FileHandle(forWritingTo: sessionsJSONLURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: jsonData + lineEnd)
        }

        // 2. Append to sessions.csv
        let csvLine = "\(record.id),\(record.date),\(record.type),\(record.startTime),\(record.endTime),\(record.plannedSeconds),\(record.actualSeconds),\(record.overtimeSeconds),\(String(format: "%.2f", record.actualMinutes)),\(record.completedTarget),\(record.audioMode),\(record.endReason)\n"
        if let csvData = csvLine.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: sessionsCSVURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: csvData)
        }

        DispatchQueue.main.async {
            self.allSessions.append(record)
            self.recomputeStats()
        }
    }

    func loadExistingSessions() {
        guard let content = try? String(contentsOf: sessionsJSONLURL, encoding: .utf8) else {
            return
        }
        let decoder = JSONDecoder()
        var loaded: [TBSessionRecord] = []
        for line in content.split(separator: "\n") {
            if let data = line.data(using: .utf8),
               let record = try? decoder.decode(TBSessionRecord.self, from: data) {
                loaded.append(record)
            }
        }
        allSessions = loaded
        recomputeStats()
    }

    func recomputeStats() {
        let today = todayDateString()
        var todayWork = 0
        var todayOvertime = 0
        var todayCount = 0
        var todayAborted = 0
        var todayAbortedSecs = 0
        var todayRest = 0

        var byDate: [String: TBDailySummary] = [:]

        for session in allSessions {
            var summary = byDate[session.date] ?? TBDailySummary(
                date: session.date,
                workSessions: 0,
                completedTargetSessions: 0,
                totalWorkSeconds: 0,
                totalWorkMinutes: 0,
                totalOvertimeSeconds: 0,
                totalRestSeconds: 0,
                abortedWorkSessions: 0,
                abortedWorkSeconds: 0,
                screenLockAborts: 0,
                manualStopAborts: 0
            )

            if session.type == "work" {
                if session.isAbortedWork {
                    summary.abortedWorkSessions += 1
                    summary.abortedWorkSeconds += session.actualSeconds
                    if session.endReason == "aborted_screen_lock" {
                        summary.screenLockAborts += 1
                    } else {
                        summary.manualStopAborts += 1
                    }

                    if session.date == today {
                        todayAborted += 1
                        todayAbortedSecs += session.actualSeconds
                    }
                } else {
                    summary.workSessions += 1
                    if session.completedTarget {
                        summary.completedTargetSessions += 1
                    }
                    summary.totalWorkSeconds += session.actualSeconds
                    summary.totalWorkMinutes = (Double(summary.totalWorkSeconds) / 60.0 * 100).rounded() / 100.0
                    summary.totalOvertimeSeconds += session.overtimeSeconds

                    if session.date == today {
                        todayWork += session.actualSeconds
                        todayOvertime += session.overtimeSeconds
                        todayCount += 1
                    }
                }
            } else if session.type == "rest" {
                summary.totalRestSeconds += session.actualSeconds
                if session.date == today {
                    todayRest += session.actualSeconds
                }
            }

            byDate[session.date] = summary
        }

        todayWorkSeconds = todayWork
        todayOvertimeSeconds = todayOvertime
        todayWorkCount = todayCount
        todayAbortedCount = todayAborted
        todayAbortedSeconds = todayAbortedSecs
        todayRestSeconds = todayRest

        let sortedSummaries = byDate.values.sorted { $0.date > $1.date }
        recentDailySummaries = Array(sortedSummaries.prefix(7))

        if let summaryData = try? prettyEncoder.encode(sortedSummaries) {
            try? summaryData.write(to: dailySummaryJSONURL, options: .atomic)
        }
    }

    func formattedDuration(seconds: Int) -> String {
        let totalMinutes = seconds / 60
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else if mins > 0 {
            return "\(mins)m"
        } else {
            return "\(seconds)s"
        }
    }

    func revealDataFolderInFinder() {
        ensureDataDirectoryAndFiles()
        NSWorkspace.shared.selectFile(sessionsJSONLURL.path, inFileViewerRootedAtPath: dataDirectoryURL.path)
    }

    func copyDataPathToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sessionsJSONLURL.path, forType: .string)
    }
}
