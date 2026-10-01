# TallyConnect Liquid Glass Prototype — Analysis and Flutter Blueprint

This document is the technical blueprint of the approved TallyConnect "Liquid Glass" prototype. It covers every file, dependency, screen, data item, design token, behaviour and calculation in the prototype, with the exact file and line where each one lives. It ends with a map from each prototype mechanism to its Flutter equivalent.

The prototype source files are the single source of truth. Wherever this document and the source disagree, the source wins.

Line numbers refer to the unmodified `project/Main.dc.html` (2,780 lines, 299,699 bytes, SHA-256 `68b9c9e17f6ab9bbe4910d01915cf98a5a12215b18c551b9af41fe653ce9d529`).

The label `NOT DETERMINED FROM SOURCE` marks anything the source files cannot confirm.

---

## 1. Source inventory

### 1.1 Where the prototype lives
- **Container:** a claude.ai Design canvas artifact, https://claude.ai/artifact/CqUYTznirZMY4ja4bXG166.
- **Version analysed:** `1790760414-464f`.
- **Canvas title:** "TallyConnect Liquid Glass".
- **Authored project files:** the canvas holds 18 published files. Only the three under `project/` belong to the prototype. Everything else belongs to the canvas editor (the artifact type), not to TallyConnect.

### 1.2 Files to copy into the destination folder (verified to exist, byte-exact copies)

| # | File | Size | SHA-256 | Role |
|---|------|------|---------|------|
| 1 | `project/Main.dc.html` | 299,699 B | `68b9c9e1…d529` | **The whole app.** CSS, markup for every screen and overlay, all data and all logic. Canvas board "Prototype · tap Play", 390 × 844, `is_interactive: true`, corner radius 44. |
| 2 | `project/Guide.dc.html` | 13,587 B | `28a2b99b…1432` | Design-language board (1280 × 844): four rules, type scale, palette, glass levels, motion summary, category icon/colour map, word swaps. It is static (`renderVals(){ return {}; }`). |
| 3 | `project/canvas.json` | 787 B | `0be2a97e…772f` | Canvas index: board sizes, positions and titles, board order `["Main.dc.html","Guide.dc.html"]`, note "TallyConnect — Liquid Glass prototype". |
| 4 | `docs/PROTOTYPE_ANALYSIS.md` | — | — | This document. |

Recommended layout in your folder: keep the `project/` sub-path (`project/Main.dc.html`, `project/Guide.dc.html`, `project/canvas.json`) and put this file at `docs/PROTOTYPE_ANALYSIS.md`.

### 1.3 Files in the artifact that do NOT need copying (canvas editor runtime, not app code)

| File | Why it is excluded |
|------|-------------------|
| `index.html`, `SKILL.md` | The canvas editor page and its authoring instructions. |
| `artifact-type/app.js`, `app.css` | Editor UI. |
| `artifact-type/dc-runtime.js` | Runtime that runs `.dc.html` files: `<x-dc>`, `<helmet>`, `<sc-if>`, `<sc-for>`, `{{…}}` bindings, the `DCLogic` base class, `setState`. |
| `artifact-type/reference/*.md`, `artifact-type/thumbnail/thumbnail.json` | Editor reference docs and thumbnail. |

The `.dc.html` files load `<script src="./support.js"></script>` (Main.dc.html line 6). **`support.js` is not among the published files.** It is supplied by the canvas runtime; which runtime file serves it is `NOT DETERMINED FROM SOURCE` (`index.html` references `dc-runtime.js`). The Flutter app does not need it.

### 1.4 Embedded and external resources

| Resource | Where | Status |
|----------|-------|--------|
| **Figtree** font, weights 400/500/600/700/800 | External: `https://fonts.googleapis.com/css2?family=Figtree:wght@400;500;600;700;800&display=swap` (Main line 11, Guide line 11) | Not bundled. Source: Google Fonts, SIL Open Font License 1.1. The exact font file version Google serves is `NOT DETERMINED FROM SOURCE`. The Flutter repo already bundles the TTFs from github.com/erikdkennedy/figtree in `packages/tc_design/fonts/`. |
| **Icons** (72) | Embedded as SVG path strings in the JS object `IC`, Main lines 1612–1680, drawn as `<svg class="i" viewBox="0 0 24 24"><path d="…">` | No icon files exist. |
| **Wallpapers** | Embedded CSS gradients (`.wp-*`, `.ps-*`, `.root`, lines 341–360) plus generated gradients (`makeTheme`, line 1898) | No image files. |
| **User photo wallpaper** | Runtime upload: `<input type=file accept="image/*">` (line 1294), handled by `wp.onFile` (lines 2743–2748) | Not shipped. It is stored as a data URL in localStorage. |
| **Images, bitmaps, other fonts** | — | None. The canvas asset store is empty (0 files). |
| **Bill PDF** | Rendered as HTML ("paper" div, lines 1568–1578) | No PDF file. |

---

## 2. Runtime, frameworks and dependencies

| Item | Detail |
|------|--------|
| **Runtime** | Claude Design canvas "Design Component" format, artifact type release 1790707925-3098 at publish time. Artifact contract `0.2.47`. |
| **Component model** | `class Component extends DCLogic` (line 1915). It works like a React class component: `this.state`, `setState(obj|fn)`, `componentDidMount`, `componentDidUpdate`, `componentWillUnmount`. `renderVals()` (line 2259) returns every binding the markup uses. |
| **Templating** | `{{path}}` bindings, `<sc-if value>` conditionals, `<sc-for list as>` loops, `<helmet>` for the `<style>` and font `<link>`. |
| **Props** (`data-props`, line 1611) | `startScreen` enum, default `"login"`; options are login, home, newEntry, flow, vHub, outHub, items, party, reports, activity, team, settings, help. `glassLevel` range 20–100, step 10, default 60. `$preview` 390 × 844. |
| **Libraries** | None. No npm packages, no React or other frameworks, no TypeScript, no build step, no JSON or config files other than `canvas.json`. |
| **Browser APIs used** | `localStorage` (via `loadJ`/`saveJ`), Pointer Events (`pointerdown`/`pointermove`/`pointerup`/`pointercancel` on `window`), `document.elementFromPoint`, `getBoundingClientRect`, `Element.scrollTo` (smooth), CSS scroll-snap, `navigator.vibrate` (12 ms card menu, 10 ms tab lift), `FileReader`, `Image`, `<canvas>` 2D (`drawImage`, `toDataURL('image/jpeg', .8)`, `getImageData`), `getComputedStyle`, `setTimeout`, `<input type=date|range|color|file>`. |
| **CSS features relied on** | `backdrop-filter` (blur, saturate, brightness, contrast), `color-mix(in srgb, …)`, custom properties, `conic-gradient`, `repeating-linear-gradient`, `mask-image`, `@media (hover:hover)`, `:focus-visible`. |

