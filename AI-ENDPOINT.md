# The `/ai` endpoint

The reports, as JSON, for a reader that is a program: an agent asked to
fix what was reported, a script that files a ticket, a dashboard. The
review UI is HTML meant for a person, and scraping it means reading a
layout rather than a report.

Everything here is optional. With no `ai:` key in the deployment
config, every path under `/ai` answers **404** — not 403, because a
route that is switched off should not advertise that it exists.

- [Switching it on](#switching-it-on)
- [Reaching it](#reaching-it)
- [Conventions](#conventions)
- [Routes](#routes)
- [Errors](#errors)
- [A worked session](#a-worked-session)
- [What it will not do](#what-it-will-not-do)
- [If you are the agent reading this](#if-you-are-the-agent-reading-this)

## Switching it on

In `deploy/corrigenda.yml`:

```yaml
ai: true                    # read-only, no token
```

or, with either setting or both:

```yaml
ai:
    write: true             # may set a state and archive
    token: s3cret           # require this as a Bearer token
```

| Key | Default | Meaning |
|---|---|---|
| *(absent)* | — | The endpoint does not exist: 404 everywhere under `/ai` |
| `ai: true` | — | Read-only, no token beyond whatever Apache asked for |
| `write` | `false` | Allow `POST .../state` and `.../archive`. Never delete |
| `token` | none | A shared secret, compared in constant time |

The config is read once, at start: **a change needs a restart of the
service**. `write` is only true when it is YAML's `true` — `write:
"yes"` is a string, and a string is not permission. An empty `token:`
is refused outright rather than read as "no token wanted", since that
would open the endpoint at the moment somebody was closing it.

## Reaching it

**On the host**, through the socket. This is the intended path: it
meets no Apache, so it needs no LDAP credentials.

```sh
curl --unix-socket /var/run/corrigenda/corrigenda.sock \
     http://localhost/ai/reports
```

**Through the vhost**, under the same mount as everything else, behind
the same LDAP block:

```sh
curl -u user https://tools.example.com/.corrigenda/ai/reports
```

Paths below are written from the endpoint root. Through the vhost they
carry the mount prefix; the service is told what that prefix is and
never needs it written down twice.

With a token configured, either header works:

```sh
curl -H "Authorization: Bearer s3cret"   .../ai/reports
curl -H "X-Corrigenda-Token: s3cret"     .../ai/reports
```

## Conventions

- Responses are pretty-printed JSON, `application/json`, except the
  files served by `GET /reports/:id/file/:name`, which come back as
  themselves.
- **Errors are JSON too**, including for an unmatched path: a client
  that has to tell an error from a report by looking at it will get it
  wrong once. The shape is always `{"error": "…"}`.
- POST bodies may be `application/json` or a form post — a shell
  reaches for the second, a program sends the first.
- A **report id** is `YYYYMMDDThhmmssZ-xxxxxxxx`: the filing time in
  UTC and eight hex digits. Anything else is refused as "no such
  report" without the store being touched.
- **States** are `open`, `fixed`, `wontfix`. Archived is not a fourth
  state: a report is archived *and* fixed, or archived and wontfix.
  Archiving says whether anyone still wants it in front of them; the
  state says what happened to the defect.
- **Channels** name what a report carried: `fragment`, `rules`,
  `computed`, `diagnostics`, `audit`, `screenshot`.

## Routes

### `GET /ai/`

What is here, in the words a program needs. A client that knows nothing
else can start from this.

```json
{
  "service": "corrigenda",
  "version": "0.1.0",
  "reports": 5,
  "writable": true,
  "id": "YYYYMMDDThhmmssZ-xxxxxxxx",
  "states": ["open", "fixed", "wontfix"],
  "channels": { "fragment": "element", "rules": "css rules", "…": "…" },
  "routes": { "GET /reports": "…", "…": "…" }
}
```

`reports` counts what is on disk, including anything the index has
lost. `writable` is the config's `write`, so a client can find out
whether a write is worth attempting before attempting it.

### `GET /ai/reports`

The listing, newest first.

| Parameter | Values | Default | Meaning |
|---|---|---|---|
| `archived` | `0`, `1`, `true`, `all` | `0` | The working list, the archive, or both |
| `state` | `open`, `fixed`, `wontfix` | — | Only this state |
| `site` | a hostname | — | Only reports about this site |
| `limit` | an integer | `100` | How many to return. Unparseable falls back to the default |

Filters are applied to the whole store and the limit is applied last,
so `?state=fixed&limit=10` means "the ten newest fixed ones", never
"the fixed ones among the newest ten".

```json
{
  "count": 2,
  "matched": 17,
  "reports": [
    {
      "id": "20260803T133936Z-6a34c0f9",
      "at": "2026-08-03T13:39:36Z",
      "type": "visual",
      "site": "www.example.com",
      "url": "https://www.example.com/",
      "summary": "improve footer. add colophon?",
      "reporter": "sdalu",
      "channels": ["fragment", "rules", "computed"],
      "state": "open",
      "archived": false
    }
  ]
}
```

`count` is how many came back; `matched` is how many answered the
filter. When they differ there is more to ask for — a client that sees
only one number concludes it has seen everything.

`summary` is the first line of the reporter's message. `reporter` is
the name Apache authenticated, or `null` where nobody was asked.

### `GET /ai/reports/:id`

One report in full: the document exactly as it was filed, plus the two
things that are not in it — what has happened to it since, and what
arrived beside it.

```json
{
  "id": "20260803T133936Z-6a34c0f9",
  "state": "open",
  "archived": false,
  "files": ["report.json", "screenshot.webp"],
  "report": { "schema": 1, "type": "visual", "page": { "…": "…" } }
}
```

`files` never lists `state`, which is a marker rather than an
attachment. The shape of `report` is the payload described in
[DESIGN.md §7](DESIGN.md) — what was picked, the rules that matched it,
the computed styles, the environment, the diagnostics, the
accessibility audit — and it is stored verbatim, so a client should
read the keys it knows and ignore the rest.

### `GET /ai/reports/:id/file/:name`

The files beside a report, served as themselves. The name is a path
component, so it is whitelisted:

| Name | Type |
|---|---|
| `screenshot.webp` | `image/webp` |
| `snapshot.html` | `text/html` |
| `report.json` | `application/json` |

Anything else is `404 not servable`. For a visual defect this is the
route that matters: the picture is the report.

### `POST /ai/reports/:id/state`

Requires `write: true`.

```sh
curl -X POST -H 'Content-Type: application/json' \
     -d '{"state": "fixed"}' .../ai/reports/<id>/state
```

Answers the report as `GET /ai/reports/:id` would, with the new state.
An unknown state is `422`, and says which ones exist.

### `POST /ai/reports/:id/archive`

Requires `write: true`.

```sh
curl -X POST -H 'Content-Type: application/json' \
     -d '{"archived": true}' .../ai/reports/<id>/archive
```

`false`, `"false"`, `"0"` and `0` all mean "bring it back"; an absent
body means archive. Answers the report, with `archived` set.

## Errors

| Status | When |
|---|---|
| `400` | A body that claimed to be JSON and was not |
| `401` | A token is configured and the request did not carry it, or carried the wrong one |
| `403` | A write was attempted and the config says read-only |
| `404` | No such report, no such file, no such route — and every path when the endpoint is switched off |
| `422` | A state that is not one of the three |

There is no `429`: this is behind an authenticated vhost on a store
that takes tens of reports a month.

## A worked session

An agent given a site to fix, from nothing:

```sh
SOCK="--unix-socket /var/run/corrigenda/corrigenda.sock"
BASE="http://localhost/ai"

curl -s $SOCK $BASE/                                  # what is here
curl -s $SOCK "$BASE/reports?state=open&site=www.example.com"

ID=20260803T133936Z-6a34c0f9
curl -s $SOCK $BASE/reports/$ID                       # the whole report
curl -s $SOCK -o shot.webp $BASE/reports/$ID/file/screenshot.webp

# …fix it in the site's repository, then:
curl -s $SOCK -X POST -H 'Content-Type: application/json' \
     -d '{"state": "fixed"}' $BASE/reports/$ID/state
curl -s $SOCK -X POST -d '' $BASE/reports/$ID/archive
```

The same store is readable from a terminal with no service running at
all — `rake data:list`, `rake data:show ID=…` — which is the shorter
path when you are already on the host and the question is not
programmatic.

## What it will not do

- **Delete a report.** Not at any setting. It is the one operation here
  with nothing behind it — the directory, the screenshot and the index
  line all go — and something acting on its own reading of a situation
  is the last thing to hand it to. The review UI asks twice, and keeps
  it.
- **Accept a report.** Filing is `POST /report`, which the widget uses
  and which validates a payload against the schema. This endpoint reads
  what was filed.
- **Tell you it is switched off.** That is what the 404 is: a route
  that does not exist looks like a route that does not exist.

## If you are the agent reading this

This file is meant to be handed to you as context. What follows is how
to use the endpoint well, and what not to conclude from it.

### Start by asking, not by assuming

`GET /ai/` before anything else. It tells you the version, how many
reports exist, and **whether you may write** — attempting a write that
the deployment forbids wastes a turn and produces a 403 you then have
to explain. Read `routes` from it rather than from memory: this file
describes the endpoint at the time it was written, and the service in
front of you is the authority.

If every path answers **404**, the endpoint is switched off. That is a
configuration fact, not a routing puzzle: say so, name the `ai:` key,
and stop. Do not go looking for another base path, and do not fall back
to scraping `/review`.

### Reading a report properly

The listing is a summary; `summary` is only the first line of what
somebody typed. Fetch the report itself before forming any view of it,
and **look at the screenshot** — the defect is usually visible in it and
often not describable without it.

Inside `report`, the parts worth your attention:

| Key | What it gives you |
|---|---|
| `page.url`, `page.site`, `page.build` | where it happened, and which deploy |
| `message` | what the reporter saw, in their words. A symptom, not a diagnosis |
| `target.selector`, `target.xpath` | how to find the element again |
| `target.html` | the element as it was, so you can recognise it after a rebuild |
| `target.rules[]` | every CSS rule that matched, with `href` (the stylesheet), `context` (`@layer …`, `@media …`) and `css` (the rule as written) |
| `target.computed` | what the browser actually resolved — box, type, colour, overflow |
| `target.audit` | `contrast`, `targetSize`, `targetTooSmall`: measured, not guessed |
| `environment.viewport`, `device-pixel-ratio`, `color-scheme`, `pointer` | the conditions. A defect at `380x800` is not reproducible at your default width |
| `diagnostics.errors`, `.resources`, `.overflow` | what the page was complaining about at the time |
| `capture` | which channels the reporter switched on. A key absent from here was never captured, and its absence says nothing about the page |

`target.rules[].href` and `context` are the bridge from the browser to
the repository: they name the stylesheet and the cascade layer the rule
came from, which is where a real fix belongs. `css` is cut at 400
characters and `target.html` at the payload cap, both marked where they
end — treat a long one as an identifier and read the real thing in the
repository. `target.fingerprint` (tag, id, classes, text, index) is
what recognises the element again after the selector has stopped
matching.

### Turning a report into a change

1. Reproduce at the reported width, colour scheme and pointer type
   before touching anything. Most "cannot reproduce" is a viewport.
2. Prefer the rule the report already found. `href` plus `selector`
   plus `context` usually locates the exact declaration; changing it
   where it lives beats adding an override somewhere else.
3. `target.audit` is measurement. If `contrast` is 2.37 and
   `targetTooSmall` is true, those are the two things to fix, whatever
   the message said.
4. Verify in the same conditions. The report says what the browser did;
   your fix has to change what the browser does, not what the stylesheet
   looks like.

### Writing back, carefully

Only after the change exists and you have checked it:

```sh
curl -X POST -H 'Content-Type: application/json' \
     -d '{"state": "fixed"}' .../ai/reports/<id>/state
```

- `fixed` means the defect is gone where it was reported, not that a
  commit exists.
- `wontfix` is a decision a person makes. If you believe a report
  should be closed unfixed, say so to whoever asked you and leave it
  `open`.
- Archiving takes it out of the working list. Do that after `fixed`,
  not instead of it.
- **There is no field for a note.** The endpoint stores states, not
  comments, so anything you want the next reader to know belongs in the
  commit message or wherever your work is recorded — do not encode it
  in the state.
- Both writes are idempotent. Setting `fixed` twice is not an error,
  and neither is archiving an archived report.

### Boundaries worth respecting

- You cannot delete a report through this endpoint at any setting, and
  should not ask a human to do it for you as a way around that.
- The screenshot may show real content and real people. It is already
  redacted for form fields and nothing off-screen; treat the rest as
  material belonging to the site's owner.
- The store is small — tens of reports a month. Fetch what you need and
  cache it for the length of your task; there is no pagination beyond
  `limit`, and no rate limit to discover by hitting it.
- If you are running on the host itself, `rake data:list`, `rake
  data:show ID=…` and `rake data:status ID=… SET=…` read and write the
  same store with no service involved. Prefer them when the service is
  down or the question is not programmatic.
