#!/system/bin/sh
# CoreType — Early Boot Profile Sync (runs before Zygote mounts fonts)

MODDIR="${0%/*}"

# shellcheck disable=SC1091
. "$MODDIR/lib/common.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/profiles.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/font_xml.sh"

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
            if ct_patch_font_xml "$_bak_xml" "$_dst_xml" "$WANT_PROFILE"; then
                chmod 0644 "$_dst_xml" 2>/dev/null || true
                _ok=$((_ok + 1))
            fi
        fi
    done
    if [ "$_ok" -gt 0 ]; then
        ct_conf_set "applied_profile" "$WANT_PROFILE"
        ct_log "Applied optical profile '$WANT_PROFILE' on boot (patched=$_ok)"
    fi
fi
