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
        this.setStatus(`${this.data.manifest.length} modules loaded from repo data (${this.data.base === "config/" ? "published" : "local checkout"}).`);
      } catch (e) {
        this.setStatus("index.json missing — run tools/config-ui/serve.sh (it generates it). Start-from lists will be empty.", true);
      }
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
      ((om.get(a) ?? 99999) - (om.get(b) ?? 99999)) || (a < b ? -1 : a > b ? 1 : 0));
    const orderInput = document.getElementById("profile-order").value.trim();
    const orderNum = Number(orderInput);
    const order = orderInput === "" || Number.isNaN(orderNum) ? 10000 : orderNum;
    const doc = {
      modules,
      label: document.getElementById("profile-label").value,
      description: document.getElementById("profile-desc").value,
      order,
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
    const table = document.createElement("table");
    table.className = "module-table";
    const thead = document.createElement("thead");
    const headRow = document.createElement("tr");
    for (const label of ["", "Module", "Key", "Description", "Link"]) {
      const th = document.createElement("th");
      th.textContent = label;
      headRow.append(th);
    }
    thead.append(headRow);
    table.append(thead);
    const tbody = document.createElement("tbody");
    for (const cat of [...byCategory.keys()].sort()) {
      const catRow = document.createElement("tr");
      catRow.className = "category-row";
      const catCell = document.createElement("td");
      catCell.colSpan = 5;
      catCell.textContent = cat;
      catRow.append(catCell);
      tbody.append(catRow);
      const mods = byCategory.get(cat).sort((a, b) =>
        ((a.order ?? 99999) - (b.order ?? 99999)) || a.key.localeCompare(b.key));
      for (const mod of mods) {
        const row = document.createElement("tr");
        const cbCell = document.createElement("td");
        cbCell.className = "cb";
        const cb = document.createElement("input");
        cb.type = "checkbox";
        cb.checked = this.selection.has(mod.key);
        cb.addEventListener("change", () => this.toggle(mod.key, cb.checked));
        cbCell.append(cb);
        const nameCell = document.createElement("td");
        const name = document.createElement("strong");
        name.textContent = mod.name || mod.key;
        nameCell.append(name);
        if (mod.status && mod.status !== "active") {
          const badge = document.createElement("span");
          badge.className = "badge warn";
          badge.textContent = mod.status;
          nameCell.append(" ", badge);
        }
        const keyCell = document.createElement("td");
        keyCell.className = "key";
        keyCell.textContent = mod.key;
        const descCell = document.createElement("td");
        descCell.className = "desc";
        descCell.textContent = mod.description || "";
        const linkCell = document.createElement("td");
        linkCell.className = "link";
        const repoUrl = (mod.repo || "").replace(/\.git$/, "");
        if (/^https?:\/\//.test(repoUrl)) {
          const a = document.createElement("a");
          a.href = repoUrl;
          a.target = "_blank";
          a.rel = "noopener";
          a.textContent = "GitHub ↗";
          linkCell.append(a);
        }
        row.append(cbCell, nameCell, keyCell, descCell, linkCell);
        tbody.append(row);
      }
    }
    table.append(tbody);
    list.append(table);
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

// ---- Settings Preset tab ----
ConfigUI.preset = {
  meta: { name: "", description: "" },
  entries: [], // {file, key, value} — insertion order is export order

  parse(text) {
    const out = { name: "", description: "", entries: [] };
    let section = null;
    for (const raw of text.split("\n")) {
      const s = raw.trim();
      let m = s.match(/^#\s*CONFIG_NAME:\s*(.*)$/);
      if (m) { out.name = m[1].trim(); continue; }
      m = s.match(/^#\s*CONFIG_DESCRIPTION:\s*(.*)$/);
      if (m) { out.description = m[1].trim(); continue; }
      if (!s || s.startsWith("#")) continue;
      m = s.match(/^\[(.+)\]$/);
      if (m) { section = m[1]; continue; }
      const eq = s.indexOf("=");
      if (eq > 0) {
        out.entries.push({
          file: section || "worldserver.conf",
          key: s.slice(0, eq).trim(),
          value: s.slice(eq + 1).trim(),
        });
      }
    }
    return out;
  },

  serialize() {
    const lines = [
      `# CONFIG_NAME: ${this.meta.name}`,
      `# CONFIG_DESCRIPTION: ${this.meta.description}`,
      "",
    ];
    let current = null;
    for (const e of this.entries) {
      if (!e.key) continue;
      if (e.file !== current) {
        if (current !== null) lines.push("");
        lines.push(`[${e.file}]`);
        current = e.file;
      }
      lines.push(`${e.key} = ${e.value}`);
    }
    return lines.join("\n").replace(/\n+$/, "") + "\n";
  },

  groupOf(key) {
    if (key.startsWith("Rate.")) return "Rates";
    if (key.startsWith("AllowTwoSide.")) return "Cross-faction";
    if (key.startsWith("Death.") || key.startsWith("Corpse.")) return "Death & Corpse";
    if (key === "MaxPlayerLevel" || key.startsWith("GM.")) return "Player & GM";
    return "Other";
  },

  applyImport(parsed, sourceName) {
    this.meta = { name: parsed.name, description: parsed.description };
    this.entries = parsed.entries.map(e => ({ ...e }));
    document.getElementById("preset-cfgname").value = this.meta.name;
    document.getElementById("preset-cfgdesc").value = this.meta.description;
    if (sourceName) document.getElementById("preset-file").value = sourceName.replace(/\.conf$/, "");
    this.render();
    ConfigUI.setStatus(`Loaded ${this.entries.length} settings from ${sourceName || "import"}.`);
  },

  render() {
    const box = document.getElementById("preset-groups");
    box.textContent = "";
    const groups = new Map();
    this.entries.forEach((entry, i) => {
      const g = this.groupOf(entry.key || "");
      if (!groups.has(g)) groups.set(g, []);
      groups.get(g).push([entry, i]);
    });
    const order = ["Rates", "Player & GM", "Cross-faction", "Death & Corpse", "Other"];
    for (const g of order) {
      if (!groups.has(g)) continue;
      const wrap = document.createElement("div");
      wrap.className = "preset-group";
      const h = document.createElement("h3");
      h.textContent = g;
      wrap.append(h);
      for (const [entry, i] of groups.get(g)) {
        const row = document.createElement("div");
        row.className = "preset-row";
        const file = document.createElement("input");
        file.value = entry.file; file.title = "target file"; file.size = 14;
        file.addEventListener("input", () => { entry.file = file.value; });
        const k = document.createElement("input");
        k.className = "k"; k.value = entry.key; k.placeholder = "Setting.Key";
        k.addEventListener("change", () => { entry.key = k.value.trim(); this.render(); });
        const v = document.createElement("input");
        v.className = "v"; v.value = entry.value; v.placeholder = "value";
        v.addEventListener("input", () => { entry.value = v.value; });
        const del = document.createElement("button");
        del.textContent = "✕"; del.title = "remove";
        del.addEventListener("click", () => { this.entries.splice(i, 1); this.render(); });
        row.append(file, k, v, del);
        wrap.append(row);
      }
      box.append(wrap);
    }
  },
};

document.addEventListener("configui:ready", () => {
  const select = document.getElementById("preset-start");
  select.length = 1;
  for (const file of ConfigUI.data.index.presets) {
    select.append(new Option(file, file));
  }
});

document.getElementById("preset-start").addEventListener("change", async e => {
  if (!e.target.value) return;
  try {
    const text = await ConfigUI.fetchData("presets/" + e.target.value);
    ConfigUI.preset.applyImport(ConfigUI.preset.parse(text), e.target.value);
  } catch (err) {
    ConfigUI.setStatus(`Could not load ${e.target.value}: ${err.message}`, true);
  }
});

document.getElementById("preset-add-row").addEventListener("click", () => {
  ConfigUI.preset.entries.push({ file: "worldserver.conf", key: "", value: "" });
  ConfigUI.preset.render();
});

document.getElementById("preset-export").addEventListener("click", () => {
  const name = document.getElementById("preset-file").value.trim();
  if (!name || !ConfigUI.safeName(name)) {
    ConfigUI.setStatus("Preset file name is required and may only use letters, digits, dot, dash, underscore.", true);
    return;
  }
  ConfigUI.preset.meta.name = document.getElementById("preset-cfgname").value;
  ConfigUI.preset.meta.description = document.getElementById("preset-cfgdesc").value;
  ConfigUI.download(name + ".conf", ConfigUI.preset.serialize());
});

document.addEventListener("configui:import", e => {
  if (!e.detail.name.endsWith(".conf")) return;
  const parsed = ConfigUI.preset.parse(e.detail.text);
  if (!parsed.name && !parsed.description && parsed.entries.length === 0) {
    ConfigUI.setStatus(`Not a valid preset .conf (${e.detail.name}): no CONFIG_NAME/CONFIG_DESCRIPTION or settings found.`, true);
    return;
  }
  ConfigUI.preset.applyImport(parsed, e.detail.name);
});

// ---- .env Flags tab ----
ConfigUI.env = {
  parseModules(text) {
    const keys = new Set();
    for (const m of text.matchAll(/^\s*(MODULE_[A-Z0-9_]+)\s*=\s*1\s*$/gm)) keys.add(m[1]);
    return keys;
  },

  serialize() {
    const sel = ConfigUI.profile.selection;
    return ConfigUI.data.manifest.map(m => `${m.key}=${sel.has(m.key) ? 1 : 0}`).join("\n") + "\n";
  },

  render() {
    document.getElementById("env-output").value = this.serialize();
  },
};

document.addEventListener("configui:selection-changed", () => ConfigUI.env.render());
document.addEventListener("configui:ready", () => ConfigUI.env.render());

document.getElementById("env-copy").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(document.getElementById("env-output").value);
    ConfigUI.setStatus("Module flag block copied to clipboard.");
  } catch (e) {
    ConfigUI.setStatus("Clipboard blocked — select the text and copy manually.", true);
  }
});

document.addEventListener("configui:import", e => {
  const looksLikeEnv = e.detail.name === ".env" || e.detail.name.endsWith(".env")
    || (!e.detail.name.endsWith(".json") && !e.detail.name.endsWith(".conf")
        && /^\s*MODULE_[A-Z0-9_]+\s*=/m.test(e.detail.text));
  if (!looksLikeEnv) return;
  const keys = ConfigUI.env.parseModules(e.detail.text);
  ConfigUI.profile.applyImport(
    { modules: [...keys], label: "", description: "", order: 10000 },
    e.detail.name,
  );
  document.getElementById("profile-name").value = "";
  ConfigUI.emit("configui:selection-changed", {});
  ConfigUI.setStatus(`Selection set from ${e.detail.name}: ${keys.size} enabled modules.`);
});

ConfigUI.init();
