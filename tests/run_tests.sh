#!/bin/sh
# CoreType — Automated POSIX Test Suite (KernelSU-Umount-Safe Dual-Optical)

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

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Simulate HyperOS 3 stock /system/fonts/ (ONLY Roboto-Regular, RobotoStatic-Regular, RobotoFlex-Regular)
HOS3_FONTS="$TMP_DIR/hos3_fonts"
mkdir -p "$HOS3_FONTS"
for _mf in Roboto-Regular.ttf RobotoStatic-Regular.ttf RobotoFlex-Regular.ttf; do
    printf 'mockfont' > "$HOS3_FONTS/$_mf"
done

printf '=== Test 1: HyperOS 3 KernelSU-Umount-Safe Stock-Slot Allocation ===\n'
ct_resolve_stock_slots "$HOS3_FONTS"
if [ "$CT_SLOT_TEXT" = "Roboto-Regular.ttf" ] \
    && [ "$CT_SLOT_DISP" = "RobotoStatic-Regular.ttf" ] \
    && [ "$CT_SLOT_ITAL" = "RobotoFlex-Regular.ttf" ] \
    && [ "$CT_SLOT_DITAL" = "RobotoFlex-Regular.ttf" ]; then
    pass "HyperOS 3 slots mapped strictly onto existing stock files (zero non-stock filenames)"
else
    fail "Unexpected HyperOS 3 slots: text=$CT_SLOT_TEXT disp=$CT_SLOT_DISP ital=$CT_SLOT_ITAL dital=$CT_SLOT_DITAL"
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

if ct_patch_font_xml "$TMP_DIR/hyperos3_fallback.xml" "$TMP_DIR/nested/etc/font_fallback.xml" "dynamic_optical" "$HOS3_FONTS"; then
    pass "HyperOS 3 font_fallback.xml patched & validated cleanly (auto-created nested dir)"
    cp "$TMP_DIR/nested/etc/font_fallback.xml" "$TMP_DIR/font_fallback.xml"
else
    fail "HyperOS 3 font_fallback.xml patching failed"
fi

assert_not_grep 'CoreType-SFPro' "$TMP_DIR/font_fallback.xml" "Zero non-stock CoreType-SFPro filenames in XML (prevents KSU umount SIGSEGV)"
assert_grep 'CoreType Dual-Optical' "$TMP_DIR/font_fallback.xml" "Contains CoreType Dual-Optical XML marker"
assert_grep 'weight="400" style="normal">Roboto-Regular\.ttf' "$TMP_DIR/font_fallback.xml" "Body 400 routed to Text slot (Roboto-Regular.ttf)"
assert_grep 'weight="400" style="italic">RobotoFlex-Regular\.ttf' "$TMP_DIR/font_fallback.xml" "Body 400 italic routed to Italic slot (RobotoFlex-Regular.ttf)"
assert_grep 'weight="600" style="normal">RobotoStatic-Regular\.ttf' "$TMP_DIR/font_fallback.xml" "Header 600 routed to Display slot (RobotoStatic-Regular.ttf)"
assert_grep 'weight="700" style="italic">RobotoFlex-Regular\.ttf' "$TMP_DIR/font_fallback.xml" "Header 700 italic routed to Italic slot (RobotoFlex-Regular.ttf)"
assert_grep 'weight="100" style="normal">RobotoStatic-Regular\.ttf' "$TMP_DIR/font_fallback.xml" "Lockscreen clock 100 routed to Display slot (RobotoStatic-Regular.ttf)"
assert_not_grep 'supportedAxes="wght,ital"' "$TMP_DIR/font_fallback.xml" "Eliminated HyperOS 3 duplicate Roboto-Regular fallback overwrite"
assert_grep 'tag="wdth" stylevalue="96\.5"' "$TMP_DIR/font_fallback.xml" "Calibrated Text width wdth=96.5"
assert_grep 'tag="wdth" stylevalue="97\.0"' "$TMP_DIR/font_fallback.xml" "Calibrated Display width wdth=97.0"
assert_grep 'tag="wdth" stylevalue="82\.0"' "$TMP_DIR/font_fallback.xml" "Optical condensed width wdth=82.0"
assert_not_grep 'MiSansVF_Overlay\.ttf' "$TMP_DIR/font_fallback.xml" "Replaced MiSansVF_Overlay.ttf in sans-serif"
assert_not_grep 'MiSansLatinVF\.ttf' "$TMP_DIR/font_fallback.xml" "Replaced MiSansLatinVF.ttf in Latin family"
assert_grep 'MiSansArabicVF\.ttf' "$TMP_DIR/font_fallback.xml" "Preserved Arabic fallback"
assert_grep 'MiSansJapaneseVF\.ttf' "$TMP_DIR/font_fallback.xml" "Preserved Japanese fallback"
assert_grep 'NotoColorEmoji\.ttf' "$TMP_DIR/font_fallback.xml" "Preserved NotoColorEmoji fallback"
assert_grep 'CommentedOut\.ttf' "$TMP_DIR/font_fallback.xml" "Preserved commented-out <family> block verbatim"

