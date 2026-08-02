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

    const MARK      = "debugFeedbackCapture";   /* data-debug-feedback-capture */
    const VERSION   = api.runtime.getManifest().version;
    const FROM_PAGE = "debug-feedback";
    const FROM_EXT  = "debug-feedback-extension";
    const CAPTURE   = "debug-feedback/capture";

    document.documentElement.dataset[MARK] = VERSION;

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
