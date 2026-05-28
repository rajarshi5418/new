"""
Camera capture + Claude vision app — iOS/Android phone camera with Excel export.

Captures one or more photos from a webcam or phone camera (or imports from a
local gallery folder), sends each to Claude claude-sonnet-4-6 for structured
analysis, and exports all results to a formatted Excel workbook.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
iOS SETUP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Option A — Camo (USB or Wi-Fi, best quality)
  Install Camo on iPhone + Mac/PC companion → https://reincubate.com/camo/
  The iPhone appears as a system webcam:
    python camera_claude.py --source 1 --count 5

Option B — Wi-Fi snapshot (no cable)
  Install "IP Camera Lite" (App Store) → Start server → note IP address
    python camera_claude.py --ios-snapshot http://192.168.1.42:8080/shot.jpg --count 5

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Android SETUP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Install "IP Webcam" (Play Store) → Start server
    python camera_claude.py --ios-snapshot http://192.168.1.42:8080/shot.jpg --count 5
    python camera_claude.py --source http://192.168.1.42:8080/video --count 5

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GALLERY IMPORT (analyse existing photos from your phone or computer)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Single file:
    python camera_claude.py --gallery photo.jpg

  Multiple files:
    python camera_claude.py --gallery img1.jpg img2.png img3.heic

  Entire folder (all images inside):
    python camera_claude.py --gallery ~/Pictures/holiday/

  Mix of files and folders:
    python camera_claude.py --gallery photo.jpg ~/Downloads/shots/
"""

import argparse
import base64
import re
import sys
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Optional

import anthropic
import cv2
import numpy as np
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

MODEL = "claude-sonnet-4-6"
OUTPUT_DIR = Path("captured_photos")
CAPTURE_DELAY_FRAMES = 30

SYSTEM_PROMPT = """\
You are an expert visual analyst with deep knowledge across many domains including:

VISUAL PERCEPTION & COMPOSITION
- Photographic composition: rule of thirds, leading lines, symmetry, framing,
  depth of field, bokeh, foreground/background relationships.
- Colour theory: hue, saturation, value, complementary colours, colour harmony,
  warm vs cool palettes, colour psychology.
- Lighting analysis: direction (front, side, back, top), quality (hard/soft),
  colour temperature (Kelvin scale), shadows, highlights, dynamic range.
- Spatial reasoning: perspective, vanishing points, scale relationships,
  three-dimensional layout inferred from a two-dimensional image.

SCENE UNDERSTANDING
- Object recognition: identify items, their material, approximate size, state
  (new/used/damaged), and likely purpose.
- People & expressions: posture, gesture, facial expression (if clearly
  visible), apparent activity, interpersonal dynamics.
- Environment classification: indoor/outdoor, architectural style, geographic
  cues, time of day, season, weather conditions.
- Text & symbols: read any visible text, logos, signs, or iconography and
  explain their significance in context.

TECHNICAL IMAGE QUALITY
- Sharpness, noise/grain level, motion blur, chromatic aberration, lens
  distortion, exposure (under/over/correct), white balance.
- Estimated capture conditions: handheld vs tripod, natural vs artificial
  light, consumer vs professional equipment.

CONTEXTUAL & CULTURAL ANALYSIS
- Identify cultural artefacts, traditions, or references visible in the scene.
- Note safety considerations if relevant (e.g., hazards, PPE compliance).
- Highlight anything unusual, unexpected, or noteworthy in the scene.

RESPONSE FORMAT
Structure every analysis with these exact sections and headings:
1. **Summary** — one-sentence overview of what the photo shows.
2. **Main Subjects** — primary objects, people, or focal points.
3. **Environment & Context** — setting, background, spatial layout.
4. **Technical Quality** — lighting, sharpness, exposure, colour balance.
5. **Notable Details** — anything interesting, unusual, or worth pointing out.
6. **Suggested Follow-up** — one question or action the viewer might explore.

Be precise, concise, and informative.  If you are uncertain about something,
say so rather than guessing.  Focus on what is actually visible in the image.
"""

SECTION_KEYS = [
    "Summary",
    "Main Subjects",
    "Environment & Context",
    "Technical Quality",
    "Notable Details",
    "Suggested Follow-up",
]


# ---------------------------------------------------------------------------
# Camera capture
# ---------------------------------------------------------------------------

def parse_source(raw: str) -> int | str:
    try:
        return int(raw)
    except ValueError:
        return raw


