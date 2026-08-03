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
 * Nothing here names a host. The manifest asks for `activeTab`, which
 * the browser grants for the tab whose button you pressed and for as
 * long as that visit lasts -- enough to inject the widget and to
 * photograph the tab, and it goes stale by itself. A site added to the
 * estate tomorrow therefore needs no new build and no reinstall, which
 * is the whole point: baking the hosts in made every change of host a
 * redeployment.
 *
 * What a click cannot buy is the bridge running on a page you have NOT
 * clicked: a page that carries the widget already (MoXoW injects it)
 * wants a mapped capture without a toolbar visit. That is what the
 * optional permission is for. It is asked for at the click, because a
 * click is the user gesture browsers require, and once granted the
 * content script is registered for that origin and runs at
 * document_start on every later visit.
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
 */
const REMEMBERED = "endpoint";
const SCRIPT_ID = "corrigenda-bridge";

const remember = async (base) => {
    if (!base) return;

    const known = await api.storage.local.get(REMEMBERED);
    if (known[REMEMBERED] === base) return;

    await api.storage.local.set({ [REMEMBERED]: base });
};

/* Every origin the user has granted, as a match pattern. Read from the
 * browser rather than kept in storage: the browser is where a
 * permission actually lives, and it can be revoked from the add-ons
 * page without telling us. */
const granted = async () => {
    const { origins } = await api.permissions.getAll();
    return origins || [];
};

/* One registration covering everything granted, replaced whenever that
 * set changes. Registered scripts survive restarts, so this is
 * idempotent by design: unregister, then register what is true now. */
const registerBridge = async () => {
    const origins = await granted();

    try {
        await api.scripting.unregisterContentScripts({ ids: [SCRIPT_ID] });
    } catch {
        /* not registered yet, which is the normal first case */
    }

    if (!origins.length) return;

    await api.scripting.registerContentScripts([{
        id: SCRIPT_ID,
        js: ["content.js"],
        matches: origins,
        runAt: "document_start",
        persistAcrossSessions: true
    }]);
};

api.runtime.onInstalled.addListener(() => { registerBridge(); });
api.runtime.onStartup.addListener(() => { registerBridge(); });
api.permissions.onAdded?.addListener(() => { registerBridge(); });
api.permissions.onRemoved?.addListener(() => { registerBridge(); });

/* The origin of a page, as a pattern the permission API accepts. */
const originOf = (url) => {
    try {
        const { protocol, host } = new URL(url);
        return /^https?:$/.test(protocol) ? `${protocol}//${host}/*` : null;
    } catch {
        return null;
    }
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

/* Ask first, and ask synchronously: a handler that has awaited anything
 * is no longer a user input handler. Firefox says so outright ("if a
 * user input handler waits on a promise, then its status as a user
 * input handler is lost") and Chrome throws "This function must be
 * called during a user gesture" -- so permissions.request has to be the
 * first thing this listener does, before the injection and before any
 * check of what is already granted. That rules out asking
 * permissions.contains beforehand, and nothing is lost by it: an origin
 * already held is granted silently, with no prompt.
 *
 * The injection needs nothing but activeTab, which the click itself
 * grants, so the widget appears whatever the answer is. The question is
 * only about later visits: with the origin granted, the bridge runs at
 * document_start and a page that already carries the widget gets a
 * mapped capture without anyone pressing anything.
 *
 * `asked` keeps a refusal from being re-asked at every click. It is
 * memory, not storage, because storage would have to be awaited: it
 * lasts as long as this background context does, and a refuser is asked
 * again at most once per browser session.
 */
const asked = new Set();

api.action.onClicked.addListener((tab) => {
    const origin = originOf(tab?.url || "");

    if (origin && !asked.has(origin)) {
        asked.add(origin);
        /* Not awaited, for the same reason it is called first. */
        api.permissions.request({ origins: [origin] })?.catch?.(() => {
            /* Refused, or asked where the browser will not ask. The
             * button still works; only the automatic bridge is lost. */
        });
    }

    inject(tab).catch(() => {
        /* A page no extension may script -- about:, the add-ons page,
         * another extension's page. Nothing to do and nothing to say. */
    });
});

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
