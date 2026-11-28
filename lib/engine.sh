#!/system/bin/sh
# shellcheck disable=SC2034
# CoreType — Unified Slot-Sync, Universal HyperOS MiSans Slider & OTA-Safe XML Engine
# Shared by customize.sh (install) and post-fs-data.sh (profile switch & OTA auto-resync).
# Compatible with HyperOS 1 / 2 / 3 / 4 and Android 12–17.

ct_verify_ttf() {
    _f="$1"
    [ -f "$_f" ] || return 1
    _sz=$(ct_file_size "$_f")
    [ "$_sz" -gt 102400 ] || return 1
    if command -v od >/dev/null 2>&1; then
        _magic=$(od -An -tx1 -N4 "$_f" 2>/dev/null | tr -d ' \n\r')
        [ "$_magic" = "00010000" ] || return 1
    fi
    return 0
}

ct_verify_all_masters() {
    _src_dir="$1"
    for _mf in \
        CoreType-SFPro-Text.ttf \
        CoreType-SFPro-Text-Italic.ttf \
        CoreType-SFPro-Display.ttf \
        CoreType-SFPro-Display-Italic.ttf; do
        if ! ct_verify_ttf "$_src_dir/$_mf"; then
            # shellcheck disable=SC2034
            CT_FAILED_MASTER="$_mf"
            return 1
        fi
    done
    for _opt in \
        CoreType-SFPro-Flex.ttf \
        CoreType-SFPro-GMS-Medium.ttf \
        CoreType-SFPro-GMS-Bold.ttf; do
        if [ -f "$_src_dir/$_opt" ] && ! ct_verify_ttf "$_src_dir/$_opt"; then
            # shellcheck disable=SC2034
            CT_FAILED_MASTER="$_opt"
            return 1
        fi
    done
    return 0
}

# Verify HyperOS Lockscreen/AOD -> Homescreen clock typography parity:
#   - Never overwrite stock MiClock*.otf fonts
#   - Confirm Display/Flex SF Pro masters carrying tnum (tabular numerals) & calt (09:41 colon) are intact
ct_verify_hyperos_clock_parity() {
    _moddir="$1"
    # Ensure no MiClock*.otf was ever accidentally staged inside module overlays
    rm -f "$_moddir/system/fonts"/MiClock*.otf "$_moddir/system/product/fonts"/MiClock*.otf 2>/dev/null || true
    ct_verify_ttf "$_moddir/fonts/CoreType-SFPro-Display.ttf" || return 1
    return 0
}

ct_sync_font_file() {
    _src_f="$1"
    _dst_f="$2"
    mkdir -p "$(dirname "$_dst_f")"
    ln -f "$_src_f" "$_dst_f" 2>/dev/null || cp -f "$_src_f" "$_dst_f"
    chmod 0644 "$_dst_f" 2>/dev/null || true
}

# Detect a verified separate CJK fallback font accessible in /system/fonts/ (other than MiSansVF.ttf).
# Requiring presence in /system/fonts/ guarantees font_fallback.xml resolution & KernelSU-umount safety.
# Sets: CT_CJK_FALLBACK
ct_resolve_cjk_fallback() {
    _sys_fdir="${1:-/system/fonts}"
    CT_CJK_FALLBACK=""

    for _cand in MiSansTCVF.ttf MiSansL3.otf NotoSansCJK-Regular.ttc; do
        if [ -e "$_sys_fdir/$_cand" ]; then
            CT_CJK_FALLBACK="$_cand"
            return 0
        fi
    done
    return 1
}

