# Corrigenda — what it captures, and why

The design: what a report holds, how it is captured, what happens to it
after it arrives. [README.md](README.md) is the shorter answer — what
this is and how to run it — and this is the reasoning underneath.
[HISTORY.md](HISTORY.md) keeps what was tried and abandoned, so this
one can describe the thing as it stands.

A small injectable client (one JS file) plus a Ruby endpoint, used to
capture precise, reproducible reports about a rendered page: visual
defects, layout breakage, wrong content, things that do not work.

**Built and in service** (§10 phases 1 and 2): the endpoint, the store
and the review UI; the widget — launcher, menu, element picker with
keyboard tree navigation, capture switches with live size estimates,
payload preview, the gzipped POST; the screenshot channel of §6.2 with
tab calibration, opaque redaction of form fields, cropping and WebP
encoding; the browser add-on that takes that picture where a page
cannot; and retention (§8), off unless a deployment asks for it.

**Not built:** annotation and the drag rectangle (§6.2), the DOM
snapshot (§6.3), the enrichment pass (§8), the deep-link review mode.

Two details settled during the build, both narrower than this spec
assumed: gzip is detected by **magic number** rather than a custom
header, and a plain `application/json` body is accepted alongside
multipart so the endpoint can be exercised with `curl`.

## 1. Scope, and what the audience decision changes

The widget is **staff-only** (see Decisions). That is not a small
detail — it changes what this thing is. It is not a public feedback
collector; it is a **capture tool for our own testing sessions**,
used while walking a site at several widths, on a phone, in a browser
we do not normally use.

Consequences, all of them simplifying:

- **No anti-abuse machinery.** No HMAC tickets, no rate limiting, no
  honeypots, no spam moderation. Apache authenticates before the
  request reaches Ruby.
- **The reporter is known.** `REMOTE_USER` comes from the existing
  LDAP auth, so no name/email field and no "notify me when fixed"
  loop; the reporter and the fixer are the same small group.
- **Report volume is low.** Tens per month, not thousands. Filesystem
  storage is not a compromise, it is correct.
- **Priorities shift.** Reproduction fidelity and diagnostics matter
  most; the typo-reporting path matters least (we can edit the file
  directly). Capture richness beats reporting convenience.

Reports are **pull, not push**: they land on disk and are read in the
review UI when we choose to. No mail, no XMPP.

## 2. Decisions

| Question | Decision |
|---|---|
| Endpoint | **Sinatra + Puma** (gems not yet installed; `rack 3.1.19` is) |
| Audience | **Staff only**, behind the existing LDAP `AdminAuth` macro |
| Screenshot | **User-selectable per report**, fine-grained (§6) |
| Notification | **Review UI only** |

## 3. Architecture

| Piece | Location | Role |
|---|---|---|
| `corrigenda.js` | `client/`, served by the service at `/.corrigenda/corrigenda.js` — the one path under it that needs no authentication | Whole client: UI, picker, capture, transport |
| CSS | inlined in the JS | Adopted `CSSStyleSheet` in an open shadow root |
| `corrigenda` service | one Sinatra app, one Puma | Receives, validates, stores; serves review UI |
| store | `<data>/corrigenda/` | One directory per report, plus `index.jsonl` |

### No separate CSS file

The widget is injected into pages whose CSS is the thing under
investigation. A widget styled by the host page will itself look
broken, and its own styles can perturb the layout being diagnosed —
the measurement changes the measured. An **open shadow root** with an
adopted stylesheet gives total isolation, drops injection to one
`<script>` tag, and removes a request. Theming stays possible through
a handful of `--corrigenda-*` custom properties, which pierce shadow
boundaries by design. The root is open rather than closed: the CSS
isolation is identical either way, and an open root can be inspected in
devtools and driven from a test, which a closed one cannot.

Nothing the widget injects participates in page flow: the launcher and
panel are `position: fixed`, the picker overlay is `fixed` and
`pointer-events: none`.

## 4. Delivery — two entry points, same module

Both load the identical module; they differ only in when it starts.

**A. Apache-injected, gated on `REMOTE_USER` — DOES NOT WORK HERE.** The
original plan was `mod_substitute` inside
`<If "%{REMOTE_USER} != ''">`. That expression is only non-empty when
Apache authenticated **the page**, and of the fourteen vhosts on this
host exactly one authenticates anything. On the
exhibition sites `REMOTE_USER` is always empty, so the widget would
never appear on precisely the sites whose CSS is under investigation.
`mod_substitute` is also not loaded (commented at `httpd.conf:106`).

