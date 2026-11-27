#!/bin/sh
# CoreType — Automated POSIX Test Suite (HyperOS 1–4, AOSP 12–16, MiSans Slider & Apple iOS Emoji)

set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() {
    PASS=$((PASS + 1))
    printf '  [PASS] %s\n' "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf '  [FAIL] %s\n' "$1" >&2
}

assert_grep() {
    _pattern="$1"
    _file="$2"
    _label="$3"
    if grep -qE "$_pattern" "$_file"; then
        pass "$_label"
    else
        fail "$_label (missing pattern: $_pattern)"
    fi
}

assert_not_grep() {
    _pattern="$1"
    _file="$2"
    _label="$3"
    if grep -qE "$_pattern" "$_file"; then
        fail "$_label (unexpected pattern: $_pattern)"
    else
        pass "$_label"
    fi
}

# shellcheck disable=SC1091
. "$REPO_ROOT/lib/common.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/lib/profiles.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/lib/font_xml.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/lib/engine.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/lib/emoji.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/lib/gms_fonts.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Simulate HyperOS 3/4 stock /system/fonts/ + /product/fonts/
HOS3_FONTS="$TMP_DIR/hos3_fonts"
HOS3_PROD="$TMP_DIR/hos3_prod"
mkdir -p "$HOS3_FONTS" "$HOS3_PROD"
for _mf in Roboto-Regular.ttf RobotoStatic-Regular.ttf RobotoFlex-Regular.ttf MiSansVF.ttf MiSansVF_Overlay.ttf MiSansTCVF.ttf NotoColorEmoji.ttf NotoColorEmojiFlags.ttf; do
    printf 'mockfont' > "$HOS3_FONTS/$_mf"
done
for _pf in MiSansVF.ttf MiSansLatinVF.ttf MiSansTCVF.ttf; do
    printf 'mockfont' > "$HOS3_PROD/$_pf"
done

printf '=== Test 1: HyperOS 3/4 Stock-Slot Allocation & CJK Fallback Safety ===\n'
ct_resolve_stock_slots "$HOS3_FONTS"
if [ "$CT_SLOT_TEXT" = "Roboto-Regular.ttf" ] \
    && [ "$CT_SLOT_DISP" = "RobotoStatic-Regular.ttf" ] \
    && [ "$CT_SLOT_ITAL" = "RobotoFlex-Regular.ttf" ] \
    && [ "$CT_SLOT_DITAL" = "RobotoFlex-Regular.ttf" ]; then
    pass "HyperOS 3/4 slots mapped strictly onto existing stock files"
else
    fail "Unexpected HyperOS 3/4 slots"
fi

if ct_resolve_cjk_fallback "$HOS3_FONTS" "$HOS3_PROD" && [ "$CT_CJK_FALLBACK" = "MiSansTCVF.ttf" ]; then
    pass "Detected safe CJK fallback (MiSansTCVF.ttf) for MiSans Slider mode"
else
    fail "Expected CJK fallback MiSansTCVF.ttf, got ${CT_CJK_FALLBACK:-empty}"
fi

