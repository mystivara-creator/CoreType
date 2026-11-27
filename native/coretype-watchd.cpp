#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

// CoreType — Native C++20 Event-Driven Typography Watcher (coretype-watchd)
// Zero-polling epoll + inotify + dual timerfd (250ms debounce + bounded recovery backoff) + signalfd.
// Target footprint: < 300 KB VmRSS, 0% idle CPU, 0 wakelock, 100% orthogonal to hardware daemons.
// Compatible with HyperOS 1 / 2 / 3 / 4 & Android 12–17 (arm64-v8a / aarch64).

#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <string>
#include <string_view>
#include <sys/epoll.h>
#include <sys/file.h>
#include <sys/inotify.h>
#include <sys/mount.h>
#include <sys/signalfd.h>
#include <sys/stat.h>
#include <sys/timerfd.h>
#include <sys/xattr.h>
#include <unistd.h>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#ifndef CLONE_NEWNS
#define CLONE_NEWNS 0x00020000
#endif

#ifndef MNT_DETACH
#define MNT_DETACH 2
#endif

namespace {

constexpr int kDebounceMs = 250;
constexpr int kRecoveryBackoffMs[] = {1000, 3000, 10000};
constexpr int kRecoveryStepCount = 3;
constexpr int kTextTrackingUpm = -46;
constexpr int kDisplayTrackingUpm = -26;
constexpr char kSelinuxSystemFile[] = "u:object_r:system_file:s0";

struct Config {
    std::string moddir = "/data/adb/modules/coretype";
    std::string datadir = "/data/adb/coretype";
    std::string rundir = "/dev/.coretype";
    std::string data_fonts_root = "/data/fonts/files";
    std::string gms_files_root = "/data/data/com.google.android.gms/files";
    bool oneshot = false;
    bool skip_fbe_wait = false;
};

struct SyncStats {
    int gms_latin_mounted = 0;
    int gms_emoji_mounted = 0;
    int64_t latency_us = 0;
};

bool file_exists(const std::string& path) {
    struct stat st {};
    return ::stat(path.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

bool dir_exists(const std::string& path) {
    struct stat st {};
    return ::stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

int64_t file_size(const std::string& path) {
    struct stat st {};
    if (::stat(path.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) {
        return -1;
    }
    return static_cast<int64_t>(st.st_size);
}

bool ensure_dir(const std::string& path, mode_t mode) {
    if (dir_exists(path)) {
        return true;
    }
    if (::mkdir(path.c_str(), mode) == 0) {
        ::chmod(path.c_str(), mode);
        return true;
    }
    return errno == EEXIST && dir_exists(path);
}

bool write_file_atomic(const std::string& path, const std::string& content, mode_t mode) {
    const std::string tmp = path + ".tmp." + std::to_string(::getpid());
    int fd = ::open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, mode);
    if (fd < 0) {
        return false;
    }
    const char* ptr = content.data();
    size_t remaining = content.size();
    while (remaining > 0) {
        ssize_t written = ::write(fd, ptr, remaining);
        if (written < 0) {
            if (errno == EINTR) continue;
            ::close(fd);
            ::unlink(tmp.c_str());
            return false;
        }
        ptr += written;
        remaining -= static_cast<size_t>(written);
    }
    ::fchmod(fd, mode);
    ::close(fd);
    if (::rename(tmp.c_str(), path.c_str()) != 0) {
        ::unlink(tmp.c_str());
        return false;
    }
    return true;
}

std::string read_small_file(const std::string& path) {
    int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return {};
    std::string out;
    char buf[4096];
    for (;;) {
        ssize_t n = ::read(fd, buf, sizeof(buf));
        if (n < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (n == 0) break;
        out.append(buf, static_cast<size_t>(n));
        if (out.size() > 262144) break;
    }
    ::close(fd);
    return out;
}

std::string read_prop_value(const std::string& file_path, std::string_view key, std::string_view fallback) {
    const std::string data = read_small_file(file_path);
    size_t start = 0;
    while (start < data.size()) {
        size_t end = data.find('\n', start);
        if (end == std::string::npos) end = data.size();
        std::string_view line(data.data() + start, end - start);
        if (!line.empty() && line.back() == '\r') {
            line.remove_suffix(1);
        }
        size_t eq = line.find('=');
        if (eq != std::string_view::npos && line.substr(0, eq) == key) {
            std::string_view val = line.substr(eq + 1);
            if (!val.empty()) {
                return std::string(val);
            }
        }
        start = end + 1;
    }
    return std::string(fallback);
}

bool contains_ci(std::string_view hay, std::string_view needle) {
    if (needle.empty() || hay.size() < needle.size()) return false;
    for (size_t i = 0; i + needle.size() <= hay.size(); ++i) {
        bool match = true;
        for (size_t j = 0; j < needle.size(); ++j) {
            char a = hay[i + j];
            char b = needle[j];
            if (a >= 'A' && a <= 'Z') a = static_cast<char>(a - 'A' + 'a');
            if (b >= 'A' && b <= 'Z') b = static_cast<char>(b - 'A' + 'a');
            if (a != b) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

bool starts_with(std::string_view s, std::string_view prefix) {
    return s.size() >= prefix.size() && s.substr(0, prefix.size()) == prefix;
}

bool ends_with(std::string_view s, std::string_view suffix) {
    return s.size() >= suffix.size() && s.substr(s.size() - suffix.size()) == suffix;
}

std::string_view path_basename(std::string_view p) {
    size_t slash = p.rfind('/');
    return (slash == std::string_view::npos) ? p : p.substr(slash + 1);
}

int read_self_rss_kb() {
    const std::string status = read_small_file("/proc/self/status");
    size_t pos = status.find("VmRSS:");
    if (pos == std::string::npos) return 0;
    pos += 6;
    while (pos < status.size() && (status[pos] == ' ' || status[pos] == '\t')) ++pos;
    int kb = 0;
    while (pos < status.size() && status[pos] >= '0' && status[pos] <= '9') {
        kb = kb * 10 + (status[pos] - '0');
        ++pos;
    }
    return kb;
}

void enter_global_mount_ns() {
    int fd = ::open("/proc/1/ns/mnt", O_RDONLY | O_CLOEXEC);
    if (fd >= 0) {
        (void)::setns(fd, CLONE_NEWNS);
        ::close(fd);
    }
}

bool module_disabled_or_removed(const Config& cfg) {
    if (!dir_exists(cfg.moddir)) return true;
    if (file_exists(cfg.moddir + "/disable")) return true;
    if (file_exists(cfg.moddir + "/remove")) return true;
    return false;
}

std::string unescape_mount_path(std::string_view raw) {
    std::string out;
    out.reserve(raw.size());
    for (size_t i = 0; i < raw.size(); ++i) {
        if (raw[i] == '\\' && i + 3 < raw.size() &&
            raw[i + 1] >= '0' && raw[i + 1] <= '7' &&
            raw[i + 2] >= '0' && raw[i + 2] <= '7' &&
            raw[i + 3] >= '0' && raw[i + 3] <= '7') {
            int val = (raw[i + 1] - '0') * 64 + (raw[i + 2] - '0') * 8 + (raw[i + 3] - '0');
            out.push_back(static_cast<char>(val));
            i += 3;
        } else {
            out.push_back(raw[i]);
        }
    }
    return out;
}

std::unordered_set<std::string> load_active_mounts() {
    std::unordered_set<std::string> mounts;
    std::string data = read_small_file("/proc/self/mountinfo");
    bool use_mountinfo = !data.empty();
    if (!use_mountinfo) {
        data = read_small_file("/proc/mounts");
    }
    size_t start = 0;
    while (start < data.size()) {
        size_t end = data.find('\n', start);
        if (end == std::string::npos) end = data.size();
        std::string_view line(data.data() + start, end - start);
        int target_field = use_mountinfo ? 4 : 1;
        int field = 0;
        size_t i = 0;
        while (i < line.size()) {
            while (i < line.size() && line[i] == ' ') ++i;
            size_t tok_start = i;
            while (i < line.size() && line[i] != ' ') ++i;
            if (field == target_field && i > tok_start) {
                mounts.insert(unescape_mount_path(line.substr(tok_start, i - tok_start)));
                break;
            }
            ++field;
        }
        start = end + 1;
    }
    return mounts;
}

bool valid_apple_emoji_master(const std::string& path) {
    if (file_size(path) <= 5242880) return false;
    int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return false;
    unsigned char magic[4] = {0, 0, 0, 0};
    ssize_t n = ::read(fd, magic, sizeof(magic));
    ::close(fd);
    return n == 4 && magic[0] == 0x00 && magic[1] == 0x01 && magic[2] == 0x00 && magic[3] == 0x00;
}

void prepare_font_source(const std::string& path) {
    if (!file_exists(path)) return;
    ::chmod(path.c_str(), 0644);
    (void)::setxattr(path.c_str(), "security.selinux", kSelinuxSystemFile, sizeof(kSelinuxSystemFile), 0);
}

bool is_latin_ui_gms_font(std::string_view base) {
    if (!ends_with(base, ".ttf")) return false;
    if (contains_ci(base, "emoji") || contains_ci(base, "mono") ||
        contains_ci(base, "icon") || contains_ci(base, "symbol") ||
        contains_ci(base, "serif") || contains_ci(base, "cjk") ||
        contains_ci(base, "arabic")) {
        return false;
    }
    return starts_with(base, "Google_Sans") || starts_with(base, "GoogleSans") ||
           starts_with(base, "Product_Sans") || starts_with(base, "ProductSans") ||
           starts_with(base, "Roboto") || starts_with(base, "Inter");
}

bool is_managed_latin_mount(const Config& cfg, std::string_view mpath) {
    if (mpath.find("/fonts/opentype/") == std::string_view::npos) return false;
    if (!starts_with(mpath, cfg.gms_files_root) &&
        mpath.find("/com.google.android.gms/files/fonts/opentype/") == std::string_view::npos) {
        return false;
    }
    return is_latin_ui_gms_font(path_basename(mpath));
}

bool is_managed_emoji_mount(const Config& cfg, std::string_view mpath) {
    std::string_view base = path_basename(mpath);
    if (!ends_with(base, ".ttf") || !contains_ci(base, "emoji")) return false;
    if (starts_with(mpath, cfg.data_fonts_root + "/") && base == "NotoColorEmoji.ttf") {
        return true;
    }
    if (starts_with(mpath, cfg.gms_files_root + "/fonts/opentype/")) {
        return true;
    }
    if (mpath.find("/com.google.android.gms/files/fonts/opentype/") != std::string_view::npos) {
        return true;
    }
    if (mpath.find("/com.facebook.") != std::string_view::npos &&
        mpath.find("/app_ras_blobs/") != std::string_view::npos) {
        return true;
    }
    return false;
}

std::string select_sfpro_source(const Config& cfg, std::string_view fname) {
    const std::string fdir = cfg.moddir + "/fonts/";
    const std::string f_text = fdir + "CoreType-SFPro-Text.ttf";
    const std::string f_disp = fdir + "CoreType-SFPro-Display.ttf";
    const std::string f_ital = fdir + "CoreType-SFPro-Text-Italic.ttf";
    const std::string f_dital = file_exists(fdir + "CoreType-SFPro-Display-Italic.ttf")
                                    ? (fdir + "CoreType-SFPro-Display-Italic.ttf")
                                    : f_ital;
    const std::string f_med = file_exists(fdir + "CoreType-SFPro-GMS-Medium.ttf")
                                  ? (fdir + "CoreType-SFPro-GMS-Medium.ttf")
                                  : f_text;
    const std::string f_bold = file_exists(fdir + "CoreType-SFPro-GMS-Bold.ttf")
                                   ? (fdir + "CoreType-SFPro-GMS-Bold.ttf")
                                   : f_disp;

    const bool is_italic = ends_with(fname, "-1_0.ttf") ||
                           fname.find("-1_0-") != std::string_view::npos ||
                           contains_ci(fname, "italic");
    const bool is_bold = fname.find("-600-") != std::string_view::npos ||
                         fname.find("-700-") != std::string_view::npos ||
                         fname.find("-800-") != std::string_view::npos ||
                         fname.find("-900-") != std::string_view::npos ||
                         contains_ci(fname, "bold");
    const bool is_medium = fname.find("-500-") != std::string_view::npos ||
                           contains_ci(fname, "medium");
    const bool is_display_light = contains_ci(fname, "display") ||
                                  fname.find("-100-") != std::string_view::npos ||
                                  fname.find("-200-") != std::string_view::npos ||
                                  fname.find("-300-") != std::string_view::npos ||
                                  contains_ci(fname, "light") ||
                                  contains_ci(fname, "thin");

    if (is_italic) {
        return (is_bold || contains_ci(fname, "display")) ? f_dital : f_ital;
    }
    if (is_bold) return f_bold;
    if (is_medium) return f_med;
    if (is_display_light) return f_disp;
    return f_text;
}

bool bind_ro_idempotent(const std::string& src, const std::string& dst,
                        std::unordered_set<std::string>& mounted) {
    if (!file_exists(dst) || !file_exists(src)) return false;
    if (mounted.find(dst) != mounted.end()) {
        return true;
    }
    if (::mount(src.c_str(), dst.c_str(), nullptr, MS_BIND, nullptr) == 0) {
        (void)::mount(nullptr, dst.c_str(), nullptr, MS_BIND | MS_REMOUNT | MS_RDONLY, nullptr);
        mounted.insert(dst);
        return true;
    }
    return false;
}

void detach_disabled_mounts(const Config& cfg, bool want_latin, bool want_emoji,
                            std::unordered_set<std::string>& mounted) {
    if (want_latin && want_emoji) return;
    std::vector<std::string> to_detach;
    for (const auto& m : mounted) {
        if (!want_latin && is_managed_latin_mount(cfg, m)) {
            to_detach.push_back(m);
        } else if (!want_emoji && is_managed_emoji_mount(cfg, m)) {
            to_detach.push_back(m);
        }
    }
    for (const auto& dst : to_detach) {
        if (::umount2(dst.c_str(), MNT_DETACH) == 0) {
            mounted.erase(dst);
        }
    }
}

void list_dir_entries(const std::string& dir, std::vector<std::string>& out) {
    DIR* d = ::opendir(dir.c_str());
    if (!d) return;
    while (struct dirent* ent = ::readdir(d)) {
        if (ent->d_name[0] == '.' &&
            (ent->d_name[1] == '\0' || (ent->d_name[1] == '.' && ent->d_name[2] == '\0'))) {
            continue;
        }
        out.emplace_back(ent->d_name);
    }
    ::closedir(d);
}

void sync_gms_opentype_dir(const Config& cfg, const std::string& ot_dir,
                           bool want_latin, bool want_emoji,
                           const std::string& emoji_src,
                           std::unordered_set<std::string>& mounted,
                           SyncStats& stats) {
    std::vector<std::string> entries;
    list_dir_entries(ot_dir, entries);
    for (const auto& name : entries) {
        const std::string full = ot_dir + "/" + name;
        if (want_emoji && !emoji_src.empty() && ends_with(name, ".ttf") && contains_ci(name, "emoji")) {
            if (bind_ro_idempotent(emoji_src, full, mounted)) {
                ++stats.gms_emoji_mounted;
            }
            continue;
        }
        if (want_latin && is_latin_ui_gms_font(name)) {
            const std::string src = select_sfpro_source(cfg, name);
            if (bind_ro_idempotent(src, full, mounted)) {
                ++stats.gms_latin_mounted;
            }
        }
    }
}

SyncStats perform_sync(const Config& cfg) {
    const auto t0 = std::chrono::steady_clock::now();
    SyncStats stats {};

    const std::string state_path = cfg.datadir + "/state.prop";
    const std::string conf_path = cfg.datadir + "/config.conf";

    // Prefer live WebUI config.conf toggle first so SIGUSR1 / Sync Now can live-unmount immediately
    std::string gms_latin_flag = read_prop_value(conf_path, "gms_fonts_enabled", "");
    if (gms_latin_flag.empty()) {
        gms_latin_flag = read_prop_value(state_path, "gms_fonts_enabled", "1");
    }
    std::string emoji_flag = read_prop_value(conf_path, "emoji_enabled", "");
    if (emoji_flag.empty()) {
        emoji_flag = read_prop_value(state_path, "emoji_active", "1");
    }

    const bool want_latin = (gms_latin_flag != "0");
    const bool want_emoji = (emoji_flag != "0");

    std::unordered_set<std::string> mounted = load_active_mounts();

    // Live-unmount any previously active GMS mounts when user toggles OFF in WebUI
    detach_disabled_mounts(cfg, want_latin, want_emoji, mounted);

    const std::string fdir = cfg.moddir + "/fonts/";
    if (want_latin) {
        prepare_font_source(fdir + "CoreType-SFPro-Text.ttf");
        prepare_font_source(fdir + "CoreType-SFPro-Text-Italic.ttf");
        prepare_font_source(fdir + "CoreType-SFPro-Display.ttf");
        prepare_font_source(fdir + "CoreType-SFPro-Display-Italic.ttf");
        prepare_font_source(fdir + "CoreType-SFPro-GMS-Medium.ttf");
        prepare_font_source(fdir + "CoreType-SFPro-GMS-Bold.ttf");
    }

    std::string emoji_src;
    if (want_emoji) {
        const std::string master = fdir + "CoreType-AppleEmoji.ttf";
        if (valid_apple_emoji_master(master)) {
            prepare_font_source(master);
            emoji_src = master;
            const std::string sys_emoji = "/system/fonts/NotoColorEmoji.ttf";
            if (file_size(sys_emoji) == file_size(master)) {
                emoji_src = sys_emoji;
            }
        }
    }

    // 1. Android FontManagerService dynamic emoji cache (/data/fonts/files/*/NotoColorEmoji.ttf)
    if (want_emoji && !emoji_src.empty() && dir_exists(cfg.data_fonts_root)) {
        std::vector<std::string> subdirs;
        list_dir_entries(cfg.data_fonts_root, subdirs);
        for (const auto& sub : subdirs) {
            const std::string target = cfg.data_fonts_root + "/" + sub + "/NotoColorEmoji.ttf";
            if (bind_ro_idempotent(emoji_src, target, mounted)) {
                ++stats.gms_emoji_mounted;
            }
        }
    }

    // 2. Primary GMS FontsProvider OpenType cache
    const std::string primary_ot = cfg.gms_files_root + "/fonts/opentype";
    if (dir_exists(primary_ot)) {
        sync_gms_opentype_dir(cfg, primary_ot, want_latin, want_emoji, emoji_src, mounted, stats);
    }

    // 3. Secondary Android users & existing Meta app_ras_blobs (live default GMS root only)
    if (cfg.gms_files_root == "/data/data/com.google.android.gms/files") {
        std::vector<std::string> users;
        list_dir_entries("/data/user", users);
        for (const auto& uid : users) {
            if (uid.empty() || uid == "0") continue;
            bool all_digits = true;
            for (char c : uid) {
                if (c < '0' || c > '9') { all_digits = false; break; }
            }
            if (!all_digits) continue;
            const std::string sec_ot = "/data/user/" + uid + "/com.google.android.gms/files/fonts/opentype";
            if (dir_exists(sec_ot)) {
                sync_gms_opentype_dir(cfg, sec_ot, want_latin, want_emoji, emoji_src, mounted, stats);
            }
        }

        if (want_emoji && !emoji_src.empty()) {
            std::vector<std::string> pkgs;
            list_dir_entries("/data/data", pkgs);
            for (const auto& pkg : pkgs) {
                if (!starts_with(pkg, "com.facebook.")) continue;
                const std::string blob_dir = "/data/data/" + pkg + "/app_ras_blobs";
                if (!dir_exists(blob_dir)) continue;
                std::vector<std::string> blobs;
                list_dir_entries(blob_dir, blobs);
                for (const auto& bf : blobs) {
                    if (ends_with(bf, ".ttf") && contains_ci(bf, "emoji")) {
                        if (bind_ro_idempotent(emoji_src, blob_dir + "/" + bf, mounted)) {
                            ++stats.gms_emoji_mounted;
                        }
                    }
                }
            }
        }
    }

    const auto t1 = std::chrono::steady_clock::now();
    stats.latency_us = std::chrono::duration_cast<std::chrono::microseconds>(t1 - t0).count();
    return stats;
}

class WatchManager {
public:
    WatchManager(int inotify_fd, const std::string& target_ot_dir)
        : ifd_(inotify_fd), target_ot_(target_ot_dir) {}

    void ensure_watch(const std::string& path, uint32_t mask) {
        if (!dir_exists(path)) return;
        if (path_to_wd_.find(path) != path_to_wd_.end()) return;
        int wd = ::inotify_add_watch(ifd_, path.c_str(), mask);
        if (wd >= 0) {
            wd_to_path_[wd] = path;
            path_to_wd_[path] = wd;
        }
    }

    // Erase wd mapping ONLY on IN_IGNORED to prevent wd reuse race conditions
    bool handle_ignored(int wd) {
        auto it = wd_to_path_.find(wd);
        if (it == wd_to_path_.end()) return false;
        const std::string old_path = it->second;
        path_to_wd_.erase(old_path);
        wd_to_path_.erase(it);
        if (old_path == target_ot_) {
            watch_healthy_ = false;
            needs_recovery_count_ = true;
            return true;
        }
        return false;
    }

    void mark_target_lost() {
        watch_healthy_ = false;
        needs_recovery_count_ = true;
    }

    // Returns true if GMS opentype watch is healthy; increments watch_recoveries_ on recovery
    bool arm_hierarchy(const Config& cfg) {
        constexpr uint32_t kDirMask =
            IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE_SELF | IN_MOVE_SELF;
        if (ends_with(cfg.gms_files_root, "/files")) {
            const std::string parent = cfg.gms_files_root.substr(0, cfg.gms_files_root.size() - 6);
            ensure_watch(parent, IN_CREATE | IN_MOVED_TO);
        }
        ensure_watch(cfg.gms_files_root, kDirMask);
        ensure_watch(cfg.gms_files_root + "/fonts", kDirMask);
        ensure_watch(target_ot_, kDirMask);
        ensure_watch(cfg.data_fonts_root, kDirMask);
        if (dir_exists(cfg.data_fonts_root)) {
            std::vector<std::string> subdirs;
            list_dir_entries(cfg.data_fonts_root, subdirs);
            for (const auto& sub : subdirs) {
                ensure_watch(cfg.data_fonts_root + "/" + sub, kDirMask);
            }
        }
        ensure_watch(cfg.moddir, IN_CREATE | IN_MOVED_TO | IN_DELETE_SELF);

        const bool ot_watched = (path_to_wd_.find(target_ot_) != path_to_wd_.end()) && dir_exists(target_ot_);
        if (ot_watched) {
            if (!watch_healthy_ && needs_recovery_count_) {
                ++watch_recoveries_;
                needs_recovery_count_ = false;
            }
            watch_healthy_ = true;
            recovery_step_ = 0;
        } else {
            watch_healthy_ = false;
            needs_recovery_count_ = true;
        }
        return watch_healthy_;
    }

    std::string path_for_wd(int wd) const {
        auto it = wd_to_path_.find(wd);
        return it != wd_to_path_.end() ? it->second : std::string{};
    }

    bool healthy() const { return watch_healthy_; }
    uint64_t recoveries() const { return watch_recoveries_; }

    int next_recovery_backoff_ms() {
        const int idx = (recovery_step_ < kRecoveryStepCount) ? recovery_step_ : (kRecoveryStepCount - 1);
        if (recovery_step_ + 1 < kRecoveryStepCount) {
            ++recovery_step_;
        }
        return kRecoveryBackoffMs[idx];
    }

private:
    int ifd_;
    std::string target_ot_;
    bool watch_healthy_ = false;
    bool needs_recovery_count_ = false;
    uint64_t watch_recoveries_ = 0;
    int recovery_step_ = 0;
    std::unordered_map<int, std::string> wd_to_path_;
    std::unordered_map<std::string, int> path_to_wd_;
};

void write_telemetry(const Config& cfg, const SyncStats& stats, uint64_t sync_count,
                     bool watch_healthy, uint64_t watch_recoveries) {
    const int rss_kb = read_self_rss_kb();
    std::string out;
    out.reserve(384);
    out += "daemon_mode=native-epoll\n";
    out += "daemon_pid=" + std::to_string(::getpid()) + "\n";
    out += "daemon_rss_kb=" + std::to_string(rss_kb) + "\n";
    out += "watch_health=" + std::string(watch_healthy ? "healthy" : "recovering") + "\n";
    out += "watch_recoveries=" + std::to_string(watch_recoveries) + "\n";
    out += "gms_latin_mounted=" + std::to_string(stats.gms_latin_mounted) + "\n";
    out += "gms_emoji_mounted=" + std::to_string(stats.gms_emoji_mounted) + "\n";
    out += "sync_count=" + std::to_string(sync_count) + "\n";
    out += "last_sync_latency_us=" + std::to_string(stats.latency_us) + "\n";
    out += "active_text_tracking_upm=" + std::to_string(kTextTrackingUpm) + "\n";
    out += "active_display_tracking_upm=" + std::to_string(kDisplayTrackingUpm) + "\n";
    (void)write_file_atomic(cfg.rundir + "/telemetry.prop", out, 0644);
}

void set_oneshot_timer(int tfd, int ms) {
    struct itimerspec its {};
    if (ms > 0) {
        its.it_value.tv_sec = ms / 1000;
        its.it_value.tv_nsec = static_cast<long>(ms % 1000) * 1000000L;
    }
    its.it_interval.tv_sec = 0;
    its.it_interval.tv_nsec = 0;
    (void)::timerfd_settime(tfd, 0, &its, nullptr);
}

void cleanup_rundir(const Config& cfg, int lock_fd) {
    ::unlink((cfg.rundir + "/watchd.pid").c_str());
    ::unlink((cfg.rundir + "/telemetry.prop").c_str());
    ::unlink((cfg.rundir + "/watchd.lock").c_str());
    if (lock_fd >= 0) {
        ::flock(lock_fd, LOCK_UN);
        ::close(lock_fd);
    }
    ::rmdir(cfg.rundir.c_str());
}

bool parse_args(int argc, char** argv, Config& cfg) {
    for (int i = 1; i < argc; ++i) {
        std::string_view arg(argv[i]);
        if (arg == "--moddir" && i + 1 < argc) {
            cfg.moddir = argv[++i];
        } else if (arg == "--datadir" && i + 1 < argc) {
            cfg.datadir = argv[++i];
        } else if (arg == "--rundir" && i + 1 < argc) {
            cfg.rundir = argv[++i];
        } else if (arg == "--data-fonts" && i + 1 < argc) {
            cfg.data_fonts_root = argv[++i];
        } else if (arg == "--gms-files" && i + 1 < argc) {
            cfg.gms_files_root = argv[++i];
        } else if (arg == "--oneshot") {
            cfg.oneshot = true;
        } else if (arg == "--no-fbe-wait") {
            cfg.skip_fbe_wait = true;
        } else if (arg == "--version") {
            std::puts("coretype-watchd 1.2.0");
            return false;
        } else if (arg == "--help") {
            std::puts("Usage: coretype-watchd [--moddir PATH] [--datadir PATH] [--rundir PATH] [--oneshot] [--no-fbe-wait]");
            return false;
        }
    }
    return true;
}

}  // namespace

int main(int argc, char** argv) {
    Config cfg;
    if (!parse_args(argc, argv, cfg)) {
        return 0;
    }

    enter_global_mount_ns();

    if (!ensure_dir(cfg.rundir, 0755)) {
        return 1;
    }

    // Atomic single-instance lock
    const std::string lock_path = cfg.rundir + "/watchd.lock";
    int lock_fd = ::open(lock_path.c_str(), O_CREAT | O_RDWR | O_CLOEXEC, 0600);
    if (lock_fd < 0) {
        return 1;
    }
    if (::flock(lock_fd, LOCK_EX | LOCK_NB) != 0) {
        ::close(lock_fd);
        return 0;  // Another instance is already active
    }

    (void)write_file_atomic(cfg.rundir + "/watchd.pid", std::to_string(::getpid()) + "\n", 0644);

    if (cfg.oneshot) {
        SyncStats st = perform_sync(cfg);
        const bool ot_ok = dir_exists(cfg.gms_files_root + "/fonts/opentype");
        write_telemetry(cfg, st, 1, ot_ok, 0);
        ::flock(lock_fd, LOCK_UN);
        ::close(lock_fd);
        return 0;
    }

    // Block signals so signalfd receives them cleanly inside epoll
    sigset_t mask;
    sigemptyset(&mask);
    sigaddset(&mask, SIGUSR1);
    sigaddset(&mask, SIGTERM);
    sigaddset(&mask, SIGINT);
    sigaddset(&mask, SIGHUP);
    ::sigprocmask(SIG_BLOCK, &mask, nullptr);

    int sfd = ::signalfd(-1, &mask, SFD_NONBLOCK | SFD_CLOEXEC);
    int ifd = ::inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    int tfd_debounce = ::timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC);
    int tfd_recovery = ::timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC);
    int epfd = ::epoll_create1(EPOLL_CLOEXEC);

    if (sfd < 0 || ifd < 0 || tfd_debounce < 0 || tfd_recovery < 0 || epfd < 0) {
        if (sfd >= 0) ::close(sfd);
        if (ifd >= 0) ::close(ifd);
        if (tfd_debounce >= 0) ::close(tfd_debounce);
        if (tfd_recovery >= 0) ::close(tfd_recovery);
        if (epfd >= 0) ::close(epfd);
        cleanup_rundir(cfg, lock_fd);
        return 1;
    }

    // FBE-safe startup wait until Credential-Encrypted user storage (/sdcard/Android) unlocks
    if (!cfg.skip_fbe_wait) {
        for (int wait_i = 0; wait_i < 90 && !dir_exists("/sdcard/Android"); ++wait_i) {
            if (module_disabled_or_removed(cfg)) {
                ::close(epfd); ::close(tfd_recovery); ::close(tfd_debounce); ::close(ifd); ::close(sfd);
                cleanup_rundir(cfg, lock_fd);
                return 0;
            }
            struct signalfd_siginfo si {};
            if (::read(sfd, &si, sizeof(si)) == static_cast<ssize_t>(sizeof(si))) {
                if (si.ssi_signo == SIGTERM || si.ssi_signo == SIGINT) {
                    ::close(epfd); ::close(tfd_recovery); ::close(tfd_debounce); ::close(ifd); ::close(sfd);
                    cleanup_rundir(cfg, lock_fd);
                    return 0;
                }
            }
            ::sleep(2);
        }
    }

    const std::string target_ot = cfg.gms_files_root + "/fonts/opentype";
    WatchManager watcher(ifd, target_ot);
    if (!watcher.arm_hierarchy(cfg)) {
        set_oneshot_timer(tfd_recovery, watcher.next_recovery_backoff_ms());
    }

    uint64_t sync_count = 1;
    SyncStats last_stats = perform_sync(cfg);
    write_telemetry(cfg, last_stats, sync_count, watcher.healthy(), watcher.recoveries());

    auto add_epoll = [epfd](int fd) {
        struct epoll_event ev {};
        ev.events = EPOLLIN;
        ev.data.fd = fd;
        return ::epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev) == 0;
    };

    if (!add_epoll(sfd) || !add_epoll(ifd) || !add_epoll(tfd_debounce) || !add_epoll(tfd_recovery)) {
        ::close(epfd); ::close(tfd_recovery); ::close(tfd_debounce); ::close(ifd); ::close(sfd);
        cleanup_rundir(cfg, lock_fd);
        return 1;
    }

    constexpr int kMaxEvents = 16;
    struct epoll_event events[kMaxEvents];
    bool running = true;

    while (running) {
        int nfds = ::epoll_wait(epfd, events, kMaxEvents, -1);
        if (nfds < 0) {
            if (errno == EINTR) continue;
            break;
        }

        for (int i = 0; i < nfds; ++i) {
            const int fd = events[i].data.fd;

            if (fd == sfd) {
                struct signalfd_siginfo si {};
                while (::read(sfd, &si, sizeof(si)) == static_cast<ssize_t>(sizeof(si))) {
                    if (si.ssi_signo == SIGTERM || si.ssi_signo == SIGINT) {
                        running = false;
                        break;
                    }
                    if (si.ssi_signo == SIGUSR1 || si.ssi_signo == SIGHUP) {
                        if (module_disabled_or_removed(cfg)) {
                            running = false;
                            break;
                        }
                        if (watcher.arm_hierarchy(cfg)) {
                            set_oneshot_timer(tfd_recovery, 0);
                        } else {
                            set_oneshot_timer(tfd_recovery, watcher.next_recovery_backoff_ms());
                        }
                        last_stats = perform_sync(cfg);
                        ++sync_count;
                        write_telemetry(cfg, last_stats, sync_count, watcher.healthy(), watcher.recoveries());
                    }
                }
            } else if (fd == ifd) {
                alignas(struct inotify_event) char buf[4096];
                bool schedule_debounce = false;
                bool needs_rearm = false;
                for (;;) {
                    ssize_t len = ::read(ifd, buf, sizeof(buf));
                    if (len <= 0) break;
                    ssize_t off = 0;
                    while (off < len) {
                        const auto* ev = reinterpret_cast<const struct inotify_event*>(buf + off);
                        const std::string wpath = watcher.path_for_wd(ev->wd);
                        std::string_view ename = (ev->len > 0) ? std::string_view(ev->name) : std::string_view{};

                        if (ev->mask & IN_IGNORED) {
                            // Erase wd mapping strictly on IN_IGNORED (prevents double-remove / wd reuse race)
                            if (watcher.handle_ignored(ev->wd)) {
                                needs_rearm = true;
                            } else if (wpath != cfg.moddir) {
                                needs_rearm = true;
                            }
                        } else if (wpath == cfg.moddir) {
                            if (ename == "disable" || ename == "remove" || (ev->mask & IN_DELETE_SELF)) {
                                running = false;
                            }
                        } else {
                            if (ev->mask & (IN_DELETE_SELF | IN_MOVE_SELF)) {
                                if (wpath == target_ot) {
                                    watcher.mark_target_lost();
                                }
                                needs_rearm = true;
                            } else if (ev->mask & IN_CREATE) {
                                if ((ev->mask & IN_ISDIR) || ename == "files" ||
                                    ename == "fonts" || ename == "opentype") {
                                    needs_rearm = true;
                                    schedule_debounce = true;
                                }
                            } else if (ev->mask & (IN_CLOSE_WRITE | IN_MOVED_TO)) {
                                if (ends_with(ename, ".ttf")) {
                                    schedule_debounce = true;
                                }
                            }
                        }
                        off += static_cast<ssize_t>(sizeof(struct inotify_event) + ev->len);
                    }
                }
                if (running && needs_rearm) {
                    const bool was_healthy = watcher.healthy();
                    if (watcher.arm_hierarchy(cfg)) {
                        set_oneshot_timer(tfd_recovery, 0);
                        if (!was_healthy) {
                            schedule_debounce = true;
                        }
                    } else {
                        set_oneshot_timer(tfd_recovery, watcher.next_recovery_backoff_ms());
                        write_telemetry(cfg, last_stats, sync_count, false, watcher.recoveries());
                    }
                }
                if (running && schedule_debounce) {
                    set_oneshot_timer(tfd_debounce, kDebounceMs);
                }
            } else if (fd == tfd_debounce) {
                uint64_t exp = 0;
                ssize_t rn = ::read(tfd_debounce, &exp, sizeof(exp));
                if (rn != static_cast<ssize_t>(sizeof(exp))) {
                    continue;
                }
                if (module_disabled_or_removed(cfg)) {
                    running = false;
                    break;
                }
                if (watcher.arm_hierarchy(cfg)) {
                    set_oneshot_timer(tfd_recovery, 0);
                } else {
                    set_oneshot_timer(tfd_recovery, watcher.next_recovery_backoff_ms());
                }
                last_stats = perform_sync(cfg);
                ++sync_count;
                write_telemetry(cfg, last_stats, sync_count, watcher.healthy(), watcher.recoveries());
            } else if (fd == tfd_recovery) {
                uint64_t exp = 0;
                ssize_t rn = ::read(tfd_recovery, &exp, sizeof(exp));
                if (rn != static_cast<ssize_t>(sizeof(exp))) {
                    continue;
                }
                if (module_disabled_or_removed(cfg)) {
                    running = false;
                    break;
                }
                if (watcher.arm_hierarchy(cfg)) {
                    set_oneshot_timer(tfd_recovery, 0);
                    last_stats = perform_sync(cfg);
                    ++sync_count;
                    write_telemetry(cfg, last_stats, sync_count, true, watcher.recoveries());
                } else {
                    set_oneshot_timer(tfd_recovery, watcher.next_recovery_backoff_ms());
                    write_telemetry(cfg, last_stats, sync_count, false, watcher.recoveries());
                }
            }
        }
    }

    ::close(epfd);
    ::close(tfd_recovery);
    ::close(tfd_debounce);
    ::close(ifd);
    ::close(sfd);
    cleanup_rundir(cfg, lock_fd);
    return 0;
}
