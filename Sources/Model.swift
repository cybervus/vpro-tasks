import Foundation
import UserNotifications

struct Client: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var phone = ""
    var address = ""
    var note = ""
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var clientID: UUID? = nil
    var title = ""
    var details = ""
    var hasDate = true
    var date = Date()
    var hasTime = false
    var urgent = false
    var done = false
    var remindMinutes = 15   // -1 = не напоминать
}

private struct Snapshot: Codable {
    var clients: [Client]
    var tasks: [TaskItem]
}

final class Store: ObservableObject {
    @Published var clients: [Client] = [] { didSet { changed() } }
    @Published var tasks: [TaskItem] = [] { didSet { changed() } }

    private var loading = true
    private let notifDelegate = NotifDelegate()
    private let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("data.json")

    init() {
        load()
        loading = false
        let center = UNUserNotificationCenter.current()
        center.delegate = notifDelegate
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        reschedule()
    }

    // MARK: данные
    func client(_ id: UUID?) -> Client? { clients.first { $0.id == id } }

    func upsert(client c: Client) {
        if let i = clients.firstIndex(where: { $0.id == c.id }) { clients[i] = c } else { clients.append(c) }
    }
    func upsert(task t: TaskItem) {
        if let i = tasks.firstIndex(where: { $0.id == t.id }) { tasks[i] = t } else { tasks.append(t) }
    }
    func delete(client c: Client) {
        tasks.removeAll { $0.clientID == c.id }
        clients.removeAll { $0.id == c.id }
    }
    func delete(task t: TaskItem) { tasks.removeAll { $0.id == t.id } }
    func toggle(_ t: TaskItem) {
        if let i = tasks.firstIndex(where: { $0.id == t.id }) { tasks[i].done.toggle() }
    }

    // MARK: сохранение
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        clients = s.clients
        tasks = s.tasks
    }

    private func changed() {
        guard !loading else { return }
        if let data = try? JSONEncoder().encode(Snapshot(clients: clients, tasks: tasks)) {
            try? data.write(to: fileURL, options: .atomic)
        }
        reschedule()
    }

    // MARK: напоминания
    private func fireDate(_ t: TaskItem) -> Date? {
        if t.hasTime { return t.date.addingTimeInterval(-Double(t.remindMinutes) * 60) }
        return Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: t.date)
    }

    private func body(_ t: TaskItem) -> String {
        var parts: [String] = []
        if let c = client(t.clientID) {
            parts.append(c.name)
            if !c.address.isEmpty { parts.append(c.address) }
        }
        if !t.details.isEmpty { parts.append(t.details) }
        return parts.joined(separator: "\n")
    }

    private func reschedule() {
        guard !loading else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        var items: [(TaskItem, Date)] = []
        for t in tasks where !t.done && t.hasDate && t.remindMinutes >= 0 {
            if let f = fireDate(t), f > now { items.append((t, f)) }
        }
        items.sort { $0.1 < $1.1 }
        for (t, fire) in items.prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = t.title
            content.body = body(t)
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: t.id.uuidString, content: content, trigger: trigger))
        }
    }
}
