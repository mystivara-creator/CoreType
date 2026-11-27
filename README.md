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

## How CoreType Achieves True Native iOS Typography

- **Dual Optical Variable Masters (`opsz=17` Text & `opsz=28` Display):**
  - `CoreType-SFPro-Text.ttf` & `CoreType-SFPro-Text-Italic.ttf` (`wght 350–500`): Pure **SF Pro Text** (`opsz=17`) with Apple's **−46 UPM** iOS Text tracking baked non-destructively into OpenType `GPOS kern` (`SinglePos`, applied right after Apple's native `PairPos` kerning).
  - `CoreType-SFPro-Display.ttf` & `CoreType-SFPro-Display-Italic.ttf` (`wght 100–300` Clocks/Hero, `wght 600–950` Headers/Titles): Pure **SF Pro Display** (`opsz=28`) with Apple's **−26 UPM** Display tracking baked into `GPOS kern`.
  - **Dynamic Weight Curve Engine (ROM-Aware + WebUI Live Preview):** Automatically detects HyperOS `mipro` vs linear AOSP curves from stock XMLs and computes a monotonic, tapered weight ramp — customizable anytime in WebUI via **Weight Bias** (`-60` to `+80`) and **Header Contrast** (`Soft` / `Balanced` / `Apple Native`) with real-time live specimen preview.
  - **Universal HyperOS & GMS Ecosystem App Fonts:** Routes explicit HyperOS & Google XML families (`mipro`, `misans`, `miui`, `google-sans`, `google-sans-text`, `inter`) to Dual-Optical SF Pro, and non-destructively read-only bind-mounts GMS `FontsProvider` caches (`Google_Sans*`, `Product_Sans*`, `Roboto*`) used by **Play Store, Gmail, Google Maps, Google Photos & Gboard** with true Regular (400), Medium (500), Semibold (600), and Italic matching (toggleable ON/OFF in WebUI).
  - **100% Pure Apple Glyph Shapes & Ultra-Lean `gvar`:** Prunes unused Apple PUA symbols, desktop-only stylistic sets, and unused `wdth < 75 / > 100` extremes — shrinking `gvar` by **~75%** and cutting per-app `mmap` RAM while preserving all non-PUA Unicode glyphs (including Phonetic Extensions superscripts), **0-unit identical HarfBuzz shaping**, Apple's centered `09:41` clock colon (`calt`), and tabular numerals (`tnum`).
  - **Universal HyperOS 1 / 2 / 3 / 4 MiSans + Font Weight Slider Support:** Automatically detects a safe separate CJK fallback (`MiSansTCVF.ttf`, `MiSansL3.otf`, or `NotoSansCJK-Regular.ttc`) so BOTH **`Default`** (full Dual-Optical Display + Text) and **`MiSans`** (with HyperOS's live Font Weight slider) render SF Pro with **zero CJK tofu boxes**.
  - **Apple iOS 26.4 Color Emoji Engine (Full Edition):** Android-native CBDT/CBLC Apple Emoji with non-destructive read-only bind-mounting over BOTH Android `/data/fonts/files/` AND Google Play Services `FontsProvider` / Jetpack `EmojiCompat` caches (`/data/data/com.google.android.gms/files/fonts/opentype/*Emoji*.ttf`) — beats `Noto_COLR_Emoji_Compat` overrides without breaking Google Fonts or modifying `/data` on disk — plus an instant **WebUI ON/OFF toggle**.
  - **Two Automatic CI Editions:**
    - **`CoreType-v1.2.0-Lite.zip`** (~2.1 MB) — Dual-Optical SF Pro + Dynamic Weight Curve + Universal GMS Fonts + MiSans Slider
    - **`CoreType-v1.2.0-Full.zip`** (~35 MB) — Everything in Lite + Apple iOS 26.4 Emoji
- **Zero-Bootloop, FBE-Safe & KernelSU-Umount-Safe Architecture:**
  - **100% Stock-Slot Mapping (Zero Non-Stock Filenames in XML):** Maps Dual-Optical SF Pro masters strictly onto existing stock `/system/fonts/` slots (`Roboto-Regular.ttf`, `RobotoStatic-Regular.ttf`, `RobotoFlex-Regular.ttf`, etc.). Even when KernelSU `Unmount modules` hides overlays inside banking apps, every referenced stock filename still exists on disk — eliminating `minikin::Font::prepareFont` `SIGSEGV` crashes completely.
  - **KernelSU / KernelSU-Next `Unmount modules` Note:** Apps with `Unmount modules` enabled are intentionally isolated by KernelSU to stock `/system/fonts/` (Roboto + Google Noto Emoji). Keep `Unmount modules` **ON** for banking/root-detecting apps, and turn it **OFF** for everyday apps where you want SF Pro & Apple iOS Emoji (such as **Gboard**, **Notes**, **WhatsApp**, and **Android System WebView**).
  - **FBE-Safe Micro GMS Watcher & Zero-Reboot `action.sh`:** Waits cleanly for Android File-Based Encryption unlock (`/sdcard/Android`) before binding `/data/data/com.google.android.gms/files/fonts/opentype/`, then runs a single-instance sleep-only watcher (`0` wakelock, `< 1 MB` RAM, 60s interval) to catch any newly downloaded GMS fonts/emojis automatically — plus a 1-tap **Sync Now** button in WebUI & `action.sh` for instant on-demand sync with zero reboot.
  - **Automatic ROM / HyperOS OTA Resync:** Detects `ro.build.fingerprint` changes in `post-fs-data` (before mounts & Zygote) and automatically refreshes stock XML snapshots, stock slots, and patches — zero re-flashing needed after OTA updates.
  - **Self-Healing Bootloop Guard:** Automatically disables the module (`disable` flag) if 2 consecutive boots ever fail to reach `sys.boot_completed=1`.
  - **Shared-Inode Hardlinks & 100% Fallback Preservation:** Uses real `0644` hardlinks (no symlinks) to share Linux kernel RAM page cache; preserves CJK (via detected fallback), Arabic, Indic, and `MiClock*.otf`.
- **WebUI Optical Profile & Dynamic Curve Controls (KSU / APatch / MMRL):**
  - `iOS Optical Dynamic` *(Recommended)* — pure shapes (`wdth 96.5 / 97.0`) + Apple GPOS `trak`
  - `iOS Native Pro` — 100% uncompressed Apple width (`wdth 100.0`) + Apple GPOS `trak`
  - `iOS Compact Crisp` — tighter optical width (`wdth 91.5 / 92.0`) for ultra-dense UI

---

## Building Locally

```sh
python3 scripts/build_fonts.py --out-dir system/fonts
sh tests/run_tests.sh
```

> **Note on Licensing:** CoreType does not redistribute Apple's proprietary font binaries in Git. The automated build pipeline fetches and processes Apple's official public `SF-Pro.dmg` directly at build time.
