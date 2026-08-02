# Deploying the endpoint

Route A of DEBUG-FEEDBACK.md §4: the endpoint is mounted same-origin on
a vhost, and the widget is loaded on demand by a bookmarklet. Nothing is
injected into any page, so no `mod_substitute` and no global httpd.conf
change is involved.

The endpoint itself is **started by hand** with `../run`. There is no
rc.d script and no service account: it runs in a terminal, as whoever
starts it, reading `debug-feedback.yml` from here.

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

## Install (root, once)

    # the store, owned by whoever will start ../run
    install -d -m 0750 /var/db/debug-feedback

    # the config, so the file and the installed copy do not drift
    install -m 0644 deploy/debug-feedback.yml /usr/local/etc/debug-feedback.yml

    # the apache macros
    install -m 0644 deploy/macro-debug-feedback.conf \
        /usr/local/etc/apache24/Includes/macro-debug-feedback.conf

Then add ONE line inside the pilot vhost, in
`/web/sites/<name>/conf/apache.conf`:

    Use DebugFeedbackEndpoint

and check before reloading:

    httpd -t && /usr/local/etc/rc.d/apache24 reload

The macro file has to be loaded before a vhost may `Use` it;
`Includes/*.conf` is read at httpd.conf:513 and the vhosts at 553, so
one reload does both in the right order.

## Starting it

    ./run                        # configured socket, store and allowlist
    ./run -p 9393                # a port instead, to reach it directly
    ./run -f -p 9393 -d /var/tmp/store   # fixture playground

## Why the socket is reachable by Apache

Apache runs as `www` and the socket is 0660, so the group has to be
right or the proxy gets EACCES. It is right because of a BSD detail
rather than anything Puma does: a new file takes the **group of its
directory**, not of the creating process. `../run` makes
`/var/run/debug-feedback` group `www` mode 0750, so the socket created
inside it comes out group `www`, and `umask=0117` in the bind URL makes
it 0660. Apache connects; nothing else can see the directory.

Verified on this host: a file created in a `www`-group directory comes
out gid 80.

## The bookmarklet

One line, kept as a file so it can be edited rather than retyped:
`bookmarklet.js`. It injects the client from whichever host serves
`/common/js/debug-feedback.js`; the widget then defaults its endpoint to
`/.debug-feedback/report/` **relative to the page**, which keeps the
POST same-origin and inside that vhost's auth.

## Checking it works

    curl --unix-socket /var/run/debug-feedback/debug-feedback.sock \
         http://localhost/report/health
    curl -u <you> https://<vhost>/.debug-feedback/report/health
    curl -u <you> https://<vhost>/.debug-feedback/review/

The first proves the endpoint, the second the proxy and the auth, the
third is the listing.
