# Deploying the endpoint

The endpoint is mounted same-origin on a vhost, and the widget is
loaded on demand — by a bookmarklet, or by a site that asks for it.
Nothing is injected into any page, so no `mod_substitute` and no global
httpd.conf change is involved.

The endpoint itself is **started by hand** with `../run`. There is no
rc.d script and no service account: it runs in a terminal, as whoever
starts it, reading `corrigenda.yml` from here.

**Nothing restarts it on boot or after a crash.** That is the trade for
having nothing to install. If it matters, start it inside tmux or under
a supervisor; the process is an ordinary foreground puma.

Apache serves the endpoint and authenticates it. It does not put the
widget on any page: that is the bookmarklet's job, or the site's own
framework declaration. (Injection was considered and does not work on
this estate — [HISTORY.md](../HISTORY.md) says why, and what would have
to change first.)

## How it is wired here

As deployed on this host, httpd.conf
includes this repo's macro file directly rather than a copy of it:

    Include /web/ops/Corrigenda/deploy/macro-corrigenda.conf

and the vhost carries one line:

    Use CorrigendaEndpoint

That means **no copy to drift between here and Apache** — but the file
itself is generated, because two of the things in it were written
twice. The socket the service binds and the path it is mounted under
are in `corrigenda.yml`, and Apache cannot read YAML:

    ./macro                  rewrite macro-corrigenda.conf from corrigenda.yml
    ./macro --check          say whether it is current (exit 1 if not)
    ./macro --stdout         print it instead of writing
    ./macro --config PATH    read another config, with --stdout

Three things come from the config: the socket, the mount, and the
`auth:` block — `type: ldap` with a `url`, `type: file` with an
htpasswd, or `type: none` for a deployment that asks nobody. `require`
is passed to Apache as written, so `valid-user`, `user alice bob`, or
an `ldap-group`. There is no default for `type`: a config without the
block is refused rather than quietly generating an open endpoint.

Whatever the provider, an unauthenticated `OPTIONS` is let through. A
CORS preflight carries no credentials and cannot be given any, so
gating it turns every cross-origin report into a 401 the page never
sees the reason for.

The result is **not** tracked: it is three fields of the config in
Apache's syntax, and a copy of a config is exactly the drift the
generator exists to prevent. `./run` writes it at every start, so the
file Apache includes always agrees with the service that is running —
a config edited without a restart is a config nobody is running, and a
macro generated from one is worse than none.

What that costs: a fresh checkout has no file for `httpd.conf` to
include, so the service must be started once before Apache is
reloaded. What it buys: a socket in the config and a different socket
in the macro cannot happen, and that failure is a 503 from a proxy
talking to nobody, with nothing anywhere saying why.

    rake macro                    the same, from the repository root
    rake macro:check
    rake macro:show
    rake run ARGS="-p 9393 -f"

Editing the generator, or the config it reads, changes the live
Apache configuration at the next reload. It also means this repo
is production configuration: a bad edit, a rename of the directory, or a
checkout that removes the file breaks *every* vhost the next time httpd
reloads, not just this one. `httpd -t` before every reload.

The ordering constraint is unchanged: the macro must be loaded before a
vhost may `Use` it. The include above sits at httpd.conf:553 and the
vhosts are read at 559, so one reload does both in the right order.

The store is the remaining root step:

    install -d -m 0750 /var/db/corrigenda

owned by whoever starts `../run`. Installing the config to
/usr/local/etc/corrigenda.yml is optional and, on this host,
skipped: `../run` reads `corrigenda.yml` from here, which is the
same file.

## Starting it

    ./run                        # configured socket, store and allowlist
    ./run -p 9393                # a port instead, to reach it directly
    ./run -f -p 9393 -d /var/tmp/store   # fixture playground

## Letting a program read the reports

`corrigenda.yml` decides. With no `ai:` key — the state of this
deployment — every path under `/ai` answers 404. With `ai: true` the
service answers JSON there: the listing, one report, the screenshot as
bytes.

Through the vhost it sits behind the same LDAP block as the review UI,
so nothing new is exposed. On the host itself the socket is the shorter
path and meets no Apache at all:

    curl --unix-socket /var/run/corrigenda/corrigenda.sock \
         http://localhost/ai/reports

Add `write: true` to let it set a state and archive; there is no
delete. Add `token: <secret>` to require a Bearer token as well —
worth it if the endpoint is ever reachable by anything you would not
hand the LDAP password to. Changing any of this needs a restart, since
the config is read at start.

## Keeping the store from growing forever

Nothing expires unless `corrigenda.yml` says so. With a `retention:`
rule set (see the template), the sweep is a command somebody or cron
runs — never the service on its own:

    bundle exec rake data:purge:show   # what it would take
    bundle exec rake data:purge        # take it

Look before you cut: `:show` prints every report with the rule that
selected it and its age in days, and removes nothing. Once the numbers
say what you meant, a crontab line is the rest of it — weekly is plenty
at this volume, and there is no harm in a run that finds nothing:

    12 4 * * 0  cd /web/ops/Corrigenda && \
                CORRIGENDA_CONFIG=deploy/corrigenda.yml \
                /usr/local/bin/bundle exec rake data:purge >/dev/null

A purge takes the report's directory — screenshots and snapshots with
it — and its line in `index.jsonl`, and prunes the month directory it
empties. There is nothing behind it: no trash, no tombstone.

## Why the socket is reachable by Apache

Apache runs as `www` and the socket is 0660, so the group has to be
right or the proxy gets EACCES. It is right because of a BSD detail
rather than anything Puma does: a new file takes the **group of its
directory**, not of the creating process. `../run` makes
`/var/run/corrigenda` group `www` mode 0750, so the socket created
inside it comes out group `www`, and `umask=0117` in the bind URL makes
it 0660. Apache connects; nothing else can see the directory.

Verified on this host: a file created in a `www`-group directory comes
out gid 80.

## The bookmarklet

There is no file for it, and there was one until it went stale: a copy
with a host written into it disagrees with the service the day the
host changes. The landing page builds it in the browser from
`location.origin` and the mount it was served under, so the
bookmarklet you drag is always the one for the instance you are
looking at.

What it does when used: read `<link rel="corrigenda">` on the page it
lands on and load the client from there, so a bookmarklet made on one
instance still does the right thing on a site with an endpoint of its
own. Where the page advertises nothing, the instance that emitted the
bookmarklet is the fallback, and that goes on the tag as
`data-endpoint` — without it the client would post to the page's own
origin, which is a 404 on any site that does not mount the service.

## Checking it works

    curl --unix-socket /var/run/corrigenda/corrigenda.sock \
         http://localhost/report/health
    curl -u <you> https://<vhost>/.corrigenda/report/health
    curl -u <you> https://<vhost>/.corrigenda/review/

The first proves the endpoint, the second the proxy and the auth, the
third is the listing.
