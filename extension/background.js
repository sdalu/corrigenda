/*
 * The privileged half. It does exactly one thing: photograph the tab a
 * request came from, and say what it actually photographed.
 *
 * Firefox has tabs.captureTab, whose `rect` is in CSS pixels relative to
 * the PAGE and may lie outside the visible viewport (Firefox 82+). That
 * is the whole reason this extension exists: from a page, getDisplayMedia
 * in Firefox offers only a window or a screen, neither of which can be
 * mapped to page coordinates, so the widget can neither crop to an
 * element nor mask form fields.
 *
 * Chrome has only tabs.captureVisibleTab: the viewport, at the device
 * pixel ratio, and nothing else. That still removes the share dialog and
 * still gives a frame in page coordinates, which is most of the value —
 * so the request is honoured as far as it can be and the reply carries
 * the rectangle that came back. The caller crops from THAT, never from
 * what it asked for, and the two browsers need no branch on the far side.
 */
const api = globalThis.browser ?? globalThis.chrome;
const CAPTURE = "corrigenda/capture";
const LEARN = "corrigenda/learn";

const validRect = (rect) =>
    rect !== null &&
    typeof rect === "object" &&
    ["x", "y", "width", "height"].every((key) => Number.isFinite(rect[key])) &&
    rect.width >= 1 && rect.height >= 1;

/* A scale the page chose, bounded: it decides how many device pixels
 * come back, and an unbounded one is a way to ask the browser for a
 * gigapixel image. */
const boundedScale = (value) =>
    Math.min(Math.max(Number(value) || 1, 0.25), 4);

/* Firefox: exactly the rectangle asked for, at the scale asked for. */
const captureRect = async (tabId, rect, scale) => ({
    dataUrl: await api.tabs.captureTab(tabId, { format: "png", rect, scale }),
    rect,
    scale
});

/* Chrome: the visible viewport, at whatever ratio the display has. The
 * viewport's page coordinates come from the content script, which is the
 * only side that can read scrollX/scrollY. */
const captureViewport = async (windowId, viewport, scale) => ({
    dataUrl: await api.tabs.captureVisibleTab(windowId, { format: "png" }),
    rect: viewport,
    scale
});

const capture = async (message, sender) => {
    const tab = sender.tab;
    if (!tab || tab.id === undefined) throw new Error("no tab to capture");
    if (!validRect(message.rect)) throw new Error("bad rect");
    if (!validRect(message.viewport)) throw new Error("bad viewport");

    const scale = boundedScale(message.scale);

    /* Feature, not user agent: a Chromium that grows captureTab tomorrow
     * takes the better path the day it ships. */
    return api.tabs.captureTab
        ? captureRect(tab.id, message.rect, scale)
        : captureViewport(tab.windowId, message.viewport, scale);
};

/* The toolbar button, which is what a bookmarklet would have been. A web
 * page cannot install a bookmarklet -- browsers refuse programmatic
 * bookmark creation and strip javascript: URLs -- so the extension does
 * the job the bookmarklet was standing in for: put the widget on the
 * page in front of you.
 *
 * Where the reports go is a question with three answers, tried in this
 * order:
 *
 *   1. <link rel="corrigenda"> on the page. MoXoW emits it for any site
 *      the widget is configured for, whether or not that client got the
 *      widget itself.
 *   2. The last one this add-on saw. Visiting one prepared page teaches
 *      it the estate's endpoint, and from then on the button works on
 *      pages that say nothing -- an app behind the same login, a static
 *      page, anything never prepared for this.
 *   3. The page's own origin, which is right for a site that mounts the
 *      service and is what the widget assumed before any of this.
 *
 * So the add-on still carries no endpoint of its own: not one written
 * at build time, not one you are asked to type. It follows the estate,
 * and remembers.
 */
const REMEMBERED = "endpoint";

const remember = async (base) => {
    if (!base) return;

    const known = await api.storage.local.get(REMEMBERED);
    if (known[REMEMBERED] === base) return;

    await api.storage.local.set({ [REMEMBERED]: base });
};

const recalled = async () =>
    (await api.storage.local.get(REMEMBERED))[REMEMBERED] || null;

const inject = async (tab) => {
    if (tab?.id === undefined) return;

    const [result] = await api.scripting.executeScript({
        target: { tabId: tab.id },
        args: [await recalled()],
        func: (known) => {
            if (window.__corrigendaLoaded) return null;

            const advertised = document.querySelector(
                'link[rel="corrigenda"]')?.href || null;
            const base = (advertised || known || "/.corrigenda")
                .replace(/\/+$/, "");

            /* The client reads its configuration off its own tag
             * (document.currentScript), so the endpoint has to be on it
             * before it runs, not appended afterwards. */
            const script = document.createElement("script");
            script.src = `${base}/corrigenda.js`;
            script.dataset.endpoint = `${base}/report/`;
            document.documentElement.append(script);

            return advertised;
        }
    });

    await remember(result?.result?.replace(/\/+$/, ""));
};

api.action.onClicked.addListener((tab) => { inject(tab); });

api.runtime.onMessage.addListener((message, sender, sendResponse) => {
    /* A page of the estate saying where its reports go. Nothing to
     * answer: the content script is telling, not asking. */
    if (message?.type === LEARN) {
        remember(String(message.endpoint || "").replace(/\/+$/, ""));
        return false;
    }

    if (message?.type !== CAPTURE) return false;

    capture(message, sender).then(
        (result) => sendResponse({ ok: true, ...result }),
        (error) => sendResponse({ ok: false, error: String(error.message || error) })
    );

    /* true keeps the message channel open for the async reply — the one
     * form both browsers agree on. */
    return true;
});
