#!/system/bin/sh
# CoreType — Self-Healing Bootloop Guard, OTA Auto-Resync, Profile & iOS Emoji Sync
# Runs in post-fs-data BEFORE Magisk/KernelSU mounts module overlays and BEFORE Zygote starts.

MODDIR="${0%/*}"

# shellcheck disable=SC1091
. "$MODDIR/lib/common.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/profiles.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/font_xml.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/engine.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/emoji.sh"

ct_init_dirs
BOOT_FILE="$CT_DATA_DIR/boot_attempts"

# 1. Self-Healing Bootloop Guard:
#    If 2 consecutive boots fail to reach sys.boot_completed=1, CoreType auto-disables itself
#    so the next boot is guaranteed 100% stock HyperOS/Android.
_attempts=0
if [ -r "$BOOT_FILE" ]; then
    _raw=$(tr -cd '0-9' < "$BOOT_FILE" 2>/dev/null)
    [ -n "$_raw" ] && _attempts="$_raw"
fi

if [ "$_attempts" -ge 2 ]; then
    touch "$MODDIR/disable" 2>/dev/null || true
    printf '0\n' > "$BOOT_FILE" 2>/dev/null || true
    ct_state_set "status" "safe_disabled"
    ct_state_set "bootloop_guard" "triggered"
    ct_log "SAFE_MODE: auto-disabled CoreType after $_attempts incomplete boots"
    exit 0
fi

printf '%s\n' "$((_attempts + 1))" > "$BOOT_FILE" 2>/dev/null || true

# 2. Pre-Zygote master integrity check
if ! ct_verify_all_masters "$MODDIR/fonts"; then
    touch "$MODDIR/disable" 2>/dev/null || true
    ct_state_set "status" "safe_disabled"
    ct_log "SAFE_MODE: corrupt/missing master ${CT_FAILED_MASTER:-unknown}, auto-disabled module"
    exit 0
fi

WANT_PROFILE=$(ct_conf_get "profile" "dynamic_optical")
APPLIED_PROFILE=$(ct_conf_get "applied_profile" "")
if ! ct_profile_valid "$WANT_PROFILE"; then
    WANT_PROFILE="dynamic_optical"
fi

WANT_EMOJI=$(ct_conf_get "emoji_enabled" "1")
[ "$WANT_EMOJI" = "0" ] || WANT_EMOJI="1"
APPLIED_EMOJI=$(ct_conf_get "applied_emoji" "")

# 3. Automatic ROM / HyperOS OTA Detection & Resync
LIVE_FP=$(ct_get_fingerprint)
SAVED_FP=$(ct_conf_get "build_fingerprint" "")
OTA_CHANGED=0
if [ -n "$LIVE_FP" ] && [ -n "$SAVED_FP" ] && [ "$LIVE_FP" != "$SAVED_FP" ]; then
    OTA_CHANGED=1
fi

if [ "$OTA_CHANGED" = "1" ]; then
    ct_log "OTA detected ($SAVED_FP -> $LIVE_FP); resyncing stock slots, emoji & font XMLs"
    ct_sync_stock_slots "$MODDIR" "/system/fonts" "/product/fonts"
    ct_sync_emoji_slots "$MODDIR" "$WANT_EMOJI" "/system/fonts"
    if ct_patch_all_xmls "$MODDIR" "$WANT_PROFILE" 1 ""; then
        ct_conf_set "build_fingerprint" "$LIVE_FP"
        ct_conf_set "applied_profile" "$WANT_PROFILE"
        ct_conf_set "applied_emoji" "$WANT_EMOJI"
        ct_conf_set "ota_status" "resynced"
        ct_log "OTA resync complete (patched=$CT_PATCHED_COUNT emoji=$CT_EMOJI_ACTIVE)"
    else
        touch "$MODDIR/disable" 2>/dev/null || true
        ct_state_set "status" "safe_disabled"
        ct_log "SAFE_MODE: OTA XML resync failed validation, auto-disabled module"
        exit 0
    fi
else
    # Verify mapped stock slots exist before mount; repair from masters if missing
    ct_load_slots
    _slot_missing=0
    for _req in "$CT_SLOT_TEXT" "$CT_SLOT_DISP" "$CT_SLOT_ITAL" "$CT_SLOT_DITAL"; do
        [ -s "$MODDIR/system/fonts/$_req" ] || _slot_missing=1
    done
    if [ "$_slot_missing" = "1" ]; then
        ct_sync_stock_slots "$MODDIR" "/system/fonts" "/product/fonts"
        ct_sync_emoji_slots "$MODDIR" "$WANT_EMOJI" "/system/fonts"
        ct_log "Self-repaired missing stock font slot links from local masters"
    elif [ "$WANT_EMOJI" != "$APPLIED_EMOJI" ]; then
        ct_sync_emoji_slots "$MODDIR" "$WANT_EMOJI" "/system/fonts"
        ct_conf_set "applied_emoji" "$WANT_EMOJI"
        ct_log "Applied iOS Emoji toggle: enabled=$WANT_EMOJI active=$CT_EMOJI_ACTIVE"
    fi

    # 4. Apply pending optical profile switch selected from WebUI
    if [ "$WANT_PROFILE" != "$APPLIED_PROFILE" ]; then
        if ct_patch_all_xmls "$MODDIR" "$WANT_PROFILE" 0 ""; then
            ct_conf_set "applied_profile" "$WANT_PROFILE"
            ct_log "Applied optical profile '$WANT_PROFILE' on boot (patched=$CT_PATCHED_COUNT)"
        fi
    fi
fi

# 5. Non-destructive bind-mount over GMS dynamic emoji cache (runs before FontManagerService)
if [ "$WANT_EMOJI" = "1" ]; then
    ct_bind_gms_emoji_cache "$MODDIR" "/data/fonts/files"
fi
