// Versioned, deliberately small integration boundary. No HTML, scripts or remote URLs.
export const fonts = {
  editorial: 'Georgia, "Times New Roman", serif',
  modern: "Arial, Helvetica, sans-serif",
  humanist: "Trebuchet MS, Arial, sans-serif",
};
export const themes = {
  conference: {
    name: "Deccan Queen on Rails",
    headline: "Good people.\nGreat conversations.",
    place: "Hyatt Regency · Pune",
    date: "08—11 OCTOBER 2026",
    accent: "#803c35",
    surface: "#f5f0e7",
    font: "editorial",
    category: "A GATHERING OF CURIOUS MINDS",
    intro:
      "Four days to exchange ideas, build something meaningful, and find your people. Come for the craft. Stay for the conversations.",
    sectionTitles: {
      about: "Better, together.",
      programme: "Make room for discovery.",
      visit: "Meet us in Pune.",
    },
    details: [
      "Thoughtful talks",
      "Hands-on workshops",
      "Connections that last",
    ],
    programme: [
      [
        "01 / LEARN",
        "Ideas worth taking home",
        "Fresh perspectives and honest conversations about the work we do.",
      ],
      [
        "02 / BUILD",
        "A little less theory",
        "Roll up your sleeves, work alongside peers, and try something new.",
      ],
      [
        "03 / CONNECT",
        "Your kind of people",
        "Unhurried breaks, shared tables, and room for the unexpected.",
      ],
    ],
  },
  marathon: {
    name: "Pune City Run",
    headline: "Your city.\nYour stride.",
    place: "Race village · Pune",
    date: "SUNDAY / 22 NOVEMBER 2026",
    accent: "#d8f250",
    surface: "#142c27",
    font: "modern",
    category: "EVERY PACE HAS A PLACE",
    intro:
      "From your first starting line to your next personal best. Take to the streets with a city that moves with you.",
    sectionTitles: {
      about: "Find your distance.",
      programme: "The morning is yours.",
      visit: "See you at the start.",
    },
    details: [
      "21.1 km · Half marathon",
      "10 km · City run",
      "5 km · Community run",
    ],
    programme: [
      [
        "05:00 / ARRIVE",
        "Find your rhythm",
        "Meet your running crew at the race village and get ready together.",
      ],
      [
        "06:00 / RUN",
        "Own the morning",
        "A city route, a shared goal, and encouragement at every turn.",
      ],
      [
        "09:00 / CELEBRATE",
        "Every finish counts",
        "Cool down, swap stories, and savour the moment you made it.",
      ],
    ],
  },
  campus: {
    name: "The Open Chapter",
    headline: "A world between\nthe lines.",
    place: "The campus lawns · Bengaluru",
    date: "12—13 DECEMBER 2026",
    accent: "#754424",
    surface: "#f7eecf",
    font: "editorial",
    category: "WORDS · ART · PEOPLE · POSSIBILITY",
    intro:
      "A weekend for open minds. Wander between stories, discover a new voice, and take part in conversations that stay with you.",
    sectionTitles: {
      about: "Follow your curiosity.",
      programme: "Turn a new page.",
      visit: "A place to belong.",
    },
    details: [
      "Stories & conversations",
      "Art & independent voices",
      "A shared campus",
    ],
    programme: [
      [
        "THE READING ROOM",
        "Stories out loud",
        "Meet new voices and revisit old favourites in intimate readings.",
      ],
      [
        "THE COMMON GROUND",
        "Ideas in company",
        "Join conversations across literature, culture, and everyday life.",
      ],
      [
        "THE MAKERS’ CORNER",
        "Make something of it",
        "Browse small presses, share your work, and leave with a new idea.",
      ],
    ],
  },
};
export const sectionNames = {
  about: "About the event",
  programme: "Programme",
  visit: "Venue & information",
};
export function defaults(theme = "conference") {
  const t = Object.hasOwn(themes, theme) ? themes[theme] : themes.conference;
  return {
    version: 1,
    theme: Object.hasOwn(themes, theme) ? theme : "conference",
    name: t.name,
    headline: t.headline,
    place: t.place,
    date: t.date,
    accent: t.accent,
    surface: t.surface,
    font: t.font,
    sections: Object.keys(sectionNames),
    assets: {},
  };
}
export function validate(raw, fallback = "conference") {
  const result = defaults(
    Object.hasOwn(themes, raw?.theme) ? raw.theme : fallback,
  );
  if (!raw || raw.version !== 1) return result;
  for (const [key, limit] of Object.entries({
    name: 70,
    headline: 100,
    place: 90,
    date: 70,
  }))
    if (typeof raw[key] === "string" && raw[key].trim())
      result[key] = raw[key].slice(0, limit);
  for (const key of ["accent", "surface"])
    if (/^#[\da-f]{6}$/i.test(raw[key])) result[key] = raw[key];
  if (Object.hasOwn(fonts, raw.font)) result.font = raw.font;
  if (
    Array.isArray(raw.sections) &&
    raw.sections.length === 3 &&
    new Set(raw.sections).size === 3 &&
    raw.sections.every((key) => Object.hasOwn(sectionNames, key))
  )
    result.sections = [...raw.sections];
  for (const key of ["logo", "cover", "favicon"]) {
    const value = raw.assets?.[key];
    if (
      typeof value === "string" &&
      value.length < 1500000 &&
      /^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(value)
    )
      result.assets[key] = value;
  }
  return result;
}
export function ink(hex) {
  const [r, g, b] = hex
    .slice(1)
    .match(/../g)
    .map((n) => {
      const v = parseInt(n, 16) / 255;
      return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
    });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.179 ? "#000000" : "#ffffff";
}
export const storageKey = (theme) => `dqor.theme-studio.v1.${theme}`;
