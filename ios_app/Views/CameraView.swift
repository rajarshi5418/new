// Views/CameraView.swift
// Camera capture tab: opens the device camera, previews the captured image,
// sends it to Claude for analysis, and saves the result to SwiftData.

import SwiftUI
import UIKit
import SwiftData

// MARK: - UIImagePickerController wrapper

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - ShareSheet helper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - CameraView

struct CameraView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showPicker = false
    @State private var capturedImage: UIImage?
    @State private var customPrompt = ""
    @State private var isAnalysing = false
    @State private var analysisResult: AnalysisResult?
    @State private var savedRecord: DocumentRecord?
    @State private var showResult = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showNoCameraAlert = false

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // ── Image preview area ────────────────────────────────────
                    if let image = capturedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 340)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(radius: 6)
                            .padding(.horizontal)
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.secondarySystemBackground))
                            .frame(height: 240)
                            .overlay {
                                VStack(spacing: 12) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.secondary)
                                    Text("No photo captured yet")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal)
                    }

                    // ── Camera button ─────────────────────────────────────────
                    Button {
                        if cameraAvailable {
                            showPicker = true
                        } else {
                            showNoCameraAlert = true
                        }
                    } label: {
                        Label("Capture Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)

                    // ── Custom prompt field ───────────────────────────────────
                    if capturedImage != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Custom question (optional)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField("e.g. What document is this?", text: $customPrompt, axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.horizontal)

                        // ── Analyse button ────────────────────────────────────
                        Button {
                            Task { await runAnalysis() }
                        } label: {
                            if isAnalysing {
                                HStack {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Analysing with Claude…")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                Label("Send to Claude", systemImage: "paperplane.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .disabled(isAnalysing)
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top)
            }
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.large)
        }
        // Camera picker sheet
        .sheet(isPresented: $showPicker) {
            ImagePicker(sourceType: .camera, selectedImage: $capturedImage)
                .ignoresSafeArea()
        }
        // Result sheet
        .sheet(isPresented: $showResult) {
            if let record = savedRecord {
                NavigationStack {
                    AnalysisResultView(record: record)
                }
            }
        }
        // Error alert
        .alert("Analysis Failed", isPresented: $showError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "Unknown error")
        })
        // No camera alert
        .alert("Camera Unavailable", isPresented: $showNoCameraAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text("This device does not have an accessible camera. Use the Gallery tab to import photos.")
        })
    }

    // MARK: - Analysis

    private func runAnalysis() async {
        guard let image = capturedImage else { return }
        isAnalysing = true
        defer { isAnalysing = false }

        do {
            let result = try await ClaudeService.shared.analyze(image: image, prompt: customPrompt)

            // Save photo to disk
            let photoPath = savePhotoToDisk(image) ?? ""

            // Persist record
            let record = DocumentRecord(from: result, photoPath: photoPath)
            modelContext.insert(record)
            try modelContext.save()

            savedRecord = record
            showResult = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    CameraView()
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}
