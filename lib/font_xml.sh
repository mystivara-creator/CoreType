#!/system/bin/sh
# CoreType — KernelSU-Umount-Safe Dual-Optical XML Patcher & Structural Validator
#
# CRITICAL ANDROID 14-17 / KERNELSU-UMOUNT ARCHITECTURE:
#   `FontManagerService` (system_server, NOT umounted) broadcasts the font paths
#   from `font_fallback.xml` to ALL apps — including apps where KernelSU `umount`
#   hides module-added files. If `font_fallback.xml` references a brand-new filename
#   that doesn't exist in stock `/system/fonts/`, umounted apps (e.g. Gboard, banking)
#   hit ENOENT -> nullptr -> SIGSEGV in `minikin::Font::prepareFont`.
#
#   CoreType solves this 100% by mapping its Dual-Optical SF Pro variable masters
#   STRICTLY onto existing stock filenames discovered on the ROM:
#     - CT_SLOT_TEXT  (Text opsz=17 Upright)  -> Roboto-Regular.ttf
#     - CT_SLOT_DISP  (Display opsz=28 Upright)-> RobotoStatic-Regular.ttf / Roboto-Bold.ttf / Roboto-Regular.ttf
#     - CT_SLOT_FLEX  (Flex opsz=17..28)      -> RobotoFlex-Regular.ttf / $CT_SLOT_TEXT
#     - CT_SLOT_ITAL  (Text opsz=17 Italic)   -> Roboto-Italic.ttf / RobotoStatic-Italic.ttf / ... / $CT_SLOT_TEXT
#     - CT_SLOT_DITAL (Display opsz=28 Italic)-> Roboto-BoldItalic.ttf / $CT_SLOT_ITAL
#
#   Result: Mounted processes get 100% true Dual-Optical SF Pro (Display + Text + Italic),
#   while KernelSU-umounted apps fall back seamlessly to stock files with ZERO crashes.

# Discover existing stock font slots inside <sys_fonts_dir> (default: /system/fonts)
# Sets: CT_SLOT_TEXT, CT_SLOT_DISP, CT_SLOT_ITAL, CT_SLOT_DITAL, CT_SLOT_FLEX
ct_resolve_stock_slots() {
    _sdir="${1:-/system/fonts}"

    CT_SLOT_TEXT="Roboto-Regular.ttf"

    if [ -e "$_sdir/RobotoStatic-Regular.ttf" ]; then
        CT_SLOT_DISP="RobotoStatic-Regular.ttf"
    elif [ -e "$_sdir/Roboto-Bold.ttf" ]; then
        CT_SLOT_DISP="Roboto-Bold.ttf"
    else
        CT_SLOT_DISP="$CT_SLOT_TEXT"
    fi

    # Dedicated continuous-opsz slot (opsz 17..28) for Jetpack Compose & Material 3 roboto-flex
    if [ -e "$_sdir/RobotoFlex-Regular.ttf" ]; then
        CT_SLOT_FLEX="RobotoFlex-Regular.ttf"
    else
        CT_SLOT_FLEX="$CT_SLOT_TEXT"
    fi

    if [ -e "$_sdir/Roboto-Italic.ttf" ]; then
        CT_SLOT_ITAL="Roboto-Italic.ttf"
    elif [ -e "$_sdir/RobotoStatic-Italic.ttf" ]; then
        CT_SLOT_ITAL="RobotoStatic-Italic.ttf"
    elif [ -e "$_sdir/RobotoCondensed-Italic.ttf" ]; then
        CT_SLOT_ITAL="RobotoCondensed-Italic.ttf"
    elif [ -e "$_sdir/Roboto-MediumItalic.ttf" ]; then
        CT_SLOT_ITAL="Roboto-MediumItalic.ttf"
    elif [ -e "$_sdir/Roboto-BoldItalic.ttf" ]; then
        CT_SLOT_ITAL="Roboto-BoldItalic.ttf"
    elif [ -e "$_sdir/Roboto-LightItalic.ttf" ]; then
        CT_SLOT_ITAL="Roboto-LightItalic.ttf"
    else
        CT_SLOT_ITAL="$CT_SLOT_TEXT"
    fi

    if [ -e "$_sdir/Roboto-BoldItalic.ttf" ] && [ "$CT_SLOT_ITAL" != "Roboto-BoldItalic.ttf" ]; then
        CT_SLOT_DITAL="Roboto-BoldItalic.ttf"
    else
        CT_SLOT_DITAL="$CT_SLOT_ITAL"
    fi
}

