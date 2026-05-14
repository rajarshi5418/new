// Views/GalleryView.swift
// Gallery import tab: pick up to 10 photos with PHPickerViewController,
// analyse each with Claude, and save results to SwiftData.

import SwiftUI
import PhotosUI
import SwiftData

// MARK: - PHPickerViewController wrapper

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 10
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker

        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard !results.isEmpty else { return }

            var images: [UIImage] = []
            let group = DispatchGroup()

            for result in results {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    defer { group.leave() }
                    if let image = object as? UIImage {
                        images.append(image)
                    }
                }
            }

            group.notify(queue: .main) {
                self.parent.selectedImages = images
            }
        }
    }
}

// MARK: - GalleryView

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showPicker = false
    @State private var selectedImages: [UIImage] = []
    @State private var customPrompt = ""
    @State private var isAnalysing = false
    @State private var currentIndex = 0
    @State private var savedRecords: [DocumentRecord] = []
    @State private var showResults = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Pick button ───────────────────────────────────────────
                    Button {
                        showPicker = true
                    } label: {
                        Label("Select Photos", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)

                    // ── Thumbnail grid ────────────────────────────────────────
                    if !selectedImages.isEmpty {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(selectedImages.indices, id: \.self) { i in
                                Image(uiImage: selectedImages[i])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.horizontal)

                        // ── Custom prompt ─────────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Custom question (optional)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField("e.g. List all visible text", text: $customPrompt, axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.horizontal)

                        // ── Analyse button ────────────────────────────────────
                        Button {
                            Task { await analyseAll() }
                        } label: {
                            if isAnalysing {
                                HStack(spacing: 10) {
                                    ProgressView().tint(.white)
                                    Text("Analysing \(currentIndex) of \(selectedImages.count)…")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                Label("Analyse All (\(selectedImages.count) photos)",
                                      systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .disabled(isAnalysing)
                        .padding(.horizontal)
                    } else {
                        // Empty state
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.secondarySystemBackground))
                            .frame(height: 200)
                            .overlay {
                                VStack(spacing: 12) {
                                    Image(systemName: "photo.stack")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.secondary)
                                    Text("No photos selected")
                                        .foregroundStyle(.secondary)
                                    Text("Tap 'Select Photos' to import up to 10 images")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                            }
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top)
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showPicker) {
            PhotoPicker(selectedImages: $selectedImages)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showResults) {
            NavigationStack {
                BatchResultsView(records: savedRecords)
            }
        }
        .alert("Analysis Failed", isPresented: $showError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "Unknown error")
        })
    }

    // MARK: - Batch Analysis

    private func analyseAll() async {
        guard !selectedImages.isEmpty else { return }
        isAnalysing = true
        currentIndex = 0
        savedRecords = []

        for (index, image) in selectedImages.enumerated() {
            currentIndex = index + 1
            do {
                let result = try await ClaudeService.shared.analyze(image: image, prompt: customPrompt)
                let photoPath = savePhotoToDisk(image) ?? ""
                let record = DocumentRecord(from: result, photoPath: photoPath)
                modelContext.insert(record)
                savedRecords.append(record)
            } catch {
                // Log error but continue with remaining images
                print("[GalleryView] Image \(index + 1) failed: \(error.localizedDescription)")
            }
        }

        do {
            try modelContext.save()
        } catch {
            print("[GalleryView] Save failed: \(error)")
        }

        isAnalysing = false

        if savedRecords.isEmpty {
            errorMessage = "None of the selected photos could be analysed. Check your API key in Settings."
            showError = true
        } else {
            showResults = true
        }
    }
}

// MARK: - Batch Results View

struct BatchResultsView: View {
    let records: [DocumentRecord]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(records, id: \.id) { record in
            NavigationLink {
                AnalysisResultView(record: record)
            } label: {
                HStack(spacing: 12) {
                    if let image = record.thumbnail {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 56, height: 56)
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(record.summary.isEmpty ? "No summary" : record.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Results (\(records.count))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

#Preview {
    GalleryView()
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}
