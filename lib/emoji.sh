#!/system/bin/sh
# shellcheck disable=SC2034
# CoreType — Apple iOS Emoji Engine (KernelSU-Umount-Safe + Non-Destructive GMS Cache Bind)
# Works universally across Android 12–16 and HyperOS 1 / 2 / 3 / 4.

ct_emoji_master_valid() {
    _ef="$1"
    [ -f "$_ef" ] || return 1
    # Apple Color Emoji CBDT/CBLC binary is > 5 MB and starts with valid TrueType sfnt (00 01 00 00)
    _sz=$(wc -c < "$_ef" 2>/dev/null || echo 0)
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

# Non-destructive bind-mount over Google Play Services dynamic emoji cache (/data/fonts/files/*/NotoColorEmoji.ttf).
# Leaves /data/fonts intact on disk; vanishes cleanly on disable/uninstall/reboot.
# Usage: ct_bind_gms_emoji_cache <moddir> [data_fonts_root]
ct_bind_gms_emoji_cache() {
    _moddir="$1"
    _df_root="${2:-/data/fonts/files}"
    _emoji_src="$_moddir/fonts/CoreType-AppleEmoji.ttf"
    CT_GMS_EMOJI_BOUND=0

    ct_emoji_master_valid "$_emoji_src" || return 0
    [ -d "$_df_root" ] || return 0

    for _gms_ttf in "$_df_root"/*/NotoColorEmoji.ttf; do
        [ -f "$_gms_ttf" ] || continue
        if ! grep -Fq " $_gms_ttf " /proc/mounts 2>/dev/null; then
            if mount -o bind "$_emoji_src" "$_gms_ttf" 2>/dev/null; then
                CT_GMS_EMOJI_BOUND=$((CT_GMS_EMOJI_BOUND + 1))
            fi
        else
            CT_GMS_EMOJI_BOUND=$((CT_GMS_EMOJI_BOUND + 1))
        fi
    done
    return 0
}