**B. Bookmarklet — SHIPPED.** Injects the client on demand, on any site
including staging, with no global module and no page rewriting. With no
`data-*` attributes the widget falls back to `/.corrigenda/report/` and
`location.hostname`, so the POST stays same-origin and inside that
vhost's auth. See `deploy/`.

**C. Cookie-gated injection — the way back to automatic.** If the
load-time capture proves necessary, gate the substitution on a signed
cookie set by a login step rather than on `REMOTE_USER`, and give
injected responses `Cache-Control: no-store`: one URL then serves two
different bodies depending on something no `Vary` header mentions, and
staff and visitors would otherwise trade cached copies.

The trade-off that motivated (A) is real and still unpaid: only a
load-time script captures **errors and failed resource loads that
happen before activation** — which is most of them. The bookmarklet is
for "I am looking at something odd right now"; a testing pass wants (C).

### What a site must carry, and what it may

**Mandatory — one link.** A site says where its reports go, in the head
of every page:

```html
<link rel="corrigenda" href="https://tools.example.com/.corrigenda">
```

Everything reads it: the widget when nothing on its own tag says
otherwise, the bookmarklet, the add-on. Without it a site can only be
reported on by someone whose tool already knows the address — the
bookmarklet falls back to the instance it was built from, the add-on to
the last endpoint it saw, and a first-time user of either has neither.

**Optional — the script.** It puts the widget on the page rather than
waiting to be asked:

```html
<script src="/.corrigenda/corrigenda.js"
        data-endpoint="/.corrigenda/report"
        data-site="www.example.com"
        data-build="2026-08-02.3"
        data-lang="fr" defer></script>
```

The bookmarklet and the add-on put the same widget there on demand, so
this is convenience — with one thing they cannot match, and it is the
trade-off named above: a load-time script is **already listening**, so
the report carries the errors and failed loads from before anyone
noticed. `data-endpoint` overrides the link, which is what a page that
advertises nothing needs, or one pointed at a test instance;
`data-build` should carry the deployed git commit, so every report maps
to a deploy.

## 5. The widget

A single small launcher (fixed, bottom inline-end, respects safe-area
insets). Opening it offers a short menu; the choice decides what is
captured by default:

- **Something looks wrong here** → element picker
- **Text is wrong** → text-selection mode, prefilled with the current selection
- **Something does not work** → picker + error/network log emphasised
- **Suggestion / question** → free text, no picker

### The picker

Devtools-like, with refinements devtools does not need and this does:

- Hover highlight: one absolutely-positioned overlay in the shadow
  root, `pointer-events: none`, plus a label chip showing
  `tag#id.class` and the element's rendered size.
- **Keyboard tree navigation**: ↑/↓ to parent/first child, ←/→ to
  siblings, `Enter` locks, `Esc` cancels. This solves the usual picker
  problem — the interesting element is normally the *container*, not
  the leaf the mouse can hit — and makes the picker keyboard-operable.
- Clicks are intercepted capture-phase and cancelled, so picking a
  link does not navigate.
