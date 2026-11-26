#!/system/bin/sh
# CoreType — Magisk / KernelSU / APatch Installer

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

ct_ui_print " "
ct_ui_print "============================================="
ct_ui_print "  CoreType — Optical SF Pro Engine v1.0.0"
ct_ui_print "  by mystivara | Zero LSPosed"
ct_ui_print "============================================="

if [ ! -f "$MODPATH/system/fonts/CoreType-SFPro.ttf" ]; then
    abort "! Missing CoreType-SFPro.ttf in module package."
fi

ct_init_dirs
STOCK_DIR="$CT_DATA_DIR/stock_xml"
mkdir -p "$STOCK_DIR"

ACTIVE_PROFILE=$(ct_conf_get "profile" "dynamic_optical")
if ! ct_profile_valid "$ACTIVE_PROFILE"; then
    ACTIVE_PROFILE="dynamic_optical"
fi
ct_load_profile "$ACTIVE_PROFILE"
ct_conf_set "profile" "$CT_PROFILE"
ct_conf_set "applied_profile" "$CT_PROFILE"

ct_ui_print "- Profile: $CT_PROFILE_LABEL ($CT_PROFILE)"
ct_ui_print "  Body opsz=17 (wdth=$CT_WDTH_TEXT) | Header opsz=26..28 (wdth=$CT_WDTH_DISP)"

# Snapshot stock XMLs once (follows HyperOS /data/system/fonts/theme_webview symlinks)
PATCHED_COUNT=0
for _xml_name in font_fallback.xml fonts.xml; do
    _sys_xml="/system/etc/$_xml_name"
    _bak_xml="$STOCK_DIR/$_xml_name"
    _dst_xml="$MODPATH/system/etc/$_xml_name"

    if [ ! -r "$_bak_xml" ] && [ -r "$_sys_xml" ]; then
        if ! grep -q 'CoreType-SFPro\.ttf' "$_sys_xml" 2>/dev/null; then
            cat "$_sys_xml" > "$_bak_xml" 2>/dev/null || true
        fi
    fi

    _src_xml="$_bak_xml"
    [ -r "$_src_xml" ] || _src_xml="$_sys_xml"

    if [ -r "$_src_xml" ]; then
        if ct_patch_font_xml "$_src_xml" "$_dst_xml" "$CT_PROFILE"; then
            ct_ui_print "- Patched /system/etc/$_xml_name (preserved all ROM fallbacks)"
            PATCHED_COUNT=$((PATCHED_COUNT + 1))
        else
            ct_ui_print "! Warning: skipped $_xml_name (validation guard)"
        fi
    fi
done

if [ "$PATCHED_COUNT" -eq 0 ]; then
    abort "! Failed to patch any system font XML configuration."
fi

# Direct filename compatibility links (apps/SystemUI loading Roboto or MiSansLatinVF directly)
if [ -f /system/fonts/Roboto-Regular.ttf ]; then
    ln -sf CoreType-SFPro.ttf "$MODPATH/system/fonts/Roboto-Regular.ttf"
    ct_ui_print "- Linked Roboto-Regular.ttf -> CoreType-SFPro.ttf"
fi

if [ -f /product/fonts/MiSansLatinVF.ttf ] || [ -f /system/product/fonts/MiSansLatinVF.ttf ]; then
    mkdir -p "$MODPATH/system/product/fonts"
    ln -sf /system/fonts/CoreType-SFPro.ttf "$MODPATH/system/product/fonts/MiSansLatinVF.ttf"
    ct_ui_print "- Linked HyperOS MiSansLatinVF.ttf -> CoreType-SFPro.ttf"
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ct_state_set "profile" "$CT_PROFILE"
ct_state_set "profile_label" "$CT_PROFILE_LABEL"
ct_state_set "patched_xmls" "$PATCHED_COUNT"
ct_log "Installed CoreType v1.0.0 with profile=$CT_PROFILE patched_xmls=$PATCHED_COUNT"

ct_ui_print "- Installation complete! Reboot to enjoy Optical SF Pro."
ct_ui_print " "
