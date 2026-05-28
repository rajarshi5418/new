# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains two parallel implementations of the same concept: capture or import photos, send them to Claude for structured visual/document analysis, and export results.

1. **`camera_claude.py`** — Python CLI tool using OpenCV for camera capture and the Anthropic SDK for analysis, with Excel export via openpyxl.
2. **`ios_app/`** — SwiftUI iOS app (iOS 17+) with camera/gallery capture, SwiftData persistence, and XML Spreadsheet export.

The primary use case is analysing Jharkhand government documents (Hindi/Devanagari) — extracting metadata like File No., Sanchika No., department, subject lines — though both tools support general photo analysis.

## Python CLI

### Setup

```bash
pip install -r requirements.txt
export ANTHROPIC_API_KEY='sk-ant-...'
```

### Running

```bash
# Default webcam, one shot
python camera_claude.py

# iOS phone via Camo (USB/Wi-Fi)
python camera_claude.py --source 1 --count 5

# iOS/Android via snapshot URL
python camera_claude.py --ios-snapshot http://192.168.1.42:8080/shot.jpg --count 5

# Analyse existing images (files, folders, or mix)
python camera_claude.py --gallery photo.jpg
python camera_claude.py --gallery ~/Pictures/docs/
python camera_claude.py --gallery img1.jpg img2.png "What stamps are visible?"

# Custom output filename
python camera_claude.py --gallery photo.jpg --excel my_report.xlsx
```

Output photos are saved to `captured_photos/`. Excel report is written to `analysis_TIMESTAMP.xlsx` by default.

## iOS App

The app must be built and run from **Xcode 15+** on a physical iPhone (camera does not work on Simulator). Minimum deployment target: **iOS 17.0**.

See `ios_app/README.md` for full Xcode setup steps (project creation, file import, Info.plist keys, API key entry).

## Architecture

### Python (`camera_claude.py`)

Single-file script with four logical sections:

- **Camera capture** — `capture_from_snapshot_url` (HTTP JPEG endpoint), `capture_from_stream` (OpenCV webcam/MJPEG), `load_gallery_images` (file/folder expansion).
- **Claude API** — `analyse_photo` builds a multipart message with the system prompt marked `cache_control: ephemeral`, sends to `claude-sonnet-4-6`, returns raw text.
- **Parser** — `parse_analysis` uses regex to extract the 6 structured sections from Claude's Markdown output.
- **Excel export** — `save_to_excel` writes a formatted openpyxl workbook with a "Photo Analysis" sheet and a "Summary" metadata sheet.

### iOS App (`ios_app/`)

| Layer | File | Role |
|---|---|---|
| Entry | `CameraClaudeApp.swift` | `@main`, configures SwiftData `ModelContainer` |
| Root UI | `ContentView.swift` | `TabView` with 4 tabs |
| Model | `Models/DocumentRecord.swift` | SwiftData `@Model` — one row per analysed photo |
| API types | `Models/ClaudeModels.swift` | `Codable` structs for Anthropic Messages API + `AnalysisResult` parser |
| API client | `Services/ClaudeService.swift` | `actor` — resizes images to ≤1568px, calls API with prompt caching, parses response |
| Export | `Services/ExportService.swift` | Generates XML Spreadsheet (`.xls`) and CSV |
| Views | `Views/*.swift` | Camera, Gallery (batch up to 10), History (search/delete/export), AnalysisResult, Settings |

The API key is stored in `UserDefaults` under `"anthropic_api_key"` and entered via the Settings tab.

### Shared Analysis Structure

Both implementations use the identical 6-section response format enforced by the system prompt:
**Summary → Main Subjects → Environment & Context → Technical Quality → Notable Details → Suggested Follow-up**

When a government document is detected, a 7th **Document Metadata** section is appended with fields: Name, Department, File No., Sanchika No., Rank/ID, Unit, Subject (Hindi/English), Reference No., Date, Year, Purpose, Document Type, Stamps/Seals, Legibility Issues.

### Prompt Caching

Both implementations mark the system prompt with `cache_control: {type: "ephemeral"}`. The system prompt is intentionally long (>2048 tokens) to exceed Anthropic's minimum for cache activation on Sonnet, reducing latency and cost on repeated analyses.

## Data Files

- `govt_documents.db` — SQLite database of previously analysed government documents.
- `jharkhand_*.xlsx` / `register_page_299.xlsx` — Source spreadsheets of Jharkhand government register data.
- `jharkhand_documents_share.zip` — Archive of document images.
