"""Bounded server-side inspection. Writes metadata only; never rewrites bytes.

Run with a task-owned Python environment and Pillow from requirements.txt.
Input is stdin, never a URL or user-supplied filesystem path. No temp image,
shell, network fetch, or persistent image cache is involved.
"""
import hashlib
import io
import json
import resource
import sys
import warnings

if __name__ == "__main__":
    resource.setrlimit(resource.RLIMIT_AS, (384 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (5, 5))
    resource.setrlimit(resource.RLIMIT_FSIZE, (0, 0))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

from PIL import Image, ImageFile, features, __version__  # noqa: E402

MAX_BYTES = 10 * 1024 * 1024
MAX_PIXELS = 12 * 1024 * 1024
MAX_ANIMATION_PIXELS = 1024 * 1024
MAX_WORK = 16 * 1024 * 1024
MAX_FRAMES = 120
Image.MAX_IMAGE_PIXELS = MAX_PIXELS
ImageFile.LOAD_TRUNCATED_IMAGES = False
warnings.simplefilter("error")


def inspect(data):
    if not 0 < len(data) <= MAX_BYTES:
        raise ValueError("size")
    formats = ["JPEG", "PNG", "GIF", "WEBP"]
    with Image.open(io.BytesIO(data), formats=formats) as image:
        fmt = image.format
        width, height = image.size
        if not (0 < width <= 16384 and 0 < height <= 16384):
            raise ValueError("dimensions")
        pixels = width * height
        if pixels > MAX_PIXELS:
            raise ValueError("pixels")
        # APNG is deliberately rejected until the viewer format contract covers
        # it; never accept an animation and silently expose only its first frame.
        if fmt == "PNG" and getattr(image, "is_animated", False):
            raise ValueError("APNG not in v1")
        orientation = image.getexif().get(274, 1)
        if orientation not in range(1, 9):
            raise ValueError("orientation")
        frames = 0
        cycle_duration = 0
        max_frame_duration = 0
        while True:
            try:
                image.seek(frames)
            except EOFError:
                break
            frames += 1
            if frames > MAX_FRAMES or (frames > 1 and
                                      (pixels > MAX_ANIMATION_PIXELS or pixels * frames > MAX_WORK)):
                raise ValueError("animation work")
            image.load()  # decode every frame using Pillow/libwebp, not headers
            duration = float(image.info.get("duration", 0))
            if duration < 0 or duration > 15000:
                raise ValueError("frame duration")
            # Conservative budget for short/zero delays which engines may
            # normalize. Original duration/loop bytes are never modified.
            duration = max(duration, 100)
            cycle_duration += duration
            max_frame_duration = max(max_frame_duration, duration)
            if cycle_duration > 60000:
                raise ValueError("cycle duration")
        if not frames:
            raise ValueError("no frames")
    # PNG.verify checks all chunk CRCs; re-open because load/seek consumed it.
    if fmt == "PNG":
        with Image.open(io.BytesIO(data), formats=["PNG"]) as image:
            image.verify()
    # Reject clearly truncated containers even when a decoder tolerates EOF.
    if fmt == "JPEG" and not data.endswith(b"\xff\xd9"):
        raise ValueError("JPEG terminator")
    if fmt == "GIF" and not data.endswith(b";"):
        raise ValueError("GIF terminator")
    if fmt == "PNG" and not data.endswith(b"\x00\x00\x00\x00IEND\xaeB`\x82"):
        raise ValueError("PNG terminator")
    if fmt == "WEBP" and (data[:4] != b"RIFF" or data[8:12] != b"WEBP" or
                          int.from_bytes(data[4:8], "little") + 8 != len(data)):
        raise ValueError("WebP container length")
    display_width, display_height = width, height
    if orientation in (5, 6, 7, 8):
        display_width, display_height = height, width
    return {"mimeType": Image.MIME[fmt], "width": width, "height": height,
            "displayWidth": display_width, "displayHeight": display_height,
            "frames": frames, "animated": frames > 1,
            "sha256": hashlib.sha256(data).hexdigest(), "byteLength": len(data),
            "cycleDurationMs": int(cycle_duration) if frames > 1 else 0,
            "maxFrameDurationMs": int(max_frame_duration) if frames > 1 else 0}


def main():
    if __version__ != "12.3.0" or not features.check("webp"):
        return 3
    if sys.argv[1:] == ["--probe"]:
        print("postmedia-validator/v1")
        return 0
    if sys.argv[1:]:
        return 3
    try:
        result = inspect(sys.stdin.buffer.read(MAX_BYTES + 1))
    except Exception:
        return 2  # no byte, metadata, filename or exception details in logs
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
