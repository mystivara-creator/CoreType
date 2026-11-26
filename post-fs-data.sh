#!/system/bin/sh
# CoreType — Self-Healing Bootloop Guard & Early Boot Profile Sync
# Runs before Zygote mounts fonts.

MODDIR="${0%/*}"

# shellcheck disable=SC1091
. "$MODDIR/lib/common.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/profiles.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/font_xml.sh"

ct_init_dirs
BOOT_FILE="$CT_DATA_DIR/boot_attempts"

# 1. Self-Healing Bootloop Guard:
#    If the device fails to reach sys.boot_completed=1 twice in a row,
#    CoreType auto-disables itself so the next boot is 100% stock HyperOS/Android.
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

# 2. Pre-Zygote font binary integrity check
for _req in \
    CoreType-SFPro-Text.ttf \
    CoreType-SFPro-Text-Italic.ttf \
    CoreType-SFPro-Display.ttf \
    CoreType-SFPro-Display-Italic.ttf; do
    if [ ! -s "$MODDIR/system/fonts/$_req" ]; then
        touch "$MODDIR/disable" 2>/dev/null || true
        ct_state_set "status" "safe_disabled"
        ct_log "SAFE_MODE: missing $_req before boot, auto-disabled module"
        exit 0
    fi
done

# 3. Apply pending optical profile switch selected from WebUI
WANT_PROFILE=$(ct_conf_get "profile" "dynamic_optical")
APPLIED_PROFILE=$(ct_conf_get "applied_profile" "")

if ! ct_profile_valid "$WANT_PROFILE"; then
    WANT_PROFILE="dynamic_optical"
fi

if [ "$WANT_PROFILE" != "$APPLIED_PROFILE" ]; then
    STOCK_DIR="$CT_DATA_DIR/stock_xml"
    _ok=0
    for _xml_name in font_fallback.xml fonts.xml; do
        _bak_xml="$STOCK_DIR/$_xml_name"
        _dst_xml="$MODDIR/system/etc/$_xml_name"
        if [ -r "$_bak_xml" ]; then
            if ct_patch_font_xml "$_bak_xml" "$_dst_xml" "$WANT_PROFILE" "$MODDIR/system/fonts"; then
                chmod 0644 "$_dst_xml" 2>/dev/null || true
                _ok=$((_ok + 1))
            fi
        fi
    done
    for _hxml in hyper_font_fallback.xml hyper_fonts.xml; do
        _hbak="$STOCK_DIR/$_hxml"
        _hdst="$MODDIR/system/system_ext/etc/$_hxml"
        if [ -r "$_hbak" ]; then
            if ct_patch_font_xml "$_hbak" "$_hdst" "$WANT_PROFILE" "$MODDIR/system/fonts"; then
                chmod 0644 "$_hdst" 2>/dev/null || true
                _ok=$((_ok + 1))
            fi
        fi
    done
    if [ "$_ok" -gt 0 ]; then
        ct_conf_set "applied_profile" "$WANT_PROFILE"
        ct_log "Applied optical profile '$WANT_PROFILE' on boot (patched=$_ok)"
    fi
fi
