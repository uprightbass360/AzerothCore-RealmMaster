// RealmMaster Config Builder — vanilla JS, no dependencies.
// Format rules mirror tools/config-ui/check_roundtrip.py (the authority).
"use strict";

const ConfigUI = {
  data: { manifest: [], orderMap: new Map(), index: { profiles: [], presets: [] }, base: null },

  // The page runs from two roots: Pages serves it at the site root next to
  // config/, local serve.sh serves the whole repo (page under tools/config-ui/).
  BASES: ["config/", "../../config/"],

  async fetchData(relPath) {
    const res = await fetch(this.data.base + relPath);
    if (!res.ok) throw new Error(`${res.status} for ${relPath}`);
    return res.text();
  },

  setStatus(message, isError) {
    const el = document.getElementById("status");
    el.textContent = message;
    el.classList.toggle("error", !!isError);
  },

  download(filename, text) {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([text], { type: "text/plain" }));
    a.download = filename;
    a.click();
    URL.revokeObjectURL(a.href);
  },

  safeName(name) { return /^[A-Za-z0-9._-]+$/.test(name); },

  emit(type, detail) { document.dispatchEvent(new CustomEvent(type, { detail })); },

  async init() {
    for (const base of this.BASES) {
      try {
        const res = await fetch(base + "module-manifest.json");
        if (!res.ok) continue;
        const j = await res.json();
        this.data.manifest = Array.isArray(j) ? j : (j.modules || []);
        this.data.base = base;
        break;
      } catch (e) { /* file:// or missing — try next base */ }
    }
    if (!this.data.base) {
      this.setStatus("Could not fetch repo data (opened via file://?). Use the file picker: drop module-manifest.json first, then any files to edit.", true);
    } else {
      try {
        this.data.index = JSON.parse(await this.fetchData("index.json"));
      } catch (e) {
        this.setStatus("index.json missing — run tools/config-ui/serve.sh (it generates it). Start-from lists will be empty.", true);
      }
      this.setStatus(`${this.data.manifest.length} modules loaded from repo data (${this.data.base === "config/" ? "published" : "local checkout"}).`);
    }
    this.data.orderMap = new Map(this.data.manifest.map(m => [m.key, m.order ?? 99999]));
    this.emit("configui:ready", {});
  },
};
window.ConfigUI = ConfigUI;

// ---- tabs ----
document.querySelectorAll(".tab-btn").forEach(btn => btn.addEventListener("click", () => {
  document.querySelectorAll(".tab-btn").forEach(b => b.classList.toggle("active", b === btn));
  document.querySelectorAll(".panel").forEach(p => p.classList.toggle("active", p.id === "panel-" + btn.dataset.tab));
}));

// ---- import routing: drag-drop and picker both emit configui:import ----
function routeFiles(fileList) {
  for (const file of fileList) {
    file.text().then(text => {
      if (file.name === "module-manifest.json") {
        const j = JSON.parse(text);
        ConfigUI.data.manifest = Array.isArray(j) ? j : (j.modules || []);
        ConfigUI.data.orderMap = new Map(ConfigUI.data.manifest.map(m => [m.key, m.order ?? 99999]));
        ConfigUI.setStatus(`${ConfigUI.data.manifest.length} modules loaded from dropped manifest.`);
        ConfigUI.emit("configui:ready", {});
      } else {
        ConfigUI.emit("configui:import", { name: file.name, text });
      }
    }).catch(e => ConfigUI.setStatus(`Could not read ${file.name}: ${e.message}`, true));
  }
}
const dropZone = document.getElementById("drop-zone");
dropZone.addEventListener("dragover", e => { e.preventDefault(); dropZone.classList.add("drag"); });
dropZone.addEventListener("dragleave", () => dropZone.classList.remove("drag"));
dropZone.addEventListener("drop", e => { e.preventDefault(); dropZone.classList.remove("drag"); routeFiles(e.dataTransfer.files); });
document.getElementById("file-input").addEventListener("change", e => routeFiles(e.target.files));

ConfigUI.init();
