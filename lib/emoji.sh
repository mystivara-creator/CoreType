#!/system/bin/sh
# shellcheck disable=SC2034
# CoreType — Apple iOS Emoji Engine (KernelSU-Umount-Safe + Non-Destructive GMS Cache Bind)
# Works universally across Android 12–17 and HyperOS 1 / 2 / 3 / 4.

ct_emoji_master_valid() {
    _ef="$1"
    [ -f "$_ef" ] || return 1
    # Apple Color Emoji CBDT/CBLC binary is > 5 MB and starts with valid TrueType sfnt (00 01 00 00)
    _sz=$(ct_file_size "$_ef")
    [ "$_sz" -gt 5242880 ] || return 1
    if command -v od >/dev/null 2>&1; then
        _magic=$(od -An -tx1 -N4 "$_ef" 2>/dev/null | tr -d ' \n\r')
        [ "$_magic" = "00010000" ] || return 1
    fi
    return 0
}

# Sync or remove Apple iOS Emoji stock slots in module /system/fonts (shared-inode hardlinks).
# Usage: ct_sync_emoji_slots <moddir> <enabled:0|1> [sys_fonts_dir]
# Sets: CT_EMOJI_AVAILABLE (0|1), CT_EMOJI_ACTIVE (0|1)
ct_sync_emoji_slots() {
    _moddir="$1"
    _enabled="${2:-1}"
    _sys_fdir="${3:-/system/fonts}"
    _emoji_src="$_moddir/fonts/CoreType-AppleEmoji.ttf"

    CT_EMOJI_AVAILABLE="0"
    CT_EMOJI_ACTIVE="0"

    # Always clean previous emoji slot files first (clean toggle OFF)
    rm -f "$_moddir/system/fonts/NotoColorEmoji.ttf" \
          "$_moddir/system/fonts/NotoColorEmojiFlags.ttf" 2>/dev/null || true

    if ! ct_emoji_master_valid "$_emoji_src"; then
        return 0
    fi
    CT_EMOJI_AVAILABLE="1"

    if [ "$_enabled" != "1" ]; then
        return 0
    fi

    mkdir -p "$_moddir/system/fonts"
    for _eslot in NotoColorEmoji.ttf NotoColorEmojiFlags.ttf; do
        if [ -e "$_sys_fdir/$_eslot" ]; then
            ln -f "$_emoji_src" "$_moddir/system/fonts/$_eslot" 2>/dev/null \
                || cp -f "$_emoji_src" "$_moddir/system/fonts/$_eslot"
            chmod 0644 "$_moddir/system/fonts/$_eslot" 2>/dev/null || true
            CT_EMOJI_ACTIVE="1"
        fi
    done

    return 0
}

ct_bind_one_emoji_target() {
    _src="$1"
    _dst="$2"
    [ -f "$_dst" ] || return 0
    if ct_is_mounted "$_dst"; then
        CT_GMS_EMOJI_BOUND=$((CT_GMS_EMOJI_BOUND + 1))
        return 0
    fi
    if mount -o bind "$_src" "$_dst" 2>/dev/null; then
        mount -o remount,ro,bind "$_dst" 2>/dev/null || true
        CT_GMS_EMOJI_BOUND=$((CT_GMS_EMOJI_BOUND + 1))
    fi
    return 0
}

# Non-destructive, SELinux-safe bind-mount over Android & GMS dynamic emoji caches.
# Covers:
#   1. /data/fonts/files/*/NotoColorEmoji.ttf (Android FontManagerService dynamic font cache)
#   2. /data/data/com.google.android.gms/files/fonts/opentype/*Emoji*.ttf (GMS FontsProvider /
#      Jetpack EmojiCompat caches such as Noto_COLR_Emoji_Compat & Noto_COLR_Emoji_No_Flags
#      used by Gboard, Notes, Chrome, WebView, and Google apps)
#   3. Existing /data/data/com.facebook.*/app_ras_blobs/*Emoji*.ttf blobs (when present)
# Leaves all /data files intact on disk; vanishes cleanly on toggle OFF / disable / uninstall.
# Usage: ct_bind_gms_emoji_cache <moddir> [data_fonts_root] [gms_opentype_dir]
ct_bind_gms_emoji_cache() {
    _moddir="$1"
    _df_root="${2:-/data/fonts/files}"
    _gms_ot_dir="${3:-/data/data/com.google.android.gms/files/fonts/opentype}"
    _emoji_src="$_moddir/fonts/CoreType-AppleEmoji.ttf"
    CT_GMS_EMOJI_BOUND=0

    ct_emoji_master_valid "$_emoji_src" || return 0

    # Ensure source binary carries SELinux u:object_r:system_file:s0 + 0644 so every
    # app sandbox (GMS, Gboard, Notes, WebView, WhatsApp, Chrome, isolated_app) can mmap it.
    chmod 0644 "$_emoji_src" 2>/dev/null || true
    if command -v chcon >/dev/null 2>&1; then
        chcon u:object_r:system_file:s0 "$_emoji_src" 2>/dev/null || true
    fi

    # Prefer live mounted /system/fonts/NotoColorEmoji.ttf when already mounted & byte-identical
    _bind_src="$_emoji_src"
    if [ -r /system/fonts/NotoColorEmoji.ttf ]; then
        _msz=$(ct_file_size "$_emoji_src")
        _lsz=$(ct_file_size /system/fonts/NotoColorEmoji.ttf)
        if [ "$_msz" -gt 0 ] && [ "$_msz" = "$_lsz" ]; then
            _bind_src="/system/fonts/NotoColorEmoji.ttf"
        fi
    fi

    # 1. System FontManagerService dynamic emoji cache
    if [ -d "$_df_root" ]; then
        for _gms_ttf in "$_df_root"/*/NotoColorEmoji.ttf; do
            ct_bind_one_emoji_target "$_bind_src" "$_gms_ttf"
        done
    fi

    # 2. GMS FontsProvider / Jetpack EmojiCompat OpenType cache (primary user)
    if [ -d "$_gms_ot_dir" ]; then
        for _ot_ttf in "$_gms_ot_dir"/*[Ee]moji*.ttf; do
            ct_bind_one_emoji_target "$_bind_src" "$_ot_ttf"
        done
    fi

    # 3. Secondary Android users' GMS cache & existing Meta/Facebook app_ras_blobs (live runtime only)
    if [ "$_gms_ot_dir" = "/data/data/com.google.android.gms/files/fonts/opentype" ]; then
        for _sec_ttf in /data/user/[1-9]*/com.google.android.gms/files/fonts/opentype/*[Ee]moji*.ttf; do
            ct_bind_one_emoji_target "$_bind_src" "$_sec_ttf"
        done
        for _fb_ttf in /data/data/com.facebook.*/app_ras_blobs/*[Ee]moji*.ttf; do
            ct_bind_one_emoji_target "$_bind_src" "$_fb_ttf"
        done
    fi

    return 0
}