ct_save_slots() {
    ct_init_dirs
    _sf="$CT_DATA_DIR/slots.conf"
    {
        printf 'CT_SLOT_TEXT=%s\n' "$CT_SLOT_TEXT"
        printf 'CT_SLOT_DISP=%s\n' "$CT_SLOT_DISP"
        printf 'CT_SLOT_ITAL=%s\n' "$CT_SLOT_ITAL"
        printf 'CT_SLOT_DITAL=%s\n' "$CT_SLOT_DITAL"
        printf 'CT_SLOT_FLEX=%s\n' "${CT_SLOT_FLEX:-$CT_SLOT_TEXT}"
        printf 'CT_CJK_FALLBACK=%s\n' "${CT_CJK_FALLBACK:-}"
        printf 'CT_MISANS_SLIDER_ACTIVE=%s\n' "${CT_MISANS_SLIDER_ACTIVE:-0}"
    } > "$_sf.tmp.$$" && mv "$_sf.tmp.$$" "$_sf"
}

ct_load_slots() {
    _sf="$CT_DATA_DIR/slots.conf"
    if [ -r "$_sf" ]; then
        CT_SLOT_TEXT=$(awk -F= '$1=="CT_SLOT_TEXT"{print $2;exit}' "$_sf")
        CT_SLOT_DISP=$(awk -F= '$1=="CT_SLOT_DISP"{print $2;exit}' "$_sf")
        CT_SLOT_ITAL=$(awk -F= '$1=="CT_SLOT_ITAL"{print $2;exit}' "$_sf")
        CT_SLOT_DITAL=$(awk -F= '$1=="CT_SLOT_DITAL"{print $2;exit}' "$_sf")
        CT_SLOT_FLEX=$(awk -F= '$1=="CT_SLOT_FLEX"{print $2;exit}' "$_sf")
        CT_CJK_FALLBACK=$(awk -F= '$1=="CT_CJK_FALLBACK"{print $2;exit}' "$_sf")
        CT_MISANS_SLIDER_ACTIVE=$(awk -F= '$1=="CT_MISANS_SLIDER_ACTIVE"{print $2;exit}' "$_sf")
    fi
    [ -n "${CT_SLOT_TEXT:-}" ] || ct_resolve_stock_slots "/system/fonts"
    [ -n "${CT_SLOT_FLEX:-}" ] || CT_SLOT_FLEX="$CT_SLOT_TEXT"
    [ -n "${CT_MISANS_SLIDER_ACTIVE:-}" ] || CT_MISANS_SLIDER_ACTIVE="0"
}

# Usage: ct_emit_font_entry <weight> <normal|italic> <text|display> <wdth> [wght_axis]
ct_emit_font_entry() {
    _w="$1"
    _style="$2"
    _optical="$3"
    _wdth="$4"
    _wght="${5:-$_w}"

    # When a ROM (e.g. HyperOS 3/4) ships no separate stock Roboto*Italic.ttf slot,
    # omit style="italic" pointing to upright Roboto-Regular.ttf so Android Minikin
    # synthesizes clean oblique italics instead of rendering <em>/_italic_ upright.
    if [ "$_style" = "italic" ] && [ "$CT_SLOT_ITAL" = "$CT_SLOT_TEXT" ]; then
        return 0
    fi

    if [ "$_optical" = "display" ]; then
        if [ "$_style" = "italic" ]; then
            _file="$CT_SLOT_DITAL"
        else
            _file="$CT_SLOT_DISP"
        fi
    else
        if [ "$_style" = "italic" ]; then
            _file="$CT_SLOT_ITAL"
        else
            _file="$CT_SLOT_TEXT"
        fi
    fi

    printf '        <font weight="%s" style="%s">%s\n' "$_w" "$_style" "$_file"
    printf '            <axis tag="wght" stylevalue="%s" />\n' "$_wght"
    if [ "$_style" = "normal" ]; then
        printf '            <axis tag="wdth" stylevalue="%s" />\n' "$_wdth"
    fi
    printf '        </font>\n'
}

