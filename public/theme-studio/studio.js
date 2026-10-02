import { defaults, validate, sectionNames, storageKey } from "./themes.js";
const $ = (id) => document.getElementById(id);
const initialTheme =
  new URLSearchParams(location.search).get("theme") || "conference";
let state = defaults(initialTheme),
  assetRevision = 0;
try {
  const preview = sessionStorage.getItem(`${storageKey(state.theme)}.preview`);
  if (preview) state = validate(JSON.parse(preview), state.theme);
} catch {
  /* A fresh draft remains available without storage. */
}
const inputs = {
  "event-name": "name",
  "event-tagline": "headline",
  "event-place": "place",
  "event-date": "date",
  accent: "accent",
  surface: "surface",
  font: "font",
};
function status(text) {
  $("status").textContent = text;
}
function updatePreview() {
  const safe = validate(state);
  $("preview").contentWindow.postMessage(
    { type: "dqor:theme-preview", state: safe },
    location.origin,
  );
  try {
    sessionStorage.setItem(
      `${storageKey(state.theme)}.preview`,
      JSON.stringify(safe),
    );
  } catch {
    /* Live preview remains usable without storage. */
  }
  $("browser-title").textContent = safe.name;
  $("favicon-preview").hidden = !safe.assets.favicon;
  $("favicon-placeholder").hidden = !!safe.assets.favicon;
  if (safe.assets.favicon) $("favicon-preview").src = safe.assets.favicon;
  else $("favicon-preview").removeAttribute("src");
  $("open-preview").href = `preview.html?theme=${state.theme}`;
}
function sectionOrder(focusKey, direction) {
  $("section-order").replaceChildren(
    ...state.sections.map((key, index) => {
      const row = document.createElement("li"),
        label = document.createElement("span");
      label.textContent = sectionNames[key];
      row.append(label);
      for (const [offset, symbol, name] of [
        [-1, "↑", "up"],
        [1, "↓", "down"],
      ]) {
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = symbol;
        button.setAttribute("aria-label", `Move ${sectionNames[key]} ${name}`);
        button.disabled =
          index + offset < 0 || index + offset >= state.sections.length;
        button.addEventListener("click", () => {
          [state.sections[index], state.sections[index + offset]] = [
            state.sections[index + offset],
            state.sections[index],
          ];
          sectionOrder(key, name);
          changed();
          status(`${sectionNames[key]} moved ${name} · unsaved browser draft`);
        });
        button.dataset.section = key;
        button.dataset.direction = name;
        row.append(button);
      }
      return row;
    }),
  );
  if (focusKey) {
    const target =
      [...$("section-order").querySelectorAll("button")].find(
        (button) =>
          button.dataset.section === focusKey &&
          button.dataset.direction === direction &&
          !button.disabled,
      ) ||
      [...$("section-order").querySelectorAll("button")].find(
        (button) => button.dataset.section === focusKey && !button.disabled,
      );
    target?.focus();
  }
}
function sync() {
  assetRevision++;
  for (const [id, key] of Object.entries(inputs)) $(id).value = state[key];
  for (const key of ["logo", "cover", "favicon"]) $(key).value = "";
  $("asset-status").textContent = Object.keys(state.assets).length
    ? "Custom assets are included in this working preview."
    : "";
  document
    .querySelectorAll("[data-theme]")
    .forEach((button) =>
      button.setAttribute("aria-pressed", button.dataset.theme === state.theme),
    );
  sectionOrder();
  updatePreview();
}
function changed() {
  status("Unsaved changes · browser preview only");
  updatePreview();
}
$("branding-form").addEventListener("submit", (event) =>
  event.preventDefault(),
);
for (const [id, key] of Object.entries(inputs))
  $(id).addEventListener("input", () => {
    state[key] = $(id).value;
    changed();
  });
document.querySelectorAll("[data-theme]").forEach((button) =>
  button.addEventListener("click", () => {
    // Retain each in-progress theme in memory; changing themes never overwrites saved drafts.
    working[state.theme] = structuredClone(state);
    state = working[button.dataset.theme] || defaults(button.dataset.theme);
    history.replaceState(null, "", `?theme=${state.theme}`);
    sync();
    status("Working preview · save to keep in this browser");
  }),
);
const working = {};
$("preview").addEventListener("load", updatePreview);
document.querySelectorAll("[data-size]").forEach((button) =>
  button.addEventListener("click", () => {
    document
      .querySelectorAll("[data-size]")
      .forEach((other) =>
        other.setAttribute("aria-pressed", String(other === button)),
      );
    document.querySelector(".preview-area").dataset.size = button.dataset.size;
  }),
);
for (const key of ["logo", "cover", "favicon"])
  $(key).addEventListener("change", async () => {
    const file = $(key).files[0],
      revision = assetRevision;
    if (!file) return;
    if (
      !["image/png", "image/jpeg", "image/webp"].includes(file.type) ||
      file.size > 1048576
    ) {
      $("asset-status").textContent =
        "Choose a PNG, JPEG or WebP image no larger than 1 MB.";
      $(key).value = "";
      return;
    }
    try {
      const data = await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = reject;
        reader.readAsDataURL(file);
      });
      const image = new Image();
      image.src = data;
      await image.decode();
      if (revision !== assetRevision) return;
      state.assets[key] = data;
      $("asset-status").textContent =
        `${key[0].toUpperCase() + key.slice(1)} added to local preview.`;
      changed();
    } catch {
      $("asset-status").textContent =
        "That file could not be read as an image. Please choose another.";
    }
  });
document.querySelectorAll("[data-remove]").forEach((button) =>
  button.addEventListener("click", () => {
    assetRevision++;
    delete state.assets[button.dataset.remove];
    $(button.dataset.remove).value = "";
    $("asset-status").textContent =
      `${button.dataset.remove} removed from preview.`;
    changed();
  }),
);
$("save").addEventListener("click", () => {
  if (!$("branding-form").reportValidity()) return;
  try {
    state = validate(state);
    localStorage.setItem(storageKey(state.theme), JSON.stringify(state));
    status("Saved in this browser · not published");
  } catch {
    status(
      "Draft could not be saved. Browser storage may be full or unavailable.",
    );
  }
});
$("restore").addEventListener("click", () => {
  try {
    const stored = localStorage.getItem(storageKey(state.theme));
    if (!stored) {
      status("No saved browser draft for this theme yet.");
      return;
    }
    state = validate(JSON.parse(stored), state.theme);
    sync();
    status("Saved browser draft restored · not published");
  } catch {
    status("Saved draft is unavailable. Your working preview is unchanged.");
  }
});
$("reset").addEventListener("click", () => {
  state = defaults(state.theme);
  sync();
  status("Working preview reset · saved draft kept");
});
sync();