---

## 3. File relationships (architecture inside `Main.dc.html`)

| Lines | Section |
|-------|---------|
| 1–8 | `<head>`, title "TallyConnect Liquid Glass", `support.js` |
| 9–487 | `<x-dc>` + `<helmet>`: Figtree `<link>` (11) and the entire `<style>` (12–486) |
| 488–493 | Root `<div class="{{rootCls}}" 390×844>`; `.wall` with 3 `.orb`s |
| 495–1604 | Screen and overlay markup (§6) |
| 1605–1608 | Toast |
| 1611 | `<script type="text/x-dc" data-dc-script data-props=…>` |
| 1612–1913 | Constants, data, helpers, theme maths (§7, §9) |
| 1915–2258 | `class Component` state and methods (§8) |
| 2259–2776 | `renderVals()`: per-screen view models (`// home` 2321, `// search` 2351, `// notifications` 2371, `// create workspace` 2374, `// new entry` 2395, `// flow` 2399, `// pick sheet` 2470, `// item picker` 2477, `// add new item` 2492, `// vouchers` 2500, `// entry detail` 2516, `// outstanding` 2522, `// bill detail` 2542, `// pdf` 2552, `// items` 2563, `// party` 2571, `// reports` 2597, `// activity` 2615, `// team` 2634, `// settings` 2657, `// billing` 2674, then refer/FAQs/card menu/drag ghost/hover bubble/hidden panel/colour picker/wallpaper, return object 2751) |

`Guide.dc.html` is independent. Nothing imports it, and it imports nothing.

---

## 4. Design tokens (all from the `<style>` block, lines 12–486)

### 4.1 Colour variables

These are defined on `.root` (line 18) and overridden by look, accent and custom themes (§9).

| Token | Default (Aurora) | Use |
|---|---|---|
| `--acc` / `--acc2` / `--acc3` | #8C1D3F / #A42A52 / #6E1531 | Accent; gradients acc2→acc3 |
| `--navy` / `--navy2` / `--navy3` | #1B2D5B / #2A4584 / #172A55 | Primary buttons (navy2→navy3), selected chips |
| `--ink` / `--ink2` / `--ink3` | #0E1B33 / #3F4B68 / #58647F | Text: primary, secondary, helper |
| `--gt` | 255,255,255 | Glass tint RGB |
| `--g` | .6 | Glass level, set by root class `g20`…`g100` (line 19) |
| `--gb` | 0 | Glass boost over a photo wallpaper: `.12`, or `.2` for dark photos |
| `--pos` / `--neg` / `--warn` | #0F7B55 / #B4233F / #A5470E | Line 442. Overridden for sunrise, rose, mint and ocean (443–446) |
| `--wall`, `--o1`, `--o2`, `--o3` | Aurora gradient (341) | Wallpaper and orb colours |
| `--c-sales` … `--c-activity` | Line 399 | Category colours. **The root always carries class `icmatch`** (line 2752), which sets every `--c-*` to `var(--acc)` (line 400), so all category icons use the accent. |

Fixed colours used directly in the CSS:
- Navy hairline and shadow base: `rgba(27,45,91,a)`.
- Chevron: `#8A94AC`.
- Tab label: `#3C4763`.
- Scrim: `rgba(14,27,51,.3)`; card-menu scrim `.06`.
- PDF page background: `#1D2231`; paper ink: `#16203A`.

### 4.2 Typography

Family: `'Figtree',-apple-system,system-ui,sans-serif` (line 13).

| Class | Size / weight | Extra |
|---|---|---|
| `.h1` | 34 / 800 | line-height 1.08, letter-spacing −.025em, margin 10 4 4 |
| `.sub` | 15.5 / 400 | line-height 1.4, ink2, margin 0 4 16 |
| `.h2` | 20 / 800 | −.01em |
| `.sec` | 12.5 / 800 | +.07em, uppercase, ink3, margin 22 8 8 |
| `.rt` | 16 / 700 | line-height 1.25 |
| `.rs` | 13.5 | ink3, line-height 1.3 |
| `.amt` | 16 / 800 | tabular-nums; `.amt.big` 32, −.02em |
| `.btn` | 16.5 / 700 | — |
| `.chip` | 15 / 700 | — |
| `.badge` | 12 / 700 | — |
| `.tab` | 11.5 / 700 | — |
| `.brand` | 22 / 800 | −.02em; `.big` 34 |
| `.inp` | 17 | — |
| `.lab` | 14.5 / 700 | — |
| `.tl` | 16 / 800 | — |
| `.ts` | 12.5 | — |
| `.ptitle` | 19 / 800 | — |
| `.kv` | 15 | `.strong` 17 / 800 |
| `.price` | 30 / 800 | — |
| `.code b` | 22 | monospace (`ui-monospace,Menlo,monospace`), .06em |

### 4.3 Spacing, sizes and radii