cat > "$TMP_DIR/hyperos3_fallback.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<familyset>
    <!-- <family name="sans-serif"><font>CommentedOut.ttf</font></family> -->
    <family name="sans-serif">
        <font weight="100" style="normal" postScriptName="MiSansVF">MiSansVF_Overlay.ttf
            <axis tag="wght" stylevalue="150" />
        </font>
        <font weight="400" style="normal" postScriptName="MiSansVF">MiSansVF_Overlay.ttf
            <axis tag="wght" stylevalue="340" />
        </font>
        <font weight="700" style="normal" postScriptName="MiSansVF">MiSansVF_Overlay.ttf
            <axis tag="wght" stylevalue="630" />
        </font>
    </family>
    <family>
        <font weight="400" style="normal" postScriptName="MiSansLatinVF">MiSansLatinVF.ttf
            <axis tag="wght" stylevalue="400" />
        </font>
    </family>
    <family lang="zh-Hans">
        <font weight="400" style="normal" postScriptName="MiSansVF">MiSansVF.ttf
            <axis tag="wght" stylevalue="340" />
        </font>
    </family>
    <family name="sans-serif-condensed">
        <font weight="400" style="normal">RobotoCondensed-Regular.ttf</font>
    </family>
    <family name="roboto-flex">
        <font weight="400" style="normal">RobotoFlex-Regular.ttf</font>
    </family>
    <family>
        <font supportedAxes="wght,ital">Roboto-Regular.ttf
            <axis tag="wdth" stylevalue="100" />
        </font>
    </family>
    <family lang="ar">
        <font weight="400" style="normal">MiSansArabicVF.ttf</font>
    </family>
    <family lang="ja">
        <font weight="400" style="normal">MiSansJapaneseVF.ttf</font>
    </family>
    <family>
        <font weight="400" style="normal">NotoColorEmoji.ttf</font>
    </family>
</familyset>
EOF

CT_MISANS_SLIDER_ACTIVE="1"
if ct_patch_font_xml "$TMP_DIR/hyperos3_fallback.xml" "$TMP_DIR/nested/etc/font_fallback.xml" "dynamic_optical" "$HOS3_FONTS"; then
    pass "HyperOS 3/4 font_fallback.xml patched & validated cleanly"
    cp "$TMP_DIR/nested/etc/font_fallback.xml" "$TMP_DIR/font_fallback.xml"
else
    fail "HyperOS 3/4 font_fallback.xml patching failed"
fi

assert_not_grep 'CoreType-SFPro' "$TMP_DIR/font_fallback.xml" "Zero non-stock CoreType-SFPro filenames in XML"
assert_grep 'CoreType Dual-Optical' "$TMP_DIR/font_fallback.xml" "Contains CoreType Dual-Optical XML marker"
assert_grep 'weight="400" style="normal">Roboto-Regular\.ttf' "$TMP_DIR/font_fallback.xml" "Body 400 routed to Text slot"
assert_grep 'weight="400" style="italic">RobotoFlex-Regular\.ttf' "$TMP_DIR/font_fallback.xml" "Body 400 italic routed to Italic slot"
assert_grep 'weight="600" style="normal">RobotoStatic-Regular\.ttf' "$TMP_DIR/font_fallback.xml" "Header 600 routed to Display slot"
assert_not_grep 'supportedAxes="wght,ital"' "$TMP_DIR/font_fallback.xml" "Eliminated duplicate Roboto-Regular fallback overwrite"
assert_grep 'tag="wght" stylevalue="550"' "$TMP_DIR/font_fallback.xml" "Harmonized mipro-demibold (700) to wght=550"
assert_grep 'tag="wght" stylevalue="650"' "$TMP_DIR/font_fallback.xml" "Harmonized mipro-semibold (800) to wght=650"
assert_grep 'MiSansTCVF\.ttf' "$TMP_DIR/font_fallback.xml" "Redirected zh-Hans CJK fallback to MiSansTCVF.ttf (zero tofu!)"
assert_not_grep 'MiSansVF\.ttf' "$TMP_DIR/font_fallback.xml" "Removed MiSansVF.ttf from zh-Hans when MiSans slider active"
assert_grep 'MiSansArabicVF\.ttf' "$TMP_DIR/font_fallback.xml" "Preserved Arabic fallback"
assert_grep 'MiSansJapaneseVF\.ttf' "$TMP_DIR/font_fallback.xml" "Preserved Japanese fallback"
assert_grep 'NotoColorEmoji\.ttf' "$TMP_DIR/font_fallback.xml" "Preserved NotoColorEmoji fallback"
assert_grep 'CommentedOut\.ttf' "$TMP_DIR/font_fallback.xml" "Preserved commented-out <family> block verbatim"