def capture_from_snapshot_url(url: str) -> tuple[bool, object]:
    """Fetch a single JPEG over HTTP — works with iOS/Android snapshot endpoints."""
    print(f"[camera] Fetching snapshot from {url} …")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "CameraClaude/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = resp.read()
    except Exception as exc:
        print(f"[error] Could not fetch snapshot: {exc}", file=sys.stderr)
        print(
            "[hint]  Make sure your phone and this computer are on the same\n"
            "        Wi-Fi network and the camera app server is running.",
            file=sys.stderr,
        )
        return False, None

    img_array = np.frombuffer(data, dtype=np.uint8)
    frame = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
    if frame is None:
        print("[error] Downloaded data is not a valid JPEG image.", file=sys.stderr)
        return False, None

    h, w = frame.shape[:2]
    print(f"[camera] Snapshot captured ({w}×{h}).")
    return True, frame


def capture_from_stream(source: int | str,
                        warmup_frames: int = CAPTURE_DELAY_FRAMES) -> tuple[bool, object]:
    """Open a local webcam or MJPEG/RTSP stream and grab one frame."""
    label = f"camera {source}" if isinstance(source, int) else f"stream {source}"
    print(f"[camera] Connecting to {label} …")
    cap = cv2.VideoCapture(source)

    if not cap.isOpened():
        print(f"[error] Could not open {label}.", file=sys.stderr)
        if isinstance(source, str):
            print(
                "[hint]  Ensure your phone and this computer share the same Wi-Fi\n"
                "        network and the streaming app is running.\n"
                "        For iOS try --ios-snapshot <url> instead of --source.",
                file=sys.stderr,
            )
        return False, None

    if isinstance(source, int) and warmup_frames > 0:
        print(f"[camera] Warming up ({warmup_frames} frames) …", end="", flush=True)
        for _ in range(warmup_frames):
            cap.read()
        print(" done.")

    ret, frame = cap.read()
    cap.release()

    if not ret or frame is None:
        print("[error] Failed to capture frame.", file=sys.stderr)
        return False, None

    h, w = frame.shape[:2]
    print(f"[camera] Frame captured ({w}×{h}).")
    return True, frame


_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".tif", ".webp", ".heic", ".heif"}


def load_gallery_images(raw_paths: list[str]) -> list[Path]:
    """Expand a list of file and/or directory paths into individual image files.

    Directories are searched non-recursively for recognised image extensions.
    Files are validated to have a supported extension.  Duplicates are removed
    and the final list is sorted by name.
    """
    collected: list[Path] = []

    for raw in raw_paths:
        p = Path(raw).expanduser().resolve()

        if p.is_dir():
            found = sorted(
                f for f in p.iterdir()
                if f.is_file() and f.suffix.lower() in _IMAGE_EXTENSIONS
            )
            if not found:
                print(f"[warn] No images found in directory: {p}", file=sys.stderr)
            collected.extend(found)

        elif p.is_file():
            if p.suffix.lower() not in _IMAGE_EXTENSIONS:
                print(f"[warn] Skipping unsupported file type: {p.name}", file=sys.stderr)
            else:
                collected.append(p)

        else:
            print(f"[warn] Path not found, skipping: {p}", file=sys.stderr)

    # Deduplicate while preserving order
    seen: set[Path] = set()
    unique: list[Path] = []
    for path in collected:
        if path not in seen:
            seen.add(path)
            unique.append(path)

    return unique


def save_photo(frame, output_dir: Path = OUTPUT_DIR) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = output_dir / f"photo_{timestamp}.jpg"
    cv2.imwrite(str(path), frame, [cv2.IMWRITE_JPEG_QUALITY, 95])
    print(f"[camera] Photo saved → {path}")
    return path


def show_preview(frame, timeout_ms: int = 1500) -> None:
    try:
        cv2.imshow("Captured photo — press any key to continue", frame)
        cv2.waitKey(timeout_ms)
        cv2.destroyAllWindows()
    except cv2.error:
        pass


def crop_frame(frame, crop: tuple[int, int, int, int]):
    """Crop frame to (x, y, w, h) pixel region, clamped to image bounds."""
    img_h, img_w = frame.shape[:2]
    x, y, cw, ch = crop
    x  = max(0, min(x,  img_w - 1))
    y  = max(0, min(y,  img_h - 1))
    cw = max(1, min(cw, img_w - x))
    ch = max(1, min(ch, img_h - y))
    print(f"[camera] Cropped to region ({x},{y}) {cw}×{ch} px.")
    return frame[y : y + ch, x : x + cw]


