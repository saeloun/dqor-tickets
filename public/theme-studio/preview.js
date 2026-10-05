import {
  defaults,
  validate,
  themes,
  fonts,
  ink,
  storageKey,
} from "./themes.js";
const $ = (id) => document.getElementById(id);
const theme = new URLSearchParams(location.search).get("theme") || "conference";
let state = defaults(theme);
try {
  const stored = sessionStorage.getItem(`${storageKey(state.theme)}.preview`);
  if (stored) state = validate(JSON.parse(stored), state.theme);
} catch {
  /* Storage is optional for the preview. */
}
function render(raw) {
  state = validate(raw);
  const content = themes[state.theme];
  document.body.dataset.theme = state.theme;
  const style = document.documentElement.style;
  for (const [key, value] of Object.entries({
    accent: state.accent,
    surface: state.surface,
    ink: ink(state.surface),
    "accent-ink": ink(state.accent),
    "display-font": fonts[state.font],
  }))
    style.setProperty(`--dq-${key}`, value);
  for (const [id, value] of Object.entries({
    "event-name": state.name,
    headline: state.headline,
    category: content.category,
    intro: content.intro,
    "event-date": state.date,
    "event-place": state.place,
    "visit-place": state.place,
    "visit-date": state.date,
    "footer-name": state.name,
  }))
    $(id).textContent = value;
  document.title = `${state.name} · Design preview`;
  document.querySelector(".event-footer a").href =
    `index.html?theme=${state.theme}`;
  for (const key of ["about", "programme", "visit"])
    document.querySelector(`#${key} h2`).textContent =
      content.sectionTitles[key];
  $("details").replaceChildren(
    ...content.details.map((text, index) => {
      const item = document.createElement("p");
      const number = document.createElement("span");
      number.textContent = `0${index + 1}`;
      const title = document.createElement("strong");
      title.textContent = text;
      item.append(number, title);
      return item;
    }),
  );
  $("programme-grid").replaceChildren(
    ...content.programme.map(([label, title, description]) => {
      const card = document.createElement("article");
      const eyebrow = document.createElement("p");
      eyebrow.className = "eyebrow";
      eyebrow.textContent = label;
      const heading = document.createElement("h3");
      heading.textContent = title;
      const body = document.createElement("p");
      body.textContent = description;
      card.append(eyebrow, heading, body);
      return card;
    }),
  );
  state.sections.forEach((key, index) => {
    $("sections").append($(key));
    $(key).querySelector(".eyebrow").textContent =
      `0${index + 1} / ${{ about: "THE EXPERIENCE", programme: "WHAT’S IN STORE", visit: "BE PART OF IT" }[key]}`;
  });
  for (const [key, id] of Object.entries({
    logo: "brand-logo",
    cover: "cover-image",
  })) {
    const img = $(id);
    img.hidden = !state.assets[key];
    if (state.assets[key]) img.src = state.assets[key];
    else img.removeAttribute("src");
  }
  $("brand-mark").hidden = !!state.assets.logo;
}
window.addEventListener("message", (event) => {
  if (
    event.origin === location.origin &&
    event.source === window.parent &&
    event.data?.type === "dqor:theme-preview"
  )
    render(event.data.state);
});
render(state);
