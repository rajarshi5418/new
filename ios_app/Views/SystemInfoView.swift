// Views/SystemInfoView.swift
// Displays iPhone system specifications extracted from native APIs.

import SwiftUI

struct SystemInfoView: View {
    @State private var specs: [SystemSpec] = []
    @State private var copied = false

    private var categories: [String] {
        var seen = Set<String>()
        return specs.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(categories, id: \.self) { category in
                    Section(category) {
                        ForEach(specs.filter { $0.category == category }) { spec in
                            HStack {
                                Text(spec.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(spec.value)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(.subheadline, design: .monospaced))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Device Specs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        copyToClipboard()
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .animation(.default, value: copied)
                }
            }
            .onAppear {
                specs = SystemInfoService.collect()
            }
        }
    }

    private func copyToClipboard() {
        let text = categories.map { category in
            let rows = specs
                .filter { $0.category == category }
                .map { "  \($0.label): \($0.value)" }
                .joined(separator: "\n")
            return "[\(category)]\n\(rows)"
        }.joined(separator: "\n\n")

        UIPasteboard.general.string = text
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}

#Preview {
    SystemInfoView()
}
