(function () {
  "use strict";

  const STATE_FILE = "/data/adb/coretype/state.prop";
  const CONF_FILE = "/data/adb/coretype/config.conf";
  const TELEM_FILE = "/dev/.coretype/telemetry.prop";
  const ACTION_SCRIPT = "/data/adb/modules/coretype/action.sh";
  const VALID_CONTRASTS = ["soft", "balanced", "apple_native"];
  const VALID_PROFILES = ["dynamic_optical", "native_pro", "compact_crisp"];
  const CONF_KEY_RE = /^[a-z0-9_]+$/;
  const CONF_VAL_RE = /^-?[A-Za-z0-9_.-]+$/;
  const TAB_TITLES = {
    typography: "CoreType",
    ecosystem: "Ecosystem",
    engine: "Engine",
  };

  let appliedProfile = "dynamic_optical";
  let wantedProfile = "dynamic_optical";
  let appliedBias = 0;
  let wantedBias = 0;
  let appliedContrast = "balanced";
  let wantedContrast = "balanced";
  let romCurve = "hyperos_mipro";
  let appliedEmoji = true;
  let wantedEmoji = true;
  let emojiAvailable = false;
  let installPendingReboot = false;
  let toastTimer = null;
  let confWriteChain = Promise.resolve();
  let suppressTabClickUntil = 0;

  function execShell(cmd) {
    return new Promise((resolve) => {
      if (typeof ksu !== "undefined" && typeof ksu.exec === "function") {
        const cbName = "_ct_cb_" + Math.random().toString(36).slice(2);
        window[cbName] = (code, stdout, stderr) => {
          delete window[cbName];
          resolve({ code, out: stdout || "", err: stderr || "" });
        };
        try {
          ksu.exec(cmd, "{}", cbName);
        } catch (e) {
          delete window[cbName];
          resolve({ code: 1, out: "", err: String(e) });
        }
        return;
      }
      resolve({ code: -1, out: "", err: "WebUI preview mode" });
    });
  }

  function parseProps(text) {
    const map = {};
    for (const line of (text || "").split(/\r?\n/)) {
      const idx = line.indexOf("=");
      if (idx > 0) {
        map[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
      }
    }
    return map;
  }

  function clampBias(v) {
    const n = parseInt(v, 10);
    if (Number.isNaN(n)) return 0;
    return Math.max(-60, Math.min(80, Math.round(n / 5) * 5));
  }

  // Exact 1:1 mathematical parity with ct_calc_wght() in lib/font_xml.sh (POSIX integer truncation)
  function calcWght(slot, curve, bias, contrast) {
    const isAosp = curve === "aosp_linear";
    const b = Math.max(-60, Math.min(80, parseInt(bias, 10) || 0));

    const aospBase = {
      100: 160, 200: 240, 300: 320, 350: 380, 400: 400,
      500: 500, 600: 570, 700: 650, 800: 740, 900: 830, 950: 900,
    };
    const hosBase = {
      100: 170, 200: 250, 300: 340, 350: 400, 400: 400,
      500: 485, 600: 535, 700: 550, 800: 650, 900: 740, 950: 830,
    };
    const base = (isAosp ? aospBase : hosBase)[slot] ?? slot;

    let cdelta = 0;
    if (contrast === "soft") {
      if (slot === 600) cdelta = -25;
      else if (slot === 700) cdelta = -30;
      else if (slot === 800) cdelta = -35;
      else if (slot === 900) cdelta = -30;
    } else if (contrast === "apple_native") {
      if (slot === 600) cdelta = 25;
      else if (slot === 700) cdelta = 45;
      else if (slot === 800) cdelta = 45;
      else if (slot === 900) cdelta = 40;
    }

    let bdelta;
    if (slot === 100 || slot === 200 || slot === 900 || slot === 950) {
      bdelta = Math.trunc(b / 2);
    } else if (slot === 300 || slot === 800) {
      bdelta = Math.trunc((b * 3) / 4);
    } else {
      bdelta = b;
    }

    return Math.max(100, Math.min(950, base + cdelta + bdelta));
  }

  function computeCurveWeights(curve, bias, contrast) {
    const b = clampBias(bias);
    const isAosp = curve === "aosp_linear";
    // On HyperOS, mipro-demibold maps to slot 700 (550) and mipro-semibold maps to slot 800 (650);
    // on AOSP, standard UI headers/bold map to slots 600 (570) and 700 (650).
    return {
      w400: calcWght(400, curve, b, contrast),
      w500: calcWght(500, curve, b, contrast),
      w600: calcWght(isAosp ? 600 : 700, curve, b, contrast),
      w700: calcWght(isAosp ? 700 : 800, curve, b, contrast),
    };
  }

  function showToast(msg, isWarn) {
    const el = document.getElementById("ios-toast");
    const txt = document.getElementById("toast-text");
    const dot = document.getElementById("toast-dot");
    if (!el || !txt) return;
    txt.textContent = msg;
    if (dot) dot.className = "toast-dot" + (isWarn ? " warn" : "");
    el.classList.add("show");
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove("show"), 2600);
  }

  const TAB_ORDER = ["typography", "ecosystem", "engine"];
  let currentTabIndex = 0;

  function positionTabLens(index, dragOffsetPx, isDragging) {
    const lens = document.getElementById("tab-lens");
    if (!lens) return;
    lens.classList.toggle("dragging", Boolean(isDragging));
    const basePct = index * 100;
    if (isDragging && typeof dragOffsetPx === "number") {
      lens.style.transform = `translate3d(calc(${basePct}% + ${dragOffsetPx.toFixed(1)}px), 0, 0) scale(1.07, 1.04)`;
    } else {
      lens.style.transform = `translate3d(${basePct}%, 0, 0)`;
    }
  }

  function syncTabButtons(activeIdx) {
    document.querySelectorAll(".tab-btn").forEach((b, i) => {
      const active = i === activeIdx;
      b.classList.toggle("active", active);
      b.setAttribute("aria-selected", active ? "true" : "false");
    });
  }

  function switchTab(tabId) {
    if (!TAB_TITLES[tabId]) tabId = "typography";
    currentTabIndex = Math.max(0, TAB_ORDER.indexOf(tabId));
    document.querySelectorAll(".tab-panel").forEach((p) => {
      p.classList.toggle("active", p.dataset.tab === tabId);
    });
    syncTabButtons(currentTabIndex);
    positionTabLens(currentTabIndex, 0, false);
    const navTitle = document.getElementById("nav-title");
    if (navTitle) navTitle.textContent = TAB_TITLES[tabId];
    if (tabId === "engine") {
      refreshTelemetryOnly();
    }
    try {
      sessionStorage.setItem("ct_active_tab", tabId);
    } catch (_) {}
  }

  function setupTabSliding() {
    const dock = document.getElementById("ios-tabbar");
    if (dock) {
      let dragging = false;
      let captured = false;
      let pointerId = null;
      let startX = 0;
      let startIdx = 0;
      let moved = false;

      const releaseCapture = () => {
        if (captured && pointerId !== null) {
          try {
            dock.releasePointerCapture(pointerId);
          } catch (_) {}
        }
        captured = false;
        pointerId = null;
      };

      dock.addEventListener("pointerdown", (e) => {
        dragging = true;
        captured = false;
        pointerId = e.pointerId;
        moved = false;
        startX = e.clientX;
        startIdx = currentTabIndex;
      });

      dock.addEventListener("pointermove", (e) => {
        if (!dragging) return;
        const rect = dock.getBoundingClientRect();
        const slotW = Math.max(1, (rect.width - 10) / 3);
        const dx = e.clientX - startX;
        if (!moved && Math.abs(dx) > 6) {
          moved = true;
          // Capture pointer only after real drag begins so simple taps always reach .tab-btn click
          try {
            dock.setPointerCapture(e.pointerId);
            captured = true;
          } catch (_) {}
        }
        if (!moved) return;

        // Clamp lens travel strictly inside the 3-tab dock
        const minDx = -startIdx * slotW;
        const maxDx = (2 - startIdx) * slotW;
        const clampedDx = Math.max(minDx, Math.min(maxDx, dx));
        positionTabLens(startIdx, clampedDx, true);

        const hoverIdx = Math.max(0, Math.min(2, Math.round(startIdx + clampedDx / slotW)));
        syncTabButtons(hoverIdx);
      });

      const finishDrag = (e) => {
        if (!dragging) return;
        dragging = false;
        releaseCapture();
        if (!moved) {
          positionTabLens(currentTabIndex, 0, false);
          return;
        }
        suppressTabClickUntil = Date.now() + 250;
        const rect = dock.getBoundingClientRect();
        const slotW = Math.max(1, (rect.width - 10) / 3);
        const dx = e.clientX - startX;
        const nextIdx = Math.max(0, Math.min(2, Math.round(startIdx + dx / slotW)));
        switchTab(TAB_ORDER[nextIdx]);
      };

      dock.addEventListener("pointerup", finishDrag);
      dock.addEventListener("pointercancel", () => {
        dragging = false;
        releaseCapture();
        syncTabButtons(currentTabIndex);
        positionTabLens(currentTabIndex, 0, false);
      });
    }

    // Horizontal swipe gesture on main content area (ignores range slider drags)
    const main = document.querySelector(".container");
    if (main) {
      let tx = 0;
      let ty = 0;
      let tracking = false;
      main.addEventListener(
        "touchstart",
        (e) => {
          if (e.touches.length !== 1 || e.target.closest('input[type="range"]')) {
            tracking = false;
            return;
          }
          tx = e.touches[0].clientX;
          ty = e.touches[0].clientY;
          tracking = true;
        },
        { passive: true }
      );
      main.addEventListener(
        "touchend",
        (e) => {
          if (!tracking || !e.changedTouches.length) return;
          tracking = false;
          const dx = e.changedTouches[0].clientX - tx;
          const dy = e.changedTouches[0].clientY - ty;
          if (Math.abs(dx) > 54 && Math.abs(dx) > Math.abs(dy) * 1.45) {
            if (dx < 0 && currentTabIndex < 2) {
              switchTab(TAB_ORDER[currentTabIndex + 1]);
            } else if (dx > 0 && currentTabIndex > 0) {
              switchTab(TAB_ORDER[currentTabIndex - 1]);
            }
          }
        },
        { passive: true }
      );
    }
  }

  function bindInteractiveGlow() {
    document.querySelectorAll(".interactive-glow").forEach((el) => {
      const setPos = (e) => {
        const rect = el.getBoundingClientRect();
        const x = ((e.clientX - rect.left) / Math.max(1, rect.width)) * 100;
        const y = ((e.clientY - rect.top) / Math.max(1, rect.height)) * 100;
        el.style.setProperty("--glow-x", `${x.toFixed(1)}%`);
        el.style.setProperty("--glow-y", `${y.toFixed(1)}%`);
      };
      el.addEventListener("pointerdown", (e) => {
        setPos(e);
        el.classList.add("glowing");
      });
      el.addEventListener("pointermove", (e) => {
        if (e.buttons > 0 || e.pointerType === "mouse") setPos(e);
      });
      const clear = () => el.classList.remove("glowing");
      el.addEventListener("pointerup", clear);
      el.addEventListener("pointercancel", clear);
      el.addEventListener("pointerleave", clear);
    });
  }

  function syncPresetHighlight() {
    document.querySelectorAll(".preset-pill").forEach((btn) => {
      const pBias = parseInt(btn.dataset.bias, 10);
      const pContrast = btn.dataset.contrast;
      const isSelected = wantedBias === pBias && wantedContrast === pContrast;
      btn.classList.toggle("selected", isSelected);
      btn.setAttribute("aria-pressed", isSelected ? "true" : "false");
    });
  }

  function updateLiveSpecimen() {
    const w = computeCurveWeights(romCurve, wantedBias, wantedContrast);
    const bodyEl = document.getElementById("specimen-body");
    const subEl = document.getElementById("specimen-subhead");
    const headEl = document.getElementById("specimen-header");
    const metaEl = document.getElementById("specimen-meta-curve");

    if (bodyEl) bodyEl.style.fontVariationSettings = `"wght" ${w.w400}`;
    if (subEl) subEl.style.fontVariationSettings = `"wght" ${w.w500}`;
    if (headEl) headEl.style.fontVariationSettings = `"wght" ${w.w700}`;
    if (metaEl) {
      metaEl.textContent = `Body ${w.w400} · Medium ${w.w500} · Header ${w.w600} · Bold ${w.w700}`;
    }

    const biasChip = document.getElementById("bias-value");
    const resetBtn = document.getElementById("bias-reset");
    if (biasChip) {
      if (wantedBias === 0) {
        biasChip.textContent = "0 · Standard";
      } else if (wantedBias > 0) {
        biasChip.textContent = `+${wantedBias} · Fuller`;
      } else {
        biasChip.textContent = `−${Math.abs(wantedBias)} · Lighter`;
      }
    }
    if (resetBtn) {
      resetBtn.classList.toggle("hidden", wantedBias === 0);
    }
    syncPresetHighlight();
  }

  function formatLatency(usRaw) {
    const us = parseInt(usRaw || "0", 10);
    if (!us || us <= 0) return "—";
    if (us < 1000) return `${us} µs`;
    return `${(us / 1000).toFixed(1)} ms`;
  }

  function renderLiveTelemetry(tm, st) {
    const mode = tm.daemon_mode || st.gms_watcher || "idle";
    const pill = document.getElementById("daemon-pill");
    if (pill) {
      pill.textContent = mode === "native-epoll" ? "native-epoll" : mode;
      pill.className = "mini-tag " + (mode === "native-epoll" ? "mini-tag-green" : "");
    }

    const rss = parseInt(tm.daemon_rss_kb || "0", 10);
    const priv = parseInt(tm.daemon_private_kb || "0", 10);
    if (priv > 0) {
      document.getElementById("tm-rss").textContent = `${priv} KB`;
      const vmMb = rss > 0 ? ` · RSS ${(rss / 1024).toFixed(1)} MB` : "";
      document.getElementById("tm-pid").textContent =
        (tm.daemon_pid ? `PID ${tm.daemon_pid}` : "Private") + vmMb;
    } else {
      document.getElementById("tm-rss").textContent = rss > 0 ? `${rss} KB` : "—";
      document.getElementById("tm-pid").textContent = tm.daemon_pid ? `PID ${tm.daemon_pid}` : "Idle";
    }

    const health = tm.watch_health || (mode === "native-epoll" ? "healthy" : "idle");
    const rec = parseInt(tm.watch_recoveries || "0", 10);
    const healthEl = document.getElementById("tm-health");
    if (healthEl) {
      healthEl.textContent =
        health === "healthy" ? "Healthy" : health === "recovering" ? "Recovering" : "Idle";
      healthEl.style.color =
        health === "healthy" ? "var(--green)" : health === "recovering" ? "var(--amber)" : "";
    }
    const recEl = document.getElementById("tm-recoveries");
    if (recEl) {
      recEl.textContent = `${rec} ${rec === 1 ? "recovery" : "recoveries"}`;
    }

    const gl = parseInt(tm.gms_latin_mounted ?? st.gms_fonts_bound ?? "0", 10);
    const ge = parseInt(tm.gms_emoji_mounted ?? st.gms_emoji_bound ?? "0", 10);
    document.getElementById("tm-mounts").textContent = `${gl + ge}`;
    document.getElementById("tm-mounts-sub").textContent = `${gl} Latin · ${ge} Emoji`;

    document.getElementById("tm-latency").textContent = formatLatency(tm.last_sync_latency_us);
    const sc = parseInt(tm.sync_count || "0", 10);
    document.getElementById("tm-syncs").textContent = `${sc} ${sc === 1 ? "sync" : "syncs"}`;

    const tTrak = tm.active_text_tracking_upm || "-44";
    const dTrak = tm.active_display_tracking_upm || "-26";
    document.getElementById("tm-trak").textContent = `${tTrak} / ${dTrak} UPM`;

    return { gl, ge };
  }

  function selectProfileRow(profile) {
    document.querySelectorAll(".ios-check-row").forEach((el) => {
      const selected = el.dataset.profile === profile;
      el.classList.toggle("selected", selected);
      el.setAttribute("aria-checked", selected ? "true" : "false");
    });
  }

  function selectContrast(contrast) {
    document.querySelectorAll(".seg-btn").forEach((el) => {
      const selected = el.dataset.contrast === contrast;
      el.classList.toggle("selected", selected);
      el.setAttribute("aria-checked", selected ? "true" : "false");
    });
  }

  // Note: Universal GMS App Fonts is Instant Live-Apply (SIGUSR1) — intentionally excluded from Reboot banner!
  function updateRebootBanner() {
    const dirty =
      installPendingReboot ||
      wantedProfile !== appliedProfile ||
      wantedBias !== appliedBias ||
      wantedContrast !== appliedContrast ||
      (emojiAvailable && wantedEmoji !== appliedEmoji);
    document.getElementById("reboot-banner").classList.toggle("hidden", !dirty);
  }

  // Build a Toybox/BusyBox/GNU-safe atomic multi-key shell update command (zero parallel .tmp collisions)
  function buildWriteConfCommand(entries, confFile) {
    const target = confFile || CONF_FILE;
    const pairs = Object.entries(entries).filter(
      ([k, v]) => CONF_KEY_RE.test(k) && CONF_VAL_RE.test(String(v))
    );
    if (!pairs.length) return null;

    const specArg = pairs.map(([k, v]) => `${k}=${v}`).join(" ");
    const printfArgs = pairs.map(([k, v]) => `'${k}=${v}'`).join(" ");
    return [
      `mkdir -p "$(dirname "${target}")"`,
      `_tmp="${target}.tmp.$$"`,
      `if [ -f "${target}" ]; then`,
      `  awk -F= -v spec='${specArg}' '`,
      `    BEGIN { n = split(spec, arr, " "); for (i = 1; i <= n; i++) { p = index(arr[i], "="); if (p > 1) { k = substr(arr[i], 1, p - 1); kv[k] = substr(arr[i], p + 1); order[++m] = k } } }`,
      `    ($1 in kv) { print $1 "=" kv[$1]; seen[$1] = 1; next }`,
      `    { print }`,
      `    END { for (i = 1; i <= m; i++) { k = order[i]; if (!seen[k]) print k "=" kv[k] } }`,
      `  ' "${target}" > "$_tmp" && mv "$_tmp" "${target}" || { rm -f "$_tmp"; exit 1; }`,
      `else`,
      `  printf '%s\\n' ${printfArgs} > "$_tmp" && mv "$_tmp" "${target}" || { rm -f "$_tmp"; exit 1; }`,
      `fi`,
    ].join("\n");
  }

  // Serialized, atomic multi-key config writer (eliminates parallel .tmp collisions & lost updates)
  function writeConfKeys(entries) {
    const cmd = buildWriteConfCommand(entries, CONF_FILE);
    if (!cmd) {
      return Promise.resolve({ code: 1, out: "", err: "Invalid config key/value" });
    }

    const task = () => execShell(cmd);
    const next = confWriteChain.then(task, task);
    confWriteChain = next.catch(() => {});
    return next;
  }

  function writeConfKey(key, val) {
    return writeConfKeys({ [key]: val });
  }

  async function refreshTelemetryOnly() {
    const [stRes, tmRes] = await Promise.all([
      execShell(`cat ${STATE_FILE} 2>/dev/null`),
      execShell(`cat ${TELEM_FILE} 2>/dev/null`),
    ]);
    if (stRes.code !== -1) {
      renderLiveTelemetry(parseProps(tmRes.out), parseProps(stRes.out));
    }
  }

  async function loadState() {
    const [stRes, cfRes, tmRes] = await Promise.all([
      execShell(`cat ${STATE_FILE} 2>/dev/null`),
      execShell(`cat ${CONF_FILE} 2>/dev/null`),
      execShell(`cat ${TELEM_FILE} 2>/dev/null`),
    ]);

    const badge = document.getElementById("status-badge");
    const emojiToggle = document.getElementById("emoji-toggle");
    const gmsToggle = document.getElementById("gms-fonts-toggle");
    const biasSlider = document.getElementById("weight-bias-slider");

    if (stRes.code === -1) {
      badge.textContent = "Preview";
      badge.className = "status-pill badge-muted";
      emojiAvailable = true;
      emojiToggle.checked = true;
      gmsToggle.checked = true;
      biasSlider.value = "0";
      selectProfileRow("dynamic_optical");
      selectContrast("balanced");
      updateLiveSpecimen();
      renderLiveTelemetry(
        {
          daemon_mode: "native-epoll",
          daemon_pid: "4128",
          daemon_private_kb: "212",
          daemon_rss_kb: "2120",
          watch_health: "healthy",
          watch_recoveries: "0",
          gms_latin_mounted: "10",
          gms_emoji_mounted: "4",
          sync_count: "3",
          last_sync_latency_us: "840",
          active_text_tracking_upm: "-44",
          active_display_tracking_upm: "-26",
        },
        {}
      );
      document.getElementById("kv-profile").textContent = "iOS Optical Dynamic";
      document.getElementById("kv-curve").textContent = "HyperOS Auto · Bias 0 · Balanced";
      document.getElementById("kv-flex").textContent = "RobotoFlex (opsz 17→28 · FV)";
      document.getElementById("kv-slots").textContent = "Roboto · Static · Flex";
      document.getElementById("kv-misans").textContent = "Active (CJK: MiSansTCVF)";
      document.getElementById("kv-emoji").textContent = "Active (iOS 26.4 · 4 GMS bound)";
      document.getElementById("kv-xml").textContent = "font_fallback.xml";
      document.getElementById("kv-guard").textContent = "Healthy · OTA Synced";
      return;
    }

    const st = parseProps(stRes.out);
    const cf = parseProps(cfRes.out);
    const tm = parseProps(tmRes.out);

    const isActive = st.status === "active";
    const isPendingReboot = st.status === "pending_reboot";
    installPendingReboot = isPendingReboot;
    badge.textContent = isActive
      ? "Active"
      : isPendingReboot
        ? "Pending Reboot"
        : st.status === "safe_disabled"
          ? "Safe Mode"
          : "Degraded";
    badge.className = "status-pill " + (isActive ? "badge-active" : "badge-warn");

    wantedProfile = VALID_PROFILES.includes(cf.profile)
      ? cf.profile
      : (VALID_PROFILES.includes(st.profile) ? st.profile : "dynamic_optical");
    appliedProfile = VALID_PROFILES.includes(cf.applied_profile)
      ? cf.applied_profile
      : (VALID_PROFILES.includes(st.profile) ? st.profile : "dynamic_optical");
    selectProfileRow(wantedProfile);

    romCurve = st.rom_curve || cf.rom_curve || "hyperos_mipro";
    wantedBias = clampBias(cf.weight_bias !== undefined ? cf.weight_bias : st.weight_bias);
    appliedBias = clampBias(cf.applied_weight_bias !== undefined ? cf.applied_weight_bias : st.weight_bias);
    wantedContrast = VALID_CONTRASTS.includes(cf.contrast_mode)
      ? cf.contrast_mode
      : (VALID_CONTRASTS.includes(st.contrast_mode) ? st.contrast_mode : "balanced");
    appliedContrast = VALID_CONTRASTS.includes(cf.applied_contrast_mode)
      ? cf.applied_contrast_mode
      : (VALID_CONTRASTS.includes(st.contrast_mode) ? st.contrast_mode : "balanced");

    biasSlider.value = String(wantedBias);
    selectContrast(wantedContrast);
    updateLiveSpecimen();

    const gmsEnabled = (cf.gms_fonts_enabled || st.gms_fonts_enabled || "1") !== "0";
    gmsToggle.checked = gmsEnabled;

    emojiAvailable = st.emoji_available === "1";
    appliedEmoji = st.emoji_active === "1";
    wantedEmoji = emojiAvailable ? (cf.emoji_enabled !== "0") : false;

    emojiToggle.disabled = !emojiAvailable;
    emojiToggle.checked = emojiAvailable && wantedEmoji;
    if (!emojiAvailable) {
      document.getElementById("emoji-title").textContent = "iOS 26.4 Color Emoji (Lite)";
      document.getElementById("emoji-desc").textContent =
        "Flash CoreType-Full.zip to enable Apple iOS 26.4 Emoji.";
    }

    const { gl, ge } = renderLiveTelemetry(tm, st);
    const curveTag = romCurve === "aosp_linear" ? "AOSP Linear" : "HyperOS Auto";
    const appliedBiasTag = appliedBias > 0 ? `+${appliedBias}` : `${appliedBias}`;

    document.getElementById("kv-profile").textContent = st.profile_label || appliedProfile;
    document.getElementById("kv-curve").textContent =
      `${curveTag} · Bias ${appliedBiasTag} · ${st.contrast_label || appliedContrast}`;
    document.getElementById("kv-flex").textContent = st.slot_flex
      ? `${st.slot_flex.replace(".ttf", "")} (opsz 17→28 · FV)`
      : "Shared Text Slot";
    document.getElementById("kv-slots").textContent =
      st.slot_text && st.slot_disp
        ? `${st.slot_text.replace("-Regular.ttf", "")} · ${st.slot_disp.replace("-Regular.ttf", "")}`
        : "Resolved";

    const misansEl = document.getElementById("kv-misans");
    if (st.misans_slider === "1") {
      const cjk = (st.cjk_fallback || "CJK").replace(".ttf", "").replace(".ttc", "");
      misansEl.textContent = `Active (CJK: ${cjk})`;
    } else {
      misansEl.textContent = "System Default";
    }

    const emojiEl = document.getElementById("kv-emoji");
    if (!emojiAvailable) {
      emojiEl.textContent = "Lite (Stock Emoji)";
    } else if (appliedEmoji) {
      emojiEl.textContent = ge > 0 ? `Active (${ge} GMS bound)` : "Active (System)";
    } else {
      emojiEl.textContent = "Off (Stock Emoji)";
    }

    document.getElementById("kv-xml").textContent = st.xml_active || "font_fallback.xml";
    const ota = st.ota_status === "resynced" ? "OTA Resynced" : "OTA Synced";
    document.getElementById("kv-guard").textContent =
      `${st.bootloop_guard === "healthy" ? "Healthy" : (st.bootloop_guard || "Active")} · ${ota} (${gl} GMS)`;

    updateRebootBanner();
  }

  function setupListeners() {
    // 3-Tab Bottom Dock
    document.querySelectorAll(".tab-btn").forEach((btn) => {
      btn.addEventListener("click", () => {
        if (Date.now() < suppressTabClickUntil) return;
        switchTab(btn.dataset.tabTarget);
      });
    });

    // Quick Presets (One-Tap Curve — single atomic config write)
    document.querySelectorAll(".preset-pill").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const nextContrast = btn.dataset.contrast;
        if (!VALID_CONTRASTS.includes(nextContrast)) return;
        wantedBias = clampBias(btn.dataset.bias);
        wantedContrast = nextContrast;
        document.getElementById("weight-bias-slider").value = String(wantedBias);
        selectContrast(wantedContrast);
        updateLiveSpecimen();
        updateRebootBanner();
        const res = await writeConfKeys({
          weight_bias: String(wantedBias),
          contrast_mode: wantedContrast,
        });
        if (res.code > 0) {
          showToast("Failed to save preset", true);
          return;
        }
        showToast(`${btn.querySelector(".preset-name").textContent} saved · Reboot to apply`, true);
      });
    });

    // Weight Bias Slider
    const biasSlider = document.getElementById("weight-bias-slider");
    biasSlider.addEventListener("input", () => {
      wantedBias = clampBias(biasSlider.value);
      updateLiveSpecimen();
      updateRebootBanner();
    });
    biasSlider.addEventListener("change", async () => {
      wantedBias = clampBias(biasSlider.value);
      const res = await writeConfKey("weight_bias", String(wantedBias));
      if (res.code > 0) showToast("Failed to save Weight Bias", true);
      updateRebootBanner();
    });

    document.getElementById("bias-reset").addEventListener("click", async () => {
      wantedBias = 0;
      biasSlider.value = "0";
      updateLiveSpecimen();
      const res = await writeConfKey("weight_bias", "0");
      updateRebootBanner();
      showToast(res.code > 0 ? "Failed to reset Weight Bias" : "Weight Bias reset to 0", res.code > 0);
    });

    // Header Contrast Segmented Control
    document.querySelectorAll(".seg-btn").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const c = btn.dataset.contrast;
        if (!VALID_CONTRASTS.includes(c) || c === wantedContrast) return;
        wantedContrast = c;
        selectContrast(c);
        updateLiveSpecimen();
        const res = await writeConfKey("contrast_mode", c);
        if (res.code > 0) showToast("Failed to save Header Contrast", true);
        updateRebootBanner();
      });
    });

    // Optical Width Profile Checkmark Rows
    document.querySelectorAll(".ios-check-row").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const next = btn.dataset.profile;
        if (!VALID_PROFILES.includes(next) || next === wantedProfile) return;
        wantedProfile = next;
        selectProfileRow(next);
        const res = await writeConfKey("profile", next);
        if (res.code > 0) showToast("Failed to save Optical Profile", true);
        updateRebootBanner();
      });
    });

    // Universal GMS App Fonts — INSTANT LIVE APPLY via SIGUSR1 (0 reboot!)
    const gmsToggle = document.getElementById("gms-fonts-toggle");
    gmsToggle.addEventListener("change", async () => {
      const enabled = gmsToggle.checked;
      gmsToggle.disabled = true;
      try {
        const wres = await writeConfKey("gms_fonts_enabled", enabled ? "1" : "0");
        if (wres.code > 0) {
          gmsToggle.checked = !enabled;
          showToast("Failed to update GMS config", true);
          return;
        }
        const res = await execShell(`sh ${ACTION_SCRIPT} 2>&1`);
        if (res.code === -1) {
          showToast(enabled ? "GMS Fonts ON · Applied live" : "GMS Fonts OFF · Detached live");
          return;
        }
        if (res.code !== 0) {
          showToast("GMS live sync failed", true);
          return;
        }
        await refreshTelemetryOnly();
        showToast(
          enabled ? "GMS Fonts ON · Applied live (0 reboot)" : "GMS Fonts OFF · Detached live (0 reboot)"
        );
      } finally {
        gmsToggle.disabled = false;
      }
    });

    // Apple iOS Emoji Toggle
    const emojiToggle = document.getElementById("emoji-toggle");
    emojiToggle.addEventListener("change", async () => {
      if (!emojiAvailable) return;
      const next = emojiToggle.checked;
      emojiToggle.disabled = true;
      try {
        const wres = await writeConfKey("emoji_enabled", next ? "1" : "0");
        if (wres.code > 0) {
          emojiToggle.checked = !next;
          showToast("Failed to update Emoji config", true);
          return;
        }
        wantedEmoji = next;
        const res = await execShell(`sh ${ACTION_SCRIPT} 2>&1`);
        await refreshTelemetryOnly();
        updateRebootBanner();
        if (res.code > 0) {
          showToast("Emoji config saved · Reboot to apply", true);
        } else {
          showToast("Emoji cache synced · Reboot for system slot", true);
        }
      } finally {
        emojiToggle.disabled = !emojiAvailable;
      }
    });

    // Instant GMS Sync Button
    const syncBtn = document.getElementById("sync-gms-btn");
    syncBtn.addEventListener("click", async () => {
      syncBtn.disabled = true;
      syncBtn.textContent = "Syncing…";
      try {
        const res = await execShell(`sh ${ACTION_SCRIPT} 2>&1`);
        if (res.code === -1) {
          showToast("Preview · SIGUSR1 (< 5 ms)");
        } else if (res.code !== 0) {
          const errMsg = (res.out || res.err || "Sync failed").trim().split(/\r?\n/).pop();
          document.getElementById("sync-gms-desc").textContent = errMsg;
          showToast("GMS Sync failed", true);
        } else {
          const msg = (res.out || "Synced").trim().split(/\r?\n/).pop();
          document.getElementById("sync-gms-desc").textContent = msg;
          await refreshTelemetryOnly();
          showToast("GMS Synced via SIGUSR1");
        }
      } finally {
        syncBtn.textContent = "Sync Now";
        syncBtn.disabled = false;
      }
    });

    // One-Tap Diagnostic Bundle
    const diagBtn = document.getElementById("export-diag-btn");
    diagBtn.addEventListener("click", async () => {
      diagBtn.disabled = true;
      diagBtn.textContent = "Exporting…";
      try {
        const res = await execShell(`sh ${ACTION_SCRIPT} --diag 2>&1`);
        if (res.code === -1) {
          showToast("Preview · /sdcard/Download/coretype-diag.txt");
        } else if (res.code !== 0) {
          const errMsg = (res.out || res.err || "Export failed").trim().split(/\r?\n/).pop();
          document.getElementById("diag-desc").textContent = errMsg;
          showToast("Diagnostic export failed", true);
        } else {
          const msg = (res.out || "Exported").trim().split(/\r?\n/).pop();
          document.getElementById("diag-desc").textContent = msg;
          showToast("Diagnostic exported to Download");
        }
      } finally {
        diagBtn.textContent = "Export";
        diagBtn.disabled = false;
      }
    });

    // Tinted Solid Surfaces Accessibility Toggle
    const glassToggle = document.getElementById("reduced-glass-toggle");
    try {
      const saved = localStorage.getItem("ct_reduced_glass") === "1";
      glassToggle.checked = saved;
      document.body.classList.toggle("reduced-glass", saved);
    } catch (_) {}
    glassToggle.addEventListener("change", () => {
      const on = glassToggle.checked;
      document.body.classList.toggle("reduced-glass", on);
      try {
        localStorage.setItem("ct_reduced_glass", on ? "1" : "0");
      } catch (_) {}
      showToast(on ? "Tinted solid surfaces enabled" : "Liquid Glass enabled");
    });

    // Restore last tab in session
    try {
      const lastTab = sessionStorage.getItem("ct_active_tab");
      if (lastTab && TAB_TITLES[lastTab]) switchTab(lastTab);
    } catch (_) {}
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = { calcWght, computeCurveWeights, clampBias, parseProps, buildWriteConfCommand };
    return;
  }

  document.addEventListener("DOMContentLoaded", () => {
    bindInteractiveGlow();
    setupTabSliding();
    setupListeners();
    loadState();
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) refreshTelemetryOnly();
    });
  });
})();
