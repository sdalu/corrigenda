# Working in this repository

Notes for an agent working here. Everything a person needs is in
[README.md](README.md), [DESIGN.md](DESIGN.md) and the READMEs
under `deploy/`, `extension/` and `test/browser/`; what follows is the
part that would be noise in those — the host's quirks, the guards that
will fail a commit, and the habits this codebase is written in.

**Where a sentence belongs.** The READMEs are written in the present
tense: how it works now, and what it will not do. What was tried and
abandoned, and the bug that made a decision, go in
[HISTORY.md](HISTORY.md); why it is shaped as it is goes in DESIGN.md;
anything only an agent needs comes here. When you fix something, the
fix is documented where it works — the story of it, if it is worth
keeping, goes to HISTORY.

## The shape of it

    lib/corrigenda/   intake, review, store, config, schema, prefix
    client/           corrigenda.js — the whole widget, CSS inlined
    views/            the landing page and the review UI (Erubi)
    extension/        the browser add-on, sources and build script
    deploy/           config template, the Apache macro generator
    test/             unit suites; test/browser/ drives real browsers

`lib/corrigenda.rb` is the umbrella: it defines `VERSION` and the error
family (`Error`, `PayloadError`, `StorageError`) and requires the rest.
**Require it, not the individual files** — rescuing `StorageError` after
`require "corrigenda/store"` alone raises `NameError`, which is how a
bad report id once came back as a rake backtrace instead of a sentence.

## Running things

    bundle exec rake test           unit suites, ~2s, no network
    bundle exec rake test:browser   the real-browser checks (below)
    bundle exec rake -T             everything else: data:*, macro:*, addon:*

`./run` starts the service in the foreground; `./run -f -p 9393` serves
the fixture page too and is the fastest way to look at the widget.
Nothing supervises the service — **do not restart the running one
unless asked.** It is started by hand, by its owner, and a config edit
does not reach it until they do.

`rake data:purge` deletes reports and has nothing behind it. Run
`rake data:purge:show` first, always, and never point either at the
deployment's store to try something out — `CORRIGENDA_CONFIG=` a
throwaway config instead.

## The browser checks, and finding the browsers

`test/browser/run` (behind `rake test:browser`) starts the servers,
finds the toolchain and runs the four checks. The toolchain is not in
this repository and not installed by it: it is a playwright-core plus
browser build that happens to be on this host, under

    /root/.claude/tools/playwright-chromium

**Probe for a file it must contain, never for the directory.** On
2026-08-02 both that path and `/compat/linux/root/.claude/...` existed
and only the second was populated, so a `Dir.exist?` test picked the
empty husk and node died on a missing executable. Which side holds the
real tool is a property of the moment:

    TOOLS=$(ruby -e 'b = "/root/.claude/tools/playwright-chromium"
                     puts ["/compat/linux#{b}", b].find { File.exist?("#{it}/shim.js") }')

Then `CHROMIUM=$TOOLS`, `NODE_PATH=$TOOLS/node_modules`,
`LD_LIBRARY_PATH=$TOOLS/libs/usr/lib64:$TOOLS/libs/lib64`, and run node
from inside `$TOOLS` — playwright-core resolves the browsers it launches
relative to where it is installed. `test/browser/run` does all of this;
prefer it, and reach for the raw commands only when a check fails and
you want to drive the same page yourself.

## Reading the reports as a program

If the deployment's config carries an `ai:` key, the service answers
JSON under `/ai` — the listing, one report in full, and the screenshot
as bytes. On this host, reach it through the socket rather than through
Apache, which saves needing a login:

    curl --unix-socket /var/run/corrigenda/corrigenda.sock \
         http://localhost/ai/reports

`GET /ai/` describes itself: the routes, whether writes are allowed,
the id format. Writes (`POST /ai/reports/:id/state`, `.../archive`)
answer 403 unless the config says `write: true`, and there is no delete
at all — that stays in the review UI, which asks twice.

Without the key every path there is a 404, so the first thing to check
when it seems missing is the config and not the code. From a terminal
`rake data:list` and friends read the same store with no service at
all.

## The host splits paths

This host runs a Linux compatibility layer: a Linux-side process
resolves `/web/X` by trying `/compat/linux/web/X` first. So a write
addressed to a file under `/web` can land in a shadow while the real
file stays untouched, and a listing can look inconsistent afterwards.

- Ruby is a native build; the shell and the editing tools may not be.
  When something must land natively, write it with Ruby.
- **Verify every write into `/web` with `git status`, not with `ls`.**
  A new file must appear as untracked; a changed one as modified.
- If a shadow appears (`/compat/linux/web/...`), do not try to clear it
  yourself — the permission classifier refuses. Save what is in it,
  hand the owner `! rm -rf /compat/linux/web`, then write again.
- The session scratchpad is itself already a `/compat/linux` path and
  may be resolved twice. Never put one in a command handed to the
  owner's shell: their shell will not find it.

## Guards that will fail a commit

- `test/tracked_files_test.rb` refuses **any private hostname of this
  estate in a tracked file**. Use `example.com`. This caught a CSS
  comment naming a site as an example of a long name — the guard is not
  only about code.
- `test/version_test.rb` keeps `VERSION` in step across `lib/`, the
  widget, and both add-on manifests. Change it with
  `rake addon:version TO=...`, which also rebuilds the packages.
- `test/deploy_test.rb` checks the generated Apache macro against the
  config it comes from.

Never commit: `deploy/corrigenda.yml` (it names a deployment),
`deploy/macro-corrigenda.conf` (generated at every start),
`extension/dist/` (built in a second), `vendor/`, `store/`.

## The voice

Ruby 3.4, four-space indent, 80 columns, `frozen_string_literal`, double
quotes, `it` for single-argument blocks, endless `def` for
single-expression methods.

Comments here explain **why**, in prose, and often record what was tried
and did not work — the Firefox drag that made a link's words
unselectable, the marker read once at load, the dataset that could not
be renamed with `mv`. When you write one, write that kind: the next
reader's question, answered. Commit messages are the same voice, a
sentence-shaped subject and prose below it.

When patching a file with a script, anchor on exact text and **assert
the hit count** before substituting; a heredoc's `<<~` will strip the
indentation an anchor depends on, and `gsub`'s replacement string eats
`\1`. Both have cost time here.
