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
const READY = "corrigenda/ready";

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

/* The toolbar button. It turns this site on: the click asks for the
 * origin, and a granted origin is where the bridge is registered, so
 * every later visit gets a mapped capture with nothing to press.
 *
 * It used to put the widget on the page as well -- the job a bookmarklet
 * would do, since a web page cannot install one. That is switched off
 * (see the listener below). The widget already arrives three other ways:
 * a site that serves it, a site that only advertises the endpoint plus
 * the bookmarklet, or the bookmarklet alone. Adding a fourth made this
 * add-on a second delivery mechanism to keep in step with the first, and
 * a page-injected <script src> is remotely hosted code by the letter of
 * both stores' policies. What is left is the one thing nothing else can
 * do: photograph the tab in page coordinates.
 *
 * Nothing here names a host. The manifest asks for `activeTab`, which
 * the browser grants for the tab whose button you pressed and for as
 * long as that visit lasts; a site added to the estate tomorrow
 * therefore needs no new build and no reinstall, which is the whole
 * point -- baking the hosts in made every change of host a redeployment.
 */
const REMEMBERED = "endpoint";
const SCRIPT_ID = "corrigenda-bridge";

const remember = async (base) => {
    if (!base) return;

    const known = await api.storage.local.get(REMEMBERED);
    if (known[REMEMBERED] === base) return;

    await api.storage.local.set({ [REMEMBERED]: base });
};

/* Firefox's tabs.captureTab and Chrome's captureVisibleTab both want
 * <all_urls> or activeTab -- a permission for the one site being
 * photographed is not accepted, which is documented and was the whole
 * fault: activeTab is granted by the click and gone at the next
 * navigation, so a capture worked until the page was reloaded and then
 * said "Missing activeTab permission" for ever after.
 *
 * So the permission asked for is <all_urls>. What it is not is a
 * licence to be everywhere: the sites this add-on acts on are the ones
 * somebody switched on, kept here, and nothing runs anywhere else.
 * The permission is what the browser demands; the list is what the
 * add-on does with it.
 */
const ALL_URLS = "<all_urls>";
const ENABLED = "sites";

const mayCapture = () => api.permissions.contains({ origins: [ALL_URLS] });

const enabledSites = async () =>
    (await api.storage.local.get(ENABLED))[ENABLED] || [];

const enable = async (origin) => {
    const sites = await enabledSites();
    if (sites.includes(origin)) return sites;

    const next = [...sites, origin];
    await api.storage.local.set({ [ENABLED]: next });
    return next;
};

/* Every origin switched on, and nothing else -- so revoking <all_urls>
 * from the add-ons page turns the bridge off everywhere, and the list
 * survives to mean something again if it is granted back. */
const granted = async () =>
    (await mayCapture()) ? await enabledSites() : [];

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

/* And once whenever this half is loaded at all, which the events above
 * do not cover: enabling a disabled add-on, or reloading it from
 * about:debugging, starts a fresh background with the old registration
 * still standing -- pointing at a script from an extension that no
 * longer exists. Every page loaded after that got a bridge whose
 * runtime was already gone, and the only cure anybody found was to
 * disable and re-enable, which is this line by hand.
 */
registerBridge();

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

/* The bridge, into the page that is already open. registerBridge() puts
 * it on every later load of a granted origin, but the tab somebody just
 * pressed the button in has no content script in it yet -- and telling
 * them to reload the page they are reporting on is telling them to lose
 * the state they were reporting about. */
const arm = async (tab) => {
    if (tab?.id === undefined) return;

    try {
        await api.scripting.executeScript({
            target: { tabId: tab.id },
            files: ["content.js"]
        });
    } catch {
        /* A page no extension may script, or one that navigated away
         * while the prompt was open. The next load gets it from the
         * registration either way. */
    }
};

