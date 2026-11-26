(function () {
  "use strict";

  const STATE_FILE = "/data/adb/coretype/state.prop";
  const CONF_FILE = "/data/adb/coretype/config.conf";

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

  async function loadState() {
    const [stRes, cfRes] = await Promise.all([
      execShell(`cat ${STATE_FILE} 2>/dev/null`),
      execShell(`cat ${CONF_FILE} 2>/dev/null`),
    ]);

    const badge = document.getElementById("status-badge");
    if (stRes.code === -1) {
      badge.textContent = "Preview";
      badge.className = "badge badge-muted";
      selectButton("dynamic_optical");
      document.getElementById("kv-profile").textContent = "iOS Optical Dynamic";
      document.getElementById("kv-mounted").textContent = "4/4 Dual-Optical VF";
      document.getElementById("kv-xml").textContent = "font_fallback.xml";
      document.getElementById("kv-wdth").textContent = "96.5 / 97.0";
      document.getElementById("kv-guard").textContent = "Healthy";
      return;
    }

    const st = parseProps(stRes.out);
    const cf = parseProps(cfRes.out);

    const isActive = st.status === "active";
    badge.textContent = isActive ? "Active" : st.status === "safe_disabled" ? "Safe Mode" : "Degraded";
    badge.className = "badge " + (isActive ? "badge-active" : "badge-warn");

    const wanted = cf.profile || st.profile || "dynamic_optical";
    const applied = cf.applied_profile || st.profile || "dynamic_optical";
    selectButton(wanted);

    document.getElementById("kv-profile").textContent = st.profile_label || applied;
    document.getElementById("kv-mounted").textContent =
      st.font_mounted === "1" ? "4/4 Dual-Optical VF" : "Not Mounted";
    document.getElementById("kv-xml").textContent = st.xml_active || "none";
    document.getElementById("kv-wdth").textContent =
      st.wdth_text && st.wdth_disp ? `${st.wdth_text} / ${st.wdth_disp}` : "—";
    document.getElementById("kv-guard").textContent =
      st.bootloop_guard === "healthy" ? "Healthy (0 faults)" : (st.bootloop_guard || "Armed");

    document.getElementById("reboot-banner").classList.toggle("hidden", wanted === applied);
  }

  async function setProfile(profileId) {
    selectButton(profileId);
    const cmd = `mkdir -p /data/adb/coretype && if [ -f ${CONF_FILE} ]; then awk -F= -v v='${profileId}' 'BEGIN{d=0} $1=="profile"{print "profile="v;d=1;next} {print} END{if(!d)print "profile="v}' ${CONF_FILE} > ${CONF_FILE}.tmp && mv ${CONF_FILE}.tmp ${CONF_FILE}; else printf 'profile=%s\\n' '${profileId}' > ${CONF_FILE}; fi`;
    await execShell(cmd);
    document.getElementById("reboot-banner").classList.remove("hidden");
  }

  document.querySelectorAll(".profile-item").forEach((btn) => {
    btn.addEventListener("click", () => setProfile(btn.dataset.profile));
  });

  loadState();
})();
