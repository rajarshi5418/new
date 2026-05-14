# CameraClaude iOS App

A production-quality SwiftUI app that captures or imports photos, sends them to Claude claude-sonnet-4-6 for structured visual/document analysis, stores all results with SwiftData, and exports to Excel-compatible XML Spreadsheet format.

---

## Xcode Setup (step by step)

### 1. Create the Xcode project

1. Open **Xcode 15** (or later).
2. Choose **File → New → Project**.
3. Select **iOS → App** and click **Next**.
4. Set the following options:
   - **Product Name**: `CameraClaudeApp`
   - **Team**: your Apple developer account (or Personal Team for device testing)
   - **Organization Identifier**: e.g. `com.yourname`
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: None *(we configure SwiftData manually)*
5. Click **Next**, choose a save location, and click **Create**.

### 2. Remove default files

Delete the following files Xcode generated (move to trash when prompted):
- `ContentView.swift`
- `CameraClaudeApp.swift` (or whatever Xcode named the @main file)
- `Assets.xcassets` is fine to keep

### 3. Add all source files

Drag the following files and folders from this `ios_app/` directory into the Xcode Project Navigator (tick **Copy items if needed** and select your app target):

```
ios_app/
├── CameraClaudeApp.swift
├── ContentView.swift
├── Models/
│   ├── DocumentRecord.swift
│   └── ClaudeModels.swift
├── Services/
│   ├── ClaudeService.swift
│   └── ExportService.swift
└── Views/
    ├── CameraView.swift
    ├── GalleryView.swift
    ├── HistoryView.swift
    ├── AnalysisResultView.swift
    └── SettingsView.swift
```

### 4. Set minimum deployment target

1. Click the project name at the top of the Navigator.
2. Select the **CameraClaudeApp** target.
3. In the **General** tab, set **Minimum Deployments → iOS** to **17.0**.

### 5. Configure Info.plist

If Xcode created an `Info.plist` file in your project, open it and add these entries (or merge with the provided `Info.plist`):

| Key | Value |
|-----|-------|
| `NSCameraUsageDescription` | `Used to capture photos for Claude AI analysis` |
| `NSPhotoLibraryUsageDescription` | `Used to import photos for Claude AI analysis` |
| `NSPhotoLibraryAddUsageDescription` | `Used to save captured photos to your library` |

If Xcode manages privacy settings in the Target's Info tab instead, add them there under **Custom iOS Target Properties**.

### 6. Build and run on a physical iPhone

> **Camera will NOT work on the Simulator.** Use a real device.

1. Plug in your iPhone via USB.
2. In the Xcode scheme selector (top toolbar), choose your iPhone.
3. Press **⌘R** to build and run.
4. Trust the developer certificate on the phone if prompted (**Settings → General → VPN & Device Management → Trust**).

### 7. Enter your Anthropic API key

1. Open the app on your iPhone.
2. Tap the **Settings** tab (gear icon).
3. Paste your API key (starts with `sk-ant-`) into the **Anthropic API Key** field.
4. Tap **Save API Key**.

Get your API key at [console.anthropic.com](https://console.anthropic.com).

---

## Architecture

| File | Role |
|------|------|
| `CameraClaudeApp.swift` | `@main` entry point, sets up `ModelContainer` |
| `ContentView.swift` | Root `TabView` (Camera / Gallery / History / Settings) |
| `Models/DocumentRecord.swift` | SwiftData `@Model` — one record per analysed photo |
| `Models/ClaudeModels.swift` | Codable types for the Anthropic Messages API + `AnalysisResult` parser |
| `Services/ClaudeService.swift` | `actor` that calls the API, resizes images, parses responses |
| `Services/ExportService.swift` | Generates XML Spreadsheet (`.xls`) and CSV files |
| `Views/CameraView.swift` | Device camera via `UIImagePickerController` |
| `Views/GalleryView.swift` | Photo library via `PHPickerViewController`, batch analysis |
| `Views/HistoryView.swift` | `@Query` list of records, search, swipe-to-delete, export |
| `Views/AnalysisResultView.swift` | Full analysis display with cards for each section |
| `Views/SettingsView.swift` | API key, instructions, clear history |

---

## Features

- **Camera capture** — one photo at a time via the native iOS camera
- **Gallery import** — pick up to 10 photos from the photo library simultaneously
- **Claude vision analysis** — structured 6-section analysis with prompt caching
- **Document metadata extraction** — regex-based extraction of Name, Department, File No., Sanchika No., Rank/ID, Unit, Subject (Hindi/English), Year, Purpose
- **SwiftData persistence** — all records stored locally, queryable, searchable
- **Excel export** — pure XML Spreadsheet (no ZIP library needed); opens in Excel, Numbers, LibreOffice
- **CSV fallback** — plain CSV export
- **Single-record export** — export just one record directly from its detail view
- **Share sheet** — share analysis text + photo via any iOS share target
- **Search** — filter history by name, department, file number, or summary
- **Swipe to delete** — with automatic photo file cleanup from disk

---

## Prompt Caching

The system prompt is marked with `cache_control: {type: "ephemeral"}`. Because it is >2048 tokens, Anthropic will cache it between API calls, reducing latency and cost on repeated analyses. Token usage (input / cache_write / cache_read / output) is printed to the Xcode console on every call.

---

## Export Format

The `.xls` file is an **XML Spreadsheet** (Office 2003 XML format) — a self-contained XML text file that Excel 2003+, Microsoft 365, Apple Numbers, and LibreOffice all open natively. No ZIP compression or third-party libraries are needed.

Columns exported:
`ID | Timestamp | Name | Department | File No. | Sanchika No. | Rank/ID | Unit | Subject (Hindi) | Subject (English) | Year | Purpose | Summary | Main Subjects | Environment & Context | Technical Quality | Notable Details | Suggested Follow-up | Photo Path | Raw Analysis`

---

## Troubleshooting

**"API key is not set"** — Go to Settings tab and save your key.

**Camera shows blank / crashes** — Must run on a physical device, not Simulator.

**Build errors about SwiftData** — Ensure minimum deployment is iOS 17.0.

**"No module found" errors** — Make sure all `.swift` files are added to the correct target membership (check the File Inspector panel, right side of Xcode).

**Export file won't open on PC** — The `.xls` XML Spreadsheet format requires Excel 2003 or later. If using an older version, use the CSV export instead.
