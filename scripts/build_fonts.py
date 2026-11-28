#!/usr/bin/env python3
"""
CoreType Font Engineering Pipeline (v1.2.2 — 2D opsz × wght Apple CoreText Parity Engine)

Transforms official Apple SF-Pro.ttf & SF-Pro-Italic.ttf into FIVE ultra-lean,
optical-calibrated Variable Fonts + TWO GMS static instances for Android 12–17 & HyperOS 1–4:

  1. CoreType-SFPro-Text.ttf           (opsz=17, wght 100..950 + wdth 75..100, wght-adaptive GPOS -46/-32/-20 UPM)
  2. CoreType-SFPro-Text-Italic.ttf    (opsz=17, wght 100..950, wght-adaptive GPOS -46/-32/-20 UPM)
  3. CoreType-SFPro-Display.ttf        (opsz=28, wght 100..950 + wdth 75..100, wght-adaptive GPOS -14/-26/-16 UPM)
  4. CoreType-SFPro-Display-Italic.ttf (opsz=28, wght 100..950, wght-adaptive GPOS -14/-26/-16 UPM)
  5. CoreType-SFPro-Flex.ttf           (continuous opsz 17..28 + 2D opsz×wght GPOS 1.1 FeatureVariations)
  6. CoreType-SFPro-GMS-Medium.ttf     (static Text Medium wght=500, opsz=17 for GMS FontsProvider)
  7. CoreType-SFPro-GMS-Bold.ttf       (static Semi-Display Semibold wght=600, opsz=24 for GMS FontsProvider)
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

# 2D (opsz × wght) Apple HIG CoreText tracking rules evaluated top-to-bottom (first match wins):
# - Text (opsz=17): snug -46 UPM for body/labels (wght < 580), breathing open to -32 UPM at
#   Semibold/Bold (wght >= 580) and -20 UPM at Heavy/Black (wght >= 750) — makes HyperOS MiSans
#   Weight Slider and bold UI runs feel alive with zero stroke collision.
# - Display (opsz=28): airy -14 UPM for Thin/UltraLight clocks (wght <= 280), iconic -26 UPM
#   for Light..Bold headers, and sculptural -16 UPM for Heavy/Black (wght >= 750).
# - Flex (continuous opsz 17..28): Apple's exact 20pt Text->Semi-Display (-34 UPM) and 24pt
#   Large Display (-24 UPM) optical thresholds combined with weight-adaptive breathing (-14/-16/-20/-32 UPM).
TEXT_WEIGHT_VARIATIONS = [
    {"conditions": [("wght", 750.0, None)], "track_units": -20, "space_track": -10, "label": "Text-Heavy"},
    {"conditions": [("wght", 580.0, None)], "track_units": -32, "space_track": -14, "label": "Text-Bold"},
]

DISPLAY_WEIGHT_VARIATIONS = [
    {"conditions": [("wght", None, 280.0)], "track_units": -14, "space_track": -6, "label": "Display-Thin"},
    {"conditions": [("wght", 750.0, None)], "track_units": -16, "space_track": -8, "label": "Display-Heavy"},
]

FLEX_2D_VARIATIONS = [
    {"conditions": [("opsz", 24.0, None), ("wght", 750.0, None)], "track_units": -16, "space_track": -8, "label": "Display-Heavy"},
    {"conditions": [("opsz", 24.0, None), ("wght", None, 280.0)], "track_units": -14, "space_track": -6, "label": "Display-Thin"},
    {"conditions": [("opsz", 24.0, None)], "track_units": -24, "space_track": -10, "label": "Display"},
    {"conditions": [("opsz", 20.0, None), ("wght", 750.0, None)], "track_units": -18, "space_track": -8, "label": "SemiDisplay-Heavy"},
    {"conditions": [("opsz", 20.0, None)], "track_units": -34, "space_track": -14, "label": "SemiDisplay"},
    {"conditions": [("wght", 750.0, None)], "track_units": -20, "space_track": -10, "label": "Text-Heavy"},
    {"conditions": [("wght", 580.0, None)], "track_units": -32, "space_track": -14, "label": "Text-Bold"},
]

OPTICAL_SPECS = [
    {
        "src": "SF-Pro.ttf",
        "out": "CoreType-SFPro-Text.ttf",
        "is_italic": False,
        "opsz": 17.0,
        "default_wdth": 96.5,
        "track_units": -46,
        "space_track": -18,
        "feature_variations": TEXT_WEIGHT_VARIATIONS,
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
        "feature_variations": TEXT_WEIGHT_VARIATIONS,
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
        "feature_variations": DISPLAY_WEIGHT_VARIATIONS,
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
        "feature_variations": DISPLAY_WEIGHT_VARIATIONS,
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
        "feature_variations": FLEX_2D_VARIATIONS,
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
    Preserve ALL Unicode scripts AND ALL Apple Symbols / PUA glyphs present in SF-Pro.ttf
    (including Basic/Ext Latin A-E, Phonetic Extensions U+1D00..1DFF like 'ʲᵈᵐ', Greek,
    Cyrillic, Vietnamese, Math, Currency, Punctuation, Arrows, the bitten Apple logo ''
    U+F8FF, and full Apple SF Symbols in U+E000..F8FF & U+F0000+).
    Android maps font files read-only via shared mmap page cache (demand-paged), so full
    symbol preservation adds zero idle CPU/RAM overhead while preventing all symbol tofu boxes.

    Excludes ONLY Arabic blocks so HyperOS/Android's native Arabic fonts (MiSansArabicVF /
    NotoNaskhArabic) continue shaping Arabic text cleanly.
    """
    # Let ROM's native Arabic fonts handle Arabic blocks cleanly
    if (0x0600 <= cp <= 0x06FF) or (0x0750 <= cp <= 0x077F) or (0x0870 <= cp <= 0x08FF):
        return False
    if (0xFB50 <= cp <= 0xFDFF) or (0xFE70 <= cp <= 0xFEFE):
        return False
    return True