# ---------------------------------------------------------------------------
# Claude API
# ---------------------------------------------------------------------------

def encode_image_base64(image_path: Path) -> str:
    with open(image_path, "rb") as f:
        return base64.standard_b64encode(f.read()).decode("utf-8")


_MEDIA_TYPE_MAP = {
    ".jpg":  "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png":  "image/png",
    ".gif":  "image/gif",
    ".webp": "image/webp",
    # HEIC/BMP/TIFF not natively supported by Claude — convert to JPEG first
}


def ensure_jpeg(image_path: Path) -> Path:
    """Return a JPEG version of the image, converting with OpenCV if needed."""
    if image_path.suffix.lower() in (".jpg", ".jpeg"):
        return image_path

    frame = cv2.imread(str(image_path))
    if frame is None:
        raise ValueError(f"Cannot read image file: {image_path}")

    jpeg_path = image_path.with_suffix(".converted.jpg")
    cv2.imwrite(str(jpeg_path), frame, [cv2.IMWRITE_JPEG_QUALITY, 95])
    print(f"[gallery] Converted {image_path.name} → {jpeg_path.name}")
    return jpeg_path


def analyse_photo(image_path: Path, user_prompt: str = "") -> str:
    """Send photo to Claude and return the raw analysis text."""
    client = anthropic.Anthropic()

    # Convert unsupported formats to JPEG before encoding
    send_path = ensure_jpeg(image_path)
    media_type = _MEDIA_TYPE_MAP.get(send_path.suffix.lower(), "image/jpeg")

    image_data = encode_image_base64(send_path)
    question = user_prompt.strip() or (
        "Please analyse this photo in detail following your structured format."
    )

    print(f"[claude] Sending photo to {MODEL} …")

    response = client.messages.create(
        model=MODEL,
        max_tokens=2048,
        system=[
            {
                "type": "text",
                "text": SYSTEM_PROMPT,
                "cache_control": {"type": "ephemeral"},
            }
        ],
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": media_type,
                            "data": image_data,
                        },
                    },
                    {"type": "text", "text": question},
                ],
            }
        ],
    )

    usage = response.usage
    print(
        f"[claude] Tokens — input: {usage.input_tokens}, "
        f"cache write: {getattr(usage, 'cache_creation_input_tokens', 0)}, "
        f"cache read: {getattr(usage, 'cache_read_input_tokens', 0)}, "
        f"output: {usage.output_tokens}"
    )

    return "\n".join(b.text for b in response.content if b.type == "text")


# ---------------------------------------------------------------------------
# Analysis parser
# ---------------------------------------------------------------------------

def parse_analysis(text: str) -> dict[str, str]:
    """Extract the 6 structured sections from Claude's Markdown analysis."""
    result = {k: "" for k in SECTION_KEYS}

    # Match **Section Name** (optional dash/em-dash) then content until the
    # next numbered section heading or end of string.
    pattern = re.compile(
        r"\*\*(" + "|".join(re.escape(k) for k in SECTION_KEYS) + r")\*\*"
        r"[^\n]*\n?"           # optional remainder of the heading line
        r"(.*?)"               # section body (non-greedy)
        r"(?=\n\d+\.\s+\*\*|\Z)",  # stop at next numbered heading or EOF
        re.DOTALL,
    )

    for match in pattern.finditer(text):
        key = match.group(1)
        body = match.group(2).strip()
        result[key] = body

    return result


# ---------------------------------------------------------------------------
# Excel export
# ---------------------------------------------------------------------------

_HDR_FILL = PatternFill("solid", fgColor="1F3864")   # dark navy
_HDR_FONT = Font(bold=True, color="FFFFFF", size=11)
_HDR_ALIGN = Alignment(horizontal="center", vertical="center", wrap_text=True)

_EVEN_FILL = PatternFill("solid", fgColor="D6E4F0")  # light blue
_ODD_FILL = PatternFill("solid", fgColor="FFFFFF")
_DATA_ALIGN = Alignment(vertical="top", wrap_text=True)

_BORDER = Border(
    left=Side(style="thin", color="BFBFBF"),
    right=Side(style="thin", color="BFBFBF"),
    top=Side(style="thin", color="BFBFBF"),
    bottom=Side(style="thin", color="BFBFBF"),
)

