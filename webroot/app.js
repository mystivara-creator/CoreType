(function () {
  "use strict";

  const STATE_FILE = "/data/adb/coretype/state.prop";
  const CONF_FILE = "/data/adb/coretype/config.conf";
  const VALID_PROFILES = ["dynamic_optical", "native_pro", "compact_crisp"];

  let appliedProfile = "dynamic_optical";
  let wantedProfile = "dynamic_optical";
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

  function selectButton(profileId) {
    document.querySelectorAll(".profile-item").forEach((btn) => {
      btn.classList.toggle("selected", btn.dataset.profile === profileId);
    });
  }

  function syncRebootBanner() {
    const dirty = wantedProfile !== appliedProfile || (emojiAvailable && wantedEmoji !== appliedEmoji);
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

    if (stRes.code === -1) {
      badge.textContent = "Preview";
      badge.className = "badge badge-muted";
      appliedProfile = "dynamic_optical";
      wantedProfile = "dynamic_optical";
      appliedEmoji = "1";
      wantedEmoji = "1";
      emojiAvailable = true;
      emojiToggle.checked = true;
      selectButton("dynamic_optical");
      document.getElementById("kv-profile").textContent = "iOS Optical Dynamic";
      document.getElementById("kv-mounted").textContent = "Dual-Optical VF (Shared Inode)";
      document.getElementById("kv-slots").textContent = "Roboto · Static · Flex";
      document.getElementById("kv-misans").textContent = "Active (CJK: MiSansTCVF)";
      document.getElementById("kv-emoji").textContent = "Active (Full Edition)";
      document.getElementById("kv-xml").textContent = "font_fallback.xml";
      document.getElementById("kv-wdth").textContent = "96.5 / 97.0";
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
    document.getElementById("kv-wdth").textContent =
      st.wdth_text && st.wdth_disp ? `${st.wdth_text} / ${st.wdth_disp}` : "—";

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

  async function setEmoji(enabled) {
    if (!emojiAvailable) return;
    wantedEmoji = enabled ? "1" : "0";
    await writeConfKey("emoji_enabled", wantedEmoji);
    syncRebootBanner();
  }

  document.querySelectorAll(".profile-item").forEach((btn) => {
    btn.addEventListener("click", () => setProfile(btn.dataset.profile));
  });

  document.getElementById("emoji-toggle").addEventListener("change", (ev) => {
    setEmoji(ev.target.checked);
  });

  loadState();
})();
