#!/system/bin/sh
# CoreType — Shared POSIX Shell Helpers

CT_DATA_DIR="${CT_DATA_DIR:-/data/adb/coretype}"
CT_CONF_FILE="$CT_DATA_DIR/config.conf"
CT_STATE_FILE="$CT_DATA_DIR/state.prop"
CT_LOG_FILE="$CT_DATA_DIR/coretype.log"

ct_init_dirs() {
    mkdir -p "$CT_DATA_DIR" 2>/dev/null || true
}

ct_log() {
    ct_init_dirs
    _ct_ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "00:00:00")
    printf '[%s] %s\n' "$_ct_ts" "$1" >> "$CT_LOG_FILE" 2>/dev/null || true
}

ct_conf_get() {
    _key="$1"
    _default="${2:-}"
    if [ -r "$CT_CONF_FILE" ]; then
        _val=$(awk -F= -v k="$_key" '$1 == k { sub(/^[^=]*=/, ""); print; found=1; exit } END { if (!found) exit 1 }' "$CT_CONF_FILE" 2>/dev/null)
        if [ -n "$_val" ]; then
            printf '%s\n' "$_val"
            return 0
        fi
    fi
    printf '%s\n' "$_default"
}

ct_conf_set() {
    _key="$1"
    _val="$2"
    ct_init_dirs
    _tmp="$CT_CONF_FILE.tmp.$$"
    if [ -r "$CT_CONF_FILE" ]; then
        awk -F= -v k="$_key" -v v="$_val" '
            BEGIN { done=0 }
            $1 == k { print k "=" v; done=1; next }
            { print }
            END { if (!done) print k "=" v }
        ' "$CT_CONF_FILE" > "$_tmp" 2>/dev/null && mv "$_tmp" "$CT_CONF_FILE"
    else
        printf '%s=%s\n' "$_key" "$_val" > "$_tmp" && mv "$_tmp" "$CT_CONF_FILE"
    fi
}

ct_state_set() {
    _key="$1"
    _val="$2"
    ct_init_dirs
    _tmp="$CT_STATE_FILE.tmp.$$"
    if [ -r "$CT_STATE_FILE" ]; then
        awk -F= -v k="$_key" -v v="$_val" '
            BEGIN { done=0 }
            $1 == k { print k "=" v; done=1; next }
            { print }
            END { if (!done) print k "=" v }
        ' "$CT_STATE_FILE" > "$_tmp" 2>/dev/null && mv "$_tmp" "$CT_STATE_FILE"
    else
        printf '%s=%s\n' "$_key" "$_val" > "$_tmp" && mv "$_tmp" "$CT_STATE_FILE"
    fi
}
