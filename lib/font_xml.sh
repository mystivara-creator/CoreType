#!/system/bin/sh
# CoreType — Schema-Faithful Dual-Optical XML Patcher & Structural Validator
# Routes Body (350..500) -> CoreType-SFPro-Text (opsz=17 + Apple Text trak)
# Routes Headers (600..950) & Clocks (100..300) -> CoreType-SFPro-Display (opsz=28 + Apple Display trak)
# Preserves 100% of device fallback families (CJK, Arabic, Indic, Emoji, Symbols).

# Usage: ct_emit_font_entry <weight> <normal|italic> <text|display> <wdth> <use_psname:0|1>
ct_emit_font_entry() {
    _w="$1"
    _style="$2"
    _optical="$3"
    _wdth="$4"
    _use_ps="$5"

    if [ "$_optical" = "display" ]; then
        if [ "$_style" = "italic" ]; then
            _file="CoreType-SFPro-Display-Italic.ttf"
            _ps="CoreTypeSFProDisplay-Italic"
        else
            _file="CoreType-SFPro-Display.ttf"
            _ps="CoreTypeSFProDisplay-Regular"
        fi
    else
        if [ "$_style" = "italic" ]; then
            _file="CoreType-SFPro-Text-Italic.ttf"
            _ps="CoreTypeSFProText-Italic"
        else
            _file="CoreType-SFPro-Text.ttf"
            _ps="CoreTypeSFProText-Regular"
        fi
    fi

    if [ "$_use_ps" = "1" ]; then
        printf '        <font weight="%s" style="%s" postScriptName="%s">%s\n' "$_w" "$_style" "$_ps" "$_file"
    else
        printf '        <font weight="%s" style="%s">%s\n' "$_w" "$_style" "$_file"
    fi
    printf '            <axis tag="wght" stylevalue="%s" />\n' "$_w"
    if [ "$_style" = "normal" ]; then
        printf '            <axis tag="wdth" stylevalue="%s" />\n' "$_wdth"
    fi
    printf '        </font>\n'
}

ct_emit_sans_serif_block() {
    _open_tag="$1"
    _use_ps="$2"
    printf '    %s\n' "$_open_tag"
    # Thin / Light (Lockscreen Clocks & Display Hero) -> True SF Pro Display (opsz=28 + Display trak)
    ct_emit_font_entry 100 normal display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 100 italic display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 200 normal display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 200 italic display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 300 normal display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 300 italic display "$CT_WDTH_DISP" "$_use_ps"
    # Body / Chat / Notifications / UI Labels -> True SF Pro Text (opsz=17 + Text trak)
    ct_emit_font_entry 350 normal text "$CT_WDTH_TEXT" "$_use_ps"
    ct_emit_font_entry 400 normal text "$CT_WDTH_TEXT" "$_use_ps"
    ct_emit_font_entry 400 italic text "$CT_WDTH_TEXT" "$_use_ps"
    ct_emit_font_entry 500 normal text "$CT_WDTH_MID" "$_use_ps"
    ct_emit_font_entry 500 italic text "$CT_WDTH_MID" "$_use_ps"
    # Headers / Settings Titles / App Bars / Bold -> True SF Pro Display (opsz=28 + Display trak)
    ct_emit_font_entry 600 normal display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 600 italic display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 700 normal display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 700 italic display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 800 normal display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 800 italic display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 900 normal display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 900 italic display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 950 normal display "$CT_WDTH_DISP" "$_use_ps"
    printf '    </family>\n'
}

ct_emit_condensed_block() {
    _open_tag="$1"
    _use_ps="$2"
    printf '    %s\n' "$_open_tag"
    ct_emit_font_entry 300 normal display "$CT_WDTH_COND" "$_use_ps"
    ct_emit_font_entry 400 normal text "$CT_WDTH_COND" "$_use_ps"
    ct_emit_font_entry 400 italic text "$CT_WDTH_COND" "$_use_ps"
    ct_emit_font_entry 500 normal text "$CT_WDTH_COND" "$_use_ps"
    ct_emit_font_entry 600 normal display "$CT_WDTH_COND" "$_use_ps"
    ct_emit_font_entry 700 normal display "$CT_WDTH_COND" "$_use_ps"
    ct_emit_font_entry 700 italic display "$CT_WDTH_COND" "$_use_ps"
    printf '    </family>\n'
}

