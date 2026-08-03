# The `/api` endpoint

The reports, as JSON, for a reader that is a program: an agent asked to
fix what was reported, a script that files a ticket, a dashboard. The
review UI is HTML meant for a person, and scraping it means reading a
layout rather than a report.

Everything here is optional. With no `api:` key in the deployment
config, every path under `/api` answers **404** — not 403, because a
route that is switched off should not advertise that it exists.

The same interface as an OpenAPI 3.1 document is
[openapi.yaml](openapi.yaml) in this repository, and the running
service serves it at `/api/openapi.json`. It is written by hand rather
than generated — a description generated from the code only restates
the code — and `test/openapi_test.rb` fails if either drifts from the
other.

- [Switching it on](#switching-it-on)
- [Reaching it](#reaching-it)
- [Conventions](#conventions)
- [Routes](#routes)
- [The schema](#the-schema)
- [Errors](#errors)
- [A worked session](#a-worked-session)
- [What it will not do](#what-it-will-not-do)
- [If you are the agent reading this](#if-you-are-the-agent-reading-this)

## Switching it on

In `deploy/corrigenda.yml`:

```yaml
api: true                    # read-only, no token
```

or, with either setting or both:

```yaml
api:
    write: true             # may set a state and archive
    token: s3cret           # require this as a Bearer token
```

| Key | Default | Meaning |
|---|---|---|
| *(absent)* | — | The endpoint does not exist: 404 everywhere under `/api` |
| `api: true` | — | Read-only, no token beyond whatever Apache asked for |
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
     http://localhost/api/reports
```

**Through the vhost**, under the same mount as everything else, behind
the same LDAP block:

```sh
curl -u user https://tools.example.com/.corrigenda/api/reports
```

Paths below are written from the endpoint root. Through the vhost they
carry the mount prefix; the service is told what that prefix is and
never needs it written down twice.

With a token configured, either header works:

```sh
curl -H "Authorization: Bearer s3cret"   .../api/reports
curl -H "X-Corrigenda-Token: s3cret"     .../api/reports
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
- **Conditional requests work.** A report and each of its files carry
  an `ETag`; send it back as `If-None-Match` and an unchanged one
  answers `304` with no body. A report's tag covers its state, its
  archive marker and the length of its journal — the three things about
  it that can change. The filed document itself never does.

## Routes

### `GET /api/`

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

### `GET /api/reports`

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

### `GET /api/reports/:id`

One report in full: the document exactly as it was filed, plus the two
things that are not in it — what has happened to it since, and what
arrived beside it.

```json
{
  "id": "20260803T133936Z-6a34c0f9",
  "state": "open",
  "archived": false,
  "files": ["report.json", "screenshot.webp"],
  "journal": [
    { "at": "2026-08-03T14:57:43Z", "kind": "state",
      "note": "open → fixed", "by": "sdalu", "agent": "claude" }
  ],
  "report": { "schema": 1, "type": "visual", "page": { "…": "…" } }
}
```

`files` is what was filed with the report, never the markers the
service keeps beside it — the state, the archive flag, the journal.
`journal` is that trail, oldest first, and has a route of its own
below. The shape of `report` is the payload described in
[DESIGN.md §7](DESIGN.md) — what was picked, the rules that matched it,
the computed styles, the environment, the diagnostics, the
accessibility audit — and it is stored verbatim, so a client should
read the keys it knows and ignore the rest.

### `PATCH /api/reports/:id`

Requires `write: true`. The two things about a report that can change,
in one request:

```sh
curl -X PATCH -H 'Content-Type: application/json' \
     -d '{"state": "fixed", "archived": true}' .../api/reports/<id>
```

Any of `state`, `archived`, `note`, `agent` and `refs`; a key that is
none of them is `422` and says which one it objected to — silence
would let a client believe a change happened. `note` is recorded in
the journal beside the change, which is the whole reason it is
accepted here: an agent that has just fixed something has the
sentence to hand, and a second request is how a trail ends up with
states nobody explained. Answers the report as `GET` would.

The two `POST` routes below do the same things one at a time. They stay
because a shell reaches for a URL rather than a verb, and because
`POST .../state` reads like what it does.

### `DELETE /api/reports/:id`

Always `405`, with `Allow: GET, PATCH`. Answered rather than left to
the 404 because a client that tried it has guessed something reasonable
and is owed the reason: deleting takes the directory, the screenshot
and the index line, with nothing behind it, and stays in the review UI,
which asks twice.

### `GET /api/reports/:id/journal`

What has been done about the report, oldest first.

```json
{
  "count": 2,
  "entries": [
    { "at": "2026-08-03T14:57:43Z", "kind": "state",
      "note": "open → fixed", "by": "sdalu", "agent": "claude" },
    { "at": "2026-08-03T14:57:43Z", "kind": "note",
      "note": "raised .caption line-height to 1.5; contrast now 4.8:1",
      "by": "sdalu", "agent": "claude", "refs": ["a1b2c3d"] }
  ]
}
```

Entries are appended and never rewritten — a trail that can be edited
is a trail nobody has to believe. `kind` is `state` or `archive` for
the ones the service writes itself when those change, and `note` for
what a caller said. The same trail is on the report's page in the
review UI and in `rake data:show`, so a change made by a program is
read by a person in the same place as one made by hand.

`by` is the user the server authenticated; `agent` is what the caller
calls itself. They are two different facts and are kept apart: a
program naming itself is useful, and it is not identification.

### `POST /api/reports/:id/journal`

Requires `write: true`. Writing into somebody's record of their own
defect is a write, even though it changes nothing about the report.

```sh
curl -X POST -H 'Content-Type: application/json' \
     -d '{"note": "verified at 380px in Firefox", "agent": "claude"}' \
     .../api/reports/<id>/journal
```

Answers `201` with the entry as recorded. `at` and `by` are the
server's to set: a client cannot backdate an entry or sign it as
somebody else. An entry with an empty note is `422` — a line that says
nothing is worse than no line.

### `GET /api/reports/:id/file/:name`
FROM

b = swap!(b, <<~'FROM', <<~'TO')
Anything else is `404 not servable`. For a visual defect this is the
route that matters: the picture is the report.
FROM
Anything else is `404 not servable`. For a visual defect this is the
route that matters: the picture is the report.

A file never changes, so this route carries `ETag` and `Last-Modified`
and answers `304` to anything that asks twice — worth having, since the
screenshot is the largest thing here by an order of magnitude.

The files beside a report, served as themselves. The name is a path
component, so it is whitelisted:

| Name | Type |
|---|---|
| `screenshot.webp` | `image/webp` |
| `snapshot.html` | `text/html` |
| `report.json` | `application/json` |

Anything else is `404 not servable`. For a visual defect this is the
route that matters: the picture is the report.

### `POST /api/reports/:id/state`

Requires `write: true`.

```sh
curl -X POST -H 'Content-Type: application/json' \
     -d '{"state": "fixed"}' .../api/reports/<id>/state
```

Answers the report as `GET /api/reports/:id` would, with the new state.
An unknown state is `422`, and says which ones exist.

### `POST /api/reports/:id/archive`

Requires `write: true`.

```sh
curl -X POST -H 'Content-Type: application/json' \
     -d '{"archived": true}' .../api/reports/<id>/archive
```

`false`, `"false"`, `"0"` and `0` all mean "bring it back"; an absent
body means archive. Answers the report, with `archived` set.

## The schema

[openapi.yaml](openapi.yaml), and `/api/openapi.json` from a running
service. Everything above is in it: paths, parameters, response shapes,
the security schemes, and the states and file names as enumerations
rather than prose.

It is checked against the service rather than trusted:
`test/openapi_test.rb` asserts that every route is described and every
description has a route behind it, that the version in `info` is the
service's own, that the states are the store's, that the servable file
names are the whitelist, and that the id pattern is the one the app
enforces. A schema that has drifted from what it describes is worse
than none, because it is believed.

Generating clients from it is the point of having it. Nothing here
depends on that: `curl` is a fine client for six routes.

## Errors

| Status | When |
|---|---|
| `400` | A body that claimed to be JSON and was not |
| `401` | A token is configured and the request did not carry it, or carried the wrong one |
| `403` | A write was attempted and the config says read-only |
| `404` | No such report, no such file, no such route — and every path when the endpoint is switched off |
| `405` | `DELETE`, at any setting. Carries `Allow` |
| `422` | A state that is not one of the three, a field a report cannot be told, or a journal entry with nothing in it |

There is no `429`: this is behind an authenticated vhost on a store
that takes tens of reports a month.

## A worked session

An agent given a site to fix, from nothing:

```sh
SOCK="--unix-socket /var/run/corrigenda/corrigenda.sock"
BASE="http://localhost/api"

curl -s $SOCK $BASE/                                  # what is here
curl -s $SOCK "$BASE/reports?state=open&site=www.example.com"

ID=20260803T133936Z-6a34c0f9
curl -s $SOCK $BASE/reports/$ID                       # the whole report
curl -s $SOCK -o shot.webp $BASE/reports/$ID/file/screenshot.webp

# …fix it in the site's repository, then say so and why, in one call:
curl -s $SOCK -X PATCH -H 'Content-Type: application/json' \
     -d '{"state": "fixed", "archived": true,
          "note": "raised .caption line-height to 1.5; contrast 4.8:1",
          "agent": "claude", "refs": ["a1b2c3d"]}' \
     $BASE/reports/$ID

curl -s $SOCK $BASE/reports/$ID/journal        # what the next reader sees
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

`GET /api/` before anything else. It tells you the version, how many
reports exist, and **whether you may write** — attempting a write that
the deployment forbids wastes a turn and produces a 403 you then have
to explain. Read `routes` from it rather than from memory: this file
describes the endpoint at the time it was written, and the service in
front of you is the authority.

If every path answers **404**, the endpoint is switched off. That is a
configuration fact, not a routing puzzle: say so, name the `api:` key,
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
     -d '{"state": "fixed"}' .../api/reports/<id>/state
```

- `fixed` means the defect is gone where it was reported, not that a
  commit exists.
- `wontfix` is a decision a person makes. If you believe a report
  should be closed unfixed, say so to whoever asked you and leave it
  `open`.
- Archiving takes it out of the working list. Do that after `fixed`,
  not instead of it.
- **Say what you did.** Every state change records itself, but only you
  know why. Send the reason with the change:

  ```sh
  curl -X PATCH -H 'Content-Type: application/json' \
       -d '{"state": "fixed",
            "note": "raised .caption line-height to 1.5; contrast now 4.8:1",
            "agent": "claude", "refs": ["a1b2c3d"]}' \
       .../api/reports/<id>
  ```

  A person will read that trail to decide whether to believe the state.
  Write for them: what you changed, where, and how you checked — not
  "fixed the issue". Put commits, file paths or URLs in `refs`.
- **Record work in progress too.** If you looked and did not change
  anything, that is worth a line: "reproduced at 380px, the overflow is
  the nav not the caption". The next reader — often you — starts from
  it instead of from nothing.
- Both writes are idempotent. Setting `fixed` twice is not an error,
  and neither is archiving an archived report. Neither records a second
  entry, so a retry does not litter the trail.

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