| Element | Values |
|---|---|
| Frame | 390 × 844 |
| Screen padding | `.scr` 28 16 36. On tab screens (`.wt`) the content stops 100 px from the bottom and gets an 18 px bottom fade mask. |
| Flow body | `.fbody` 28 16 20 |
| Nav row | `.nav` min-height 48, gap 10, margin-bottom 10 |
| Grids | `.two`/`.grid2` 2 columns gap 12; `.grid3` gap 12; `.grid4` gap 10; `.big3` gap 10; `.wgrid` 3 columns gap 12, `.wide` spans all columns |
| Rows | `.row` padding 12 14, min-height 66, gap 12; `.mrow` min-height 56 |
| Buttons | `.btn` height 56, radius 18; `.cbtn` 46 round (`.sm` 40) |
| Fields | `.inp` height 56, radius 16 (textarea 84) |
| Chips | `.chip` height 42, radius 21 |
| Segments | `.seg` padding 4, radius 17; buttons 42 high, radius 13 |
| Icon tiles | `.ico` 56/r18 (`.sm` 44/r14, `.xs` 38/r12); inner tint square inset 7/5/4, radius 13/10/9, currentColor at 10 % |
| Icons | `.i` 22, stroke 1.9; `.s` 18; `.xs` 15 (stroke 2.2); `.l` 28 (1.8); `.xl` 34 (1.7); `.fat` 3.2. All round caps and joins. |
| Avatars | `.av` 40 (`.sm` 34, `.lg` 58) |
| Radii | `.glass` 22, `.hero` 26, `.cobox` 24, `.tabbar` 34, `.pill` 28, sheet top 32, drawer 0 32 32 0, toast 26 |
| Tab bar | `.tabbar` left/right 14, bottom 20, height 68, padding 6; `.tab` 70 × 56 at `left = 6 + pos × 70` |

### 4.4 Shadows

| Surface | Shadow |
|---|---|
| Glass | inset 0 1px 0 rgba(255,255,255,.95), inset 0 −1px 0 rgba(27,45,91,.05), 0 14px 34px −16px rgba(27,45,91,.24), 0 2px 6px rgba(27,45,91,.05) |
| `.btn-p` | 0 14px 26px −12px color-mix(navy3 70%) |
| `.btn-a` | acc3 65% |
| `.ghost` | 0 30px 50px −18px rgba(27,45,91,.55) |
| `.ico` | 0 8px 18px −9px rgba(27,45,91,.32) |

### 4.5 Animations and timing

| Keyframe | Lines | Use |
|---|---|---|
| `inF` / `inB` | 30–31 | Screen change: x ±30 px + fade, .42s cubic-bezier(.2,.85,.2,1) |
| `up` | 32 | Sheet: translateY(105%), .46s cubic-bezier(.2,.95,.25,1) |
| `slideL` | 33 | Drawer, .42s |
| `fade` | 34 | Scrim .25s |
| `pop` | 35 | Toast .42s cubic-bezier(.3,1.5,.5,1) |
| `wig` / `wigw` | 36, 290 | Armed cards ±1.4° / wide cards ±.35°, .34s infinite |
| `rise` | 37 | y 10 + fade; tab bar .35s, step panels .35s |
| `drift` | 22 | Orbs, 16s alternate, delays −6s / −11s |
| `cmIn` | 321 | Card menu scale .84→1, .38s cubic-bezier(.3,1.5,.5,1) |
| `flashIn` | 433 | Restored card, 1.3s |
| `spinR` | 417 | Hover dwell ring, .6s |

Other timings:
- **Press:** `.tap:active` scale .955, .12s; release spring .38s cubic-bezier(.3,1.45,.5,1); hover (pointer devices only) translateY −2 scale 1.02.
- **Tab pill:** stretch .2s cubic-bezier(.4,0,.2,1) with scaleY .84, then settle .62s cubic-bezier(.26,1.55,.44,1) (line 1985).
- **Tab move during reorder:** left .55s cubic-bezier(.28,1.5,.45,1).
- **Toast:** visible 2600 ms.
- **Long-press:** 480 ms for cards, 450 ms for tabs.
- **Hover-to-open a tab:** 650 ms dwell. **Page-edge flip:** 700 ms.

---

## 5. Liquid Glass implementation

| Surface | CSS | Lines |
|---|---|---|
| `.glass` (base) | Background `rgba(var(--gt), --g*.9+.06+--gb)`; `backdrop-filter: blur(26px) saturate(185%)`; border 1px rgba(255,255,255,.8); radius 22; shadows from §4.4; `::before` sheen linear-gradient(155deg, white .65 0% → 0 36% → 0 72% → rgba(196,208,246,.22) 100%) | 38–39 |
| `.tap::after` | Press highlight: gradient white .55→.12→.26 plus inner ring white .85 | 41, 459 |
| `.sheet` / `.drawer` | Background `rgba(--gt, --g*.45+.5)` | 182, 186 |
| `.tabbar.glass` | Background white .18→.04; `blur(6px) saturate(210%) brightness(1.06)`; border white .58; inner glows; outer shadow 0 16 30 −18 | 377–378 |
| `.pill` | White gradient .46/.12/.22; `blur(10px) saturate(210%)`; inner accent glow; `::after` gloss strip | 142–143 |
| `.hbub` | Hover bubble: radial white glass; `blur(1.5px) saturate(240%) brightness(1.12)`; slides with `left .48s cubic-bezier(.3,1.45,.45,1)` | 384–385, 415 |
| `.cmenu.glass` | Water-glass menu: gradient white .3/.06/.14; `blur(7px) saturate(230%) brightness(1.08) contrast(1.03)`; border white .62; text milk-shadowed | 372–375 |
| `.sheet.hpanel` | Floating hidden-cards panel: left/right 12, bottom 100, radius 30, `blur(10px) saturate(220%) brightness(1.06)` | 427–429 |
| `.hero` / `.acth` | Light accent surfaces: gradients from color-mix(acc 20%), `blur(22px) saturate(180%)` | 451–460 |
| `.foot` | Footer bar: `rgba(--gt,.5)`, `blur(22px) saturate(170%)`, top border white .85 | 157 |
| `.photo` | Photo wallpaper: `--gb` .12 (`.photo-dark` .2), orbs hidden, white overlay .34→.2 (dark .58→.46) | 462–466 |
| Glass level | Root class `g{round(glass/10)*10}`; slider 20–100 step 10; presets 20/40/60/80/100. **Not persisted** — it resets to the prop value (60) on reload. | 2752 |