# Populate module's /system/fonts & /system/product/fonts using shared-inode hardlinks
# strictly onto existing stock slots (KernelSU-umount-safe, zero extra RAM/disk duplication).
# Usage: ct_sync_stock_slots <moddir> [sys_fonts_dir] [product_fonts_dir]
ct_sync_stock_slots() {
    _moddir="$1"
    _sys_fdir="${2:-/system/fonts}"
    _prod_fdir="${3:-/product/fonts}"
    _src_fonts="$_moddir/fonts"

    ct_resolve_stock_slots "$_sys_fdir"
    ct_resolve_cjk_fallback "$_sys_fdir" "$_prod_fdir" || true
    CT_MISANS_SLIDER_ACTIVE="0"

    # Clean stale font files before re-syncing (prevents leftover files after OTA slot change)
    rm -rf "$_moddir/system/fonts" "$_moddir/system/product/fonts" "$_moddir/system/system_ext/fonts" 2>/dev/null || true
    mkdir -p "$_moddir/system/fonts"

    ct_sync_font_file "$_src_fonts/CoreType-SFPro-Text.ttf" "$_moddir/system/fonts/$CT_SLOT_TEXT"
    if [ "$CT_SLOT_DISP" != "$CT_SLOT_TEXT" ]; then
        ct_sync_font_file "$_src_fonts/CoreType-SFPro-Display.ttf" "$_moddir/system/fonts/$CT_SLOT_DISP"
    fi
    if [ "$CT_SLOT_FLEX" != "$CT_SLOT_TEXT" ] && [ "$CT_SLOT_FLEX" != "$CT_SLOT_DISP" ]; then
        if [ -f "$_src_fonts/CoreType-SFPro-Flex.ttf" ]; then
            ct_sync_font_file "$_src_fonts/CoreType-SFPro-Flex.ttf" "$_moddir/system/fonts/$CT_SLOT_FLEX"
        else
            ct_sync_font_file "$_src_fonts/CoreType-SFPro-Text.ttf" "$_moddir/system/fonts/$CT_SLOT_FLEX"
        fi
    fi
    if [ "$CT_SLOT_ITAL" != "$CT_SLOT_TEXT" ] \
        && [ "$CT_SLOT_ITAL" != "$CT_SLOT_DISP" ] \
        && [ "$CT_SLOT_ITAL" != "$CT_SLOT_FLEX" ]; then
        ct_sync_font_file "$_src_fonts/CoreType-SFPro-Text-Italic.ttf" "$_moddir/system/fonts/$CT_SLOT_ITAL"
    fi
    if [ "$CT_SLOT_DITAL" != "$CT_SLOT_ITAL" ] \
        && [ "$CT_SLOT_DITAL" != "$CT_SLOT_TEXT" ] \
        && [ "$CT_SLOT_DITAL" != "$CT_SLOT_DISP" ] \
        && [ "$CT_SLOT_DITAL" != "$CT_SLOT_FLEX" ]; then
        ct_sync_font_file "$_src_fonts/CoreType-SFPro-Display-Italic.ttf" "$_moddir/system/fonts/$CT_SLOT_DITAL"
    fi

    # HyperOS Latin font slots across /system/fonts, /product/fonts, and /system_ext/fonts
    for _extra_font in MiSansVF_Overlay.ttf MiSansLatinVF.ttf MiSansGlobalVF.ttf; do
        if [ -e "$_sys_fdir/$_extra_font" ]; then
            ct_sync_font_file "$_src_fonts/CoreType-SFPro-Text.ttf" "$_moddir/system/fonts/$_extra_font"
        fi
        if [ -e "$_prod_fdir/$_extra_font" ] || [ -e "/system$_prod_fdir/$_extra_font" ]; then
            ct_sync_font_file "$_src_fonts/CoreType-SFPro-Text.ttf" "$_moddir/system/product/fonts/$_extra_font"
        fi
        if [ "$_sys_fdir" = "/system/fonts" ] && { [ -e "/system_ext/fonts/$_extra_font" ] || [ -e "/system/system_ext/fonts/$_extra_font" ]; }; then
            ct_sync_font_file "$_src_fonts/CoreType-SFPro-Text.ttf" "$_moddir/system/system_ext/fonts/$_extra_font"
        fi
    done

    # Universal HyperOS MiSans + Font Weight Slider Support (HyperOS 1/2/3/4):
    # ONLY enabled when a separate CJK fallback exists on the ROM (zero CJK tofu boxes!).
    if [ -n "$CT_CJK_FALLBACK" ]; then
        for _mi_vf in MiSansVF.ttf MiLanProVF.ttf MiSans-Regular.ttf; do
            if [ -e "$_sys_fdir/$_mi_vf" ]; then
                ct_sync_font_file "$_src_fonts/CoreType-SFPro-Text.ttf" "$_moddir/system/fonts/$_mi_vf"
                CT_MISANS_SLIDER_ACTIVE="1"
            fi
            if [ -e "$_prod_fdir/$_mi_vf" ] || [ -e "/system$_prod_fdir/$_mi_vf" ]; then
                ct_sync_font_file "$_src_fonts/CoreType-SFPro-Text.ttf" "$_moddir/system/product/fonts/$_mi_vf"
                CT_MISANS_SLIDER_ACTIVE="1"
            fi
            if [ "$_sys_fdir" = "/system/fonts" ] && { [ -e "/system_ext/fonts/$_mi_vf" ] || [ -e "/system/system_ext/fonts/$_mi_vf" ]; }; then
                ct_sync_font_file "$_src_fonts/CoreType-SFPro-Text.ttf" "$_moddir/system/system_ext/fonts/$_mi_vf"
                CT_MISANS_SLIDER_ACTIVE="1"
            fi
        done
    fi

    ct_save_slots
}

