#!/system/bin/sh
# CoreType — KernelSU-Umount-Safe Dual-Optical XML Patcher & Structural Validator
#
# CRITICAL ANDROID 14-16 / KERNELSU-UMOUNT ARCHITECTURE:
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
#     - CT_SLOT_ITAL  (Text opsz=17 Italic)   -> Roboto-Italic.ttf / RobotoFlex-Regular.ttf / Roboto-Regular.ttf
#     - CT_SLOT_DITAL (Display opsz=28 Italic)-> Roboto-BoldItalic.ttf / $CT_SLOT_ITAL
#
#   Result: Mounted processes get 100% true Dual-Optical SF Pro (Display + Text + Italic),
#   while KernelSU-umounted apps fall back seamlessly to stock files with ZERO crashes.

# Discover existing stock font slots inside <sys_fonts_dir> (default: /system/fonts)
# Sets: CT_SLOT_TEXT, CT_SLOT_DISP, CT_SLOT_ITAL, CT_SLOT_DITAL
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

    if [ -e "$_sdir/Roboto-Italic.ttf" ]; then
        CT_SLOT_ITAL="Roboto-Italic.ttf"
    elif [ -e "$_sdir/RobotoFlex-Regular.ttf" ]; then
        CT_SLOT_ITAL="RobotoFlex-Regular.ttf"
    else
        CT_SLOT_ITAL="$CT_SLOT_TEXT"
    fi

    if [ -e "$_sdir/Roboto-BoldItalic.ttf" ]; then
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
    } > "$_sf.tmp.$$" && mv "$_sf.tmp.$$" "$_sf"
}

ct_load_slots() {
    _sf="$CT_DATA_DIR/slots.conf"
    if [ -r "$_sf" ]; then
        CT_SLOT_TEXT=$(awk -F= '$1=="CT_SLOT_TEXT"{print $2;exit}' "$_sf")
        CT_SLOT_DISP=$(awk -F= '$1=="CT_SLOT_DISP"{print $2;exit}' "$_sf")
        CT_SLOT_ITAL=$(awk -F= '$1=="CT_SLOT_ITAL"{print $2;exit}' "$_sf")
        CT_SLOT_DITAL=$(awk -F= '$1=="CT_SLOT_DITAL"{print $2;exit}' "$_sf")
    fi
    [ -n "${CT_SLOT_TEXT:-}" ] || ct_resolve_stock_slots "/system/fonts"
}