# Usage: ct_emit_flex_font_entry <weight> <normal|italic> <opsz> <wdth> <wght_axis>
ct_emit_flex_font_entry() {
    _w="$1"
    _style="$2"
    _opsz="$3"
    _wdth="$4"
    _wght="$5"

    if [ "$_style" = "italic" ]; then
        if [ "$CT_SLOT_ITAL" = "$CT_SLOT_TEXT" ]; then
            return 0
        fi
        if [ "$_opsz" -ge 24 ]; then
            _file="$CT_SLOT_DITAL"
        else
            _file="$CT_SLOT_ITAL"
        fi
        printf '        <font weight="%s" style="italic">%s\n' "$_w" "$_file"
        printf '            <axis tag="wght" stylevalue="%s" />\n' "$_wght"
        printf '        </font>\n'
    else
        printf '        <font weight="%s" style="normal">%s\n' "$_w" "${CT_SLOT_FLEX:-$CT_SLOT_TEXT}"
        printf '            <axis tag="wght" stylevalue="%s" />\n' "$_wght"
        printf '            <axis tag="wdth" stylevalue="%s" />\n' "$_wdth"
        if [ "${CT_SLOT_FLEX:-$CT_SLOT_TEXT}" != "$CT_SLOT_TEXT" ]; then
            printf '            <axis tag="opsz" stylevalue="%s" />\n' "$_opsz"
        fi
        printf '        </font>\n'
    fi
}

# Detect stock ROM typography curve from source XML:
#   - hyperos_mipro: HyperOS 1/2/3/4 XMLs with MiSans/MiLanPro/mipro weight offsets
#   - aosp_linear:   Standard AOSP / Pixel linear CSS weights
# Sets: CT_ROM_CURVE
ct_detect_xml_curve_mode() {
    _xml_src="$1"
    if [ -r "$_xml_src" ] \
        && grep -qE 'MiSansVF|MiLanProVF|mipro|weight="350"' "$_xml_src" 2>/dev/null; then
        CT_ROM_CURVE="hyperos_mipro"
    else
        CT_ROM_CURVE="aosp_linear"
    fi
}

# Dynamic Weight Curve Calculator:
#   wght_out = clamp(base(slot, rom_curve) + contrast_delta(slot, contrast_mode) + tapered_bias(slot, weight_bias), 100, 950)
# Usage: ct_calc_wght <slot_weight>
ct_calc_wght() {
    _slot="$1"
    _rom="${CT_ROM_CURVE:-hyperos_mipro}"
    _cm="${CT_CONTRAST_MODE:-balanced}"
    _bias="${CT_WEIGHT_BIAS:-0}"

    # 1. ROM-calibrated perceptual baseline
    if [ "$_rom" = "aosp_linear" ]; then
        case "$_slot" in
            100) _base=160 ;;
            200) _base=240 ;;
            300) _base=320 ;;
            350) _base=380 ;;
            400) _base=400 ;;
            500) _base=500 ;;
            600) _base=570 ;;
            700) _base=650 ;;
            800) _base=740 ;;
            900) _base=830 ;;
            950) _base=900 ;;
            *)   _base="$_slot" ;;
        esac
    else
        # HyperOS mipro compensation: mipro-normal(350)->400, mipro-demibold(700)->550, mipro-semibold(800)->650
        case "$_slot" in
            100) _base=170 ;;
            200) _base=250 ;;
            300) _base=340 ;;
            350) _base=400 ;;
            400) _base=400 ;;
            500) _base=485 ;;
            600) _base=535 ;;
            700) _base=550 ;;
            800) _base=650 ;;
            900) _base=740 ;;
            950) _base=830 ;;
            *)   _base="$_slot" ;;
        esac
    fi

    # 2. Dynamic Header Contrast slope (anchors body 400, adjusts header hierarchy 600..900)
    _cdelta=0
    case "$_cm" in
        soft)
            case "$_slot" in
                600) _cdelta=-25 ;;
                700) _cdelta=-30 ;;
                800) _cdelta=-35 ;;
                900) _cdelta=-30 ;;
            esac
            ;;
        apple_native)
            case "$_slot" in
                600) _cdelta=25 ;;
                700) _cdelta=45 ;;
                800) _cdelta=45 ;;
                900) _cdelta=40 ;;
            esac
            ;;
    esac

    # 3. Tapered User Weight Bias (100% on core UI 350..700, 75% on 300/800, 50% on extremes)
    case "$_slot" in
        100|200|900|950) _bdelta=$((_bias / 2)) ;;
        300|800)         _bdelta=$(((_bias * 3) / 4)) ;;
        *)               _bdelta="$_bias" ;;
    esac

    _out=$((_base + _cdelta + _bdelta))
    [ "$_out" -lt 100 ] && _out=100
    [ "$_out" -gt 950 ] && _out=950
    printf '%s' "$_out"
}

