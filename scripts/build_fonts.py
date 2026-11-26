#!/usr/bin/env python3
"""
CoreType Font Engineering Pipeline
Transforms official Apple SF-Pro.ttf & SF-Pro-Italic.ttf into Android & HyperOS
optical-calibrated variable fonts:
  1. Subsets out Apple-only Private Use Area (SF Symbols) to cut RAM & boot time
     (~20 MB -> ~1.5 MB) while preserving full Latin, Extended Latin, Vietnamese,
     Greek, Cyrillic, Math, Currency, Punctuation, and OpenType features.
  2. Shifts Variable Font default origin from opsz=28.0 (Display) to opsz=17.0
     (Text) and wdth=100.0 to wdth=95.5 (Roboto/MiSans optical width match)
     while keeping full wght/opsz/wdth variable axes intact for XML mapping.
  3. Calibrates hhea & OS/2 vertical metrics to match Android/HyperOS baselines
     (ascent=1900, descent=-500, lineGap=0) for pixel-accurate UI alignment.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

SF_PRO_DMG_URL = "https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg"

# Unicode ranges to preserve (drops Apple PUA SF Symbols U+E000-F8FF, U+F0000+)
KEEP_UNICODES = (
    list(range(0x0000, 0x0530))    # Basic Latin, Latin-1, Ext-A/B, IPA, Greek, Cyrillic
    + list(range(0x1E00, 0x27FF))  # Latin Ext Additional (Vietnamese), Punctuation, Currency, Arrows, Math, Box, Misc Symbols
    + list(range(0x2E00, 0x2E7F))  # Supplemental Punctuation
    + list(range(0xFB00, 0xFB06))  # Standard Latin ligatures
    + [0xFEFF, 0xFFFC, 0xFFFD]     # BOM, Object Replacement, Replacement Char
)

# Android Roboto / HyperOS MiSans baseline vertical metrics (at UPM 2048)
ANDROID_ASCENT = 1900
ANDROID_DESCENT = -500
ANDROID_LINE_GAP = 0
ANDROID_WIN_ASCENT = 1946
ANDROID_WIN_DESCENT = 512


def run_cmd(cmd, cwd=None):
    res = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Command failed ({res.returncode}): {' '.join(cmd)}\n{res.stderr}")
    return res.stdout


def extract_sf_pro(dmg_path: Path, extract_dir: Path) -> Path:
    """Extract SF-Pro.ttf and SF-Pro-Italic.ttf from Apple's official SF-Pro.dmg."""
    extract_dir.mkdir(parents=True, exist_ok=True)
    print(f"[CoreType] Extracting {dmg_path.name} ...")
    run_cmd(["7z", "x", "-y", str(dmg_path)], cwd=extract_dir)

    pkg_candidates = list(extract_dir.rglob("*.pkg"))
    if not pkg_candidates:
        raise FileNotFoundError("Could not find SFProFonts.pkg inside SF-Pro.dmg")
    pkg_path = pkg_candidates[0]
    print(f"[CoreType] Extracting {pkg_path.name} ...")
    run_cmd(["7z", "x", "-y", str(pkg_path)], cwd=extract_dir)

    payload_candidates = list(extract_dir.rglob("Payload~")) + list(extract_dir.rglob("Payload"))
    if not payload_candidates:
        raise FileNotFoundError("Could not find Payload inside SFProFonts.pkg")
    payload_path = payload_candidates[0]

    payload_dir = extract_dir / "payload"
    payload_dir.mkdir(exist_ok=True)
    print(f"[CoreType] Unpacking {payload_path.name} ...")
    run_cmd(["7z", "x", "-y", str(payload_path)], cwd=payload_dir)

    fonts_dir = payload_dir / "Library" / "Fonts"
    if not (fonts_dir / "SF-Pro.ttf").exists():
        raise FileNotFoundError(f"SF-Pro.ttf not found in {fonts_dir}")
    return fonts_dir


def subset_font(font: TTFont) -> None:
    """Strip Apple-only Private Use Area glyphs while keeping all scripts & OT features."""
    opts = Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.name_legacy = True
    opts.name_languages = ["*"]
    opts.notdef_outline = True
    opts.drop_tables += ["DSIG"]
    opts.hinting = True
    subsetter = Subsetter(options=opts)
    subsetter.populate(unicodes=KEEP_UNICODES)
    subsetter.subset(font)


def calibrate_vertical_metrics(font: TTFont) -> None:
    """Align hhea & OS/2 vertical metrics to Android Roboto / HyperOS MiSans baseline."""
    hhea = font["hhea"]
    hhea.ascent = ANDROID_ASCENT
    hhea.descent = ANDROID_DESCENT
    hhea.lineGap = ANDROID_LINE_GAP

    os2 = font["OS/2"]
    os2.sTypoAscender = ANDROID_ASCENT
    os2.sTypoDescender = ANDROID_DESCENT
    os2.sTypoLineGap = ANDROID_LINE_GAP
    os2.usWinAscent = ANDROID_WIN_ASCENT
    os2.usWinDescent = ANDROID_WIN_DESCENT
    # Set USE_TYPO_METRICS (bit 7) so Android/Skia honors Typo metrics consistently
    os2.fsSelection |= 1 << 7