---

## 6. Screens, overlays and navigation

### 6.1 Navigation model
State keys: `screen`, `history[]`, `dir` ('fwd'/'bk'), `tab`, `tabOrder` (line 1916+).

| Method | Lines | Behaviour |
|---|---|---|
| `go(s, extra)` | 1993 | A tab screen calls `selectTab`. Any other screen pushes the current screen onto history. `extra` merges parameters into state. |
| `selectTab(i)` | 1985 | Clears history and overlays, sets `dir` from position, animates the pill. |
| `back()` | 1999 | Pops history. With empty history: forgot → login, otherwise `selectTab(0)`. |
| `jump(s)` | 1978 | Used for the `startScreen` prop. |

Other navigation constants:
- `TABS` (1689): Home(home), Dues(outHub, rupeeC), Team(team), Activity(activity), Reports(reports, chart).
- `NO_TAB` (1690): login, forgot, flow, createWs, manageWs, billDetail, partyDetail, actDetail, entryDetail, newEntry.
- `TITLES` (1692): labels for the back pill.
- There is no URL router; navigation is pure state.

### 6.2 Screens (27)

| Key | Title on screen | Markup lines | View-model lines |
|---|---|---|---|
| login | Welcome back | 495–516 | 2758–2760 |
| forgot | Forgot password? | 518–543 | 2760 |
| home | Dashboard pages | 545–625 | 2321–2350 |
| notifs | Alerts | 627–649 | 2371–2373, 2763–2765 |
| createWs | Make a workspace | 651–675 | 2374–2386 |
| manageWs | Workspaces | 677–700 | 2388–2393 |
| newEntry | New Entry | 702–716 | 2395–2398 |
| flow | Entry flow (5 types) | 718–867 | 2399–2469 |
| vHub | Vouchers | 869–889 | 2500–2505 |
| vList | All Vouchers / by kind | 891–925 | 2506–2515 |
| entryDetail | Entry | 927–944 | 2516–2521 |
| outHub | Money due | 946–965 | 2522–2528 |
| outList | To get / To give | 967–996 | 2529–2541 |
| billDetail | Bill details | 998–1025 | 2542–2551 |
| items | Items | 1027–1052 | 2563–2570 |
| party | Party | 1054–1081 | 2571–2581 |
| partyDetail | Party detail (Summary/Items/Entries) | 1083–1108 | 2582–2596 |
| reports | Reports | 1110–1137 | 2597–2601 |
| report | Report detail | 1139–1151 | 2602–2613 |
| activity | Activity | 1153–1182 | 2615–2623 |
| actDetail | Activity detail | 1184–1200 | 2624–2633 |
| team | Sales Team | 1202–1226 | 2634–2648 |
| settings | Profile/Alerts/Plan/Look | 1228–1321 | 2657–2672, 2712–2749 |
| companies | Companies | 1323–1335 | 2297–2299 |
| billing | Plans | 1337–1353 | 2674–2680 |
| refer | Refer a friend | 1355–1377 | 2682 |
| help | Help | 1379–1399 | 2683, 2309 |

### 6.3 Overlays (`state.overlay`, 12) and floating layers

| Overlay | Markup lines | Notes |
|---|---|---|
| menu (side drawer) | 1412–1434 | 320 px drawer: profile, account rows with unread count, Plan, Support, Version 19.6.2, Log out |
| search | 1436–1448 | Sheet `top:60px`; filters the `SEARCH` list (2352–2369) |
| company | 1450–1461 | Choose company, Refresh, Manage |
| pick | 1463–1474 | Party, account or ledger picker with search |
| newParty | 1476–1487 | — |
| picker | 1489–1510 | `.sheetf` item picker, `top:40px` |
| addItem | 1512–1529 | Add new item, `.sheetf` |
| invite / newUser / member | 1531–1561 | Team sheets |
| pdf | 1563–1582 | Full-screen dark viewer |
| hiddenPanel | 1594–1604 | Floating glass panel |

Floating layers that are not overlays:
- Card menu `cmenu`: 1584–1590.
- List drag ghost `lgh`: 1591–1593.
- Home drag ghost: 621.
- Edge indicators: 619–620.
- Toast: 1605–1608.
- Tab bar: 1401–1410.

### 6.4 Dead code (in the logic, never rendered by the markup)
- The legacy Home "customize" mode: `tiles`, `customize`, `hiddenDraft`, `startCustomize`/`saveCustomize`.
- The edit mode `enterEdit`/`doneEdit`/`cancelEdit`. No markup references `{{editing}}`; `.editing` CSS exists but is unused.
- `THEMES` / `state.theme` / `state.wall` / `sg.themes` / `sg.walls` / `.th-*` classes (334–339).
- The icon-mode toggles `setIcColour` / `setIcMatch`; key `tc-liquid-icons` is saved but never loaded.
- The `.wp-*` thumbnails `.wthumb` are used; `.prev .blob` is used in the glass preview.
- **Do not reproduce any of the dead code as UI.**

---

## 7. Mock and sample data

All mock data is embedded in `Main.dc.html`. Money in the prototype is in **rupees** (the Flutter seed stores paise).