ct_emit_sans_serif_entries() {
    # Thin / Light (Lockscreen Clocks & Display Hero) -> SF Pro Display (opsz=28 + Display trak)
    _w100=$(ct_calc_wght 100)
    _w200=$(ct_calc_wght 200)
    _w300=$(ct_calc_wght 300)
    _w350=$(ct_calc_wght 350)
    _w400=$(ct_calc_wght 400)
    _w500=$(ct_calc_wght 500)
    _w600=$(ct_calc_wght 600)
    _w700=$(ct_calc_wght 700)
    _w800=$(ct_calc_wght 800)
    _w900=$(ct_calc_wght 900)
    _w950=$(ct_calc_wght 950)

    ct_emit_font_entry 100 normal display "$CT_WDTH_DISP" "$_w100"
    ct_emit_font_entry 100 italic display "$CT_WDTH_DISP" "$_w100"
    ct_emit_font_entry 200 normal display "$CT_WDTH_DISP" "$_w200"
    ct_emit_font_entry 200 italic display "$CT_WDTH_DISP" "$_w200"
    ct_emit_font_entry 300 normal display "$CT_WDTH_DISP" "$_w300"
    ct_emit_font_entry 300 italic display "$CT_WDTH_DISP" "$_w300"
    # Body / Notes Editor / Chat / UI Labels -> SF Pro Text (opsz=17 + Text trak)
    ct_emit_font_entry 350 normal text "$CT_WDTH_TEXT" "$_w350"
    ct_emit_font_entry 400 normal text "$CT_WDTH_TEXT" "$_w400"
    ct_emit_font_entry 400 italic text "$CT_WDTH_TEXT" "$_w400"
    ct_emit_font_entry 500 normal text "$CT_WDTH_MID" "$_w500"
    ct_emit_font_entry 500 italic text "$CT_WDTH_MID" "$_w500"
    # Headers / Section Labels / Bold -> SF Pro Display (opsz=28 + Display trak)
    ct_emit_font_entry 600 normal display "$CT_WDTH_DISP" "$_w600"
    ct_emit_font_entry 600 italic display "$CT_WDTH_DISP" "$_w600"
    ct_emit_font_entry 700 normal display "$CT_WDTH_DISP" "$_w700"
    ct_emit_font_entry 700 italic display "$CT_WDTH_DISP" "$_w700"
    ct_emit_font_entry 800 normal display "$CT_WDTH_DISP" "$_w800"
    ct_emit_font_entry 800 italic display "$CT_WDTH_DISP" "$_w800"
    ct_emit_font_entry 900 normal display "$CT_WDTH_DISP" "$_w900"
    ct_emit_font_entry 900 italic display "$CT_WDTH_DISP" "$_w900"
    ct_emit_font_entry 950 normal display "$CT_WDTH_DISP" "$_w950"
}

