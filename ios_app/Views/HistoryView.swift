// Views/HistoryView.swift
// History tab: searchable list of all DocumentRecord entries with swipe-to-delete
// and Export to XLS toolbar button.

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DocumentRecord.timestamp, order: .reverse) private var records: [DocumentRecord]

    @State private var searchText = ""
    @State private var showExportSheet = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showExportError = false
    @State private var selectedRecord: DocumentRecord?

    private var filteredRecords: [DocumentRecord] {
        guard !searchText.isEmpty else { return records }
        let q = searchText.lowercased()
        return records.filter {
            $0.name.lowercased().contains(q)
            || $0.department.lowercased().contains(q)
            || $0.fileNo.lowercased().contains(q)
            || $0.summary.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    emptyStateView
                } else {
                    recordList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search name, department…")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportAll()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(records.isEmpty)
                }
            }
        }
        // Export activity sheet
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
                    .ignoresSafeArea()
            }
        }
        // Record detail sheet
        .sheet(item: $selectedRecord) { record in
            NavigationStack {
                AnalysisResultView(record: record)
            }
        }
        // Export error alert
        .alert("Export Failed", isPresented: $showExportError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(exportError ?? "Unknown error")
        })
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No history yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Capture or import photos and analyse them with Claude to see results here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordList: some View {
        List {
            ForEach(filteredRecords, id: \.id) { record in
                Button {
                    selectedRecord = record
                } label: {
                    HistoryRowView(record: record)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteRecords)
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func deleteRecords(at offsets: IndexSet) {
        for index in offsets {
            let record = filteredRecords[index]
            // Delete the photo from disk
            if !record.photoPath.isEmpty {
                try? FileManager.default.removeItem(atPath: record.photoPath)
            }
            modelContext.delete(record)
        }
        try? modelContext.save()
    }

    private func exportAll() {
        do {
            let url = try ExportService.shared.generateXLS(records: Array(records))
            exportURL = url
            showExportSheet = true
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }
}

// MARK: - History Row

struct HistoryRowView: View {
    let record: DocumentRecord

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let image = record.thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.secondarySystemBackground)
                        .overlay(
                            Image(systemName: "doc.text.image")
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Text info
            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayName)
                    .font(.headline)
                    .lineLimit(1)

                if !record.department.isEmpty {
                    Text(record.department)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(record.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}
