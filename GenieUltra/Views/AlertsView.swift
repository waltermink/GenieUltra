import SwiftUI

// MARK: - Alerts Hub

struct AlertsView: View {
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Alert Type", selection: $selectedTab) {
                    Text("Wait Times").tag(0)
                    Text("Lightning Lane").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()
                if selectedTab == 0 {
                    WaitAlertsContent()
                } else {
                    LLAlertsContent()
                }
            }
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Wait Time Alerts

private struct WaitAlertsContent: View {
    @Environment(AlertStore.self) private var alertStore
    @State private var showingAdd = false
    @State private var editingAlert: WaitTimeAlert?
    @State private var selection = Set<UUID>()
    @State private var editMode = EditMode.inactive

    var body: some View {
        Group {
            if alertStore.waitTimeAlerts.isEmpty {
                ContentUnavailableView(
                    "No Wait Time Alerts",
                    systemImage: "bell.slash",
                    description: Text("Tap + to get notified when a wait drops or a ride opens.")
                )
            } else {
                List(selection: $selection) {
                    ForEach(alertStore.waitTimeAlerts) { alert in
                        WaitAlertRow(alert: alert)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button { editingAlert = alert } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                    .onDelete { indexSet in
                        for i in indexSet { alertStore.deleteWaitAlert(id: alertStore.waitTimeAlerts[i].id) }
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, $editMode)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !alertStore.waitTimeAlerts.isEmpty {
                    if editMode.isEditing {
                        Button("Cancel") { editMode = .inactive; selection.removeAll() }
                    } else {
                        Button("Select") { editMode = .active }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if editMode.isEditing && !selection.isEmpty {
                    Button("Delete (\(selection.count))", role: .destructive) {
                        for id in selection { alertStore.deleteWaitAlert(id: id) }
                        selection.removeAll(); editMode = .inactive
                    }
                    .tint(.red)
                } else if !editMode.isEditing {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showingAdd) { AddWaitTimeAlertView() }
        .sheet(item: $editingAlert) { alert in AddWaitTimeAlertView(editing: alert) }
    }
}

private struct WaitAlertRow: View {
    @Environment(AlertStore.self) private var alertStore
    let alert: WaitTimeAlert
    @State private var testFired = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.attractionName).font(.headline)
                Group {
                    switch alert.type {
                    case .threshold: Text("Notify when wait ≤ \(alert.threshold ?? 0) min")
                    case .isOperating: Text("Notify when ride is operating")
                    }
                }
                .font(.subheadline).foregroundStyle(.secondary)
                if let lastFired = alert.lastFired {
                    Text("Last fired \(lastFired.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button {
                Task {
                    await alertStore.fireTest(waitAlert: alert)
                    testFired = true
                    try? await Task.sleep(for: .seconds(2))
                    testFired = false
                }
            } label: {
                Image(systemName: testFired ? "checkmark.circle.fill" : "play.circle")
                    .foregroundStyle(testFired ? .green : .orange).font(.title3)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { alert.enabled }, set: { _ in alertStore.toggleWaitAlert(id: alert.id) }))
                .labelsHidden()
        }
        .opacity(alert.enabled ? 1 : 0.5)
        .padding(.vertical, 2)
    }
}

// MARK: - Lightning Lane Alerts

private struct LLAlertsContent: View {
    @Environment(AlertStore.self) private var alertStore
    @State private var showingAdd = false
    @State private var editingAlert: LightningLaneAlert?
    @State private var selection = Set<UUID>()
    @State private var editMode = EditMode.inactive

    var body: some View {
        Group {
            if alertStore.lightningLaneAlerts.isEmpty {
                ContentUnavailableView(
                    "No Lightning Lane Alerts",
                    systemImage: "bolt.slash",
                    description: Text("Tap + to get notified when Lightning Lane opens in your target window.")
                )
            } else {
                List(selection: $selection) {
                    ForEach(alertStore.lightningLaneAlerts) { alert in
                        LLAlertRow(alert: alert)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button { editingAlert = alert } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                    .onDelete { indexSet in
                        for i in indexSet { alertStore.deleteLLAlert(id: alertStore.lightningLaneAlerts[i].id) }
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, $editMode)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !alertStore.lightningLaneAlerts.isEmpty {
                    if editMode.isEditing {
                        Button("Cancel") { editMode = .inactive; selection.removeAll() }
                    } else {
                        Button("Select") { editMode = .active }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if editMode.isEditing && !selection.isEmpty {
                    Button("Delete (\(selection.count))", role: .destructive) {
                        for id in selection { alertStore.deleteLLAlert(id: id) }
                        selection.removeAll(); editMode = .inactive
                    }
                    .tint(.red)
                } else if !editMode.isEditing {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showingAdd) { AddLightningLaneAlertView() }
        .sheet(item: $editingAlert) { alert in AddLightningLaneAlertView(editing: alert) }
    }
}

private struct LLAlertRow: View {
    @Environment(AlertStore.self) private var alertStore
    let alert: LightningLaneAlert
    @State private var testFired = false

    private var llTypeSummary: String {
        switch (alert.includeStandardLL, alert.includePremierAccess) {
        case (true, true):   return "LL + Premier Access"
        case (true, false):  return "Lightning Lane"
        case (false, true):  return "Premier Access"
        default:             return "None"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.attractionName).font(.headline)
                Text(llTypeSummary).font(.subheadline).foregroundStyle(.secondary)
                Text("Window: \(hourLabel(alert.windowStartHour)) – \(hourLabel(alert.windowEndHour))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task {
                    await alertStore.fireTest(llAlert: alert)
                    testFired = true
                    try? await Task.sleep(for: .seconds(2))
                    testFired = false
                }
            } label: {
                Image(systemName: testFired ? "checkmark.circle.fill" : "play.circle")
                    .foregroundStyle(testFired ? .green : .orange).font(.title3)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { alert.enabled }, set: { _ in alertStore.toggleLLAlert(id: alert.id) }))
                .labelsHidden()
        }
        .opacity(alert.enabled ? 1 : 0.5)
        .padding(.vertical, 2)
    }

    private func hourLabel(_ hour: Int) -> String {
        var c = DateComponents(); c.hour = hour; c.minute = 0
        guard let d = Calendar.current.date(from: c) else { return "\(hour):00" }
        let f = DateFormatter(); f.dateFormat = "h a"
        return f.string(from: d)
    }
}

// MARK: - Add / Edit Wait Time Alert

struct AddWaitTimeAlertView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AlertStore.self) private var alertStore
    @Environment(ParkDataStore.self) private var store

    let editing: WaitTimeAlert?

    @State private var selectedAttractionID: String?
    @State private var alertType: WaitTimeAlertType
    @State private var threshold: Int

    init(editing: WaitTimeAlert? = nil) {
        self.editing = editing
        _selectedAttractionID = State(initialValue: editing?.attractionID)
        _alertType = State(initialValue: editing?.type ?? .threshold)
        _threshold = State(initialValue: editing?.threshold ?? 30)
    }

    private var sortedAttractions: [EntityLiveData] {
        store.attractions.sorted { $0.name < $1.name }
    }
    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Attraction") {
                    Picker("Attraction", selection: $selectedAttractionID) {
                        Text("Select…").tag(Optional<String>.none)
                        ForEach(sortedAttractions) { a in
                            Text(a.name).tag(Optional(a.id))
                        }
                    }
                }

                Section("Alert Type") {
                    Picker("Type", selection: $alertType) {
                        Text("Wait time drops to…").tag(WaitTimeAlertType.threshold)
                        Text("Ride starts operating").tag(WaitTimeAlertType.isOperating)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if alertType == .threshold {
                    Section {
                        Picker("Threshold", selection: $threshold) {
                            ForEach(Array(stride(from: 5, through: 120, by: 5)), id: \.self) { v in
                                Text("\(v) min").tag(v)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 140)
                    } header: {
                        Text("Alert when wait ≤ \(threshold) min")
                    } footer: {
                        Text("Notified at most once per hour while wait stays at or below this value.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Wait Alert" : "New Wait Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(selectedAttractionID == nil)
                        .tint(.blue)
                }
            }
        }
    }

    private func save() {
        guard let id = selectedAttractionID,
              let attraction = store.attractions.first(where: { $0.id == id }) else { return }
        if var updated = editing {
            updated.attractionID = attraction.id
            updated.attractionName = attraction.name
            updated.type = alertType
            updated.threshold = alertType == .threshold ? threshold : nil
            alertStore.updateWaitAlert(updated)
        } else {
            alertStore.addWaitAlert(WaitTimeAlert(
                attractionID: attraction.id,
                attractionName: attraction.name,
                type: alertType,
                threshold: alertType == .threshold ? threshold : nil
            ))
        }
        dismiss()
    }
}

// MARK: - Add / Edit Lightning Lane Alert

struct AddLightningLaneAlertView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AlertStore.self) private var alertStore
    @Environment(ParkDataStore.self) private var store

    let editing: LightningLaneAlert?

    @State private var selectedAttractionID: String?
    @State private var includeStandard: Bool
    @State private var includePaid: Bool
    @State private var windowStartHour: Int
    @State private var windowEndHour: Int

    init(editing: LightningLaneAlert? = nil) {
        self.editing = editing
        _selectedAttractionID = State(initialValue: editing?.attractionID)
        _includeStandard = State(initialValue: editing?.includeStandardLL ?? true)
        _includePaid = State(initialValue: editing?.includePremierAccess ?? false)
        // Default start to current hour (clamped to picker range), end to current hour + 4
        let currentHour = Calendar.current.component(.hour, from: Date())
        _windowStartHour = State(initialValue: editing?.windowStartHour ?? max(6, min(currentHour, 22)))
        _windowEndHour = State(initialValue: editing?.windowEndHour ?? max(7, min(currentHour + 4, 23)))
    }

    /// Only attractions that currently advertise a Lightning Lane or Premier Access queue.
    private var llAttractions: [EntityLiveData] {
        let filtered = store.attractions.filter {
            $0.queue?.returnTime != nil || $0.queue?.paidReturnTime != nil
        }.sorted { $0.name < $1.name }
        // Fall back to all attractions if LL isn't active yet today
        return filtered.isEmpty ? store.attractions.sorted { $0.name < $1.name } : filtered
    }

    private var canSave: Bool {
        selectedAttractionID != nil && (includeStandard || includePaid) && windowStartHour < windowEndHour
    }
    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Attraction") {
                    Picker("Attraction", selection: $selectedAttractionID) {
                        Text("Select…").tag(Optional<String>.none)
                        ForEach(llAttractions) { a in
                            Text(a.name).tag(Optional(a.id))
                        }
                    }
                    if store.attractions.filter({ $0.queue?.returnTime != nil || $0.queue?.paidReturnTime != nil }).isEmpty {
                        Text("Showing all attractions — LL not currently active in live data.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Lightning Lane Type") {
                    Toggle("Standard Lightning Lane", isOn: $includeStandard)
                    Toggle("Premier Access (paid)", isOn: $includePaid)
                }

                Section {
                    HStack(spacing: 0) {
                        VStack(spacing: 4) {
                            Text("Start").font(.caption).foregroundStyle(.secondary)
                            Picker("Start", selection: $windowStartHour) {
                                ForEach(6...22, id: \.self) { h in Text(hourLabel(h)).tag(h) }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 140)
                        }
                        VStack(spacing: 4) {
                            Text("End").font(.caption).foregroundStyle(.secondary)
                            Picker("End", selection: $windowEndHour) {
                                ForEach(7...23, id: \.self) { h in Text(hourLabel(h)).tag(h) }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 140)
                        }
                    }
                    if windowStartHour >= windowEndHour {
                        Text("End must be after start.").font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Return Time Window")
                } footer: {
                    Text("Notified when a return time falls within this range.")
                }
            }
            .navigationTitle(isEditing ? "Edit LL Alert" : "New LL Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(!canSave)
                        .tint(.blue)
                }
            }
        }
    }

    private func save() {
        guard let id = selectedAttractionID,
              let attraction = store.attractions.first(where: { $0.id == id }) else { return }
        if var updated = editing {
            updated.attractionID = attraction.id
            updated.attractionName = attraction.name
            updated.includeStandardLL = includeStandard
            updated.includePremierAccess = includePaid
            updated.windowStartHour = windowStartHour
            updated.windowEndHour = windowEndHour
            alertStore.updateLLAlert(updated)
        } else {
            alertStore.addLLAlert(LightningLaneAlert(
                attractionID: attraction.id,
                attractionName: attraction.name,
                includeStandardLL: includeStandard,
                includePremierAccess: includePaid,
                windowStartHour: windowStartHour,
                windowEndHour: windowEndHour
            ))
        }
        dismiss()
    }

    private func hourLabel(_ hour: Int) -> String {
        var c = DateComponents(); c.hour = hour; c.minute = 0
        guard let d = Calendar.current.date(from: c) else { return "\(hour):00" }
        let f = DateFormatter(); f.dateFormat = "h a"
        return f.string(from: d)
    }
}
