# Sexey's School — Brand Rules for the Music Dept Booking System

These rules apply to every client-facing part of the system: the booking site (`index.html`), the foyer TV board (`display.html`), emails (`supabase/functions/band-invite-email`), and anything new. They are taken from the live front end in GitHub (`OMHMus/Music-Department-Booking-System`) and checked against the official crest artwork. If code and this document ever disagree, fix one so they match again — don't let them drift.

---

## 1. Core identity

| Element | Rule |
|---|---|
| Name | Always **Sexey's School** (straight or curly apostrophe, never "Sexeys"). Department: **Music Department**. Product: **Practice Room Booking** (site title "Sexey's Practice Rooms"). |
| Brand colours | **Maroon `#8B292B`** and **Gold `#C8A877`** — sampled from the crest (gold reads `#C8A876` in the artwork; use `#C8A877` in code). |
| Tone | Warm, formal, traditional (est. 1891) — but plain and friendly in pupil-facing text. Short sentences, British English (colour, centre, organise), 24-hour times with an en dash: `11:05–11:25`. |

---

## 2. Logo & crest

Assets live in `/assets` in the repo. The full portrait logo (`SEXEYS_SCHOOL_LOGO_PORTRAIT.png/.jpg`) is in the project files.

| File | Size | Use |
|---|---|---|
| `logo.png` | 300×318 | Full portrait lockup (crest + SEXEY'S + SCHOOL). Login screen only, ~150px tall. |
| `crest.png` | 140×153 | Shield alone. Header lockup (58px tall), formal card headers (52px), TV header (108px). |
| `wordmark.png` | 440×169 | "SEXEY'S SCHOOL" text. Paired with the crest in the header (42px tall). |
| `favicon.png` | 59×64 | Browser tab icon. |

**Do**
- Keep the crest and wordmark in their original colours on white or very light backgrounds.
- On maroon backgrounds, use the crest alone (the gold border carries it) — never the maroon wordmark.
- Give the logo clear space at least equal to the height of the "S" in SCHOOL.
- Mark decorative crest images `alt=""`; give the wordmark `alt="Sexey's School"`.

**Don't**
- Recolour, stretch, rotate, outline or add effects (the TV board's soft drop shadow on maroon is the only exception).
- Recreate the crest in CSS/SVG or type out the wordmark in a font as a substitute, except on the TV board where Cinzel text is used at large size.
- Place the logo on busy images or on the gold colour.

---

## 3. Colour

All colours are CSS custom properties on `:root`. **Always use the variable, never a raw hex**, so dark mode works. (The only raw hex allowed is in HTML emails, where variables aren't supported.)

### Brand

| Token | Light | Use |
|---|---|---|
| `--maroon` | `#8B292B` | Primary buttons, selected/own bookings, active tab, header band, badges, progress fills, checkbox accent. `theme-color` meta. |
| `--maroon-deep` | `#6E1F21` | Hover state for maroon; bottom of the header gradient. |
| `--maroon-ink` | `#4A1416` | TV board only: page surround, room names, text on gold. |
| `--gold` | `#C8A877` | **Lines and accents only**: header underline (3px), focus ring, borders of free slots / formal cards / outline buttons. |
| `--gold-ink` | `#86672F` (dark `#D9BE8C`) | Gold-coloured **text**: capacity labels, slot names, numbered terms. |
| Gold light | `#E9D6B3` | Eyebrow text on maroon. (`#F1E3CC` for secondary text on selected maroon slots.) |
| `--soft` | `#F4ECDD` (dark `#33291C`) | Hover background, "current step", quota-full, waiting pill. |

### Neutrals

| Token | Light | Dark | Use |
|---|---|---|---|
| `--bg` | `#F6F3EF` | `#170F10` | Page background, inputs. Warm off-white — never pure grey. |
| `--card` / `--paper` | `#FFFFFF` | `#221819` | Cards, header bar. |
| `--ink` | `#2B1B1C` | `#F2EAE4` | Body text. Warm near-black, never `#000`. |
| `--mut` | `#6F5E5D` | `#B5A5A1` | Secondary text, hints, footer. |
| `--line` | `#E4DAD1` | `#3A2B2C` | Borders and dividers. |
| `--acc-text` | `#8B292B` | `#E6A79F` | Headings and maroon-coloured text (lightens in dark mode for contrast). |
| `--shut` / `--shut-ink` | `#EEE8E2` / `#857774` | `#2C2122` / `#9C8B88` | Closed or full slots (disabled). |

### Status

| Token | Light | Use |
|---|---|---|
| `--ok-bg` / `--ok-ink` | `#E3F1E7` / `#25573A` | Success messages, "Free" text, confirmed pills, completed steps. |
| `--bad-bg` / `--bad` | `#FBE5E2` / `#A3271F` | Errors, cancel/destructive buttons. |

Green is the only non-brand hue allowed, and only for "available / success". Red errors use a brighter red than maroon so they're never confused with the brand.

### Contrast (checked)

| Pair | Ratio | Verdict |
|---|---|---|
| White on maroon | 8.6 : 1 | ✅ Any size |
| `#E9D6B3` on maroon | 6.0 : 1 | ✅ |
| Maroon on `--bg` | 7.8 : 1 | ✅ |
| `--ink` on `--bg` | 14.9 : 1 | ✅ |
| `--mut` on `--bg` | 5.5 : 1 | ✅ |
| `--gold-ink` on white | 5.3 : 1 | ✅ |
| `--maroon-ink` on gold | 6.7 : 1 | ✅ |
| **Gold `#C8A877` on white** | **2.3 : 1** | ❌ Never use gold for text on light backgrounds — use `--gold-ink`. |
| `--gold-ink` on `--soft` | 4.5 : 1 | ⚠️ Borderline. Fine at 14px+ bold; the 11.5px "waiting" pill is a known edge case. |
| `--shut-ink` on `--shut` | 3.5 : 1 | Acceptable only because these slots are disabled. |

New colour pairings must reach **4.5 : 1** for normal text (WCAG AA).

---

## 4. Typography

Loaded from Google Fonts:
`Cinzel:wght@500;600` and `Montserrat:wght@400;500;600;700` (TV board also loads Cinzel 700 and Montserrat 800).

| Token | Stack | Use |
|---|---|---|
| `--f-display` | `"Cinzel","Trajan Pro",Georgia,serif` | Headings (h1–h3), the selected date, fieldset legends, numbered terms, the signature field. Cinzel is the closest web font to the wordmark's classical capitals. |
| `--f-ui` | `"Montserrat","Gotham","Helvetica Neue",Arial,sans-serif` | Everything else. Montserrat matches the geometric "SCHOOL" lettering. |

| Style | Spec |
|---|---|
| Body | 15px / 1.5, Montserrat 400 |
| Page title (h1) | Cinzel 600, `clamp(24px,4vw,32px)`, letter-spacing .02em, white on maroon band |
| h2 / h3 | Cinzel 600, 19px / 16px, `--acc-text`, letter-spacing .02em, `text-wrap:balance` |
| Eyebrow | 11–11.5px, UPPERCASE, letter-spacing .14–.16em, weight 600 |
| Labels | 13px, weight 600 |
| Buttons | 14px, weight 600 |
| Small labels / badges | 10.5–11.5px, weight 600–700, UPPERCASE with letter-spacing .08–.1em |
| Times & counts | `font-variant-numeric: tabular-nums` |

Cinzel is for short display text only — never paragraphs, buttons or form text. Emails fall back to Georgia (headings) and Helvetica/Arial (body).

---

## 5. Layout & shape

| Element | Rule |
|---|---|
| Page width | `.wrap` max 66rem, 16px side gutter. No horizontal scroll at phone width. |
| Header | White bar with crest + wordmark, **3px gold bottom border**, then a maroon gradient band (`--maroon` → `--maroon-deep`) with eyebrow "Music Department" and the page h1. |
| Cards | `--card`, 1px `--line` border, radius 12px, padding 18px, soft warm shadow `--shadow`. |
| Formal cards | (Induction, agreement, confirm booking) 1.5px gold border, maroon header strip with 3px gold underline, eyebrow + white h2/h3, crest optional at 52px. |
| Radii | Buttons/pills/badges: 999px. Cards: 12px. Slots/messages: 10px. Inputs: 8px. |
| Spacing | Gaps of 6, 8, 10, 12, 14, 16px; 16px between cards. |
| Footer | Centred, 12.5px, `--mut`: "Sexey's School Music Department · Problems with a booking? Speak to a member of the Music staff." |

---

## 6. Components

**Buttons** (pill-shaped, 999px radius)
- Primary: maroon fill, white text → hover `--maroon-deep`.
- Secondary (`.alt`): card fill, `--line` border → hover gold border + `--soft`.
- Destructive (`.bad`): transparent, red border and text → hover red fill, white text.
- On the white header (Log out): white fill, maroon text, gold border.
- Icon buttons (day arrows): 40×40 circle.

**Inputs** — 1.5px `--line` border, radius 8px, `--bg` fill. Focus: gold border + `0 0 0 3px rgba(200,168,119,.3)` glow. Checkboxes use `accent-color: var(--maroon)`.

**Focus** — every interactive element shows `outline: 3px solid var(--gold); outline-offset: 2px` on `:focus-visible`. Never remove it.

**Tabs** — transparent muted pills; hover `--soft`; active is maroon fill + white.

**Booking slots** — the core visual language, kept identical on the site, TV board and legend:
| State | Look |
|---|---|
| Free | White, **gold** border, gold-ink name, green "Free" |
| Selected / mine | **Maroon** fill, white text, `#F1E3CC` secondary |
| Closed / full | `--shut` fill, no border, `--shut-ink` text (TV: diagonal stripes) |
| Past (TV) | Faded to ~38% opacity |
| Current session (TV) | 6px gold outline |

**Messages** — 4px left border; green for success, red for errors; `role="status"`.

**Pills & badges** — badge: maroon, white, uppercase 10.5px. Status pills: green (confirmed), soft/gold-ink (waiting). Chips: green / red.

**Steps** — numbered circles; current step maroon circle on `--soft`; completed shows ✓ in green.

---

## 7. Dark mode, motion & print

- Dark mode via `@media (prefers-color-scheme: dark)` redefining the tokens above. Maroon and gold stay the same; text, surfaces and `--acc-text` / `--gold-ink` lighten. Any new token must get a dark value.
- Transitions only on button background/border (.12s), inside `prefers-reduced-motion: no-preference`.
- Print hides account controls, the maroon band, tabs, steps, action buttons, footer and messages; cards lose their shadow.

---

## 8. Channel-specific notes

**Foyer TV board (`display.html`)** — fixed 1920×1080 stage scaled to fit; maroon gradient header with 6px gold underline; Cinzel room and column names; large Montserrat 800 names. Text sizes are 3–4× the site's. Session times in `SESS` must match `SN` in `index.html`.

**Emails** — table layout, inline styles, raw hex values: page `#F6F3EF`, card white with `#E4DAD1` border and 12px radius, maroon header with 3px gold underline, `#E9D6B3` eyebrow "Sexey's School · Music Department", Georgia title, maroon pill button with white text, muted `#6F5E5D` footnote.

---

## 9. Checklist for any new client-facing change

1. Uses the CSS variables in §3, not new hex values.
2. Headings in Cinzel, everything else in Montserrat.
3. Gold is used for lines/accents; gold-coloured text uses `--gold-ink`.
4. New colour pairs hit 4.5 : 1 contrast; tested in light and dark mode.
5. Free = gold outline, mine/selected = maroon, closed = grey — on every screen.
6. Works at phone width with a visible gold focus ring.
7. Session times, limits and rules match the Supabase functions and migrations (e.g. `WEEKLY_LIMIT` / `EXAM_LIMIT` ↔ `practice_check_booking`).
8. Change committed to GitHub; any database part applied in Supabase and recorded in `supabase/migrations`.

*Source of truth: `index.html` lines 8–190, `display.html` styles, and `band-invite-email/index.ts` in `OMHMus/Music-Department-Booking-System` (commit `a31d522`, 4 Oct 2026).*
