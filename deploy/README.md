# Deploying the endpoint

Route A of DEBUG-FEEDBACK.md §4: the endpoint is mounted same-origin on a
vhost, and the widget is loaded on demand by a bookmarklet. Nothing is
injected into any page, so no `mod_substitute` and no global httpd.conf
change is involved.

## Why not the automatic injection

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

## Just trying it?

`../run-local` runs the endpoint from the working copy with no service
account, nothing in /usr/local/etc and nothing to uninstall:

    ./run-local -f          # fixture page + client + endpoint, port 9393
    ./run-local -s /tmp/x.sock   # over a unix socket, as deployed

Nothing below is needed for that.

## Install (needs root; nothing here does it for you)

    # 1. service account and directories
    pw useradd debugfeedback -d /nonexistent -s /usr/sbin/nologin -c "Debug feedback endpoint"
    install -d -o debugfeedback -g debugfeedback -m 0750 /var/db/debug-feedback

    # 2. configuration
    install -o root -g wheel -m 0644 deploy/debug-feedback.yml /usr/local/etc/debug-debug-feedback.yml

    # 3. service
    install -o root -g wheel -m 0755 deploy/debug-feedback.rc /usr/local/etc/rc.d/debug_feedback
    sysrc debug_feedback_enable=YES
    service debug_feedback start

    # 4. apache macros, parked until you rename them
    install -o root -g wheel -m 0644 deploy/macro-debug-feedback.conf \
        /usr/local/etc/apache24/Includes/macro-debug-feedback.conf.proposed

    # 5. add ONE line inside the pilot vhost, then check and reload
    #    (in /web/sites/<name>/conf/apache.conf):
    #        Use DebugFeedbackEndpoint
    mv /usr/local/etc/apache24/Includes/macro-debug-feedback.conf.proposed \
       /usr/local/etc/apache24/Includes/macro-debug-feedback.conf
    httpd -t && /usr/local/etc/rc.d/apache24 reload

Step 5 is deliberately last: the macro file must be loaded before a
vhost may `Use` it, and `httpd -t` will tell you if it is not.

## Why the socket is reachable by Apache

The service runs as `debugfeedback`, Apache as `www`, and the socket is 0660
— so the group has to be right or the proxy gets EACCES. It is right
because of a BSD detail rather than anything Puma does: a new file takes
the **group of its directory**, not of the creating process. The rc
script makes `/var/run/debug-feedback` `debugfeedback:www` mode 0750, so the socket
created inside it comes out group `www`, and `umask=0117` in the bind
URL makes it 0660. Apache connects; nothing else can even see the
directory.

Verified on this host: a file created in a `www`-group directory comes
out gid 80.

## The bookmarklet

One line, kept as a file so it can be edited rather than retyped:
`deploy/bookmarklet.js`. It injects the client from whichever host is
serving `/common/js/debug-feedback.js`; the widget then defaults its endpoint
to `/.debug-feedback/report/` **relative to the page**, which is what keeps
the POST same-origin and inside that vhost's auth.

## Checking it works

    curl --unix-socket /var/run/debug-feedback/debug-feedback.sock http://localhost/report/health
    curl -u <you> https://<vhost>/.debug-feedback/report/health
    curl -u <you> https://<vhost>/.debug-feedback/review/

The first proves the service; the second proves the proxy and the auth;
the third is the listing.
