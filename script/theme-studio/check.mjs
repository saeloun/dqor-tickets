// Run with Node 22+: node script/theme-studio/check.mjs
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const source = await readFile(
  new URL("../../public/theme-studio/themes.js", import.meta.url),
  "utf8",
);
const { validate, defaults, ink } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
);
for (const key of ["__proto__", "constructor", "missing"])
  assert.equal(defaults(key).theme, "conference");
assert.deepEqual(validate(null), defaults());
const unsafe = validate({
  version: 1,
  theme: "__proto__",
  accent: "red; background:url(https://example.com)",
  surface: "#fff",
  font: "__proto__",
  sections: ["about", "about", "visit"],
  assets: {
    logo: "data:image/svg+xml;base64,PHN2Zz4=",
    cover: "https://example.com/tracker.png",
  },
  name: "a".repeat(100),
});
assert.equal(unsafe.accent, defaults().accent);
assert.equal(unsafe.surface, defaults().surface);
assert.equal(unsafe.font, defaults().font);
assert.deepEqual(unsafe.sections, defaults().sections);
assert.deepEqual(unsafe.assets, {});
assert.equal(unsafe.name.length, 70);
const changed = {
  ...defaults("campus"),
  sections: ["visit", "about", "programme"],
  accent: "#223344",
  assets: { favicon: "data:image/png;base64,aGVsbG8=" },
};
assert.deepEqual(validate(JSON.parse(JSON.stringify(changed))), changed);
// Sample the complete RGB cube at 17-step intervals: either text color must meet WCAG AA.
function luminance(hex) {
  const channels = hex
    .slice(1)
    .match(/../g)
    .map((x) => {
      const c = parseInt(x, 16) / 255;
      return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
    });
  return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
}
let colors = 0;
for (let r = 0; r <= 255; r += 17)
  for (let g = 0; g <= 255; g += 17)
    for (let b = 0; b <= 255; b += 17) {
      const hex =
        "#" + [r, g, b].map((x) => x.toString(16).padStart(2, "0")).join("");
      const l = luminance(hex),
        text = luminance(ink(hex));
      const ratio = (Math.max(l, text) + 0.05) / (Math.min(l, text) + 0.05);
      assert.ok(ratio >= 4.5, `${hex}: ${ratio}`);
      colors++;
    }
console.log(
  `PASS: invalid theme/schema/asset inputs rejected; draft round-trip preserved; ${colors} palette colors meet 4.5:1 foreground contrast.`,
);