_COLUMNS = [
    ("#",                     5),
    ("Timestamp",            20),
    ("Photo File",           36),
    ("Summary",              45),
    ("Main Subjects",        35),
    ("Environment & Context",35),
    ("Technical Quality",    35),
    ("Notable Details",      35),
    ("Suggested Follow-up",  35),
]


def save_to_excel(records: list[dict], output_path: Path) -> None:
    """Write all photo analysis records to a formatted Excel workbook."""
    wb = Workbook()
    ws = wb.active
    ws.title = "Photo Analysis"

    # ── Header row ──────────────────────────────────────────────────────────
    ws.row_dimensions[1].height = 32
    for col, (header, width) in enumerate(_COLUMNS, 1):
        cell = ws.cell(row=1, column=col, value=header)
        cell.font = _HDR_FONT
        cell.fill = _HDR_FILL
        cell.alignment = _HDR_ALIGN
        cell.border = _BORDER
        ws.column_dimensions[get_column_letter(col)].width = width

    ws.freeze_panes = "A2"

    # ── Data rows ───────────────────────────────────────────────────────────
    for row_idx, rec in enumerate(records, 2):
        fill = _EVEN_FILL if row_idx % 2 == 0 else _ODD_FILL
        ws.row_dimensions[row_idx].height = 90

        values = [
            row_idx - 1,
            rec["timestamp"],
            rec["photo_path"],
            rec["Summary"],
            rec["Main Subjects"],
            rec["Environment & Context"],
            rec["Technical Quality"],
            rec["Notable Details"],
            rec["Suggested Follow-up"],
        ]

        for col, value in enumerate(values, 1):
            cell = ws.cell(row=row_idx, column=col, value=value)
            cell.fill = fill
            cell.alignment = _DATA_ALIGN
            cell.border = _BORDER

    # ── Summary sheet ────────────────────────────────────────────────────────
    ws2 = wb.create_sheet("Summary")
    ws2.column_dimensions["A"].width = 25
    ws2.column_dimensions["B"].width = 60

    meta_rows = [
        ("Generated",     datetime.now().strftime("%Y-%m-%d %H:%M:%S")),
        ("Total photos",  len(records)),
        ("Model",         MODEL),
    ]
    for r, (label, value) in enumerate(meta_rows, 1):
        ws2.cell(r, 1, label).font = Font(bold=True)
        ws2.cell(r, 2, value)

    wb.save(output_path)
    print(f"[excel]  Workbook saved → {output_path.resolve()}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Capture or import photos and export Claude analysis to Excel.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
examples:
  # iOS — Camo (USB/Wi-Fi), take 3 photos
  python camera_claude.py --source 1 --count 3

  # iOS — snapshot URL (IP Camera Lite), take 5 photos
  python camera_claude.py --ios-snapshot http://192.168.1.42:8080/shot.jpg --count 5

  # Android — IP Webcam snapshot, custom question
  python camera_claude.py --ios-snapshot http://192.168.1.42:8080/shot.jpg \\
      --count 4 --excel my_report.xlsx "What products are visible?"

  # Gallery import — single file
  python camera_claude.py --gallery photo.jpg

  # Gallery import — multiple files
  python camera_claude.py --gallery img1.jpg img2.png img3.heic

  # Gallery import — entire folder
  python camera_claude.py --gallery ~/Pictures/holiday/

  # Gallery import — mix of files and folder, custom question
  python camera_claude.py --gallery photo.jpg ~/Downloads/shots/ "Describe the scene"

  # Default webcam, single shot
  python camera_claude.py

  # Crop to a 640×480 region at offset (100, 50) before sending to Claude
  python camera_claude.py --crop 100 50 640 480

  # Gallery import with crop region
  python camera_claude.py --gallery ~/Photos/ --crop 0 0 1280 720
        """,
    )

    source_group = p.add_mutually_exclusive_group()
    source_group.add_argument(
        "--source",
        default="0",
        metavar="CAM",
        help="Camera index (default: 0) or MJPEG/RTSP URL.",
    )
    source_group.add_argument(
        "--ios-snapshot",
        metavar="URL",
        help="iOS/Android JPEG snapshot endpoint, e.g. http://192.168.1.42:8080/shot.jpg",
    )
    source_group.add_argument(
        "--gallery",
        nargs="+",
        metavar="PATH",
        help=(
            "Analyse existing images instead of capturing live. "
            "Accepts one or more image files and/or folders. "
            "Supported formats: JPG, PNG, BMP, TIFF, WEBP, HEIC."
        ),
    )

    p.add_argument(
        "--count",
        type=int,
        default=1,
        metavar="N",
        help="Number of live photos to capture (default: 1). Ignored with --gallery.",
    )
    p.add_argument(
        "--crop",
        nargs=4,
        type=int,
        metavar=("X", "Y", "W", "H"),
        help=(
            "Limit capture to a pixel region — X Y W H "
            "(left column, top row, width, height). "
            "Applied to every live frame and gallery image before analysis."
        ),
    )
    p.add_argument(
        "--excel",
        metavar="FILE",
        help="Output Excel filename (default: analysis_TIMESTAMP.xlsx).",
    )
    p.add_argument(
        "question",
        nargs="*",
        help="Optional custom question to ask Claude about each photo.",
    )
    return p


def do_capture(args) -> tuple[bool, object]:
    """Dispatch to the correct live-capture method based on CLI args."""
    if args.ios_snapshot:
        return capture_from_snapshot_url(args.ios_snapshot)
    return capture_from_stream(parse_source(args.source))


def analyse_and_record(
    image_path: Path,
    label: str,
    user_prompt: str,
    records: list[dict],
) -> None:
    """Analyse one image, print the result, and append to records."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    try:
        raw_analysis = analyse_photo(image_path, user_prompt)
    except anthropic.AuthenticationError:
        print(
            "[error] ANTHROPIC_API_KEY is missing or invalid.\n"
            "        Export it with:  export ANTHROPIC_API_KEY='sk-ant-…'",
            file=sys.stderr,
        )
        sys.exit(1)
    except (anthropic.APIError, ValueError) as exc:
        print(f"[error] {label}: {exc}", file=sys.stderr)
        return

    sections = parse_analysis(raw_analysis)

    print(f"\n{'=' * 70}")
    print(f"{label} — CLAUDE'S ANALYSIS")
    print("=" * 70)
    print(raw_analysis)
    print("=" * 70)

    records.append(
        {
            "timestamp": timestamp,
            "photo_path": str(image_path.resolve()),
            **sections,
        }
    )


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    user_prompt = " ".join(args.question)
    excel_path = Path(
        args.excel or f"analysis_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    )
    records: list[dict] = []

    # ── Gallery import mode ───────────────────────────────────────────────────
    if args.gallery:
        gallery_files = load_gallery_images(args.gallery)
        if not gallery_files:
            print("[error] No valid image files found in the provided paths.", file=sys.stderr)
            sys.exit(1)

        total = len(gallery_files)
        print(f"[gallery] Found {total} image(s) to analyse.")

        for idx, image_path in enumerate(gallery_files, 1):
            print(f"\n[gallery] Processing {idx}/{total}: {image_path.name}")
            if args.crop:
                frame = cv2.imread(str(image_path))
                if frame is not None:
                    frame = crop_frame(frame, tuple(args.crop))
                    image_path = image_path.parent / f"{image_path.stem}_crop.jpg"
                    cv2.imwrite(str(image_path), frame, [cv2.IMWRITE_JPEG_QUALITY, 95])
            analyse_and_record(image_path, f"IMAGE {idx}/{total} ({image_path.name})", user_prompt, records)

    # ── Live camera mode ──────────────────────────────────────────────────────
    else:
        count = max(1, args.count)

        for shot in range(1, count + 1):
            if count > 1:
                try:
                    input(f"\n[{shot}/{count}] Point your camera at the subject and press Enter …")
                except (EOFError, KeyboardInterrupt):
                    print("\n[info] Capture stopped by user.")
                    break

            success, frame = do_capture(args)
            if not success:
                print(f"[warn] Skipping photo {shot} — capture failed.", file=sys.stderr)
                continue

            if args.crop:
                frame = crop_frame(frame, tuple(args.crop))
            show_preview(frame)
            image_path = save_photo(frame)
            analyse_and_record(image_path, f"PHOTO {shot}/{count}", user_prompt, records)

    # ── Export to Excel ───────────────────────────────────────────────────────
    if records:
        save_to_excel(records, excel_path)
        print(f"\n[done]  {len(records)} photo(s) analysed.")
        print(f"[done]  Excel report → {excel_path.resolve()}")
    else:
        print("[warn]  No photos were successfully analysed; Excel not written.", file=sys.stderr)


if __name__ == "__main__":
    main()
