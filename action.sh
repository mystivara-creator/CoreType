#!/system/bin/sh
# CoreType — Instant On-Demand GMS Fonts & iOS Emoji Sync (No Reboot Required)
# Triggered via KernelSU / Magisk / APatch Action button or CoreType WebUI "Sync GMS Now".

MODDIR="${0%/*}"

# shellcheck disable=SC1091
. "$MODDIR/lib/common.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/emoji.sh"
# shellcheck disable=SC1091
. "$MODDIR/lib/gms_fonts.sh"

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
ct_log "Manual GMS sync: fonts=${CT_GMS_FONTS_BOUND:-0} emoji=${CT_GMS_EMOJI_BOUND:-0}"
ct_trim_log

printf 'CoreType GMS Sync Complete: %s Latin font(s), %s Emoji cache(s) bound.\n' \
    "${CT_GMS_FONTS_BOUND:-0}" "${CT_GMS_EMOJI_BOUND:-0}"
