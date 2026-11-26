#!/system/bin/sh
# CoreType — Boot Completion Confirmation & WebUI Telemetry

MODDIR="${0%/*}"

# shellcheck disable=SC1091
. "$MODDIR/lib/common.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/profiles.sh"

# Wait for Android boot completion before disarming Bootloop Guard
_wait=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$_wait" -lt 60 ]; do
    sleep 1
    _wait=$((_wait + 1))
done

if [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; then
    printf '0\n' > "$CT_DATA_DIR/boot_attempts" 2>/dev/null || true
    if command -v cmd >/dev/null 2>&1; then
        cmd overlay enable --user 0 org.mystivara.coretype.overlay.settings >/dev/null 2>&1 || true
        cmd overlay set-priority org.mystivara.coretype.overlay.settings highest >/dev/null 2>&1 || true
    fi
fi

_prof=$(ct_conf_get "applied_profile" "dynamic_optical")
ct_load_profile "$_prof"

_font_ok="1"
for _req in \
    CoreType-SFPro-Text.ttf \
    CoreType-SFPro-Text-Italic.ttf \
    CoreType-SFPro-Display.ttf \
    CoreType-SFPro-Display-Italic.ttf; do
    if [ ! -s "/system/fonts/$_req" ]; then
        _font_ok="0"
        break
    fi
done

_xml_ok="0"
_xml_active="none"
if [ -r /system/etc/font_fallback.xml ] \
    && grep -q 'CoreType-SFPro-Text\.ttf' /system/etc/font_fallback.xml 2>/dev/null \
    && grep -q 'CoreType-SFPro-Display\.ttf' /system/etc/font_fallback.xml 2>/dev/null; then
    _xml_ok="1"
    _xml_active="font_fallback.xml"
elif [ -r /system/etc/fonts.xml ] \
    && grep -q 'CoreType-SFPro-Text\.ttf' /system/etc/fonts.xml 2>/dev/null \
    && grep -q 'CoreType-SFPro-Display\.ttf' /system/etc/fonts.xml 2>/dev/null; then
    _xml_ok="1"
    _xml_active="fonts.xml"
fi

if [ "$_font_ok" = "1" ] && [ "$_xml_ok" = "1" ]; then
    _status="active"
else
    _status="degraded"
fi

ct_state_set "status" "$_status"
ct_state_set "profile" "$CT_PROFILE"
ct_state_set "profile_label" "$CT_PROFILE_LABEL"
ct_state_set "wdth_text" "$CT_WDTH_TEXT"
ct_state_set "wdth_disp" "$CT_WDTH_DISP"
ct_state_set "font_mounted" "$_font_ok"
ct_state_set "xml_active" "$_xml_active"
ct_state_set "optical_engine" "dual_master_gpos_trak"
ct_state_set "bootloop_guard" "healthy"
ct_log "Boot verify: status=$_status profile=$CT_PROFILE xml=$_xml_active fonts=$_font_ok"
