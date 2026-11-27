#!/system/bin/sh
# CoreType — Zero-Daemon Boot Verification & Single-Pass Telemetry
# Runs once at boot, disarms Bootloop Guard, writes state.prop atomically, and exits (0 KB persistent RAM).

MODDIR="${0%/*}"

# shellcheck disable=SC1091
. "$MODDIR/lib/common.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/profiles.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/font_xml.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/emoji.sh"

# Low-overhead boot completion poll (2s interval, up to 90s for post-flash ART cache)
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

# Verify Apple iOS Emoji availability & active status + catch late GMS emoji cache updates
_emoji_avail="0"
_emoji_active="0"
CT_GMS_EMOJI_BOUND=0
_want_emoji=$(ct_conf_get "applied_emoji" "1")
if ct_emoji_master_valid "$MODDIR/fonts/CoreType-AppleEmoji.ttf"; then
    _emoji_avail="1"
    if [ "$_want_emoji" = "1" ]; then
        ct_bind_gms_emoji_cache "$MODDIR" "/data/fonts/files"
        _ewant=$(wc -c < "$MODDIR/fonts/CoreType-AppleEmoji.ttf" 2>/dev/null || echo 0)
        _elive=$(wc -c < /system/fonts/NotoColorEmoji.ttf 2>/dev/null || echo 1)
        if [ "$_ewant" -gt 5242880 ] && [ "$_ewant" = "$_elive" ]; then
            _emoji_active="1"
        fi
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

_ota_state=$(ct_conf_get "ota_status" "synced")

# Single-pass atomic write (1 rename instead of 15 forks)
ct_state_write_all \
    "status=$_status" \
    "profile=$CT_PROFILE" \
    "profile_label=$CT_PROFILE_LABEL" \
    "wdth_text=$CT_WDTH_TEXT" \
    "wdth_disp=$CT_WDTH_DISP" \
    "font_mounted=$_font_ok" \
    "xml_active=$_xml_active" \
    "slot_text=$CT_SLOT_TEXT" \
    "slot_disp=$CT_SLOT_DISP" \
    "slot_ital=$CT_SLOT_ITAL" \
    "misans_slider=${CT_MISANS_SLIDER_ACTIVE:-0}" \
    "misans_prod_mounted=$_misans_prod_ok" \
    "cjk_fallback=${CT_CJK_FALLBACK:-none}" \
    "emoji_available=$_emoji_avail" \
    "emoji_active=$_emoji_active" \
    "gms_emoji_bound=${CT_GMS_EMOJI_BOUND:-0}" \
    "ota_status=$_ota_state" \
    "optical_engine=dual_master_gpos_trak_umount_safe" \
    "bootloop_guard=$_guard_state"

ct_log "Boot verify: status=$_status profile=$CT_PROFILE xml=$_xml_active fonts=$_font_ok misans=${CT_MISANS_SLIDER_ACTIVE:-0}/prod=$_misans_prod_ok emoji=$_emoji_active/$_emoji_avail/gms=${CT_GMS_EMOJI_BOUND:-0} guard=$_guard_state"
ct_trim_log