printf '=== Test 2: HyperOS 1 / Classic AOSP Stock-Slot & NotoSansCJK Fallback ===\n'
AOSP_FONTS="$TMP_DIR/aosp_fonts"
mkdir -p "$AOSP_FONTS"
for _mf in Roboto-Regular.ttf Roboto-Bold.ttf Roboto-Italic.ttf Roboto-BoldItalic.ttf MiLanProVF.ttf NotoSansCJK-Regular.ttc; do
    printf 'mockfont' > "$AOSP_FONTS/$_mf"
done
ct_resolve_stock_slots "$AOSP_FONTS"
ct_resolve_cjk_fallback "$AOSP_FONTS" "$TMP_DIR/empty_prod"
if [ "$CT_SLOT_DISP" = "Roboto-Bold.ttf" ] && [ "$CT_SLOT_DITAL" = "Roboto-BoldItalic.ttf" ] && [ "$CT_CJK_FALLBACK" = "NotoSansCJK-Regular.ttc" ]; then
    pass "HyperOS 1 / Classic AOSP resolves 4 slots + NotoSansCJK-Regular.ttc fallback"
else
    fail "Unexpected HyperOS 1 / AOSP slot or CJK fallback"
fi

cat > "$TMP_DIR/hos1_fonts.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<familyset version="22">
    <family name="sans-serif">
        <font weight="400" style="normal">Roboto-Regular.ttf</font>
    </family>
    <family lang="zh-Hans">
        <font weight="400" style="normal">MiLanProVF.ttf</font>
    </family>
    <family>
        <font weight="400" style="normal">NotoColorEmoji.ttf</font>
    </family>
</familyset>
EOF

CT_MISANS_SLIDER_ACTIVE="1"
if ct_patch_font_xml "$TMP_DIR/hos1_fonts.xml" "$TMP_DIR/fonts.xml" "dynamic_optical" "$AOSP_FONTS"; then
    pass "HyperOS 1 / legacy fonts.xml patched cleanly"
else
    fail "HyperOS 1 / legacy fonts.xml patching failed"
fi
assert_grep 'index="2">NotoSansCJK-Regular\.ttc' "$TMP_DIR/fonts.xml" "HyperOS 1 zh-Hans redirected to NotoSansCJK-Regular.ttc index=2"

printf '=== Test 3: Debloated ROM Without Separate CJK Preserves MiSansVF.ttf ===\n'
NOCJK_FONTS="$TMP_DIR/nocjk_fonts"
NOCJK_MOD="$TMP_DIR/nocjk_mod"
mkdir -p "$NOCJK_FONTS" "$NOCJK_MOD/fonts"
printf 'mock' > "$NOCJK_FONTS/Roboto-Regular.ttf"
printf 'mock' > "$NOCJK_FONTS/MiSansVF.ttf"
for _mf in CoreType-SFPro-Text.ttf CoreType-SFPro-Text-Italic.ttf CoreType-SFPro-Display.ttf CoreType-SFPro-Display-Italic.ttf; do
    { printf '\000\001\000\000'; dd if=/dev/zero bs=1024 count=110 2>/dev/null; } > "$NOCJK_MOD/fonts/$_mf"
done
CT_DATA_DIR="$TMP_DIR/nocjk_data"
ct_sync_stock_slots "$NOCJK_MOD" "$NOCJK_FONTS" "$TMP_DIR/empty_prod"
if [ "$CT_MISANS_SLIDER_ACTIVE" = "0" ] && [ ! -e "$NOCJK_MOD/system/fonts/MiSansVF.ttf" ]; then
    pass "Safely preserved MiSansVF.ttf when no separate CJK fallback exists"
else
    fail "Should not override MiSansVF.ttf without separate CJK fallback"
fi

printf '=== Test 4: Unified Engine (MiSans Slider + Apple iOS Emoji Lite/Full + Bootloop Guard) ===\n'
CT_DATA_DIR="$TMP_DIR/data"
CT_CONF_FILE="$CT_DATA_DIR/config.conf"
CT_STATE_FILE="$CT_DATA_DIR/state.prop"
CT_LOG_FILE="$CT_DATA_DIR/coretype.log"

