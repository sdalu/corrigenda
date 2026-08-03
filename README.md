# Corrigenda

*Corrigenda*: the things to be corrected.

Point at what a page got wrong, on the page itself. What arrives is the
evidence rather than a description of it — the element, the CSS rules
that styled it, what the browser was complaining about at the time, and
a screenshot if you asked for one.

It is a capture tool for the people who run a site, not a public
feedback box: the reporter is already logged in, reports land on disk,
and somebody reads them when they choose to. No mail, no queue, no
moderation.

## What it is made of

A widget (one JavaScript file, CSS inlined, living in a shadow root), a
small Sinatra service that receives and stores reports and shows them
back, and an optional browser add-on that improves one thing: the
screenshot.

    client/corrigenda.js   the widget
    lib/, views/           the service and its two pages
    extension/             the add-on
    deploy/                config and the Apache macro generated from it

Reports are directories, one per report, under a store you name — the
report as JSON, the screenshot beside it, a `state` file, and a
`journal.jsonl` of what has been done about it — plus one
`index.jsonl` line for listing. There is no database, and at tens of
reports a month there does not need to be.

## Getting a report in

Three ways, in the order they cost you anything:

1. **The bookmarklet.** The landing page carries one; drag it to the
   toolbar and it loads the widget on whatever page you are looking at.
   Nothing has to be installed on the site.
2. **The site loads it.** A MoXoW site says
   `corrigenda="https://tools.example.com|<who>"` in its framework
   declaration, and the widget is on the page before its own images
   and scripts have finished failing — so those failures reach the
   report.
3. **The add-on**, alongside either of the above. A page can only
   photograph itself through the browser's screen-sharing permission,
   which cannot crop to an element or black out a password field. The
   add-on takes the picture through the browser's own capture API
   instead. See [extension/README.md](extension/README.md).

A screenshot is optional, and you choose how much of the page it holds.
Cropping to the picked element keeps a 16-pixel margin around it — a
defect is usually a relationship with whatever sits next to the
element, and a crop at its own edges throws that away. On a high-DPI
screen the stored image shows that margin at the screen's own scale, so
it looks like more than sixteen. Form fields are blacked out before the
image is encoded, and nothing off-screen is ever captured.

## Running it

Ruby 3.4, Sinatra 4.2, Puma 8. Gems install into `vendor/`.

    bundle install
    cp deploy/corrigenda-template.yml deploy/corrigenda.yml
    $EDITOR deploy/corrigenda.yml      # the store, the endpoint, who may reach it
    ./run

The config is the deployment: where reports are written, the socket
Apache proxies to, which sites may be reported on, how long a report is
kept. It is not tracked, and the Apache configuration is generated from
it rather than written twice — [deploy/README.md](deploy/README.md) has
the whole wiring, including why the service starts by hand.

To see the widget without any of that:

    ./run -f -p 9393     # then open http://127.0.0.1:9393/fixture.html

## Reading what came in

The review UI is at `/review` behind the same login as the endpoint.
From a terminal on the host, the same store, without the proxy:

    rake data:list                     the working list
    rake data:list ALL=1               with the archived ones
    rake data:show     ID=<report>     one report in full
    rake data:status   ID=<report>     what happened to it…
    rake data:status   ID=<report> SET=fixed NOTE="what you changed"
    rake data:archive  ID=<report>     done looking at it (UNDO=1 to undo)

The listing carries a six-character column for what a report holds —
`E` element, `R` css rules, `C` computed styles, `D` diagnostics,
`A` accessibility, `S` screenshot, a dot where a channel is missing.
The same letters appear on the review UI's chips.

### For a program

Optional, and absent unless the config asks for it: a JSON interface
under `/api`, for a reader that is a program — an agent asked to fix
what was reported, a script that files a ticket. Switch it on with
`api: true`, and it lists reports, hands over one in full, and serves
the screenshot as an image. It describes itself at `/api/`, so a client
that knows nothing else can start there.

    curl --unix-socket /var/run/corrigenda/corrigenda.sock \
         http://localhost/api/reports

It describes itself: [openapi.yaml](openapi.yaml), served at
`/api/openapi.json` and rendered at `/apidocs`, where the masthead
grows an **API** tab on a deployment that has switched it on. In
short: read-only until the config says `write: true`, and even then
it can only set a state, archive, and record what was done —
deleting a report is not offered to a program at all.
`token: <secret>` adds a Bearer token on top of whatever Apache already
asked for. With no `api:` key, every path under `/api` answers 404 rather
than 403 — a route that is switched off should not advertise that it
exists.

Nothing expires unless the config says it should:

    retention:
        archived: 90     # days since somebody archived it
        any:      365    # days since filing, whatever its state

    rake data:purge:show     what that would take, and take nothing
    rake data:purge          take it

## Tests

    bundle exec rake test           the endpoint, ~2 seconds
    bundle exec rake test:browser   the widget, in real Firefox and Chromium

The second half exists because the picker, the CSSOM walk, the
sanitiser and the CORS dance only exist in a browser — see
[test/browser/README.md](test/browser/README.md).

## Where the rest is written down

| | |
|---|---|
| [DESIGN.md](DESIGN.md) | what it captures and why, the payload, the storage model — the reasoning under all of it |
| [HISTORY.md](HISTORY.md) | approaches taken and abandoned, and the failures that shaped what is here |
| [openapi.yaml](openapi.yaml) | the JSON interface in full — the only description of it, rendered at `/apidocs` |
| [deploy/README.md](deploy/README.md) | installing it, the Apache wiring, retention in cron |
| [extension/README.md](extension/README.md) | the add-on: build, install, permissions |
| [test/browser/README.md](test/browser/README.md) | the browser checks and what each covers |
| [CLAUDE.md](CLAUDE.md) | conventions and host quirks, for agents working in this repo |
