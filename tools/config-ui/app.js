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

// ---- Module Profile tab ----
ConfigUI.profile = {
  selection: new Set(),
  pendingUnknown: [],

  parse(text) {
    const d = JSON.parse(text);
    return {
      modules: d.modules || [],
      label: d.label || "",
      description: d.description || "",
      order: d.order ?? 10000,
    };
  },

  serialize() {
    const om = ConfigUI.data.orderMap;
    const modules = [...this.selection].sort((a, b) =>
      ((om.get(a) ?? 99999) - (om.get(b) ?? 99999)) || a.localeCompare(b));
    const doc = {
      modules,
      label: document.getElementById("profile-label").value,
      description: document.getElementById("profile-desc").value,
      order: (n => Number.isNaN(n) ? 10000 : n)(Number(document.getElementById("profile-order").value)),
    };
    return JSON.stringify(doc, null, 2) + "\n";
  },

  applyImport(profile, sourceName) {
    const valid = new Set(ConfigUI.data.manifest.map(m => m.key));
    this.selection = new Set(profile.modules.filter(k => valid.has(k)));
    this.pendingUnknown = profile.modules.filter(k => !valid.has(k));
    document.getElementById("profile-label").value = profile.label;
    document.getElementById("profile-desc").value = profile.description;
    document.getElementById("profile-order").value = profile.order;
    if (sourceName) document.getElementById("profile-name").value = sourceName.replace(/\.json$/, "");
    this.render();
    ConfigUI.setStatus(`Loaded ${profile.modules.length} modules from ${sourceName || "import"}.`);
  },

  toggle(key, on) {
    if (on) this.selection.add(key); else this.selection.delete(key);
    this.renderWarnings();
    ConfigUI.emit("configui:selection-changed", {});
  },

  missingRequires() {
    const missing = new Map(); // required key -> [dependent names]
    for (const mod of ConfigUI.data.manifest) {
      if (!this.selection.has(mod.key)) continue;
      for (const req of mod.requires || []) {
        if (!this.selection.has(req)) {
          if (!missing.has(req)) missing.set(req, []);
          missing.get(req).push(mod.key);
        }
      }
    }
    return missing;
  },

  renderWarnings() {
    const box = document.getElementById("profile-warnings");
    box.textContent = "";
    for (const key of this.pendingUnknown) {
      const div = document.createElement("div");
      div.append(`Unknown module key (not in manifest, excluded from export): ${key} `);
      const keep = document.createElement("button");
      keep.textContent = "keep anyway";
      keep.addEventListener("click", () => {
        this.selection.add(key);
        this.pendingUnknown = this.pendingUnknown.filter(k => k !== key);
        this.renderWarnings();
        ConfigUI.emit("configui:selection-changed", {});
      });
      div.append(keep);
      box.append(div);
    }
    for (const [req, dependents] of this.missingRequires()) {
      const div = document.createElement("div");
      div.append(`⚠ ${dependents.join(", ")} requires ${req} `);
      const add = document.createElement("button");
      add.textContent = "add required";
      add.addEventListener("click", () => {
        this.selection.add(req);
        this.render();
        ConfigUI.emit("configui:selection-changed", {});
      });
      div.append(add);
      box.append(div);
    }
  },

  render() {
    const list = document.getElementById("module-list");
    const filter = document.getElementById("module-search").value.toLowerCase();
    list.textContent = "";
    const byCategory = new Map();
    for (const mod of ConfigUI.data.manifest) {
      const hay = `${mod.key} ${mod.name || ""} ${mod.description || ""}`.toLowerCase();
      if (filter && !hay.includes(filter)) continue;
      const cat = mod.category || "uncategorized";
      if (!byCategory.has(cat)) byCategory.set(cat, []);
      byCategory.get(cat).push(mod);
    }
    for (const cat of [...byCategory.keys()].sort()) {
      const h = document.createElement("div");
      h.className = "category";
      h.textContent = cat;
      list.append(h);
      const mods = byCategory.get(cat).sort((a, b) =>
        ((a.order ?? 99999) - (b.order ?? 99999)) || a.key.localeCompare(b.key));
      for (const mod of mods) {
        const row = document.createElement("div");
        row.className = "module-row";
        const cb = document.createElement("input");
        cb.type = "checkbox";
        cb.checked = this.selection.has(mod.key);
        cb.addEventListener("change", () => this.toggle(mod.key, cb.checked));
        const name = document.createElement("strong");
        name.textContent = mod.name || mod.key;
        const key = document.createElement("span");
        key.className = "key";
        key.textContent = mod.key;
        const desc = document.createElement("span");
        desc.className = "desc";
        desc.textContent = mod.description || "";
        row.append(cb, name, key, desc);
        if (mod.status && mod.status !== "active") {
          const badge = document.createElement("span");
          badge.className = "badge warn";
          badge.textContent = mod.status;
          row.append(badge);
        }
        list.append(row);
      }
    }
    this.renderWarnings();
  },
};

document.addEventListener("configui:ready", () => {
  const select = document.getElementById("profile-start");
  select.length = 1;
  for (const file of ConfigUI.data.index.profiles) {
    select.append(new Option(file, file));
  }
  ConfigUI.profile.render();
  ConfigUI.emit("configui:selection-changed", {});
});

document.getElementById("profile-start").addEventListener("change", async e => {
  if (!e.target.value) return;
  try {
    const text = await ConfigUI.fetchData("module-profiles/" + e.target.value);
    ConfigUI.profile.applyImport(ConfigUI.profile.parse(text), e.target.value);
    ConfigUI.emit("configui:selection-changed", {});
  } catch (err) {
    ConfigUI.setStatus(`Could not load ${e.target.value}: ${err.message}`, true);
  }
});

document.getElementById("module-search").addEventListener("input", () => ConfigUI.profile.render());

document.getElementById("profile-export").addEventListener("click", () => {
  const name = document.getElementById("profile-name").value.trim();
  if (!name || !ConfigUI.safeName(name)) {
    ConfigUI.setStatus("Profile file name is required and may only use letters, digits, dot, dash, underscore.", true);
    return;
  }
  ConfigUI.download(name + ".json", ConfigUI.profile.serialize());
});

document.addEventListener("configui:import", e => {
  if (!e.detail.name.endsWith(".json")) return;
  try {
    ConfigUI.profile.applyImport(ConfigUI.profile.parse(e.detail.text), e.detail.name);
    ConfigUI.emit("configui:selection-changed", {});
  } catch (err) {
    ConfigUI.setStatus(`Not a valid profile JSON (${e.detail.name}): ${err.message}`, true);
  }
});

ConfigUI.init();
