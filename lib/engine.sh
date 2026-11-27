#!/system/bin/sh
# CoreType — Unified Slot-Sync & OTA-Safe XML Orchestration Engine
# Shared by customize.sh (install) and post-fs-data.sh (profile switch & OTA auto-resync).

ct_verify_ttf() {
    _f="$1"
    [ -f "$_f" ] || return 1
    _sz=$(wc -c < "$_f" 2>/dev/null || echo 0)
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
    return 0
}

ct_sync_font_file() {
    _src_f="$1"
    _dst_f="$2"
    mkdir -p "$(dirname "$_dst_f")"
    ln -f "$_src_f" "$_dst_f" 2>/dev/null || cp -f "$_src_f" "$_dst_f"
    chmod 0644 "$_dst_f" 2>/dev/null || true
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
    ct_save_slots

    # Clean stale font files before re-syncing (prevents leftover files after OTA slot change)
    rm -rf "$_moddir/system/fonts" "$_moddir/system/product/fonts" 2>/dev/null || true
    mkdir -p "$_moddir/system/fonts"

    ct_sync_font_file "$_src_fonts/CoreType-SFPro-Text.ttf" "$_moddir/system/fonts/$CT_SLOT_TEXT"
    if [ "$CT_SLOT_DISP" != "$CT_SLOT_TEXT" ]; then
        ct_sync_font_file "$_src_fonts/CoreType-SFPro-Display.ttf" "$_moddir/system/fonts/$CT_SLOT_DISP"
    fi
    if [ "$CT_SLOT_ITAL" != "$CT_SLOT_TEXT" ] && [ "$CT_SLOT_ITAL" != "$CT_SLOT_DISP" ]; then
        ct_sync_font_file "$_src_fonts/CoreType-SFPro-Text-Italic.ttf" "$_moddir/system/fonts/$CT_SLOT_ITAL"
    fi
    if [ "$CT_SLOT_DITAL" != "$CT_SLOT_ITAL" ] \
        && [ "$CT_SLOT_DITAL" != "$CT_SLOT_TEXT" ] \
        && [ "$CT_SLOT_DITAL" != "$CT_SLOT_DISP" ]; then
        ct_sync_font_file "$_src_fonts/CoreType-SFPro-Display-Italic.ttf" "$_moddir/system/fonts/$CT_SLOT_DITAL"
    fi

    # HyperOS Latin font slots (NEVER touches CJK MiSansVF.ttf, Arabic, MiClock, or Emoji)
    for _extra_font in MiSansVF_Overlay.ttf MiSansLatinVF.ttf; do
        if [ -e "$_sys_fdir/$_extra_font" ]; then
            ct_sync_font_file "$_src_fonts/CoreType-SFPro-Text.ttf" "$_moddir/system/fonts/$_extra_font"
        fi
    done

    if [ -e "$_prod_fdir/MiSansLatinVF.ttf" ] || [ -e "/system$_prod_fdir/MiSansLatinVF.ttf" ]; then
        ct_sync_font_file "$_src_fonts/CoreType-SFPro-Text.ttf" "$_moddir/system/product/fonts/MiSansLatinVF.ttf"
    fi
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

    # Standard AOSP / HyperOS /system/etc XML targets
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

        if [ -n "$_live_xml" ] && { [ "$_force_snap" = "1" ] || [ ! -r "$_bak_xml" ]; }; then
            if ! grep -q 'CoreType' "$_live_xml" 2>/dev/null; then
                cat "$_live_xml" > "$_bak_xml" 2>/dev/null || true
            fi
        fi

        _src_xml="$_bak_xml"
        [ -r "$_src_xml" ] || _src_xml="$_live_xml"

        if [ -n "$_src_xml" ] && [ -r "$_src_xml" ]; then
            if ct_patch_font_xml "$_src_xml" "$_dst_xml" "$_prof" "$_moddir/system/fonts"; then
                chmod 0644 "$_dst_xml" 2>/dev/null || true
                CT_PATCHED_COUNT=$((CT_PATCHED_COUNT + 1))
            fi
        fi
    done

    # HyperOS 3 /system_ext/etc/hyper_font_fallback.xml & hyper_fonts.xml targets
    for _hxml in hyper_font_fallback.xml hyper_fonts.xml; do
        _hbak="$_stock_dir/$_hxml"
        _hdst="$_moddir/system/system_ext/etc/$_hxml"

        _hsrc="$_root/system_ext/etc/$_hxml"
        [ -r "$_hsrc" ] || _hsrc="$_root/system/system_ext/etc/$_hxml"

        if [ -r "$_hsrc" ] && { [ "$_force_snap" = "1" ] || [ ! -r "$_hbak" ]; }; then
            if ! grep -q 'CoreType' "$_hsrc" 2>/dev/null; then
                cat "$_hsrc" > "$_hbak" 2>/dev/null || true
            fi
        fi

        _huse="$_hbak"
        [ -r "$_huse" ] || _huse="$_hsrc"

        if [ -n "$_huse" ] && [ -r "$_huse" ]; then
            if ct_patch_font_xml "$_huse" "$_hdst" "$_prof" "$_moddir/system/fonts"; then
                chmod 0644 "$_hdst" 2>/dev/null || true
                CT_PATCHED_COUNT=$((CT_PATCHED_COUNT + 1))
            fi
        fi
    done

    [ "$CT_PATCHED_COUNT" -gt 0 ]
}
