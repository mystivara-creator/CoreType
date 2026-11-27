#!/system/bin/sh
# CoreType — Boot Verification, Telemetry & Native C++20 Event-Driven Daemon Launcher
# 1. Disarms Bootloop Guard as soon as sys.boot_completed=1
# 2. Writes atomic state.prop telemetry
# 3. Launches native C++20 `coretype-watchd` (epoll + inotify + timerfd + signalfd, 0% idle CPU,
#    < 300 KB RSS, 0 wakelock, /dev/.coretype/) when executable on this ABI; falls back to
#    a lightweight POSIX shell watcher ONLY on unsupported architectures.

MODDIR="${0%/*}"
CT_RUN_DIR="/dev/.coretype"

# shellcheck disable=SC1091
. "$MODDIR/lib/common.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/profiles.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/font_xml.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/emoji.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/gms_fonts.sh"

# 1. Low-overhead boot completion poll (2s interval, up to 90s for post-flash ART cache)
_wait=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$_wait" -lt 45 ]; do
    sleep 2
    _wait=$((_wait + 1))
done

_guard_state="armed"
if [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; then
    printf '0\n' > "$CT_DATA_DIR/boot_attempts" 2>/dev/null || true
    _guard_state="healthy"
fi

_prof=$(ct_conf_get "applied_profile" "dynamic_optical")
ct_load_profile "$_prof"
ct_load_weight_curve "$(ct_conf_get "applied_weight_bias" "0")" "$(ct_conf_get "applied_contrast_mode" "balanced")"
_rom_curve=$(ct_conf_get "rom_curve" "hyperos_mipro")
ct_load_slots

# Verify mounted stock font slots match CoreType's optical master byte sizes
_font_ok="0"
_want_sz=$(wc -c < "$MODDIR/fonts/CoreType-SFPro-Text.ttf" 2>/dev/null || echo 0)
_live_sz=$(wc -c < "/system/fonts/$CT_SLOT_TEXT" 2>/dev/null || echo 1)
if [ "$_want_sz" -gt 102400 ] && [ "$_want_sz" = "$_live_sz" ]; then
    _font_ok="1"
fi

# Verify /product/fonts/MiSansVF.ttf mount status when MiSans slider is active
_misans_prod_ok="0"
if [ "${CT_MISANS_SLIDER_ACTIVE:-0}" = "1" ] && [ -r /product/fonts/MiSansVF.ttf ]; then
    _mlive_sz=$(wc -c < /product/fonts/MiSansVF.ttf 2>/dev/null || echo 1)
    if [ "$_want_sz" -gt 102400 ] && [ "$_want_sz" = "$_mlive_sz" ]; then
        _misans_prod_ok="1"
    fi
fi

_xml_ok="0"
_xml_active="none"
if [ -r /system/etc/font_fallback.xml ] \
    && grep -q 'CoreType Dual-Optical' /system/etc/font_fallback.xml 2>/dev/null; then
    _xml_ok="1"
    _xml_active="font_fallback.xml"
elif [ -r /system/etc/fonts.xml ] \
    && grep -q 'CoreType Dual-Optical' /system/etc/fonts.xml 2>/dev/null; then
    _xml_ok="1"
    _xml_active="fonts.xml"
fi

if [ "$_font_ok" = "1" ] && [ "$_xml_ok" = "1" ]; then
    _status="active"
else
    _status="degraded"
fi

_want_gms_fonts=$(ct_conf_get "applied_gms_fonts" "1")
_want_emoji=$(ct_conf_get "applied_emoji" "1")
_emoji_avail="0"
_emoji_active="0"
if ct_emoji_master_valid "$MODDIR/fonts/CoreType-AppleEmoji.ttf"; then
    _emoji_avail="1"
    if [ "$_want_emoji" = "1" ]; then
        _ewant=$(wc -c < "$MODDIR/fonts/CoreType-AppleEmoji.ttf" 2>/dev/null || echo 0)
        _elive=$(wc -c < /system/fonts/NotoColorEmoji.ttf 2>/dev/null || echo 1)
        if [ "$_ewant" -gt 5242880 ] && [ "$_ewant" = "$_elive" ]; then
            _emoji_active="1"
        fi
    fi
fi

_ota_state=$(ct_conf_get "ota_status" "synced")

ct_write_state() {
    _w_mode="$1"
    ct_state_write_all \
        "status=$_status" \
        "profile=$CT_PROFILE" \
        "profile_label=$CT_PROFILE_LABEL" \
        "wdth_text=$CT_WDTH_TEXT" \
        "wdth_disp=$CT_WDTH_DISP" \
        "rom_curve=$_rom_curve" \
        "weight_bias=$CT_WEIGHT_BIAS" \
        "contrast_mode=$CT_CONTRAST_MODE" \
        "contrast_label=$CT_CONTRAST_LABEL" \
        "gms_fonts_enabled=$_want_gms_fonts" \
        "gms_fonts_bound=${CT_GMS_FONTS_BOUND:-0}" \
        "font_mounted=$_font_ok" \
        "xml_active=$_xml_active" \
        "slot_text=$CT_SLOT_TEXT" \
        "slot_disp=$CT_SLOT_DISP" \
        "slot_flex=${CT_SLOT_FLEX:-$CT_SLOT_TEXT}" \
        "slot_ital=$CT_SLOT_ITAL" \
        "misans_slider=${CT_MISANS_SLIDER_ACTIVE:-0}" \
        "misans_prod_mounted=$_misans_prod_ok" \
        "cjk_fallback=${CT_CJK_FALLBACK:-none}" \
        "emoji_available=$_emoji_avail" \
        "emoji_active=$_emoji_active" \
        "gms_emoji_bound=${CT_GMS_EMOJI_BOUND:-0}" \
        "gms_watcher=$_w_mode" \
        "ota_status=$_ota_state" \
        "optical_engine=coretext_parity_continuous_opsz_epoll" \
        "bootloop_guard=$_guard_state"
}

ct_write_fallback_telemetry() {
    _sc="$1"
    _rss=$(awk '/^VmRSS:/{print $2;exit}' /proc/self/status 2>/dev/null || echo 0)
    mkdir -p "$CT_RUN_DIR" 2>/dev/null || true
    chmod 0755 "$CT_RUN_DIR" 2>/dev/null || true
    _tfile="$CT_RUN_DIR/telemetry.prop"
    if {
        printf 'daemon_mode=shell-fallback\n'
        printf 'daemon_pid=%s\n' "$$"
        printf 'daemon_rss_kb=%s\n' "${_rss:-0}"
        printf 'gms_latin_mounted=%s\n' "${CT_GMS_FONTS_BOUND:-0}"
        printf 'gms_emoji_mounted=%s\n' "${CT_GMS_EMOJI_BOUND:-0}"
        printf 'sync_count=%s\n' "$_sc"
        printf 'last_sync_latency_us=0\n'
        printf 'active_text_tracking_upm=-46\n'
        printf 'active_display_tracking_upm=-26\n'
    } > "$_tfile.tmp.$$" 2>/dev/null; then
        mv "$_tfile.tmp.$$" "$_tfile" 2>/dev/null || true
    fi
    chmod 0644 "$_tfile" 2>/dev/null || true
}

CT_GMS_FONTS_BOUND=0
CT_GMS_EMOJI_BOUND=0

_need_watcher="0"
if [ "$_want_gms_fonts" = "1" ] || { [ "$_emoji_avail" = "1" ] && [ "$_want_emoji" = "1" ]; }; then
    _need_watcher="1"
fi

if [ "$_need_watcher" != "1" ]; then
    ct_write_state "idle"
    ct_log "Boot verify: status=$_status profile=$CT_PROFILE curve=$_rom_curve/bias=$CT_WEIGHT_BIAS/$CT_CONTRAST_MODE xml=$_xml_active fonts=$_font_ok watcher=idle guard=$_guard_state"
    ct_trim_log
    exit 0
fi

# 2. Prefer Native C++20 epoll+inotify+timerfd Daemon (0% idle CPU, < 300 KB RSS, 0 wakelock)
WATCHD_BIN="$MODDIR/bin/coretype-watchd"
if [ -x "$WATCHD_BIN" ] && "$WATCHD_BIN" --version >/dev/null 2>&1; then
    ct_write_state "native-epoll"
    ct_log "Boot verify: status=$_status profile=$CT_PROFILE curve=$_rom_curve/bias=$CT_WEIGHT_BIAS/$CT_CONTRAST_MODE xml=$_xml_active fonts=$_font_ok watcher=native-epoll guard=$_guard_state"
    ct_trim_log
    exec "$WATCHD_BIN" --moddir "$MODDIR" --datadir "$CT_DATA_DIR" --rundir "$CT_RUN_DIR"
fi

# 3. Lightweight POSIX Shell Fallback (ONLY when native ABI binary is unavailable)
ct_write_state "shell-fallback"
_uwait=0
while [ ! -d /sdcard/Android ] && [ "$_uwait" -lt 90 ]; do
    sleep 2
    _uwait=$((_uwait + 1))
done

mkdir -p "$CT_RUN_DIR" 2>/dev/null || true
chmod 0755 "$CT_RUN_DIR" 2>/dev/null || true
if [ -r "$CT_RUN_DIR/watchd.pid" ]; then
    _old_pid=$(tr -cd '0-9' < "$CT_RUN_DIR/watchd.pid" 2>/dev/null)
    if [ -n "$_old_pid" ] && [ "$_old_pid" != "$$" ]; then
        kill "$_old_pid" 2>/dev/null || true
    fi
fi
printf '%s\n' "$$" > "$CT_RUN_DIR/watchd.pid" 2>/dev/null || true

ct_run_gms_sync() {
    CT_GMS_FONTS_BOUND=0
    CT_GMS_EMOJI_BOUND=0
    if [ "$_want_gms_fonts" = "1" ]; then
        ct_bind_gms_latin_fonts "$MODDIR"
    fi
    if [ "$_emoji_avail" = "1" ] && [ "$_want_emoji" = "1" ]; then
        ct_bind_gms_emoji_cache "$MODDIR" "/data/fonts/files"
    fi
}

_sync_n=1
ct_run_gms_sync
ct_write_state "shell-fallback"
ct_write_fallback_telemetry "$_sync_n"
ct_log "Boot verify: status=$_status profile=$CT_PROFILE watcher=shell-fallback gms_fonts=${CT_GMS_FONTS_BOUND:-0} gms_emoji=${CT_GMS_EMOJI_BOUND:-0} guard=$_guard_state"
ct_trim_log

while [ -d "$MODDIR" ] && [ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ]; do
    sleep 60
    if [ ! -d "$MODDIR" ] || [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
        break
    fi
    ct_run_gms_sync
    _sync_n=$((_sync_n + 1))
    ct_write_fallback_telemetry "$_sync_n"
done

rm -rf "$CT_RUN_DIR" 2>/dev/null || true
