import SwiftUI

private let ruFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ru_RU")
    return f
}()

func fmt(_ d: Date, _ pattern: String) -> String {
    ruFormatter.dateFormat = pattern
    return ruFormatter.string(from: d)
}

func phoneURL(_ s: String) -> URL? {
    let d = s.filter { "+0123456789".contains($0) }
    return d.isEmpty ? nil : URL(string: "tel:" + d)
}

func mapURL(_ s: String) -> URL? {
    guard !s.isEmpty, let q = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
    return URL(string: "http://maps.apple.com/?q=" + q)
}

struct ContentView: View {
    var body: some View {
        TabView {
            TasksView().tabItem { Label("Задачи", systemImage: "checklist") }
            ClientsView().tabItem { Label("Клиенты", systemImage: "person.2") }
        }
        .environment(\.locale, Locale(identifier: "ru_RU"))
    }
}

// MARK: - Задачи

enum TaskFilter: String, CaseIterable, Identifiable {
    case today = "Сегодня", later = "Позже", all = "Все", done = "Готово"
    var id: String { rawValue }
}

struct TasksView: View {
    @EnvironmentObject var store: Store
    @State private var filter: TaskFilter = .today
    @State private var editing: TaskItem?

    private func passes(_ t: TaskItem) -> Bool {
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        switch filter {
        case .today: return !t.done && t.hasDate && t.date < endOfToday
        case .later: return !t.done && (!t.hasDate || t.date >= endOfToday)
        case .all: return !t.done
        case .done: return t.done
        }
    }

