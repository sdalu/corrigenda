# Working in this repository

Notes for an agent working here. Everything a person needs is in
[README.md](README.md), [DESIGN.md](DESIGN.md) and the READMEs
under `deploy/`, `extension/` and `test/browser/`; what follows is the
part that would be noise in those — the guards that will fail a commit
and the habits this codebase is written in. The host's quirks are one
level up, in [`/web/CLAUDE.md`](../../CLAUDE.md): which binary sees
which filesystem, how to find the browser toolchain, patch-script
traps. The general working rules are in `~/.claude/CLAUDE.md` and the
AI-BASELINE it imports.

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
browser build that happens to be on this host, and finding it —
probing for a file rather than for the directory, and the environment
it wants — is in `/web/CLAUDE.md`. `test/browser/run` does all of that,
so prefer it, and reach for the raw commands only when a check fails
and you want to drive the same page yourself.

## Reading the reports as a program

Driving a deployment — listing reports, the review loop, the journal
voice, what is never the agent's to do — is
[AGENT-USAGE.md](AGENT-USAGE.md)'s
subject, kept out of this file so the agent fixing a site never needs
the dev conventions, and the agent working here is not handed the
operator's. Read it before touching the store or the API, even from a
dev session. What stays here is only what is true of this checkout's
host: reach the deployment through its socket rather than through
Apache, which saves needing a login —

    curl --unix-socket /var/run/corrigenda/corrigenda.sock \
         http://localhost/api/reports

— and remember that without an `api:` key in the config every path
under `/api` is a 404, so the first thing to check when it seems
missing is the config and not the code.

## Guards that will fail a commit

- `test/tracked_files_test.rb` refuses **any private hostname of this
  estate in a tracked file**. Use `example.com`. This caught a CSS
  comment naming a site as an example of a long name — the guard is not
  only about code.
- `test/version_test.rb` keeps `VERSION` in step between `lib/` and the
  widget — bump both by hand together. The add-on's version is its own
  (installed, not served); the test only requires the two manifests to
  agree with each other, and `rake addon:version TO=...` is what raises
  it and rebuilds the packages.
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

Patch scripts, and the traps in them, are in `/web/CLAUDE.md`: both of
the ones named there cost time in this repository first.
