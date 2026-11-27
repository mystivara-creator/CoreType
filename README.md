# CoreType

**Dual-Optical San Francisco Pro typography engine for HyperOS & Android.**  
Part of the **Mystivara Ecosystem** (`CoreFlow` · `CoreSurface` · `CoreType`) — **100% Standalone, Zero LSPosed**.

---

## Why Raw SF Pro Looks "Dead & Wide" on Android

Installing raw Apple `SF-Pro.ttf` on Android/HyperOS always feels lifeless and bloats UI layouts for four real typographic reasons:

1. **Android Ignores Apple's `trak` Table:** Apple's CoreText dynamically tightens San Francisco's letter-spacing using an AAT `trak` table (`-40` to `-52` UPM at 16–17pt UI Text). Android's HarfBuzz/Minikin **completely ignores `trak`**, making every line render ~12–15% too loose and bloated.
2. **Wrong Default Optical Size (`opsz`):** Raw `SF-Pro.ttf` defaults to `opsz=28.0` (Display) rather than `17.0` (Text), flattening header-vs-body hierarchy.
3. **Upright vs Italic Width Mismatch:** Apple's `SF-Pro-Italic.ttf` lacks a `wdth` axis, so width-hacking only the upright font leaves italics visibly wider than upright text.
4. **40 MB Apple PUA Bloat:** Raw `SF-Pro.ttf` + `SF-Pro-Italic.ttf` pack ~71,000 glyphs (mostly Apple-only SF Symbols in Private Use Area) that waste RAM and slow Zygote boot.

## How CoreType Achieves True Native Apple CoreText Parity

