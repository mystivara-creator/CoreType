#!/system/bin/sh
# CoreType — Universal HyperOS 1–4 & Android 12–16 Installer (KernelSU-Umount-Safe, OTA-Aware)

# shellcheck disable=SC2034
SKIPUNZIP=0

# shellcheck disable=SC1091
. "$MODPATH/lib/common.sh"
# shellcheck disable=SC1091
. "$MODPATH/lib/profiles.sh"
# shellcheck disable=SC1091
. "$MODPATH/lib/font_xml.sh"
# shellcheck disable=SC1091
. "$MODPATH/lib/engine.sh"
# shellcheck disable=SC1091
. "$MODPATH/lib/emoji.sh"

ct_ui_print() {
    if command -v ui_print >/dev/null 2>&1; then
        ui_print "$1"
    else
        printf '%s\n' "$1"
    fi
}

ct_ui_print " "
ct_ui_print "============================================="
ct_ui_print "  CoreType — CoreText-Parity Engine v1.2.0"
ct_ui_print "  by Mystivara | HyperOS 1–4 (Android 12–17)"
ct_ui_print "============================================="

# 0. Exclusive HyperOS ARM64 (aarch64) Platform Gate (HyperOS 1/2/3/4 & Android 12–17)
_ct_arch=$(uname -m 2>/dev/null || true)
_ct_abi=$(getprop ro.product.cpu.abi 2>/dev/null || true)
case "${_ct_arch}:${_ct_abi}" in
    *aarch64*|*arm64*) ;;
    *)
        abort "! Unsupported architecture (${_ct_arch:-unknown} / ${_ct_abi:-unknown}). CoreType requires ARM64 (aarch64)."
        ;;
esac

_ct_hos_name=$(getprop ro.mi.os.version.name 2>/dev/null || true)
_ct_hos_code=$(getprop ro.mi.os.version.code 2>/dev/null || true)
_ct_inc_ver=$(getprop ro.build.version.incremental 2>/dev/null || true)
_ct_miui_ver=$(getprop ro.miui.ui.version.name 2>/dev/null || true)
_ct_android_rel=$(getprop ro.build.version.release 2>/dev/null || echo "unknown")
_ct_is_hyperos="0"
if [ -n "$_ct_hos_name" ] || [ -n "$_ct_hos_code" ] || [ -n "$_ct_miui_ver" ]; then
    _ct_is_hyperos="1"
else
    case "$_ct_inc_ver" in
        OS[1-9]*|*.OS[1-9]*) _ct_is_hyperos="1" ;;
    esac
fi
if [ "$_ct_is_hyperos" != "1" ] \
    && [ ! -r /system_ext/etc/hyper_font_fallback.xml ] \
    && [ ! -e /product/fonts/MiSansVF.ttf ]; then
    abort "! Unsupported ROM detected. CoreType v1.2.0 is exclusively engineered for Xiaomi HyperOS (HyperOS 1–4 / Android 12–17)."
fi
ct_ui_print "- Platform: ARM64 | HyperOS ${_ct_hos_name:-${_ct_miui_ver:-detected}} (Android ${_ct_android_rel})"

# 1. Pre-flight binary integrity & HyperOS Lockscreen/AOD clock parity verification
if ! ct_verify_all_masters "$MODPATH/fonts"; then
    abort "! Integrity check failed: ${CT_FAILED_MASTER:-master} is missing or corrupt."
fi
ct_verify_hyperos_clock_parity "$MODPATH" || abort "! Lockscreen/AOD clock parity check failed."
ct_ui_print "- Verified optical SF Pro masters & HyperOS Lockscreen/AOD clock parity (tnum + calt 09:41)"

ct_init_dirs
# Reset Bootloop Guard counter on fresh install
printf '0\n' > "$CT_DATA_DIR/boot_attempts"

ACTIVE_PROFILE=$(ct_conf_get "profile" "dynamic_optical")
if ! ct_profile_valid "$ACTIVE_PROFILE"; then
    ACTIVE_PROFILE="dynamic_optical"
fi
ct_load_profile "$ACTIVE_PROFILE"
ct_conf_set "profile" "$CT_PROFILE"
ct_conf_set "applied_profile" "$CT_PROFILE"

WEIGHT_BIAS=$(ct_conf_get "weight_bias" "0")
CONTRAST_MODE=$(ct_conf_get "contrast_mode" "balanced")
ct_load_weight_curve "$WEIGHT_BIAS" "$CONTRAST_MODE"
ct_conf_set "weight_bias" "$CT_WEIGHT_BIAS"
ct_conf_set "applied_weight_bias" "$CT_WEIGHT_BIAS"
ct_conf_set "contrast_mode" "$CT_CONTRAST_MODE"
ct_conf_set "applied_contrast_mode" "$CT_CONTRAST_MODE"

GMS_FONTS_ENABLED=$(ct_conf_get "gms_fonts_enabled" "1")
[ "$GMS_FONTS_ENABLED" = "0" ] || GMS_FONTS_ENABLED="1"
ct_conf_set "gms_fonts_enabled" "$GMS_FONTS_ENABLED"
ct_conf_set "applied_gms_fonts" "$GMS_FONTS_ENABLED"

EMOJI_ENABLED=$(ct_conf_get "emoji_enabled" "1")
[ "$EMOJI_ENABLED" = "0" ] || EMOJI_ENABLED="1"
ct_conf_set "emoji_enabled" "$EMOJI_ENABLED"
ct_conf_set "applied_emoji" "$EMOJI_ENABLED"

# Record current ROM fingerprint for automatic HyperOS/Android OTA re-sync
BUILD_FP=$(ct_get_fingerprint)
[ -n "$BUILD_FP" ] && ct_conf_set "build_fingerprint" "$BUILD_FP"

