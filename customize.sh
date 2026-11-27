#!/system/bin/sh
# CoreType — KernelSU-Umount-Safe, OTA-Aware Zero-Bootloop Installer

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

ct_ui_print() {
    if command -v ui_print >/dev/null 2>&1; then
        ui_print "$1"
    else
        printf '%s\n' "$1"
    fi
}

ct_ui_print " "
ct_ui_print "============================================="
ct_ui_print "  CoreType — Dual-Optical SF Pro v1.0.0"
ct_ui_print "  by Mystivara | Zero LSPosed"
ct_ui_print "============================================="

# 1. Pre-flight binary integrity verification of all 4 optical masters
if ! ct_verify_all_masters "$MODPATH/fonts"; then
    abort "! Integrity check failed: ${CT_FAILED_MASTER:-master} is missing or corrupt."
fi
ct_ui_print "- Verified all 4 Dual-Optical SF Pro variable masters"

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

# Record current ROM fingerprint for automatic HyperOS/Android OTA re-sync
BUILD_FP=$(ct_get_fingerprint)
[ -n "$BUILD_FP" ] && ct_conf_set "build_fingerprint" "$BUILD_FP"

# 2. Allocate KernelSU-Umount-Safe Stock Slots (zero non-stock filenames in XML)
ct_sync_stock_slots "$MODPATH" "/system/fonts" "/product/fonts"

ct_ui_print "- Profile: $CT_PROFILE_LABEL ($CT_PROFILE)"
ct_ui_print "- KernelSU-Umount-Safe Stock Slots (shared inode):"
ct_ui_print "  Text    (opsz 17) -> $CT_SLOT_TEXT"
ct_ui_print "  Display (opsz 28) -> $CT_SLOT_DISP"
ct_ui_print "  Italic  (opsz 17) -> $CT_SLOT_ITAL"
ct_ui_print "  DispIt  (opsz 28) -> $CT_SLOT_DITAL"

# 3. Snapshot stock XMLs and emit strictly validated Dual-Optical XMLs
if ! ct_patch_all_xmls "$MODPATH" "$CT_PROFILE" 0 ""; then
    abort "! Failed to patch any system font XML safely. Aborting with zero changes."
fi
ct_ui_print "- Patched $CT_PATCHED_COUNT system font XML(s) (100% ROM fallbacks preserved)"

# Notice if user has an active Xiaomi Theme Store font overriding system fonts
if [ -s /data/system/theme/fonts/Roboto-Regular.ttf ]; then
    ct_ui_print " "
    ct_ui_print "! Notice: Custom Xiaomi Theme font detected in /data/system/theme/fonts/."
    ct_ui_print "  Select 'Default' in Settings -> Display -> Font after rebooting."
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ct_state_write_all \
    "status=pending_reboot" \
    "profile=$CT_PROFILE" \
    "profile_label=$CT_PROFILE_LABEL" \
    "wdth_text=$CT_WDTH_TEXT" \
    "wdth_disp=$CT_WDTH_DISP" \
    "patched_xmls=$CT_PATCHED_COUNT" \
    "slot_text=$CT_SLOT_TEXT" \
    "slot_disp=$CT_SLOT_DISP" \
    "slot_ital=$CT_SLOT_ITAL" \
    "ota_status=synced" \
    "optical_engine=dual_master_gpos_trak_umount_safe" \
    "bootloop_guard=armed"

ct_log "Installed CoreType v1.0.0 (profile=$CT_PROFILE xmls=$CT_PATCHED_COUNT slots=$CT_SLOT_TEXT/$CT_SLOT_DISP/$CT_SLOT_ITAL)"

ct_ui_print "- Self-Healing Bootloop Guard: ARMED"
ct_ui_print "- OTA Auto-Resync: ENABLED"
ct_ui_print "- Installation complete! Reboot to enjoy Native iOS SF Pro."
ct_ui_print " "
