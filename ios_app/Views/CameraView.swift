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
    @State private var showCropEditor = false

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

                    // ── Select capture area ───────────────────────────────────
                    if capturedImage != nil {
                        Button {
                            showCropEditor = true
                        } label: {
                            Label("Select Capture Area", systemImage: "crop")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange.opacity(0.12))
                                .foregroundStyle(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }

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
        // Crop area editor
        .fullScreenCover(isPresented: $showCropEditor) {
            if let image = capturedImage {
                CropSelectorView(
                    image: image,
                    onApply: { cropped in
                        capturedImage = cropped
                        showCropEditor = false
                    },
                    onCancel: { showCropEditor = false }
                )
            }
        }
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

// MARK: - Crop Selector

struct CropSelectorView: View {
    let image: UIImage
    let onApply: (UIImage) -> Void
    let onCancel: () -> Void

    // Normalized (0…1) corners of the crop rect relative to the image
    @State private var normTL = CGPoint(x: 0.1, y: 0.1)
    @State private var normBR = CGPoint(x: 0.9, y: 0.9)
    @State private var dragMode: DragMode = .none
    @State private var lastTranslation: CGSize = .zero

    private let handleR: CGFloat = 16
    private let minFrac: CGFloat = 0.06

    private enum DragMode { case none, tl, tr, bl, br, pan }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let imgSz = fittedSize(for: image, in: geo.size)
                let ox = (geo.size.width  - imgSz.width)  / 2
                let oy = (geo.size.height - imgSz.height) / 2
                let tl = CGPoint(x: ox + normTL.x * imgSz.width,  y: oy + normTL.y * imgSz.height)
                let br = CGPoint(x: ox + normBR.x * imgSz.width,  y: oy + normBR.y * imgSz.height)

                ZStack(alignment: .topLeading) {
                    Color.black
                        .frame(width: geo.size.width, height: geo.size.height)

                    Image(uiImage: image)
                        .resizable()
                        .frame(width: imgSz.width, height: imgSz.height)
                        .offset(x: ox, y: oy)

                    // Dark masks on four sides of the crop rect
                    if tl.y > 0 {
                        Color.black.opacity(0.6)
                            .frame(width: geo.size.width, height: tl.y)
                    }
                    if br.y < geo.size.height {
                        Color.black.opacity(0.6)
                            .frame(width: geo.size.width, height: geo.size.height - br.y)
                            .offset(y: br.y)
                    }
                    if tl.x > 0 {
                        Color.black.opacity(0.6)
                            .frame(width: tl.x, height: br.y - tl.y)
                            .offset(y: tl.y)
                    }
                    if br.x < geo.size.width {
                        Color.black.opacity(0.6)
                            .frame(width: geo.size.width - br.x, height: br.y - tl.y)
                            .offset(x: br.x, y: tl.y)
                    }

                    // Crop border
                    Rectangle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: br.x - tl.x, height: br.y - tl.y)
                        .offset(x: tl.x, y: tl.y)

                    // Corner handles
                    ForEach([tl, CGPoint(x: br.x, y: tl.y), CGPoint(x: tl.x, y: br.y), br],
                            id: \.x) { pt in
                        Circle().fill(Color.white)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .frame(width: handleR * 2, height: handleR * 2)
                            .offset(x: pt.x - handleR, y: pt.y - handleR)
                    }

                    // Transparent drag target covering the full area
                    Color.clear
                        .frame(width: geo.size.width, height: geo.size.height)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    onDrag(val, tl: tl, br: br, imgSz: imgSz)
                                }
                                .onEnded { _ in
                                    dragMode = .none
                                    lastTranslation = .zero
                                }
                        )
                }
                .clipped()
            }
            .background(Color.black)

            // Bottom toolbar
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .padding()
                Spacer()
                Text("Drag corners or rectangle to adjust")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Apply Crop") { onApply(cropped()) }
                    .bold()
                    .padding()
            }
            .background(Color(.systemBackground))
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: Drag handling

    private func onDrag(_ val: DragGesture.Value, tl: CGPoint, br: CGPoint, imgSz: CGSize) {
        let start  = val.startLocation
        let hitR   = handleR * 2.5

        if dragMode == .none {
            if dist(start, tl) < hitR                              { dragMode = .tl }
            else if dist(start, CGPoint(x: br.x, y: tl.y)) < hitR { dragMode = .tr }
            else if dist(start, CGPoint(x: tl.x, y: br.y)) < hitR { dragMode = .bl }
            else if dist(start, br) < hitR                         { dragMode = .br }
            else                                                    { dragMode = .pan }
            lastTranslation = .zero
        }

        let dxPx = val.translation.width  - lastTranslation.width
        let dyPx = val.translation.height - lastTranslation.height
        lastTranslation = val.translation

        let dx = dxPx / imgSz.width
        let dy = dyPx / imgSz.height

        switch dragMode {
        case .none: break
        case .tl:
            normTL.x = max(0,          min(normTL.x + dx, normBR.x - minFrac))
            normTL.y = max(0,          min(normTL.y + dy, normBR.y - minFrac))
        case .tr:
            normBR.x = max(normTL.x + minFrac, min(normBR.x + dx, 1))
            normTL.y = max(0,          min(normTL.y + dy, normBR.y - minFrac))
        case .bl:
            normTL.x = max(0,          min(normTL.x + dx, normBR.x - minFrac))
            normBR.y = max(normTL.y + minFrac, min(normBR.y + dy, 1))
        case .br:
            normBR.x = max(normTL.x + minFrac, min(normBR.x + dx, 1))
            normBR.y = max(normTL.y + minFrac, min(normBR.y + dy, 1))
        case .pan:
            let w = normBR.x - normTL.x, h = normBR.y - normTL.y
            normTL.x = max(0, min(normTL.x + dx, 1 - w))
            normTL.y = max(0, min(normTL.y + dy, 1 - h))
            normBR.x = normTL.x + w
            normBR.y = normTL.y + h
        }
    }

    // MARK: Helpers

    private func fittedSize(for img: UIImage, in container: CGSize) -> CGSize {
        let ar  = img.size.width / img.size.height
        let cAR = container.width / container.height
        return ar > cAR
            ? CGSize(width: container.width,       height: container.width  / ar)
            : CGSize(width: container.height * ar, height: container.height)
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // Normalize image orientation then crop to the selected rect.
    private func cropped() -> UIImage {
        let src = normalized(image)
        let pw  = CGFloat(src.cgImage!.width)
        let ph  = CGFloat(src.cgImage!.height)
        let rect = CGRect(
            x:      normTL.x * pw,
            y:      normTL.y * ph,
            width:  (normBR.x - normTL.x) * pw,
            height: (normBR.y - normTL.y) * ph
        )
        guard let cg = src.cgImage?.cropping(to: rect) else { return image }
        return UIImage(cgImage: cg, scale: src.scale, orientation: .up)
    }

    private func normalized(_ img: UIImage) -> UIImage {
        guard img.imageOrientation != .up else { return img }
        let renderer = UIGraphicsImageRenderer(size: img.size)
        return renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: img.size)) }
    }
}

#Preview {
    CameraView()
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}
