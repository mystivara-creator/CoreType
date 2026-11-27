# CoreType

**Dual-Optical San Francisco Pro typography engine for HyperOS & Android.**  
Part of the **Mystivara Ecosystem** (`CoreFlow` · `CoreSurface` · `CoreType`) — **100% Standalone**.

---

## Why Raw SF Pro Looks "Dead & Wide" on Android

Installing raw Apple `SF-Pro.ttf` on Android/HyperOS always feels lifeless and bloats UI layouts for four real typographic reasons:

1. **Android Ignores Apple's `trak` Table:** Apple's CoreText dynamically tightens San Francisco's letter-spacing using an AAT `trak` table (`-40` to `-52` UPM at 16–17pt UI Text). Android's HarfBuzz/Minikin **completely ignores `trak`**, making every line render ~12–15% too loose and bloated.
2. **Wrong Default Optical Size (`opsz`):** Raw `SF-Pro.ttf` defaults to `opsz=28.0` (Display) rather than `17.0` (Text), flattening header-vs-body hierarchy.
3. **Upright vs Italic Width Mismatch:** Apple's `SF-Pro-Italic.ttf` lacks a `wdth` axis, so width-hacking only the upright font leaves italics visibly wider than upright text.
4. **40 MB Apple PUA Bloat:** Raw `SF-Pro.ttf` + `SF-Pro-Italic.ttf` pack ~71,000 glyphs (mostly Apple-only SF Symbols in Private Use Area) that waste RAM and slow Zygote boot.

## How CoreType Achieves True Native Apple CoreText Parity