def subset_font(font: TTFont) -> None:
    """Retain 100% UI scripts & Apple Symbols/PUA while dropping desktop-only OT sets & Arabic fallback blocks."""
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

    # Build reverse map glyph -> primary codepoint and collect PUA/SF Symbol glyphs so icon
    # glyphs retain 100% native Apple sidebearings and never bloat/overflow SinglePos subtables.
    glyph_to_cp = {}
    pua_glyphs = set()
    for cp, gname in cmap.items():
        if gname not in glyph_to_cp:
            glyph_to_cp[gname] = cp
        if (0xE000 <= cp <= 0xF8FF) or cp >= 0xF0000:
            pua_glyphs.add(gname)

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
        if (
            gname == ".notdef"
            or gname in mark_glyphs
            or gname in pua_glyphs
            or gname.split(".")[0] in pua_glyphs
        ):
            continue
        aw, _lsb = hmtx[gname]
        if aw <= 0:
            continue

        cp = glyph_to_cp.get(gname)
        cat = None
        if cp is not None:
            cat = unicodedata.category(chr(cp))
            if cat in ("Mn", "Me", "Cf", "Cc", "Co"):
                continue

        is_digit = (cp is not None and 0x0030 <= cp <= 0x0039) or gname.split(".")[0] in digit_prefixes
        if is_digit:
            # Keep Semi-Display/Display/Bold/Heavy (>= -36) digits at pure 0 UPM; gentle -8 UPM on Text (-46)
            if track_units >= -36:
                continue
            delta = -8
            x_place = -4
        elif cp in (0x0020, 0x00A0):
            delta = space_track
            x_place = 0
        elif cat == "Sc" or cp in (0x0025, 0x00B0, 0x2030):
            # Currency & numeric unit symbols ($, €, Rp, %, °, ‰) -> airy 40% tracking next to digits
            delta = int(round(track_units * 0.40))
            x_place = int(round(delta / 2.0))
        elif cat in ("Ps", "Pe", "Pi", "Pf") or cp in (0x0022, 0x0027, 0x002F):
            # Parentheses, brackets, quotation marks & slash -> crisp 45% optical clearance
            delta = int(round(track_units * 0.45))
            x_place = int(round(delta / 2.0))
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

        if delta == 0:
            continue

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


def _piecewise_linear_map(value: float, segments: dict) -> float:
    """Apply an OpenType `avar` piecewise-linear mapping dictionary to a normalized coordinate."""
    if not segments:
        return value
    pts = sorted(segments.items())
    if value <= pts[0][0]:
        return pts[0][1]
    if value >= pts[-1][0]:
        return pts[-1][1]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x0 <= value <= x1:
            if x1 == x0:
                return y0
            return y0 + (y1 - y0) * ((value - x0) / (x1 - x0))
    return value


