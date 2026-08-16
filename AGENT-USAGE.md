# Driving the review, as an agent

This file is for the agent pointed *at* a deployment: asked to read
the reports, fix what they name, and write down what happened. If you
are working on Corrigenda's own code, this is not your file —
[CLAUDE.md](CLAUDE.md) is.

And the review is not code review. A report names a defect in what a
page *shows* — the rendered, served content, at a viewport and colour
scheme somebody was actually looking at. Source is only where the fix
lives; the page is where the defect lives, and the only place it can
be verified gone. Nothing below asks you to judge code, and no diff,
however clean, settles a report — the rendered page does.

Nothing here names a deployment, deliberately. The running service is
the authority for its own specifics: its landing page prints a prompt
with the socket it actually listens on, a site it actually accepts
reports about, and what you are allowed to do there. Start from that
prompt when you are handed one; what follows is the part that is true
of every deployment and so cannot drift. A running deployment serves
this very file at `/agent-usage.md`, beside a `/llms.txt` that points
to it — nothing here needs a checkout.

## Finding your footing

Ask the interface before assuming anything about it:

- `GET /api/` first. It says which routes exist, which changes this
  deployment allows, and what a report id looks like — learn what you
  may do rather than discovering a 403 halfway through a task.
- `GET /api/openapi.json` is the full schema, rendered at `/apidocs`.
  Every operation carries a note addressed to you — read it before
  deciding how to use anything.
- If every path under `/api` answers 404, the interface is switched
  off (`api:` absent from the config). That is a configuration to
  raise with the owner, not a bug to hunt.
- A 403 on a write means the deployment has not granted it. Say which
  grant was missing and what you would have written; do not look for
  a way around it.

On the deployment's own host the service usually listens on a socket
(`curl --unix-socket <socket> http://localhost/api/...`), which saves
needing a login; the landing page and `deploy/` config say where.
Without a running service at all, `rake data:list`, `data:show` and
`data:status` read and write the same store from a terminal.

## The loop

`GET /api/sites` says which sites have open reports. Work through
them — `GET /api/reports?state=open`, with `&site=` when you were
asked for one site rather than all — and for each report:

1. **Read it in full**, screenshot included. The report is evidence,
   not a description: the element, every CSS rule that matched it and
   the stylesheet and cascade layer each came from, what the browser
   was complaining about at the time.
2. **Reproduce the defect at the viewport and colour scheme the
   report names.** A defect reported at 320 px in dark mode is not
   confirmed — or refuted — at 1200 px in light.
3. **Fix it where the rule lives.** The report tells you which
   stylesheet and layer produced each matching rule; prefer changing
   it there over adding an override somewhere downstream.
4. **Verify under the same conditions**, and take an after-picture
   the same way the report's own screenshot was taken.
5. **Journal it** (below). If you may set state and the defect is
   verified gone, set `proposed`; if the report needs a decision
   rather than a change, leave it open and say what decision it
   needs.

*Fixed* is not your call to make. When the defect is verified gone
under the conditions the report names, the state you set is
`proposed` — the claim before the confirmation, and what tells the
reviewer to look. `fixed`, like `wontfix`, is a person's decision
after their own look: set it only when the person driving you has
explicitly said to, in this run's instructions. And "I changed
something" is not even `proposed` — somebody will trust the state and
stop checking behind it.

## The journal

Every report carries a journal, appended and never rewritten. State
changes write their own line; the reason is yours to add — `PATCH`
with a `note`, or `rake data:status ID=… SET=… NOTE="…"`. A person
reads that trail to decide whether to believe the state, so write for
them: what changed, where, and how you checked it. Work that changed
nothing is worth a line too.

A line can carry a picture — `image: {data: "<base64 or a data:
URL>"}` beside the note, or `SHOT=after.webp` on the rake task. It is
filed with the report and shown beside the screenshot it was filed
with, which is the comparison somebody wants before believing
"fixed". The image takes `viewport` and `scheme` beside `data`: say
what the picture was really taken at, because the page prints those
next to the conditions the report names, and a comparison made under
others should be visible rather than assumed.

## What is never yours

- **The word `fixed`.** Yours is `proposed`, and only once you have
  verified. `fixed` and `wontfix` belong to a person; an explicit
  instruction in the task you were given is the one thing that makes
  `fixed` yours to set.
- **Deleting a report.** Refused at every setting — the API answers
  405 however the deployment is configured. If a report should not
  exist, that is a person's call in the review UI; do not ask a human
  to run the deletion for you as a way around it.
- **Grants you were not given.** `write: [journal]` alone is a common
  and deliberate configuration: record what you found and what you
  believe the state should be, and a person moves it.
- **Expiry.** `rake data:purge` deletes reports with nothing behind
  it. It is retention housekeeping, not review work — leave it to the
  store's owner.
