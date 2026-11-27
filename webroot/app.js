(function () {
  "use strict";

  const STATE_FILE = "/data/adb/coretype/state.prop";
  const CONF_FILE = "/data/adb/coretype/config.conf";
  const TELEM_FILE = "/dev/.coretype/telemetry.prop";
  const WATCHD_PID_FILE = "/dev/.coretype/watchd.pid";
  const VALID_PROFILES = ["dynamic_optical", "native_pro", "compact_crisp"];
  const VALID_CONTRASTS = ["soft", "balanced", "apple_native"];

  let appliedProfile = "dynamic_optical";
  let wantedProfile = "dynamic_optical";
  let appliedBias = 0;
  let wantedBias = 0;
  let appliedContrast = "balanced";
  let wantedContrast = "balanced";
  let romCurve = "hyperos_mipro";
  let appliedGmsFonts = "1";
  let wantedGmsFonts = "1";
  let appliedEmoji = "1";
  let wantedEmoji = "1";
  let emojiAvailable = false;

  function execShell(cmd) {
    return new Promise((resolve) => {
      if (typeof window.ksu !== "undefined" && typeof window.ksu.exec === "function") {
        const cb = "ct_cb_" + Date.now() + "_" + Math.floor(Math.random() * 10000);
        window[cb] = function (errno, stdout, stderr) {
          delete window[cb];
          resolve({ code: errno, out: stdout || "", err: stderr || "" });
        };
        window.ksu.exec(cmd, "{}", cb);
      } else {
        resolve({ code: -1, out: "", err: "No KSU bridge" });
      }
    });
  }

  function parseProps(raw) {
    const map = {};
    (raw || "").split("\n").forEach((line) => {
      const idx = line.indexOf("=");
      if (idx > 0) {
        map[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
      }
    });
    return map;
  }

  function clampBias(val) {
    const n = parseInt(val, 10);
    if (Number.isNaN(n)) return 0;
    return Math.max(-60, Math.min(80, n));
  }

  // Exact JS mirror of ct_calc_wght() in lib/font_xml.sh for live WebUI preview
  function calcWght(slot, rom, contrast, bias) {
    const bases =
      rom === "aosp_linear"
        ? { 200: 240, 400: 400, 500: 500, 600: 570, 700: 650, 800: 740 }
        : { 200: 250, 400: 400, 500: 485, 600: 535, 700: 550, 800: 650 };
    const base = bases[slot] || slot;

    let cdelta = 0;
    if (contrast === "soft") {
      if (slot === 600) cdelta = -25;
      else if (slot === 700) cdelta = -30;
      else if (slot === 800) cdelta = -35;
    } else if (contrast === "apple_native") {
      if (slot === 600) cdelta = 25;
      else if (slot === 700 || slot === 800) cdelta = 45;
    }

    let bdelta = bias;
    if (slot === 200) bdelta = Math.trunc(bias / 2);
    else if (slot === 800) bdelta = Math.trunc((bias * 3) / 4);

    return Math.max(100, Math.min(950, base + cdelta + bdelta));
  }

  function biasLabel(bias) {
    if (bias === 0) return "0 · Standard";
    const sign = bias > 0 ? "+" : "";
    const tag = bias < -20 ? "Airy" : bias < 0 ? "Light" : bias <= 30 ? "Crisp" : "Bold";
    return `${sign}${bias} · ${tag}`;
  }

  function formatLatency(usRaw) {
    const us = parseInt(usRaw || "0", 10);
    if (Number.isNaN(us) || us <= 0) return "< 1 ms";
    if (us < 1000) return `${us} µs`;
    return `${(us / 1000).toFixed(2)} ms`;
  }

  function renderLiveTelemetry(tm, st) {
    const mode = tm.daemon_mode || st.gms_watcher || "idle";
    const pill = document.getElementById("daemon-pill");
    pill.textContent = mode;
    pill.className = "pill " + (mode === "native-epoll" ? "pill-live" : "");

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
    document.getElementById("tm-health").textContent =
      health === "healthy" ? "Healthy" : health === "recovering" ? "Recovering" : "Idle";
    document.getElementById("tm-recoveries").textContent =
      `${rec} recover${rec === 1 ? "y" : "ies"}`;

    const latinCnt = parseInt(tm.gms_latin_mounted || st.gms_fonts_bound || "0", 10);
    const emojiCnt = parseInt(tm.gms_emoji_mounted || st.gms_emoji_bound || "0", 10);
    document.getElementById("tm-mounts").textContent = `${latinCnt + emojiCnt} active`;
    document.getElementById("tm-mounts-sub").textContent = `${latinCnt} Latin · ${emojiCnt} Emoji`;

    document.getElementById("tm-latency").textContent = formatLatency(tm.last_sync_latency_us);
    const sc = parseInt(tm.sync_count || "0", 10);
    document.getElementById("tm-syncs").textContent = `${sc} sync${sc === 1 ? "" : "s"}`;

    const tUpm = tm.active_text_tracking_upm || "-46";
    const dUpm = tm.active_display_tracking_upm || "-26";
    document.getElementById("tm-trak").textContent = `${tUpm} / ${dUpm} UPM`;
  }

  function updateLiveSpecimen() {
    const wClock = calcWght(200, romCurve, wantedContrast, wantedBias);
    const wBody = calcWght(400, romCurve, wantedContrast, wantedBias);
    const wMed = calcWght(500, romCurve, wantedContrast, wantedBias);
    const wSub = calcWght(600, romCurve, wantedContrast, wantedBias);
    const wHdr = calcWght(700, romCurve, wantedContrast, wantedBias);
    const wBold = calcWght(800, romCurve, wantedContrast, wantedBias);

    const setW = (id, w) => {
      const el = document.getElementById(id);
      if (el) el.style.fontVariationSettings = `"wght" ${w}`;
    };
    setW("specimen-clock", wClock);
    setW("specimen-header", wHdr);
    setW("specimen-subhead", wSub);
    setW("specimen-body", wBody);

    document.getElementById("specimen-meta-curve").textContent =
      `Body ${wBody} · Med ${wMed} · Header ${wHdr} · Bold ${wBold}`;

    document.getElementById("bias-value").textContent = biasLabel(wantedBias);
    document.getElementById("bias-reset").classList.toggle("hidden", wantedBias === 0);
  }

  function selectButton(profileId) {
    document.querySelectorAll(".profile-item").forEach((btn) => {
      btn.classList.toggle("selected", btn.dataset.profile === profileId);
    });
  }

  function selectContrast(mode) {
    document.querySelectorAll("#contrast-group .seg-btn").forEach((btn) => {
      btn.classList.toggle("selected", btn.dataset.contrast === mode);
    });
  }

  function syncRebootBanner() {
    const dirty =
      wantedProfile !== appliedProfile ||
      wantedBias !== appliedBias ||
      wantedContrast !== appliedContrast ||
      wantedGmsFonts !== appliedGmsFonts ||
      (emojiAvailable && wantedEmoji !== appliedEmoji);
    document.getElementById("reboot-banner").classList.toggle("hidden", !dirty);
  }

  function writeConfKey(key, val) {
    const cmd = `mkdir -p /data/adb/coretype && if [ -f ${CONF_FILE} ]; then awk -F= -v k='${key}' -v v='${val}' 'BEGIN{d=0} $1==k{print k"="v;d=1;next} {print} END{if(!d)print k"="v}' ${CONF_FILE} > ${CONF_FILE}.tmp && mv ${CONF_FILE}.tmp ${CONF_FILE}; else printf '%s=%s\\n' '${key}' '${val}' > ${CONF_FILE}; fi`;
    return execShell(cmd);
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
      badge.className = "badge badge-muted";
      emojiAvailable = true;
      emojiToggle.checked = true;
      gmsToggle.checked = true;
      biasSlider.value = "0";
      selectButton("dynamic_optical");
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
          gms_latin_mounted: "12",
          gms_emoji_mounted: "4",
          sync_count: "2",
          last_sync_latency_us: "840",
          active_text_tracking_upm: "-46",
          active_display_tracking_upm: "-26",
        },
        {}
      );
      document.getElementById("kv-profile").textContent = "iOS Optical Dynamic";
      document.getElementById("kv-curve").textContent = "HyperOS Auto · Bias 0 · Balanced";
      document.getElementById("kv-flex").textContent = "RobotoFlex (opsz 12–36)";
      document.getElementById("kv-slots").textContent = "Roboto · Static · Flex";
      document.getElementById("kv-misans").textContent = "Active (CJK: MiSansTCVF)";
      document.getElementById("kv-emoji").textContent = "Active (iOS 26.4 · 3 GMS bound)";
      document.getElementById("kv-xml").textContent = "font_fallback.xml";
      document.getElementById("kv-guard").textContent = "Healthy · OTA Synced";
      return;
    }

    const st = parseProps(stRes.out);
    const cf = parseProps(cfRes.out);
    const tm = parseProps(tmRes.out);

    const isActive = st.status === "active";
    badge.textContent = isActive ? "Active" : st.status === "safe_disabled" ? "Safe Mode" : "Degraded";
    badge.className = "badge " + (isActive ? "badge-active" : "badge-warn");

    wantedProfile = cf.profile || st.profile || "dynamic_optical";
    appliedProfile = cf.applied_profile || st.profile || "dynamic_optical";
    selectButton(wantedProfile);

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
    renderLiveTelemetry(tm, st);

    wantedGmsFonts = cf.gms_fonts_enabled === "0" ? "0" : "1";
    appliedGmsFonts = cf.applied_gms_fonts === "0" ? "0" : (st.gms_fonts_enabled === "0" ? "0" : "1");
    gmsToggle.checked = wantedGmsFonts === "1";

    emojiAvailable = st.emoji_available === "1";
    wantedEmoji = cf.emoji_enabled === "0" ? "0" : "1";
    appliedEmoji = cf.applied_emoji === "0" ? "0" : (st.emoji_active === "1" ? "1" : "0");

    if (emojiAvailable) {
      emojiToggle.disabled = false;
      emojiToggle.checked = wantedEmoji === "1";
      const gmsBound = parseInt(tm.gms_emoji_mounted || st.gms_emoji_bound || "0", 10);
      document.getElementById("kv-emoji").textContent =
        st.emoji_active === "1"
          ? (gmsBound > 0 ? `Active (iOS 26.4 · ${gmsBound} GMS bound)` : "Active (iOS 26.4 · GMS-Aware)")
          : "Disabled (Stock Emoji)";
    } else {
      emojiToggle.disabled = true;
      emojiToggle.checked = false;
      document.getElementById("emoji-title").textContent = "Lite Edition (SF Pro Only)";
      document.getElementById("emoji-desc").textContent =
        "Flash CoreType-Full.zip to enable Apple iOS 26.4 Color Emoji.";
      document.getElementById("kv-emoji").textContent = "Not Bundled (Lite)";
    }

    document.getElementById("kv-profile").textContent = st.profile_label || appliedProfile;
    const romTag = romCurve === "aosp_linear" ? "AOSP Auto" : "HyperOS Auto";
    const biasTxt = appliedBias > 0 ? `+${appliedBias}` : `${appliedBias}`;
    const cLabel = st.contrast_label || (appliedContrast === "soft" ? "Soft" : appliedContrast === "apple_native" ? "Apple Native" : "Balanced");
    document.getElementById("kv-curve").textContent = `${romTag} · Bias ${biasTxt} · ${cLabel}`;

    const shortSlot = (name) => (name || "—").replace(/-Regular\.ttf$|\.ttf$|\.otf$|\.ttc$/g, "");
    const flexSlot = st.slot_flex || st.slot_text || "";
    document.getElementById("kv-flex").textContent =
      flexSlot && flexSlot !== st.slot_text
        ? `${shortSlot(flexSlot)} (opsz 12–36)`
        : "Dual-Master (17 / 28)";

    document.getElementById("kv-slots").textContent =
      st.slot_text ? `${shortSlot(st.slot_text)} · ${shortSlot(st.slot_disp)} · ${shortSlot(flexSlot)}` : "—";

    document.getElementById("kv-misans").textContent =
      st.misans_slider === "1"
        ? `Active (CJK: ${shortSlot(st.cjk_fallback)})`
        : "AOSP / Preserved";

    document.getElementById("kv-xml").textContent = st.xml_active || "none";

    const guardText = st.bootloop_guard === "healthy" ? "Healthy" : (st.bootloop_guard || "Armed");
    const otaText = st.ota_status === "resynced" ? "OTA Resynced" : "OTA Synced";
    document.getElementById("kv-guard").textContent = `${guardText} · ${otaText}`;

    syncRebootBanner();
  }

  async function setProfile(profileId) {
    if (!VALID_PROFILES.includes(profileId)) return;
    wantedProfile = profileId;
    selectButton(profileId);
    await writeConfKey("profile", profileId);
    syncRebootBanner();
  }

  async function setWeightBias(val) {
    wantedBias = clampBias(val);
    document.getElementById("weight-bias-slider").value = String(wantedBias);
    updateLiveSpecimen();
    await writeConfKey("weight_bias", String(wantedBias));
    syncRebootBanner();
  }

  async function setContrast(mode) {
    if (!VALID_CONTRASTS.includes(mode)) return;
    wantedContrast = mode;
    selectContrast(mode);
    updateLiveSpecimen();
    await writeConfKey("contrast_mode", mode);
    syncRebootBanner();
  }

  async function setGmsFonts(enabled) {
    wantedGmsFonts = enabled ? "1" : "0";
    await writeConfKey("gms_fonts_enabled", wantedGmsFonts);
    syncRebootBanner();
  }

  async function setEmoji(enabled) {
    if (!emojiAvailable) return;
    wantedEmoji = enabled ? "1" : "0";
    await writeConfKey("emoji_enabled", wantedEmoji);
    syncRebootBanner();
  }

  async function syncGmsNow() {
    const btn = document.getElementById("sync-gms-btn");
    const desc = document.getElementById("sync-gms-desc");
    btn.disabled = true;
    btn.textContent = "Syncing…";
    const cmd = `if [ -r ${WATCHD_PID_FILE} ] && kill -0 "$(cat ${WATCHD_PID_FILE})" 2>/dev/null; then kill -USR1 "$(cat ${WATCHD_PID_FILE})" && sleep 0.08 2>/dev/null; echo "SIGUSR1 dispatched to coretype-watchd."; else sh /data/adb/modules/coretype/action.sh 2>&1; fi`;
    const res = await execShell(cmd);
    if (res.code === 0) {
      desc.textContent = (res.out || "Sync signal dispatched.").trim();
      await loadState();
    } else if (res.code === -1) {
      desc.textContent = "Preview mode: SIGUSR1 triggers coretype-watchd natively in KernelSU / APatch.";
    } else {
      desc.textContent = "Sync completed (check coretype.log if any cache was locked).";
    }
    btn.textContent = "Sync Now";
    btn.disabled = false;
  }

  async function exportDiag() {
    const btn = document.getElementById("export-diag-btn");
    const desc = document.getElementById("diag-desc");
    btn.disabled = true;
    btn.textContent = "Exporting…";
    const res = await execShell("sh /data/adb/modules/coretype/action.sh --diag 2>&1");
    if (res.code === 0) {
      desc.textContent = (res.out || "Diagnostic exported to /sdcard/Download/coretype-diag.txt").trim();
    } else if (res.code === -1) {
      desc.textContent = "Preview mode: exports to /sdcard/Download/coretype-diag.txt inside KernelSU / APatch.";
    } else {
      desc.textContent = "Diagnostic export failed (check storage permissions).";
    }
    btn.textContent = "Export Diagnostic";
    btn.disabled = false;
  }

  document.querySelectorAll(".profile-item").forEach((btn) => {
    btn.addEventListener("click", () => setProfile(btn.dataset.profile));
  });

  document.querySelectorAll("#contrast-group .seg-btn").forEach((btn) => {
    btn.addEventListener("click", () => setContrast(btn.dataset.contrast));
  });

  const biasSlider = document.getElementById("weight-bias-slider");
  biasSlider.addEventListener("input", (ev) => {
    wantedBias = clampBias(ev.target.value);
    updateLiveSpecimen();
  });
  biasSlider.addEventListener("change", (ev) => {
    setWeightBias(ev.target.value);
  });

  document.getElementById("bias-reset").addEventListener("click", () => setWeightBias(0));

  document.getElementById("gms-fonts-toggle").addEventListener("change", (ev) => {
    setGmsFonts(ev.target.checked);
  });

  document.getElementById("emoji-toggle").addEventListener("change", (ev) => {
    setEmoji(ev.target.checked);
  });

  document.getElementById("sync-gms-btn").addEventListener("click", syncGmsNow);
  document.getElementById("export-diag-btn").addEventListener("click", exportDiag);

  loadState();
})();