FAKE_MOD="$TMP_DIR/mod"
mkdir -p "$FAKE_MOD/lib" "$FAKE_MOD/fonts"
cp "$REPO_ROOT/lib/"*.sh "$FAKE_MOD/lib/"
cp "$REPO_ROOT/post-fs-data.sh" "$FAKE_MOD/"
for _mf in CoreType-SFPro-Text.ttf CoreType-SFPro-Text-Italic.ttf CoreType-SFPro-Display.ttf CoreType-SFPro-Display-Italic.ttf; do
    { printf '\000\001\000\000'; dd if=/dev/zero bs=1024 count=110 2>/dev/null; } > "$FAKE_MOD/fonts/$_mf"
done

ct_sync_stock_slots "$FAKE_MOD" "$HOS3_FONTS" "$HOS3_PROD"
if [ "$CT_MISANS_SLIDER_ACTIVE" = "1" ] \
    && [ -s "$FAKE_MOD/system/fonts/MiSansVF.ttf" ] \
    && [ -s "$FAKE_MOD/system/product/fonts/MiSansVF.ttf" ]; then
    pass "MiSans Slider synced both /system/fonts & /product/fonts MiSansVF.ttf via shared inodes"
else
    fail "MiSans Slider slot sync failed"
fi

# Test Lite Edition (no CoreType-AppleEmoji.ttf present)
ct_sync_emoji_slots "$FAKE_MOD" "1" "$HOS3_FONTS"
if [ "$CT_EMOJI_AVAILABLE" = "0" ] && [ "$CT_EMOJI_ACTIVE" = "0" ] && [ ! -e "$FAKE_MOD/system/fonts/NotoColorEmoji.ttf" ]; then
    pass "Lite edition cleanly reports emoji_available=0 without touching NotoColorEmoji.ttf"
else
    fail "Lite edition emoji check failed"
fi

# Test Full Edition (>5 MB valid TrueType magic CoreType-AppleEmoji.ttf)
{ printf '\000\001\000\000'; dd if=/dev/zero bs=1024 count=5200 2>/dev/null; } > "$FAKE_MOD/fonts/CoreType-AppleEmoji.ttf"
ct_sync_emoji_slots "$FAKE_MOD" "1" "$HOS3_FONTS"
if [ "$CT_EMOJI_AVAILABLE" = "1" ] && [ "$CT_EMOJI_ACTIVE" = "1" ] \
    && [ -s "$FAKE_MOD/system/fonts/NotoColorEmoji.ttf" ] \
    && [ -s "$FAKE_MOD/system/fonts/NotoColorEmojiFlags.ttf" ]; then
    pass "Full edition enabled Apple iOS Emoji on stock NotoColorEmoji + Flags slots"
else
    fail "Full edition emoji ON failed"
fi

# Test WebUI Emoji Toggle OFF
ct_sync_emoji_slots "$FAKE_MOD" "0" "$HOS3_FONTS"
if [ "$CT_EMOJI_AVAILABLE" = "1" ] && [ "$CT_EMOJI_ACTIVE" = "0" ] \
    && [ ! -e "$FAKE_MOD/system/fonts/NotoColorEmoji.ttf" ]; then
    pass "Emoji toggle OFF cleanly removes NotoColorEmoji slot while keeping available=1"
else
    fail "Emoji toggle OFF failed"
fi

