import Foundation
import UserNotifications

enum TBNotification {
    enum Category: String {
        case restStarted, restFinished, overtimeStarted, workAborted
    }

    enum Action: String {
        case skipRest, startRest
    }
}

typealias TBNotificationHandler = (TBNotification.Action) -> Void

class TBNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter?
    private var handler: TBNotificationHandler?

    override init() {
        super.init()

        guard Bundle.main.bundleIdentifier != nil else {
            return
        }

        let notificationCenter = UNUserNotificationCenter.current()
        self.center = notificationCenter

        notificationCenter.requestAuthorization(
            options: [.alert, .sound]
        ) { _, error in
            if let error = error {
                print("Error requesting notification authorization: \(error)")
            }
        }

        notificationCenter.delegate = self

        let actionSkipRest = UNNotificationAction(
            identifier: TBNotification.Action.skipRest.rawValue,
            title: NSLocalizedString("TBTimer.onRestStart.skip.title", comment: "Skip"),
            options: []
        )
        let actionStartRest = UNNotificationAction(
            identifier: TBNotification.Action.startRest.rawValue,
            title: NSLocalizedString("TBPopoverView.startRest.label", value: "开始休息", comment: "Start Break"),
            options: []
        )

        let restStartedCategory = UNNotificationCategory(
            identifier: TBNotification.Category.restStarted.rawValue,
            actions: [actionSkipRest],
            intentIdentifiers: []
        )
        let restFinishedCategory = UNNotificationCategory(
            identifier: TBNotification.Category.restFinished.rawValue,
            actions: [],
            intentIdentifiers: []
        )
        let overtimeStartedCategory = UNNotificationCategory(
            identifier: TBNotification.Category.overtimeStarted.rawValue,
            actions: [actionStartRest],
            intentIdentifiers: []
        )
        let workAbortedCategory = UNNotificationCategory(
            identifier: TBNotification.Category.workAborted.rawValue,
            actions: [],
            intentIdentifiers: []
        )

        notificationCenter.setNotificationCategories([
            restStartedCategory,
            restFinishedCategory,
            overtimeStartedCategory,
            workAbortedCategory
        ])
    }

    func setActionHandler(handler: @escaping TBNotificationHandler) {
        self.handler = handler
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let handler = handler,
           let action = TBNotification.Action(rawValue: response.actionIdentifier) {
            DispatchQueue.main.async {
                handler(action)
            }
        }
        completionHandler()
    }

    func send(title: String, body: String, category: TBNotification.Category) {
        guard let center = center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error = error {
                print("Error adding notification: \(error)")
            }
        }
    }
}
