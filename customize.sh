#!/system/bin/sh
# CoreType — Zero-Bootloop Magisk / KernelSU / APatch Installer

# shellcheck disable=SC2034
SKIPUNZIP=0

# shellcheck disable=SC1091
. "$MODPATH/lib/common.sh"
# shellcheck disable=SC1091
. "$MODPATH/lib/profiles.sh"
# shellcheck disable=SC1091
. "$MODPATH/lib/font_xml.sh"

ct_ui_print() {
    if command -v ui_print >/dev/null 2>&1; then
        ui_print "$1"
    else
        printf '%s\n' "$1"
    fi
}

ct_verify_ttf() {
    _f="$1"
    [ -f "$_f" ] || return 1
    # Must be > 100 KB and start with valid TrueType sfnt version (00 01 00 00)
    _sz=$(wc -c < "$_f" 2>/dev/null || echo 0)
    [ "$_sz" -gt 102400 ] || return 1
    _magic=$(od -An -tx1 -N4 "$_f" 2>/dev/null | tr -d ' \n\r')
    [ "$_magic" = "00010000" ] || return 1
    return 0
}

ct_ui_print " "
ct_ui_print "============================================="
ct_ui_print "  CoreType — Dual-Optical SF Pro v1.0.0"
ct_ui_print "  by Mystivara | Zero LSPosed"
ct_ui_print "============================================="

# 1. Pre-flight binary integrity verification of all 4 optical masters
for _font_file in \
    CoreType-SFPro-Text.ttf \
    CoreType-SFPro-Text-Italic.ttf \
    CoreType-SFPro-Display.ttf \
    CoreType-SFPro-Display-Italic.ttf; do
    if ! ct_verify_ttf "$MODPATH/system/fonts/$_font_file"; then
        abort "! Integrity check failed: $_font_file is missing or corrupt."
    fi
done
ct_ui_print "- Verified all 4 Dual-Optical SF Pro variable masters"

ct_init_dirs
STOCK_DIR="$CT_DATA_DIR/stock_xml"
mkdir -p "$STOCK_DIR"

# Reset Bootloop Guard counter on fresh install
printf '0\n' > "$CT_DATA_DIR/boot_attempts"

ACTIVE_PROFILE=$(ct_conf_get "profile" "dynamic_optical")
if ! ct_profile_valid "$ACTIVE_PROFILE"; then
    ACTIVE_PROFILE="dynamic_optical"
fi
ct_load_profile "$ACTIVE_PROFILE"
ct_conf_set "profile" "$CT_PROFILE"
ct_conf_set "applied_profile" "$CT_PROFILE"

ct_ui_print "- Profile: $CT_PROFILE_LABEL ($CT_PROFILE)"
ct_ui_print "  Text opsz=17 (-46 trak, wdth=$CT_WDTH_TEXT)"
ct_ui_print "  Display opsz=28 (-26 trak, wdth=$CT_WDTH_DISP)"

# 2. Snapshot stock XMLs once (follows HyperOS /data/system/fonts/theme_webview symlinks)
#    and generate strictly validated, schema-faithful optical XMLs.
PATCHED_COUNT=0
for _xml_name in font_fallback.xml fonts.xml; do
    _bak_xml="$STOCK_DIR/$_xml_name"
    _dst_xml="$MODPATH/system/etc/$_xml_name"

    _live_xml=""
    for _cand in "/system/etc/$_xml_name" "/product/etc/$_xml_name" "/system_ext/etc/$_xml_name"; do
        if [ -r "$_cand" ]; then
            _live_xml="$_cand"
            break
        fi
    done

    if [ ! -r "$_bak_xml" ] && [ -n "$_live_xml" ]; then
        if ! grep -q 'CoreType-SFPro' "$_live_xml" 2>/dev/null; then
            cat "$_live_xml" > "$_bak_xml" 2>/dev/null || true
        fi
    fi

    _src_xml="$_bak_xml"
    [ -r "$_src_xml" ] || _src_xml="$_live_xml"

    if [ -n "$_src_xml" ] && [ -r "$_src_xml" ]; then
        if ct_patch_font_xml "$_src_xml" "$_dst_xml" "$CT_PROFILE" "$MODPATH/system/fonts"; then
            ct_ui_print "- Patched /system/etc/$_xml_name (100% ROM fallbacks preserved)"
            PATCHED_COUNT=$((PATCHED_COUNT + 1))
        else
            ct_ui_print "! Warning: skipped $_xml_name (strict XML guard)"
        fi
    fi
done

if [ "$PATCHED_COUNT" -eq 0 ]; then
    abort "! Failed to patch any system font XML safely. Aborting with zero changes."
fi

# 3. SELinux-safe real file copies (no symlinks) for apps loading Latin font paths directly.
#    NEVER touches MiSansVF.ttf (CJK), MiSansArabicVF.ttf, MiClock*.otf, or NotoColorEmoji.ttf.
if [ -f /system/fonts/Roboto-Regular.ttf ]; then
    cp -f "$MODPATH/system/fonts/CoreType-SFPro-Text.ttf" "$MODPATH/system/fonts/Roboto-Regular.ttf"
    ct_ui_print "- Synced Roboto-Regular.ttf (SELinux-safe copy)"
fi

if [ -f /system/fonts/RobotoStatic-Regular.ttf ]; then
    cp -f "$MODPATH/system/fonts/CoreType-SFPro-Text.ttf" "$MODPATH/system/fonts/RobotoStatic-Regular.ttf"
    ct_ui_print "- Synced RobotoStatic-Regular.ttf (SELinux-safe copy)"
fi

if [ -f /product/fonts/MiSansLatinVF.ttf ] || [ -f /system/product/fonts/MiSansLatinVF.ttf ]; then
    mkdir -p "$MODPATH/system/product/fonts"
    cp -f "$MODPATH/system/fonts/CoreType-SFPro-Text.ttf" "$MODPATH/system/product/fonts/MiSansLatinVF.ttf"
    ct_ui_print "- Synced HyperOS MiSansLatinVF.ttf (SELinux-safe copy)"
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ct_state_set "profile" "$CT_PROFILE"
ct_state_set "profile_label" "$CT_PROFILE_LABEL"
ct_state_set "patched_xmls" "$PATCHED_COUNT"
ct_state_set "bootloop_guard" "armed"
ct_log "Installed CoreType v1.0.0 Dual-Optical with profile=$CT_PROFILE patched_xmls=$PATCHED_COUNT"

ct_ui_print "- Self-Healing Bootloop Guard: ARMED"
ct_ui_print "- Installation complete! Reboot to enjoy Native iOS SF Pro."
ct_ui_print " "