| Constant | Line | Contents |
|---|---|---|
| `IC` | 1612 | 72 icon paths |
| `C` | 1681 | Category colour variables |
| `T` | 1694 | 10 shortcuts: items, party, vouchers, outstanding, reports, settings, sales, purchase, moneyIn, moneyOut — each with title, subtitle, icon, target screen or flow |
| `SUMS` | 1706 | 8 money cards: toGet 348690, toGive 126850, mIn 215000, mOut 98450, sales 348690, purch 126850, cash 42300, bank 386900 — each with its navigation target |
| `KIND` | 1716 | 6 voucher kinds: label, long label, icon, sign |
| `VOUCH` | 1724 | 21 vouchers (kind, party, number, day of Sep 2026, amount). Total 918490 |
| `RECV` | 1747 | 6 receivable bills, total 348690 |
| `PAYB` | 1755 | 5 payable bills, total 126850 |
| `PARTIES` | 1762 | 14 parties (type `c`/`s`, city, balance) |
| `ITEMS` | 1778 | 8 items (stock, unit, rate, status ok/low/out). Stock value 245760 |
| `SALES9` | 1788 | 3 bill lines of Sales 9 |
| `LEDGERS` | 1793 | 6 ledgers |
| `ACCOUNTS` | 1797 | 3 bank/cash accounts |
| `COMPANIES` | 1798 | 3 companies; default `gi` |
| `FT` | 1803 | Flow types: sales, purchase, receipt, payment, journal — steps, labels, prefix `p`, party list, draft flag |
| `MODES` | 1810 | cash, bank, upi, cheque, other |
| `FORM` | 1811 | Every form default (bill numbers, dates 2026-09-26, parties, amounts, references, UTRs, notes) |
| `NOTIFS` | 1821 | 6 alerts with targets |
| `ACTS` | 1829 | 10 activity entries: 1 fail, 2 wait, 7 ok |
| `TEAM` | 1841 | 4 members: active ×2, pending, off |
| `WS` | 1847 | 3 workspaces: def (built-in), sd, me |
| `FAQS` | 1852 | 4 FAQs |
| `REPORTS` | 1858 | 8 reports |
| `PL` | 2675 | Plans: Starter ₹1,499/yr or ₹149/mo; Professional ₹3,999/yr or ₹399/mo; Enterprise current, "Custom · talk to us" |
| `SEARCH` | 2352 | 14 search results |
| Initial line items | 1932–1934 | `state.lines`: sales (3 lines), purchase (2 lines), all GST 18 % |
| Initial journal lines | 1936 | `state.jl`: Salaries A/c Dr 120000, Salary Payable Cr 120000 |

Fixed "today" is **26 Sep 2026**. It is hard-coded in texts ("As on 26 Sep 2026", due texts in `RECV`/`PAYB`, period filter `today` = day 26, `week` = day ≥ 20).

Hard-coded values in the view models:
- Report values `rv` (2599).
- Outstanding ageing (2531: on time 234820/109150, 1–30 days late 113870/17700).
- Party detail for Shree Balaji Traders (2588).
- Activity detail for Sales 11 (2629–2632).
- PDF Sales 9 taxable 95000, CGST 8550 (2555).

---

## 8. State, data flow and persistence

**State.** All state lives in one component state object (constructor, lines 1916–1955). It includes screen, navigation, overlay, company, glass, home layout, drag fields, tab order, card menu, pins, list preferences, look, colour picker, wallpaper, workspaces, flow, line items, payment modes, journal lines, form, picker state, filters (`vFilter`, `vPeriod`, `outKind`, `outFilter`, `itemsFilter`, `partyFilter`, `partySort`, `repCat`, `actFilter`, `teamFilter`, `nFilter`, `setTab`, `yearly`, `faq`), mutable lists (`acts`, `team`, `notifs`, `extraParties`), `pdf`/`zoom` and `toast`.

**Data flow.** `renderVals()` derives every view model from state on each render. Event handlers call `setState`, and `say(msg)` (1983) shows a toast.

**Persistence.** localStorage through `loadJ`/`saveJ` (1869–1870):

| Key | Value |
|---|---|
| `tc-liquid-pages-v2` | `{wsId: [[ids…], …]}` dashboard pages |
| `tc-liquid-hidden-v2` | `{wsId: [{id, page, index, snap[]}]}` hidden cards |
| `tc-liquid-pinned` | `[ids]` pinned Home cards |
| `tc-liquid-page-v2` | Current page index |
| `tc-liquid-tabs` | Tab order `[0..4]` (validated) |
| `tc-liquid-lists` | `{list: {order[], pinned[], hidden[]}}` for notifs, vouchers, bills, items, party, reports, acts, team |
| `tc-liquid-preset` | Look key |
| `tc-liquid-accent` | Accent key or `'look'` |
| `tc-liquid-mode` | `'look'` or `'custom'` |
| `tc-liquid-custom` | `{base, combo}` |
| `tc-liquid-wall` | `'theme'`, a wallpaper key, or `'photo'` |
| `tc-liquid-photo` | `{url (JPEG data URL, max side 1100), lum}` |
| `tc-liquid-look` | Legacy `{theme, wall}` |
| `tc-liquid-icons` | Written only, never read |

**Not persisted:** login, company, workspaces list, team/acts/notifs changes, filters and glass level. They reset on reload.

---

## 9. Themes, presets, colour picker and wallpapers

### 9.1 Looks
`LOOKS` (1875) defines 8 looks. Each look is a CSS class `ps-*` (353–360) that sets acc×3, navy×3, ink×3, `--gt`, wallpaper and orbs.

| Key | Title | Subtitle |
|---|---|---|
| aurora | Aurora | Maroon & navy · misty blue |
| ocean | Ocean Breeze | Calm blues |
| royal | Royal Silk | Violet on silk waves |
| sunrise | Sunrise Clay | Warm terracotta |
| mint | Mint Ledger | Fresh greens |
| pearl | Pearl Graphite | Quiet neutrals |
| prism | Prism Indigo | Soft rainbow glass |
| rose | Rose Quartz | Rose on lavender |

### 9.2 Accents
- `ACCENTS` (1876–1877) defines 17 harmony accents. Each is a class `ac-*` (401–411, 436–441) that sets acc×3 and navy×3.
- `LOOKACC` (1878) lists the 4 accents allowed per look.
- `LOOKSIG` (1879) gives each look's own accent (the first swatch).
- `okAccent` (1912) validates the stored accent.