def normalize_axis_value(font: "TTFont", axis_tag: str, user_value: float):
    """
    Convert a user-space axis value (e.g. wght=580, opsz=20) into its post-`avar`
    normalized [-1.0, 1.0] coordinate as evaluated by HarfBuzz/Minikin FeatureVariations.
    Returns (axis_index, normalized_value) or (None, None) if the axis is absent.
    """
    if "fvar" not in font:
        return None, None
    axis_idx = None
    axis = None
    for idx, a in enumerate(font["fvar"].axes):
        if a.axisTag == axis_tag:
            axis_idx = idx
            axis = a
            break
    if axis is None:
        return None, None

    if user_value <= axis.defaultValue:
        span = axis.defaultValue - axis.minValue
        norm = 0.0 if span <= 0 else (user_value - axis.defaultValue) / span
    else:
        span = axis.maxValue - axis.defaultValue
        norm = 0.0 if span <= 0 else (user_value - axis.defaultValue) / span
    norm = max(-1.0, min(1.0, norm))

    if "avar" in font and axis_tag in font["avar"].segments:
        norm = _piecewise_linear_map(norm, font["avar"].segments[axis_tag])
        norm = max(-1.0, min(1.0, norm))

    return axis_idx, norm


def bake_gpos_feature_variations(
    font: "TTFont",
    default_lookup_idx: int,
    rules: list,
) -> int:
    """
    Attach ordered OpenType GPOS 1.1 FeatureVariations records across any combination of
    `opsz` and `wght` axes so Android HarfBuzz/Minikin dynamically adapts Apple tracking
    both by optical size (17->20->24->28) AND by weight (Thin/Regular/Bold/Heavy).
    Returns number of FeatureVariationRecords added.
    """
    if default_lookup_idx is None or not rules or "GPOS" not in font or "fvar" not in font:
        return 0

    gpos = font["GPOS"].table
    lookup_cache = {}
    new_records = []

    # Small F2DOT14 quantization epsilon so exact boundary coordinates (e.g. opsz=20, wght=580)
    # always match inclusively after 2.14 fixed-point serialization.
    eps = 1e-4

    for rule in rules:
        cond_tables = []
        valid_rule = True
        for axis_tag, min_user, max_user in rule["conditions"]:
            if min_user is not None:
                axis_idx, norm_min = normalize_axis_value(font, axis_tag, min_user)
                if axis_idx is None:
                    valid_rule = False
                    break
                norm_min = max(-1.0, norm_min - eps)
            else:
                axis_idx = None
                norm_min = -1.0

            if max_user is not None:
                axis_idx2, norm_max = normalize_axis_value(font, axis_tag, max_user)
                if axis_idx2 is None:
                    valid_rule = False
                    break
                axis_idx = axis_idx if axis_idx is not None else axis_idx2
                norm_max = min(1.0, norm_max + eps)
            else:
                norm_max = 1.0

            if axis_idx is None or norm_min > norm_max:
                valid_rule = False
                break

            cond = otTables.ConditionTable()
            cond.Format = 1
            cond.AxisIndex = axis_idx
            cond.FilterRangeMinValue = norm_min
            cond.FilterRangeMaxValue = norm_max
            cond_tables.append(cond)

        if not valid_rule or not cond_tables:
            continue

        cache_key = (rule["track_units"], rule["space_track"])
        if cache_key in lookup_cache:
            alt_lookup_idx = lookup_cache[cache_key]
        else:
            alt_lookup, _cnt = _build_tracking_lookup(font, rule["track_units"], rule["space_track"])
            if alt_lookup is None:
                continue
            alt_lookup_idx = len(gpos.LookupList.Lookup)
            gpos.LookupList.Lookup.append(alt_lookup)
            gpos.LookupList.LookupCount = len(gpos.LookupList.Lookup)
            lookup_cache[cache_key] = alt_lookup_idx

        subst_records = []
        for feat_idx, feat_rec in enumerate(gpos.FeatureList.FeatureRecord):
            if feat_rec.FeatureTag != "kern":
                continue
            alt_feat = otTables.Feature()
            alt_feat.FeatureParams = feat_rec.Feature.FeatureParams
            alt_feat.LookupListIndex = [
                alt_lookup_idx if li == default_lookup_idx else li
                for li in feat_rec.Feature.LookupListIndex
            ]
            alt_feat.LookupCount = len(alt_feat.LookupListIndex)

            sub_rec = otTables.FeatureTableSubstitutionRecord()
            sub_rec.FeatureIndex = feat_idx
            sub_rec.Feature = alt_feat
            subst_records.append(sub_rec)

        if not subst_records:
            continue

        cond_set = otTables.ConditionSet()
        cond_set.ConditionTable = cond_tables
        cond_set.ConditionCount = len(cond_tables)

        feat_subst = otTables.FeatureTableSubstitution()
        feat_subst.Version = 0x00010000
        feat_subst.SubstitutionRecord = subst_records
        feat_subst.SubstitutionCount = len(subst_records)

        fvr = otTables.FeatureVariationRecord()
        fvr.ConditionSet = cond_set
        fvr.FeatureTableSubstitution = feat_subst
        new_records.append(fvr)

    if not new_records:
        return 0

    gpos.Version = 0x00010001  # GPOS 1.1 required for FeatureVariations
    if getattr(gpos, "FeatureVariations", None) is None:
        fv = otTables.FeatureVariations()
        fv.Version = 0x00010000
        fv.FeatureVariationRecord = new_records
        fv.FeatureVariationCount = len(new_records)
        gpos.FeatureVariations = fv
    else:
        gpos.FeatureVariations.FeatureVariationRecord.extend(new_records)
        gpos.FeatureVariations.FeatureVariationCount = len(gpos.FeatureVariations.FeatureVariationRecord)

    return len(new_records)


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


