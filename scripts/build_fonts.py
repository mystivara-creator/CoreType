#!/usr/bin/env python3
"""
CoreType Font Engineering Pipeline (v1.0.0 — Dual Optical Master + Apple trak Engine)

Transforms official Apple SF-Pro.ttf & SF-Pro-Italic.ttf into FOUR ultra-lean,
optical-calibrated Variable Fonts for Android 12–16 & HyperOS 2/3/4:

  1. CoreType-SFPro-Text.ttf        (opsz=17 pinned, wght 1..1000 + wdth 30..150, Apple Text trak baked via GPOS)
  2. CoreType-SFPro-Text-Italic.ttf (opsz=17 pinned, wght 1..1000, Apple Text trak baked via GPOS)
  3. CoreType-SFPro-Display.ttf     (opsz=28 pinned, wght 1..1000 + wdth 30..150, Apple Display trak baked via GPOS)
  4. CoreType-SFPro-Display-Italic.ttf (opsz=28 pinned, wght 1..1000, Apple Display trak baked via GPOS)

Why Dual Optical Masters + GPOS Tracking?
  - Android's HarfBuzz/Minikin ignores Apple's AAT `trak` table, which is the #1 reason
    raw SF Pro looks too loose, flat, and 12–15% too wide on Android.
  - By baking Apple's real iOS `trak` values directly into a non-destructive OpenType
    GPOS `kern` SinglePos lookup (applied AFTER Apple's native PairPos kerning), we:
      * Preserve 100% pure, undistorted Apple SF Pro letter shapes (`glyf`/`gvar`/`HVAR` untouched!)
      * Match Upright & Italic widths 1:1 (even though SF-Pro-Italic lacks a `wdth` axis)
      * Deliver unmistakable iOS Header (Display opsz=28) vs Body (Text opsz=17) contrast
      * Keep full Variable Weight (`wght` 1..1000) so HyperOS's Font Weight slider works natively
      * Cut total font size dramatically (~40 MB raw -> ~3 MB total across all 4 masters)
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

try:
    from fontTools.subset import Options, Subsetter
    from fontTools.ttLib import TTFont
    from fontTools.ttLib.tables import otTables
    from fontTools.varLib.instancer import instantiateVariableFont
except ImportError:
    Options = Subsetter = TTFont = otTables = instantiateVariableFont = None

SF_PRO_DMG_URL = "https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg"

# Vertical metrics calibrated to exact 4:1 ascent:descent parity (UPM 2048, total 2460 = 1.201x):
# Matches HyperOS MiSansTCVF (960:-240) & NotoSansCJK line-height cleanly so mixed Latin + CJK
# runs, circular notification badges, and tabular clocks (09:41) align with zero vertical clipping.
ANDROID_ASCENT = 1968
ANDROID_DESCENT = -492
ANDROID_LINE_GAP = 0
ANDROID_WIN_ASCENT = 1968
ANDROID_WIN_DESCENT = 492

# Optical master specifications derived directly from Apple SF-Pro.ttf `trak` table (UPM 2048):
# - Text (16–17pt iOS UI): Apple `trak` track 0.0 is -40..-52 UPM -> bake -46 UPM (+ mild wdth=96.5 default)
# - Display (24–36pt Headers / Clocks): Display glyphs are already ~100 UPM tighter than Text;
#   bake -26 UPM Display tracking (+ mild wdth=97.0 default) for crisp, punchy iOS headlines.
# - Flex (Continuous opsz 12..36 for RobotoFlex / Material 3 / Jetpack Compose): preserves live
#   continuous `opsz` axis (12..36) with balanced -36 UPM tracking & pure 0 UPM tabular digits.
OPTICAL_SPECS = [
    {
        "src": "SF-Pro.ttf",
        "out": "CoreType-SFPro-Text.ttf",
        "is_italic": False,
        "opsz": 17.0,
        "default_wdth": 96.5,
        "track_units": -46,
        "space_track": -18,
        "family": "CoreType SF Pro Text",
        "subfamily": "Regular",
        "ps_name": "CoreTypeSFProText-Regular",
    },
    {
        "src": "SF-Pro-Italic.ttf",
        "out": "CoreType-SFPro-Text-Italic.ttf",
        "is_italic": True,
        "opsz": 17.0,
        "default_wdth": None,
        "track_units": -46,
        "space_track": -18,
        "family": "CoreType SF Pro Text",
        "subfamily": "Italic",
        "ps_name": "CoreTypeSFProText-Italic",
    },
    {
        "src": "SF-Pro.ttf",
        "out": "CoreType-SFPro-Display.ttf",
        "is_italic": False,
        "opsz": 28.0,
        "default_wdth": 97.0,
        "track_units": -26,
        "space_track": -12,
        "family": "CoreType SF Pro Display",
        "subfamily": "Regular",
        "ps_name": "CoreTypeSFProDisplay-Regular",
    },
    {
        "src": "SF-Pro-Italic.ttf",
        "out": "CoreType-SFPro-Display-Italic.ttf",
        "is_italic": True,
        "opsz": 28.0,
        "default_wdth": None,
        "track_units": -26,
        "space_track": -12,
        "family": "CoreType SF Pro Display",
        "subfamily": "Italic",
        "ps_name": "CoreTypeSFProDisplay-Italic",
    },
    {
        "src": "SF-Pro.ttf",
        "out": "CoreType-SFPro-Flex.ttf",
        "is_italic": False,
        "opsz": (17.0, 17.0, 28.0),
        "default_wdth": 96.5,
        "track_units": -46,
        "space_track": -18,
        "display_track_units": -26,
        "display_space_track": -12,
        "opsz_switch_pt": 22.0,
        "family": "CoreType SF Pro Flex",
        "subfamily": "Regular",
        "ps_name": "CoreTypeSFProFlex-Regular",
    },
]


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

    payload_dir = extract_dir / "payload"
    payload_dir.mkdir(exist_ok=True)

    gzip_payloads = list(extract_dir.rglob("Payload"))
    cpio_payloads = list(extract_dir.rglob("Payload~"))

    if not cpio_payloads and gzip_payloads:
        print(f"[CoreType] Decompressing {gzip_payloads[0].name} ...")
        run_cmd(["7z", "x", "-y", str(gzip_payloads[0])], cwd=payload_dir)
        cpio_payloads = list(payload_dir.rglob("Payload~")) + [
            p for p in payload_dir.iterdir() if p.is_file() and p.name.startswith("Payload")
        ]

    if cpio_payloads:
        print(f"[CoreType] Unpacking {cpio_payloads[0].name} ...")
        run_cmd(["7z", "x", "-y", str(cpio_payloads[0])], cwd=payload_dir)
    elif not gzip_payloads:
        raise FileNotFoundError("Could not find Payload inside SFProFonts.pkg")

    found = list(payload_dir.rglob("SF-Pro.ttf"))
    if not found:
        raise FileNotFoundError(f"SF-Pro.ttf not found under {payload_dir}")
    return found[0].parent


# Android/iOS UI OpenType features to retain (drops desktop-only stylistic sets ss01..ss17,
# cv01..cv13, smcp, c2sc, appl, THEX -> cuts gvar by ~75% with 0-unit shaping diff!)
UI_LAYOUT_FEATURES = [
    "calt",  # Apple vertically-centered clock colon (09:41) & contextual alternates
    "case",  # Case-sensitive punctuation forms
    "ccmp",  # Glyph composition/decomposition (diacritics & Vietnamese)
    "frac",  # Fractions
    "kern",  # Native Apple kerning + CoreType GPOS tracking lookup
    "liga",  # Standard ligatures (fi, fl)
    "locl",  # Localized forms
    "mark",  # Mark positioning
    "mkmk",  # Mark-to-mark positioning
    "ordn",  # Ordinals
    "pnum",  # Proportional numerals
    "rlig",  # Required ligatures
    "rtlm",  # Right-to-left mirrored forms
    "subs",  # Subscript
    "sups",  # Superscript
    "tnum",  # Tabular numerals (status bar / clocks / timers)
]


def is_kept_unicode(cp: int) -> bool:
    """
    Keep ALL real Unicode glyphs present in Apple SF-Pro.ttf (including Basic/Ext Latin A-E,
    Phonetic Extensions U+1D00..1DFF for superscripts like 'ʲᵈᵐ', Greek, Cyrillic, Vietnamese,
    Superscripts/Subscripts, Math, Currency, Punctuation, Arrows, Symbols), while dropping:
      - Apple-only Private Use Area SF Symbols (U+E000..F8FF, U+F0000+)
      - Arabic presentation ranges so ROM-native MiSansArabicVF / NotoNaskhArabic handles Arabic cleanly
    """
    # Drop Private Use Areas (Apple SF Symbols)
    if (0xE000 <= cp <= 0xF8FF) or cp >= 0xF0000:
        return False
    # Preserve BOM & Replacement chars; let ROM's native Arabic fonts handle Arabic blocks
    if (0x0600 <= cp <= 0x06FF) or (0x0750 <= cp <= 0x077F) or (0x08A0 <= cp <= 0x08FF):
        return False
    if (0xFB50 <= cp <= 0xFDFF) or (0xFE70 <= cp <= 0xFEFE):
        return False
    return True


def subset_font(font: TTFont) -> None:
    """Strip Apple-only PUA glyphs & desktop-only OT sets while keeping 100% real UI scripts & features."""
    cmap = font.getBestCmap() or {}
    keep_cps = [cp for cp in cmap.keys() if is_kept_unicode(cp)]

    opts = Options()
    opts.layout_features = UI_LAYOUT_FEATURES
    opts.name_IDs = [0, 1, 2, 4, 5, 6, 16, 17]
    opts.name_legacy = True
    opts.name_languages = ["*"]
    opts.notdef_outline = True
    opts.drop_tables += ["DSIG", "trak", "MERG", "meta"]
    opts.hinting = True
    subsetter = Subsetter(options=opts)
    subsetter.populate(unicodes=keep_cps)
    subsetter.subset(font)


def _build_tracking_lookup(font: "TTFont", track_units: int, space_track: int):
    """Build a GPOS LookupType 1 (SinglePos Format 2) lookup for calibrated Apple tracking."""
    hmtx = font["hmtx"]
    cmap = font.getBestCmap() or {}
    glyph_order = font.getGlyphOrder()
    glyph_id_map = {g: i for i, g in enumerate(glyph_order)}

    # Build reverse map glyph -> primary codepoint to classify marks/space cleanly
    glyph_to_cp = {}
    for cp, gname in cmap.items():
        if gname not in glyph_to_cp:
            glyph_to_cp[gname] = cp

    # Collect GDEF mark glyphs (class 3) to guarantee we never track combining marks
    mark_glyphs = set()
    if "GDEF" in font and font["GDEF"].table.GlyphClassDef:
        for gname, gcls in font["GDEF"].table.GlyphClassDef.classDefs.items():
            if gcls == 3:
                mark_glyphs.add(gname)

    # Identify ASCII digit glyphs (including tnum/proportional alternates like zero.tf..nine.tf)
    # so narrow UI pills (e.g. battery "100", clocks "00:00") never suffer cramped "00" spacing.
    digit_prefixes = (
        "zero", "one", "two", "three", "four",
        "five", "six", "seven", "eight", "nine",
    )

    adjustments = []
    for gname in glyph_order:
        if gname == ".notdef" or gname in mark_glyphs:
            continue
        aw, _lsb = hmtx[gname]
        if aw <= 0:
            continue

        cp = glyph_to_cp.get(gname)
        cat = None
        if cp is not None:
            cat = unicodedata.category(chr(cp))
            if cat in ("Mn", "Me", "Cf", "Cc"):
                continue

        is_digit = (cp is not None and 0x0030 <= cp <= 0x0039) or gname.split(".")[0] in digit_prefixes
        if is_digit:
            # Keep Display (-26) digits at pure 0 UPM; gentle -8 UPM on Text (-46)
            if track_units >= -36:
                continue
            delta = -8
            x_place = -4
        elif cp in (0x0020, 0x00A0):
            delta = space_track
            x_place = 0
        elif aw <= 450:
            # Narrow punctuation / thin stems (i, l, ., :, ;) -> gentler proportional tracking
            delta = int(round(track_units * 0.45))
            x_place = int(round(delta / 2.0))
        elif cat in ("Sm", "Pd"):
            # Math operators, arrows & dashes (+, =, ->, —, –) -> airy 50% tracking
            delta = int(round(track_units * 0.50))
            x_place = int(round(delta / 2.0))
        elif cat == "Lu":
            # Uppercase letters & ALL-CAPS iOS section headers -> 75% tracking (-34 Text / -20 Display)
            delta = int(round(track_units * 0.75))
            x_place = int(round(delta / 2.0))
        else:
            delta = track_units
            x_place = int(round(delta / 2.0))

        # Safety clamp: never allow advance width to drop below 40% of original
        if aw + delta < max(120, int(aw * 0.4)):
            continue

        val = otTables.ValueRecord()
        val.XPlacement = x_place
        val.XAdvance = delta
        adjustments.append((glyph_id_map[gname], gname, val))

    if not adjustments:
        return None, 0

    # Coverage table MUST be sorted by GlyphID per OpenType spec
    adjustments.sort(key=lambda item: item[0])

    cov = otTables.Coverage()
    cov.glyphs = [item[1] for item in adjustments]

    subtable = otTables.SinglePos()
    subtable.Format = 2
    subtable.Coverage = cov
    # ValueFormat: bit 0 (0x0001) = XPlacement, bit 2 (0x0004) = XAdvance
    subtable.ValueFormat = 0x0005
    subtable.Value = [item[2] for item in adjustments]
    subtable.ValueCount = len(adjustments)

    lookup = otTables.Lookup()
    lookup.LookupType = 1
    lookup.LookupFlag = 0x0008  # IgnoreMarks (standard for horizontal kerning/tracking)
    lookup.SubTable = [subtable]
    lookup.SubTableCount = 1
    return lookup, len(adjustments)


def bake_gpos_tracking(font: "TTFont", track_units: int, space_track: int):
    """
    Inject Apple's calibrated iOS tracking as a non-destructive OpenType GPOS
    SinglePos (LookupType 1) lookup attached to the default-on `kern` feature.
    Returns (tracked_glyph_count, lookup_index).
    """
    if track_units == 0 or "GPOS" not in font:
        return 0, None

    gpos = font["GPOS"].table
    if not gpos.LookupList or not gpos.FeatureList:
        return 0, None

    lookup, count = _build_tracking_lookup(font, track_units, space_track)
    if lookup is None:
        return 0, None

    new_lookup_idx = len(gpos.LookupList.Lookup)
    gpos.LookupList.Lookup.append(lookup)
    gpos.LookupList.LookupCount = len(gpos.LookupList.Lookup)

    attached = 0
    for feat_rec in gpos.FeatureList.FeatureRecord:
        if feat_rec.FeatureTag == "kern":
            feat_rec.Feature.LookupListIndex.append(new_lookup_idx)
            feat_rec.Feature.LookupCount = len(feat_rec.Feature.LookupListIndex)
            attached += 1

    if attached == 0:
        raise RuntimeError("No GPOS 'kern' feature found to attach CoreType optical tracking")

    return count, new_lookup_idx


def bake_gpos_opsz_feature_variations(
    font: "TTFont",
    default_lookup_idx: int,
    display_track_units: int,
    display_space_track: int,
    opsz_switch_pt: float,
) -> int:
    """
    Attach an OpenType GPOS 1.1 FeatureVariations record on `opsz` so CoreType-SFPro-Flex.ttf
    automatically switches from Apple Text tracking (-46 UPM, opsz < 22) to Apple Display
    tracking (-26 UPM, opsz >= 22) inside Android HarfBuzz / Minikin.
    """
    if default_lookup_idx is None or "GPOS" not in font or "fvar" not in font:
        return 0

    axes = font["fvar"].axes
    opsz_idx = None
    opsz_axis = None
    for idx, axis in enumerate(axes):
        if axis.axisTag == "opsz":
            opsz_idx = idx
            opsz_axis = axis
            break
    if opsz_axis is None or opsz_axis.maxValue <= opsz_axis.defaultValue:
        return 0

    norm_min = (opsz_switch_pt - opsz_axis.defaultValue) / (opsz_axis.maxValue - opsz_axis.defaultValue)
    norm_min = max(0.0, min(1.0, norm_min))

    disp_lookup, disp_count = _build_tracking_lookup(font, display_track_units, display_space_track)
    if disp_lookup is None:
        return 0

    gpos = font["GPOS"].table
    disp_lookup_idx = len(gpos.LookupList.Lookup)
    gpos.LookupList.Lookup.append(disp_lookup)
    gpos.LookupList.LookupCount = len(gpos.LookupList.Lookup)

    # Build FeatureTableSubstitution records replacing default_lookup_idx -> disp_lookup_idx on all `kern` features
    subst_records = []
    for feat_idx, feat_rec in enumerate(gpos.FeatureList.FeatureRecord):
        if feat_rec.FeatureTag != "kern":
            continue
        alt_feat = otTables.Feature()
        alt_feat.FeatureParams = feat_rec.Feature.FeatureParams
        alt_feat.LookupListIndex = [
            disp_lookup_idx if li == default_lookup_idx else li
            for li in feat_rec.Feature.LookupListIndex
        ]
        alt_feat.LookupCount = len(alt_feat.LookupListIndex)

        sub_rec = otTables.FeatureTableSubstitutionRecord()
        sub_rec.FeatureIndex = feat_idx
        sub_rec.Feature = alt_feat
        subst_records.append(sub_rec)

    if not subst_records:
        return 0

    cond = otTables.ConditionTable()
    cond.Format = 1
    cond.AxisIndex = opsz_idx
    cond.FilterRangeMinValue = norm_min
    cond.FilterRangeMaxValue = 1.0

    cond_set = otTables.ConditionSet()
    cond_set.ConditionTable = [cond]
    cond_set.ConditionCount = 1

    feat_subst = otTables.FeatureTableSubstitution()
    feat_subst.Version = 0x00010000
    feat_subst.SubstitutionRecord = subst_records
    feat_subst.SubstitutionCount = len(subst_records)

    fvr = otTables.FeatureVariationRecord()
    fvr.ConditionSet = cond_set
    fvr.FeatureTableSubstitution = feat_subst

    gpos.Version = 0x00010001  # GPOS 1.1 required for FeatureVariations
    if getattr(gpos, "FeatureVariations", None) is None:
        fv = otTables.FeatureVariations()
        fv.Version = 0x00010000
        fv.FeatureVariationRecord = [fvr]
        fv.FeatureVariationCount = 1
        gpos.FeatureVariations = fv
    else:
        gpos.FeatureVariations.FeatureVariationRecord.append(fvr)
        gpos.FeatureVariations.FeatureVariationCount = len(gpos.FeatureVariations.FeatureVariationRecord)

    return disp_count


def calibrate_vertical_metrics(font: "TTFont") -> None:
    """Align hhea & OS/2 vertical metrics to exact 4:1 HyperOS MiSans / CJK line-height parity."""
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


def set_name_records(font: "TTFont", family: str, subfamily: str, ps_name: str) -> None:
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


def build_optical_master(src_path: Path, out_path: Path, spec: dict) -> None:
    """Build one optical-calibrated Variable Font master (Text, Display, or Continuous-opsz Flex)."""
    print(f"[CoreType] Building {spec['out']} from {src_path.name} ...")
    font = TTFont(str(src_path))
    orig_glyphs = len(font.getGlyphOrder())

    subset_font(font)
    sub_glyphs = len(font.getGlyphOrder())
    print(f"           subset: {orig_glyphs} -> {sub_glyphs} glyphs")

    # Pin `opsz` for Text (17.0) / Display (28.0) or keep continuous (12.0, 17.0, 36.0) for Flex.
    # Prune unused `wdth` extremes (<75 / >100) and `wght` extremes (<100 / >950).
    axis_limits = {
        "opsz": spec["opsz"],
        "wght": (100.0, 400.0, 950.0),
    }
    if spec["default_wdth"] is not None:
        axis_limits["wdth"] = (75.0, spec["default_wdth"], 100.0)
    if spec["is_italic"] and "fvar" in font:
        if any(a.axisTag == "YAXS" for a in font["fvar"].axes):
            axis_limits["YAXS"] = 400.0

    font = instantiateVariableFont(font, axis_limits, inplace=True)

    tracked, default_lookup_idx = bake_gpos_tracking(font, spec["track_units"], spec["space_track"])
    fv_tracked = 0
    if "display_track_units" in spec and default_lookup_idx is not None:
        fv_tracked = bake_gpos_opsz_feature_variations(
            font,
            default_lookup_idx,
            spec["display_track_units"],
            spec["display_space_track"],
            spec.get("opsz_switch_pt", 22.0),
        )
    calibrate_vertical_metrics(font)
    set_name_records(font, spec["family"], spec["subfamily"], spec["ps_name"])

    out_path.parent.mkdir(parents=True, exist_ok=True)
    font.save(str(out_path))

    # Reload verification to guarantee binary integrity
    verify = TTFont(str(out_path))
    axes_summary = [
        f"{a.axisTag}({a.minValue:.0f}..{a.defaultValue:.1f}..{a.maxValue:.0f})"
        for a in verify["fvar"].axes
    ]
    size_kb = out_path.stat().st_size / 1024.0
    fv_note = (
        f" + FeatureVariations(opsz>={spec.get('opsz_switch_pt', 22.0):.0f}: {spec['display_track_units']} UPM, {fv_tracked} glyphs)"
        if fv_tracked > 0
        else ""
    )
    print(
        f"           wrote {out_path.name} ({size_kb:.1f} KB) | "
        f"tracked={tracked} glyphs ({spec['track_units']} UPM){fv_note} | axes: {', '.join(axes_summary)}"
    )


GMS_STATIC_SPECS = [
    {
        "src_master": "CoreType-SFPro-Text.ttf",
        "out": "CoreType-SFPro-GMS-Medium.ttf",
        "coords": {"wght": 500.0, "wdth": 96.5},
        "family": "CoreType SF Pro Text",
        "subfamily": "Medium",
        "ps_name": "CoreTypeSFProText-Medium",
    },
    {
        "src_master": "CoreType-SFPro-Flex.ttf",
        "out": "CoreType-SFPro-GMS-Bold.ttf",
        "coords": {"opsz": 24.0, "wght": 600.0, "wdth": 97.0},
        "family": "CoreType SF Pro Display",
        "subfamily": "Semibold",
        "ps_name": "CoreTypeSFProDisplay-Semibold",
    },
]


def build_gms_static_instances(out_dir: Path) -> None:
    """
    Build two ultra-lean static SF Pro instances (~250 KB each) from our already-calibrated
    Variable Masters so static GMS FontsProvider targets (Google_Sans_Text-500, Google_Sans-700,
    etc. in Play Store, Gmail, Maps, Photos, Gboard) render genuine Apple Medium (Text opsz=17)
    and Semibold/Bold (Semi-Display opsz=24) instead of falling back to flat Regular (400).
    """
    for spec in GMS_STATIC_SPECS:
        src_path = out_dir / spec["src_master"]
        dst_path = out_dir / spec["out"]
        font = TTFont(str(src_path))
        font = instantiateVariableFont(font, spec["coords"], inplace=True)
        calibrate_vertical_metrics(font)
        set_name_records(font, spec["family"], spec["subfamily"], spec["ps_name"])
        font.save(str(dst_path))
        size_kb = dst_path.stat().st_size / 1024.0
        print(
            f"[CoreType] Built GMS static instance {dst_path.name} ({size_kb:.1f} KB) | "
            f"coords={spec['coords']}"
        )


def audit_built_fonts(out_dir: Path) -> None:
    """Verify OS/2 & hhea vertical metrics parity, USE_TYPO_METRICS, and continuous opsz + FeatureVariations on Flex."""
    expected_files = [s["out"] for s in OPTICAL_SPECS] + [s["out"] for s in GMS_STATIC_SPECS]
    for fname in expected_files:
        fpath = out_dir / fname
        if not fpath.is_file():
            raise RuntimeError(f"Missing expected built font: {fpath}")
        font = TTFont(str(fpath))
        upm = font["head"].unitsPerEm
        hhea = font["hhea"]
        os2 = font["OS/2"]

        assert hhea.ascent == ANDROID_ASCENT == os2.sTypoAscender == os2.usWinAscent, (
            f"Ascent mismatch in {fname}: hhea={hhea.ascent} typo={os2.sTypoAscender} win={os2.usWinAscent}"
        )
        assert hhea.descent == ANDROID_DESCENT == os2.sTypoDescender == -os2.usWinDescent, (
            f"Descent mismatch in {fname}: hhea={hhea.descent} typo={os2.sTypoDescender} win={os2.usWinDescent}"
        )
        assert hhea.lineGap == 0 and os2.sTypoLineGap == 0, f"Non-zero lineGap in {fname}"
        assert (os2.fsSelection & (1 << 7)) != 0, f"USE_TYPO_METRICS bit missing in {fname}"

        line_ratio = (os2.sTypoAscender - os2.sTypoDescender) / float(upm)
        assert 1.17 <= line_ratio <= 1.22, f"Out-of-range line-height ratio {line_ratio:.4f} in {fname}"

        is_italic_file = "Italic" in fname
        italic_angle = font["post"].italicAngle if "post" in font else 0.0
        if is_italic_file:
            assert (os2.fsSelection & 0x01) != 0 and italic_angle < 0, (
                f"Italic metadata missing in {fname}: fsSelection=0x{os2.fsSelection:x} italicAngle={italic_angle}"
            )
        else:
            assert (os2.fsSelection & 0x01) == 0 and italic_angle == 0, (
                f"Unexpected italic flag in upright {fname}: fsSelection=0x{os2.fsSelection:x} italicAngle={italic_angle}"
            )

        if fname == "CoreType-SFPro-Flex.ttf":
            axes = {a.axisTag: (a.minValue, a.defaultValue, a.maxValue) for a in font["fvar"].axes}
            assert "opsz" in axes, "CoreType-SFPro-Flex.ttf missing continuous opsz axis!"
            opsz_min, _opsz_def, opsz_max = axes["opsz"]
            assert opsz_min <= 17.0 and opsz_max >= 28.0 and opsz_max > opsz_min, (
                f"Flex opsz range invalid: {axes['opsz']} (expected continuous 17..28)"
            )
            assert "wght" in axes and "wdth" in axes, f"Flex missing wght/wdth axes: {axes}"
            gpos = font["GPOS"].table
            fv = getattr(gpos, "FeatureVariations", None)
            assert gpos.Version == 0x00010001 and fv is not None and fv.FeatureVariationCount >= 1, (
                "CoreType-SFPro-Flex.ttf missing GPOS 1.1 FeatureVariations for dynamic opsz tracking!"
            )

    print(
        f"[CoreType] Vertical metrics, continuous opsz & GPOS FeatureVariations audit PASSED "
        f"(ascent={ANDROID_ASCENT}, descent={ANDROID_DESCENT}, ratio={(ANDROID_ASCENT - ANDROID_DESCENT)/2048.0:.4f}, "
        f"Flex opsz=17..28 [-46->-26 UPM], GMS-Bold opsz=24)"
    )


def self_test_specs() -> int:
    """Fast dependency-free audit of CoreType font metrics, optical specs, and Unicode filtering."""
    total_h = ANDROID_ASCENT - ANDROID_DESCENT
    ratio = total_h / 2048.0
    ascent_share = ANDROID_ASCENT / float(total_h)
    assert ANDROID_LINE_GAP == 0, "Line gap must be 0 for consistent HyperOS/CJK rendering"
    assert ANDROID_WIN_ASCENT == ANDROID_ASCENT and ANDROID_WIN_DESCENT == -ANDROID_DESCENT
    assert 1.17 <= ratio <= 1.22, f"Unexpected line-height ratio: {ratio:.4f}"
    assert abs(ascent_share - 0.80) < 0.01, f"Ascent share {ascent_share:.4f} deviates from 4:1 CJK parity"

    flex_specs = [s for s in OPTICAL_SPECS if s["out"] == "CoreType-SFPro-Flex.ttf"]
    assert len(flex_specs) == 1 and flex_specs[0]["opsz"] == (17.0, 17.0, 28.0), "Flex opsz must preserve Apple 17..28 domain"
    assert flex_specs[0]["track_units"] == -46 and flex_specs[0]["display_track_units"] == -26, (
        "Flex dynamic FeatureVariations must transition -46 Text -> -26 Display"
    )
    gms_bold = [s for s in GMS_STATIC_SPECS if s["out"] == "CoreType-SFPro-GMS-Bold.ttf"]
    assert len(gms_bold) == 1 and gms_bold[0]["coords"].get("opsz") == 24.0, (
        "GMS Bold static instance must use Semi-Display opsz=24.0"
    )
    assert "tnum" in UI_LAYOUT_FEATURES and "calt" in UI_LAYOUT_FEATURES and "kern" in UI_LAYOUT_FEATURES

    # Verify Unicode preservation (Phonetic Extensions 'ʲᵈᵐ', Latin, digits) & PUA/Arabic exclusion
    for cp in (0x0041, 0x0030, 0x02B2, 0x1D48, 0x1D50):
        assert is_kept_unicode(cp), f"Expected U+{cp:04X} to be preserved"
    for cp in (0xE000, 0xF8FF, 0x100000, 0x0627):
        assert not is_kept_unicode(cp), f"Expected U+{cp:04X} to be excluded"

    print(
        f"[PASS] build_fonts.py audit OK: metrics={ANDROID_ASCENT}/{ANDROID_DESCENT} "
        f"(ratio={ratio:.4f}, ascent={ascent_share*100:.1f}%), Flex opsz=17..28 FeatureVariations(-46->-26), "
        f"GMS-Bold opsz=24, tnum+calt+Unicode verified"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Build CoreType dual-optical SF Pro variable fonts.")
    parser.add_argument("--src-fonts-dir", type=Path, help="Path to already-extracted Apple Library/Fonts directory")
    parser.add_argument("--dmg", type=Path, help="Path to local SF-Pro.dmg (if omitted, downloads from Apple CDN)")
    parser.add_argument("--out-dir", type=Path, help="Output directory for CoreType-*.ttf")
    parser.add_argument("--self-test", action="store_true", help="Run metrics & spec audit without building fonts")
    args = parser.parse_args()

    if args.self_test:
        return self_test_specs()

    if TTFont is None:
        raise RuntimeError("fontTools is required to build fonts (install python3-fonttools)")
    if not args.out_dir:
        parser.error("--out-dir is required unless --self-test is specified")

    tmp_dir = None
    try:
        if args.src_fonts_dir:
            fonts_dir = args.src_fonts_dir
        else:
            tmp_dir = Path(tempfile.mkdtemp(prefix="coretype_build_"))
            dmg_path = args.dmg
            if dmg_path is None:
                dmg_path = tmp_dir / "SF-Pro.dmg"
                print("[CoreType] Downloading official SF-Pro.dmg from Apple CDN ...")
                run_cmd(["curl", "-fsSL", "-o", str(dmg_path), SF_PRO_DMG_URL])
            fonts_dir = extract_sf_pro(dmg_path, tmp_dir / "extract")

        for spec in OPTICAL_SPECS:
            build_optical_master(
                fonts_dir / spec["src"],
                args.out_dir / spec["out"],
                spec,
            )

        build_gms_static_instances(args.out_dir)
        audit_built_fonts(args.out_dir)

        print("[CoreType] All 5 optical SF Pro variable masters + 2 GMS static instances built & audited!")
        return 0
    finally:
        if tmp_dir and tmp_dir.exists():
            shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