ct_emit_condensed_entries() {
    _w300=$(ct_calc_wght 300)
    _w400=$(ct_calc_wght 400)
    _w500=$(ct_calc_wght 500)
    _w600=$(ct_calc_wght 600)
    _w700=$(ct_calc_wght 700)

    ct_emit_font_entry 300 normal display "$CT_WDTH_COND" "$_w300"
    ct_emit_font_entry 400 normal text "$CT_WDTH_COND" "$_w400"
    ct_emit_font_entry 400 italic text "$CT_WDTH_COND" "$_w400"
    ct_emit_font_entry 500 normal text "$CT_WDTH_COND" "$_w500"
    ct_emit_font_entry 600 normal display "$CT_WDTH_COND" "$_w600"
    ct_emit_font_entry 700 normal display "$CT_WDTH_COND" "$_w700"
    ct_emit_font_entry 700 italic display "$CT_WDTH_COND" "$_w700"
}

ct_emit_display_entries() {
    _w300=$(ct_calc_wght 300)
    _w400=$(ct_calc_wght 400)
    _w500=$(ct_calc_wght 500)
    _w600=$(ct_calc_wght 600)
    _w700=$(ct_calc_wght 700)
    _w800=$(ct_calc_wght 800)
    _w900=$(ct_calc_wght 900)

    ct_emit_font_entry 300 normal display "$CT_WDTH_DISP" "$_w300"
    ct_emit_font_entry 400 normal display "$CT_WDTH_DISP" "$_w400"
    ct_emit_font_entry 500 normal display "$CT_WDTH_DISP" "$_w500"
    ct_emit_font_entry 600 normal display "$CT_WDTH_DISP" "$_w600"
    ct_emit_font_entry 700 normal display "$CT_WDTH_DISP" "$_w700"
    ct_emit_font_entry 800 normal display "$CT_WDTH_DISP" "$_w800"
    ct_emit_font_entry 900 normal display "$CT_WDTH_DISP" "$_w900"
}

ct_emit_flex_entries() {
    _w100=$(ct_calc_wght 100)
    _w200=$(ct_calc_wght 200)
    _w300=$(ct_calc_wght 300)
    _w350=$(ct_calc_wght 350)
    _w400=$(ct_calc_wght 400)
    _w500=$(ct_calc_wght 500)
    _w600=$(ct_calc_wght 600)
    _w700=$(ct_calc_wght 700)
    _w800=$(ct_calc_wght 800)
    _w900=$(ct_calc_wght 900)
    _w950=$(ct_calc_wght 950)

    # Graduated Apple CoreText optical ramp (Body 17 -> Medium 18 -> Title3 21 -> Title2 24 -> Display 28)
    ct_emit_flex_font_entry 100 normal 28 "$CT_WDTH_DISP" "$_w100"
    ct_emit_flex_font_entry 200 normal 28 "$CT_WDTH_DISP" "$_w200"
    ct_emit_flex_font_entry 300 normal 24 "$CT_WDTH_DISP" "$_w300"
    ct_emit_flex_font_entry 350 normal 17 "$CT_WDTH_TEXT" "$_w350"
    ct_emit_flex_font_entry 400 normal 17 "$CT_WDTH_TEXT" "$_w400"
    ct_emit_flex_font_entry 400 italic 17 "$CT_WDTH_TEXT" "$_w400"
    ct_emit_flex_font_entry 500 normal 18 "$CT_WDTH_MID" "$_w500"
    ct_emit_flex_font_entry 500 italic 18 "$CT_WDTH_MID" "$_w500"
    ct_emit_flex_font_entry 600 normal 21 "$CT_WDTH_DISP" "$_w600"
    ct_emit_flex_font_entry 700 normal 24 "$CT_WDTH_DISP" "$_w700"
    ct_emit_flex_font_entry 700 italic 24 "$CT_WDTH_DISP" "$_w700"
    ct_emit_flex_font_entry 800 normal 28 "$CT_WDTH_DISP" "$_w800"
    ct_emit_flex_font_entry 900 normal 28 "$CT_WDTH_DISP" "$_w900"
    ct_emit_flex_font_entry 950 normal 28 "$CT_WDTH_DISP" "$_w950"
}

