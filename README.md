# CoreType

**Optical-aware San Francisco Pro typography engine for HyperOS & Android.**  
Part of the **Mystivara Ecosystem** (`CoreFlow` · `CoreSurface` · `CoreType`) — **100% Standalone, Zero LSPosed**.

---

## Why Raw SF Pro Looks "Flat & Wide" on Android

Installing raw Apple `SF-Pro.ttf` on Android/HyperOS usually feels lifeless and bloats UI layouts for three real typographic reasons:

1. **Wrong Default Optical Size (`opsz`):** Apple's `SF-Pro.ttf` defaults to `opsz=28.0` (Display) instead of `17.0` (Text), making headers and body text look flat and uniform.
2. **Wider Advance Widths:** At `wdth=100`, SF Pro Text averages **~15% wider** than Android Roboto / HyperOS MiSans — causing Status Bar, Quick Settings, and button labels to wrap or truncate (`...`).
3. **20 MB Apple PUA Bloat:** Raw `SF-Pro.ttf` ships ~35,900 glyphs (mostly Apple-only SF Symbols in Private Use Area) that waste RAM and slow down Zygote font loading.

## How CoreType Solves It

- **Progressive Optical Size (`opsz`) Curve:** Dynamically maps system weights in `font_fallback.xml` & `fonts.xml`:
  - **Body / Chat / Notifications (`wght 350–400`):** `opsz=17.0` (**SF Pro Text** — open, crisp, effortless reading)
  - **UI Labels / Tabs (`wght 500`):** `opsz=20.0` (smooth Text → Display transition)
  - **Headers / Settings Titles / App Bars (`wght 600–700`):** `opsz=26.0–28.0` (**SF Pro Display** — tighter tracking, unmistakable iOS punch)
  - **Lockscreen Clock / Hero Display (`wght 100–300`, `800–950`):** `opsz=26.0–28.0` (**SF Pro Display**)
- **Apple-Native Optical Width Calibration (`wdth`):** Uses SF Pro's own hand-drawn `wdth` variable axis (never artificial horizontal stretching) calibrated to Android/HyperOS UI grids (`91 / 89` default).
- **Android Baseline Metrics Alignment:** Calibrates `hhea` & `OS/2` (`1900 / -500`) so icons, badges, and status bar pills align pixel-accurately.
- **Lean & Fast:** Strips Apple-only PUA SF Symbols during CI build (`~20 MB → ~1.5 MB`), keeping full Latin, Extended Latin, Vietnamese, Greek, Cyrillic, Math, Currency, Punctuation, and OpenType features.
- **Full HyperOS 2/3/4 & AOSP Compatibility:** Dynamically patches `font_fallback.xml` & `fonts.xml` at flash time while preserving **100% of device fallbacks** (Arabic, CJK, Devanagari, Emoji, Symbols).
- **WebUI Optical Profile Switcher (KSU / APatch / MMRL):**
  - `iOS Optical Dynamic` *(Recommended)*
  - `iOS Native Pro`
  - `iOS Compact Crisp`

---

## Building Locally

```sh
python3 scripts/build_fonts.py --out-dir system/fonts
sh tests/run_tests.sh
```

> **Note on Licensing:** CoreType does not redistribute Apple's proprietary font binaries in Git. The automated build pipeline fetches and processes Apple's official public `SF-Pro.dmg` directly at build time.
