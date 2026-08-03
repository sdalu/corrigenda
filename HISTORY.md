# What was tried

Approaches that were taken and abandoned, and the failures that shaped
what is here now. None of it is needed to run Corrigenda —
[README.md](README.md) is that, and [DESIGN.md](DESIGN.md) is why the
thing is shaped as it is. This file exists so the other documents can
stay in the present tense, and so nobody re-opens a question that was
already answered by measurement.

## Apache was going to inject the widget

The first plan had Apache put the widget on every page itself, with
`mod_substitute`, gated on `<If "%{REMOTE_USER} != ''">` so that only
signed-in staff received it.

That gate cannot work on this estate. It only fires when Apache
authenticated **the page**, and of the fourteen vhosts here only one
authenticates anything: on the exhibition sites `REMOTE_USER` is always
empty, so the widget would have appeared everywhere except the sites
whose CSS was under investigation. `mod_substitute` was also commented
out in `httpd.conf`.

So injection was dropped in favour of loading the widget on demand —
the bookmarklet, or a site that asks for it in its own framework
declaration. Nothing is injected into any page today, and no global
httpd change is involved in deploying this.

If it is ever revisited: gate on a signed cookie set by a login step
rather than on `REMOTE_USER`, and give injected responses
`Cache-Control: no-store`, because the same URL would then serve two
different bodies depending on something no `Vary` header mentions.

## Firefox would not let you select words inside a link

The browser suite ran in Chromium alone at first, and a bug hid there
for as long as it did: in Firefox, words inside a link could not be
selected at all, which is half of what a *content* report is.

Firefox decides at mousedown that a gesture on a link is a drag, and
once it has decided, cancelling `dragstart` stops the drag and still
leaves the selection empty — measured, not assumed. Only the
`draggable` attribute, set before the gesture begins, gives the words
back; `-webkit-user-drag` is ignored there.

A second Firefox-only failure surfaced the same day: the widget's
window clamped itself against a `getBoundingClientRect` that was still
mid-transition, so a fast drag escaped the viewport.

Both are why `selection-check.js` exists and why it runs the same
assertions in both engines.

## The add-on was detected once, at load

The client used to read the add-on's marker attribute a single time,
when it loaded. A marker set a moment later was therefore invisible
forever.

A `document_start` content script always wins that race in practice, so
nothing was observably broken — but depending on an ordering you cannot
see is not the same as being correct, and `extension-check.js` was what
made the difference visible. Detection is live now: the widget asks,
and until something answers it behaves as though there were no add-on.

## The name was DebugFeedback

Until 2026-08-03 the tool was called DebugFeedback, which said what it
was made of. *Corrigenda* — the things to be corrected — says what it
holds, on an estate whose business is publishing. The rename went
through seven roots at once, including the framework attribute sites
use to ask for the widget.

Two things kept the old name for a few hours: the ZFS dataset holding
the store, which is renamed with `zfs rename` and a mountpoint change
rather than with `mv`, and the runtime directory, which is recreated at
every start and so followed at the next restart. Both have since
followed, and nothing on this host answers to the old name.

## The document named after its own repository

The design document was `CORRIGENDA.md` while it was the only document
here. Once a README existed to answer "what is this and how do I run
it", a file named after the repository it sits in said nothing about
its contents, and it became `DESIGN.md`.
