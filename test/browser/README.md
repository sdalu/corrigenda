# Browser end-to-end test

Drives the real widget in real headless browsers against the real
endpoint. Unit tests (`bundle exec rake test`) cover the endpoint;
this covers the half that only exists in a browser — the picker, the
CSSOM walk, the sanitiser, the add-on bridge, and the gzipped POST.

```sh
bundle exec rake test:browser     # all four checks, both engines
ONLY="widget" bundle exec rake test:browser
test/browser/run --list           # what each check covers
test/browser/run --help           # and what the runner does
```

`test/browser/run` is the whole recipe below in one command: it starts
the servers on the ports the checks have written into them, finds the
toolchain, runs each check, and stops the servers whatever happens. A
failed run keeps its stores and names the server log; a passing one
takes them away (`--keep` overrides). It is not part of `rake test`
because the browsers are a toolchain this repository does not carry:
a checkout without them should still pass its tests.

It does not go through `../../run`, and deliberately: that script is
the deployment doorway and wants a config naming a deployment, while an
absent config is a valid development config. These checks pass in a
bare checkout.

## Driving the same page yourself

When a check fails, the useful next step is usually to look at the page
it was driving rather than at the check. Serve it, and open it:

```sh
./run -f -p 9393        # the fixture page, the client, and the endpoint
```

`http://127.0.0.1:9393/fixture.html` is then the same page the checks
use, with a real browser and a real screen-capture permission instead
of the stub below. Reports land in a store of their own, away from any
real one.

To run one check against a server you started yourself, keep the ports
(`9393`, and `9397` for the cross-origin pass — they are written into
the checks) and run its script under node with the browser toolchain on
`CHROMIUM`, `NODE_PATH` and `LD_LIBRARY_PATH`. Finding that toolchain
on this host has a trap in it, and the recipe lives in
[CLAUDE.md](../../CLAUDE.md) rather than here.

What landed:

```sh
ls /var/tmp/corrigenda-browser-store/*/*/*/report.json
```

## Four checks, and why three of them run twice

`widget-check.js` is the end-to-end pass: the picker, the CSSOM walk,
the sanitiser, the gzipped POST. Chromium only — it is about the
widget's own logic, which does not vary by engine.

`selection-check.js` runs the **same assertions in Chromium and in
Firefox**, because everything it covers is where the two engines
disagree: selecting words inside a link, which Firefox will treat as a
drag unless the `draggable` attribute says otherwise, and the widget's
own window staying inside the viewport when dragged fast. Both are
failures only one engine has ever shown ([HISTORY.md](../../HISTORY.md)
has the measurements).

The Firefox build sits beside the Chromium one under `browsers/`.
Adding a case here costs nothing; adding one to `widget-check.js`
tests one engine.

`extension-check.js` runs in both too, and tests the widget's half of
the add-on bridge with a **stub content script** — an add-on cannot be
loaded into these runs, but the client's side is where the interesting
questions are: does it use the bridge instead of the share dialog, ask
for the whole document when "no crop" is chosen, crop from the
rectangle it was *given* rather than the one it asked for (Chrome
answers with the viewport whatever you request), and fall back to
`getDisplayMedia` when the bridge fails? The stub answers exactly as
`extension/content.js` does, in three moods: grant the rectangle, grant
only the viewport, refuse.

It also covers detection: the widget asks whether an add-on is there
and waits for an answer, rather than reading a marker once and
believing it, so a check here fails if that ever regresses.

The fixture is built to be broken on purpose: a stylesheet with a
layered and media-nested `.caption` rule (so the CSSOM walk has
context to record), an image that 404s, a 2400px block that forces
horizontal overflow, and a form with a password field — the last one
is there to prove the sanitiser drops it.

Screenshots land in `$SHOTS` (default `/var/tmp`).

## The getDisplayMedia stub

Screen capture cannot be granted to a headless browser, so the test
replaces `navigator.mediaDevices.getDisplayMedia` with a canvas stream
sized to the viewport — and nothing else. Calibration, redaction,
cropping, WebP encoding and the multipart upload all run against it for
real, so the only untested step is the permission dialog itself.

Because the stub canvas is exactly viewport-sized, calibration succeeds
and the redaction bars land on the fixture's two inputs; open the stored
`screenshot.webp` to confirm it.

## The cross-origin pass

`cross-origin-check.js` needs a second server, because it tests the
arrangement a site gets when it does *not* mount the endpoint: the page
on one origin, the endpoint on another.

```sh
# the endpoint, on a second origin (0.0.0.0 so both names reach it)
CORRIGENDA_STORE=/var/tmp/corrigenda-xorigin \
    bundle exec puma -b tcp://0.0.0.0:9397 test/browser/config.ru
```

`test/browser/run` starts that second server only when this check is
among the ones asked for.

The page is served from `127.0.0.1` and the endpoint answers on
`localhost`: same machine, different origin as far as a browser is
concerned. Both are overridable with `PAGE_ORIGIN` / `ENDPOINT_ORIGIN`.

Chromium is launched with Local Network Access turned off. That rule
refuses a request from one loopback origin to another without a
permission a headless run cannot grant — it is about localhost, not
about CORS, and no pair of public https hosts is subject to it. Firefox
needs no such flag, which is worth remembering when one engine passes
and the other does not: the first question is whether the failure is
about the feature or about the address.
