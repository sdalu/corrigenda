# Browser end-to-end test

Drives the real widget in headless Chromium against the real
endpoint. Unit tests (`bundle exec rake test`) cover the endpoint;
this covers the half that only exists in a browser — the picker, the
CSSOM walk, the sanitiser, and the gzipped POST.

Three steps, from `ops/DebugFeedback`:

```sh
# 1. serve the fixture page, the client, and the endpoint together
printf 'store: /var/tmp/debug-feedback-browser-store\n' > /var/tmp/fb.yml
DEBUG_FEEDBACK_CONFIG=/var/tmp/fb.yml \
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
node -r ./shim.js /web/ops/DebugFeedback/test/browser/widget-check.js

# 3. read what landed
ls /var/tmp/debug-feedback-browser-store/*/*/*/report.json
```

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
