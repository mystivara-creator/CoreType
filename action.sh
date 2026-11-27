#!/system/bin/sh
# CoreType — Instant On-Demand GMS Fonts & iOS Emoji Sync (No Reboot Required)
# Triggers native C++20 `coretype-watchd` via SIGUSR1 (< 5 ms), or falls back to direct POSIX sync.

MODDIR="${0%/*}"
CT_RUN_DIR="/dev/.coretype"
PID_FILE="$CT_RUN_DIR/watchd.pid"
TELEM_FILE="$CT_RUN_DIR/telemetry.prop"

# shellcheck disable=SC1091
. "$MODDIR/lib/common.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/emoji.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/gms_fonts.sh"

# Fast path: signal native epoll daemon via SIGUSR1 (< 5 ms zero-fork sync)
if [ -r "$PID_FILE" ]; then
    _wpid=$(tr -cd '0-9' < "$PID_FILE" 2>/dev/null)
    if [ -n "$_wpid" ] && kill -0 "$_wpid" 2>/dev/null; then
        _prev_sc=$(awk -F= '$1=="sync_count"{print $2;exit}' "$TELEM_FILE" 2>/dev/null || echo 0)
        kill -USR1 "$_wpid" 2>/dev/null || true
        # Brief settle so telemetry.prop reflects the completed SIGUSR1 sync
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
        printf 'CoreType Native Sync (SIGUSR1): %s Latin, %s Emoji mounted in %s us.\n' \
            "${_gl:-0}" "${_ge:-0}" "${_lat:-0}"
        exit 0
    fi
fi

# Direct fallback path (when daemon is idle or shell-fallback is used)
_want_gms_fonts=$(ct_conf_get "applied_gms_fonts" "1")
_want_emoji=$(ct_conf_get "applied_emoji" "1")

CT_GMS_FONTS_BOUND=0
CT_GMS_EMOJI_BOUND=0

if [ "$_want_gms_fonts" = "1" ]; then
    ct_bind_gms_latin_fonts "$MODDIR"
fi

if [ "$_want_emoji" = "1" ] && ct_emoji_master_valid "$MODDIR/fonts/CoreType-AppleEmoji.ttf"; then
    ct_bind_gms_emoji_cache "$MODDIR" "/data/fonts/files"
fi

ct_state_set "gms_fonts_bound" "${CT_GMS_FONTS_BOUND:-0}"
ct_state_set "gms_emoji_bound" "${CT_GMS_EMOJI_BOUND:-0}"
ct_log "Manual GMS sync (shell): fonts=${CT_GMS_FONTS_BOUND:-0} emoji=${CT_GMS_EMOJI_BOUND:-0}"
ct_trim_log

printf 'CoreType GMS Sync Complete: %s Latin font(s), %s Emoji cache(s) bound.\n' \
    "${CT_GMS_FONTS_BOUND:-0}" "${CT_GMS_EMOJI_BOUND:-0}"