# Usage: ct_emit_font_entry <weight> <normal|italic> <text|display> <wdth> [wght_axis]
ct_emit_font_entry() {
    _w="$1"
    _style="$2"
    _optical="$3"
    _wdth="$4"
    _wght="${5:-$_w}"

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

ct_emit_sans_serif_block() {
    _open_tag="$1"
    printf '    <!-- CoreType Dual-Optical -->\n'
    printf '    %s\n' "$_open_tag"
    # Thin / Light (Lockscreen Clocks & Display Hero) -> SF Pro Display (opsz=28 + Display trak)
    ct_emit_font_entry 100 normal display "$CT_WDTH_DISP" 150
    ct_emit_font_entry 100 italic display "$CT_WDTH_DISP" 150
    ct_emit_font_entry 200 normal display "$CT_WDTH_DISP" 230
    ct_emit_font_entry 200 italic display "$CT_WDTH_DISP" 230
    ct_emit_font_entry 300 normal display "$CT_WDTH_DISP" 310
    ct_emit_font_entry 300 italic display "$CT_WDTH_DISP" 310
    # Body / Chat / Notifications / UI Labels -> SF Pro Text (opsz=17 + Text trak)
    ct_emit_font_entry 350 normal text "$CT_WDTH_TEXT" 370
    ct_emit_font_entry 400 normal text "$CT_WDTH_TEXT" 400
    ct_emit_font_entry 400 italic text "$CT_WDTH_TEXT" 400
    ct_emit_font_entry 500 normal text "$CT_WDTH_MID" 500
    ct_emit_font_entry 500 italic text "$CT_WDTH_MID" 500
    # Headers / Section Labels / Bold -> SF Pro Display (opsz=28 + Display trak)
    # Calibrated for HyperOS mipro weight offsets (mipro-demibold=700 -> iOS Semibold 590,
    # mipro-semibold=800 -> iOS Bold 680, mipro-bold=900 -> iOS Heavy 760).
    ct_emit_font_entry 600 normal display "$CT_WDTH_DISP" 550
    ct_emit_font_entry 600 italic display "$CT_WDTH_DISP" 550
    ct_emit_font_entry 700 normal display "$CT_WDTH_DISP" 590
    ct_emit_font_entry 700 italic display "$CT_WDTH_DISP" 590
    ct_emit_font_entry 800 normal display "$CT_WDTH_DISP" 680
    ct_emit_font_entry 800 italic display "$CT_WDTH_DISP" 680
    ct_emit_font_entry 900 normal display "$CT_WDTH_DISP" 760
    ct_emit_font_entry 900 italic display "$CT_WDTH_DISP" 760
    ct_emit_font_entry 950 normal display "$CT_WDTH_DISP" 850
    printf '    </family>\n'
}

ct_emit_condensed_block() {
    _open_tag="$1"
    printf '    %s\n' "$_open_tag"
    ct_emit_font_entry 300 normal display "$CT_WDTH_COND" 310
    ct_emit_font_entry 400 normal text "$CT_WDTH_COND" 400
    ct_emit_font_entry 400 italic text "$CT_WDTH_COND" 400
    ct_emit_font_entry 500 normal text "$CT_WDTH_COND" 500
    ct_emit_font_entry 600 normal display "$CT_WDTH_COND" 550
    ct_emit_font_entry 700 normal display "$CT_WDTH_COND" 590
    ct_emit_font_entry 700 italic display "$CT_WDTH_COND" 590
    printf '    </family>\n'
}

ct_emit_display_block() {
    _open_tag="$1"
    printf '    %s\n' "$_open_tag"
    ct_emit_font_entry 300 normal display "$CT_WDTH_DISP" 310
    ct_emit_font_entry 400 normal display "$CT_WDTH_DISP" 400
    ct_emit_font_entry 500 normal display "$CT_WDTH_DISP" 500
    ct_emit_font_entry 600 normal display "$CT_WDTH_DISP" 550
    ct_emit_font_entry 700 normal display "$CT_WDTH_DISP" 590
    ct_emit_font_entry 800 normal display "$CT_WDTH_DISP" 680
    ct_emit_font_entry 900 normal display "$CT_WDTH_DISP" 760
    printf '    </family>\n'
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
        for _req in "$CT_SLOT_TEXT" "$CT_SLOT_DISP" "$CT_SLOT_ITAL" "$CT_SLOT_DITAL"; do
            [ -s "$_fdir/$_req" ] || return 1
        done
    fi

    return 0
}

# Usage: ct_patch_font_xml <src_xml> <dst_xml> <profile_id> [fonts_dir]
ct_patch_font_xml() {
    _src="$1"
    _dst="$2"
    _prof="${3:-dynamic_optical}"
    _fdir="${4:-}"

    [ -r "$_src" ] || return 1
    ct_load_profile "$_prof"
    [ -n "${CT_SLOT_TEXT:-}" ] || ct_resolve_stock_slots "/system/fonts"

    mkdir -p "$(dirname "$_dst")" || return 1

    _sans_file="$_dst.sans.$$"
    _latin_file="$_dst.latin.$$"
    _cond_file="$_dst.cond.$$"
    _disp_file="$_dst.disp.$$"
    _flex_file="$_dst.flex.$$"
    _tmp_out="$_dst.tmp.$$"

    ct_emit_sans_serif_block '<family name="sans-serif">' > "$_sans_file"
    ct_emit_sans_serif_block '<family>' > "$_latin_file"
    ct_emit_condensed_block '<family name="sans-serif-condensed">' > "$_cond_file"
    ct_emit_display_block '<family name="sans-serif-display">' > "$_disp_file"
    ct_emit_sans_serif_block '<family name="roboto-flex">' > "$_flex_file"

    awk -v sans_f="$_sans_file" \
        -v latin_f="$_latin_file" \
        -v cond_f="$_cond_file" \
        -v disp_f="$_disp_file" \
        -v flex_f="$_flex_file" '
        function dump_file(path,    line) {
            while ((getline line < path) > 0) print line
            close(path)
        }
        BEGIN {
            in_fam = 0
            in_cmt = 0
            fam_buf = ""
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
            fam_type = "other"
            if ($0 ~ /name="sans-serif"/) fam_type = "sans"
            else if ($0 ~ /name="sans-serif-condensed"/) fam_type = "cond"
            else if ($0 ~ /name="sans-serif-display"/) fam_type = "disp"
            else if ($0 ~ /name="roboto-flex"/) fam_type = "flex"
            else if ($0 ~ /<family[ \t]*>/) fam_type = "unnamed"
            if ($0 ~ /<\/family>/) {
                if (fam_type == "sans") dump_file(sans_f)
                else if (fam_type == "cond") dump_file(cond_f)
                else if (fam_type == "disp") dump_file(disp_f)
                else if (fam_type == "flex") dump_file(flex_f)
                else printf "%s", fam_buf
                in_fam = 0
                fam_buf = ""
            }
            next
        }
        in_fam == 1 {
            fam_buf = fam_buf $0 "\n"
            if ($0 ~ /<\/family>/) {
                if (fam_type == "sans") {
                    dump_file(sans_f)
                } else if (fam_type == "cond") {
                    dump_file(cond_f)
                } else if (fam_type == "disp") {
                    dump_file(disp_f)
                } else if (fam_type == "flex") {
                    dump_file(flex_f)
                } else if (fam_type == "unnamed" && (fam_buf ~ /MiSansLatinVF\.ttf/ || fam_buf ~ /Roboto-Regular\.ttf/)) {
                    dump_file(latin_f)
                } else {
                    printf "%s", fam_buf
                }
                in_fam = 0
                fam_buf = ""
            }
            next
        }
        { print }
    ' "$_src" > "$_tmp_out"

    rm -f "$_sans_file" "$_latin_file" "$_cond_file" "$_disp_file" "$_flex_file"

    if ct_validate_font_xml "$_tmp_out" "$_fdir"; then
        mkdir -p "$(dirname "$_dst")"
        mv "$_tmp_out" "$_dst"
        return 0
    fi

    rm -f "$_tmp_out"
    return 1
}
