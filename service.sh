#!/system/bin/sh
# CoreType — Post-Boot Verification & WebUI Telemetry State

MODDIR="${0%/*}"

# shellcheck disable=SC1091
. "$MODDIR/lib/common.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/profiles.sh"

_prof=$(ct_conf_get "applied_profile" "dynamic_optical")
ct_load_profile "$_prof"

_font_ok="0"
[ -f /system/fonts/CoreType-SFPro.ttf ] && [ -f /system/fonts/CoreType-SFPro-Italic.ttf ] && _font_ok="1"

_xml_ok="0"
_xml_active="none"
if [ -r /system/etc/font_fallback.xml ] && grep -q 'CoreType-SFPro\.ttf' /system/etc/font_fallback.xml 2>/dev/null; then
    _xml_ok="1"
    _xml_active="font_fallback.xml"
elif [ -r /system/etc/fonts.xml ] && grep -q 'CoreType-SFPro\.ttf' /system/etc/fonts.xml 2>/dev/null; then
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
ct_log "Boot verify: status=$_status profile=$CT_PROFILE xml=$_xml_active"
