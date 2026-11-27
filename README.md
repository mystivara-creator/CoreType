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
  - **HyperOS `mipro` Weight Calibration:** Compensates for HyperOS's +100/+200 `mipro-demibold` (`700 → wght 590`) and `mipro-semibold` (`800 → wght 680`) weight offsets so section headers look crisp and refined like native iOS.
  - **100% Pure Apple Glyph Shapes & Ultra-Lean `gvar`:** Prunes unused Apple PUA symbols, desktop-only stylistic sets, and unused `wdth < 75 / > 100` extremes — shrinking `gvar` by **~75%** and cutting per-app `mmap` RAM while preserving **0-unit identical HarfBuzz shaping**, Apple's centered `09:41` clock colon (`calt`), and tabular numerals (`tnum`).
- **Zero-Bootloop, Zero-Daemon & KernelSU-Umount-Safe Architecture:**
  - **100% Stock-Slot Mapping (Zero Non-Stock Filenames in XML):** Maps Dual-Optical SF Pro masters strictly onto existing stock `/system/fonts/` slots (`Roboto-Regular.ttf`, `RobotoStatic-Regular.ttf`, `RobotoFlex-Regular.ttf`, etc.). Even when KernelSU `umount modules` hides mounts inside Gboard or banking apps, every referenced stock filename still exists on disk — eliminating `minikin::Font::prepareFont` `SIGSEGV` crashes completely.
  - **Automatic ROM / HyperOS OTA Resync:** Detects `ro.build.fingerprint` changes in `post-fs-data` (before mounts & Zygote) and automatically refreshes stock XML snapshots, stock slots, and patches — zero re-flashing needed after OTA updates.
  - **Self-Healing Bootloop Guard:** Automatically disables the module (`disable` flag) if 2 consecutive boots ever fail to reach `sys.boot_completed=1`.
  - **Zero Background Daemon (0 KB Persistent RAM):** `service.sh` verifies health, writes `state.prop` in one atomic pass, trims logs `< 16 KB`, and exits immediately.
  - **Shared-Inode Hardlinks & 100% Fallback Preservation:** Uses real `0644` hardlinks (no symlinks) to share Linux kernel RAM page cache; never touches `MiSansVF.ttf` (CJK), Arabic, Indic, `MiClock*.otf`, or `NotoColorEmoji.ttf`.
- **WebUI Optical Profile Switcher (KSU / APatch / MMRL):**
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
