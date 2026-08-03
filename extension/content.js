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
    const FROM_PAGE = "corrigenda";
    const FROM_EXT  = "corrigenda-extension";
    const CAPTURE   = "corrigenda/capture";
    const LEARN     = "corrigenda/learn";

    document.documentElement.dataset[MARK] = VERSION;

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
        window.postMessage({ source: FROM_EXT, id, ...payload }, window.origin);
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
            reply(message.id, { type: "pong", version: VERSION });
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
            reply(message.id, { type: "failed",
                                error: String(error.message || error) });
        }
    });
})();
