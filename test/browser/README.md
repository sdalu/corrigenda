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

## By hand

Worth knowing when a check fails and you want to drive the same page
yourself. Three steps, from `ops/Corrigenda`:

```sh
# 1. serve the fixture page, the client, and the endpoint together
printf 'store: /var/tmp/corrigenda-browser-store\n' > /var/tmp/corrigenda.yml
CORRIGENDA_CONFIG=/var/tmp/corrigenda.yml \
    bundle exec puma -b tcp://127.0.0.1:9393 test/browser/config.ru

# 2. drive it (see the headless-Chromium recipe in Common/CLAUDE.md).
#    node is a native FreeBSD build and the shell is not, so the two can
#    disagree about what an absolute path means. Which spelling holds the
#    real tool is NOT fixed -- probe it, once, at the start of a session:
TOOLS=$(ruby -e 'b = "/root/.claude/tools/playwright-chromium"
                 puts ["/compat/linux#{b}", b].find { File.exist?("#{it}/shim.js") }')

cd "$TOOLS"
export LD_LIBRARY_PATH="$PWD/libs/usr/lib64:$PWD/libs/lib64"
export NODE_PATH="$TOOLS/node_modules"
export CHROMIUM="$TOOLS"
node -r ./shim.js /web/ops/Corrigenda/test/browser/widget-check.js
node -r ./shim.js /web/ops/Corrigenda/test/browser/selection-check.js
node -r ./shim.js /web/ops/Corrigenda/test/browser/extension-check.js

# 3. read what landed
ls /var/tmp/corrigenda-browser-store/*/*/*/report.json
```

## Four checks, and why three of them run twice

`widget-check.js` is the end-to-end pass: the picker, the CSSOM walk,
the sanitiser, the gzipped POST. Chromium only — it is about the
widget's own logic, which does not vary by engine.

`selection-check.js` runs the **same assertions in Chromium and in
Firefox**, because everything it covers is exactly where the two
engines disagree. It was written after a bug that was invisible for as
long as the suite ran in Chromium alone: words inside a link could not
be selected in Firefox at all. Firefox decides at mousedown that a
gesture on a link is a drag, and once it has decided, cancelling
`dragstart` stops the drag and still leaves the selection empty —
measured. Only the `draggable` attribute, set before the gesture
begins, gives the words back; `-webkit-user-drag` is ignored there.
A second Firefox-only failure surfaced the same day: the window's
clamp read a `getBoundingClientRect` that was still mid-transition, so
a fast drag escaped the viewport.

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

It also found a real fragility: the client used to read the add-on's
marker once at load, so a marker set a moment later was invisible
forever. A `document_start` content script always wins that race, but
depending on an ordering you cannot see is not the same as being
correct — detection is live now.

The fixture is built to be broken on purpose: a stylesheet with a
layered and media-nested `.caption` rule (so the CSSOM walk has
context to record), an image that 404s, a 2400px block that forces
horizontal overflow, and a form with a password field — the last one
is there to prove the sanitiser drops it.

Screenshots land in `$SHOTS` (default `/var/tmp`).

Probe for a **file** the tool must contain, not for the directory: on
2026-08-02 both spellings of the directory existed and only the
`/compat/linux` one was populated, so a `Dir.exist?` test picked the
empty husk and node failed on a missing executable. Which side is
populated is a property of the moment, not a rule.

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

node -r ./shim.js /web/ops/Corrigenda/test/browser/cross-origin-check.js
```

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
