// Views/SettingsView.swift
// Settings tab: API key management, history clearing, and app information.

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allRecords: [DocumentRecord]

    @AppStorage("anthropic_api_key") private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var showClearConfirm = false
    @State private var showClearedAlert = false
    @State private var localAPIKey = ""

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        NavigationStack {
            Form {

                // ── API Key ───────────────────────────────────────────────────
                Section {
                    HStack {
                        if showAPIKey {
                            TextField("sk-ant-…", text: $localAPIKey)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-ant-…", text: $localAPIKey)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(.body, design: .monospaced))
                        }
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Save API Key") {
                        apiKey = localAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .disabled(localAPIKey.trimmingCharacters(in: .whitespacesAndNewlines) == apiKey)

                    if !apiKey.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("API key saved")
                                .foregroundStyle(.green)
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Get your API key at console.anthropic.com. The key is stored securely in UserDefaults on this device only and is never transmitted except to api.anthropic.com.")
                }

                // ── How to get API key ────────────────────────────────────────
                Section("How to get your API key") {
                    VStack(alignment: .leading, spacing: 6) {
                        InstructionRow(number: "1", text: "Open console.anthropic.com in Safari")
                        InstructionRow(number: "2", text: "Sign in or create a free account")
                        InstructionRow(number: "3", text: "Go to API Keys → Create Key")
                        InstructionRow(number: "4", text: "Copy the key (starts with sk-ant-)")
                        InstructionRow(number: "5", text: "Paste it in the field above and tap Save")
                    }
                    .padding(.vertical, 4)
                }

                // ── Camera setup ──────────────────────────────────────────────
                Section("iOS Camera Setup") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This app uses the built-in iPhone camera directly.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text("Option A — Camo (USB or Wi-Fi, best quality)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Install Camo on iPhone + Mac companion app from reincubate.com/camo — the phone appears as a system webcam for macOS apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text("Option B — IP Camera Lite")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Install 'IP Camera Lite' from the App Store. Start the server, note the IP address, then use Gallery Import to fetch snapshot URLs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // ── History management ────────────────────────────────────────
                Section("Data") {
                    HStack {
                        Text("Records stored")
                        Spacer()
                        Text("\(allRecords.count)")
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear All History", systemImage: "trash")
                    }
                    .disabled(allRecords.isEmpty)
                }

                // ── Device Specs ──────────────────────────────────────────────
                Section("Device") {
                    NavigationLink(destination: SystemInfoView()) {
                        Label("System Specifications", systemImage: "cpu")
                    }
                }

                // ── About ─────────────────────────────────────────────────────
                Section("About") {
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Model")
                        Spacer()
                        Text("claude-sonnet-4-6")
                            .foregroundStyle(.secondary)
                            .font(.system(.subheadline, design: .monospaced))
                    }
                    HStack {
                        Text("Minimum iOS")
                        Spacer()
                        Text("17.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Storage")
                        Spacer()
                        Text("SwiftData + Documents")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                localAPIKey = apiKey
            }
            .confirmationDialog(
                "Clear All History?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete \(allRecords.count) Record\(allRecords.count == 1 ? "" : "s")",
                       role: .destructive) {
                    clearHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all analysis records and their saved photos. This cannot be undone.")
            }
            .alert("History Cleared", isPresented: $showClearedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("All records and photos have been deleted.")
            }
        }
    }

    // MARK: - Actions

    private func clearHistory() {
        for record in allRecords {
            // Delete photo from disk
            if !record.photoPath.isEmpty {
                try? FileManager.default.removeItem(atPath: record.photoPath)
            }
            modelContext.delete(record)
        }
        try? modelContext.save()
        showClearedAlert = true
    }
}

// MARK: - Instruction Row

struct InstructionRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}