# Structural XML sanity check (prevents malformed XML or missing slot files from reaching Zygote)
# Usage: ct_validate_font_xml <xml_path> [fonts_dir]
ct_validate_font_xml() {
    _xml="$1"
    _fdir="${2:-}"

    [ -s "$_xml" ] || return 1
    grep -q '<familyset' "$_xml" || return 1
    grep -q '</familyset>' "$_xml" || return 1
    grep -q 'CoreType Dual-Optical' "$_xml" || return 1

    # Zero-crash guarantee: NEVER allow non-stock CoreType-SFPro-*.ttf filenames in XML
    if grep -q 'CoreType-SFPro' "$_xml"; then
        return 1
    fi

    # Verify balanced <family> and <font> open/close counts (ignoring XML comments)
    if ! awk '
        BEGIN { in_c=0; fo=0; fc=0; fno=0; fnc=0 }
        {
            line = $0
            while (in_c || index(line, "<!--") > 0) {
                if (in_c) {
                    p = index(line, "-->")
                    if (p == 0) { line = ""; break }
                    line = substr(line, p + 3)
                    in_c = 0
                } else {
                    s = index(line, "<!--")
                    e = index(substr(line, s + 4), "-->")
                    if (e == 0) { line = substr(line, 1, s - 1); in_c = 1; break }
                    line = substr(line, 1, s - 1) substr(line, s + 4 + e + 2)
                }
            }
            tmp = line
            while (match(tmp, /<family([ \t]|>)/)) { fo++; tmp = substr(tmp, RSTART + RLENGTH) }
            tmp = line
            while (match(tmp, /<\/family>/)) { fc++; tmp = substr(tmp, RSTART + RLENGTH) }
            tmp = line
            while (match(tmp, /<font([ \t]|>)/)) {
                rest = substr(tmp, RSTART)
                next_pos = RSTART + RLENGTH
                if (rest ~ /^<font[^>]*\/>/) {
                    sub(/^<font[^>]*\/>/, "", rest)
                    tmp = rest
                    continue
                }
                fno++
                tmp = substr(tmp, next_pos)
            }
            tmp = line
            while (match(tmp, /<\/font>/)) { fnc++; tmp = substr(tmp, RSTART + RLENGTH) }
        }
        END {
            if (in_c != 0 || fo == 0 || fo != fc || fno == 0 || fno != fnc) exit 1
        }
    ' "$_xml"; then
        return 1
    fi

    if [ -n "$_fdir" ]; then
        for _req in "$CT_SLOT_TEXT" "$CT_SLOT_DISP" "$CT_SLOT_ITAL" "$CT_SLOT_DITAL" "${CT_SLOT_FLEX:-$CT_SLOT_TEXT}"; do
            [ -s "$_fdir/$_req" ] || return 1
        done
    fi

    return 0
}

ct_emit_cjk_zh_hans_entries() {
    _cjk="$1"
    case "$_cjk" in
        *.ttc)
            printf '        <font weight="400" style="normal" index="2">%s</font>\n' "$_cjk"
            ;;
        *VF.ttf)
            for _cw in 100 200 300 400 500 600 700 800 900; do
                printf '        <font weight="%s" style="normal">%s\n' "$_cw" "$_cjk"
                printf '            <axis tag="wght" stylevalue="%s" />\n' "$_cw"
                printf '        </font>\n'
            done
            ;;
        *)
            printf '        <font weight="400" style="normal">%s</font>\n' "$_cjk"
            ;;
    esac
}