printf '=== Test 2: Classic AOSP Stock-Slot Allocation (4 Distinct Slots) ===\n'
AOSP_FONTS="$TMP_DIR/aosp_fonts"
mkdir -p "$AOSP_FONTS"
for _mf in Roboto-Regular.ttf Roboto-Bold.ttf Roboto-Italic.ttf Roboto-BoldItalic.ttf; do
    printf 'mockfont' > "$AOSP_FONTS/$_mf"
done
ct_resolve_stock_slots "$AOSP_FONTS"
if [ "$CT_SLOT_TEXT" = "Roboto-Regular.ttf" ] \
    && [ "$CT_SLOT_DISP" = "Roboto-Bold.ttf" ] \
    && [ "$CT_SLOT_ITAL" = "Roboto-Italic.ttf" ] \
    && [ "$CT_SLOT_DITAL" = "Roboto-BoldItalic.ttf" ]; then
    pass "Classic AOSP resolves 4 distinct stock slots cleanly"
else
    fail "Unexpected AOSP slots: text=$CT_SLOT_TEXT disp=$CT_SLOT_DISP ital=$CT_SLOT_ITAL dital=$CT_SLOT_DITAL"
fi

cat > "$TMP_DIR/legacy_fonts.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<familyset version="22">
    <family name="sans-serif">
        <font weight="400" style="normal">Roboto-Regular.ttf</font>
    </family>
    <family>
        <font weight="400" style="normal">NotoColorEmoji.ttf</font>
    </family>
</familyset>
EOF

if ct_patch_font_xml "$TMP_DIR/legacy_fonts.xml" "$TMP_DIR/fonts.xml" "dynamic_optical" "$AOSP_FONTS"; then
    pass "Legacy fonts.xml patched & validated cleanly"
else
    fail "Legacy fonts.xml patching failed"
fi
assert_not_grep 'postScriptName=' "$TMP_DIR/fonts.xml" "XML cleanly omits postScriptName for umount safety"
assert_grep 'weight="700" style="normal">Roboto-Bold\.ttf' "$TMP_DIR/fonts.xml" "AOSP Display 700 routed to Roboto-Bold.ttf"
assert_grep 'weight="700" style="italic">Roboto-BoldItalic\.ttf' "$TMP_DIR/fonts.xml" "AOSP Display 700 italic routed to Roboto-BoldItalic.ttf"

printf '=== Test 3: Optical Profiles (native_pro & compact_crisp) ===\n'
ct_resolve_stock_slots "$HOS3_FONTS"
ct_patch_font_xml "$TMP_DIR/hyperos3_fallback.xml" "$TMP_DIR/out_native.xml" "native_pro" "$HOS3_FONTS"
assert_grep 'tag="wdth" stylevalue="100\.0"' "$TMP_DIR/out_native.xml" "native_pro uses uncompressed wdth=100.0"

