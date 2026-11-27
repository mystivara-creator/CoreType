(function () {
  "use strict";

  const STATE_FILE = "/data/adb/coretype/state.prop";
  const CONF_FILE = "/data/adb/coretype/config.conf";
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
    const [stRes, cfRes] = await Promise.all([
      execShell(`cat ${STATE_FILE} 2>/dev/null`),
      execShell(`cat ${CONF_FILE} 2>/dev/null`),
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
      document.getElementById("kv-profile").textContent = "iOS Optical Dynamic";
      document.getElementById("kv-curve").textContent = "HyperOS Auto · Bias 0 · Balanced";
      document.getElementById("kv-gms-fonts").textContent = "Active (GMS Bound)";
      document.getElementById("kv-mounted").textContent = "Dual-Optical VF (Shared Inode)";
      document.getElementById("kv-slots").textContent = "Roboto · Static · Flex";
      document.getElementById("kv-misans").textContent = "Active (CJK: MiSansTCVF)";
      document.getElementById("kv-emoji").textContent = "Active (iOS 26.4 · 3 GMS bound)";
      document.getElementById("kv-xml").textContent = "font_fallback.xml";
      document.getElementById("kv-guard").textContent = "Healthy · OTA Synced";
      return;
    }

    const st = parseProps(stRes.out);
    const cf = parseProps(cfRes.out);

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

    wantedGmsFonts = cf.gms_fonts_enabled === "0" ? "0" : "1";
    appliedGmsFonts = cf.applied_gms_fonts === "0" ? "0" : (st.gms_fonts_enabled === "0" ? "0" : "1");
    gmsToggle.checked = wantedGmsFonts === "1";

    const gmsFontBound = parseInt(st.gms_fonts_bound || "0", 10);
    document.getElementById("kv-gms-fonts").textContent =
      appliedGmsFonts === "1"
        ? (gmsFontBound > 0 ? `Active (${gmsFontBound} GMS bound)` : "Active (GMS-Aware)")
        : "Disabled";

    emojiAvailable = st.emoji_available === "1";
    wantedEmoji = cf.emoji_enabled === "0" ? "0" : "1";
    appliedEmoji = cf.applied_emoji === "0" ? "0" : (st.emoji_active === "1" ? "1" : "0");

    if (emojiAvailable) {
      emojiToggle.disabled = false;
      emojiToggle.checked = wantedEmoji === "1";
      const gmsBound = parseInt(st.gms_emoji_bound || "0", 10);
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

    document.getElementById("kv-mounted").textContent =
      st.font_mounted === "1" ? "Dual-Optical VF (Shared Inode)" : "Not Mounted";

    const shortSlot = (name) => (name || "—").replace(/-Regular\.ttf$|\.ttf$|\.otf$|\.ttc$/g, "");
    document.getElementById("kv-slots").textContent =
      st.slot_text ? `${shortSlot(st.slot_text)} · ${shortSlot(st.slot_disp)} · ${shortSlot(st.slot_ital)}` : "—";

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

  async function syncGmsNow() {
    const btn = document.getElementById("sync-gms-btn");
    const desc = document.getElementById("sync-gms-desc");
    btn.disabled = true;
    btn.textContent = "Syncing…";
    const res = await execShell("sh /data/adb/modules/coretype/action.sh 2>&1");
    if (res.code === 0) {
      desc.textContent = (res.out || "GMS cache synced cleanly.").trim();
      await loadState();
    } else if (res.code === -1) {
      desc.textContent = "Preview mode: action.sh runs natively inside KernelSU / APatch.";
    } else {
      desc.textContent = "Sync completed (check coretype.log if any cache was locked).";
    }
    btn.textContent = "Sync Now";
    btn.disabled = false;
  }

  document.getElementById("emoji-toggle").addEventListener("change", (ev) => {
    setEmoji(ev.target.checked);
  });

  document.getElementById("sync-gms-btn").addEventListener("click", syncGmsNow);

  loadState();
})();
