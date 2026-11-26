#!/system/bin/sh
# CoreType — Dynamic font_fallback.xml & fonts.xml Optical Patcher
# Patches ONLY primary sans-serif / MiSansLatinVF / condensed / display families
# while preserving 100% of device-specific fallback families (CJK, Arabic, Emoji, etc.).

ct_emit_font_entry() {
    _w="$1"
    _style="$2"
    _opsz="$3"
    _wdth="$4"
    if [ "$_style" = "italic" ]; then
        printf '        <font weight="%s" style="italic" postScriptName="CoreTypeSFPro-Italic">CoreType-SFPro-Italic.ttf\n' "$_w"
        printf '            <axis tag="wght" stylevalue="%s" />\n' "$_w"
        printf '            <axis tag="opsz" stylevalue="%s" />\n' "$_opsz"
        printf '        </font>\n'
    else
        printf '        <font weight="%s" style="normal" postScriptName="CoreTypeSFPro-Regular">CoreType-SFPro.ttf\n' "$_w"
        printf '            <axis tag="wght" stylevalue="%s" />\n' "$_w"
        printf '            <axis tag="opsz" stylevalue="%s" />\n' "$_opsz"
        printf '            <axis tag="wdth" stylevalue="%s" />\n' "$_wdth"
        printf '        </font>\n'
    fi
}

ct_emit_sans_serif_block() {
    _open_tag="$1"
    printf '    %s\n' "$_open_tag"
    # Thin / Light (Lockscreen Clock & Display Hero) -> SF Pro Display (opsz 28)
    ct_emit_font_entry 100 normal 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 100 italic 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 200 normal 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 200 italic 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 300 normal 26.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 300 italic 26.0 "$CT_WDTH_DISP"
    # Body Text (Chat, Notifications, Paragraphs) -> True SF Pro Text (opsz 17)
    ct_emit_font_entry 350 normal 17.0 "$CT_WDTH_TEXT"
    ct_emit_font_entry 400 normal 17.0 "$CT_WDTH_TEXT"
    ct_emit_font_entry 400 italic 17.0 "$CT_WDTH_TEXT"
    # UI Labels / Buttons / List Titles -> Optical Bridge (opsz 20)
    ct_emit_font_entry 500 normal 20.0 "$CT_WDTH_MID"
    ct_emit_font_entry 500 italic 20.0 "$CT_WDTH_MID"
    # Headers / Settings Titles / App Bars -> Signature iOS Display (opsz 26..28)
    ct_emit_font_entry 600 normal 26.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 600 italic 26.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 700 normal 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 700 italic 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 800 normal 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 800 italic 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 900 normal 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 900 italic 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 950 normal 28.0 "$CT_WDTH_DISP"
    printf '    </family>\n'
}

ct_emit_condensed_block() {
    _open_tag="$1"
    printf '    %s\n' "$_open_tag"
    ct_emit_font_entry 300 normal 22.0 "$CT_WDTH_COND"
    ct_emit_font_entry 400 normal 17.0 "$CT_WDTH_COND"
    ct_emit_font_entry 400 italic 17.0 "$CT_WDTH_COND"
    ct_emit_font_entry 500 normal 20.0 "$CT_WDTH_COND"
    ct_emit_font_entry 600 normal 26.0 "$CT_WDTH_COND"
    ct_emit_font_entry 700 normal 28.0 "$CT_WDTH_COND"
    ct_emit_font_entry 700 italic 28.0 "$CT_WDTH_COND"
    printf '    </family>\n'
}

ct_emit_display_block() {
    _open_tag="$1"
    printf '    %s\n' "$_open_tag"
    ct_emit_font_entry 300 normal 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 400 normal 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 500 normal 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 600 normal 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 700 normal 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 800 normal 28.0 "$CT_WDTH_DISP"
    ct_emit_font_entry 900 normal 28.0 "$CT_WDTH_DISP"
    printf '    </family>\n'
}

# Usage: ct_patch_font_xml <src_xml> <dst_xml> <profile_id>
ct_patch_font_xml() {
    _src="$1"
    _dst="$2"
    _prof="${3:-dynamic_optical}"

    [ -r "$_src" ] || return 1
    ct_load_profile "$_prof"

    _sans_file="$_dst.sans.$$"
    _latin_file="$_dst.latin.$$"
    _cond_file="$_dst.cond.$$"
    _disp_file="$_dst.disp.$$"
    _tmp_out="$_dst.tmp.$$"

    ct_emit_sans_serif_block '<family name="sans-serif">' > "$_sans_file"
    ct_emit_sans_serif_block '<family>' > "$_latin_file"
    ct_emit_condensed_block '<family name="sans-serif-condensed">' > "$_cond_file"
    ct_emit_display_block '<family name="sans-serif-display">' > "$_disp_file"

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

    # Strict validation before atomic commit
    if [ -s "$_tmp_out" ] \
        && grep -q '<familyset' "$_tmp_out" \
        && grep -q '</familyset>' "$_tmp_out" \
        && grep -q 'CoreType-SFPro\.ttf' "$_tmp_out"; then
        mkdir -p "$(dirname "$_dst")"
        mv "$_tmp_out" "$_dst"
        return 0
    fi

    rm -f "$_tmp_out"
    return 1
}
