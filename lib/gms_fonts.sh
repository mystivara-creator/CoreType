#!/system/bin/sh
# shellcheck disable=SC2034
# CoreType — Universal GMS Downloadable Fonts Engine (Non-Destructive Read-Only Bind)
# Routes Google Play Services FontsProvider caches (Google_Sans*, Product_Sans*, Roboto*, Inter*)
# used by Play Store, Gmail, Google Maps, Google Photos, Gboard, and Material 3 apps to SF Pro
# with true weight/italic matching (Regular 400, Medium 500, Semibold/Bold 600+, Italic).
#
# Zero disk writes to /data; every bind-mount vanishes cleanly on toggle OFF / disable / uninstall.

ct_gms_prepare_source() {
    _src="$1"
    [ -f "$_src" ] || return 1
    chmod 0644 "$_src" 2>/dev/null || true
    if command -v chcon >/dev/null 2>&1; then
        chcon u:object_r:system_file:s0 "$_src" 2>/dev/null || true
    fi
    return 0
}

# Pick the exact SF Pro binary (Variable master or GMS static weight instance) for a GMS filename
ct_gms_select_sfpro_source() {
    _moddir="$1"
    _fname="$2"

    _f_text="$_moddir/fonts/CoreType-SFPro-Text.ttf"
    _f_disp="$_moddir/fonts/CoreType-SFPro-Display.ttf"
    _f_flex="$_moddir/fonts/CoreType-SFPro-Flex.ttf"
    _f_ital="$_moddir/fonts/CoreType-SFPro-Text-Italic.ttf"
    _f_dital="$_moddir/fonts/CoreType-SFPro-Display-Italic.ttf"
    _f_med="$_moddir/fonts/CoreType-SFPro-GMS-Medium.ttf"
    _f_bold="$_moddir/fonts/CoreType-SFPro-GMS-Bold.ttf"

    [ -f "$_f_flex" ] || _f_flex="$_f_text"
    [ -f "$_f_med" ] || _f_med="$_f_text"
    [ -f "$_f_bold" ] || _f_bold="$_f_disp"
    [ -f "$_f_dital" ] || _f_dital="$_f_ital"

    # Match italic files first (GMS naming: *-1_0.ttf or *Italic*)
    case "$_fname" in
        *-1_0.ttf|*-1_0-*.ttf|*[Ii]talic*)
            case "$_fname" in
                *[Dd]isplay*|*-600-*|*-700-*|*-800-*|*-900-*)
                    printf '%s\n' "$_f_dital"
                    ;;
                *)
                    printf '%s\n' "$_f_ital"
                    ;;
            esac
            return 0
            ;;
    esac

    # Match bold / semibold static weights (600..900)
    case "$_fname" in
        *-600-*|*-700-*|*-800-*|*-900-*|*[Bb]old*|*[Ss]emi[Bb]old*)
            printf '%s\n' "$_f_bold"
            return 0
            ;;
    esac

    # Match medium static weight (500)
    case "$_fname" in
        *-500-*|*[Mm]edium*)
            printf '%s\n' "$_f_med"
            return 0
            ;;
    esac

    # Match Material 3 Expressive continuous-opsz Flex variable font (Google_Sans_Flex-400*)
    case "$_fname" in
        *[Ff]lex*)
            printf '%s\n' "$_f_flex"
            return 0
            ;;
    esac

    # Match Display / Light / Thin (100..300)
    case "$_fname" in
        *[Dd]isplay*|*-100-*|*-200-*|*-300-*|*[Ll]ight*|*[Tt]hin*)
            printf '%s\n' "$_f_disp"
            return 0
            ;;
    esac

    # Default / Regular (400) / Variable Font
    printf '%s\n' "$_f_text"
    return 0
}

# Filter strictly to Latin UI fonts (never touch Emoji, Mono, Code, Icons, Symbols, CJK, Arabic)
ct_gms_is_latin_ui_font() {
    _base="$1"
    case "$_base" in
        *[Ee]moji*|*[Mm]ono*|*[Cc]ode*|*[Ii]con*|*[Ss]ymbol*|*[Ss]erif*|*[Cc][Jj][Kk]*|*[Aa]rabic*)
            return 1
            ;;
        Google_Sans*.ttf|GoogleSans*.ttf|Product_Sans*.ttf|ProductSans*.ttf|Roboto*.ttf|Inter*.ttf)
            return 0
            ;;
    esac
    return 1
}

ct_bind_one_gms_font() {
    _src="$1"
    _dst="$2"
    [ -f "$_dst" ] || return 0
    if grep -Fq " $_dst " /proc/mounts 2>/dev/null; then
        CT_GMS_FONTS_BOUND=$((CT_GMS_FONTS_BOUND + 1))
        return 0
    fi
    if mount -o bind "$_src" "$_dst" 2>/dev/null; then
        mount -o remount,ro,bind "$_dst" 2>/dev/null || true
        CT_GMS_FONTS_BOUND=$((CT_GMS_FONTS_BOUND + 1))
    fi
    return 0
}

# Usage: ct_bind_gms_latin_fonts <moddir> [gms_opentype_dir]
# Sets: CT_GMS_FONTS_BOUND
ct_bind_gms_latin_fonts() {
    _moddir="$1"
    _gms_ot_dir="${2:-/data/data/com.google.android.gms/files/fonts/opentype}"
    CT_GMS_FONTS_BOUND=0

    [ -f "$_moddir/fonts/CoreType-SFPro-Text.ttf" ] || return 0

    for _prep in \
        "$_moddir/fonts/CoreType-SFPro-Text.ttf" \
        "$_moddir/fonts/CoreType-SFPro-Text-Italic.ttf" \
        "$_moddir/fonts/CoreType-SFPro-Display.ttf" \
        "$_moddir/fonts/CoreType-SFPro-Display-Italic.ttf" \
        "$_moddir/fonts/CoreType-SFPro-Flex.ttf" \
        "$_moddir/fonts/CoreType-SFPro-GMS-Medium.ttf" \
        "$_moddir/fonts/CoreType-SFPro-GMS-Bold.ttf"; do
        ct_gms_prepare_source "$_prep" || true
    done

    if [ -d "$_gms_ot_dir" ]; then
        for _gttf in "$_gms_ot_dir"/*.ttf; do
            [ -f "$_gttf" ] || continue
            _gbase="${_gttf##*/}"
            ct_gms_is_latin_ui_font "$_gbase" || continue
            _gsrc=$(ct_gms_select_sfpro_source "$_moddir" "$_gbase")
            ct_bind_one_gms_font "$_gsrc" "$_gttf"
        done
    fi

    if [ "$_gms_ot_dir" = "/data/data/com.google.android.gms/files/fonts/opentype" ]; then
        for _sttf in /data/user/[1-9]*/com.google.android.gms/files/fonts/opentype/*.ttf; do
            [ -f "$_sttf" ] || continue
            _sbase="${_sttf##*/}"
            ct_gms_is_latin_ui_font "$_sbase" || continue
            _ssrc=$(ct_gms_select_sfpro_source "$_moddir" "$_sbase")
            ct_bind_one_gms_font "$_ssrc" "$_sttf"
        done
    fi

    return 0
}