### 9.3 Resolution order (root class built at line 2752)
1. `g{level}`
2. `ps-{preset}`
3. `ac-{accent}` when the accent is not `'look'`
4. `icmatch`
5. `photo` / `photo-dark`
6. `menuOnAll` while the card menu is open

`applyTheme()` (1958) then writes inline overrides:
- **Custom mode:** writes all 14 `THEME_KEYS` (1911) from `makeTheme`.
- **Wallpaper key other than `'theme'`:** copies `--wall`/`--o1..3` from `.wp-{key}`.
- **Photo:** sets `--wall` to `url(data) center/cover`.

### 9.4 Custom colour engine: `makeTheme(hex, ci)` (1898–1910)
1. Convert HSL. If saturation < 10 it is treated as grey; otherwise saturation is clamped to 38–82.
2. `acc` = the first lightness ≤ 46, stepping down by 2, that gives contrast ≥ 4.8 on `#F2F4FA` (`readable`, 1897). `acc2` = L+11 (max 62); `acc3` = L−10 (min 8).
3. Second hue `h2` = h + combo shift; saturation capped at the combo cap.
4. navy ×3 at L 20/32/14; ink ×3 at L 12/30, and ink3 readable at 42.
5. `--gt` = hsl(h, 55, 98.4).
6. Wallpaper: 3 radial blobs at L 87/89/91 plus a linear top/bottom gradient; orbs at L 82/85/87.

Combos (`COMBOS`, 1896):

| Combo | Hue shift | Saturation cap |
|---|---|---|
| Tonal | 0 | 42 |
| Harmony | 32 | 40 |
| Contrast | 180 | 34 |
| Balanced | 120 | 30 |
| Business | 0 | 8 |

Colour helpers (1880–1895): `hsl2rgb`, `rgb2hex`, `hslx`, `hex2rgb`, `rgb2hsl`, `hsv2hex`, `hex2hsv`, `lumOf`, `contrastOf`.

### 9.5 Colour picker
Markup 1275–1280, logic `cp` at 2713–2725:
- Saturation/value pad (164 px), pointer drag.
- Hue range 0–359.
- Hex input, filtered to hex characters, max 6.
- Native `<input type=color>` button.
- 16 quick swatches (2721).
- 5 combination previews; tapping one shows the toast "<Combo> look applied".

### 9.6 Wallpapers
- `WALLS` (1913) defines 9 wallpapers: aurora, ocean, lavender, sunrise, mint, pearl, silk, prism, dunes. CSS lines 342–350.
- The picker also shows "Match theme" and, when a photo exists, "My photo" (`WITEMS`, 2729).
- The picker uses a pending selection with a preview card, then Apply/Cancel (`wp`, 2731–2742). Apply shows "Wallpaper applied".
- Photo upload (2743–2748): the image must be an `image/*` file ("Please pick a photo"). It is downscaled to a maximum side of 1100 px and saved as JPEG at quality .8. A 16 × 16 sample gives the average luminance; below .35 counts as dark. Failure shows "Could not read that photo".
- Reset (2665): glass 60, aurora, accent `look`, mode `look`, wall `theme`; toast "Look set back to default".

---

## 10. Interactions

### 10.1 Tap and press
- `.tap`: press scale .955 with the highlight from §5; springy release.
- `_lpFired` guards prevent a tap from also firing after a long-press.

### 10.2 Tab bar (1401–1410; `selectTab` 1985; `tDown` 2188; `hb` 2697–2706; `armDwell` 2161)
- **Tap:** switches tab. The pill stretches across the old and new tabs, then springs onto the target.
- **Press and slide:** the hover bubble follows the finger; releasing on another tab selects it.
- **Mouse hover:** a 650 ms dwell auto-selects the tab, with the `spinR` ring.
- **Long-press 450 ms:** lifts the tab (`.lift`: translateY −8, scale 1.14, glass). Dragging reorders and saves to `tc-liquid-tabs`.

### 10.3 Dashboard (Home)
- **Pager:** horizontal scroll-snap pager (`.pager` top 176, bottom 122) with page dots.
- **Default pages:** `defaultPages(ws)` = `[['newEntry', …ws.feats, 'money']]` (2037).
- **Long-press 480 ms on a card** (`pDown`, 2058) opens the card menu next to the card (`openCardMenu`, 2169: 214 × 262 px, placed below or above the card). Moving more than 12 px after the menu opens starts a drag.
- **Menu items:** Pin/Unpin, Open, Drag (arms the card: wiggle plus a move badge), Hide (`cm`, 2687–2695).
- **Drag** (`beginDrag` 2208 / `dragMove` 2218):
  - A ghost follows the finger.
  - `elementFromPoint` finds the `[data-wid]` card under it. On wide cards the cursor's vertical half picks before/after; on others the horizontal half does (`moveTo`).
  - `[data-endpage]` "Drop here" moves the card to the end of a page.
  - **Edge flip:** needs more than 44 px of horizontal travel and the pointer within 22 px of the left or right edge, moving towards it. After a 700 ms hold the card moves to the previous or next page, creating a new page at the end (`flip`, 2238). Only one flip per edge entry.
  - `dragEnd` (2252) runs `cleanPages` and persists; `dragCancel` (2247) restores the snapshot.
- **`cleanPages`** (2041): drops empty pages except page 0 and pages that hold hidden cards, then remaps hidden-card page indexes.
- **Pin** (`togglePin`, 2179): moves the card to the front of page 1 after the other pinned cards. Toast "Pinned to the first page" or "Unpinned".
- **Hide** (`hideWidget`, 2086): stores `{id, page, index, snap}`. Refused when it is the last card. Toast "Card hidden".
- **Unhide** (`restoreHidden`, 2108): re-inserts the card next to its original neighbours using the snapshot. The `flash` animation plays; toasts "Card unhidden" or "Cards unhidden". "Hidden cards · Unhide" row → hidden panel → Unhide / Unhide all.

