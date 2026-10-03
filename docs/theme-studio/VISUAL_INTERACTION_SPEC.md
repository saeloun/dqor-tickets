# DQOR visual and interaction spec

A shared language for calm organizer work and expressive event pages. Operational screens should make the next action obvious; event themes provide personality. This is an incremental specification, not a claim that every surface already implements it.

The forest palette below applies to organizer and scanner operations. The primary attendee experience is being refined separately around event artwork, restrained chrome and a single ticket action; do not apply operational styling wholesale to attendee pages.

## Foundations

| Token | Value / rule |
| --- | --- |
| Canvas / card | `#F6F5EF` / white |
| Main ink / muted ink | `#243024` / `#53634A` |
| Primary | `#334B28` with white text |
| Decorative border / control border | `#B6C2AB` / `#7A8972` |
| Spacing | 8px rhythm; 16px inline gap; 24px card padding |
| Shape | 12px cards; restrained 4px form-control corners |
| Type | System sans body, 16px minimum editable text; 14px labels, 13px supporting copy; Georgia/system serif display, 32–48px |
| Controls | 48×48 minimum target for key actions; text links in navigation get the same height; visible 3px focus ring |

Measured contrast: main ink/canvas **12.62:1**, primary/white **9.64:1**, muted ink/white **6.46:1**. Decorative separators need not look like interactive boundaries. Use the stronger control border for inputs. Text should meet 4.5:1; visible focus and meaningful control boundaries should meet 3:1 against their adjacent surface. Do not claim compliance from a palette alone.

## Keep the three identities

| Theme | Expression | Default accent / surface | Type |
| --- | --- | --- | --- |
| The Gathering | Conference; spacious, warm, conversational | `#803C35` / `#F5F0E7` | Editorial serif |
| The Movement | Marathon; energetic type and clear distances | `#D8F250` / `#142C27` | Bold modern sans |
| The Commons | Campus, literature, convention; paper and editorial hierarchy | `#754424` / `#F7EECF` | Editorial serif |

Retain existing original artwork and section rhythm. Derive foregrounds from chosen colors. The CTA's focus ring must contrast against the surrounding page, not inherit its opposite-color button text. Theme configuration must not recolor staff success/error states. No arbitrary CSS, scripts, remote fonts or imported client material.

## Journeys and state language

1. **Setup:** show the true sequence, not an artificial completion score. Branding: choose look → optional images → arrange → save → inspect saved draft. Free event: details → publish event → free tickets. A future local-time input must actually convert and validate; the present UTC form explicitly explains the conversion.
2. **Edit:** visible labels, short examples, optional fields marked as optional. Explain image defaults so an empty upload does not look broken. Preserve values, file choices and focus after errors. On phones, stack controls before truncating meaningful values.
3. **Save:** one underlying submit operation even when a sticky action repeats it. Disable conflicting edits during the request, announce its actual action, prevent duplicates, and never automatically retry an uncertain mutation.
4. **Preview:** label saved versus published state. Keep form edits in place. Show loading, a recoverable failure with Retry, and an always-reachable Back control. Escape/browser Back restore opener focus. A preview is not a publication.
5. **Confirm:** show the committed result, next action and relevant timestamp. Free tickets display event, attendee, number, date and timezone; explicitly say when no email is sent. Check-in uses text-labelled outcomes and a changed count, not color alone.

## Web and native agreement

Web supports 320px reflow, keyboard navigation, visible focus, reduced motion, and touch controls without hover dependence. Check screen-reader announcement order and browser zoom separately.

Foundation adopted the organizer tokens in its own layout. Android agreed to the palette, 8dp spacing, 12dp cards, 16sp body and 48dp controls; preserve 200% text, a reachable bottom scan/review action, and retained selections. Android review captures use a synthetic emulator test activity because the launcher is screenshot-protected. iOS received the same proposal; native screens are owned and verified by their respective teams. Use platform accessibility text scaling, not fixed-height text containers. Read-only admission/meal/party demos must stay explicitly labelled until their contracts exist.

## Boundaries

Browser-only theme drafts, server-saved DQOR configuration, free-event publication and native demo state are distinct. Preserve their labels. Shared private-response caching is a separate release gate owned by foundation PR169; authentication and `no-store` headers alone do not prevent a service worker from caching responses. No deployment or theme public activation is authorized by this spec.
