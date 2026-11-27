#!/system/bin/sh
# CoreType — Clean Uninstall (Gracefully stops native coretype-watchd & cleans /dev/.coretype)

for _pf in /dev/.coretype/watchd.pid /data/adb/coretype/watcher.pid; do
    if [ -r "$_pf" ]; then
        _wpid=$(tr -cd '0-9' < "$_pf" 2>/dev/null)
        if [ -n "$_wpid" ]; then
            kill -TERM "$_wpid" 2>/dev/null || true
        fi
    fi
done

rm -rf /dev/.coretype /data/adb/coretype 2>/dev/null || true
