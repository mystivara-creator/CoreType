#!/bin/sh
# CoreType — Automated POSIX Test Suite

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

printf '=== Test 1: HyperOS 3 font_fallback.xml Optical Patching ===\n'
cat > "$TMP_DIR/hyperos3_fallback.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<familyset>
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

if ct_patch_font_xml "$TMP_DIR/hyperos3_fallback.xml" "$TMP_DIR/out_hos3.xml" "dynamic_optical"; then
    pass "HyperOS 3 XML patched cleanly"
else
    fail "HyperOS 3 XML patching failed"
fi

assert_grep 'CoreType-SFPro\.ttf' "$TMP_DIR/out_hos3.xml" "Injected CoreType-SFPro.ttf"
assert_grep 'CoreType-SFPro-Italic\.ttf' "$TMP_DIR/out_hos3.xml" "Injected CoreType-SFPro-Italic.ttf"
assert_grep 'tag="opsz" stylevalue="17\.0"' "$TMP_DIR/out_hos3.xml" "Body text mapped to opsz=17.0 (SF Pro Text)"
assert_grep 'tag="opsz" stylevalue="26\.0"' "$TMP_DIR/out_hos3.xml" "Semibold header mapped to opsz=26.0 (SF Pro Display)"
assert_grep 'tag="opsz" stylevalue="28\.0"' "$TMP_DIR/out_hos3.xml" "Bold/Clock mapped to opsz=28.0 (SF Pro Display)"
assert_grep 'tag="wdth" stylevalue="91\.0"' "$TMP_DIR/out_hos3.xml" "Calibrated body width wdth=91.0"
assert_grep 'tag="wdth" stylevalue="89\.0"' "$TMP_DIR/out_hos3.xml" "Calibrated display width wdth=89.0"
assert_grep 'tag="wdth" stylevalue="78\.0"' "$TMP_DIR/out_hos3.xml" "Native optical condensed wdth=78.0"
assert_not_grep 'MiSansVF_Overlay\.ttf' "$TMP_DIR/out_hos3.xml" "Replaced MiSansVF_Overlay.ttf in sans-serif"
assert_not_grep 'MiSansLatinVF\.ttf' "$TMP_DIR/out_hos3.xml" "Replaced MiSansLatinVF.ttf in Latin family"
assert_grep 'MiSansArabicVF\.ttf' "$TMP_DIR/out_hos3.xml" "Preserved Arabic fallback"
assert_grep 'MiSansJapaneseVF\.ttf' "$TMP_DIR/out_hos3.xml" "Preserved Japanese fallback"
assert_grep 'NotoColorEmoji\.ttf' "$TMP_DIR/out_hos3.xml" "Preserved NotoColorEmoji fallback"

printf '=== Test 2: Optical Profiles (native_pro & compact_crisp) ===\n'
ct_patch_font_xml "$TMP_DIR/hyperos3_fallback.xml" "$TMP_DIR/out_native.xml" "native_pro"
assert_grep 'tag="wdth" stylevalue="98\.0"' "$TMP_DIR/out_native.xml" "native_pro uses wdth=98.0 for text"
assert_grep 'tag="wdth" stylevalue="96\.0"' "$TMP_DIR/out_native.xml" "native_pro uses wdth=96.0 for display"

ct_patch_font_xml "$TMP_DIR/hyperos3_fallback.xml" "$TMP_DIR/out_compact.xml" "compact_crisp"
assert_grep 'tag="wdth" stylevalue="86\.0"' "$TMP_DIR/out_compact.xml" "compact_crisp uses wdth=86.0 for text"
assert_grep 'tag="wdth" stylevalue="84\.5"' "$TMP_DIR/out_compact.xml" "compact_crisp uses wdth=84.5 for display"

printf '=== Test 3: Config Helpers ===\n'
CT_DATA_DIR="$TMP_DIR/data"
CT_CONF_FILE="$CT_DATA_DIR/config.conf"
ct_conf_set "profile" "compact_crisp"
_got=$(ct_conf_get "profile" "dynamic_optical")
if [ "$_got" = "compact_crisp" ]; then
    pass "ct_conf_set / ct_conf_get round-trip"
else
    fail "ct_conf_get expected compact_crisp, got $_got"
fi

printf '=== Test 4: ShellCheck Static Analysis ===\n'
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
