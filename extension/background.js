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
 * Pages that already carry the widget (MoXoW injects it for some
 * clients) are left alone: the client refuses to mount twice, but
 * fetching the file again for nothing is still a fetch. */
/* The page says where its reports go:
 *
 *   <link rel="corrigenda" href="https://tools.sdalu.com/.corrigenda">
 *
 * which MoXoW emits for any site the widget is configured for, whether
 * or not that client got the widget itself. So this add-on carries no
 * endpoint of its own: it is installed once and follows whatever the
 * estate is doing, including a site that moves its endpoint or mounts
 * its own. Nothing to rebuild, nothing to reinstall, nothing to drift.
 *
 * A page that advertises nothing falls back to its own origin, which is
 * what the widget assumed before any of this and is right for a site
 * that mounts the service. If it does not, the report says so plainly
 * rather than failing silently. */
const inject = async (tab) => {
    if (tab?.id === undefined) return;

    await api.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => {
            if (window.__corrigendaLoaded) return;

            const advertised = document.querySelector(
                'link[rel="corrigenda"]')?.href;
            const base = (advertised || "/.corrigenda")
                .replace(/\/+$/, "");

            /* The client reads its configuration off its own tag
             * (document.currentScript), so the endpoint has to be on it
             * before it runs, not appended afterwards. */
            const script = document.createElement("script");
            script.src = `${base}/corrigenda.js`;
            script.dataset.endpoint = `${base}/report/`;
            document.documentElement.append(script);
        }
    });
};

api.action.onClicked.addListener((tab) => { inject(tab); });

api.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message?.type !== CAPTURE) return false;

    capture(message, sender).then(
        (result) => sendResponse({ ok: true, ...result }),
        (error) => sendResponse({ ok: false, error: String(error.message || error) })
    );

    /* true keeps the message channel open for the async reply — the one
     * form both browsers agree on. */
    return true;
});