- **Dual-Optical Masters + Dynamic `opsz` GPOS `FeatureVariations` (`opsz` 17–28):**
  - `CoreType-SFPro-Text.ttf` & `CoreType-SFPro-Text-Italic.ttf` (`wght 350–500`): Pure **SF Pro Text** (`opsz=17`) with Apple's **−46 UPM** iOS Text tracking baked non-destructively into OpenType `GPOS kern` (`SinglePos`, applied right after Apple's native `PairPos` kerning).
  - `CoreType-SFPro-Display.ttf` & `CoreType-SFPro-Display-Italic.ttf` (`wght 100–300` Clocks/Hero, `wght 600–950` Headers/Titles): Pure **SF Pro Display** (`opsz=28`) with Apple's **−26 UPM** Display tracking and pure `0` UPM tabular digit spacing.
  - **`CoreType-SFPro-Flex.ttf` (`RobotoFlex-Regular.ttf`, continuous `opsz` + GPOS `FeatureVariations`):** Preserves Apple's continuous optical sizing axis (`opsz` `17..28`, `wght` `100..950`, `wdth` `75..100`) and dynamically switches tracking from **−46 UPM** (Text, `opsz < 22`) to **−26 UPM** (Display, `opsz >= 22`) inside Android HarfBuzz/Minikin so Jetpack Compose & Material 3 apps shift both letter proportions and tracking like Apple CoreText.
  - **Vertical Metrics Parity (`1968 / −492`, exact 4:1 ratio):** Matches HyperOS `MiSansTCVF` & `NotoSansCJK` line-height (`1.201× UPM`, `USE_TYPO_METRICS` enabled, `lineGap=0`) so mixed Latin + CJK text, notification badges, and centered `09:41` clocks (`calt`, `tnum`) align with zero vertical clipping.
  - **Dynamic Weight Curve Engine (ROM-Aware + WebUI Live Preview):** Automatically detects HyperOS `mipro` vs linear AOSP curves from stock XMLs and computes a monotonic, tapered weight ramp — customizable anytime in WebUI via **Quick Presets**, **Weight Bias** (`-60` to `+80`), and **Header Contrast** (`Soft` / `Balanced` / `Apple Native`) with real-time live specimen preview.
  - **Universal HyperOS & GMS Ecosystem App Fonts:** Routes explicit HyperOS & Google XML families (`mipro`, `misans`, `miui`, `google-sans`, `google-sans-text`, `inter`) to SF Pro, and non-destructively read-only bind-mounts GMS `FontsProvider` caches (`Google_Sans*`, `Google_Sans_Flex`, `Product_Sans*`, `Roboto*`, excluding `Google_Sans_Code` monospace) using Text Medium (`opsz=17`), Semi-Display Bold (`opsz=24`), Flex, and Italic matching — with **Instant Live-Apply** (`SIGUSR1`, 0 reboot) in WebUI.
  - **Universal HyperOS 1 / 2 / 3 / 4 MiSans + Font Weight Slider Support:** Automatically detects a safe separate CJK fallback (`MiSansTCVF.ttf`, `MiSansL3.otf`, or `NotoSansCJK-Regular.ttc`) so BOTH **`Default`** (full Dual-Optical + Dynamic Curve) and **`MiSans`** (with HyperOS's live Font Weight slider) render SF Pro with **zero CJK tofu boxes**.
  - **Apple iOS 26.4 Color Emoji Engine (Full Edition):** Android-native CBDT/CBLC Apple Emoji with non-destructive read-only bind-mounting over BOTH Android `/data/fonts/files/` AND Google Play Services `FontsProvider` / Jetpack `EmojiCompat` caches (`/data/data/com.google.android.gms/files/fonts/opentype/*Emoji*.ttf`) — plus an instant **WebUI ON/OFF toggle**.
  - **Two Automatic CI Editions:**
    - **`CoreType-v1.2.1-Lite.zip`** (~2.8 MB) — Dual-Optical SF Pro + Dynamic `opsz` Flex (`FeatureVariations`) + Dynamic Curve + Native C++20 `coretype-watchd` + Universal GMS Fonts + MiSans Slider
    - **`CoreType-v1.2.1-Full.zip`** (~36 MB) — Everything in Lite + Apple iOS 26.4 Emoji
- **Native C++20 Event-Driven Daemon (`native/coretype-watchd.cpp`):**
  - **Zero-Polling `epoll` + `inotify` + Dual `timerfd` + `signalfd`:** Sleeps completely in `epoll_wait(..., -1)` with **0% idle CPU**, **0 wakelock**, and **< 300 KB private RAM** (`aarch64` static-libstdc++, stripped).
  - **100% Orthogonal Runtime Namespace (`/dev/.coretype/`):** Uses atomic `flock(2)` (`watchd.lock`), `watchd.pid`, and `telemetry.prop` inside global mount namespace (`/proc/1/ns/mnt`) — never touches `/sys` or `/proc` hardware tuning (100% orthogonal to `CoreFlow-Engine`).
  - **Self-Healing `inotify` & Live `umount2`:** Cleans watch descriptors strictly on `IN_IGNORED` (zero `wd` reuse races), recovers automatically from HyperOS Security Cleaner or GMS *Clear Data* via bounded backoff (`1s → 3s → 10s`), coalesces `.ttf` writes with 250 ms debounce, checks `/proc/self/mountinfo` for idempotent read-only `mount(2)`, and detaches disabled GMS mounts live via `umount2(MNT_DETACH)` when toggled OFF in WebUI.
  - **Instant `SIGUSR1` Sync, Live Telemetry & One-Tap Diagnostic (`action.sh --diag`):** Dispatches `SIGUSR1` (< 5 ms), reports `watch_health`, `watch_recoveries`, `daemon_private_kb` & `daemon_rss_kb`, mount counts & sync latency in WebUI, and exports a read-only diagnostic bundle to `/sdcard/Download/coretype-diag.txt`.
- **HyperOS 1–4 (Android 12–17) ARM64 Exclusive & KernelSU-Umount-Safe Architecture:**
  - **Exclusive ARM64 HyperOS Platform Gate & Lockscreen Clock Parity:** Supports **HyperOS 1 / 2 / 3 / 4** across **Android 12–17** (including HyperOS 4 on Android 17), preserves stock `MiClock*.otf`, and verifies `tnum` + `calt` (`09:41`) clock alignment with zero clipping.
  - **100% Stock-Slot Mapping (Zero Non-Stock Filenames in XML):** Maps all SF Pro masters strictly onto existing stock `/system/fonts/` slots (`Roboto-Regular.ttf`, `RobotoStatic-Regular.ttf`, `RobotoFlex-Regular.ttf`, etc.) — eliminating `minikin::Font::prepareFont` `SIGSEGV` crashes in umounted banking apps.
  - **KernelSU / KernelSU-Next `Unmount modules` Note:** Keep global `Umount modules` **OFF** (with `Superuser` **OFF**) for everyday apps where you want SF Pro & Apple iOS Emoji, and enable `Custom → Umount modules = ON` specifically for banking / e-wallet apps.
  - **Automatic ROM / HyperOS OTA Resync & Self-Healing Bootloop Guard:** Detects `ro.build.fingerprint` changes pre-Zygote and auto-disables after 2 failed boots.
- **iOS 27 Liquid Glass & Settings Native 3-Tab WebUI (KSU / APatch / MMRL):**
  - Auto Light & Dark (`prefers-color-scheme`) with layered Liquid Glass lensing, interactive pointer inner-glow, **3-Tab Bottom Dock** (`Typography` · `Ecosystem` · `Engine`), **3 Quick Curve Presets**, **Instant Live-Apply** GMS toggle, and **Tinted Solid Surfaces** accessibility mode (`prefers-reduced-transparency`).
  - `iOS Optical Dynamic` *(Recommended)* — pure shapes (`wdth 96.5 / 97.0`) + Apple GPOS `trak`
  - `iOS Native Pro` — 100% uncompressed Apple width (`wdth 100.0`) + Apple GPOS `trak`
  - `iOS Compact Crisp` — tighter optical width (`wdth 91.5 / 92.0`) for ultra-dense UI

---

## Building Locally

```sh
python3 scripts/build_fonts.py --out-dir fonts
sh tests/run_tests.sh
```

---

## License & Legal Disclaimer

- **Source Code (`MIT License`):** All original CoreType source code — including the C++20 `coretype-watchd` daemon, POSIX shell engine, Python optical build pipeline, WebUI, and automated test suite — is licensed under the [MIT License](LICENSE).
- **No Proprietary Fonts in Git:** CoreType does **not** store or redistribute Apple's proprietary font binaries inside this Git repository. The build pipeline fetches public upstream packages strictly at build time.
- **Trademarks & Third-Party Assets:** CoreType is an **independent, non-commercial** community project and is **not affiliated with, endorsed by, or sponsored by Apple Inc., Xiaomi Corp., or Google LLC**. *San Francisco (SF Pro)*, *CoreText*, and *Apple Color Emoji* are trademarks/copyrighted assets of **Apple Inc.**; *HyperOS* and *MiSans* are trademarks of **Xiaomi Corp.**; *Android* and *Google Sans* are trademarks of **Google LLC**.
- **Personal / Educational Use & Takedown Compliance:** Any processed font outputs are intended strictly for personal, non-commercial customization and educational typography research. If you are a rights holder and believe any release asset should be removed, please open an issue or contact the maintainer and it will be taken down promptly.