    private var visible: [TaskItem] {
        store.tasks.filter { passes($0) }.sorted { a, b in
            let da = a.hasDate ? a.date : Date.distantFuture
            let db = b.hasDate ? b.date : Date.distantFuture
            return da < db
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Фильтр", selection: $filter) {
                    ForEach(TaskFilter.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                List {
                    if visible.isEmpty {
                        Text("Здесь пока пусто").foregroundColor(.secondary)
                    }
                    ForEach(visible) { t in
                        TaskRow(task: t)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = t }
                    }
                    .onDelete { idx in
                        let items = idx.map { visible[$0] }
                        for t in items { store.delete(task: t) }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Задачи")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editing = TaskItem(clientID: store.clients.first?.id)
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { t in TaskForm(task: t) }
        }
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: Store
    let task: TaskItem

    private var subtitle: String {
        var parts: [String] = []
        if let c = store.client(task.clientID) { parts.append(c.name) }
        if task.hasDate { parts.append(fmt(task.date, task.hasTime ? "d MMM, HH:mm" : "d MMM")) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { store.toggle(task) } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(task.done ? .green : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text((task.urgent ? "❗ " : "") + task.title)
                    .strikethrough(task.done)
                    .font(.headline)
                Text(subtitle).font(.subheadline).foregroundColor(.secondary)
            }
        }
    }
}

struct TaskForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var task: TaskItem

    init(task: TaskItem) { _task = State(initialValue: task) }

    private var isNew: Bool { !store.tasks.contains { $0.id == task.id } }

    private func commit() {
        var t = task
        t.title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cal = Calendar.current
        if t.hasTime {
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: t.date)
            t.date = cal.date(from: c) ?? t.date
        } else {
            t.date = cal.startOfDay(for: t.date)
        }
        store.upsert(task: t)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Клиент") {
                    if store.clients.isEmpty {
                        Text("Сначала добавьте клиента во вкладке «Клиенты»").foregroundColor(.secondary)
                    } else {
                        Picker("Клиент", selection: $task.clientID) {
                            ForEach(store.clients) { c in Text(c.name).tag(Optional(c.id)) }
                        }
                    }
                }
                Section("Задача") {
                    TextField("Что нужно сделать", text: $task.title)
                    TextField("Детали: что взять, что проверить", text: $task.details, axis: .vertical)
                        .lineLimit(3...8)
                    Toggle("Срочно", isOn: $task.urgent)
                }
                Section {
                    Toggle("Указать дату", isOn: $task.hasDate)
                    if task.hasDate {
                        DatePicker("Дата", selection: $task.date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                        Toggle("Указать время", isOn: $task.hasTime)
                        if task.hasTime {
                            DatePicker("Время", selection: $task.date, displayedComponents: .hourAndMinute)
                        }
                        Picker("Напомнить", selection: $task.remindMinutes) {
                            Text("Не напоминать").tag(-1)
                            Text("В момент начала").tag(0)
                            Text("За 15 минут").tag(15)
                            Text("За 1 час").tag(60)
                            Text("За 1 день").tag(1440)
                        }
                    }
                } header: {
                    Text("Когда")
                } footer: {
                    Text("Для задач без времени напоминание приходит в 08:00 в этот день.")
                }
                if !isNew {
                    Section {
                        Button("Удалить задачу", role: .destructive) {
                            store.delete(task: task)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Новая задача" : "Задача")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { commit() }
                        .disabled(task.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if task.clientID == nil { task.clientID = store.clients.first?.id }
            }
        }
    }
}

// MARK: - Клиенты

struct ClientsView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Client?

    private var sorted: [Client] {
        store.clients.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func subtitle(_ c: Client) -> String {
        let open = store.tasks.filter { $0.clientID == c.id && !$0.done }.count
        return [c.phone, "задач: \(open)"].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            List {
                if sorted.isEmpty {
                    Text("Клиентов пока нет. Нажмите +").foregroundColor(.secondary)
                }
                ForEach(sorted) { c in
                    NavigationLink(destination: ClientDetail(clientID: c.id)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.name).font(.headline)
                            Text(subtitle(c)).font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    let items = idx.map { sorted[$0] }
                    for c in items { store.delete(client: c) }
                }
            }
            .navigationTitle("Клиенты")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { editing = Client() } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { c in ClientForm(client: c) }
        }
    }
}

struct ClientDetail: View {
    @EnvironmentObject var store: Store
    let clientID: UUID
    @State private var editingClient: Client?
    @State private var editingTask: TaskItem?

    private var clientTasks: [TaskItem] {
        store.tasks.filter { $0.clientID == clientID }.sorted { a, b in
            if a.done != b.done { return !a.done }
            return a.date < b.date
        }
    }

    var body: some View {
        Group {
            if let c = store.client(clientID) {
                List {
                    Section("Контакты") {
                        if let url = phoneURL(c.phone) { Link("📞 " + c.phone, destination: url) }
                        if let url = mapURL(c.address) { Link("📍 " + c.address, destination: url) }
                        if !c.note.isEmpty { Text(c.note) }
                    }
                    Section("Задачи") {
                        ForEach(clientTasks) { t in
                            TaskRow(task: t)
                                .contentShape(Rectangle())
                                .onTapGesture { editingTask = t }
                        }
                        Button("+ Задача") { editingTask = TaskItem(clientID: c.id) }
                    }
                }
                .navigationTitle(c.name)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Изменить") { editingClient = c }
                    }
                }
            } else {
                Text("Клиент удалён").foregroundColor(.secondary)
            }
        }
        .sheet(item: $editingClient) { c in ClientForm(client: c) }
        .sheet(item: $editingTask) { t in TaskForm(task: t) }
    }
}

struct ClientForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var client: Client
    @State private var showPicker = false

    init(client: Client) { _client = State(initialValue: client) }

    private var isNew: Bool { !store.clients.contains { $0.id == client.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Клиент") {
                    TextField("Название / имя", text: $client.name)
                }
                Section("Телефон") {
                    TextField("Телефон", text: $client.phone).keyboardType(.phonePad)
                    Button {
                        showPicker = true
                    } label: {
                        Label("Выбрать из контактов", systemImage: "person.crop.circle.badge.plus")
                    }
                }
                Section("Адрес и заметки") {
                    TextField("Адрес объекта", text: $client.address)
                    TextField("Заметки: доступы, особенности", text: $client.note, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(isNew ? "Новый клиент" : "Клиент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        store.upsert(client: client)
                        dismiss()
                    }
                    .disabled(client.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                ContactPicker(isPresented: $showPicker) { name, phone in
                    if client.name.trimmingCharacters(in: .whitespaces).isEmpty { client.name = name }
                    if !phone.isEmpty { client.phone = phone }
                }
            }
        }
    }
}
