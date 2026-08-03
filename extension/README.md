# Corrigenda capture — the browser add-on

The widget works without this. What the add-on adds is the one thing a
page cannot do for itself: **photograph its own tab**.

From a page, `getDisplayMedia` is the only way to take a screenshot, and
it asks the user to share a surface. Firefox offers a window or a whole
screen and no tabs at all, so the frame that comes back cannot be mapped
to page coordinates — which is why, in Firefox, the widget can neither
crop to the picked element nor mask form fields, and says so in a
warning. Chrome can share a tab, but only if the user picks the right
entry in the dialog.

An extension has `tabs.captureTab` (Firefox) or `tabs.captureVisibleTab`
(Chrome): no dialog, and a frame that is already in page coordinates.

|                                   | bookmarklet / injected | Firefox add-on | Chrome add-on |
|-----------------------------------|:----------------------:|:--------------:|:-------------:|
| Share dialog per screenshot       | yes                    | no             | no            |
| Crop to the picked element        | Chrome only            | yes            | yes           |
| Mask form fields                  | Chrome only            | yes            | yes           |
| Below the fold ("no crop")        | no                     | **yes**        | no            |
| Puts the widget on any page       | drag a bookmarklet     | toolbar button | toolbar button|

Firefox's `rect` is in CSS pixels **relative to the page** and may lie
outside the visible viewport (Firefox 82+), which is what makes a real
full-page capture possible. Chrome has no equivalent, so it answers with
the viewport whatever was asked for — and says so, which is why the
client crops from the rectangle it was *given* rather than the one it
requested. That is the only place the two browsers differ.

## What is here

    manifest.firefox.json   event page, SVG icon
    manifest.chrome.json    service worker, PNG icons
    background.js           the privileged half: capture, and the button
    content.js              the bridge, injected at document_start
    build                   writes dist/<target>/ and dist/<target>.zip

`background.js` and `content.js` are shared, and branch on the API they
find (`browser` or `chrome`, `captureTab` or not) rather than on the
browser they think they are running in.

## Build

    ./build              # both
    ./build firefox      # one

Each target lands in `dist/<target>/` as a loadable directory, and in
`dist/<target>.zip` for signing or handing over. `icon-48.png` and
`icon-128.png` are rendered from `icon.svg` and committed, so a build
needs no browser.

## Install

**Firefox, for a session:** `about:debugging` → This Firefox → Load
Temporary Add-on → pick `dist/firefox/manifest.json`. Gone at restart.

**Firefox, permanently:** the package has to be signed. Submit
`dist/firefox.zip` to addons.mozilla.org as an *unlisted* add-on; AMO
returns a signed `.xpi` that installs anywhere without being published.

**Chrome:** `chrome://extensions` → Developer mode → Load unpacked →
pick `dist/chrome/`.

The landing page at the mount point serves both zips and repeats these
steps, so nobody has to find this file.

## Where it sends reports

It carries no endpoint of its own — not one written in at build time,
not one you are asked to type. Three answers, in order:

1. `<link rel="corrigenda">` on the page. **This is the one thing a
   site must carry**, and MoXoW emits it for every page of a configured
   site, whether or not that client got the widget.
2. The last endpoint this add-on saw. One prepared page teaches it, in
   passing, so the toolbar button then works on pages that say nothing:
   an app behind the same login, a static page, anything never prepared
   for this.
3. The page's own origin, which is right for a site that mounts the
   service itself.

So a site that carries the link needs nothing else for the add-on to
work. Carrying the script as well is a separate choice, and it buys an
earlier start rather than a capability: a load-time script is already
listening when the page's own errors and failed loads happen.

## Permissions, and why

The add-on names no hosts. It ships with none declared and asks for the
site you are on, the first time you press the button there — so adding
a site to the estate is a line in the service's config, not a new build
of the add-on that everyone has to install again.

- `activeTab` — for the capture, and for the first click on any page.
  It is granted by the click itself and lasts until you navigate away,
  which is exactly as long as the widget needs. The capture is always of
  the tab the request came from: the tab id comes from the messaging
  layer, never from the page.
- `scripting` — for the toolbar button, which injects the widget on the
  page in front of you.
- `storage` — for the last endpoint seen, and nothing else.
- `optional_host_permissions: *://*/*` — nothing is granted by
  installing. Granting a site, at the prompt the first click raises,
  registers the bridge on it: a page that carries the widget itself then
  gets a mapped capture without anyone pressing the button first.
  Revoke the site in the add-on's permissions and it goes back to
  button-only, which still works — nothing else breaks.

The content script accepts messages only from its own window and origin,
and only in the shape the widget sends. The background half validates
the rectangle and bounds the scale before handing anything to the
browser.

The prompt is raised as the first statement of the click handler,
before the injection and before any check of what is already granted.
That is not a preference: a handler that has awaited anything is no
longer a user input handler, so `permissions.request` after an `await`
fails outright — Firefox drops the handler's privileged status,
Chrome throws *This function must be called during a user gesture*.
Asking without checking first costs nothing, since an origin already
held is granted silently. A refusal is remembered in memory for as long
as the background context lives, which is what keeps a second click
from nagging; storage would have to be awaited.

## Its version is its own

The add-on is versioned separately from the service, and the separation
is the point: this is *installed*, not served. A browser may be carrying
any build ever handed out, while the service is only ever the one it is
running — and AMO requires the number to rise with every upload, on a
cadence that has nothing to do with how often the endpoint changes.
Tying the two together would either invalidate a signed package you have
already distributed or stamp a number on code that has not changed.

The number lives in each manifest, because a manifest must be readable
on its own — by a browser loading it, by `addons-linter` checking it —
with nothing generated first. Both must say the same thing, since the
two packages are one add-on, so there is one command:

```sh
rake addon:version              # what they say now
rake addon:version TO=0.2.0     # write both, rebuild the packages
```

`test/version_test.rb` fails if they ever disagree, and the landing page
prints the version out of the package it is offering, so a reader can
see which build they are downloading.

## What the browsers require

`extension/build` produces a package for each, and `npx addons-linter
dist/firefox` reports it clean. The floors are set by the newest key
each manifest carries:

- **Firefox 140** (Android 142) — `data_collection_permissions`, which
  AMO now requires of new extensions. `optional_host_permissions`
  itself only needs 128.
- **Chrome 102** — `optional_host_permissions`, declared as
  `minimum_chrome_version`.

The Firefox package declares `websiteContent` as data it collects: the
picture it takes is what a website is showing, and it is taken so that
the picture can be filed. Strictly the add-on transmits nothing itself
— it hands the capture to the page in the tab it came from, and the
page uploads it when you press Send — so `"required": ["none"]` is
arguable. Declaring the content is the honest reading of what happens
next, and under-declaring is what fails a review.

Neither store has seen this. Two things would come up if one did: the
toolbar button adds a `<script src>` from the endpoint to the page,
which is remote code by the letter of both policies (it is the same
script the site serves itself, and the same one the bookmarklet
loads), and a broad `*://*/*` optional permission needs a justification
in the listing. Both are reasons this is distributed as an unlisted
signed build rather than through a store.

## Why there is no bookmarklet installer

There is no way for a web page to install a bookmarklet: browsers refuse
programmatic bookmark creation, and a `javascript:` URL typed or pasted
into the address bar is stripped. Dragging the link, or right-clicking
it and choosing *Bookmark link*, is the whole of the mechanism. The
toolbar button here is the answer to that — same result, one click, no
dragging.
