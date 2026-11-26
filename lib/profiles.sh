#!/system/bin/sh
# shellcheck disable=SC2034
# CoreType — Optical Typography Profile Definitions
#
# Progressive Optical Size (opsz) Curve:
#   - Weights 350..400 (Body, Chat, Notifications): opsz=17.0 (True SF Pro Text)
#   - Weight  500      (UI Labels, Buttons, Tabs):  opsz=20.0 (Text->Display bridge)
#   - Weight  600      (iOS Semibold Headers):      opsz=26.0 (SF Pro Display)
#   - Weights 700..950 (Page Headers, Bold Titles): opsz=28.0 (SF Pro Display)
#   - Weights 100..300 (Lockscreen Clock, Hero):    opsz=28.0 (SF Pro Display)

ct_profile_valid() {
    case "$1" in
        dynamic_optical|native_pro|compact_crisp) return 0 ;;
        *) return 1 ;;
    esac
}

# Sets CT_WDTH_TEXT, CT_WDTH_MID, CT_WDTH_DISP, CT_WDTH_COND, CT_PROFILE_LABEL
ct_load_profile() {
    _prof="${1:-dynamic_optical}"
    if ! ct_profile_valid "$_prof"; then
        _prof="dynamic_optical"
    fi
    CT_PROFILE="$_prof"
    case "$_prof" in
        dynamic_optical)
            CT_PROFILE_LABEL="iOS Optical Dynamic"
            CT_WDTH_TEXT="91.0"
            CT_WDTH_MID="90.0"
            CT_WDTH_DISP="89.0"
            CT_WDTH_COND="78.0"
            ;;
        native_pro)
            CT_PROFILE_LABEL="iOS Native Pro"
            CT_WDTH_TEXT="98.0"
            CT_WDTH_MID="97.0"
            CT_WDTH_DISP="96.0"
            CT_WDTH_COND="82.0"
            ;;
        compact_crisp)
            CT_PROFILE_LABEL="iOS Compact Crisp"
            CT_WDTH_TEXT="86.0"
            CT_WDTH_MID="85.5"
            CT_WDTH_DISP="84.5"
            CT_WDTH_COND="74.0"
            ;;
    esac
}
