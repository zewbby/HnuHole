"""Synthetic-only validation and deterministic fixtures for Go HTTP/SQL tests."""
import hashlib
import io
import json
from pathlib import Path
import sys
import unittest

from PIL import Image
from validate_image import inspect


def sample(fmt, animated=False, **kwargs):
    first = Image.new("RGB", (3, 2), "red")
    out = io.BytesIO()
    if animated:
        second = Image.new("RGB", (3, 2), "blue")
        first.save(out, format=fmt, save_all=True, append_images=[second],
                   duration=[80, 120], loop=2, **kwargs)
    else:
        first.save(out, format=fmt, **kwargs)
    return out.getvalue()


class ValidatorTests(unittest.TestCase):
    def test_all_original_formats_and_frames(self):
        for fmt in ("JPEG", "PNG", "GIF", "WEBP"):
            with self.subTest(format=fmt):
                data = sample(fmt)
                self.assertEqual(inspect(data)["frames"], 1)
                self.assertEqual(inspect(data)["sha256"], hashlib.sha256(data).hexdigest())
        for fmt in ("GIF", "WEBP"):
            with self.subTest(animation=fmt):
                data = sample(fmt, True)
                metadata = inspect(data)
                self.assertEqual(metadata["frames"], 2)
                self.assertTrue(metadata["animated"])
                self.assertEqual(metadata["byteLength"], len(data))

    def test_truncated_and_fake_images(self):
        for data in (b"", b"https://example.invalid/a.jpg", b"<svg></svg>",
                     *(sample(fmt)[:-1] for fmt in ("JPEG", "PNG", "GIF", "WEBP")),
                     sample("WEBP", True)[:-2]):
            with self.subTest(length=len(data)):
                with self.assertRaises(Exception):
                    inspect(data)

    def test_real_orientation_without_reencoding(self):
        exif = Image.Exif()
        exif[274] = 6
        result = inspect(sample("JPEG", exif=exif))
        self.assertEqual((result["width"], result["height"]), (3, 2))
        self.assertEqual((result["displayWidth"], result["displayHeight"]), (2, 3))

    def test_unsupported_animation_and_work_limits(self):
        with self.assertRaises(ValueError):
            inspect(sample("PNG", True))
        first = Image.new("RGB", (3, 2), "red")
        out = io.BytesIO()
        first.save(out, format="GIF", save_all=True,
                   append_images=[Image.new("RGB", (3, 2), (i % 255, 3, 9)) for i in range(301)],
                   duration=20)
        with self.assertRaises(ValueError):
            inspect(out.getvalue())


def fixtures(directory):
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    for fmt in ("PNG", "JPEG", "GIF", "WEBP"):
        data = sample(fmt, animated=fmt in ("GIF", "WEBP"))
        (directory / (fmt.lower() + ".bin")).write_bytes(data)
        (directory / (fmt.lower() + ".json")).write_text(json.dumps(inspect(data)), encoding="utf-8")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--fixtures"]:
        fixtures(Path(sys.argv[2]))
    else:
        unittest.main()
