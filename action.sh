#!/system/bin/sh
# CoreType — Instant On-Demand Sync (SIGUSR1) & One-Tap Diagnostic Bundle (--diag)
# Usage:
#   sh action.sh                      -> triggers SIGUSR1 on native coretype-watchd (< 5 ms)
#   sh action.sh --diag [output_file] -> exports read-only diagnostic report (default /sdcard/Download/coretype-diag.txt)

MODDIR="${0%/*}"
CT_RUN_DIR="${CT_RUN_DIR:-/dev/.coretype}"
PID_FILE="$CT_RUN_DIR/watchd.pid"
TELEM_FILE="$CT_RUN_DIR/telemetry.prop"

# shellcheck disable=SC1091
. "$MODDIR/lib/common.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/emoji.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/gms_fonts.sh"

ct_export_diag() {
    _out="${1:-/sdcard/Download/coretype-diag.txt}"
    mkdir -p "$(dirname "$_out")" 2>/dev/null || true

    _ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    _mod_ver=$(awk -F= '$1=="version"{print $2;exit}' "$MODDIR/module.prop" 2>/dev/null || echo "unknown")
    _arch=$(uname -m 2>/dev/null || echo "unknown")
    _abi=""
    _model=""
    _android=""
    _sdk=""
    _hos=""
    _inc=""
    _fp=""
    if command -v getprop >/dev/null 2>&1; then
        _abi=$(getprop ro.product.cpu.abi 2>/dev/null || true)
        _model=$(getprop ro.product.model 2>/dev/null || true)
        _android=$(getprop ro.build.version.release 2>/dev/null || true)
        _sdk=$(getprop ro.build.version.sdk 2>/dev/null || true)
        _hos=$(getprop ro.mi.os.version.name 2>/dev/null || true)
        _inc=$(getprop ro.build.version.incremental 2>/dev/null || true)
        _fp=$(getprop ro.build.fingerprint 2>/dev/null || true)
    fi

    {
        printf '=============================================\n'
        printf '  CoreType Diagnostic Report (Read-Only)\n'
        printf '=============================================\n'
        printf 'timestamp=%s\n' "$_ts"
        printf 'module_version=%s\n' "$_mod_ver"
        printf 'arch=%s (%s)\n' "$_arch" "${_abi:-unknown}"
        printf 'device=%s\n' "${_model:-unknown}"
        printf 'android=%s (API %s)\n' "${_android:-unknown}" "${_sdk:-unknown}"
        printf 'hyperos=%s (%s)\n' "${_hos:-unknown}" "${_inc:-unknown}"
        printf 'fingerprint=%s\n\n' "${_fp:-unknown}"

        printf '=== LIVE TELEMETRY (%s) ===\n' "$TELEM_FILE"
        if [ -r "$TELEM_FILE" ]; then
            cat "$TELEM_FILE"
        else
            printf '(not running or telemetry unavailable)\n'
        fi

        printf '\n=== ENGINE STATE (%s) ===\n' "$CT_STATE_FILE"
        if [ -r "$CT_STATE_FILE" ]; then
            cat "$CT_STATE_FILE"
        else
            printf '(state.prop unavailable)\n'
        fi

        printf '\n=== ACTIVE GMS/FONT MOUNTS & ANTI-DUPLICATION CHECK ===\n'
        if [ -r /proc/mounts ]; then
            _mnt_lines=$(awk '$2 ~ /com\.google\.android\.gms\/files\/fonts|\/data\/fonts\/files\/|\/system\/fonts\/|\/product\/fonts\// { print $2 }' /proc/mounts 2>/dev/null | sort)
            _total_m=0
            _uniq_m=0
            if [ -n "$_mnt_lines" ]; then
                _total_m=$(printf '%s\n' "$_mnt_lines" | wc -l | tr -d ' ')
                _uniq_m=$(printf '%s\n' "$_mnt_lines" | sort -u | wc -l | tr -d ' ')
                printf '%s\n' "$_mnt_lines"
            else
                printf '(no font/GMS bind mounts detected in current namespace)\n'
            fi
            printf 'total_mounts=%s\nunique_mounts=%s\nduplicate_mounts=%s\n' \
                "$_total_m" "$_uniq_m" "$((_total_m - _uniq_m))"
        else
            printf '(/proc/mounts unreadable)\n'
        fi

        printf '\n=== ACTIVE FONT XML VERIFICATION ===\n'
        for _xml in /system/etc/font_fallback.xml /system_ext/etc/hyper_font_fallback.xml /system/etc/fonts.xml; do
            if [ -r "$_xml" ]; then
                _has_ct="0"
                _has_opsz="0"
                _has_bad="0"
                grep -q 'CoreType Dual-Optical' "$_xml" 2>/dev/null && _has_ct="1"
                grep -q 'tag="opsz"' "$_xml" 2>/dev/null && _has_opsz="1"
                grep -q 'CoreType-SFPro' "$_xml" 2>/dev/null && _has_bad="1"
                printf '%s: patched=%s continuous_opsz=%s non_stock_leak=%s\n' \
                    "$_xml" "$_has_ct" "$_has_opsz" "$_has_bad"
            fi
        done
    } > "$_out.tmp.$$" && mv "$_out.tmp.$$" "$_out"

    chmod 0644 "$_out" 2>/dev/null || true
    printf 'Diagnostic exported to %s\n' "$_out"
}