def set_name_records(font: TTFont, family: str, subfamily: str, ps_name: str) -> None:
    """Stamp clean CoreType naming records for Android font_fallback.xml postScriptName matching."""
    name_table = font["name"]
    full_name = f"{family} {subfamily}" if subfamily != "Regular" else family
    records = {
        1: family,
        2: subfamily,
        4: full_name,
        6: ps_name,
        16: family,
        17: subfamily,
    }
    for name_id, value in records.items():
        name_table.setName(value, name_id, 3, 1, 0x0409)  # Windows Unicode BMP en-US
        name_table.setName(value, name_id, 1, 0, 0)       # Mac Roman English


def build_variable_font(src_path: Path, out_path: Path, is_italic: bool) -> None:
    """Process one SF Pro variable font (upright or italic)."""
    print(f"[CoreType] Loading {src_path.name} ...")
    font = TTFont(str(src_path))
    orig_glyphs = len(font.getGlyphOrder())

    print(f"[CoreType] Subsetting {src_path.name} ({orig_glyphs} glyphs) ...")
    subset_font(font)
    sub_glyphs = len(font.getGlyphOrder())
    print(f"[CoreType]   -> kept {sub_glyphs} glyphs (dropped {orig_glyphs - sub_glyphs} Apple PUA/unused glyphs)")

    # Shift default origin to opsz=17.0 (Text) and calibrated wdth=91.0 (Upright)
    # while keeping full variable axes intact for progressive opsz XML mapping!
    axis_limits = {"opsz": (17.0, 17.0, 28.0)}
    if not is_italic:
        axis_limits["wdth"] = (30.0, 91.0, 150.0)
    else:
        # Pin Apple-internal YAXS axis if present in SF-Pro-Italic.ttf
        if "fvar" in font and any(a.axisTag == "YAXS" for a in font["fvar"].axes):
            axis_limits["YAXS"] = 400.0

    print(f"[CoreType] Recalibrating variable default origin: {axis_limits} ...")
    font = instantiateVariableFont(font, axis_limits, inplace=True)

    print("[CoreType] Calibrating vertical metrics (Android 1900/-500) ...")
    calibrate_vertical_metrics(font)

    if is_italic:
        set_name_records(font, "CoreType SF Pro", "Italic", "CoreTypeSFPro-Italic")
    else:
        set_name_records(font, "CoreType SF Pro", "Regular", "CoreTypeSFPro-Regular")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    font.save(str(out_path))
    size_kb = out_path.stat().st_size / 1024.0
    axes_summary = [
        f"{a.axisTag}({a.minValue:.0f}..{a.defaultValue:.1f}..{a.maxValue:.0f})"
        for a in font["fvar"].axes
    ]
    print(f"[CoreType] Wrote {out_path.name} ({size_kb:.1f} KB) | axes: {', '.join(axes_summary)}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build CoreType optical-calibrated SF Pro variable fonts.")
    parser.add_argument("--src-fonts-dir", type=Path, help="Path to already-extracted Apple Library/Fonts directory")
    parser.add_argument("--dmg", type=Path, help="Path to local SF-Pro.dmg (if omitted, downloads from Apple CDN)")
    parser.add_argument("--out-dir", type=Path, required=True, help="Output directory for CoreType-*.ttf")
    args = parser.parse_args()

    tmp_dir = None
    try:
        if args.src_fonts_dir:
            fonts_dir = args.src_fonts_dir
        else:
            tmp_dir = Path(tempfile.mkdtemp(prefix="coretype_build_"))
            dmg_path = args.dmg
            if dmg_path is None:
                dmg_path = tmp_dir / "SF-Pro.dmg"
                print(f"[CoreType] Downloading official SF-Pro.dmg from Apple CDN ...")
                run_cmd(["curl", "-fsSL", "-o", str(dmg_path), SF_PRO_DMG_URL])
            fonts_dir = extract_sf_pro(dmg_path, tmp_dir / "extract")

        build_variable_font(
            fonts_dir / "SF-Pro.ttf",
            args.out_dir / "CoreType-SFPro.ttf",
            is_italic=False,
        )
        build_variable_font(
            fonts_dir / "SF-Pro-Italic.ttf",
            args.out_dir / "CoreType-SFPro-Italic.ttf",
            is_italic=True,
        )
        print("[CoreType] Font build complete!")
        return 0
    finally:
        if tmp_dir and tmp_dir.exists():
            shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
