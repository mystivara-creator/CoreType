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

    _dtmp="$_out.tmp.$$"
    if ! {
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
            _live_gl=""
            _live_ge=""
            if [ -r "$TELEM_FILE" ]; then
                _live_gl=$(awk -F= '$1=="gms_latin_mounted"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || true)
                _live_ge=$(awk -F= '$1=="gms_emoji_mounted"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || true)
            fi
            if [ -n "$_live_gl" ] || [ -n "$_live_ge" ]; then
                awk -F= -v gl="${_live_gl}" -v ge="${_live_ge}" '
                    $1=="gms_fonts_bound" && gl!="" { print "gms_fonts_bound=" gl; next }
                    $1=="gms_emoji_bound" && ge!="" { print "gms_emoji_bound=" ge; next }
                    { print }
                ' "$CT_STATE_FILE"
            else
                cat "$CT_STATE_FILE"
            fi
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
        for _xml in /system/etc/font_fallback.xml /system_ext/etc/hyper_font_fallback.xml /system/etc/fonts.xml /system_ext/etc/hyper_fonts.xml; do
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
    } > "$_dtmp" 2>/dev/null || ! mv "$_dtmp" "$_out" 2>/dev/null; then
        rm -f "$_dtmp" 2>/dev/null || true
        printf 'Failed to write diagnostic report to %s\n' "$_out" >&2
        return 1
    fi

    chmod 0644 "$_out" 2>/dev/null || true
    printf 'Diagnostic exported to %s\n' "$_out"
}

if [ "${1:-}" = "--diag" ]; then
    ct_export_diag "${2:-/sdcard/Download/coretype-diag.txt}"
    exit $?
fi

_want_gms_fonts=$(ct_conf_get "gms_fonts_enabled" "1")
[ "$_want_gms_fonts" = "0" ] || _want_gms_fonts="1"
_want_emoji=$(ct_conf_get "emoji_enabled" "1")
[ "$_want_emoji" = "0" ] || _want_emoji="1"

# Fast path: signal native epoll daemon via SIGUSR1 (< 5 ms zero-fork sync & live umount2)
# Strictly verify PID belongs to coretype-watchd so we never signal shell-fallback or a recycled PID.
if [ -r "$PID_FILE" ]; then
    _wpid=$(tr -cd '0-9' < "$PID_FILE" 2>/dev/null)
    if ct_pid_matches "$_wpid" 'coretype-watchd'; then
        _prev_sc=$(awk -F= '$1=="sync_count"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || true)
        _prev_sc="${_prev_sc:-0}"
        kill -USR1 "$_wpid" 2>/dev/null || true
        _tries=0
        while [ "$_tries" -lt 10 ]; do
            _cur_sc=$(awk -F= '$1=="sync_count"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || true)
            _cur_sc="${_cur_sc:-0}"
            if [ "$_cur_sc" != "$_prev_sc" ]; then
                break
            fi
            sleep 0.05 2>/dev/null || sleep 1
            _tries=$((_tries + 1))
        done
        _lat=$(awk -F= '$1=="last_sync_latency_us"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || true)
        _gl=$(awk -F= '$1=="gms_latin_mounted"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || true)
        _ge=$(awk -F= '$1=="gms_emoji_mounted"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || true)
        _wh=$(awk -F= '$1=="watch_health"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || true)
        ct_conf_set "applied_gms_fonts" "$_want_gms_fonts" 2>/dev/null || true
        ct_state_set "gms_fonts_enabled" "$_want_gms_fonts" 2>/dev/null || true
        ct_state_set "gms_fonts_bound" "${_gl:-0}" 2>/dev/null || true
        ct_state_set "gms_emoji_bound" "${_ge:-0}" 2>/dev/null || true
        printf 'CoreType Native Sync (SIGUSR1): %s Latin, %s Emoji mounted in %s us (watch=%s).\n' \
            "${_gl:-0}" "${_ge:-0}" "${_lat:-0}" "${_wh:-healthy}"
        exit 0
    fi
fi

# On-demand native daemon wake-up (handles Lite + GMS OFF at boot -> user toggles GMS ON live)
_watchd_bin="$MODDIR/bin/coretype-watchd"
if { [ "$_want_gms_fonts" = "1" ] || { [ "$_want_emoji" = "1" ] && ct_emoji_master_valid "$MODDIR/fonts/CoreType-AppleEmoji.ttf"; }; } \
    && [ -x "$_watchd_bin" ] && "$_watchd_bin" --version >/dev/null 2>&1; then
    _fbe_arg=""
    if [ "$(getprop sys.boot_completed 2>/dev/null || true)" = "1" ] || [ -d /sdcard/Android ]; then
        _fbe_arg="--no-fbe-wait"
    fi
    if command -v setsid >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        setsid "$_watchd_bin" --moddir "$MODDIR" --datadir "$CT_DATA_DIR" --rundir "$CT_RUN_DIR" $_fbe_arg </dev/null >/dev/null 2>&1 &
    else
        # shellcheck disable=SC2086
        "$_watchd_bin" --moddir "$MODDIR" --datadir "$CT_DATA_DIR" --rundir "$CT_RUN_DIR" $_fbe_arg </dev/null >/dev/null 2>&1 &
    fi
    _tries=0
    while [ "$_tries" -lt 20 ]; do
        [ -s "$TELEM_FILE" ] && break
        sleep 0.05 2>/dev/null || sleep 1
        _tries=$((_tries + 1))
    done
    if [ -s "$TELEM_FILE" ]; then
        _lat=$(awk -F= '$1=="last_sync_latency_us"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || true)
        _gl=$(awk -F= '$1=="gms_latin_mounted"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || true)
        _ge=$(awk -F= '$1=="gms_emoji_mounted"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || true)
        _wh=$(awk -F= '$1=="watch_health"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || true)
        ct_conf_set "applied_gms_fonts" "$_want_gms_fonts" 2>/dev/null || true
        ct_state_set "gms_fonts_enabled" "$_want_gms_fonts" 2>/dev/null || true
        ct_state_set "gms_watcher" "native-epoll" 2>/dev/null || true
        ct_state_set "gms_fonts_bound" "${_gl:-0}" 2>/dev/null || true
        ct_state_set "gms_emoji_bound" "${_ge:-0}" 2>/dev/null || true
        printf 'CoreType Native Daemon Started: %s Latin, %s Emoji mounted in %s us (watch=%s).\n' \
            "${_gl:-0}" "${_ge:-0}" "${_lat:-0}" "${_wh:-healthy}"
        exit 0
    fi
fi

# Direct fallback path (when native ABI binary is unavailable or both toggles are OFF)

CT_GMS_FONTS_BOUND=0
CT_GMS_EMOJI_BOUND=0

if [ "$_want_gms_fonts" = "1" ]; then
    ct_bind_gms_latin_fonts "$MODDIR"
else
    for _um in /data/data/com.google.android.gms/files/fonts/opentype/*.ttf; do
        [ -f "$_um" ] || continue
        ct_gms_is_latin_ui_font "${_um##*/}" || continue
        if ct_is_mounted "$_um"; then
            umount -l "$_um" 2>/dev/null || true
        fi
    done
fi

if [ "$_want_emoji" = "1" ] && ct_emoji_master_valid "$MODDIR/fonts/CoreType-AppleEmoji.ttf"; then
    ct_bind_gms_emoji_cache "$MODDIR" "/data/fonts/files"
else
    for _ue in /data/fonts/files/*/NotoColorEmoji.ttf /data/data/com.google.android.gms/files/fonts/opentype/*[Ee]moji*.ttf; do
        [ -f "$_ue" ] || continue
        if ct_is_mounted "$_ue"; then
            umount -l "$_ue" 2>/dev/null || true
        fi
    done
fi

ct_conf_set "applied_gms_fonts" "$_want_gms_fonts" 2>/dev/null || true
ct_state_set "gms_fonts_enabled" "$_want_gms_fonts" 2>/dev/null || true
ct_state_set "gms_fonts_bound" "${CT_GMS_FONTS_BOUND:-0}"
ct_state_set "gms_emoji_bound" "${CT_GMS_EMOJI_BOUND:-0}"
ct_log "Manual GMS sync (shell): fonts=${CT_GMS_FONTS_BOUND:-0} emoji=${CT_GMS_EMOJI_BOUND:-0}"
ct_trim_log

printf 'CoreType GMS Sync Complete: %s Latin font(s), %s Emoji cache(s) bound.\n' \
    "${CT_GMS_FONTS_BOUND:-0}" "${CT_GMS_EMOJI_BOUND:-0}"