# Usage: ct_patch_font_xml <src_xml> <dst_xml> <profile_id> [fonts_dir]
ct_patch_font_xml() {
    _src="$1"
    _dst="$2"
    _prof="${3:-dynamic_optical}"
    _fdir="${4:-}"

    [ -r "$_src" ] || return 1
    ct_load_profile "$_prof"
    ct_detect_xml_curve_mode "$_src"
    [ -n "${CT_SLOT_TEXT:-}" ] || ct_resolve_stock_slots "/system/fonts"

    mkdir -p "$(dirname "$_dst")" || return 1

    _sans_file="$_dst.sans.$$"
    _cond_file="$_dst.cond.$$"
    _disp_file="$_dst.disp.$$"
    _flex_file="$_dst.flex.$$"
    _cjk_file="$_dst.cjk.$$"
    _tmp_out="$_dst.tmp.$$"

    ct_emit_sans_serif_entries > "$_sans_file"
    ct_emit_condensed_entries > "$_cond_file"
    ct_emit_display_entries > "$_disp_file"
    ct_emit_flex_entries > "$_flex_file"

    _cjk_redirect="0"
    if [ "${CT_MISANS_SLIDER_ACTIVE:-0}" = "1" ] && [ -n "${CT_CJK_FALLBACK:-}" ]; then
        ct_emit_cjk_zh_hans_entries "$CT_CJK_FALLBACK" > "$_cjk_file"
        _cjk_redirect="1"
    else
        : > "$_cjk_file"
    fi

    awk -v sans_f="$_sans_file" \
        -v cond_f="$_cond_file" \
        -v disp_f="$_disp_file" \
        -v flex_f="$_flex_file" \
        -v cjk_f="$_cjk_file" \
        -v cjk_on="$_cjk_redirect" '
        function dump_file(path,    line) {
            while ((getline line < path) > 0) print line
            close(path)
        }
        function emit_wrapped(open_tag, body_path, add_marker) {
            if (add_marker) print "    <!-- CoreType Dual-Optical -->"
            print open_tag
            dump_file(body_path)
            print "    </family>"
        }
        function extract_open_tag(line,    idx) {
            idx = index(line, ">")
            if (idx > 0) return substr(line, 1, idx)
            return line
        }
        function classify_family(line) {
            if (line ~ /name="roboto-flex"/) return "flex"
            if (line ~ /name="(sans-serif|mipro|misans|misans-latin|miui|google-sans|google-sans-text|google-sans-medium|inter)"/) return "sans"
            if (line ~ /name="sans-serif-condensed"/) return "cond"
            if (line ~ /name="(sans-serif-display|google-sans-display|mipro-display)"/) return "disp"
            if (cjk_on == "1" && line ~ /lang="zh-Hans"/) return "zh_hans"
            if (line ~ /<family[ \t]*>/) return "unnamed"
            return "other"
        }
        function flush_family() {
            if (fam_type == "sans") {
                emit_wrapped(fam_open, sans_f, 1)
            } else if (fam_type == "flex") {
                emit_wrapped(fam_open, flex_f, 0)
            } else if (fam_type == "cond") {
                emit_wrapped(fam_open, cond_f, 0)
            } else if (fam_type == "disp") {
                emit_wrapped(fam_open, disp_f, 0)
            } else if (fam_type == "zh_hans" && (fam_buf ~ /MiSansVF\.ttf/ || fam_buf ~ /MiLanProVF\.ttf/)) {
                emit_wrapped(fam_open, cjk_f, 0)
            } else if (fam_type == "unnamed" && (fam_buf ~ /MiSansLatinVF\.ttf/ || fam_buf ~ /Roboto-Regular\.ttf/)) {
                emit_wrapped("    <family>", sans_f, 1)
            } else {
                printf "%s", fam_buf
            }
            in_fam = 0
            fam_buf = ""
        }
        BEGIN {
            in_fam = 0
            in_cmt = 0
            fam_buf = ""
            fam_open = ""
            fam_type = ""
        }
        in_cmt == 1 {
            print
            if (index($0, "-->") > 0) in_cmt = 0
            next
        }
        in_fam == 0 && index($0, "<!--") > 0 {
            print
            s = index($0, "<!--")
            if (index(substr($0, s + 4), "-->") == 0) in_cmt = 1
            next
        }
        /<family([ \t]|>)/ {
            in_fam = 1
            fam_buf = $0 "\n"
            fam_open = extract_open_tag($0)
            fam_type = classify_family($0)
            if ($0 ~ /<\/family>/) {
                flush_family()
            }
            next
        }
        in_fam == 1 {
            fam_buf = fam_buf $0 "\n"
            if ($0 ~ /<\/family>/) {
                flush_family()
            }
            next
        }
        { print }
    ' "$_src" > "$_tmp_out"

    rm -f "$_sans_file" "$_cond_file" "$_disp_file" "$_flex_file" "$_cjk_file"

    if ct_validate_font_xml "$_tmp_out" "$_fdir"; then
        mkdir -p "$(dirname "$_dst")"
        mv "$_tmp_out" "$_dst"
        return 0
    fi

    rm -f "$_tmp_out"
    return 1
}