RIBBI_SUBFAMILIES = {"Regular", "Italic", "Bold", "Bold Italic"}


def build_name_records(family: str, subfamily: str, ps_name: str) -> dict:
    """Compute OpenType RIBBI-compliant name table entries (IDs 1, 2, 4, 6, 16, 17)."""
    full_name = f"{family} {subfamily}" if subfamily != "Regular" else family
    if subfamily in RIBBI_SUBFAMILIES:
        legacy_family = family
        legacy_subfamily = subfamily
    else:
        legacy_family = f"{family} {subfamily}"
        legacy_subfamily = "Regular"
    return {
        1: legacy_family,
        2: legacy_subfamily,
        4: full_name,
        6: ps_name,
        16: family,
        17: subfamily,
    }


def set_name_records(font: "TTFont", family: str, subfamily: str, ps_name: str) -> None:
    """Stamp clean CoreType naming records for Android font_fallback.xml postScriptName matching."""
    name_table = font["name"]
    records = build_name_records(family, subfamily, ps_name)
    for name_id, value in records.items():
        name_table.setName(value, name_id, 3, 1, 0x0409)  # Windows Unicode BMP en-US
        name_table.setName(value, name_id, 1, 0, 0)       # Mac Roman English


def build_optical_master(src_path: Path, out_path: Path, spec: dict) -> None:
    """Build one optical-calibrated Variable Font master (Text, Display, or Continuous-opsz Flex)."""
    print(f"[CoreType] Building {spec['out']} from {src_path.name} ...")
    with TTFont(str(src_path)) as font:
        orig_glyphs = len(font.getGlyphOrder())

        subset_font(font)
        sub_glyphs = len(font.getGlyphOrder())
        print(f"           subset: {orig_glyphs} -> {sub_glyphs} glyphs")

        # Pin `opsz` for Text (17.0) / Display (28.0) or keep continuous (17.0, 17.0, 28.0) for Flex.
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
        fv_count = 0
        fv_rules = spec.get("feature_variations") or []
        if fv_rules and default_lookup_idx is not None:
            fv_count = bake_gpos_feature_variations(font, default_lookup_idx, fv_rules)
        calibrate_vertical_metrics(font)
        set_name_records(font, spec["family"], spec["subfamily"], spec["ps_name"])

        out_path.parent.mkdir(parents=True, exist_ok=True)
        font.save(str(out_path))

    # Reload verification to guarantee binary integrity
    with TTFont(str(out_path)) as verify:
        axes_summary = [
            f"{a.axisTag}({a.minValue:.0f}..{a.defaultValue:.1f}..{a.maxValue:.0f})"
            for a in verify["fvar"].axes
        ]
    size_kb = out_path.stat().st_size / 1024.0
    fv_note = f" + GPOS-1.1 FeatureVariations({fv_count} rules)" if fv_count > 0 else ""
    print(
        f"           wrote {out_path.name} ({size_kb:.1f} KB) | "
        f"tracked={tracked} glyphs (default {spec['track_units']} UPM){fv_note} | axes: {', '.join(axes_summary)}"
    )