- **Dual-Optical Masters + Continuous Optical Sizing (`opsz` 12–36):**
  - `CoreType-SFPro-Text.ttf` & `CoreType-SFPro-Text-Italic.ttf` (`wght 350–500`): Pure **SF Pro Text** (`opsz=17`) with Apple's **−46 UPM** iOS Text tracking baked non-destructively into OpenType `GPOS kern` (`SinglePos`, applied right after Apple's native `PairPos` kerning).
  - `CoreType-SFPro-Display.ttf` & `CoreType-SFPro-Display-Italic.ttf` (`wght 100–300` Clocks/Hero, `wght 600–950` Headers/Titles): Pure **SF Pro Display** (`opsz=28`) with Apple's **−26 UPM** Display tracking and pure `0` UPM tabular digit spacing.
  - **`CoreType-SFPro-Flex.ttf` (`RobotoFlex-Regular.ttf`, continuous `opsz` 12–36):** Preserves Apple's continuous optical sizing axis (`opsz` `12..36`, `wght` `100..950`, `wdth` `75..100`) with balanced **−36 UPM** GPOS tracking so Jetpack Compose & Material 3 apps (Play Store, Gmail, Settings) smoothly shift letter proportions by text size like Apple CoreText.
  - **Vertical Metrics Parity (`1968 / −492`, exact 4:1 ratio):** Matches HyperOS `MiSansTCVF` & `NotoSansCJK` line-height (`1.201× UPM`, `USE_TYPO_METRICS` enabled, `lineGap=0`) so mixed Latin + CJK text, notification badges, and centered `09:41` clocks (`calt`, `tnum`) align with zero vertical clipping.
  - **Dynamic Weight Curve Engine (ROM-Aware + WebUI Live Preview):** Automatically detects HyperOS `mipro` vs linear AOSP curves from stock XMLs and computes a monotonic, tapered weight ramp — customizable anytime in WebUI via **Weight Bias** (`-60` to `+80`) and **Header Contrast** (`Soft` / `Balanced` / `Apple Native`) with real-time live specimen preview.
  - **Universal HyperOS & GMS Ecosystem App Fonts:** Routes explicit HyperOS & Google XML families (`mipro`, `misans`, `miui`, `google-sans`, `google-sans-text`, `inter`) to SF Pro, and non-destructively read-only bind-mounts GMS `FontsProvider` caches (`Google_Sans*`, `Product_Sans*`, `Roboto*`) used by **Play Store, Gmail, Google Maps, Google Photos & Gboard** with true Regular (400), Medium (500), Semibold (600), and Italic matching (toggleable ON/OFF in WebUI).
  - **Universal HyperOS 1 / 2 / 3 / 4 MiSans + Font Weight Slider Support:** Automatically detects a safe separate CJK fallback (`MiSansTCVF.ttf`, `MiSansL3.otf`, or `NotoSansCJK-Regular.ttc`) so BOTH **`Default`** (full Dual-Optical + Dynamic Curve) and **`MiSans`** (with HyperOS's live Font Weight slider) render SF Pro with **zero CJK tofu boxes**.
  - **Apple iOS 26.4 Color Emoji Engine (Full Edition):** Android-native CBDT/CBLC Apple Emoji with non-destructive read-only bind-mounting over BOTH Android `/data/fonts/files/` AND Google Play Services `FontsProvider` / Jetpack `EmojiCompat` caches (`/data/data/com.google.android.gms/files/fonts/opentype/*Emoji*.ttf`) — plus an instant **WebUI ON/OFF toggle**.
  - **Two Automatic CI Editions:**
    - **`CoreType-v1.2.0-Lite.zip`** (~2.6 MB) — Dual-Optical SF Pro + Continuous `opsz` Flex + Dynamic Curve + Native C++20 `coretype-watchd` + Universal GMS Fonts + MiSans Slider
    - **`CoreType-v1.2.0-Full.zip`** (~36 MB) — Everything in Lite + Apple iOS 26.4 Emoji
- **Native C++20 Event-Driven Daemon (`native/coretype-watchd.cpp`):**
  - **Zero-Polling `epoll` + `inotify` + `timerfd` + `signalfd`:** Sleeps completely in `epoll_wait(..., -1)` with **0% idle CPU**, **0 wakelock**, and **< 300 KB VmRSS** (`aarch64` static-libstdc++, stripped).
  - **100% Orthogonal Runtime Namespace (`/dev/.coretype/`):** Uses atomic `flock(2)` (`watchd.lock`), `watchd.pid`, and `telemetry.prop` inside global mount namespace (`/proc/1/ns/mnt`) — never touches `/sys` or `/proc` hardware tuning (100% orthogonal to `CoreFlow-Engine`).
  - **Direct `mount(2)` Syscall & 250 ms Batch Debounce:** Watches `/data/data/com.google.android.gms` → `files` → `fonts` → `opentype` (auto-recovers even after GMS *Clear Data*), coalesces downloads via 250 ms one-shot `timerfd`, and checks `/proc/self/mountinfo` for 100% idempotent read-only bind-mounts.
  - **Instant `SIGUSR1` On-Demand Sync & Live Telemetry:** `action.sh` and WebUI **Sync Now** dispatch `SIGUSR1` (< 5 ms), updating `/dev/.coretype/telemetry.prop` (`daemon_mode`, `daemon_pid`, `daemon_rss_kb`, `gms_latin_mounted`, `gms_emoji_mounted`, `sync_count`, `last_sync_latency_us`, `active_text_tracking_upm`, `active_display_tracking_upm`) displayed live in WebUI's **Live Engine Telemetry** card.
- **Zero-Bootloop, FBE-Safe & KernelSU-Umount-Safe Architecture:**
  - **100% Stock-Slot Mapping (Zero Non-Stock Filenames in XML):** Maps all SF Pro masters strictly onto existing stock `/system/fonts/` slots (`Roboto-Regular.ttf`, `RobotoStatic-Regular.ttf`, `RobotoFlex-Regular.ttf`, etc.) — eliminating `minikin::Font::prepareFont` `SIGSEGV` crashes in umounted banking apps.
  - **KernelSU / KernelSU-Next `Unmount modules` Note:** Keep global `Umount modules` **OFF** (with `Superuser` **OFF**) for everyday apps where you want SF Pro & Apple iOS Emoji, and enable `Custom → Umount modules = ON` specifically for banking / e-wallet apps.
  - **Automatic ROM / HyperOS OTA Resync & Self-Healing Bootloop Guard:** Detects `ro.build.fingerprint` changes pre-Zygote and auto-disables after 2 failed boots.
- **WebUI Optical Profile, Dynamic Curve & Live Telemetry (KSU / APatch / MMRL):**
  - `iOS Optical Dynamic` *(Recommended)* — pure shapes (`wdth 96.5 / 97.0`) + Apple GPOS `trak`
  - `iOS Native Pro` — 100% uncompressed Apple width (`wdth 100.0`) + Apple GPOS `trak`
  - `iOS Compact Crisp` — tighter optical width (`wdth 91.5 / 92.0`) for ultra-dense UI

---

## Building Locally

```sh
python3 scripts/build_fonts.py --out-dir fonts
sh tests/run_tests.sh
```

> **Note on Licensing:** CoreType does not redistribute Apple's proprietary font binaries in Git. The automated build pipeline fetches and processes Apple's official public `SF-Pro.dmg` directly at build time.
