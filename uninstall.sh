#!/system/bin/sh
# CoreType — Clean Uninstall

_pid_file="/data/adb/coretype/watcher.pid"
if [ -r "$_pid_file" ]; then
    _wpid=$(tr -cd '0-9' < "$_pid_file" 2>/dev/null)
    if [ -n "$_wpid" ]; then
        kill "$_wpid" 2>/dev/null || true
    fi
fi

rm -rf /data/adb/coretype 2>/dev/null || true
