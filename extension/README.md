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

## Why there is no bookmarklet installer

There is no way for a web page to install a bookmarklet: browsers refuse
programmatic bookmark creation, and a `javascript:` URL typed or pasted
into the address bar is stripped. Dragging the link, or right-clicking
it and choosing *Bookmark link*, is the whole of the mechanism. The
toolbar button here is the answer to that — same result, one click, no
dragging.