# Snapshot stock XMLs (refreshing on OTA) and emit strictly validated Dual-Optical XMLs.
# Usage: ct_patch_all_xmls <moddir> <profile> [force_resnapshot:0|1] [root_prefix]
# Sets: CT_PATCHED_COUNT
ct_patch_all_xmls() {
    _moddir="$1"
    _prof="$2"
    _force_snap="${3:-0}"
    _root="${4:-}"

    _stock_dir="$CT_DATA_DIR/stock_xml"
    mkdir -p "$_stock_dir"
    CT_PATCHED_COUNT=0

    # Standard AOSP 12-16 & HyperOS 1/2/3/4 /system/etc XML targets
    for _xml_name in font_fallback.xml fonts.xml; do
        _bak_xml="$_stock_dir/$_xml_name"
        _dst_xml="$_moddir/system/etc/$_xml_name"

        _live_xml=""
        for _cand in "$_root/system/etc/$_xml_name" "$_root/product/etc/$_xml_name" "$_root/system_ext/etc/$_xml_name"; do
            if [ -r "$_cand" ]; then
                _live_xml="$_cand"
                break
            fi
        done

        if [ -n "$_live_xml" ] && { [ "$_force_snap" = "1" ] || [ ! -s "$_bak_xml" ]; }; then
            if ! grep -q 'CoreType' "$_live_xml" 2>/dev/null; then
                _btmp="$_bak_xml.tmp.$$"
                if cat "$_live_xml" > "$_btmp" 2>/dev/null && mv "$_btmp" "$_bak_xml" 2>/dev/null; then
                    :
                else
                    rm -f "$_btmp" 2>/dev/null || true
                fi
            fi
        fi

        _src_xml="$_bak_xml"
        [ -s "$_src_xml" ] || _src_xml="$_live_xml"

        if [ -n "$_src_xml" ] && [ -s "$_src_xml" ]; then
            if ct_patch_font_xml "$_src_xml" "$_dst_xml" "$_prof" "$_moddir/system/fonts"; then
                chmod 0644 "$_dst_xml" 2>/dev/null || true
                CT_PATCHED_COUNT=$((CT_PATCHED_COUNT + 1))
            fi
        fi
    done

    # HyperOS 3/4 /system_ext/etc/hyper_font_fallback.xml & hyper_fonts.xml targets
    for _hxml in hyper_font_fallback.xml hyper_fonts.xml; do
        _hbak="$_stock_dir/$_hxml"
        _hdst="$_moddir/system/system_ext/etc/$_hxml"

        _hsrc="$_root/system_ext/etc/$_hxml"
        [ -r "$_hsrc" ] || _hsrc="$_root/system/system_ext/etc/$_hxml"

        if [ -r "$_hsrc" ] && { [ "$_force_snap" = "1" ] || [ ! -s "$_hbak" ]; }; then
            if ! grep -q 'CoreType' "$_hsrc" 2>/dev/null; then
                _hbtmp="$_hbak.tmp.$$"
                if cat "$_hsrc" > "$_hbtmp" 2>/dev/null && mv "$_hbtmp" "$_hbak" 2>/dev/null; then
                    :
                else
                    rm -f "$_hbtmp" 2>/dev/null || true
                fi
            fi
        fi

        _huse="$_hbak"
        [ -s "$_huse" ] || _huse="$_hsrc"

        if [ -n "$_huse" ] && [ -s "$_huse" ]; then
            if ct_patch_font_xml "$_huse" "$_hdst" "$_prof" "$_moddir/system/fonts"; then
                chmod 0644 "$_hdst" 2>/dev/null || true
                CT_PATCHED_COUNT=$((CT_PATCHED_COUNT + 1))
            fi
        fi
    done

    [ "$CT_PATCHED_COUNT" -gt 0 ]
}
