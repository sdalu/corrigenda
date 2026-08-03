# Deploying the endpoint

Route A of CORRIGENDA.md §4: the endpoint is mounted same-origin on
a vhost, and the widget is loaded on demand by a bookmarklet. Nothing is
injected into any page, so no `mod_substitute` and no global httpd.conf
change is involved.

The endpoint itself is **started by hand** with `../run`. There is no
rc.d script and no service account: it runs in a terminal, as whoever
starts it, reading `corrigenda.yml` from here.

**Nothing restarts it on boot or after a crash.** That is the trade for
having nothing to install. If it matters, start it inside tmux or under
a supervisor; the process is an ordinary foreground puma.

## Why the automatic injection is not used

§4 originally gated injection on `<If "%{REMOTE_USER} != ''">`. That
only fires when Apache authenticated the **page**, and of the fourteen
vhosts here only tools.sdalu.com authenticates anything — on the
exhibition sites `REMOTE_USER` is always empty, so the widget would
never appear on precisely the sites whose CSS is under investigation.
`mod_substitute` is also commented out at httpd.conf:106.

If automatic injection is wanted later, gate it on a signed cookie set
by a login step rather than on `REMOTE_USER`, and give injected
responses `Cache-Control: no-store` — the same URL then serves two
different bodies depending on something no `Vary` header mentions.

## How it is wired here

As deployed on this host (pilot: **tools.sdalu.com**), httpd.conf
includes this repo's macro file directly rather than a copy of it:

    Include /web/ops/Corrigenda/deploy/macro-corrigenda.conf

and the vhost carries one line:

    Use CorrigendaEndpoint

That means **no copy to drift** — editing `macro-corrigenda.conf`
here changes the live config at the next reload. It also means this repo
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

One line, kept as a file so it can be edited rather than retyped:
`bookmarklet.js`. It injects the client from whichever host serves
`/.corrigenda/corrigenda.js`; the widget then defaults its endpoint to
`/.corrigenda/report/` **relative to the page**, which keeps the
POST same-origin and inside that vhost's auth.

## Checking it works

    curl --unix-socket /var/run/corrigenda/corrigenda.sock \
         http://localhost/report/health
    curl -u <you> https://<vhost>/.corrigenda/report/health
    curl -u <you> https://<vhost>/.corrigenda/review/

The first proves the endpoint, the second the proxy and the auth, the
third is the listing.