ct_emit_display_block() {
    _open_tag="$1"
    _use_ps="$2"
    printf '    %s\n' "$_open_tag"
    ct_emit_font_entry 300 normal display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 400 normal display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 500 normal display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 600 normal display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 700 normal display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 800 normal display "$CT_WDTH_DISP" "$_use_ps"
    ct_emit_font_entry 900 normal display "$CT_WDTH_DISP" "$_use_ps"
    printf '    </family>\n'
}

# Structural XML sanity check (prevents malformed XML from ever reaching Zygote)
# Usage: ct_validate_font_xml <xml_path> [fonts_dir]
ct_validate_font_xml() {
    _xml="$1"
    _fdir="${2:-}"

    [ -s "$_xml" ] || return 1
    grep -q '<familyset' "$_xml" || return 1
    grep -q '</familyset>' "$_xml" || return 1
    grep -q 'CoreType-SFPro-Text\.ttf' "$_xml" || return 1
    grep -q 'CoreType-SFPro-Display\.ttf' "$_xml" || return 1

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
            while (match(tmp, /<family([[:space:]]|>)/)) { fo++; tmp = substr(tmp, RSTART + RLENGTH) }
            tmp = line
            while (match(tmp, /<\/family>/)) { fc++; tmp = substr(tmp, RSTART + RLENGTH) }
            tmp = line
            while (match(tmp, /<font([[:space:]]|>)/)) { fno++; tmp = substr(tmp, RSTART + RLENGTH) }
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
        for _req in \
            CoreType-SFPro-Text.ttf \
            CoreType-SFPro-Text-Italic.ttf \
            CoreType-SFPro-Display.ttf \
            CoreType-SFPro-Display-Italic.ttf; do
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

    # Match target schema: Android 14-16 font_fallback.xml supports postScriptName;
    # legacy fonts.xml (<familyset version="22">) omits postScriptName cleanly.
    _use_ps="0"
    case "$(basename "$_dst")" in
        font_fallback.xml) _use_ps="1" ;;
        *)
            if grep -q 'postScriptName=' "$_src" 2>/dev/null; then
                _use_ps="1"
            fi
            ;;
    esac

    _sans_file="$_dst.sans.$$"
    _latin_file="$_dst.latin.$$"
    _cond_file="$_dst.cond.$$"
    _disp_file="$_dst.disp.$$"
    _tmp_out="$_dst.tmp.$$"

    ct_emit_sans_serif_block '<family name="sans-serif">' "$_use_ps" > "$_sans_file"
    ct_emit_sans_serif_block '<family>' "$_use_ps" > "$_latin_file"
    ct_emit_condensed_block '<family name="sans-serif-condensed">' "$_use_ps" > "$_cond_file"
    ct_emit_display_block '<family name="sans-serif-display">' "$_use_ps" > "$_disp_file"

    awk -v sans_f="$_sans_file" \
        -v latin_f="$_latin_file" \
        -v cond_f="$_cond_file" \
        -v disp_f="$_disp_file" '
        function dump_file(path,    line) {
            while ((getline line < path) > 0) print line
            close(path)
        }
        BEGIN {
            in_fam = 0
            fam_buf = ""
            fam_type = ""
        }
        /<family([[:space:]]|>)/ {
            in_fam = 1
            fam_buf = $0 "\n"
            fam_type = "other"
            if ($0 ~ /name="sans-serif"/) fam_type = "sans"
            else if ($0 ~ /name="sans-serif-condensed"/) fam_type = "cond"
            else if ($0 ~ /name="sans-serif-display"/) fam_type = "disp"
            else if ($0 ~ /<family[[:space:]]*>/) fam_type = "unnamed"
            if ($0 ~ /<\/family>/) {
                if (fam_type == "sans") dump_file(sans_f)
                else if (fam_type == "cond") dump_file(cond_f)
                else if (fam_type == "disp") dump_file(disp_f)
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
                } else if (fam_type == "unnamed" && fam_buf ~ /MiSansLatinVF\.ttf/) {
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

    rm -f "$_sans_file" "$_latin_file" "$_cond_file" "$_disp_file"

    if ct_validate_font_xml "$_tmp_out" "$_fdir"; then
        mkdir -p "$(dirname "$_dst")"
        mv "$_tmp_out" "$_dst"
        return 0
    fi

    rm -f "$_tmp_out"
    return 1
}