### 10.4 Customisable lists — `L(list, rows, keyOf, labelOf, base)` (2266–2277)
- Rows: hidden rows are removed; pinned rows come first, then the saved order, then the original order.
- A `.pinmini` badge marks pinned rows. A "N hidden · Unhide" row restores all hidden rows of the list.
- The same long-press menu applies. Drag (`lBegin`/`lMove`, 2137–2160) reorders by vertical half (Reports by horizontal half) and auto-scrolls within 56 px of the edges, 12 px per move.
- Keys and labels per list:

| List | Key | Label |
|---|---|---|
| notifs | id | t |
| vouchers | no | party · no |
| bills | no | party · no |
| items | name | name |
| party | name | name |
| reports | id | t |
| acts | id | title |
| team | email | name |

### 10.5 Scroll and swipe
- Screens scroll vertically; the scrollbar is hidden.
- The pager swipes horizontally with snap.
- The pager position is restored on returning to Home (`restorePager`, 1970).

---

## 11. Forms, validation, calculations and workflows

### 11.1 Entry flow (`FT` 1803; flow view model 2399–2469; `saveFlow` 2009)

**Steps per type:**

| Type | Steps |
|---|---|
| Sales, Purchase | Details → Items → Payment → Check |
| Receipt, Payment | Details → How paid → Check |
| Journal | Details → Accounts → Check |

**Totals** (`totals`, 2007):

```
sub = round(Σ rate × qty)
gst = round(Σ rate × qty × gst / 100)
total = sub + gst
```

- Balance = total − amount paid. Shown as "Still to get" / "Still to pay"; class `tot b` when greater than 0, otherwise `tot c`.
- Journal: Dr sum must equal Cr sum and both must be greater than 0. Otherwise the warning reads "Not matching yet · difference ₹X"; when matched, "Matched — both sides are equal".

**Next is disabled when:**
- step 0 has no party, or
- the Items step has no lines, or
- the journal is unbalanced (2453).

**Changing payment mode** sets the account for receipt/payment: Cash → "Cash in hand"; otherwise "HDFC Bank – Current" (receipt) or "ICICI Bank – Current" (payment) (2441).

**Saving:**
- Save adds an activity entry with status waiting, time "Just now", selects the Home tab and shows "Saved! It will reach Tally by itself". After 5 s the entry becomes "ok".
- Draft (sales/purchase only) shows "Draft saved on this phone".

**Line items:**
- Stepper −/+ (minimum 1); removing a line shows "Item removed".
- Item picker: tap toggles the item (qty 1, GST 18); the footer shows "N items picked" and the total.
- Add new item (2492–2499):
  - Categories: General, Wires & Cables, Lighting, Switches, Switchgear, Fans.
  - Units: PCS, NOS, COIL, BOX, MTR.
  - GST: 0/5/12/18/28.
  - Calculation: `nsub = qty × rate × (1 − disc/100)`; `ngst = nsub × gst/100`; shown with `inr2`.
  - Disabled without a name, quantity and rate. Toast "<name> added to bill".

**New party:** disabled without a name. Toast "<name> added"; the party is added to `extraParties`.

### 11.2 Other validations
- Invite: email must match `/.+@.+\..+/`. Add person: name required.
- Create workspace: name plus at least one shortcut. Money cards default to `['toGet','toGive']`.
- Login and forgot-password: no validation (any input is accepted).

### 11.3 Formatting
- `inr` (1683): Indian grouping, rounded, U+2212 minus.
- `inr2` (1684): two decimals.
- `fdate` (1686): `yyyy-mm-dd` → "dd Mon yyyy".
- `initials` (1687).

### 11.4 Toast texts
Every toast goes through `say()`, so a full list comes from `grep -o "say('[^']*'" Main.dc.html`. Notable ones:
- Login: "Welcome back, workk72002". Logout: "You are logged out".
- "Now showing <company>", "Company list refreshed from Tally", "Up to date · synced just now".
- "All marked as read", "Workspace saved", "Now using <ws>", "<ws> deleted".
- "Home layout saved" (dead code).
- "Share sheet opened", "Saved to Downloads", "Reminder sent on WhatsApp to <party>", "WhatsApp reminders sent to 2 customers".
- "Point the camera at a barcode", "Stock list shared", "Party details shared", "Report shared".
- "Trying again…", "Sent to Tally", "Everything is up to date".
- "Invite sent to <email>", "<name> added to your team", "<name> turned off/on", "Invite sent again", "Invite cancelled".
- "Calling support…", "Opening WhatsApp…", "Opening email…", "Code copied", "We will call you to switch to <plan>".
- "Pinned to the top", "Unpinned", "Card hidden", "Card(s) unhidden", "Pinned to the first page".
- "<combo> look applied", "Wallpaper applied", "Please pick a photo", "Could not read that photo", "Look set back to default".

---

## 12. Responsive and browser-specific behaviour

- **Fixed frame:** the design is a fixed 390 × 844 frame (`.root`). There are no media queries for width.
- **Coordinate scaling:** `localPt` (2207) rescales pointer coordinates by `rootWidth / 390`, so the frame can be scaled while drag maths stays in frame units.
- **Hover:** effects apply only under `@media (hover:hover)`.
- **Touch handling:** `touch-action:none` on armed or lifted cards and on the tab bar. `-webkit-touch-callout:none` and `user-select:none` on draggable items.
- **Safe areas, Android back and status bar:** not handled. Placement of these on real devices is `NOT DETERMINED FROM SOURCE`; it is a Flutter decision.
- **Haptics:** `navigator.vibrate` is ignored on iOS Safari. That is browser behaviour, not prototype logic.

---

## 13. PROTOTYPE → FLUTTER CONVERSION MAP

