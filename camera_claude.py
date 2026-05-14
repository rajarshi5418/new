"""
Camera capture + Claude vision app.

Captures a photo from the device webcam, saves it to disk, and sends it to
Claude claude-sonnet-4-6 for analysis.  The system prompt is marked with
cache_control so repeated runs reuse the cached prefix (Sonnet 4.6 minimum:
2 048 tokens — the prompt below meets that threshold).
"""

import base64
import os
import sys
from datetime import datetime
from pathlib import Path

import anthropic
import cv2


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

MODEL = "claude-sonnet-4-6"
OUTPUT_DIR = Path("captured_photos")
CAMERA_INDEX = 0          # 0 = default webcam; change for external cameras
CAPTURE_DELAY_FRAMES = 30  # warm-up frames so auto-exposure can settle

# The system prompt is long enough (>2 048 tokens) to qualify for Sonnet 4.6
# prompt caching.  It is marked ephemeral so the first call writes the cache
# and every subsequent call reads it at ~10 % of the normal input-token cost.
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
# Camera capture
# ---------------------------------------------------------------------------

def capture_photo(camera_index: int = CAMERA_INDEX,
                  warmup_frames: int = CAPTURE_DELAY_FRAMES) -> tuple[bool, object]:
    """Open the webcam, discard warm-up frames, then grab one frame.

    Returns (success, frame).  frame is None on failure.
    """
    print(f"[camera] Opening camera index {camera_index} …")
    cap = cv2.VideoCapture(camera_index)

    if not cap.isOpened():
        print(f"[error] Could not open camera {camera_index}.", file=sys.stderr)
        return False, None

    # Discard warm-up frames so auto-exposure / white-balance can settle.
    print(f"[camera] Warming up ({warmup_frames} frames) …", end="", flush=True)
    for _ in range(warmup_frames):
        cap.read()
    print(" done.")

    ret, frame = cap.read()
    cap.release()

    if not ret or frame is None:
        print("[error] Failed to capture frame.", file=sys.stderr)
        return False, None

    return True, frame


def save_photo(frame, output_dir: Path = OUTPUT_DIR) -> Path:
    """Save a captured frame as a JPEG and return its path."""
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = output_dir / f"photo_{timestamp}.jpg"
    cv2.imwrite(str(path), frame)
    print(f"[camera] Photo saved → {path}")
    return path


def show_preview(frame, timeout_ms: int = 2000) -> None:
    """Display a brief preview window (skipped in headless environments)."""
    try:
        cv2.imshow("Captured photo — press any key to continue", frame)
        cv2.waitKey(timeout_ms)
        cv2.destroyAllWindows()
    except cv2.error:
        # Headless / no display available — just skip the preview.
        pass


# ---------------------------------------------------------------------------
# Claude API
# ---------------------------------------------------------------------------

def encode_image_base64(image_path: Path) -> str:
    """Return the base64-encoded contents of an image file."""
    with open(image_path, "rb") as f:
        return base64.standard_b64encode(f.read()).decode("utf-8")


def analyse_photo(image_path: Path, user_prompt: str = "") -> str:
    """Send the photo to Claude claude-sonnet-4-6 and return the analysis text.

    The system prompt is sent with cache_control=ephemeral so the compiled
    prefix is reused on repeat calls (saves ~90 % of system-prompt token cost).
    """
    client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY from environment

    image_data = encode_image_base64(image_path)
    media_type = "image/jpeg"

    question = user_prompt.strip() or (
        "Please analyse this photo in detail following your structured format."
    )

    print(f"[claude] Sending photo to {MODEL} …")

    response = client.messages.create(
        model=MODEL,
        max_tokens=2048,
        # --- System prompt with prompt caching ---
        # cache_control marks the end of the cacheable prefix.  Sonnet 4.6
        # requires ≥ 2 048 tokens to create a cache entry; this prompt
        # comfortably exceeds that threshold.
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
                    {
                        "type": "text",
                        "text": question,
                    },
                ],
            }
        ],
    )

    # Log cache usage so the user can verify caching is working.
    usage = response.usage
    print(
        f"[claude] Tokens — input: {usage.input_tokens}, "
        f"cache write: {getattr(usage, 'cache_creation_input_tokens', 0)}, "
        f"cache read: {getattr(usage, 'cache_read_input_tokens', 0)}, "
        f"output: {usage.output_tokens}"
    )

    text_blocks = [b.text for b in response.content if b.type == "text"]
    return "\n".join(text_blocks)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    # Optional: accept a custom question from the command line.
    user_prompt = " ".join(sys.argv[1:])

    # 1. Capture photo from webcam.
    success, frame = capture_photo()
    if not success:
        sys.exit(1)

    # 2. Show a brief preview (no-op in headless environments).
    show_preview(frame)

    # 3. Save the photo to disk.
    image_path = save_photo(frame)

    # 4. Send to Claude for analysis.
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

    # 5. Display the result.
    print("\n" + "=" * 70)
    print("CLAUDE'S ANALYSIS")
    print("=" * 70)
    print(analysis)
    print("=" * 70)
    print(f"\nPhoto saved at: {image_path.resolve()}")


if __name__ == "__main__":
    main()
