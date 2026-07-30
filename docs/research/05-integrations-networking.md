# Integrations & Conference Operations Research

Sources verified directly against the `rubyevents/rubyevents` GitHub repo (via `gh api`, main branch, checked 2026-07-29) and against public docs/repos for OSEM, Pretalx, Pretix, Tito, Indico, and FOSSASIA/Eventyay. Where a claim is inferred rather than confirmed from source, it is marked "(inferred)".

---

## Part 1 — RubyEvents.org export format

### 1.1 What RubyEvents.org is

`rubyevents/rubyevents` (https://github.com/rubyevents/rubyevents, homepage rubyevents.org) is an **open-source Rails app** ("On a mission to index all Ruby events") whose entire dataset lives as **YAML files committed to the repo**, not behind a write API. There is no REST/GraphQL endpoint for submitting a conference — the only contribution path is:

1. Fork the repo.
2. Add/edit YAML files under `data/`.
3. Run `bin/lint` (runs `standardrb`, `erblint`, JS `standard`, and **Yerba**, a YAML linter that validates every data file against a Ruby schema class in `app/schemas/`).
4. Run `bin/rails db:seed` (or `db:seed:event_series[<slug>]` / `db:seed:all`) to load it into a local Rails DB and preview on `bin/dev`.
5. Open a pull request.

This means **our platform's "export to RubyEvents" feature is a file-generator + PR-opener, not an API sync.** The realistic implementation is: generate the exact YAML tree below, then either (a) open a PR programmatically via the GitHub API using a bot/PAT with a fork of `rubyevents/rubyevents`, or (b) hand the organizer a downloadable zip/branch diff to PR manually. There is no known webhook or ingest endpoint to push to instead.

### 1.2 Directory structure

```
data/
  <series-slug>/                     # e.g. "railsconf", "rubyconf-india"
    series.yml                       # one per conference *series* (recurring brand)
    <series-slug>-<year>/            # one per *edition*, e.g. "railsconf-2024"
      event.yml
      cfp.yml
      involvements.yml
      schedule.yml
      sponsors.yml
      venue.yml
      videos.yml
  speakers.yml                       # ONE global file — master speaker directory for ALL events
  topics.yml                         # ONE global controlled-vocabulary list of talk topics
  featured_cities.yml                # global, unrelated to per-event data
```

Confirmed by listing `data/railsconf/` (21 `railsconf-YYYY` edition folders + `series.yml`) and `data/railsconf/railsconf-2024/` (all 7 files present). As of the check, `data/` contains **~220 conference/meetup series folders**.

Each schema is enforced by a matching Ruby class in `app/schemas/*.rb` (e.g. `EventSchema`, `SeriesSchema`, `VideoSchema`) using a `data_file "**/xxx.yml"` glob — these are the authoritative field lists; the `docs/ADDING_*.md` guides are the human-readable walkthroughs. Both were pulled and are the basis for the field tables below.

### 1.3 File-by-file schema

#### `data/<series>/series.yml` — the conference brand (`SeriesSchema`)

One per recurring conference/meetup group. Real example (RailsConf):

```yaml
---
id: "railsconf"
name: "RailsConf"
website: "https://railsconf.org/"
kind: "conference"
frequency: "yearly"
language: "English"
twitter: "railsconf"
ended: true
aliases:
  - Rails Conf
  - Rails Conference
youtube_channels:
  - id: "UCWnPjmqvljcafA0z2U1fwKQ"
    name: "confreaks"
    handle: "@confreaks"
    playlist_matcher: "rails"
```

| Field | Type | Notes |
|---|---|---|
| `id`, `name` | string | id matches folder name |
| `kind` | enum | `conference, meetup, retreat, hackathon, event, podcast, online, organisation, workshop` |
| `frequency` | enum | `yearly, monthly, weekly, irregular, biweekly, biyearly, quarterly` |
| `ended` | bool | series has stopped running |
| `default_country_code` | string | ISO code, optional |
| `language` | enum | from `Language.english_names` |
| `website, twitter, facebook, mastodon, bsky, github, linkedin, meetup, luma, guild, vimeo` | string | all optional social/links |
| `youtube_channels` | array of `{id, name, handle, playlist_matcher}` | `playlist_matcher` filters playlists when one channel hosts multiple series (e.g. Confreaks hosting both RailsConf and RubyConf) |
| `aliases` | array of string | alternate names |

#### `data/<series>/<edition>/event.yml` — one specific edition (`EventSchema`)

```yaml
---
id: "railsconf-2024"
title: "RailsConf 2024"
location: "Detroit, MI, United States"
timezone: "America/Detroit"
kind: "conference"
description: |-
  RailsConf, hosted by Ruby Central, is the world's largest and longest-running...
start_date: "2024-05-07"
end_date: "2024-05-09"
recordings_published_date: "2024-07-10"
year: 2024
playlist: "https://www.youtube.com/playlist?list=..."
website: "https://2024.railsconf.org"
banner_background: "#DB525A"
featured_background: "#231F20"
featured_color: "#FFFFFF"
coordinates:
  latitude: 42.3261
  longitude: -83.0571
```

Required: `id`, `title`, `kind` (enum `conference, meetup, retreat, hackathon, event, workshop`), `location`, `timezone` (must be a valid IANA identifier). Optional but commonly set: `start_date/end_date/pre_date` (`YYYY-MM-DD`), `status` (enum `cancelled, postponed, scheduled`), `hybrid` (bool), `last_edition` (bool), `tickets_url`, `website`, socials, and the three `*_background`/`*_color` CSS-color fields used for the site's card theming. `coordinates` is `any_of {latitude, longitude}` **or `false`** — online events set `location: "online"` and `coordinates: false`.

#### `data/<series>/<edition>/cfp.yml` — call for proposals (`CFPSchema`, array)

```yaml
---
- link: "https://sessionize.com/railsconf2024"
  open_date: "2024-01-24"
  close_date: "2024-02-13"
```
Fields: `link` (required), `name` (default "Call for Proposals"), `open_date`, `close_date`. Array because an event can run multiple CFPs (e.g. workshops CFP + talks CFP).

#### `data/<series>/<edition>/involvements.yml` — organizing team (`InvolvementSchema`, array)

```yaml
---
- name: "Organizer"
  users: []
  organisations:
    - Ruby Central
- name: "Co-Chair"
  users:
    - Ufuk Kayserilioglu
    - Andy Croll
```
Each entry: `name` (role label, free text — Organizer, Co-Chair, Volunteer, Program Committee member, etc.), `users` (array of speaker names, matched against `data/speakers.yml`), `organisations` (array of org names).

#### `data/<series>/<edition>/schedule.yml` — the grid (`ScheduleSchema`)

```yaml
days:
  - name: "Day 1"
    date: "2024-05-07"
    grid:
      - start_time: "08:30"
        end_time: "09:30"
        slots: 1
        items:
          - "Registration & Breakfast"
      - start_time: "09:30"
        end_time: "09:50"
        slots: 1
        items:
          - "Introduction"
      - start_time: "09:50"
        end_time: "10:50"
        slots: 1
        # no `items` — this slot is auto-filled from videos.yml, in chronological order
tracks:
  - name: "Supporter Talk"
    color: "#E1CD00"
    text_color: "#ffffff"     # optional
```

Key mechanic (from `docs/ADDING_SCHEDULES.md`, confirmed by structure): **a grid slot with no `items` key is a placeholder that gets auto-filled with talks from `videos.yml`, matched strictly in file order.** So `videos.yml` entries must be ordered chronologically to line up with the grid. Slots *with* `items` are non-talk activities (breaks, lunch, registration) and take either bare strings or `{title, description, speakers, track, room}` objects. `slots: N` sets how many parallel tracks/rooms that timeslot has. If multi-track, every talk in `videos.yml` for that slot needs a `track:` field that exactly string-matches a `tracks[].name`.

#### `data/<series>/<edition>/sponsors.yml` — sponsors by tier (`SponsorsSchema`, array wrapping `tiers`)

```yaml
---
- tiers:
    - name: "Platinum"
      description: "Top level sponsors with highest sponsorship tier."
      level: 1
      sponsors:
        - name: "Revela"
          website: "https://www.revela.co/"
          slug: "Revela"
          logo_url: "https://2024.railsconf.org/images/uploads/revela.png"
    - name: "Gold"
      level: 2
      sponsors:
        - name: "Shopify"
          website: "https://www.shopify.com/"
          slug: "Shopify"
          logo_url: "..."
```

Per-sponsor fields: `name`, `slug`, `website` (all **required**), `description`, `logo_url`, `badge` (optional — free-text special designation like "WiFi Sponsor", "Coffee Sponsor", "Diversity Sponsor"). Per-tier: `name`, `description`, `level` (int, lower = higher tier), `sponsors` (required array). Note this is **purely public-facing metadata** — no pricing, invoice, or payment status fields exist in this schema (see gap analysis in §1.6).

#### `data/<series>/<edition>/venue.yml` (`VenueSchema`)

```yaml
name: "Huntington Place"
address:
  street: "1 Washington Blvd"
  city: "Detroit"
  region: "Michigan"
  postal_code: "48226"
  country: "United States"
  country_code: "US"
  display: "1 Washington Blvd, Detroit, MI 48226, USA"
coordinates:
  latitude: 42.3261
  longitude: -83.0571
maps:
  google: "..."
  apple: "..."
  openstreetmap: "..."
hotels:
  - name: "Detroit Marriott at the Renaissance Center"
    kind: "Conference Hotel"
    address: { ... }
    coordinates: { ... }
```
Also supports optional `rooms[]` (`name, floor, capacity, instructions`), `spaces[]`, `accessibility {wheelchair, elevators, accessible_restrooms, notes}`, `nearby {public_transport, parking}`, `locations[]` for multi-venue events.

#### `data/<series>/<edition>/videos.yml` — the talks (`VideoSchema`, array)

This is the richest and most important file — it doubles as the **session/talk list**, whether or not a recording exists yet.

```yaml
- id: "youssef-boulkaid-railsconf-2024"
  title: "Ask your logs"
  raw_title: "RailsConf 2024 -  Ask your logs by Youssef Boulkaid"
  event_name: "RailsConf 2024"
  date: "2024-05-07"
  published_at: "2024-07-10T20:56:34Z"
  video_provider: "youtube"
  video_id: "y-VMajyrQnU"
  description: |-
    Logging is often an afterthought...
  speakers:
    - Youssef Boulkaid
  slides_url: "https://speakerdeck.com/..."
  track: "Supporter Talk"          # only needed for multi-track slots
  kind: "keynote"                  # optional; also: workshop, intro, lightning_talk, etc.
  alternative_recordings:
    - note: "Confreaks upload"
      video_provider: "youtube"
      video_id: "N6xn6KuxtKE"
  additional_resources:
    - name: "Companion repo"
      title: "..."
      type: "repo"
      url: "https://github.com/..."
```

Required: `id` (unique slug, convention `firstname-lastname-conf-year`), `date` (`YYYY-MM-DD`), and `speakers` **is functionally required** — per `docs/ADDING_VIDEOS.md`: *"videos without speakers won't display."* `video_provider` must be one of `Talk.video_providers.keys` minus `parent` (i.e. `youtube`, `vimeo`, `mp4`, `not_recorded`, etc.) — talks with no recording yet use `video_provider: "not_recorded"` and set `video_id` to the same string as `id`. When `video_provider: "youtube"`, `published_at` becomes required with pattern `YYYY-MM-DDTHH:MM:SSZ` and `video_id` must match an 11-char YouTube ID pattern. `talks:` (array of `SubVideoSchema`) supports panel discussions with sub-talks.

#### `data/speakers.yml` — global speaker directory (`SpeakerSchema`, one giant array, ~430 KB / thousands of entries)

```yaml
- name: "Aaron Patterson"
  github: "tenderlove"
  twitter: "tenderlove"
  mastodon: "https://mastodon.social/@tenderlove"
  bluesky: "tenderlove.dev"
  website: "https://tenderlovemaking.com/"
  speakerdeck: "tenderlove"
  slug: "aaron-patterson"
- name: "Abdelkader Boudih"
  github: "seuros"
  slug: "abdelkader-boudih"
  aliases:
    - name: 'Abdelkader "Seuros" Boudih'
      slug: "abdelkader-seuros-boudih"
```

Required: `name`, `slug`, `github` (a bare username, not a URL — validated by regex). Optional: `twitter`, `website`, `mastodon` (full profile URL), `bluesky` (handle), `linkedin` (username after `/in/`), `speakerdeck` (username), `aliases` (array of `{name, slug}`), `canonical_slug` (points a duplicate at the real profile).

**Critical identity-resolution rule** (confirmed via `docs/FIXING_PROFILE_NAMES.md`): **GitHub username is the canonical unique key for a speaker across the whole site.** Talk-to-speaker linking in `videos.yml` is done by **exact string match** of the `speakers:` name against a `name` or `aliases[].name` in `data/speakers.yml` — there is no ID reference, just literal name matching. This means our export must (a) guarantee the speaker name string in every `videos.yml`/`involvements.yml` entry is byte-identical to the corresponding `speakers.yml` entry, and (b) if a speaker already exists upstream under a different GitHub handle/name spelling, we should add an alias rather than a duplicate entry (RubyEvents' own contribution docs explicitly instruct this).

#### `data/topics.yml` — global flat list of talk-topic strings (controlled vocabulary, e.g. `"ActiveRecord"`, `"Accessibility (a11y)"`) used for tagging/browsing — not per-talk in the schema shown, but the master list contributors add to.

### 1.4 Validation & tooling our exporter should replicate

- `bin/lint` = `standardrb` + `erblint` (js `standard`) + **Yerba** YAML-schema validation against `app/schemas/*.rb`. Our exporter should validate against the same rules client-side (required fields, enums, date/regex patterns) before ever opening a PR, to avoid CI failures on the RubyEvents side.
- RubyEvents ships **Rails generators** to scaffold these files (`bin/rails g event`, `g schedule`, `g sponsors`) — our own export code can mirror their defaults (e.g. schedule generator auto-fills breakfast/lunch/closing party slots) to produce diffs that look "native" to RubyEvents maintainers reviewing the PR.
- Seeding order matters: series → event → (cfp, involvements, schedule, sponsors, venue) → videos, and `bin/rails db:seed:event_series[<slug>]` reloads just one series — useful if we ever run a local RubyEvents fork ourselves for pre-flight testing.

### 1.5 What our platform needs to generate to contribute a conference

For each conference we want to publish/sync to RubyEvents, generate this tree and PR it as a unit:

```
data/<our-slug>/series.yml                       (once, first time only)
data/<our-slug>/<our-slug>-<year>/event.yml
data/<our-slug>/<our-slug>-<year>/cfp.yml
data/<our-slug>/<our-slug>-<year>/involvements.yml
data/<our-slug>/<our-slug>-<year>/venue.yml
data/<our-slug>/<our-slug>-<year>/sponsors.yml
data/<our-slug>/<our-slug>-<year>/schedule.yml
data/<our-slug>/<our-slug>-<year>/videos.yml
# + PATCH (not overwrite) to the global data/speakers.yml — append-only, dedup by github handle
```

Field mapping guidance for our internal model → RubyEvents (see Part 2 entity names below):
- `Conference` (series-level fields: name/website/socials) → `series.yml`
- `ConferenceEdition`/`Event` → `event.yml` + `venue.yml`
- `Sponsor` + `SponsorshipTier` → `sponsors.yml` tiers/sponsors (name/website/logo/slug/badge only — **strip all pricing/invoice data**, RubyEvents has no such fields)
- `Session`/`Talk` + `Speaker` + `Schedule`/`TimeSlot` → `videos.yml` (+ `schedule.yml` grid, matched by chronological order and, if multitrack, `track` string match)
- `Speaker` profile → append/merge into global `speakers.yml`, matched/deduped by GitHub handle
- Organizing team roles → `involvements.yml`

### 1.6 Gaps / things RubyEvents does NOT model (so export is necessarily lossy)

RubyEvents is a **public archive of talks/recordings + light event metadata**, not an operations platform. It has no concept of: attendee registration or tickets, custom attendee questions, sponsor payments/invoices, coupon codes, or attendee networking. Our export is one-way (operational data → public archive metadata) and should only ever push the subset of fields listed above — never attempt to push registration/payment/networking data there, and never treat a successful RubyEvents PR merge as confirmation of anything beyond "our public talk/sponsor/schedule listing is now indexed."

---

## Part 2 — Conference operations feature set & data model

This section draws on OSS precedent, cross-checked against real code where possible. **OSEM** (`openSUSE/osem`, Ruby on Rails, powers openSUSE Conference/ownCloud Conference) is the most directly relevant reference since it's the same stack — its actual `app/models/*.rb` files (pulled from GitHub) are cited by name below as concrete precedent for join-table and state-machine patterns. **Pretalx** (Django, CfP/scheduling for hundreds of Python/tech conferences) and **Pretix** (Django, ticketing used by many of the same conferences, and — notably — actually used by RailsConf 2024 per its own `sponsors.yml` sponsor list mentioning Tito) round out the CfP/ticketing side. **Tito** and commercial networking apps (Brella, Swapcard, Whova) are referenced for the networking/coupon feature *shape* only — no OSS reference implementation of attendee-matchmaking was found; that piece should be designed fresh.

### 2.1 Sessions/Talks + personal schedule/agenda builder

**Entities**
- `Session` (talk/workshop/keynote/panel/lightning-talk): title, abstract, description, `session_type` (enum), track, difficulty_level, duration, state (`submitted → accepted/rejected → confirmed → withdrawn/cancelled`, cf. OSEM `Event#state_machine`), max_attendees (optional cap for workshops), room, start_time, end_time.
- `Track`: name, color, text_color (RubyEvents' own `schedule.yml` `tracks[]` shape is a fine internal model too — reuse it).
- `Room`/`Venue` — capacity, floor, accessibility notes (mirrors RubyEvents `venue.yml` `rooms[]`/`accessibility{}`).
- `ScheduleSlot` — start/end time, `slots` (parallel-track count) — again, RubyEvents' grid model is directly reusable internally, which also minimizes export-mapping work later.
- `SessionSpeaker` join (see §2.2) — many-to-many, ordered (primary speaker first).

**Attendee-facing (personal agenda)**
- `SavedSession` / `AgendaItem` join table: `attendee_id, session_id, created_at`. This is exactly OSEM's `EventsRegistration` (`belongs_to :registration; belongs_to :event`, unique on `[event, registration]`) — a simple many-to-many "I'm planning to attend this" record, distinct from actual conference registration.
- Personal-agenda view = attendee's sessions joined + rendered against the schedule grid.
- **Conflict detection**: flag when two saved sessions overlap in time (client-side or a cheap query at save-time).
- **Calendar export**: per-attendee `.ics` feed (all their saved sessions) and per-conference full-schedule `.ics`/RSS (Pretalx explicitly offers an RSS/changelog feed of schedule changes — worth matching for re-published schedules).
- **Reminders**: "session starts in 10 minutes" push/email — ties into §2.7's scheduled-job infrastructure.
- Optional: capacity-limited sessions (workshops) — OSEM's `Event#registration_possible?` checks `registrations.count < max_attendees`; same pattern applies to `AgendaItem` counts if we cap workshop RSVPs.

### 2.2 Speaker management (separate from attendees)

Speakers should be a **role/profile attached to a Person**, not a separate user class — a person can be both attendee and speaker (and organizer). Model this the way OSEM does it: a single `User`/`Person`, plus a role-tagged join.

- `SpeakerProfile`: bio, headshot, company, title, pronouns (optional), and the exact social-link set RubyEvents' `SpeakerSchema` uses — `github` (bare username, validated), `twitter`, `website`, `mastodon` (full URL), `bluesky` (handle), `linkedin` (username), `speakerdeck` (username). Matching these fields 1:1 to RubyEvents' schema makes the export in Part 1 nearly free.
- `SessionSpeaker` join with `role` enum: `speaker | submitter | co-speaker | moderator` — directly mirrors OSEM's `EventUser.ROLES = [Speaker, Submitter, Moderator]` and its `event_role`-scoped associations (`speaker_event_users`, `submitter_event_user`).
- **CFP/submission workflow**: `submitted → under_review → accepted/rejected → confirmed → withdrawn/cancelled`, modeled as a state machine (OSEM uses the `state_machine` gem on `Event` with exactly this transition set, plus `on_transition` hooks that fire acceptance/rejection emails — good template for our workflow + notification hooks).
- **Free speaker ticket codes**: on transition to `confirmed`, auto-generate a single-use, zero-price `CouponCode` (see §2.6) scoped to the "Speaker" ticket type and email it to the speaker — this is the Pretix "voucher" pattern (*"send voucher codes to invited speakers which will grant them access to a specialized type of ticket"*; a product can be flagged "only purchasable via voucher").
- **Speaker availability** (optional, higher-value add): let speakers mark blackout times during the event so the scheduler can warn on conflicts — a documented Pretalx feature (*"speakers submit their availability... pretalx will warn you when talks are scheduled in conflict"*).
- **Speaker communications**: templated, merge-field emails at each state transition (invite, acceptance, rejection, reminder-to-confirm, day-before-your-talk reminder) — Pretalx explicitly queues these in an editable outbox before sending; OSEM's `EmailSettings#generate_event_mail` + `parse_template` (`{eventtitle}`, `{proposalslink}`, etc.) is a simpler, directly-portable version of the same idea (see §2.7).

### 2.3 Sponsor management + tiers + payments/invoices

- `SponsorshipTier`: name, description, `level`/rank (int, lower = higher), price (money), max_sponsor_slots (optional), benefits (rich text or structured perks list e.g. `booth: true, tickets_included: 4, logo_placement: "homepage+banner"`). OSEM's `SponsorshipLevel` (`belongs_to :conference`, `acts_as_list scope: :conference`, `has_many :sponsors`) is the direct precedent for ordered tiers per-event.
- `Sponsor`: name, slug, website_url, logo (upload), description, badge (free-text special designation, e.g. "WiFi Sponsor" — matches RubyEvents' own `badge` field, so this maps straight through on export), primary contact name/email, `sponsorship_tier_id`. OSEM's `Sponsor` model (`belongs_to :sponsorship_level`, `mount_uploader :picture`) is the minimal shape; our version needs the commercial fields RubyEvents deliberately omits.
- `SponsorOrder`/`Agreement`: sponsor_id, tier_id, amount, currency, status (`pending → invoiced → paid → overdue/cancelled`), signed_at, notes.
- `Invoice`: number, sponsor_order_id, line items, issue/due dates, PDF, status — standard invoicing entity; wire to whatever payment rails the platform already integrates (Razorpay/Stripe) for `Payment` records (method, amount, date, provider reference, reconciliation status).
- Optional: `Booth`/exhibitor entity distinct from sponsorship tier (some sponsors get expo-floor booths as a perk) — OSEM models this as its own `Booth` + `BoothRequest` (role-tagged join: submitter/responsible) with its own accept/reject state machine, useful if the platform later supports an expo hall.
- **Export boundary**: only `name, website, logo, slug, badge, tier.name, tier.level, tier.description` ever leave the building toward RubyEvents — no `SponsorOrder`/`Invoice`/`Payment` data crosses that boundary (see §1.6).

### 2.4 Attendee networking

No strong OSS reference implementation was found (Brella/Swapcard/Whova/Grip are the commercial state of the art here and are all closed-source) — this section is a from-scratch design informed by their documented feature shape plus our own privacy defaults.

- `AttendeeProfile`: `visible_in_directory` (opt-in, default **off**), company, role/title, interests/tags (reuse the RubyEvents `topics.yml` controlled vocabulary as a shared tag source — free synergy with Part 1), "what I'm looking for" free text, avatar.
- `Connection`: requester_id, recipient_id, status (`pending → accepted/declined`), created_at — simple LinkedIn-style mutual-connection request, not a public follow graph.
- `Conversation`/`Message`: attach to an accepted `Connection`; keep v1 to basic 1:1 text messages (no threads/reactions/read-receipts needed initially) — matches the brief's "messaging basics" scope.
- "People to meet" suggestions for v1: **simple tag-overlap ranking** (shared interests/topics, shared sessions saved, same company/role complementarity) rather than AI matchmaking — cheap, explainable, and avoids the black-box feel of commercial tools; can be upgraded later.
- Optional `MeetingSlot`: proposed_time, location/virtual-link, status — a lightweight 1:1 scheduling object for attendees who accept a connection and want to book time, mirroring commercial apps' "request a meeting" flow but without calendar-provider integration in v1.
- Privacy/safety must-haves regardless of scope: opt-in-only directory visibility, block/report on a connection or message, and an org-level kill switch to disable networking entirely for events that don't want it.

### 2.5 Custom attendee questions / requirements + CSV export

Model as a small EAV-style question bank, directly modeled on OSEM's real implementation (`Question` → `QuestionType`, `Answer`, and a `Qanswer` join that connects a `(question, answer)` pair to one or more `registrations`):

- `CustomQuestion`: label, `question_type` (enum: `text, single_select, multi_select, boolean, number`), options (for select types), required (bool), scope (`applies_to: all_attendees | ticket_type | speakers_only`), sort_order, active (bool), conference_id (reusable question bank across editions, like OSEM's `has_and_belongs_to_many :conferences` on `Question`).
- `AttendeeResponse` (simpler than OSEM's answer/qanswer indirection, since our answers don't need to be globally deduplicated the way OSEM's are): attendee_id, custom_question_id, value (text) or `selected_option_ids` (array, for multi-select).
- **Ship built-in question templates** organizers can one-click enable rather than build from scratch, covering the brief's explicit list: dietary restrictions/allergies, t-shirt size, accessibility/mobility needs, additional space or equipment requirements, emergency contact, pronouns, first-time-attendee flag.
- **CSV export**: one row per attendee, one column per active `CustomQuestion` (dynamically generated — not a fixed schema), plus core attendee fields (name, email, ticket type, order status, speaker/organizer flags, connection opt-in status). Support filtered exports (by ticket type, by "has dietary requirement," by speaker-only, by sponsor-code redeemed) — this is standard practice across every commercial platform reviewed (Eventzilla, The Events Calendar, Cvent all expose exactly this "export attendees with all custom-field answers as CSV" capability) and should be considered table-stakes, not a stretch feature.

### 2.6 Coupon codes / free-speaker codes / discount tiers

Follow Pretix's explicit **two-concept split**, which cleanly maps to our two real use cases:

1. **Discount** — automatic, public, rule-based (e.g. "10% off if buying 3+ tickets," early-bird pricing by date). No code entry required; applies to anyone matching the condition.
2. **Voucher/CouponCode** — a specific code, held by specific people, redeemed manually at checkout. This is the vehicle for: speaker free tickets, sponsor-allocated comp tickets, press passes, community-partner discounts.

`CouponCode` entity: code (unique, generatable or custom), `discount_type` (`percentage | fixed_amount | free`), `value`, `applies_to` (specific ticket type(s) or "any"), `max_redemptions` (int or unlimited), `redemptions_count`, `single_use_per_email` (bool), `expires_at`, `restricted_ticket_unlock` (bool — Pretix's "product can only be bought using a voucher" flag, useful for hiding a Speaker-tier ticket entirely from public sale), `issued_to` (optional — email/speaker_id/sponsor_id for traceability), `notes`.

- **Auto-issued speaker codes**: generated on CFP-acceptance state transition (§2.2), `discount_type: free`, `restricted_ticket_unlock: true`, `max_redemptions: 1`, emailed automatically via the acceptance email template (§2.7).
- **Sponsor comp codes**: N free/discounted codes issued per `SponsorOrder` based on the tier's benefits (e.g. "Gold tier includes 4 comp tickets") — generate in bulk, sponsor distributes to their own team.
- Admin needs: bulk-generate a batch of N codes at once (Tito and Pretix both support this), CSV export of all codes + redemption status, and a redemption audit trail (who/when) for reconciliation against sponsor agreements.

### 2.7 Follow-up / reminder email sequences (no custom templates needed now)

Scope explicitly excludes a full drip-campaign template builder — instead, ship a small set of **predefined trigger points** with merge-field bodies, closely modeled on OSEM's real (if minimal) implementation: its `EmailSettings` model has boolean flags per trigger (`send_on_registration?`, `send_on_accepted`, `send_on_rejected`, `send_on_confirmed_without_registration?`) each paired with an editable `_subject`/`_body`, and a `parse_template` method that does plain `{placeholder}` substitution (`{name}`, `{eventtitle}`, `{conference_start_date}`, `{registrationlink}`, `{schedule_link}`, etc.) — fired via `Mailbot.xxx_mail(...).deliver_later` (ActiveJob-backed, async).

Recommended trigger set (`EmailSequenceStep` entity: `trigger_type`, `offset`, `subject`, `body`, `enabled`):

| trigger_type | typical offset | purpose |
|---|---|---|
| `on_registration` | immediate | registration confirmation |
| `on_ticket_purchase` | immediate | order receipt |
| `on_cfp_submit` | immediate | "we got your talk" |
| `on_cfp_accept` / `on_cfp_reject` | immediate | decision + (if accepted) speaker ticket code |
| `relative_to_event_start` | e.g. `-14.days`, `-1.day` | logistics reminder, what-to-bring, schedule link |
| `on_event_end` (`relative_to_event_end`) | `+1.day` | thank-you + feedback survey link |
| `sponsor_thank_you` | `+3.days` post-event | sponsor-specific wrap-up (attendee stats, photos) |

Implementation: relative-offset triggers are scheduled jobs (Sidekiq/ActiveJob, `perform_at(event.start_date - offset)`), immediate triggers fire synchronously off model callbacks/state transitions exactly like OSEM's `after_create :send_registration_mail` and `on_transition: :process_acceptance/:process_rejection` hooks. Keep the merge-field system (no rich template engine needed yet) — it is enough to cover 100% of what's in scope.

---

## Summary of new entities this feature set introduces

Beyond whatever `Conference`/`Attendee`/`Ticket` core already exists, the above implies roughly: `Session`, `Track`, `Room`, `AgendaItem` (saved session), `SpeakerProfile`, `SessionSpeaker` (role join), `SponsorshipTier`, `Sponsor`, `SponsorOrder`, `Invoice`, `Payment`, `Booth` (optional), `AttendeeProfile` (networking), `Connection`, `Message`, `MeetingSlot` (optional), `CustomQuestion`, `AttendeeResponse`, `CouponCode`, `EmailSequenceStep`.
