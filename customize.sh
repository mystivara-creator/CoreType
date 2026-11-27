#!/system/bin/sh
# CoreType — KernelSU-Umount-Safe Zero-Bootloop Installer

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

ct_sync_font_file() {
    _src_f="$1"
    _dst_f="$2"
    mkdir -p "$(dirname "$_dst_f")"
    ln -f "$_src_f" "$_dst_f" 2>/dev/null || cp -f "$_src_f" "$_dst_f"
}

ct_ui_print " "
ct_ui_print "============================================="
ct_ui_print "  CoreType — Dual-Optical SF Pro v1.0.0"
ct_ui_print "  by Mystivara | Zero LSPosed"
ct_ui_print "============================================="

SRC_FONTS="$MODPATH/fonts"

# 1. Pre-flight binary integrity verification of all 4 optical masters
for _font_file in \
    CoreType-SFPro-Text.ttf \
    CoreType-SFPro-Text-Italic.ttf \
    CoreType-SFPro-Display.ttf \
    CoreType-SFPro-Display-Italic.ttf; do
    if ! ct_verify_ttf "$SRC_FONTS/$_font_file"; then
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

# 2. KernelSU-Umount-Safe Stock-Slot Allocation:
#    Map all 4 Dual-Optical masters strictly onto EXISTING stock filenames in /system/fonts/.
#    Zero new filenames are ever added to font_fallback.xml -> 0% SIGSEGV in umounted apps!
ct_resolve_stock_slots "/system/fonts"
ct_save_slots

ct_ui_print "- Profile: $CT_PROFILE_LABEL ($CT_PROFILE)"
ct_ui_print "- KernelSU-Umount-Safe Stock Slots:"
ct_ui_print "  Text    (opsz 17) -> $CT_SLOT_TEXT"
ct_ui_print "  Display (opsz 28) -> $CT_SLOT_DISP"
ct_ui_print "  Italic  (opsz 17) -> $CT_SLOT_ITAL"
ct_ui_print "  DispIt  (opsz 28) -> $CT_SLOT_DITAL"

mkdir -p "$MODPATH/system/fonts"
ct_sync_font_file "$SRC_FONTS/CoreType-SFPro-Text.ttf" "$MODPATH/system/fonts/$CT_SLOT_TEXT"
if [ "$CT_SLOT_DISP" != "$CT_SLOT_TEXT" ]; then
    ct_sync_font_file "$SRC_FONTS/CoreType-SFPro-Display.ttf" "$MODPATH/system/fonts/$CT_SLOT_DISP"
fi
if [ "$CT_SLOT_ITAL" != "$CT_SLOT_TEXT" ] && [ "$CT_SLOT_ITAL" != "$CT_SLOT_DISP" ]; then
    ct_sync_font_file "$SRC_FONTS/CoreType-SFPro-Text-Italic.ttf" "$MODPATH/system/fonts/$CT_SLOT_ITAL"
fi
if [ "$CT_SLOT_DITAL" != "$CT_SLOT_ITAL" ] && [ "$CT_SLOT_DITAL" != "$CT_SLOT_TEXT" ] && [ "$CT_SLOT_DITAL" != "$CT_SLOT_DISP" ]; then
    ct_sync_font_file "$SRC_FONTS/CoreType-SFPro-Display-Italic.ttf" "$MODPATH/system/fonts/$CT_SLOT_DITAL"
fi

# HyperOS Latin font slots (NEVER touches CJK MiSansVF.ttf, Arabic, MiClock, or Emoji)
for _extra_font in MiSansVF_Overlay.ttf MiSansLatinVF.ttf; do
    if [ -e "/system/fonts/$_extra_font" ]; then
        ct_sync_font_file "$SRC_FONTS/CoreType-SFPro-Text.ttf" "$MODPATH/system/fonts/$_extra_font"
        ct_ui_print "- Synced /system/fonts/$_extra_font (shared inode)"
    fi
done

if [ -f /product/fonts/MiSansLatinVF.ttf ] || [ -f /system/product/fonts/MiSansLatinVF.ttf ]; then
    ct_sync_font_file "$SRC_FONTS/CoreType-SFPro-Text.ttf" "$MODPATH/system/product/fonts/MiSansLatinVF.ttf"
    ct_ui_print "- Synced /product/fonts/MiSansLatinVF.ttf (shared inode)"
fi

# 3. Snapshot stock XMLs once and generate strictly validated Dual-Optical XMLs
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
        if ! grep -q 'CoreType' "$_live_xml" 2>/dev/null; then
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

# HyperOS 3 /system_ext/etc/hyper_font_fallback.xml & hyper_fonts.xml targets
for _hxml in hyper_font_fallback.xml hyper_fonts.xml; do
    _hsrc="/system_ext/etc/$_hxml"
    [ -r "$_hsrc" ] || _hsrc="/system/system_ext/etc/$_hxml"
    if [ -r "$_hsrc" ]; then
        _hbak="$STOCK_DIR/$_hxml"
        if [ ! -r "$_hbak" ] && ! grep -q 'CoreType' "$_hsrc" 2>/dev/null; then
            cat "$_hsrc" > "$_hbak" 2>/dev/null || true
        fi
        _huse="$_hbak"
        [ -r "$_huse" ] || _huse="$_hsrc"
        if ct_patch_font_xml "$_huse" "$MODPATH/system/system_ext/etc/$_hxml" "$CT_PROFILE" "$MODPATH/system/fonts"; then
            ct_ui_print "- Patched /system_ext/etc/$_hxml (HyperOS theme_webview target)"
            PATCHED_COUNT=$((PATCHED_COUNT + 1))
        fi
    fi
done

if [ "$PATCHED_COUNT" -eq 0 ]; then
    abort "! Failed to patch any system font XML safely. Aborting with zero changes."
fi

# Note if user has an active HyperOS Theme Store font overriding system fonts
if [ -s /data/system/theme/fonts/Roboto-Regular.ttf ]; then
    ct_ui_print " "
    ct_ui_print "! Notice: Custom Xiaomi Theme font detected in /data/system/theme/fonts/."
    ct_ui_print "  To see Dual-Optical SF Pro everywhere, select 'Default' or 'MiSans'"
    ct_ui_print "  in Settings -> Display -> Font after rebooting."
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ct_state_set "profile" "$CT_PROFILE"
ct_state_set "profile_label" "$CT_PROFILE_LABEL"
ct_state_set "patched_xmls" "$PATCHED_COUNT"
ct_state_set "slot_text" "$CT_SLOT_TEXT"
ct_state_set "slot_disp" "$CT_SLOT_DISP"
ct_state_set "slot_ital" "$CT_SLOT_ITAL"
ct_state_set "bootloop_guard" "armed"
ct_log "Installed CoreType v1.0.0 (umount-safe slots: text=$CT_SLOT_TEXT disp=$CT_SLOT_DISP ital=$CT_SLOT_ITAL)"

ct_ui_print "- Self-Healing Bootloop Guard: ARMED"
ct_ui_print "- Installation complete! Reboot to enjoy Native iOS SF Pro."
ct_ui_print " "
