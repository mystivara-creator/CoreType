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
  - **100% Pure Apple Glyph Shapes:** `glyf`, `gvar`, `HVAR`, and accented diacritics remain untouched; Apple's iconic centered clock colon (`09:41` via `calt`) and tabular numerals (`tnum`) work natively.
  - **100% Upright ↔ Italic Width Match** and full **HyperOS Variable Font Weight Slider** compatibility (`wght 1..1000`).
- **Zero-Bootloop Safety Architecture:**
  - **Self-Healing Bootloop Guard:** Automatically disables the module (`disable` flag) if 2 consecutive boots ever fail to reach `sys.boot_completed=1`.
  - **Strict Structural XML Validator:** Verifies balanced `<familyset>`, `<family>`, `<font>` tags and font binary existence before committing any XML.
  - **Schema-Faithful Patching:** Preserves `postScriptName` in `font_fallback.xml` (Android 14–16 / HyperOS 3) while cleanly omitting it in legacy `fonts.xml` (`version="22"`).
  - **SELinux-Safe Copies & 100% Fallback Preservation:** Uses real `0644` file copies (no symlinks) for `Roboto-Regular.ttf` & `MiSansLatinVF.ttf`; never touches `MiSansVF.ttf` (CJK), Arabic, Indic, `MiClock*.otf`, or `NotoColorEmoji.ttf`.
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
