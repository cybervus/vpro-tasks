import SwiftUI
import UserNotifications

final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct FieldTasksApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
        }
    }
}
