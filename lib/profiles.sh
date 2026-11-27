#!/system/bin/sh
# shellcheck disable=SC2034
# CoreType — Dual-Optical Typography Profile Definitions
#
# Dual Optical Master Routing (with Apple `trak` baked into GPOS `kern`):
#   - Weights 350..500 (Body, Chat, UI Labels):  CoreType-SFPro-Text.ttf    (opsz=17, -46 UPM trak)
#   - Weights 600..950 (Headers, Titles, Bold):  CoreType-SFPro-Display.ttf (opsz=28, -26 UPM trak)
#   - Weights 100..300 (Lockscreen Clock, Hero): CoreType-SFPro-Display.ttf (opsz=28, -26 UPM trak)

ct_profile_valid() {
    case "$1" in
        dynamic_optical|native_pro|compact_crisp) return 0 ;;
        *) return 1 ;;
    esac
}

# Sets CT_PROFILE, CT_PROFILE_LABEL, CT_WDTH_TEXT, CT_WDTH_MID, CT_WDTH_DISP, CT_WDTH_COND
ct_load_profile() {
    _prof="${1:-dynamic_optical}"
    if ! ct_profile_valid "$_prof"; then
        _prof="dynamic_optical"
    fi
    CT_PROFILE="$_prof"
    case "$_prof" in
        dynamic_optical)
            CT_PROFILE_LABEL="iOS Optical Dynamic"
            CT_WDTH_TEXT="96.5"
            CT_WDTH_MID="96.5"
            CT_WDTH_DISP="97.0"
            CT_WDTH_COND="82.0"
            ;;
        native_pro)
            CT_PROFILE_LABEL="iOS Native Pro"
            CT_WDTH_TEXT="100.0"
            CT_WDTH_MID="100.0"
            CT_WDTH_DISP="100.0"
            CT_WDTH_COND="86.0"
            ;;
        compact_crisp)
            CT_PROFILE_LABEL="iOS Compact Crisp"
            CT_WDTH_TEXT="91.5"
            CT_WDTH_MID="91.5"
            CT_WDTH_DISP="92.0"
            CT_WDTH_COND="77.0"
            ;;
    esac
}

# Clamp user weight bias strictly to [-60, +80] (integer, default 0)
ct_weight_bias_normalize() {
    _raw="${1:-0}"
    case "$_raw" in
        ''|*[!0-9-]*)
            printf '0\n'
            return 0
            ;;
    esac
    # Reject stray minus signs like "-" or "10-5"
    case "$_raw" in
        -|-*[!0-9]*|[0-9]*-*)
            printf '0\n'
            return 0
            ;;
    esac
    if [ "$_raw" -lt -60 ]; then
        printf '%s\n' "-60"
    elif [ "$_raw" -gt 80 ]; then
        printf '%s\n' "80"
    else
        printf '%s\n' "$_raw"
    fi
}

ct_contrast_valid() {
    case "$1" in
        soft|balanced|apple_native) return 0 ;;
        *) return 1 ;;
    esac
}

# Sets CT_WEIGHT_BIAS (-60..80), CT_CONTRAST_MODE (soft|balanced|apple_native), CT_CONTRAST_LABEL
ct_load_weight_curve() {
    CT_WEIGHT_BIAS=$(ct_weight_bias_normalize "${1:-0}")
    _cm="${2:-balanced}"
    if ! ct_contrast_valid "$_cm"; then
        _cm="balanced"
    fi
    CT_CONTRAST_MODE="$_cm"
    case "$_cm" in
        soft)         CT_CONTRAST_LABEL="Soft Harmony" ;;
        balanced)     CT_CONTRAST_LABEL="HyperOS Balanced" ;;
        apple_native) CT_CONTRAST_LABEL="Apple Native" ;;
    esac
}
