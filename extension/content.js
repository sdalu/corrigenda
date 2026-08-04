/*
 * The bridge. The widget is an ordinary page script and cannot see the
 * extension; the extension can see the page but has no interface. This
 * runs in the isolated content-script world of every matching page and
 * carries two message types between them.
 *
 * It announces itself on the documentElement at document_start, so the
 * widget knows synchronously — before it draws a screenshot control it
 * may not be able to honour — that a mappable capture is available.
 */
(() => {
    "use strict";

    const api = globalThis.browser ?? globalThis.chrome;

    const MARK      = "corrigendaCapture";   /* data-corrigenda-capture */
    const VERSION   = api.runtime.getManifest().version;

    /* What is on the documentElement is not the build, it is the
     * contract: the shape of the two messages below and of the
     * replies to them. The widget requires a number and this side
     * provides one, so a browser carrying an add-on older than the
     * page it is on falls back to the share dialog instead of
     * talking past it. Raise it when an exchange changes shape --
     * never for a fix, a permission, or a release.
     *
     * 1  ping/pong, and capture{rect,viewport,scale} answered with
     *    captured{dataUrl,rect,scale} or failed{error}.
     * 2  pong also carries `granted`: whether the half that takes the
     *    picture holds a permission for this site. A helper that
     *    cannot say is one whose "yes" means only that a content
     *    script is running, which is not the question.
     */
    const HELPER    = 2;
    const FROM_PAGE = "corrigenda";
    const FROM_EXT  = "corrigenda-extension";
    const CAPTURE   = "corrigenda/capture";
    const LEARN     = "corrigenda/learn";
    const READY     = "corrigenda/ready";

    document.documentElement.dataset[MARK] = String(HELPER);

    /* A sandboxed iframe or a data: document has origin "null", which
     * postMessage refuses as a target -- and a bridge that cannot
     * address its own window has nothing to say to it. */
    const addressable = window.origin !== "null";

    /* Learned by walking past, not by being asked. A page of the estate
     * says where its reports go; telling the background half means the
     * toolbar button works later on a page that says nothing -- an app
     * behind the same login, a static page, anything never prepared for
     * this. Sent once per page and ignored if it fails: the button
     * still asks the page directly when it is pressed. */
    const learn = () => {
        const advertised = document.querySelector('link[rel="corrigenda"]')?.href;
        if (!advertised) return;

        api.runtime.sendMessage({ type: LEARN, endpoint: advertised })
           .catch(() => {});
    };

    /* Said once on every load, and the answer is not for us: a badge on
     * the toolbar button is per tab and the browser clears it at every
     * navigation, so a site that is granted looks unarmed after a
     * refresh unless something puts it back. This script only runs
     * where the add-on is granted, so its arrival is the fact worth
     * announcing. It also wakes the background half before the widget
     * asks it anything. */
    api.runtime.sendMessage({ type: READY, origin: window.origin })
       .catch(() => {});

    /* And to the page. On a normal load nothing is listening yet and
     * this is ignored; injected into a tab that is already open --
     * which is what pressing the toolbar button does -- it is the only
     * thing that tells a widget already on the page that cropping just
     * became possible. Without it the reader presses the button, is
     * told to press the button, and reloads to find out it worked. */
    if (addressable) {
        window.postMessage({ source: FROM_EXT, type: "hello", helper: HELPER },
                           window.origin);
    }

    /* This runs at document_start, where <head> has not been parsed and
     * the link cannot be there yet. The announcement above must stay
     * that early -- the widget reads it synchronously -- but the reading
     * of the page waits for a page to read. */
    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", learn, { once: true });
    } else {
        learn();
    }

    const reply = (id, payload) => {
        if (!addressable) return;

        window.postMessage({ source: FROM_EXT, id, ...payload }, window.origin);
    };

    /* An update, a disable, a reload from about:debugging: the extension
     * is replaced and every content script it had already injected keeps
     * running, attached to a runtime that is gone. Such a script still
     * answers the page -- it is ordinary JavaScript in the page's world
     * -- but everything it forwards fails, which is a bridge that says
     * yes and then cannot deliver.
     *
     * The marker is what the widget trusts, so an orphan takes its own
     * marker down. The page then reads exactly as it does with no
     * add-on, which it now effectively has, and the next load gets a
     * live one from the registration.
     */
    const orphaned = () => {
        try {
            if (api.runtime?.id) return false;
        } catch {
            /* Touching runtime at all can throw once it is gone. */
        }

        delete document.documentElement.dataset[MARK];
        return true;
    };

    /* true, false, or null for "could not ask". The three are different:
     * a refusal is the browser's answer about this site, and null is
     * this half failing to reach the other one. */
    const mayCapture = async () => {
        if (orphaned()) return false;

        try {
            const answer = await api.runtime.sendMessage({
                type: READY, origin: window.origin
            });

            return answer?.granted === true;
        } catch {
            return orphaned() ? false : null;
        }
    };

    /* Where the viewport sits in the page. Only this side can read it,
     * and Chrome's captureVisibleTab needs it to say what it returned. */
    const viewport = () => ({
        x: window.scrollX, y: window.scrollY,
        width: window.innerWidth, height: window.innerHeight
    });

    window.addEventListener("message", async (event) => {
        /* Only this window, only this origin, only our own shape: a
         * message from an iframe or another origin is not the widget. */
        if (event.source !== window) return;
        if (event.origin !== window.origin) return;

        const message = event.data;
        if (!message || message.source !== FROM_PAGE) return;

        if (message.type === "ping") {
            /* Asked of the background half rather than answered here.
             * This script running proves only that it was registered
             * once: a registration outlives the permission that put it
             * there, so on a site whose grant was revoked -- or never
             * given, with the script left over from a previous session
             * -- the page would be told a capture is available and find
             * out otherwise at the moment somebody pressed the button.
             *
             * The half that holds the permission is the half that can
             * say. It is also the half that can be asleep or revoked,
             * and a failure to reach it is the same answer: no.
             *
             * The build travels here rather than on the element:
             * nothing branches on it, and a report that says which
             * helper took its picture is worth having. */
            let granted = await mayCapture();

            /* Once more if it could not be reached at all. The
             * background half sleeps between uses -- an event page in
             * Firefox, a service worker in Chrome -- and sending to it
             * is what wakes it; a message that arrives mid-wake can be
             * lost, and answering "no" to that would take the cropping
             * away from a site that is perfectly well granted. Silence
             * twice is an answer; silence once is a nap. */
            if (granted === null) {
                await new Promise((wait) => setTimeout(wait, 200));
                granted = await mayCapture();
            }

            reply(message.id, { type: "pong", helper: HELPER,
                                version: VERSION,
                                granted: granted === true });
            return;
        }

        if (message.type !== "capture") return;

        try {
            const result = await api.runtime.sendMessage({
                type: CAPTURE,
                rect: message.rect,
                viewport: viewport(),
                scale: message.scale
            });

            reply(message.id, result?.ok
                ? { type: "captured", dataUrl: result.dataUrl,
                    rect: result.rect, scale: result.scale }
                : { type: "failed", error: result?.error || "capture refused" });
        } catch (error) {
            /* The background half can be asleep, revoked, or updating.
             * The widget falls back to getDisplayMedia on any failure,
             * so the honest thing here is to say so and stop. */
            const dead = orphaned();

            reply(message.id, {
                type: "failed",
                error: dead ? "the add-on was reloaded under this page"
                            : String(error.message || error)
            });
        }
    });
})();
