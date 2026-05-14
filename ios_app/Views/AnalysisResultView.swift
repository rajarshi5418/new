// Views/AnalysisResultView.swift
// Displays all six analysis sections plus document metadata for a DocumentRecord.
// Provides share and single-record export buttons.

import SwiftUI

struct AnalysisResultView: View {
    let record: DocumentRecord

    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showExportSheet = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showExportError = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Photo ─────────────────────────────────────────────────────
                if let image = record.thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(radius: 5)
                        .frame(maxWidth: .infinity)
                }

                // ── Document metadata card ────────────────────────────────────
                let hasMetadata = [record.name, record.department, record.fileNo,
                                   record.sanchikaNo, record.rankId, record.unit,
                                   record.year].contains(where: { !$0.isEmpty })
                if hasMetadata {
                    SectionCard(title: "Document Metadata", icon: "doc.text.fill", color: .indigo) {
                        VStack(alignment: .leading, spacing: 6) {
                            MetaRow(label: "Name", value: record.name)
                            MetaRow(label: "Department", value: record.department)
                            MetaRow(label: "File No.", value: record.fileNo)
                            MetaRow(label: "Sanchika No.", value: record.sanchikaNo)
                            MetaRow(label: "Rank/ID", value: record.rankId)
                            MetaRow(label: "Unit", value: record.unit)
                            MetaRow(label: "Year", value: record.year)
                            MetaRow(label: "Purpose", value: record.purpose)
                            MetaRow(label: "Subject (Hindi)", value: record.subjectHindi)
                            MetaRow(label: "Subject (English)", value: record.subjectEnglish)
                        }
                    }
                }

                // ── Six analysis sections ─────────────────────────────────────
                SectionCard(title: "Summary", icon: "text.alignleft", color: .blue) {
                    Text(record.summary.isEmpty ? "Not available" : record.summary)
                        .font(.body)
                }

                SectionCard(title: "Main Subjects", icon: "star.fill", color: .orange) {
                    Text(record.mainSubjects.isEmpty ? "Not available" : record.mainSubjects)
                        .font(.body)
                }

                SectionCard(title: "Environment & Context", icon: "map.fill", color: .green) {
                    Text(record.environmentContext.isEmpty ? "Not available" : record.environmentContext)
                        .font(.body)
                }

                SectionCard(title: "Technical Quality", icon: "camera.aperture", color: .purple) {
                    Text(record.technicalQuality.isEmpty ? "Not available" : record.technicalQuality)
                        .font(.body)
                }

                SectionCard(title: "Notable Details", icon: "magnifyingglass", color: .pink) {
                    Text(record.notableDetails.isEmpty ? "Not available" : record.notableDetails)
                        .font(.body)
                }

                SectionCard(title: "Suggested Follow-up", icon: "arrow.right.circle.fill", color: .teal) {
                    Text(record.suggestedFollowUp.isEmpty ? "Not available" : record.suggestedFollowUp)
                        .font(.body)
                }

                // ── Export to Excel button ────────────────────────────────────
                Button {
                    exportSingle()
                } label: {
                    Label("Export to Excel", systemImage: "tablecells")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGreen))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 4)

                // ── Timestamp ─────────────────────────────────────────────────
                Text("Analysed: \(record.formattedDate)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom)
            }
            .padding()
        }
        .navigationTitle(record.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareText()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        // Share sheet for text
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
                .ignoresSafeArea()
        }
        // Export sheet for XLS
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
                    .ignoresSafeArea()
            }
        }
        .alert("Export Failed", isPresented: $showExportError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(exportError ?? "Unknown error")
        })
    }

    // MARK: - Actions

    private func shareText() {
        let text = buildShareText()
        shareItems = [text]
        if let image = record.thumbnail { shareItems.append(image) }
        showShareSheet = true
    }

    private func exportSingle() {
        do {
            let url = try ExportService.shared.generateXLS(record: record)
            exportURL = url
            showExportSheet = true
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    private func buildShareText() -> String {
        var parts: [String] = []
        parts.append("=== Claude Analysis ===")
        if !record.displayName.isEmpty { parts.append("Name: \(record.displayName)") }
        if !record.department.isEmpty { parts.append("Department: \(record.department)") }
        parts.append("Date: \(record.formattedDate)")
        parts.append("")
        if !record.summary.isEmpty { parts.append("SUMMARY\n\(record.summary)") }
        if !record.mainSubjects.isEmpty { parts.append("MAIN SUBJECTS\n\(record.mainSubjects)") }
        if !record.environmentContext.isEmpty { parts.append("ENVIRONMENT & CONTEXT\n\(record.environmentContext)") }
        if !record.technicalQuality.isEmpty { parts.append("TECHNICAL QUALITY\n\(record.technicalQuality)") }
        if !record.notableDetails.isEmpty { parts.append("NOTABLE DETAILS\n\(record.notableDetails)") }
        if !record.suggestedFollowUp.isEmpty { parts.append("SUGGESTED FOLLOW-UP\n\(record.suggestedFollowUp)") }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Reusable Section Card

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Divider()
            content()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Metadata Row

struct MetaRow: View {
    let label: String
    let value: String

    var body: some View {
        if !value.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text(label + ":")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 100, alignment: .leading)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

// Helper for SwiftUI previews that need a DocumentRecord
private struct AnalysisResultPreviewWrapper: View {
    @Environment(\.modelContext) private var context
    var body: some View {
        let r = DocumentRecord(
            name: "Sample Document",
            department: "Finance",
            fileNo: "FIN/2024/001",
            rawAnalysis: "Sample raw analysis text",
            summary: "A sample financial document from 2024.",
            mainSubjects: "Budget report, year-end summary.",
            environmentContext: "Office environment, standard A4 paper.",
            technicalQuality: "Good lighting, slight shadow on right edge.",
            notableDetails: "Signed and stamped on page 3.",
            suggestedFollowUp: "Cross-check with the supporting annexures."
        )
        context.insert(r)
        return NavigationStack {
            AnalysisResultView(record: r)
        }
    }
}

#Preview {
    AnalysisResultPreviewWrapper()
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}