ct_patch_font_xml "$TMP_DIR/hyperos3_fallback.xml" "$TMP_DIR/out_compact.xml" "compact_crisp" "$HOS3_FONTS"
assert_grep 'tag="wdth" stylevalue="91\.5"' "$TMP_DIR/out_compact.xml" "compact_crisp uses wdth=91.5 for text"
assert_grep 'tag="wdth" stylevalue="92\.0"' "$TMP_DIR/out_compact.xml" "compact_crisp uses wdth=92.0 for display"

printf '=== Test 4: Strict Structural XML Validator Rejects Corruption & Non-Stock Names ===\n'
printf '<familyset><!-- CoreType Dual-Optical --><family name="sans-serif"><font>Roboto-Regular.ttf</font><font>RobotoStatic-Regular.ttf</familyset>\n' > "$TMP_DIR/broken.xml"
if ct_validate_font_xml "$TMP_DIR/broken.xml" "$HOS3_FONTS"; then
    fail "Validator should reject unbalanced <family>/<font> XML"
else
    pass "Validator rejected unbalanced XML"
fi

printf '<familyset><!-- CoreType Dual-Optical --><family name="sans-serif"><font>CoreType-SFPro-Text.ttf</font></family></familyset>\n' > "$TMP_DIR/nonstock.xml"
if ct_validate_font_xml "$TMP_DIR/nonstock.xml" "$HOS3_FONTS"; then
    fail "Validator should reject non-stock CoreType-SFPro filenames"
else
    pass "Validator rejected non-stock filename (KSU umount guard)"
fi

if ct_validate_font_xml "$TMP_DIR/font_fallback.xml" "$TMP_DIR/missing_dir"; then
    fail "Validator should reject missing font directory"
else
    pass "Validator rejected missing font files"
fi

printf '=== Test 5: Config Helpers, Slot Persistence & Self-Healing Bootloop Guard ===\n'
CT_DATA_DIR="$TMP_DIR/data"
CT_CONF_FILE="$CT_DATA_DIR/config.conf"
CT_STATE_FILE="$CT_DATA_DIR/state.prop"
CT_LOG_FILE="$CT_DATA_DIR/coretype.log"
ct_conf_set "profile" "compact_crisp"
_got=$(ct_conf_get "profile" "dynamic_optical")
if [ "$_got" = "compact_crisp" ]; then
    pass "ct_conf_set / ct_conf_get round-trip"
else
    fail "ct_conf_get expected compact_crisp, got $_got"
fi

ct_resolve_stock_slots "$HOS3_FONTS"
ct_save_slots
CT_SLOT_TEXT="" CT_SLOT_DISP="" CT_SLOT_ITAL="" CT_SLOT_DITAL=""
ct_load_slots
if [ "$CT_SLOT_DISP" = "RobotoStatic-Regular.ttf" ] && [ "$CT_SLOT_ITAL" = "RobotoFlex-Regular.ttf" ]; then
    pass "ct_save_slots / ct_load_slots round-trip"
else
    fail "ct_load_slots failed"
fi

# Simulate 2 failed boots and verify post-fs-data.sh auto-disables module
FAKE_MOD="$TMP_DIR/mod"
mkdir -p "$FAKE_MOD/lib" "$FAKE_MOD/system/fonts"
cp "$REPO_ROOT/lib/"*.sh "$FAKE_MOD/lib/"
cp "$REPO_ROOT/post-fs-data.sh" "$FAKE_MOD/"
cp "$HOS3_FONTS/"*.ttf "$FAKE_MOD/system/fonts/"
printf '2\n' > "$CT_DATA_DIR/boot_attempts"
CT_DATA_DIR="$CT_DATA_DIR" sh "$FAKE_MOD/post-fs-data.sh"
if [ -f "$FAKE_MOD/disable" ]; then
    pass "Bootloop Guard auto-disabled module after 2 failed boots"
else
    fail "Bootloop Guard did not create disable flag"
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
