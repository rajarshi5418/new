"""
Camera capture + Claude vision app — with iOS phone camera support.

Captures a photo from a webcam, Android IP stream, or iOS phone camera,
saves it to disk, and sends it to Claude claude-sonnet-4-6 for analysis.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
iOS SETUP (two options)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Option A — Camo (recommended, best quality)
  1. Install Camo on your iPhone: https://reincubate.com/camo/
  2. Install the Camo desktop companion on your Mac/PC.
  3. Connect via USB or Wi-Fi — Camo appears as a system webcam (index 0 or 1).
  4. Run:  python camera_claude.py --source 0   (or --source 1)

Option B — IP camera app (Wi-Fi, no cable needed)
  Install any MJPEG/snapshot app, e.g.:
    • "IP Camera Lite" (free, App Store)
    • "iVCam" (App Store)
    • "Iriun Webcam" (App Store + desktop client)
  After starting the server in the app, run with its snapshot URL:
    python camera_claude.py --ios-snapshot http://192.168.1.42:8080/shot.jpg
  Or its MJPEG stream URL if the app provides one:
    python camera_claude.py --source http://192.168.1.42:8080/video

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Android SETUP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Install "IP Webcam" (Play Store), tap "Start server", then:
    python camera_claude.py --source http://192.168.1.42:8080/video
  Snapshot mode also works:
    python camera_claude.py --ios-snapshot http://192.168.1.42:8080/shot.jpg
"""

import argparse
import base64
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

import anthropic
import cv2
import numpy as np


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
Structure every analysis with these sections:
1. **Summary** — one-sentence overview of what the photo shows.
2. **Main Subjects** — primary objects, people, or focal points.
3. **Environment & Context** — setting, background, spatial layout.
4. **Technical Quality** — lighting, sharpness, exposure, colour balance.
5. **Notable Details** — anything interesting, unusual, or worth pointing out.
6. **Suggested Follow-up** — one question or action the viewer might explore.

Be precise, concise, and informative.  If you are uncertain about something,
say so rather than guessing.  Focus on what is actually visible in the image.
"""


# ---------------------------------------------------------------------------
# Camera capture — three modes
# ---------------------------------------------------------------------------

def parse_source(raw: str) -> int | str:
    try:
        return int(raw)
    except ValueError:
        return raw


def capture_from_snapshot_url(url: str) -> tuple[bool, object]:
    """Fetch a single JPEG snapshot over HTTP (iOS/Android snapshot endpoint).

    Compatible with:
      • IP Camera Lite  → http://<ip>:8080/shot.jpg
      • IP Webcam (Android) → http://<ip>:8080/shot.jpg
      • Any app that serves a static JPEG endpoint
    """
    print(f"[camera] Fetching snapshot from {url} …")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "CameraClaude/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = resp.read()
    except Exception as exc:
        print(f"[error] Could not fetch snapshot: {exc}", file=sys.stderr)
        print(
            "[hint]  Make sure your iPhone and this computer are on the same\n"
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
    """Open a local webcam index or MJPEG/RTSP stream URL."""
    label = f"camera {source}" if isinstance(source, int) else f"stream {source}"
    print(f"[camera] Connecting to {label} …")
    cap = cv2.VideoCapture(source)

    if not cap.isOpened():
        print(f"[error] Could not open {label}.", file=sys.stderr)
        if isinstance(source, str):
            print(
                "[hint]  Ensure your phone and this computer share the same\n"
                "        Wi-Fi network and the streaming app is running.\n"
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


def save_photo(frame, output_dir: Path = OUTPUT_DIR) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = output_dir / f"photo_{timestamp}.jpg"
    cv2.imwrite(str(path), frame, [cv2.IMWRITE_JPEG_QUALITY, 95])
    print(f"[camera] Photo saved → {path}")
    return path


def show_preview(frame, timeout_ms: int = 2000) -> None:
    try:
        cv2.imshow("Captured photo — press any key to continue", frame)
        cv2.waitKey(timeout_ms)
        cv2.destroyAllWindows()
    except cv2.error:
        pass


# ---------------------------------------------------------------------------
# Claude API
# ---------------------------------------------------------------------------

def encode_image_base64(image_path: Path) -> str:
    with open(image_path, "rb") as f:
        return base64.standard_b64encode(f.read()).decode("utf-8")


def analyse_photo(image_path: Path, user_prompt: str = "") -> str:
    client = anthropic.Anthropic()

    image_data = encode_image_base64(image_path)
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
                            "media_type": "image/jpeg",
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
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Capture a photo from a camera or phone and analyse it with Claude.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
examples:
  # Local webcam (default)
  python camera_claude.py

  # iOS via Camo (USB/Wi-Fi — appears as system webcam)
  python camera_claude.py --source 1

  # iOS via snapshot URL (IP Camera Lite, iVCam, etc.)
  python camera_claude.py --ios-snapshot http://192.168.1.42:8080/shot.jpg

  # Android IP Webcam — MJPEG stream
  python camera_claude.py --source http://192.168.1.42:8080/video

  # Android IP Webcam — snapshot
  python camera_claude.py --ios-snapshot http://192.168.1.42:8080/shot.jpg

  # Custom question
  python camera_claude.py --ios-snapshot http://192.168.1.42:8080/shot.jpg "What is on my desk?"
        """,
    )

    source_group = p.add_mutually_exclusive_group()
    source_group.add_argument(
        "--source",
        default="0",
        metavar="CAM",
        help="Camera index (default: 0) or MJPEG/RTSP stream URL.",
    )
    source_group.add_argument(
        "--ios-snapshot",
        metavar="URL",
        help="iOS/Android snapshot JPEG endpoint, e.g. http://192.168.1.42:8080/shot.jpg",
    )

    p.add_argument(
        "question",
        nargs="*",
        help="Optional custom question to ask Claude about the photo.",
    )
    return p


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    user_prompt = " ".join(args.question)

    if args.ios_snapshot:
        success, frame = capture_from_snapshot_url(args.ios_snapshot)
    else:
        source = parse_source(args.source)
        success, frame = capture_from_stream(source)

    if not success:
        sys.exit(1)

    show_preview(frame)
    image_path = save_photo(frame)

    try:
        analysis = analyse_photo(image_path, user_prompt)
    except anthropic.AuthenticationError:
        print(
            "[error] ANTHROPIC_API_KEY is missing or invalid.\n"
            "        Export it with:  export ANTHROPIC_API_KEY='sk-ant-…'",
            file=sys.stderr,
        )
        sys.exit(1)
    except anthropic.APIError as exc:
        print(f"[error] Claude API error: {exc}", file=sys.stderr)
        sys.exit(1)

    print("\n" + "=" * 70)
    print("CLAUDE'S ANALYSIS")
    print("=" * 70)
    print(analysis)
    print("=" * 70)
    print(f"\nPhoto saved at: {image_path.resolve()}")


if __name__ == "__main__":
    main()
