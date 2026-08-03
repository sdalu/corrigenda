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

"Crop to the picked element" keeps a **16-pixel margin on every side**,
so the element arrives in its surroundings rather than cut out of them
— most visual defects are about a relationship with something next to
the element, and a crop at its own edges removes exactly that. In the
stored image the margin is multiplied by the screen's device pixel
ratio, which is why it reads as tens of pixels rather than sixteen. It
is trimmed where the shared surface ends.

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

or from the checkout root, where everything else is a rake task:

    rake addon:build
    rake addon:build TARGET=firefox
    rake addon:sign                    # Firefox, signed by AMO

Each target lands in `dist/<target>/` as a loadable directory, and in
`dist/<target>.zip` for signing or handing over. `icon-48.png` and
`icon-128.png` are rendered from `icon.svg` and committed, so a build
needs no browser.

## Install

**Firefox, for a session:** `about:debugging` → This Firefox → Load
Temporary Add-on → pick `dist/firefox/manifest.json`. Gone at restart.

**Firefox, permanently:** the package has to be signed. `rake
addon:sign` does it -- it submits to addons.mozilla.org as an
*unlisted* add-on, which is reviewed automatically and never
published, and leaves the returned `.xpi` at `dist/firefox.xpi` for
the landing page to offer. It needs `AMO_JWT_ISSUER` and
`AMO_JWT_SECRET` in the environment, and says where to get them if
they are missing.

**Chrome:** `chrome://extensions` → Developer mode → Load unpacked →
pick `dist/chrome/`.

The landing page at the mount point serves both zips and repeats these
steps, so nobody has to find this file.

## It is a helper, not a way in

The add-on does not deliver the widget and does not know where reports
go. The widget reaches a page three other ways — the site serves it,
the site advertises the endpoint and you load the bookmarklet, or the
bookmarklet alone — and every one of them already carries the endpoint
with it. A fourth route through the add-on was a second delivery
mechanism to keep in step with the first, and a page-injected
`<script src>` is remotely hosted code by the letter of both stores'
policies. What is left here is the one thing nothing else can do:
photograph the tab in page coordinates.

The injector is still in `background.js`, disabled, with the call that
restores it named in a comment. Its endpoint resolution — the page's
own `<link rel="corrigenda">`, then the last endpoint seen, then the
page's origin — is why it was kept rather than deleted.

## The helper contract

The bridge announces a number on the documentElement,
`data-corrigenda-capture`, and the widget carries the number it
requires. Neither is a release:

| side      | where                  | now |
|-----------|------------------------|-----|
| provided  | `extension/content.js` `HELPER` | 1 |
| required  | `client/corrigenda.js` `HELPER_REQUIRED` | 1 |

Raise the provided number when an exchange changes shape — never for
a fix, a permission, or a release. Below what the page requires, the
widget leaves the add-on alone and takes the share dialog, which is
the honest answer: the two are installed and served separately, so an
add-on older than the page it is on is a normal state of affairs, not
an error. Above is fine, since a helper keeps the exchanges it has
advertised.

`test/version_test.rb` refuses a checkout whose add-on provides less
than its own widget requires, and `test/browser/extension-check.js`
drives a stub advertising an old number to prove the widget ignores
it.

## Permissions, and why

The add-on names no hosts. It ships with none declared and asks for the
site you are on, the first time you press the button there — so adding
a site to the estate is a line in the service's config, not a new build
of the add-on that everyone has to install again.

- `activeTab` — for the capture. It is granted by the click itself
  and goes stale when you navigate away. The capture is always of
  the tab the request came from: the tab id comes from the
  messaging layer, never from the page.
- `scripting` — to register the bridge on the sites you have
  granted. (It is what the disabled injector would use too.)
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

Neither store lists this. It goes out through Firefox's unlisted
channel, which reviews automatically and asks for no listing text. A
public listing would need one thing this does not carry: a written
justification for the broad `*://*/*` optional permission.

## Why there is no bookmarklet installer

There is no way for a web page to install a bookmarklet: browsers refuse
programmatic bookmark creation, and a `javascript:` URL typed or pasted
into the address bar is stripped. Dragging the link, or right-clicking
it and choosing *Bookmark link*, is the whole of the mechanism, and
this add-on does not stand in for it: the toolbar button grants a
site, it does not load the widget.