/* DISABLED. Kept whole rather than deleted: turning it back on is one
 * call in the listener below, and the reasoning it encodes -- the
 * endpoint is the page's own link, then the last one this add-on
 * saw, then the page's origin -- is not something to rewrite from
 * memory. While it is off, the add-on puts no code on any page.
 */
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
 * Asking is now all it does. With the origin granted the bridge runs at
 * document_start, and a page that carries the widget -- because the site
 * serves it, or because you loaded the bookmarklet -- gets a mapped
 * capture with nothing to press. Injecting the widget was the other half
 * and is switched off: inject(tab) here brings it back.
 *
 */

/* The button is the only place a permission can be asked from -- a
 * browser will not raise that prompt without a user gesture, and an
 * add-on with no popup and no options page has exactly one gesture
 * to offer. So it stays, and now says what it did: pressing it on a
 * site that is already on would otherwise look like nothing
 * happening, which is how a working thing gets reported as broken.
 */
const announce = async (tabId, on) => {
    if (tabId === undefined) return;

    try {
        await api.action.setTitle({
            tabId,
            title: on ? "Corrigenda: capture help is on for this site"
                      : "Corrigenda: press to allow capture help here"
        });
        await api.action.setBadgeText({ tabId, text: on ? "on" : "" });
    } catch {
        /* The tab closed while we were asking. */
    }
};

api.action.onClicked.addListener((tab) => {
    const origin = originOf(tab?.url || "");
    if (!origin) return;

    /* Asked every time, and synchronously: a browser will only raise
     * this prompt inside the gesture that asked for it, so anything
     * awaited first loses the right to ask. Where the origin is already
     * granted there is no prompt -- request() answers true and nothing
     * is shown -- so the cost of asking again is nothing, and the
     * benefit is that a press after a dismissed prompt asks again.
     * Remembering the dismissal made the button dead for the rest of
     * the session on the one site somebody was trying to switch on.
     */
    api.permissions.request({ origins: [ALL_URLS] })
       .then(async (on) => {
           if (!on) return announce(tab?.id, false);

           /* Granted once, for the browser; switched on per site, by
            * this. The prompt says all sites because the capture API
            * accepts nothing narrower -- what happens on a site nobody
            * turned on is still nothing at all. */
           await enable(origin);
           await registerBridge();
           await arm(tab);
           announce(tab?.id, true);
       })
       .catch(() => { /* a prompt the browser would not raise */ });

    /* Switched off with the injector above. Restoring it is this line:
     *
     *     inject(tab).catch(() => {});
     *
     * A page no extension may script -- about:, the add-ons page,
     * another extension's page -- rejects, and there is nothing to do
     * about that and nothing to say. */
    void inject;
});

api.runtime.onMessage.addListener((message, sender, sendResponse) => {
    /* A page of the estate saying where its reports go. Nothing to
     * answer: the content script is telling, not asking. */
    if (message?.type === LEARN) {
        remember(String(message.endpoint || "").replace(/\/+$/, ""));
        return false;
    }

    /* Can this half take a picture of that page? Asked before anything
     * is offered, and answered from the permission rather than from the
     * fact that somebody is asking: a content script registered in an
     * earlier session outlives the grant that registered it, and a page
     * told "yes" on the strength of that finds out at capture time. */
    if (message?.type === READY) {
        const origin = String(message.origin || "");

        if (!/^https?:\/\//.test(origin)) {
            sendResponse({ granted: false });
            return false;
        }

        Promise.all([mayCapture(), enabledSites()])
           .then(([held, sites]) => held && sites.includes(`${origin}/*`))
           .then((granted) => {
               /* The same answer serves two purposes: the page is told
                * whether a mapped capture is available, and the button
                * gets its badge back. A badge is per tab and the
                * browser clears it on every navigation, so without this
                * a granted site reads as off after a refresh -- which
                * is how somebody presses the button again on a site
                * that was never off. */
               announce(sender.tab?.id, granted === true);
               sendResponse({ granted: granted === true });
           },
                 () => sendResponse({ granted: false }));

        return true;
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