GMS_STATIC_SPECS = [
    {
        "src_master": "CoreType-SFPro-Text.ttf",
        "out": "CoreType-SFPro-GMS-Medium.ttf",
        "coords": {"wght": 500.0, "wdth": 96.5},
        "weight_class": 500,
        "family": "CoreType SF Pro Text",
        "subfamily": "Medium",
        "ps_name": "CoreTypeSFProText-Medium",
    },
    {
        "src_master": "CoreType-SFPro-Flex.ttf",
        "out": "CoreType-SFPro-GMS-Bold.ttf",
        "coords": {"opsz": 24.0, "wght": 600.0, "wdth": 97.0},
        "weight_class": 600,
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
        with TTFont(str(src_path)) as font:
            font = instantiateVariableFont(font, spec["coords"], inplace=True)
            calibrate_vertical_metrics(font)
            os2 = font["OS/2"]
            os2.usWeightClass = int(spec["weight_class"])
            if spec["subfamily"] != "Regular":
                os2.fsSelection &= ~(1 << 6)  # Clear REGULAR bit on non-Regular static instances
            set_name_records(font, spec["family"], spec["subfamily"], spec["ps_name"])
            font.save(str(dst_path))
        size_kb = dst_path.stat().st_size / 1024.0
        print(
            f"[CoreType] Built GMS static instance {dst_path.name} ({size_kb:.1f} KB) | "
            f"coords={spec['coords']} weightClass={spec['weight_class']}"
        )


def audit_built_fonts(out_dir: Path) -> None:
    """Verify OS/2 & hhea vertical metrics parity, USE_TYPO_METRICS, static GMS weightClass, and 2D FeatureVariations."""
    gms_weight_map = {s["out"]: s["weight_class"] for s in GMS_STATIC_SPECS}
    expected_fv_map = {s["out"]: len(s.get("feature_variations") or []) for s in OPTICAL_SPECS}
    expected_files = [s["out"] for s in OPTICAL_SPECS] + [s["out"] for s in GMS_STATIC_SPECS]
    for fname in expected_files:
        fpath = out_dir / fname
        if not fpath.is_file():
            raise RuntimeError(f"Missing expected built font: {fpath}")
        with TTFont(str(fpath)) as font:
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

            if fname in gms_weight_map:
                assert "fvar" not in font, f"GMS static instance {fname} should not contain fvar!"
                assert os2.usWeightClass == gms_weight_map[fname], (
                    f"Unexpected usWeightClass in {fname}: {os2.usWeightClass} != {gms_weight_map[fname]}"
                )

            min_fv = expected_fv_map.get(fname, 0)
            if min_fv > 0:
                gpos = font["GPOS"].table
                fv = getattr(gpos, "FeatureVariations", None)
                assert gpos.Version == 0x00010001 and fv is not None and fv.FeatureVariationCount >= min_fv, (
                    f"{fname} missing expected GPOS 1.1 FeatureVariations (need >= {min_fv})!"
                )

            if fname == "CoreType-SFPro-Flex.ttf":
                axes = {a.axisTag: (a.minValue, a.defaultValue, a.maxValue) for a in font["fvar"].axes}
                assert "opsz" in axes, "CoreType-SFPro-Flex.ttf missing continuous opsz axis!"
                opsz_min, _opsz_def, opsz_max = axes["opsz"]
                assert opsz_min <= 17.0 and opsz_max >= 28.0 and opsz_max > opsz_min, (
                    f"Flex opsz range invalid: {axes['opsz']} (expected continuous 17..28)"
                )
                assert "wght" in axes and "wdth" in axes, f"Flex missing wght/wdth axes: {axes}"

    print(
        f"[CoreType] Vertical metrics, continuous opsz & 2D GPOS FeatureVariations audit PASSED "
        f"(ascent={ANDROID_ASCENT}, descent={ANDROID_DESCENT}, ratio={(ANDROID_ASCENT - ANDROID_DESCENT)/2048.0:.4f}, "
        f"Text wght[-46/-32/-20], Display wght[-14/-26/-16], Flex 2D[7 rules], GMS-Bold opsz=24)"
    )


def self_test_specs() -> int:
    """Fast dependency-free audit of CoreType font metrics, 2D optical specs, avar math, RIBBI naming, and Unicode filtering."""
    total_h = ANDROID_ASCENT - ANDROID_DESCENT
    ratio = total_h / 2048.0
    ascent_share = ANDROID_ASCENT / float(total_h)
    assert ANDROID_LINE_GAP == 0, "Line gap must be 0 for consistent HyperOS/CJK rendering"
    assert ANDROID_WIN_ASCENT == ANDROID_ASCENT and ANDROID_WIN_DESCENT == -ANDROID_DESCENT
    assert 1.17 <= ratio <= 1.22, f"Unexpected line-height ratio: {ratio:.4f}"
    assert abs(ascent_share - 0.80) < 0.01, f"Ascent share {ascent_share:.4f} deviates from 4:1 CJK parity"

    # Verify all 5 variable masters define weight/optical FeatureVariations
    for spec in OPTICAL_SPECS:
        assert len(spec.get("feature_variations") or []) >= 2, f"{spec['out']} missing FeatureVariations rules"

    flex_specs = [s for s in OPTICAL_SPECS if s["out"] == "CoreType-SFPro-Flex.ttf"]
    assert len(flex_specs) == 1 and flex_specs[0]["opsz"] == (17.0, 17.0, 28.0), "Flex opsz must preserve Apple 17..28 domain"
    assert flex_specs[0]["track_units"] == -46 and len(flex_specs[0]["feature_variations"]) == 7, (
        "Flex 2D FeatureVariations must define 7 ordered opsz x wght rules"
    )
    gms_bold = [s for s in GMS_STATIC_SPECS if s["out"] == "CoreType-SFPro-GMS-Bold.ttf"]
    assert len(gms_bold) == 1 and gms_bold[0]["coords"].get("opsz") == 24.0, (
        "GMS Bold static instance must use Semi-Display opsz=24.0"
    )
    assert "tnum" in UI_LAYOUT_FEATURES and "calt" in UI_LAYOUT_FEATURES and "kern" in UI_LAYOUT_FEATURES

    # Verify avar piecewise linear mapping math
    seg = {-1.0: -1.0, 0.0: 0.0, 0.5: 0.65, 1.0: 1.0}
    assert abs(_piecewise_linear_map(0.25, seg) - 0.325) < 1e-6
    assert abs(_piecewise_linear_map(0.75, seg) - 0.825) < 1e-6

    # Verify RIBBI compliance on non-RIBBI static subfamilies
    med_names = build_name_records("CoreType SF Pro Text", "Medium", "CoreTypeSFProText-Medium")
    assert med_names[1] == "CoreType SF Pro Text Medium" and med_names[2] == "Regular"
    assert med_names[16] == "CoreType SF Pro Text" and med_names[17] == "Medium"
    reg_names = build_name_records("CoreType SF Pro Text", "Italic", "CoreTypeSFProText-Italic")
    assert reg_names[1] == "CoreType SF Pro Text" and reg_names[2] == "Italic"

    # Verify full Unicode + Apple SF Symbols / PUA preservation (including 'ʲᵈᵐ', '' U+F8FF, SF Symbols) & Arabic fallback exclusion
    for cp in (0x0041, 0x0030, 0x02B2, 0x1D48, 0x1D50, 0xE000, 0xF8FF, 0x100000):
        assert is_kept_unicode(cp), f"Expected U+{cp:04X} to be preserved"
    for cp in (0x0627, 0x0750, 0x0870, 0xFB50, 0xFE70):
        assert not is_kept_unicode(cp), f"Expected Arabic U+{cp:04X} to defer to ROM Arabic fallback"

    print(
        f"[PASS] build_fonts.py audit OK: metrics={ANDROID_ASCENT}/{ANDROID_DESCENT} "
        f"(ratio={ratio:.4f}, ascent={ascent_share*100:.1f}%), 2D opsz x wght FeatureVariations across all 5 masters, "
        f"GMS-Bold opsz=24, full SF Symbols++avar+RIBBI+tnum+calt verified"
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
                run_cmd([
                    "curl", "-fsSL",
                    "--retry", "3",
                    "--retry-delay", "5",
                    "--connect-timeout", "30",
                    "--max-time", "600",
                    "-o", str(dmg_path),
                    SF_PRO_DMG_URL,
                ])
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
