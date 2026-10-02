# DQOR attendee direction — Deccan After Hours

An artwork-first event experience with a matching pass. This is a runnable **browser-only design prototype**, not a registration endpoint, published event, account, or usable ticket. It makes no API requests and stores no attendee data. Sample names exist only in page memory and are rendered as text. Reload resets them.

Open `/theme-studio/attendee/` on the local Rails server. Alternatively serve `public/` with a local static server. `#pass` directly opens the sample pass. Existing three themes and persisted branding settings are unchanged by this increment.

## Reference evidence and original work

Inspected the public [Luma homepage](https://luma.com/) and [iiyon!! Run event](https://luma.com/jlnifjub) in Chromium at 1440px and 390px. The latter was a **past event**, not a live booking journey. Observed patterns: large square art, quiet navigation, compact date/place rows, one clear ticket panel, host identity secondary to the event. No signed-in Luma pass was accessed. The pass below is an original DQOR composition, not a reproduction of a Luma pass. No Luma logo, cover artwork, copy or code is included.

Original artwork was created using the built-in image-generation tool and saved to `public/theme-studio/attendee/deccan-cover.png`. It depicts an imaginary courtyard and stylized Deccan hills; it is not a real venue photograph. No private Billetto or Methodology material was used. All event/host/attendee content is illustrative.

Final artwork prompt: “Use case: stylized-concept. Asset type: original square cover illustration for a premium independent Pune India event called Deccan After Hours, a gathering of creative people. Create an editorial art print of Pune's Deccan hills at dusk, an intimate architectural courtyard in foreground, warm amber glowing windows and tiny human silhouettes gathered in conversation, moon above layered terracotta and deep aubergine hills, a single pale peach flowering branch framing one corner. Elegant tactile screenprint and gouache, sophisticated flat planes and subtle grain, dramatic composition, no clipart, no corporate gradients. Palette aubergine, rust, coral, amber, pale butter. Cover must feel like a collectible contemporary cultural festival poster. No text, letters, logos or watermark; typography will be added in HTML. Square, full bleed.”

## Annotated layout contract

| Region | Event detail | Pass |
| --- | --- | --- |
| 1. Navigation | Quiet DQOR identity, visible Design preview label, sample-pass shortcut. Native uses standard Back. | Back to event remains a 48px target. No redundant dashboard navigation. |
| 2. Art | Square cover; 20px desktop /16px phone radius. 440px desktop column, full content width on phone. Art supplies the color. | 172px cropped art strip on phone, 180px desktop. Same image, continuous event identity. |
| 3. Identity | Small category/location line; event title 58px desktop /46px phone with italic serif accent; host follows on phone. Long real titles must wrap. | Event title 34px; admission category and SAMPLE label precede it. Date/time/venue stay grouped. |
| 4. Logistics | Two restrained rows: date/time with explicit timezone, then venue. Avoid competing icon tiles and dense dashboards. | Guest name then credential area. Guest text wraps safely. No operational check-in action on attendee pass. |
| 5. Action | One 50px registration-preview button in a subtly bordered panel. Free entry and demo limitation visible. | No fake wallet, download, QR or offline-success actions. Real integrations require confirmed state and existing secure contracts. |
| 6. Supporting content | Short purpose paragraph, three-line evening schedule, essential access information. | One quiet closing line; nothing competes with credential legibility. |

Palette: canvas `#F8F5F2`, ink `#332631`, accent `#642F47`, muted `#71666D`, separator `#DDD4D8`, host tint `#F0DED5`. System sans for readable interface text; Georgia italic only for display emphasis. Native should use its platform serif equivalent and system dynamic text. Foreground has strong contrast on the warm canvas; decorative separators do not represent interactive boundaries.

Mobile gutters20px, content spacing24–32px, metadata gap16px, controls48–50px. No fixed-height text rows, horizontal carousels or hover-only actions. Native body/metadata text should follow platform accessibility sizes rather than copying small web eyebrow labels literally. At large text sizes, stack metadata and let the pass grow vertically.

## Registration and credential contract

The preview dialog has a clearly labelled fictional name, browser validation, Escape/close, retained in-memory text, and a sample-pass result. It never implies that the user is booked. Browser Back returns to the event. No localStorage, network mutation, analytics or external resource is used.

Foundation's real category-question form remains separately owned: event thumbnail and chosen category above one column of labelled questions; Optional explicitly stated; inline help/errors; preserve values on Back/failure; one explicit completion action. Organizer question ordering/preview retains the operational forest palette and shows draft/frozen schema status. This prototype does not implement dynamic question persistence.

Native real passes must preserve a **white QR field, required quiet zone and unfiltered code pixels**; artwork never sits behind or over a credential. Signed-ticket generation, screen protection, auth, offline policy and scanner behavior remain with their owners. Keep scanner outcome text and operational contrast independent of event colors. This prototype deliberately has no QR, so it does not establish scan reliability.

## Rendered review

1. **Event detail — visually inspected.** Art dominates the phone entry; identity, date/place and registration follow. [Phone](attendee/event-mobile.png), [desktop](attendee/event-desktop.png).
2. **Registration — visually inspected.** Native HTML dialog keeps background inactive; explicit preview copy, visible label and focus ring. [Phone](attendee/registration-mobile.png).
3. **Sample pass — visually inspected.** Related cover strip, event identity, guest and non-scannable placeholder. [Phone](attendee/pass-mobile.png), [desktop](attendee/pass-desktop.png).
4. **Navigation and input — browser checked.** Blank-name rejection, literal HTML-like name rendering, Escape restoring opener focus, browser Back, and event/pass widths320/390/768/1440. No horizontal overflow at those widths.
5. **Limits.** No VoiceOver/TalkBack or physical native device verification in this branch. No live RSVP, email, wallet, payment, map or QR tests are claimed. Native owners received the actual screenshots and implementation contract for their independently owned screens.

The related operational editor refinement is PR174. These attendee files can be reviewed independently; they do not alter organizer settings, shared routes, auth, native source, foundation schema, service worker or public-theme activation.
