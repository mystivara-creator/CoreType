#!/usr/bin/env python3
"""
CoreType Apple iOS Emoji Fetcher & Android CBDT/CBLC Verifier
Downloads the Android-compatible CBDT/CBLC Apple Color Emoji binary (iOS 26.4)
and verifies table integrity via fontTools before packaging CoreType Full edition.
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

from fontTools.ttLib import TTFont

DEFAULT_EMOJI_ZIP_URL = (
    "https://github.com/Keinta15/Magisk-iOS-Emoji/releases/download/"
    "v26.4/Magisk_iOS_Emoji_26.4.zip"
)


def verify_android_emoji(ttf_path: Path) -> None:
    """Confirm the emoji TTF contains valid Android Skia/FreeType CBDT+CBLC bitmap tables."""
    with TTFont(str(ttf_path)) as font:
        required = {"CBDT", "CBLC", "cmap", "head", "hhea", "hmtx", "maxp", "OS/2"}
        missing = required - set(font.keys())
        if missing:
            raise RuntimeError(f"Emoji font missing required Android tables: {sorted(missing)}")

        strikes = [(s.bitmapSizeTable.ppemX, s.bitmapSizeTable.ppemY) for s in font["CBLC"].strikes]
        glyphs = len(font.getGlyphOrder())
        size_mb = ttf_path.stat().st_size / (1024.0 * 1024.0)
        if glyphs < 3000 or not strikes:
            raise RuntimeError(f"Invalid emoji font: glyphs={glyphs}, strikes={strikes}")

        print(
            f"[CoreType] Verified Apple Color Emoji ({size_mb:.1f} MB) | "
            f"glyphs={glyphs} | CBDT/CBLC strikes={strikes}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch & verify Apple Color Emoji for CoreType Full.")
    parser.add_argument("--url", default=DEFAULT_EMOJI_ZIP_URL, help="Source zip URL containing NotoColorEmoji.ttf")
    parser.add_argument("--out", type=Path, required=True, help="Output path (e.g. fonts/CoreType-AppleEmoji.ttf)")
    args = parser.parse_args()

    tmp_dir = Path(tempfile.mkdtemp(prefix="coretype_emoji_"))
    try:
        zip_path = tmp_dir / "emoji.zip"
        print("[CoreType] Downloading Android CBDT/CBLC Apple Color Emoji ...")
        res = subprocess.run(
            [
                "curl", "-fsSL",
                "--retry", "3",
                "--retry-delay", "5",
                "--connect-timeout", "30",
                "--max-time", "600",
                "-o", str(zip_path),
                args.url,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if res.returncode != 0:
            raise RuntimeError(f"Download failed: {res.stderr}")

        with zipfile.ZipFile(zip_path, "r") as zf:
            candidates = [
                n for n in zf.namelist()
                if not n.startswith("__MACOSX/") and Path(n).name == "NotoColorEmoji.ttf"
            ]
            if not candidates:
                raise FileNotFoundError("NotoColorEmoji.ttf not found inside emoji archive")
            args.out.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(candidates[0]) as src, open(args.out, "wb") as dst:
                shutil.copyfileobj(src, dst)

        verify_android_emoji(args.out)
        return 0
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