| Prototype | Flutter equivalent |
|---|---|
| `.dc.html` component + `renderVals()` | One widget per screen (`ConsumerWidget`) building from Riverpod state; view-model logic in providers or controllers |
| `<sc-if>` / `<sc-for>` | `if` / `for` collection elements in `children` lists |
| `<div class="glass">` | `TcGlass`: `ClipRRect` + `BackdropFilter(ImageFilter.compose(outer: ColorFilter.matrix(saturate×brightness×contrast), inner: ImageFilter.blur(σ)))` + fill `glassTint.withValues(alpha: g*.9+.06+gb)` + sheen `LinearGradient` + 1 px white border + `BoxShadow`s. CSS inset shadows become painted bands; CSS blur b becomes Flutter blurRadius ≈ (b/2 − .5)/.57735. |
| CSS custom properties | `TcPalette` (acc×3, navy×3, ink×3, glassTint, pos/neg/warn, wallpaper spec, orbs) supplied through an `InheritedWidget` theme; `.ps-*`, `.ac-*` and `makeTheme` become pure Dart resolvers |
| CSS classes (sizes, type) | Token classes (`TcTypography`, `TcSpacing`, `TcRadii`, `TcMotion`) plus components: `TcButton`, `TcChip`, `TcSegmented`, `TcRow`, `TcListCard`, `TcIconTile`, `TcKv`, `TcBadge`, `TcSwitch`, `TcStepper`, `TcTextField` |
| Wallpaper gradients | `CustomPainter`. `radial-gradient(W% H% at X% Y%)` → canvas translate/scale + `ui.Gradient.radial`; CSS angle linear gradients → `ui.Gradient.linear` along the CSS gradient line; `repeating-linear-gradient` → `TileMode.repeated`; `conic-gradient` → `ui.Gradient.sweep` rotated by (from − 90°) |
| `.orb` + `drift` | 3 circles with `MaskFilter.blur(σ 36)`, opacity .7, one 32 s `AnimationController` with phase offsets |
| SVG icons (`IC`) | Path strings → `Path` (path parser) → `CustomPainter` stroke, viewBox 24, round caps and joins, stroke widths from §4.3 |
| State (`this.state`, `setState`) | Riverpod `Notifier`s: navigation, overlay, toast, session/company, look, view filters, home layout, list preferences, card menu, flow, stores for acts/team/notifs/parties/workspaces |
| `localStorage` | `shared_preferences` with the same keys (JSON strings). Optionally Drift/SQLite for domain data. Photo: file in the app documents directory plus a stored path and luminance |
| Navigation (`go`/`back`/`selectTab` + history) | A navigation controller that reproduces the history rules exactly. go_router for route registration and auth guard (`/login` vs `/app`). Android back → `PopScope` calls `back()` (closes overlay first) |
| Screen change `inF`/`inB` | Keyed entry animation: `Transform.translate(±30 → 0)` + `Opacity`, 420 ms, `Cubic(.2,.85,.2,1)`. The old screen is removed immediately. |
| Sheets / drawer / scrim / toast / card menu | `Stack` overlay layers driven by an overlay provider; `TcEnter` slide/pop/fade with the same curves and durations |
| `:active` scale + `::after` | `GestureDetector` tap down/up → `AnimatedScale(.955)` + `AnimatedOpacity` highlight |
| Long-press 480/450 ms | `LongPressGestureRecognizer(duration: 480/450 ms)` via `RawGestureDetector`; `HapticFeedback.selectionClick()` for `navigator.vibrate` |
| Pointer drag + `elementFromPoint` | `onLongPressMoveUpdate` / `Listener` pointer events; hit-testing against a registry of `GlobalKey` → global `Rect` per card; ghost in an `Overlay`/`Stack` layer; edge timers with `Timer(700 ms)` |
| Scroll-snap pager | `PageView` (`PageController`, saved page index) or `PageView` + custom physics |
| Tab pill stretch/settle | `AnimationController` interpolating left/width/scaleY: 200 ms `Cubic(.4,0,.2,1)`, then 620 ms `Cubic(.26,1.55,.44,1)` |
| Hover bubble | `Listener` on the bar (pointer down/move/up); `AnimatedPositioned` with `Cubic(.3,1.45,.45,1)` |
| `<input>`, `<textarea>` | `TextField` with collapsed decoration inside the styled container |
| `<input type=date>` | `showDatePicker` (platform picker; decision D3) |
| `<input type=range>` | `Slider` or custom track |
| `<input type=color>` | No native equivalent; the custom SV pad + hue slider covers it |
| `<input type=file>`, `FileReader`, `<canvas>` | `image_picker` → copy to the documents directory → `ui.instantiateImageCodec(targetWidth: 16)` for luminance → `FileImage` wallpaper |
| PDF "paper" | Flutter widget page inside `InteractiveViewer`/`Transform.scale` (zoom 60–160 % in steps of 20) |
| `color-mix(in srgb, X p%, transparent)` | `X.withValues(alpha: X.a × p)` |
| `navigator.vibrate` | `HapticFeedback` |
| Figtree via Google Fonts | Bundled TTFs (OFL) declared in `pubspec.yaml` |

---

## 14. NOT DETERMINED FROM SOURCE
1. **`support.js`:** the exact file the canvas runtime serves for it (it is not a published project file).
2. **Figtree:** the exact font file version Google Fonts serves.
3. **Mobile device behaviour:** safe-area insets, status bar, Android back button, keyboard insets and tablet layout. The prototype is a fixed 390 × 844 frame.
4. **Real dates:** "today" is hard-coded as 26 Sep 2026; dynamic date rules are not in the source.
5. **Persistence of session state:** login, company, glass level and workspace changes are not persisted in the source; whether the app should persist them is a product decision.
6. **Backend contracts:** API endpoints, authentication and Tally write-back payloads.
7. **Real behaviour of toast-only actions:** share, download, call, WhatsApp, email, barcode scan and plan switch only show toasts in the prototype.
8. **Placeholder content:** "[YOUR SUPPORT NUMBER]", "[YOUR WHATSAPP NUMBER]", "[YOUR SUPPORT EMAIL]", "[Add your security and data-storage details here.]".