# Test GMS dynamic font + EmojiCompat opentype bind-mount discovery (mocked mount)
MOCK_DF="$TMP_DIR/data_fonts"
MOCK_GMS="$TMP_DIR/gms_opentype"
MOCK_MOUNT_LOG="$TMP_DIR/mount.log"
mkdir -p "$MOCK_DF/~~hash123==" "$MOCK_GMS"
printf 'stock' > "$MOCK_DF/~~hash123==/NotoColorEmoji.ttf"
printf 'stock' > "$MOCK_GMS/Noto_COLR_Emoji_Compat-400-100_0-0_0.ttf"
printf 'stock' > "$MOCK_GMS/Noto_COLR_Emoji_No_Flags-400-100_0-0_0.ttf"
printf 'stock' > "$MOCK_GMS/Google_Sans_Text-400-100_0-0_0.ttf"
_bound_cnt=$(
    mount() {
        printf '%s\n' "$*" >> "$MOCK_MOUNT_LOG"
        return 0
    }
    chcon() { return 0; }
    ct_bind_gms_emoji_cache "$FAKE_MOD" "$MOCK_DF" "$MOCK_GMS"
    printf '%s' "$CT_GMS_EMOJI_BOUND"
)
if [ "$_bound_cnt" = "3" ] \
    && grep -q 'Noto_COLR_Emoji_Compat' "$MOCK_MOUNT_LOG" \
    && grep -q 'Noto_COLR_Emoji_No_Flags' "$MOCK_MOUNT_LOG" \
    && ! grep -q 'Google_Sans_Text' "$MOCK_MOUNT_LOG"; then
    pass "GMS bind-mount covered /data/fonts + both EmojiCompat caches (3/3) while skipping Google_Sans_Text"
else
    fail "GMS bind-mount discovery failed (bound=$_bound_cnt)"
fi

# Simulate 2 failed boots and verify Bootloop Guard auto-disables module
printf '2\n' > "$CT_DATA_DIR/boot_attempts"
CT_DATA_DIR="$CT_DATA_DIR" sh "$FAKE_MOD/post-fs-data.sh"
if [ -f "$FAKE_MOD/disable" ]; then
    pass "Bootloop Guard auto-disabled module after 2 failed boots"
else
    fail "Bootloop Guard did not create disable flag"
fi

printf '=== Test 5: Dynamic Weight Curve Engine & Universal GMS App Fonts ===\n'
# 5a. Dynamic Weight Curve math: HyperOS vs AOSP auto-calibration + bias + contrast
ct_load_weight_curve "30" "apple_native"
CT_ROM_CURVE="hyperos_mipro"
_w400=$(ct_calc_wght 400)
_w700=$(ct_calc_wght 700)
_w100=$(ct_calc_wght 100)
if [ "$_w400" = "430" ] && [ "$_w700" = "625" ] && [ "$_w100" = "185" ]; then
    pass "Dynamic curve computed HyperOS +30 bias + apple_native cleanly (400->430, 700->625, 100->185)"
else
    fail "Unexpected HyperOS dynamic curve values (400=$_w400 700=$_w700 100=$_w100)"
fi

ct_load_weight_curve "-20" "soft"
CT_ROM_CURVE="aosp_linear"
_a400=$(ct_calc_wght 400)
_a700=$(ct_calc_wght 700)
if [ "$_a400" = "380" ] && [ "$_a700" = "600" ]; then
    pass "Dynamic curve computed AOSP -20 bias + soft contrast cleanly (400->380, 700->600)"
else
    fail "Unexpected AOSP dynamic curve values (400=$_a400 700=$_a700)"
fi

# Reset curve to default for XML test
ct_load_weight_curve "0" "balanced"
cat > "$TMP_DIR/google_families.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<familyset>
    <family name="sans-serif">
        <font weight="400" style="normal">MiSansVF_Overlay.ttf</font>
    </family>
    <family name="google-sans-text">
        <font weight="400" style="normal">GoogleSansText-Regular.ttf</font>
    </family>
    <family name="mipro">
        <font weight="400" style="normal">MiLanProVF.ttf</font>
    </family>
</familyset>
EOF
ct_resolve_stock_slots "$HOS3_FONTS"
if ct_patch_font_xml "$TMP_DIR/google_families.xml" "$TMP_DIR/google_out.xml" "dynamic_optical" "$HOS3_FONTS" \
    && grep -q '<family name="google-sans-text">' "$TMP_DIR/google_out.xml" \
    && grep -q '<family name="mipro">' "$TMP_DIR/google_out.xml" \
    && ! grep -q 'GoogleSansText-Regular\.ttf' "$TMP_DIR/google_out.xml"; then
    pass "Expanded XML patcher routed google-sans-text & mipro to SF Pro while preserving exact family names"