# 2. Allocate KernelSU-Umount-Safe Stock Slots + Universal HyperOS MiSans Slider
ct_sync_stock_slots "$MODPATH" "/system/fonts" "/product/fonts"
ct_sync_emoji_slots "$MODPATH" "$EMOJI_ENABLED" "/system/fonts"

ct_ui_print "- Profile: $CT_PROFILE_LABEL ($CT_PROFILE)"
ct_ui_print "- Dynamic Weight Curve: $CT_CONTRAST_LABEL | Bias ${CT_WEIGHT_BIAS}"
ct_ui_print "- KernelSU-Umount-Safe Stock Slots (shared inode):"
ct_ui_print "  Text    (opsz 17)    -> $CT_SLOT_TEXT"
ct_ui_print "  Display (opsz 28)    -> $CT_SLOT_DISP"
ct_ui_print "  Flex    (opsz 12-36) -> ${CT_SLOT_FLEX:-$CT_SLOT_TEXT}"
ct_ui_print "  Italic  (opsz 17)    -> $CT_SLOT_ITAL"
ct_ui_print "  DispIt  (opsz 28)    -> $CT_SLOT_DITAL"

if [ "$CT_MISANS_SLIDER_ACTIVE" = "1" ]; then
    ct_ui_print "- HyperOS MiSans + Weight Slider: ENABLED (CJK safe via $CT_CJK_FALLBACK)"
else
    ct_ui_print "- HyperOS MiSans Slider: N/A or preserved (AOSP / no separate CJK fallback)"
fi

if [ "$GMS_FONTS_ENABLED" = "1" ]; then
    ct_ui_print "- Universal GMS Fonts (Play Store/Gmail/Maps/Photos/Gboard): ENABLED"
else
    ct_ui_print "- Universal GMS Fonts: OFF (toggle anytime in WebUI)"
fi

if [ "$CT_EMOJI_AVAILABLE" = "1" ]; then
    if [ "$CT_EMOJI_ACTIVE" = "1" ]; then
        ct_ui_print "- Edition: FULL | Apple iOS Emoji: ENABLED (GMS-aware)"
    else
        ct_ui_print "- Edition: FULL | Apple iOS Emoji: OFF (toggle anytime in WebUI)"
    fi
else
    ct_ui_print "- Edition: LITE (Dual-Optical SF Pro only)"
fi

# 3. Snapshot stock XMLs and emit strictly validated Dual-Optical XMLs (Dynamic Weight Curve)
if ! ct_patch_all_xmls "$MODPATH" "$CT_PROFILE" 0 ""; then
    abort "! Failed to patch any system font XML safely. Aborting with zero changes."
fi
ct_conf_set "rom_curve" "${CT_ROM_CURVE:-hyperos_mipro}"
ct_ui_print "- Patched $CT_PATCHED_COUNT system font XML(s) (curve=${CT_ROM_CURVE:-hyperos_mipro})"

# Notice if user has an active Xiaomi Theme Store font overriding system fonts
if [ -s /data/system/theme/fonts/Roboto-Regular.ttf ]; then
    ct_ui_print " "
    ct_ui_print "! Notice: Custom Xiaomi Theme font detected in /data/system/theme/fonts/."
    ct_ui_print "  Select 'Default' or 'MiSans' in Settings -> Display -> Font after rebooting."
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
if [ -f "$MODPATH/bin/coretype-watchd" ]; then
    set_perm "$MODPATH/bin/coretype-watchd" 0 0 0755
    ct_ui_print "- Native C++20 Event Daemon (coretype-watchd): INSTALLED"
fi

ct_state_write_all \
    "status=pending_reboot" \
    "profile=$CT_PROFILE" \
    "profile_label=$CT_PROFILE_LABEL" \
    "wdth_text=$CT_WDTH_TEXT" \
    "wdth_disp=$CT_WDTH_DISP" \
    "rom_curve=${CT_ROM_CURVE:-hyperos_mipro}" \
    "weight_bias=$CT_WEIGHT_BIAS" \
    "contrast_mode=$CT_CONTRAST_MODE" \
    "contrast_label=$CT_CONTRAST_LABEL" \
    "gms_fonts_enabled=$GMS_FONTS_ENABLED" \
    "gms_fonts_bound=0" \
    "patched_xmls=$CT_PATCHED_COUNT" \
    "slot_text=$CT_SLOT_TEXT" \
    "slot_disp=$CT_SLOT_DISP" \
    "slot_flex=${CT_SLOT_FLEX:-$CT_SLOT_TEXT}" \
    "slot_ital=$CT_SLOT_ITAL" \
    "misans_slider=$CT_MISANS_SLIDER_ACTIVE" \
    "cjk_fallback=${CT_CJK_FALLBACK:-none}" \
    "emoji_available=$CT_EMOJI_AVAILABLE" \
    "emoji_active=$CT_EMOJI_ACTIVE" \
    "ota_status=synced" \
    "optical_engine=coretext_parity_continuous_opsz_epoll" \
    "bootloop_guard=armed"

ct_log "Installed CoreType v1.2.0 (profile=$CT_PROFILE curve=${CT_ROM_CURVE:-hyperos_mipro}/bias=$CT_WEIGHT_BIAS/$CT_CONTRAST_MODE xmls=$CT_PATCHED_COUNT misans=$CT_MISANS_SLIDER_ACTIVE gms_fonts=$GMS_FONTS_ENABLED emoji=$CT_EMOJI_ACTIVE/$CT_EMOJI_AVAILABLE)"

ct_ui_print "- Self-Healing Bootloop Guard: ARMED"
ct_ui_print "- OTA Auto-Resync: ENABLED"
ct_ui_print "- Installation complete! Reboot to enjoy Native iOS SF Pro."
ct_ui_print " "