- **Region select** (drag a rectangle): many visual complaints have no
  single culprit element ("too much space here", "these do not line
  up"). Stored as page coordinates plus the intersecting elements.
  Their nearest common ancestor becomes the element the fragment,
  rules, computed styles and audit describe — *unless* that ancestor is
  `<body>` or `<html>`, which is what a rectangle across a header and a
  footer produces. There the element channels have nothing to describe
  and go unavailable; the list of covered elements is the evidence.
  Adopting `<body>` shipped the whole page as the "element fragment".
- **Two-element mode**: pick A then B, for "these should be aligned /
  the same size". Nearly free once the picker exists.

## 6. Capture model — fine-grained, per report

Every capture channel is an independent, individually toggleable
switch, defaulted by config and overridable per report. Presets
(**Minimal / Standard / Full**) set the switches; a disclosure exposes
the individual controls. The audience is technical, so exposing the
detail is a feature rather than clutter.

Each switch shows a **live size estimate**, with a running total. That
is what makes the fine granularity usable rather than decorative: the
choice between channels is legible at the moment it is made.

### 6.1 Channels

| Channel | Default | Options |
|---|---|---|
| Element fragment | on | prune depth 1 / 3 / unlimited |
| Matched CSS rules | on | matched only / + inherited cascade |
| Computed styles | on | curated subset / all |
| Geometry + environment | on, forced | — |
| Diagnostics | on | errors / + failed resources / + console buffer |
| Screenshot | off | see 6.2 |
| DOM snapshot | off | see 6.3 |
| Mini-audit | off | contrast, target size, alt, overflow |

### 6.2 Screenshot — sub-options

Capture is `getDisplayMedia()`, one frame, opt-in per report. It is
the only method that shows **the user's actual rendering**; the
`html2canvas` / `foreignObject` family re-implements rendering and
therefore erases the very defect being reported, so it is rejected
outright.

- **Scope** — the browser hands back the whole shared surface; the
  client crops before upload, so the discarded pixels genuinely never
  leave the machine: picked element + margin, the viewport, or the full
  surface as captured. (A drag rectangle is specified but not built.)
- **The margin is 16 CSS pixels on every side**, added to the element's
  border box before the crop and therefore multiplied by the device
  pixel ratio in the stored image — 32 device pixels a side on a 2×
  screen, which is why the result looks looser than the outline did. It
  is deliberate: almost every visual defect is a *relationship* — this
  overlaps that, this is out of line with its neighbour, this sits too
  close to the edge — and an element cut out exactly at its own box
  takes the evidence of the relationship out with the surroundings. The
  margin is clipped where the shared surface ends, so an element at the
  edge of the page gets whatever is left rather than a black band.
- **Redaction** — every `input` except checkbox and radio, plus
  `textarea`, `select` and `[data-corrigenda-redact]`, is covered before
  the image is encoded. **Opaque fill, not blur**: a blur over short,
  low-entropy text can be undone, a filled rectangle cannot. The count
  is shown to the reporter and recorded in the payload.
- **The search for them goes through boundaries**, because a count that
  is shown as complete has to be: open shadow roots are descended into
  (they lay out in their host's coordinate space, so no offset is
  needed) and so are same-origin frames, whose rects are offset by the
  frame's content-box origin and clipped to it, composing for a frame
  inside a frame. **A cross-origin frame is covered whole** — its
  contents cannot be inspected, and from outside "there is a password
  in there" and "there is not" are the same silence. **A closed shadow
  root cannot be reached at all, so anything inside one is photographed
  unmasked and uncounted; the widget cannot see it and does not claim
  to.**
- **Output** — WebP, quality stepped 0.8 → 0.6 → 0.45 until the result
  is under the 2 MB cap, longest edge capped at 1600px.
- **Annotation** — drawing rectangles/arrows on the shot: not built.

**Cropping and redaction are conditional, and the condition is
load-bearing.** Both need page coordinates mapped into image
coordinates, and that mapping only exists when the reporter shared
*this tab*. The client calibrates: the frame width over `innerWidth`
gives a scale, and the frame height must agree with `innerHeight ×
scale` within 2%. When it does not — a whole screen, another window,
anything with browser chrome in it — the client **refuses to crop or
redact**, sends the frame untouched, and says so in the panel.

Guessing the offset would paint black bars in the wrong places, and the
reporter would believe their password field was covered when it was
not. A visible "this was not cropped or masked" is the only honest
outcome, so the failure is surfaced rather than silently approximated.

**Where the picture came from is recorded, because the two sources are
not equally trustworthy.** `payload.screenshot.provider` is `extension`
or `display`: **an extension-path image is page-assisted — it is asked
for and delivered over `postMessage` through the page, so a hostile
page can answer in the add-on's place and hand the widget a picture of
its choosing, and nothing in a script running on that page can tell the
difference.** A `display` image came from the browser's own share
dialog and no page code touched it. The widget cannot make the first
case safe; it can name it, so a reviewer weighing a screenshot knows
which kind is in front of them.

### 6.3 DOM snapshot — sub-options

A serialised, self-contained copy of the page, replayable in the
review UI. Gives an *inspectable* page rather than a picture; heavier,
so always explicit.

- **Scope** — picked subtree / nearest sectioning ancestor / whole document
- **Assets** — stylesheets only (light) / + images as data URIs /
  + fonts (heaviest)
- **Text** — verbatim / **layout skeleton**: text nodes outside the
  picked subtree replaced by filler of the same character length,
  which preserves wrapping and therefore the layout behaviour while
  shipping none of the content
- Form values are stripped unconditionally, at every setting.

A future ops script can re-render the reported URL at the reported
viewport with the headless Chromium already in the toolchain, for a
side-by-side against the snapshot. That reproduces on *our* machine,
so it complements the capture rather than replacing it.

### 6.4 Sanitisation, unconditional

Applies before serialisation, at every setting, on a clone:

- drop `<script>`; strip `value`/`checked` from form controls; drop
  `type=password` subtrees entirely
- replace `[data-corrigenda-redact]` contents with a marker
- truncate `src="data:…"` beyond a few hundred bytes
- prune to the configured depth, leaving `<!-- 47 more children -->`
- cap the fragment at ~64 KB

### 6.5 Show me what will be sent

A disclosure in the panel rendering the exact payload before it is
sent. One `<details>`, and it is the difference between a tool that is
trusted and one that is switched off.

## 7. Payload

Versioned JSON (`schema: 1`). Most of it is collected automatically —
a good report should require the reporter to do almost nothing.

**Target**
- CSS selector path (unique `#id` where available, otherwise an
  `nth-of-type` chain up to the nearest id'd ancestor), an XPath
  fallback, and a *fingerprint* (tag, classes, first ~80 chars of
  text, sibling index) so the element remains findable after markup
  drift. The text is the only part of it that is content rather than
  structure, so it is the only part that asks: `[redacted]` when the
  element or an ancestor carries `data-corrigenda-redact`, and absent
  altogether when the element fragment channel is off — otherwise the
  fingerprint quietly undid both.
- sanitised `outerHTML`
- `getBoundingClientRect`, scroll offsets, curated `getComputedStyle`
  (display, position, box metrics, font, colours, overflow)
- **the CSS rules that actually matched**: walk `document.styleSheets`,
  test `el.matches(rule.selectorText)`, report `sheet.href` + selector
  + truncated `cssText`; cross-origin sheets throw on `.cssRules`, so
  catch and note them

  This is the highest-value field. With four sites sharing
  `exhibition-standard.css`, a report that names the file and selector
  is the difference between a five-minute fix and a bisect.

**Environment** — UA + UA-CH, viewport, DPR, effective root font-size
(catches users overriding it), `prefers-color-scheme`,
`prefers-reduced-motion`, `forced-colors`, `prefers-contrast`, `lang`,
timezone, `data-build`.

**Diagnostics** — collected passively when injected at load:
- ring buffer of `window.onerror` / `unhandledrejection`
- **failed resource loads**, via a capture-phase `error` listener on
  `window`: dead images, 404 scripts, dead CDNs — all of which this
  estate has actually hit
- **horizontal overflow flag**: `documentElement.scrollWidth >
  clientWidth`, plus the offending elements from a sweep of
  `getBoundingClientRect().right > innerWidth`. Free, and it turns
  "the page looks weird on my phone" into a named element.
- navigation timing summary

**Screenshot metadata** — when an image is attached, the report carries
`screenshot: { scope, mapped, redacted, bytes }`, so the reviewer can
see whether the image was croppable and how many regions were covered
without opening it.

**Transport** — one `multipart/form-data` POST: `report.json` gzipped
via `CompressionStream('gzip')` (Baseline in both targets), plus
optional `screenshot.webp` and `snapshot.html`. Multipart avoids the
33% base64 tax and Rack parses it natively.

## 8. Endpoint

Sinatra + Puma. Gems are **not yet installed**; `rack 3.1.19` is
present, which Sinatra 4.x targets.

### Mounting — same-origin per site

One Puma process on localhost; every vhost proxies a same-origin path
to it, inside its own auth macro:

```apache
<Macro CorrigendaEndpoint>
    <Location /.corrigenda>
        Use CorrigendaAuth
        RequestHeader set X-Remote-User "expr=%{REMOTE_USER}"
        ProxyPass        unix:/var/run/corrigenda/corrigenda.sock|http://127.0.0.1/
        ProxyPassReverse unix:/var/run/corrigenda/corrigenda.sock|http://127.0.0.1/
    </Location>
</Macro>
```

A unix socket rather than a loopback port, as `gallery.example.com` and
`www.example.com` already do here — no port to allocate, and reachability
is a filesystem permission instead of "any local process may connect".
`/var/run/corrigenda/` rather than their `/tmp`, which is world-writable
and lets any local user race the path before the service binds it.

Auth sits **inside** the macro so a vhost opts in with one line and
cannot mount the endpoint unauthenticated by forgetting a second.

`REMOTE_USER` is a server variable, not a header, so it does not cross
the proxy hop: Apache re-sends it as `X-Remote-User`, and `set` (not
`add`) overwrites anything the client tried to put there. The endpoint
reads that header, falling back to `REMOTE_USER` when no proxy is in
front.

Same-origin removes CORS entirely — which matters here, because
cross-origin requests carrying HTTP Basic/LDAP credentials are
awkward to get right and easy to get subtly wrong. It also means each
site's own auth policy governs its own reports, and the app can read
`REMOTE_USER` straight from the proxied headers.

### Storage — filesystem, no database

```
store/2026/08/<ulid>/report.json
                     screenshot.webp
                     snapshot.html
                     fragment.html
                     state            # open | fixed | wontfix
                     archived         # present, or not
                     journal.jsonl    # what has been done about it
index.jsonl
```

Fits the grain of the estate (static sites, nothing to back up),
greps trivially, and survives a year of neglect. State as a marker
file means no schema migration, ever.

Server-side limits: total payload cap, per-part caps, rejection of
unknown parts. Sanity bounds, not abuse controls.

Retention is a `retention:` key in the deployment config, in days, and
absent by default — nothing expires unless an estate says it should.
Two rules: `archived: N` counts from the moment somebody archived the
report, which is when they said they were done looking at it, and
`any: N` counts from filing, for the ones nobody ever triaged. A report
old enough for both is reported under `archived`, the rule about a
decision rather than about the calendar.

Nothing sweeps on its own. `rake data:purge:show` says what a rule
would take, `rake data:purge` takes it — the split is because deletion
is the one operation here with nothing behind it. Ageing is read off
the report's id and the archive marker's mtime, so no format changed to
support this, and a report whose index line was lost still ages out.

### Enrichment — what the client cannot know

A pass that runs **after** a report lands, never in the request path:
re-open the reported URL in the headless Chromium already in the
toolchain, at the reported viewport, attach CDP, and append what the
browser-side capture is physically unable to produce.

The motivating gap is precise. CSSOM exposes no source positions, so the
client can say `.caption` in `exhibition-standard.css` but never
`exhibition-standard.css:412`; and `el.matches()` throws on a nested
`&` selector, so the client skips nested rules entirely. CDP's
`CSS.getMatchedStylesForNode` has both.

| Collected | From |
|---|---|
| Stylesheet + **line/column range** per matched rule, cascade order, inherited chain, rules that lost | `CSS.getMatchedStylesForNode` |
| Nested `&` rules the client had to skip | same |
| Element screenshot, cropped to the reported rect, no permission prompt | `Page.captureScreenshot` with `clip` |
| Full DOM + computed styles (§6.3 by another route) | `DOMSnapshot.captureSnapshot` |

**Resolution and drift.** The node is found with the stored selector,
falling back to the fingerprint (tag + text + index) when the selector
no longer resolves. A miss is recorded as `resolved: false` — markup
drifts between report and enrichment, and that must never be presented
as a successful reproduction.

**Idempotence.** Output lands in `<report>/enrichment/` beside the
report, with a `status` marker (`ok` / `failed` / `unresolved`), so a
re-run skips what is done and a permanent failure stops retrying.
Enrichment is triggered by a rake task or cron over reports lacking the
marker — never by the POST, which must stay fast and must not depend on
a browser being installed.

**It is a second opinion, not the evidence.** The enrichment renders on
the server: our fonts, our Chromium, no extensions, no user zoom, no
user stylesheet. It must be stored and displayed as a separate block,
clearly labelled, and never merged into the fields the reporter's
browser produced. Where the two disagree — the reporter's rect versus
ours — record the divergence: "cannot reproduce here" is itself a
finding, and often the most useful one.

**Chromium only, by construction.** CDP was removed from Firefox in 141,
and WebDriver BiDi has no CSS-inspection domain, so matched styles with
source positions are not obtainable from Firefox by any supported
protocol. A Firefox report therefore gets its enrichment from Chromium
or not at all — which is another reason the client-side CSSOM walk of §7
stays: it is the only thing that reports the browser the bug was seen
in. If Firefox reproduction is ever wanted for screenshots and console,
Puppeteer 23+ drives it over BiDi.

### The JSON interface, for a program

`/api`, optional, absent unless the deployment's config carries an `api:`
key. Every route, parameter and refusal is in
[openapi.yaml](openapi.yaml) — the only description of the
interface, so there is no second one to fall out of step. What
follows is why it is shaped that way. The review UI is HTML meant for a person; an agent asked to fix
what was reported would otherwise scrape it, and would be reading a
layout rather than a report.

- **Off by default, and 404 when off.** Not 403: a route that is
  switched off should not advertise that it exists. One place decides —
  the app itself — rather than a mount and a config that must agree.
- **Read-only by default.** `write: true` allows a state to be set and
  a report to be archived. **Delete is not offered at any setting**: it
  is the one operation here with nothing behind it, and something that
  acts on its own reading of a situation is the last thing to hand it
  to. The review UI asks twice; that is where it stays.
- **Auth is Apache's, plus an optional token.** Through the vhost it
  is behind the same LDAP block as everything else. A process on this
  host reaches the socket directly and meets no Apache at all, which is
  the intended path; `token: <secret>` puts a Bearer token in front of
  both, compared in constant time.
- **JSON for the refusals too**, including the 404 for an unmatched
  path — a client that has to tell an error from a report by looking at
  it will get it wrong once.
- **It describes itself** at `/api/`: routes, states, channel names,
  whether it may write, the shape of an id. A client that knows nothing
  else can start there — and `openapi.yaml`, served at
  `/api/openapi.json`, is the same thing as a schema, hand-written and
  held to the routes by a test rather than generated from them.
- **Everything done to a report is written down.** A `journal.jsonl`
  beside it, appended and never rewritten: state changes and archiving
  record themselves whichever door they came through — the API, the
  review UI, a task on the host — and a caller adds the reason. Two
  names are kept apart in each entry: `by`, the user the server
  authenticated, and `agent`, what the caller called itself. The second
  is useful and is not identification.

  This is what makes an agent's work checkable. A state that changed
  with nobody able to say why is the thing the trail exists to prevent,
  and it is shown to a person in the review UI and in `rake data:show`,
  not only to the program that wrote it.

### Review UI

Read-only listing plus detail, behind the same `AdminAuth`. Detail
shows the screenshot, the matched CSS rules, and the fragment or
snapshot replayed in a `sandbox`ed iframe. Duplicates grouped by
`hash(url + selector + type)`.

**Deep-link back**: each report yields `https://site/page#fb=<selector>`;
opening it puts the widget in review mode and highlights the element
on the live page. That closes the loop from report to fix.

### Config

One YAML per site: store path, size caps, default capture switches,
prune depth, locale, redaction selectors.

## 9. The widget must not be the bug

It reports on accessibility, so it holds the floor itself:
keyboard-operable throughout, `Esc` always cancels, focus trapped in
the panel and restored on close, `:focus-visible` rings ≥ 3:1 against
whatever sits behind them, targets ≥ 44px, animation behind
`prefers-reduced-motion`, legible under `forced-colors: active`,
`inert` on the launcher while the picker runs.

House CSS rules apply inside the shadow root as everywhere else:
`@layer` ordering, native nesting, logical properties, `is-` / `a-`
prefixes for state and action hooks.

## 10. Phasing

1. **Picker + fragment + matched CSS rules + environment + diagnostics — BUILT.**
   Endpoint stores; review UI lists. This alone identifies most visual
   defects.
2. **Screenshot** with scope and redaction — BUILT (annotation and the
   drag rectangle are not).
3. **DOM snapshot** with scope/assets/skeleton options; replay in the
   review UI.
4. **Deep-link review mode**; the enrichment pass of §8; reports →
   markdown task files in the site repo.
5. **Refinement after the report** (§12) — proposed, unscheduled, and
   the one phase that changes what a report *is*: not a complaint, but
   an agreed rendering with the rules that produce it.

## 11. Open

- Port and host for the Puma process; whether one process serves all
  vhosts or one per environment.
- How often a purge should run, and from where — cron on the host is
  the obvious answer, but nothing has been decided. Retention itself is
  settled: a config key and `rake data:purge` (§8), with no rule set on
  this deployment yet. The store lives on `/var/db/corrigenda`, its own
  ZFS dataset.
- Whether `data-build` can carry the git commit today, or needs a
  build-step change.
- Enrichment has to fetch pages that Apache protects by LDAP or by IP.
  Run it on the host against 127.0.0.1 with a `Host:` header, give it
  credentials, or accept that protected pages are not enriched?
- `console.error`/`warn` capture requires monkey-patching `console`;
  worth it, or too invasive for a tool that must not perturb the page?

## 12. Proposed: refining the fix, in the page, after the report

**Status: proposal. Nothing below is built.**

A report says what is wrong. The thing everyone actually wants next is
the *right* rendering, agreed while the page is still in front of the
person who objected to it — and that conversation currently happens in
a ticket, days later, between people describing a page to each other
from memory.

The proposal: after Send, the widget offers to keep going. The reporter
and a model work on the live page together, the page changing as they
talk, until the reporter approves what they see. What is approved is
stored beside the report, as rules rather than prose, for whoever
implements it for real.

### The shape of a session

1. **Send, then an offer.** The panel that today says *Sent* also says
   *Refine this*. Nothing starts on its own — a report is complete
   without any of this, and the offer is declinable for good.
2. **A turn is a message and a patch.** The reporter says what is
   wrong with what they are looking at ("the caption should clear the
   photo, and keep the small caps"). The service answers with prose
   *and* a patch. The widget applies the patch to the page.
3. **Either side may ask for a measurement.** "Check it at 380
   pixels", "what is the contrast now", "does anything overflow" — the
   widget already computes all three for its reports (§6), so the model
   asks for them rather than guessing, and the answer is a fact from
   the reporter's own browser, not the model's idea of one.
4. **Converge.** Each turn is on top of the last. A *before / after*
   toggle is always one press away, because agreement means nothing if
   nobody can see the two states side by side.
5. **Approve.** The final patch, the transcript, the measurements and
   an after-screenshot are stored beside the report. The state moves to
   something like `agreed`, and the report is no longer a complaint —
   it is a specification with a picture.

### What may be applied, and nothing else

This is the part that decides whether the idea is safe enough to build.

A patch is **declarative and parsed, never executed**:

- **CSS**: a list of rules — a selector and declarations, both
  re-serialised by the widget through the CSSOM before use, so anything
  that is not a valid declaration disappears rather than being applied.
  They go into their own cascade layer, appended last, so removing the
  session is removing one stylesheet.
- **DOM, constrained**: set text of a node, add or remove a class, set
  an attribute from an allowlist that excludes every event handler,
  `src`, `href` and `style`. Applied only within the picked element's
  subtree.
- **Never**: `innerHTML`, script injection, network fetches, or
  anything that survives a reload. The session lives in memory and is
  gone when the tab is closed. The site on disk is not touched by any
  of this — that is the "picked up later" part, and it is deliberate.

The model never talks to the page. The widget posts a turn to the
service, the service talks to the model, and the widget applies what
comes back after checking it. An API key belongs in the deployment
config, never in a page (`api.model:`, beside the `api:` key that already
exists).

### What is stored, and what it is for

Beside the report, on approval:

    proposal.json     the agreed patch, the transcript, the
                      measurements taken, the widths tested
    proposal.css      the same rules, as a stylesheet somebody can read
    after.webp        the page as approved

The report already records, for every matched rule, the stylesheet it
came from and its layer (§6.1). A proposal joins that: *this
declaration, against that rule, in that file*. Whoever implements it —
a person, or an agent through `/api` — starts from a diff-shaped fact
rather than from "the caption looks wrong".

**A proposal is not a patch to the site**, and the distinction is the
whole reason this stops at approval. What the browser needed is
expressed against a rendered page; where it belongs is a MoXoW layer,
a component, a shared stylesheet, possibly a template. Deciding that is
the implementation step, and it needs the repository, not the page.

### Open questions

- **Consent.** A turn sends the fragment, the matched rules and
  possibly a screenshot to a third-party model. That is a new data
  flow, and it should be stated in the panel and refusable per session
  rather than assumed from the report's own opt-ins.
- **Cost and rate.** Turns are cheap individually and unbounded in
  principle. A per-session ceiling, and a per-day one, decided by the
  deployment.
- **Who may refine.** Reading a report and rewriting a page are
  different permissions, even among staff. Probably a third setting
  beside `api.write`, not a consequence of it.
- **Offline.** The same loop is useful with no model at all: the
  reporter tweaks declarations by hand and approves the result. If that
  is built first, the model becomes one participant in an existing
  mechanism rather than the mechanism itself — which is the safer
  order, and probably the right one.