else
    fail "Expanded XML family routing failed"
fi

# 5b. Universal GMS Latin font bind-mount routing (Play Store, Gmail, Maps, Photos, Gboard)
{ printf '\000\001\000\000'; dd if=/dev/zero bs=1024 count=110 2>/dev/null; } > "$FAKE_MOD/fonts/CoreType-SFPro-GMS-Medium.ttf"
{ printf '\000\001\000\000'; dd if=/dev/zero bs=1024 count=110 2>/dev/null; } > "$FAKE_MOD/fonts/CoreType-SFPro-GMS-Bold.ttf"
MOCK_GMS_LATIN="$TMP_DIR/gms_latin"
MOCK_GMS_LOG="$TMP_DIR/gms_latin_mount.log"
mkdir -p "$MOCK_GMS_LATIN"
for _gf in \
    Google_Sans_Text-400-100_0-0_0.ttf \
    Google_Sans_Text-500-100_0-0_0.ttf \
    Google_Sans-700-100_0-0_0.ttf \
    Google_Sans_Text-400-100_0-1_0.ttf \
    Noto_COLR_Emoji_Compat-400-100_0-0_0.ttf \
    RobotoMono-400-100_0-0_0.ttf; do
    printf 'stock' > "$MOCK_GMS_LATIN/$_gf"
done
_gbound=$(
    mount() {
        printf '%s\n' "$*" >> "$MOCK_GMS_LOG"
        return 0
    }
    chcon() { return 0; }
    ct_bind_gms_latin_fonts "$FAKE_MOD" "$MOCK_GMS_LATIN"
    printf '%s' "$CT_GMS_FONTS_BOUND"
)
if [ "$_gbound" = "4" ] \
    && grep -q 'CoreType-SFPro-Text\.ttf.*Google_Sans_Text-400-100_0-0_0\.ttf' "$MOCK_GMS_LOG" \
    && grep -q 'CoreType-SFPro-GMS-Medium\.ttf.*Google_Sans_Text-500-100_0-0_0\.ttf' "$MOCK_GMS_LOG" \
    && grep -q 'CoreType-SFPro-GMS-Bold\.ttf.*Google_Sans-700-100_0-0_0\.ttf' "$MOCK_GMS_LOG" \
    && grep -q 'CoreType-SFPro-Text-Italic\.ttf.*Google_Sans_Text-400-100_0-1_0\.ttf' "$MOCK_GMS_LOG" \
    && ! grep -q 'Noto_COLR_Emoji' "$MOCK_GMS_LOG" \
    && ! grep -q 'RobotoMono' "$MOCK_GMS_LOG"; then
    pass "Universal GMS Latin bind routed 400/500/700/Italic accurately (4/4) while skipping Emoji & Mono"
else
    fail "Universal GMS Latin font routing failed (bound=$_gbound)"
fi

printf '=== Test 6: ShellCheck Static Analysis ===\n'
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -s sh \
        "$REPO_ROOT/customize.sh" \
        "$REPO_ROOT/post-fs-data.sh" \
        "$REPO_ROOT/service.sh" \
        "$REPO_ROOT/uninstall.sh" \
        "$REPO_ROOT/lib/common.sh" \
        "$REPO_ROOT/lib/profiles.sh" \
        "$REPO_ROOT/lib/font_xml.sh" \
        "$REPO_ROOT/lib/engine.sh" \
        "$REPO_ROOT/lib/emoji.sh" \
        "$REPO_ROOT/lib/gms_fonts.sh" \
        "$REPO_ROOT/tests/run_tests.sh"; then
        pass "ShellCheck passed with 0 warnings"
    else
        fail "ShellCheck reported issues"
    fi
else
    printf '  [SKIP] shellcheck not installed\n'
fi

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