if [ "${1:-}" = "--diag" ]; then
    ct_export_diag "${2:-/sdcard/Download/coretype-diag.txt}"
    exit 0
fi

# Fast path: signal native epoll daemon via SIGUSR1 (< 5 ms zero-fork sync & live umount2)
if [ -r "$PID_FILE" ]; then
    _wpid=$(tr -cd '0-9' < "$PID_FILE" 2>/dev/null)
    if [ -n "$_wpid" ] && kill -0 "$_wpid" 2>/dev/null; then
        _prev_sc=$(awk -F= '$1=="sync_count"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || echo 0)
        kill -USR1 "$_wpid" 2>/dev/null || true
        _tries=0
        while [ "$_tries" -lt 10 ]; do
            _cur_sc=$(awk -F= '$1=="sync_count"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || echo 0)
            if [ "$_cur_sc" != "$_prev_sc" ]; then
                break
            fi
            sleep 0.05 2>/dev/null || sleep 1
            _tries=$((_tries + 1))
        done
        _lat=$(awk -F= '$1=="last_sync_latency_us"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || echo 0)
        _gl=$(awk -F= '$1=="gms_latin_mounted"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || echo 0)
        _ge=$(awk -F= '$1=="gms_emoji_mounted"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || echo 0)
        _wh=$(awk -F= '$1=="watch_health"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || echo "healthy")
        printf 'CoreType Native Sync (SIGUSR1): %s Latin, %s Emoji mounted in %s us (watch=%s).\n' \
            "${_gl:-0}" "${_ge:-0}" "${_lat:-0}" "${_wh:-healthy}"
        exit 0
    fi
fi

# Direct fallback path (when daemon is idle or shell-fallback is active)
_want_gms_fonts=$(ct_conf_get "gms_fonts_enabled" "1")
_want_emoji=$(ct_conf_get "emoji_enabled" "1")

CT_GMS_FONTS_BOUND=0
CT_GMS_EMOJI_BOUND=0

if [ "$_want_gms_fonts" = "1" ]; then
    ct_bind_gms_latin_fonts "$MODDIR"
else
    for _um in /data/data/com.google.android.gms/files/fonts/opentype/*.ttf; do
        [ -f "$_um" ] || continue
        ct_gms_is_latin_ui_font "${_um##*/}" || continue
        if grep -Fq " $_um " /proc/mounts 2>/dev/null; then
            umount -l "$_um" 2>/dev/null || true
        fi
    done
fi

if [ "$_want_emoji" = "1" ] && ct_emoji_master_valid "$MODDIR/fonts/CoreType-AppleEmoji.ttf"; then
    ct_bind_gms_emoji_cache "$MODDIR" "/data/fonts/files"
else
    for _ue in /data/fonts/files/*/NotoColorEmoji.ttf /data/data/com.google.android.gms/files/fonts/opentype/*[Ee]moji*.ttf; do
        [ -f "$_ue" ] || continue
        if grep -Fq " $_ue " /proc/mounts 2>/dev/null; then
            umount -l "$_ue" 2>/dev/null || true
        fi
    done
fi

ct_state_set "gms_fonts_bound" "${CT_GMS_FONTS_BOUND:-0}"
ct_state_set "gms_emoji_bound" "${CT_GMS_EMOJI_BOUND:-0}"
ct_log "Manual GMS sync (shell): fonts=${CT_GMS_FONTS_BOUND:-0} emoji=${CT_GMS_EMOJI_BOUND:-0}"
ct_trim_log

printf 'CoreType GMS Sync Complete: %s Latin font(s), %s Emoji cache(s) bound.\n' \
    "${CT_GMS_FONTS_BOUND:-0}" "${CT_GMS_EMOJI_BOUND:-0}"
