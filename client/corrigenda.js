/*
 * corrigenda.js — page-defect reporting widget.
 * Design and endpoint: DESIGN.md, beside this file's repository
 *
 * One file, no dependencies. Everything it renders lives in a shadow
 * root so the page under investigation cannot style the widget and the
 * widget cannot perturb the page: nothing it injects participates in
 * flow, and the picker overlay never takes pointer events.
 */
(() => {
    "use strict";

    if (window.__corrigendaLoaded) return;
    window.__corrigendaLoaded = true;

    /* Served by the endpoint it reports to, so the two are the same
     * checkout: Corrigenda::VERSION in lib/corrigenda.rb is this
     * number, and a test refuses to let them drift. It goes on the
     * host element as well, where a live page can be asked which
     * widget it is actually running. */
    const VERSION = "0.2.0";

    const SCRIPT = document.currentScript;

    const CFG = (() => {
        const d = (SCRIPT && SCRIPT.dataset) || {};
        const meta = (name) =>
            document.querySelector(`meta[name="${name}"]`)?.content || null;

        /* A tag is written by hand, so a limit on it arrives as
         * whatever somebody typed -- and Number("deep") is NaN, which
         * fails every comparison it is put in. `depth >= NaN` is false
         * at every depth, so data-prune="deep" pruned nothing and the
         * fragment went out whole; `html.length > NaN` is false at
         * every length, so data-cap="64k" sent a megabyte. A number
         * that is not one is not a limit, and takes the default. */
        const number = (value, fallback) => {
            const n = Number(value || fallback);
            return Number.isFinite(n) ? n : fallback;
        };

        /* Where this page says its reports go. The tag that loaded this
         * file knows when MoXoW put it there, but a bookmarklet loaded
         * it on a page that never asked for it -- and on a site that
         * does not mount the service, its own origin is a 404. The link
         * is the page's own answer, and it is there whether or not the
         * widget was injected. */
        const advertised = document.querySelector(
            'link[rel="corrigenda"]')?.href;

        return {
            endpoint: d.endpoint ||
                      (advertised && `${advertised.replace(/\/+$/, "")}/report/`) ||
                      "/.corrigenda/report/",
            site:     d.site || location.hostname,
            build:    d.build || meta("build"),
            /* The reporter's language, not the page's. A French gallery
             * read by an English-speaking reviewer used to hand them a
             * French widget, and an English page shown to a French
             * reporter an English one -- exactly backwards, since the
             * page's lang describes the content being reported and the
             * browser's describes the person reporting it. The tag can
             * still say, for a deployment where that is wrong. */
            lang:     (d.lang || navigator.language || "en").slice(0, 2),
            prune:    number(d.prune, 3),
            cap:      number(d.cap, 64 * 1024)
        };
    })();

    /* Where a report actually goes, resolved once. Three readers want
     * it: the POST, the sentence that explains a refused one, and the
     * line under the title -- and that last one is the reason it is
     * resolved this early. The page chooses its own endpoint, so the
     * destination is not a fact about this widget but a fact about the
     * page, and somebody about to press Send is entitled to read it. */
    const ENDPOINT = new URL(CFG.endpoint, location.href);
    const CROSS_ORIGIN = ENDPOINT.origin !== location.origin;

    /* Whether a report from this page can be filed at all. The schema
     * requires page.url to be http or https -- the review UI renders it
     * as a link somebody clicks, so a javascript: or a data: address
     * filed as a report must never become one -- and a bookmarklet goes
     * wherever it is pressed, file:// documents and view-source
     * included. Asked here, the answer is a sentence in the panel
     * before anything is typed; left to the endpoint it is a 422 about
     * a field name, after the message. */
    const REPORTABLE = location.protocol === "http:" ||
                       location.protocol === "https:";

    /* ---------------------------------------------------------------
     * Diagnostics. Installed at load, before anything else, because the
     * errors worth reporting are the ones that already happened.
     * ------------------------------------------------------------- */
    const DIAG = { errors: [], resources: [] };
    const KEEP = 20;

    const remember = (list, item) => {
        if (list.length < KEEP) list.push(item);
    };

    addEventListener("error", (event) => {
        const el = event.target;
        if (el && el !== window && el.tagName) {
            remember(DIAG.resources, {
                tag: el.tagName.toLowerCase(),
                url: el.currentSrc || el.src || el.href || null
            });
        } else {
            remember(DIAG.errors, {
                message: event.message,
                source: event.filename,
                line: event.lineno
            });
        }
    }, true);

    addEventListener("unhandledrejection", (event) => {
        remember(DIAG.errors, { message: String(event.reason) });
    });

    /* ---------------------------------------------------------------
     * Text
     * ------------------------------------------------------------- */
    const STRINGS = {
        en: {
            open: "Debug", close: "Close", cancel: "Cancel", send: "Send",
            title: "Report a page defect", sending: "Sending…",
            visual: "Visual",   visualHint: "how it looks",
            content: "Content", contentHint: "the words are wrong",
            broken: "Broken",   brokenHint: "it does not work",
            idea: "Idea",       ideaHint: "suggestion or question",
            helpSelectWords: "select the words", helpConfirmWords: "use it",
            helpPickInstead: "pick the element instead",
            helpPick: "pick", helpParent: "parent", helpChild: "child",
            helpSiblings: "siblings", helpConfirm: "confirm",
            helpCancel: "cancel",
            regionCovers: "covering", across: "across",
            elements: "elements",
            message: "What is wrong?",
            include: "What gets sent",
            thanks: "Sent. Reference:",
            failed: "Could not send:",
            notReportable: "Reports cannot be filed from this page: it is " +
                           "not served over http or https.",
            fragment: "Element", rules: "CSS rules",
            computed: "Computed styles", diagnostics: "Diagnostics",
            audit: "Accessibility",
            previewShort: "what will be sent",
            surfaceTab: "this tab", surfaceWindow: "a window",
            surfaceScreen: "the whole screen", surfaceUnknown: "unknown surface",
            needShot: "Capture the screenshot, or switch it off.",
            noTabCapture: "No cropping to the element, no masking of form " +
                          "fields: this browser shares a window or a screen, " +
                          "never one tab. The add-on fixes that — press its " +
                          "toolbar button here to allow it, or install it " +
                          "from the Corrigenda page.",
            helperNotHere: "No cropping or masking: the add-on is not " +
                           "allowed on this site. Press its toolbar button " +
                           "here, once.",
            helperOutdated: "No cropping or masking: the add-on here is " +
                            "older than this page needs. Install the current " +
                            "build from the Corrigenda page.",
            helperFailed: "the add-on could not:",
            helperNone: "no add-on",
            helperSilent: "add-on silent",
            screenshot: "Screenshot",
            aboutFragment: "the picked element, sanitised",
            aboutRules: "the rules that matched it, with layer and media",
            aboutComputed: "a subset of its computed styles",
            aboutDiagnostics: "errors, failed loads, sideways overflow",
            aboutAudit: "contrast, target size, missing alt",
            aboutScreenshot: "an image you capture and crop",
            capture: "Capture…", recapture: "Capture again", drop: "Remove",
            scopeElement: "The picked element",
            scopeViewport: "The visible page",
            scopeFull: "No crop — all you shared",
            scopeNote: "Only what is on screen; scrolled-off content is never captured.",
            shotDenied: "Screen capture was refused or cancelled.",
            shotBig: "Too large to send even at low quality.",
            shotUnmapped: "Shared window or screen: cannot crop, so the " +
                          "whole picture will be sent as-is.",
            shotViewportOnly: "visible page only: this browser cannot " +
                              "photograph past the edge of the window",
            shotReady: "captured",
            maskNone: "nothing to mask", maskOne: "mask", maskMany: "masks"
        },
        fr: {
            open: "Débogage", close: "Fermer", cancel: "Annuler", send: "Envoyer",
            title: "Signaler un défaut", sending: "Envoi…",
            visual: "Visuel",   visualHint: "l'apparence",
            content: "Contenu", contentHint: "le texte est incorrect",
            broken: "Panne",    brokenHint: "ça ne fonctionne pas",
            idea: "Idée",       ideaHint: "suggestion ou question",
            helpSelectWords: "sélectionnez le texte", helpConfirmWords: "valider",
            helpPickInstead: "choisir l'élément à la place",
            helpPick: "choisir", helpParent: "parent", helpChild: "enfant",
            helpSiblings: "frères", helpConfirm: "valider",
            helpCancel: "annuler",
            regionCovers: "couvrant", across: "réparti sur",
            elements: "éléments",
            message: "Que se passe-t-il ?",
            include: "Ce qui sera envoyé",
            thanks: "Envoyé. Référence :",
            failed: "Envoi impossible :",
            notReportable: "Impossible de signaler depuis cette page : elle " +
                           "n'est pas servie en http ou https.",
            previewShort: "ce qui sera envoyé",
            fragment: "Élément", rules: "Règles CSS",
            computed: "Styles calculés", diagnostics: "Diagnostics",
            audit: "Accessibilité",
            surfaceTab: "cet onglet", surfaceWindow: "une fenêtre",
            surfaceScreen: "tout l'écran", surfaceUnknown: "surface inconnue",
            needShot: "Capturez l'écran, ou désactivez-le.",
            noTabCapture: "Ni recadrage ni masquage : ce navigateur partage " +
                          "une fenêtre ou un écran, jamais un onglet. " +
                          "L'extension corrige cela — cliquez son bouton " +
                          "ici pour l'autoriser, ou installez-la depuis la " +
                          "page Corrigenda.",
            helperNotHere: "Ni recadrage ni masquage : l'extension n'est pas " +
                           "autorisée sur ce site. Cliquez son bouton, une " +
                           "fois.",
            helperOutdated: "Ni recadrage ni masquage : l'extension installée " +
                            "est plus ancienne que cette page ne l'exige. " +
                            "Installez la version courante depuis la page " +
                            "Corrigenda.",
            helperFailed: "l'extension n'a pas pu :",
            helperNone: "sans extension",
            helperSilent: "extension muette",
            screenshot: "Capture d'écran",
            aboutFragment: "l'élément choisi, nettoyé",
            aboutRules: "les règles qui s'y appliquent, layer et media compris",
            aboutComputed: "une partie de ses styles calculés",
            aboutDiagnostics: "erreurs, chargements échoués, débordement",
            aboutAudit: "contraste, taille de cible, alt manquant",
            aboutScreenshot: "une image que vous capturez et recadrez",
            capture: "Capturer…", recapture: "Recapturer", drop: "Retirer",
            scopeElement: "L'élément sélectionné",
            scopeViewport: "La page visible",
            scopeFull: "Sans recadrage — tout le partage",
            scopeNote: "Seulement ce qui est à l\x27écran ; hors écran n\x27est jamais capturé.",
            shotDenied: "Capture d'écran refusée ou annulée.",
            shotBig: "Trop volumineuse même en qualité réduite.",
            shotUnmapped: "Fenêtre ou écran partagé : pas de recadrage, " +
                          "l'image sera envoyée telle quelle.",
            shotViewportOnly: "page visible seulement : ce navigateur ne " +
                              "photographie pas au-delà de la fenêtre",
            shotReady: "capturée",
            maskNone: "rien à masquer", maskOne: "masque",
            maskMany: "masques"
        }
    };
    const T = STRINGS[CFG.lang] || STRINGS.en;

    /* ---------------------------------------------------------------
     * Locating an element again
     * ------------------------------------------------------------- */
    const uniqueId = (el) => {
        if (!el.id) return null;
        const selector = "#" + CSS.escape(el.id);
        return document.querySelectorAll(selector).length === 1 ? selector : null;
    };

    const step = (node) => {
        const tag = node.localName;
        const parent = node.parentElement;
        if (!parent) return tag;
        const same = [...parent.children].filter((c) => c.localName === tag);
        return same.length === 1
            ? tag
            : `${tag}:nth-of-type(${same.indexOf(node) + 1})`;
    };

    const selectorFor = (el) => {
        const parts = [];
        let node = el;
        while (node && node.nodeType === 1 && node !== document.documentElement) {
            const id = uniqueId(node);
            if (id) { parts.unshift(id); return parts.join(" > "); }
            parts.unshift(step(node));
            node = node.parentElement;
        }
        parts.unshift("html");
        return parts.join(" > ");
    };

    const xpathFor = (el) => {
        const parts = [];
        let node = el;
        while (node && node.nodeType === 1) {
            const siblings = node.parentElement
                ? [...node.parentElement.children]
                      .filter((c) => c.localName === node.localName)
                : [];
            const index = siblings.length > 1
                ? `[${siblings.indexOf(node) + 1}]` : "";
            parts.unshift(node.localName + index);
            node = node.parentElement;
        }
        return "/" + parts.join("/");
    };

    /* A selector can rot when the markup moves; this is what lets a
     * human (or a fuzzy match) find the thing again anyway.
     *
     * The words are the only part of it that is content rather than
     * structure, and they were the one part that asked nobody: eighty
     * characters of element text went out whatever the report said, so
     * a page that marks a block data-corrigenda-redact had it quoted
     * here after the sanitiser had carefully removed it from the
     * fragment, and a reporter who switched the element channel off
     * still sent its text. Marked, the words are named and not quoted;
     * with the element channel off there is no fingerprint text at all.
     *
     * closest(), not hasAttribute: the marker goes on the container --
     * the account panel, the invoice -- and the secret is the text of
     * something inside it. */
    const fingerprint = (el, withText) => {
        const print = {
            tag: el.localName,
            id: el.id || null,
            classes: [...el.classList],
            index: el.parentElement
                ? [...el.parentElement.children].indexOf(el) : 0
        };

        if (withText) {
            print.text = el.closest("[data-corrigenda-redact]")
                ? "[redacted]"
                : (el.textContent || "").trim().slice(0, 80);
        }

        return print;
    };

    /* ---------------------------------------------------------------
     * Which CSS actually applied. The highest-value field in the whole
     * report: it names the file and the selector to open.
     * ------------------------------------------------------------- */
    const RULE_CAP = 40;

    /* Enough of the address to open the file, and no more. The pathname
     * alone was not enough twice over: an estate whose pages pull the
     * same /css/site.css from two hosts named the same sheet for both,
     * and a build that cache-busts with ?v= lost the one part of the
     * URL that says WHICH build the reader is looking at. The host is
     * added only when it is not this page's own, where it would be
     * noise on every row. */
    const sheetName = (sheet) => {
        if (!sheet.href) return "(inline)";

        try {
            const url = new URL(sheet.href, location.href);
            return url.origin === location.origin
                ? url.pathname + url.search
                : url.host + url.pathname + url.search;
        } catch { return sheet.href; }
    };

    const collectRules = (rules, el, sheet, context, out) => {
        for (const rule of rules) {
            if (out.length >= RULE_CAP) return;

            if (rule instanceof CSSStyleRule) {
                let hit = false;
                /* Nested rules carry "&", which matches() cannot
                 * evaluate standalone — they are skipped, not crashed on. */
                try { hit = el.matches(rule.selectorText); } catch { hit = false; }
                if (hit) {
                    out.push({
                        href: sheetName(sheet),
                        selector: rule.selectorText,
                        context: context.length ? context.join(" / ") : null,
                        css: rule.cssText.slice(0, 400)
                    });
                }
                if (rule.cssRules) {
                    collectRules(rule.cssRules, el, sheet,
                                 context.concat(rule.selectorText), out);
                }
            } else if (rule.cssRules) {
                const label = rule.conditionText
                    ? `@${rule.constructor.name.replace(/^CSS|Rule$/g, "")
                          .toLowerCase()} ${rule.conditionText}`
                    : (rule.name ? `@layer ${rule.name}` : null);
                collectRules(rule.cssRules, el, sheet,
                             label ? context.concat(label) : context, out);
            }
        }
    };

    const matchedRules = (el) => {
        const out = [], unreadable = [];
        for (const sheet of document.styleSheets) {
            let rules;
            try { rules = sheet.cssRules; }
            catch { unreadable.push(sheetName(sheet)); continue; }
            collectRules(rules, el, sheet, [], out);
        }
        return { rules: out, unreadable };
    };

    /* ---------------------------------------------------------------
     * Geometry, computed style, environment
     * ------------------------------------------------------------- */
    const COMPUTED = [
        "display", "position", "inline-size", "block-size", "box-sizing",
        "margin-block", "margin-inline", "padding-block", "padding-inline",
        "border-block-start-width", "border-inline-start-width",
        "font-family", "font-size", "line-height", "text-wrap",
        "color", "background-color", "overflow-x", "overflow-y",
        "flex", "grid-template-columns", "gap", "aspect-ratio", "z-index"
    ];

    const computedStyles = (el) => {
        const style = getComputedStyle(el);
        return Object.fromEntries(
            COMPUTED.map((name) => [name, style.getPropertyValue(name)])
                    .filter(([, value]) => value !== "")
        );
    };

    const rectOf = (el) => {
        const r = el.getBoundingClientRect();
        return {
            x: Math.round(r.x), y: Math.round(r.y),
            width: Math.round(r.width), height: Math.round(r.height)
        };
    };

    const mq = (query) => matchMedia(query).matches;

    const environment = () => ({
        "user-agent": navigator.userAgent,
        viewport: `${innerWidth}x${innerHeight}`,
        "device-pixel-ratio": String(devicePixelRatio),
        "root-font-size": getComputedStyle(document.documentElement).fontSize,
        "color-scheme": mq("(prefers-color-scheme: dark)") ? "dark" : "light",
        "reduced-motion": String(mq("(prefers-reduced-motion: reduce)")),
        "forced-colors": String(mq("(forced-colors: active)")),
        contrast: mq("(prefers-contrast: more)") ? "more" : "no-preference",
        pointer: mq("(pointer: coarse)") ? "coarse" : "fine",
        language: navigator.language,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        scroll: `${Math.round(scrollX)},${Math.round(scrollY)}`
    });

    /* Free, and it turns "looks weird on my phone" into a named element.
     *
     * Measured on the page, not on the screenful of it that happens to
     * be showing. getBoundingClientRect answers in client coordinates,
     * so a reporter who had scrolled sideways to LOOK at the overflow
     * -- which is what somebody about to report it does -- named
     * whatever had drifted past the right edge from there, and the
     * element actually sticking out was off to the left and not in the
     * list at all. Adding scrollX puts both sides of the comparison in
     * the document's own coordinates, where the answer does not depend
     * on where the window is.
     *
     * The width compared against is the page's, not scrollWidth:
     * scrollWidth is defined BY the offenders, so nothing ever reaches
     * past it and the list would always be empty. */
    const overflowReport = () => {
        const doc = document.documentElement;
        if (doc.scrollWidth <= doc.clientWidth) return { overflows: false };
        const offenders = [...document.querySelectorAll("body *")]
            .filter((el) => el.getBoundingClientRect().right + scrollX >
                            doc.clientWidth + 1)
            .slice(0, 8)
            .map((el) => selectorFor(el));
        return {
            overflows: true,
            scrollWidth: doc.scrollWidth,
            clientWidth: doc.clientWidth,
            offenders
        };
    };

    /* ---------------------------------------------------------------
     * Fragment, sanitised. Runs on a clone; the live DOM is untouched.
     * ------------------------------------------------------------- */
    const scrub = (node, depth) => {
        if (node.localName === "input") {
            if (node.type === "password") {
                node.replaceWith(document.createComment(" password field removed "));
                return;
            }
            node.removeAttribute("value");
            node.removeAttribute("checked");
        }
        if (node.localName === "textarea") node.textContent = "";
        if (node.hasAttribute("data-corrigenda-redact")) {
            node.textContent = "[redacted]";
            return;
        }
        for (const attr of [...node.attributes]) {
            if (attr.value.startsWith("data:") && attr.value.length > 200) {
                node.setAttribute(attr.name,
                                  attr.value.slice(0, 60) + "…[truncated]");
            }
        }
        const children = [...node.children];
        if (depth >= CFG.prune && children.length) {
            children.forEach((c) => c.remove());
            node.append(document.createComment(` ${children.length} more children `));
            return;
        }
        children.forEach((child) => {
            if (child.localName === "script") child.remove();
            else scrub(child, depth + 1);
        });
    };

    const fragmentHtml = (el) => {
        const clone = el.cloneNode(true);
        scrub(clone, 0);
        const html = clone.outerHTML;
        return html.length > CFG.cap
            ? html.slice(0, CFG.cap) + "\n<!-- truncated -->"
            : html;
    };

    /* ---------------------------------------------------------------
     * Accessibility check on the picked element
     * ------------------------------------------------------------- */
    const channel = (value) => {
        const c = value / 255;
        return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
    };

    const luminance = (rgb) =>
        0.2126 * channel(rgb[0]) + 0.7152 * channel(rgb[1]) + 0.0722 * channel(rgb[2]);

    /* One pixel, kept: a canvas per colour would be a canvas per
     * element per ancestor, and the walk up to the backdrop asks for
     * several of them on every audit. */
    let probeContext = null;

    const probe = () => {
        if (!probeContext) {
            const canvas = document.createElement("canvas");
            canvas.width = 1;
            canvas.height = 1;
            probeContext = canvas.getContext("2d",
                                             { willReadFrequently: true });
        }
        return probeContext;
    };

    /* Painted, not parsed. This used to read "the first three numbers
     * in the string are the sRGB bytes", which is true of rgb() and of
     * nothing else the platform now hands back: getComputedStyle
     * answers oklch(0.5 0 0) on a page written in oklch, and the old
     * reader took that for rgb(0.5, 0, 0) -- near-black -- and reported
     * a confident 21:1 for mid grey on white. A wrong number is worse
     * than none here, because the whole point of the field is to be
     * quoted in a bug report.
     *
     * So the engine is asked instead: it is the one that resolved the
     * colour, and a canvas will paint anything it can resolve --
     * oklch(), color-mix(), color(display-p3 ...), whatever comes next.
     * fillStyle keeps its previous value when a string does not parse,
     * so it is set from two different starting points: a colour that
     * answers back the sentinel both times is one this engine cannot
     * read, and the caller gets null rather than an invention. */
    const takes = (ctx, value, sentinel) => {
        ctx.fillStyle = sentinel;
        const before = ctx.fillStyle;
        ctx.fillStyle = value;
        return ctx.fillStyle !== before;
    };

    const parseColour = (value) => {
        const ctx = probe();
        if (!ctx || !value) return null;
        if (!takes(ctx, value, "#000") && !takes(ctx, value, "#fff")) return null;

        ctx.clearRect(0, 0, 1, 1);
        ctx.fillRect(0, 0, 1, 1);
        const [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data;

        /* Fully transparent is not a colour, and the backdrop walk
         * depends on hearing that: it is what makes it keep climbing
         * to the ancestor that actually paints something. */
        return a === 0 ? null : [r, g, b];
    };

    const backdropOf = (el) => {
        let node = el;
        while (node) {
            const colour = parseColour(getComputedStyle(node).backgroundColor);
            if (colour) return colour;
            node = node.parentElement;
        }
        return [255, 255, 255];
    };

    const auditOf = (el) => {
        const style = getComputedStyle(el);
        const front = parseColour(style.color);
        const back = backdropOf(el);
        const rect = el.getBoundingClientRect();
        const audit = { targetSize: `${Math.round(rect.width)}x${Math.round(rect.height)}` };

        if (front) {
            const pair = [luminance(front), luminance(back)].sort((a, b) => b - a);
            audit.contrast = Math.round(
                ((pair[0] + 0.05) / (pair[1] + 0.05)) * 100) / 100;
            audit.fontSize = style.fontSize;
        }
        if (el.localName === "img" && !el.hasAttribute("alt")) {
            audit.missingAlt = true;
        }
        const interactive = el.matches("a, button, input, select, textarea, [role=button]");
        if (interactive && (rect.width < 24 || rect.height < 24)) {
            audit.targetTooSmall = true;
        }
        return audit;
    };

    /* ---------------------------------------------------------------
     * Screenshot (§6.2). getDisplayMedia is the only method that shows
     * the user's REAL rendering; rasterising the DOM would redraw the
     * page as it was meant to look and erase the very defect being
     * reported.
     * ------------------------------------------------------------- */
    const SHOT = { blob: null, scale: null, redacted: 0, scope: "element",
                   surface: null, partial: false, provider: null };

    /* Which report the picture being taken belongs to. A capture is the
     * slowest thing this widget does and the only one that outlives the
     * panel that started it, so every one of them takes a number on the
     * way in and is thrown away if the number has moved on by the time
     * it comes back. clearShot() moves it -- and closePanel goes
     * through clearShot, so dismissing the panel moves it too. */
    let shotAge = 0;

    /* An extension, if one is installed, can photograph this tab through
     * tabs.captureTab: a rectangle in PAGE coordinates, which may lie
     * outside the viewport, at a scale we choose. It announces itself on
     * the documentElement at document_start, so this is known before the
     * first control is drawn. See ops/Corrigenda/extension.
     *
     * What it announces is a contract number, not a release: the shape of
     * the ping and capture exchanges. Below what this widget requires, the
     * add-on is older than the page it is on -- the two are installed and
     * served separately, so that happens -- and the honest answer is to
     * leave it alone and take the share dialog rather than send it a
     * message it will read as something else. Above is fine: a helper
     * keeps the exchanges it has advertised.
     *
     * Read every time it is asked, not once at load. A content script at
     * document_start does set this before any page script runs, so the
     * load-time read was right -- but it made the widget depend on an
     * ordering it cannot see, and an extension that installs, updates or
     * is enabled while the page is open would go unnoticed until a
     * reload. Reading a dataset property costs nothing. */
    /* 2: a pong that says whether the add-on holds a permission for
     * this site. A helper that cannot say only proves a content script
     * is running, which is not what the cropping scopes depend on -- so
     * an older one is treated as no helper, and the page falls back to
     * the share dialog with its warning up. */
    const HELPER_REQUIRED = 2;

    /* A sandboxed iframe or a data: document has origin "null", and
     * postMessage refuses that as a target -- it throws, and it threw
     * inside the ask's own Promise executor, where the rejection looked
     * like an add-on that had said no. It was not a no: the five-second
     * timer and the entry in `waiting` were both still standing, on
     * every ask, for the life of the document. The content script makes
     * this same test and stays silent on such a page, so there is
     * nobody on the other end anyway -- and "no add-on" is the true
     * answer as well as the cheap one. */
    const ADDRESSABLE = window.origin !== "null";

    const extension = () => {
        if (!ADDRESSABLE) return null;

        const provided = Number(
            document.documentElement.dataset.corrigendaCapture);

        return provided >= HELPER_REQUIRED ? provided : null;
    };

    /* Firefox's share dialog offers a window or a screen and no tabs at
     * all, so a frame can never be mapped to page coordinates there and
     * neither cropping nor masking is possible. preferCurrentTab is not
     * feature-detectable, so this is read off the engine — a blunt test,
     * kept honest by the calibration that follows every capture anyway.
     * With the extension the question does not arise: every scope is
     * mappable, in every browser. */
    /* The marker says an add-on is installed and running here. It does
     * not say the half that takes the picture will answer: the site may
     * never have been granted, the background half may be asleep,
     * revoked or mid-update, and a content script registered in a
     * previous session outlives the permission that put it there.
     *
     * So the marker opens the conversation and the reply settles it.
     * null while nobody has asked yet -- and treated as "no", because
     * offering a crop that turns out to be impossible is a promise
     * broken at capture time, while withdrawing the warning a moment
     * later costs nothing.
     */
    let helperAnswers = null;

    /* What the bridge said it was, for the line under the title: the
     * add-on is installed rather than served, so its build is a fact
     * about this browser that nothing else here knows. */
    let helperVersion = null;

    /* Set by the panel once it exists, so an add-on switched on while
     * somebody is looking at the panel reaches the controls it changes.
     */
    let helperArrived = null;

    /* Three things ask this -- the panel when it is built, the
     * screenshot section when it opens, and a bridge that has just been
     * injected -- and their answers used to race. A ping that timed out
     * after five seconds would land after a later one that succeeded in
     * one, and write its stale "no" over a live "yes": the scopes went
     * grey, the scope fell back to "no crop", and nothing on the page
     * had changed to explain it. That is what "random" looked like.
     *
     * So: one ask in flight at a time, and an answer that arrives after
     * a newer ask has started is dropped rather than believed.
     */
    let asking = null;
    let askCount = 0;

    const askHelper = async ({ fresh = false } = {}) => {
        if (!extension()) {
            helperAnswers = false;
            asking = null;
            return false;
        }

        /* Already on its way: wait for that one rather than adding a
         * second wake-up to a background half that is busy waking.
         *
         * Unless the world changed under it -- a bridge injected into a
         * page that was already open is exactly the case where the ask
         * in flight was addressed to nobody and will time out. That one
         * starts again, and the doomed answer is dropped when it lands.
         */
        if (asking && !fresh) return asking;

        const mine = (askCount += 1);
        asking = askOnce(mine).finally(() => {
            if (mine === askCount) asking = null;
        });

        return asking;
    };

    const askOnce = async (mine) => {
        try {
            /* Five seconds rather than two: this is a wake-up, not a
             * round trip -- an event page that has been idle takes its
             * time, and the answer decides whether the cropping scopes
             * are offered at all. Nothing waits on it visibly; the
             * warning is up until it lands and clears itself when it
             * does. */
            const pong = await BRIDGE.ask("ping", {}, 5000);
            /* An add-on that answers but speaks an older contract is one
             * this page must not talk to. It says which it speaks; a
             * helper too old to say is helper 1. */
            /* Three things, and all of them have to hold: something
             * answered, it speaks a contract this page can use, and it
             * says it may capture *here*. The last is the one that a
             * marker alone cannot tell you -- an add-on installed but
             * never granted this site answers cheerfully and cannot
             * take the picture. */
            const answer = pong?.type === "pong" &&
                (pong.helper ?? 1) >= HELPER_REQUIRED &&
                pong.granted === true;

            if (pong?.type === "pong") helperVersion = pong.version || null;

            /* Stale: something newer has been asked since, and its
             * answer is the one to keep. */
            if (mine !== askCount) return helperAnswers;

            helperAnswers = answer;
        } catch {
            if (mine !== askCount) return helperAnswers;

            helperAnswers = false;
        }

        return helperAnswers;
    };

    const tabCapture = () =>
        helperAnswers === true || !navigator.userAgent.includes("Firefox");

    /* postMessage both ways, because the page and the extension's
     * content script share a window and nothing else. Every exchange
     * carries an id: two captures can be in flight when someone changes
     * the scope while the first is still being taken. */
    const BRIDGE = {
        next: 0,
        waiting: new Map(),

        ask(type, payload = {}, timeout = 15000) {
            /* Nothing above reaches here on such a page -- extension()
             * answers null and every caller stops at that -- but the
             * timer and the waiting entry are set BEFORE the throw, so
             * the one place that leaks is the one place that refuses. */
            if (!ADDRESSABLE) {
                return Promise.reject(
                    new Error("this document has no origin to address"));
            }

            const id = `cg-${this.next += 1}`;
            return new Promise((resolve, reject) => {
                const giveUp = setTimeout(() => {
                    this.waiting.delete(id);
                    reject(new Error("the extension did not answer"));
                }, timeout);

                this.waiting.set(id, { resolve, reject, giveUp });
                postMessage({ source: "corrigenda", type, id, ...payload },
                            origin);
            });
        },

        receive(event) {
            if (event.source !== window) return;
            if (event.data?.source !== "corrigenda-extension") return;

            /* Unsolicited: a bridge that has just been put into a page
             * that was already open. Nothing asked for this, so there is
             * no promise waiting on it -- it is a nudge to ask again. */
            if (event.data.type === "hello") {
                askHelper({ fresh: true }).then(() => helperArrived?.());
                return;
            }

            const pending = this.waiting.get(event.data.id);
            if (!pending) return;

            this.waiting.delete(event.data.id);
            clearTimeout(pending.giveUp);
            if (event.data.type === "failed") {
                pending.reject(new Error(event.data.error || "capture refused"));
            } else {
                pending.resolve(event.data);
            }
        }
    };

    /* Unconditional: the listener checks the source of every message
     * anyway, and whether an extension is there is no longer decided
     * once. */
    addEventListener("message", (e) => BRIDGE.receive(e));

    const drawn = (dataUrl) => new Promise((done, fail) => {
        const image = new Image();
        image.onload = () => {
            const canvas = document.createElement("canvas");
            canvas.width = image.naturalWidth;
            canvas.height = image.naturalHeight;
            canvas.getContext("2d").drawImage(image, 0, 0);
            done(canvas);
        };
        image.onerror = () => fail(new Error("the capture did not decode"));
        image.src = dataUrl;
    });

    const SURFACES = {
        browser: () => T.surfaceTab,
        window: () => T.surfaceWindow,
        monitor: () => T.surfaceScreen
    };

    const grabFrame = async () => {
        /* Cropping and redaction need this tab. Asking for it, and asking
         * the dialog to leave whole monitors out, turns the common
         * mistake into something the browser will not offer. Options it
         * does not know are ignored, so Firefox simply gets the first. */
        const stream = await navigator.mediaDevices.getDisplayMedia({
            video: { frameRate: 1 },
            audio: false,
            preferCurrentTab: true,
            selfBrowserSurface: "include",
            surfaceSwitching: "exclude",
            monitorTypeSurfaces: "exclude"
        });

        /* The share dialog is the browser's, not ours, so the only way to
         * know what was picked is to ask the track afterwards. Firefox
         * may not report it; then the calibration is all we have. */
        const surface = stream.getVideoTracks()[0]?.getSettings?.()
                              ?.displaySurface || null;
        try {
            const video = document.createElement("video");
            video.srcObject = stream;
            video.muted = true;
            await video.play();
            /* ImageCapture.grabFrame() is Chrome-only; a video painted
             * into a canvas works in both targets. */
            await new Promise((done) =>
                requestAnimationFrame(() => requestAnimationFrame(done)));
            const canvas = document.createElement("canvas");
            canvas.width = video.videoWidth;
            canvas.height = video.videoHeight;
            canvas.getContext("2d").drawImage(video, 0, 0);
            canvas.dataset.surface = surface || "";
            return canvas;
        } finally {
            stream.getTracks().forEach((track) => track.stop());
        }
    };

    /* The frame can only be mapped to page coordinates when the user
     * shared THIS tab: its width is then the viewport width times some
     * scale, and the height agrees. A whole screen or another window
     * has browser chrome in it, and guessing where things are would
     * blank the wrong rectangles — worse than blanking none. */
    const calibrate = (canvas) => {
        const scale = canvas.width / innerWidth;
        const expected = innerHeight * scale;
        const slack = Math.max(4, expected * 0.02);
        return Math.abs(canvas.height - expected) <= slack ? scale : null;
    };

    const SECRETS = "input:not([type=checkbox]):not([type=radio]), " +
                    "textarea, select, [data-corrigenda-redact]";

    const px = (value) => parseFloat(value) || 0;

    /* Where a frame's own viewport begins, in the coordinates of the
     * document that holds it: its border box, moved in by whatever the
     * border and the padding take. What is measured inside the frame is
     * measured against that origin and against nothing else. */
    const frameOrigin = (frame) => {
        const r = frame.getBoundingClientRect();
        const style = getComputedStyle(frame);
        return { x: r.x + px(style.borderLeftWidth) + px(style.paddingLeft),
                 y: r.y + px(style.borderTopWidth) + px(style.paddingTop) };
    };

    /* A rectangle kept inside another one. A frame scrolled halfway
     * down has secrets whose boxes sit above its own, and painting
     * those where the arithmetic puts them would black out whatever the
     * page has beside the frame -- a bar in the wrong place, which this
     * file refuses to draw anywhere else either. */
    const clipTo = (box, clip) => {
        if (!clip) return box;

        const x = Math.max(box.x, clip.x);
        const y = Math.max(box.y, clip.y);
        return { x, y,
                 width: Math.min(box.x + box.width, clip.x + clip.width) - x,
                 height: Math.min(box.y + box.height, clip.y + clip.height) - y };
    };

    /* Everything that must be covered, in the top document's client
     * coordinates. The count this produces is shown to the reporter and
     * stored in the payload as the number of things that were masked,
     * so it has to be the whole truth -- and one querySelectorAll on the
     * document is not: it stops at every shadow boundary and at every
     * frame border. A password field inside a component, or inside an
     * embedded form, was photographed in full while the panel said the
     * masking was done.
     *
     * So the walk descends. An open shadow root lays out in its host's
     * own coordinate space and needs no offset; a same-origin frame
     * measures against its own viewport and is moved by the frame's
     * content-box origin. Offsets compose on the way down, so a frame
     * inside a frame arrives in the right place.
     *
     * Two things stay out of reach, and they are treated differently
     * because only one of them can be. A cross-origin frame is covered
     * whole: from outside, "there is a password in there" and "there is
     * not" are the same silence, and the only honest answer to a
     * silence is the opaque rectangle. A closed shadow root cannot even
     * be found -- nothing here can mask it, and DESIGN §6.2 says so
     * rather than letting the count imply otherwise. */
    const secretBoxes = (node, offset, clip, out) => {
        for (const el of node.querySelectorAll("*")) {
            /* The widget's own shadow root holds a textarea and a
             * select's worth of controls, and it is not in the picture
             * anyway -- it hides itself before the shutter. */
            if (el === host || host.contains(el)) continue;

            if (el.matches(SECRETS)) {
                const r = el.getBoundingClientRect();
                const box = clipTo({ x: r.x + offset.x, y: r.y + offset.y,
                                     width: r.width, height: r.height }, clip);
                if (box.width >= 1 && box.height >= 1) out.push(box);
            }

            if (el.shadowRoot) secretBoxes(el.shadowRoot, offset, clip, out);

            if (el.localName !== "iframe" && el.localName !== "frame") continue;

            const r = el.getBoundingClientRect();
            const box = clipTo({ x: r.x + offset.x, y: r.y + offset.y,
                                 width: r.width, height: r.height }, clip);
            if (box.width < 1 || box.height < 1) continue;

            /* null cross-origin in every current engine, and older ones
             * threw; a frame that has not loaded yet answers null too,
             * and is just as uninspectable. */
            let inner = null;
            try { inner = el.contentDocument; } catch { inner = null; }

            if (!inner) { out.push(box); continue; }

            const start = frameOrigin(el);
            secretBoxes(inner,
                        { x: start.x + offset.x, y: start.y + offset.y },
                        box, out);
        }
    };

    /* Opaque, not blurred: a blur over short low-entropy text can be
     * undone, a filled rectangle cannot. */
    const redact = (canvas, scale, origin) => {
        const ctx = canvas.getContext("2d");
        ctx.fillStyle = "#000";
        const boxes = [];
        secretBoxes(document, { x: 0, y: 0 }, null, boxes);

        for (const box of boxes) {
            ctx.fillRect((box.x - origin.x) * scale, (box.y - origin.y) * scale,
                         box.width * scale, box.height * scale);
        }
        return boxes.length;
    };

    /* A region is kept in page coordinates and used in client ones.
     * Kept as it was dragged -- client coordinates, which is what a
     * pointer event speaks -- it went stale the moment the page moved
     * under it: between the drag and the shutter there is a panel to
     * fill in, a scope to choose and, without the add-on, a share
     * dialog to answer, and any one of those can be a scroll. The crop
     * then landed on whatever had scrolled into that part of the
     * window, which is a picture of the wrong thing filed as evidence.
     * DESIGN 5 says page coordinates for the same reason, and
     * target.region now says what DESIGN says it does. */
    const toClient = (box) => ({
        x: box.x - scrollX, y: box.y - scrollY,
        width: box.width, height: box.height
    });

    /* The element with its margin, in client coordinates. Two callers
     * want it and they want it for different reasons: this is what the
     * picture is cropped to, and -- where the browser lets us choose the
     * rectangle -- it is also what is asked for in the first place. */
    const elementBox = () => {
        const margin = 16;
        const r = region ? toClient(region) : picked?.getBoundingClientRect();
        if (!r) return null;

        return { x: r.x - margin, y: r.y - margin,
                 width: r.width + margin * 2,
                 height: r.height + margin * 2 };
    };

    /* A rectangle in page coordinates, trimmed to the page. A capture
     * cannot ask for what is off the top or the left of the document,
     * and the margin around an element at the very edge asks for
     * exactly that. */
    const inDocument = (box) => {
        const doc    = document.documentElement;
        const width  = Math.max(doc.scrollWidth, innerWidth);
        const height = Math.max(doc.scrollHeight, innerHeight);
        const x = Math.max(0, box.x);
        const y = Math.max(0, box.y);

        return { x, y,
                 width:  Math.min(box.width  + box.x - x, width  - x),
                 height: Math.min(box.height + box.y - y, height - y) };
    };

    const cropped = (canvas, scale, origin) => {
        let box = null;
        if (SHOT.scope === "element") {
            box = elementBox();
        } else if (SHOT.scope === "viewport") {
            box = { x: 0, y: 0, width: innerWidth, height: innerHeight };
        }
        if (!box) return canvas;

        const x = Math.max(0, Math.round((box.x - origin.x) * scale));
        const y = Math.max(0, Math.round((box.y - origin.y) * scale));
        const width = Math.min(canvas.width - x, Math.round(box.width * scale));
        const height = Math.min(canvas.height - y, Math.round(box.height * scale));
        if (width < 1 || height < 1) return canvas;

        const out = document.createElement("canvas");
        out.width = width;
        out.height = height;
        out.getContext("2d").drawImage(canvas, x, y, width, height,
                                       0, 0, width, height);
        return out;
    };

    const MAX_EDGE = 1600;
    const MAX_BYTES = 2 * 1024 * 1024;

    /* What a browser will actually draw. Firefox and Chrome both stop
     * at 32767 on an edge, and both have an area ceiling below the
     * product of two of those; 100 megapixels is under every one of
     * them and still four times what this ever needs, since the upload
     * is capped at 1600px on the longest edge regardless. */
    const MAX_SIDE = 32000;
    const MAX_AREA = 100e6;

    const withinLimits = (rect) => {
        let scale = devicePixelRatio || 1;

        /* Scale first: it costs nothing here, because the picture is
         * downscaled before it is encoded anyway. */
        while (scale > 0.25 &&
               (rect.width * scale > MAX_SIDE ||
                rect.height * scale > MAX_SIDE ||
                rect.width * rect.height * scale * scale > MAX_AREA)) {
            scale /= 2;
        }

        /* Still too much, so the page is simply longer than a picture
         * can be. Take the top of it and say the shot was cut. */
        const maxHeight = Math.min(MAX_SIDE / scale,
                                   MAX_AREA / (rect.width * scale * scale));
        if (rect.height <= maxHeight) return { rect, scale, cut: false };

        return { rect: { ...rect, height: Math.floor(maxHeight) },
                 scale, cut: true };
    };

    const downscale = (canvas) => {
        const factor = MAX_EDGE / Math.max(canvas.width, canvas.height);
        if (factor >= 1) return canvas;

        const out = document.createElement("canvas");
        out.width = Math.round(canvas.width * factor);
        out.height = Math.round(canvas.height * factor);
        out.getContext("2d").drawImage(canvas, 0, 0, out.width, out.height);
        return out;
    };

    const encode = async (canvas) => {
        const target = downscale(canvas);
        for (const quality of [0.8, 0.6, 0.45]) {
            const blob = await new Promise((done) =>
                target.toBlob(done, "image/webp", quality));
            if (blob && blob.size <= MAX_BYTES) return blob;
        }
        return null;
    };

    /* Two ways to obtain a picture, one interface. A provider returns
     * the frame, where its top-left sits in client coordinates, and the
     * scale between the two -- which is everything redaction and
     * cropping need, and all that ever differed between them.
     *
     * scrollX/scrollY convert page coordinates (what the extension
     * takes) to client coordinates (what getBoundingClientRect gives,
     * and therefore what the rest of this file speaks). */
    const PROVIDERS = {
        extension: {
            name: "extension",

            /* Ask for what is wanted, not for the screenful it sits in.
             * The crop below arrives at the same picture either way, and
             * the two are not the same amount of work: a viewport on a
             * 2560x1400 display is a three-megapixel PNG, encoded by the
             * browser, carried through two message hops as a data URL,
             * decoded again, and thrown away down to the caption
             * somebody pointed at. That is the pause between choosing an
             * element and seeing it. A rectangle round the element is
             * usually a few tens of thousands of pixels and arrives at
             * once.
             *
             * Firefox draws the rectangle it is given, which is what
             * makes this worth doing -- and also why "no crop" can ask
             * for the whole document, which is impossible from a page.
             * Chrome has only captureVisibleTab and answers with the
             * viewport whatever it is asked; the crop below is what
             * makes one path serve both, and it is unchanged. */
            async grab() {
                const doc = document.documentElement;
                const box = SHOT.scope === "element" ? elementBox() : null;
                const wanted = SHOT.scope === "full"
                    ? { x: 0, y: 0,
                        width: Math.max(doc.scrollWidth, innerWidth),
                        height: Math.max(doc.scrollHeight, innerHeight) }
                    : box
                    ? inDocument({ x: box.x + scrollX, y: box.y + scrollY,
                                   width: box.width, height: box.height })
                    : { x: scrollX, y: scrollY,
                        width: innerWidth, height: innerHeight };

                /* A browser will not draw a canvas of any size, and "no
                 * crop" on a long page asks for one: an estate page of
                 * 20 000 pixels at a device ratio of 2 is 40 000 down,
                 * past every engine's limit, and what comes back is not
                 * a picture but an exception. So the scale comes down
                 * first -- the shot is capped at 1600px on its longest
                 * edge before upload anyway, so nothing legible is lost
                 * -- and the height after it, which is the one thing
                 * that has to be said out loud rather than quietly
                 * cropped. */
                const { rect, scale, cut } = withinLimits(wanted);

                const answer = await BRIDGE.ask("capture", { rect, scale });
                const canvas = await drawn(answer.dataUrl);

                /* What came back, not what was asked for. Firefox grants
                 * the rectangle; Chrome has only captureVisibleTab and
                 * grants the viewport whatever was requested. Cropping
                 * from the granted rectangle is what lets one path serve
                 * both -- and what stops a Chrome capture being cropped
                 * as though it held the whole document. */
                const got = answer.rect || rect;

                /* What it says it drew at, when it says anything usable.
                 * The fallback used to be `dpr`, which is not a name
                 * anything here defines: the first reply without a scale
                 * in it -- an older add-on, a capture path that forgot
                 * to echo it -- would have thrown a ReferenceError out
                 * of the one place that had a picture in its hands.
                 * Zero and NaN are the same failure and take the same
                 * answer, because everything downstream multiplies by
                 * this and would place the crop and every mask nowhere. */
                const given = Number(answer.scale);
                const drawnAt = Number.isFinite(given) && given > 0
                    ? given
                    : (devicePixelRatio || 1);

                /* Two ways to get less than was asked for, and they had
                 * to be answered together. `got` is measured against
                 * `rect`, which is what withinLimits left of the
                 * request -- so a page cut down to fit a canvas
                 * compared its picture against the cut-down rectangle,
                 * agreed with itself, and reported a whole capture. The
                 * comment above promised the height was "said out loud"
                 * and only a write-only SHOT.trimmed ever said it. It
                 * is said here now, where the one flag the reporter and
                 * the payload both read is decided. */
                return {
                    canvas,
                    scale: drawnAt,
                    origin: { x: got.x - scrollX, y: got.y - scrollY },
                    surface: "browser",
                    whole: !cut &&
                           got.width >= rect.width - 1 &&
                           got.height >= rect.height - 1
                };
            }
        },

        display: {
            name: "display",

            async grab() {
                const canvas = await grabFrame();
                return {
                    canvas,
                    /* null when the share was a window or a screen: the
                     * frame cannot be placed on the page at all. */
                    scale: calibrate(canvas),
                    origin: { x: 0, y: 0 },
                    surface: canvas.dataset.surface || null
                };
            }
        }
    };

    const provider = () =>
        (extension() ? PROVIDERS.extension : PROVIDERS.display);

    const capture = async (mine) => {
        /* The widget must not photograph itself: it is fixed over the
         * page it is reporting on, and would sit in the middle of the
         * evidence. visibility rather than display, so nothing reflows
         * underneath and the shot matches what you were looking at. */
        host.style.visibility = "hidden";
        /* Which of the two took it, decided once and remembered: the
         * fallback below can change the answer halfway through, and
         * asking provider() again afterwards would report where the
         * next capture would go rather than where this picture came
         * from. It ends up in the payload (§6.2). */
        const chosen = provider();
        let from = chosen.name;
        let frame;
        try {
            frame = await chosen.grab();
        } catch (error) {
            /* An extension that is asleep, revoked or mid-update must
             * not take the screenshot away with it. */
            if (chosen !== PROVIDERS.extension) throw error;

            /* Kept, because the next thing that happens is a share
             * dialog, and if that is cancelled the browser's word for it
             * -- "not allowed by the user agent in the current context"
             * -- is the only thing anybody sees. It describes the
             * dialog. The interesting failure is this one, and it was
             * being thrown away one line later. */
            bridgeError = String(error?.message || error || "").trim();
            console.warn("corrigenda: the add-on could not capture; " +
                         "falling back to the share dialog", error);

            /* One more attempt through the bridge before anything
             * louder. The background half sleeps between uses and the
             * first message through is what wakes it, so a failure here
             * is as often a nap as a refusal -- and the fallback is the
             * share dialog, which is a permission prompt in somebody's
             * face on a site that had already been granted. Ask twice
             * before doing that.
             */
            try {
                frame = await PROVIDERS.extension.grab();
                bridgeError = null;
            } catch (again) {
                bridgeError = String(again?.message || again || "").trim();
                /* Twice is an answer. Say so: the cropping scopes go and
                 * the warning comes back, rather than the next capture
                 * discovering it again. */
                helperAnswers = false;
                syncScopes();

                from = PROVIDERS.display.name;
                frame = await PROVIDERS.display.grab();
            }
        } finally {
            host.style.visibility = "";
        }

        const taken = {
            provider: from,
            scale: frame.scale,
            redacted: 0,
            surface: frame.surface,
            /* Given less than was asked for: a browser that can only
             * photograph the window, or a rectangle too tall for any
             * canvas. Not tied to the "no crop" scope any more -- a
             * viewport on a very large display is cut for the second
             * reason too, and said nothing about it. */
            partial: frame.whole === false,
            blob: null
        };

        if (frame.scale === null) {
            /* Cannot place anything: send the frame untouched and say so. */
            taken.blob = await encode(frame.canvas);
        } else {
            taken.redacted = redact(frame.canvas, frame.scale, frame.origin);
            taken.blob = await encode(
                cropped(frame.canvas, frame.scale, frame.origin));
        }

        /* Everything above takes time -- a share dialog somebody has to
         * answer, a document-sized PNG through two message hops, a WebP
         * encoded three times over -- and the panel does not wait. If it
         * was dismissed, or the shot removed, while this was happening,
         * then this picture belongs to a report that no longer exists,
         * and it used to be written into SHOT anyway: the next report
         * opened, said nothing about a screenshot, and carried the
         * previous one's image up with it. Dropped here, before it can
         * be committed, rather than untangled afterwards. */
        if (mine !== shotAge) return { stale: true };

        Object.assign(SHOT, taken);
        return { mapped: frame.scale !== null };
    };

    /* ---------------------------------------------------------------
     * Widget
     * ------------------------------------------------------------- */
    const CSS_TEXT = `
@layer reset, tokens, components, overrides;

@layer reset {
    *, *::before, *::after { box-sizing: border-box; }

    :host {
        all: initial;
        position: fixed;
        inset-block-end: 1rem;
        inset-inline-end: 1rem;
        z-index: 2147483000;
        color-scheme: light dark;
        font-family: system-ui, sans-serif;
        line-height: 1.5;
    }
}

@layer tokens {
    :host {
        --surface: light-dark(oklch(99% 0 0), oklch(22% 0.01 260));
        --raised:  light-dark(oklch(96% 0.004 260), oklch(28% 0.01 260));
        --ink:     light-dark(oklch(24% 0.01 260), oklch(94% 0.01 260));
        --muted:   light-dark(oklch(44% 0.015 260), oklch(74% 0.02 260));
        --line:    light-dark(oklch(82% 0.01 260), oklch(42% 0.015 260));
        --accent:  light-dark(oklch(45% 0.16 255), oklch(78% 0.13 255));
        --space:   0.75rem;

        /* One hue per relation, used by the ghost outline AND by the key
         * that moves there, so the colour is read off the help bar
         * instead of guessed. */
        --parent:  light-dark(oklch(62% 0.16 55),  oklch(74% 0.15 55));
        --child:   light-dark(oklch(52% 0.14 150), oklch(70% 0.14 150));
        --sibling: light-dark(oklch(55% 0.18 305), oklch(74% 0.15 305));
        --warn:    light-dark(oklch(58% 0.19 30),  oklch(72% 0.17 30));
        --danger:  light-dark(oklch(45% 0.17 28),  oklch(80% 0.14 28));
    }
}

@layer components {
    button {
        min-block-size: 2.25rem;
        padding-inline: 0.6rem;
        font: inherit;
        color: var(--ink);
        background: var(--raised);
        border: 1px solid var(--line);
        border-radius: 0.4rem;
        cursor: pointer;

        &:hover { border-color: var(--accent); }
    }

    :focus-visible {
        outline: 2px solid var(--accent);
        outline-offset: 2px;
    }

    .launcher {
        background: var(--accent);
        color: light-dark(white, black);
        border-color: transparent;
        box-shadow: 0 1px 6px rgb(0 0 0 / 0.3);
    }

    .panel {
        inline-size: min(21rem, calc(100vw - 1.5rem));
        max-block-size: calc(100dvh - 1.5rem);
        overflow-y: auto;
        padding: 0.5rem;
        color: var(--ink);
        background: var(--surface);
        border: 1px solid var(--line);
        border-radius: 0.5rem;
        box-shadow: 0 2px 16px rgb(0 0 0 / 0.35);
    }

    header {
        position: sticky;
        inset-block-start: -0.5rem;
        z-index: 1;
        /* Opaque, and paid for out of the panel's own padding, so the
         * content scrolls under it rather than through it. */
        margin: -0.5rem -0.5rem 0;
        padding: 0.5rem 0.5rem 0.35rem;
        background: var(--surface);

        display: flex;
        /* The warning and the close button are a pair of controls at the
         * end of the bar, not two separate things spaced apart -- the
         * report line takes whatever is left. */
        gap: 0.3rem;
        align-items: center;
        justify-content: space-between;
        cursor: move;
        /* the pointer belongs to the drag, not to the page scroller */
        touch-action: none;

        .titles {
            flex: 1 1 auto;
            min-inline-size: 0;
        }

        .colophon {
            margin: 0;
            font-size: 0.6875rem;
            line-height: 1.3;
            color: var(--muted);
            user-select: text;
            /* It is information, not a control, and the header is the
               drag handle: selecting it should not move the window. */
            cursor: text;
            overflow-wrap: anywhere;
        }

        /* Where reports go, when that is not here. A hostname broken
           across lines is a hostname somebody mistypes, so this one
           never breaks: it takes a line of its own and is cut with an
           ellipsis when the panel is narrower than the name -- whole
           in the title, and selectable like the rest of the line. */
        .colophon .destination {
            display: block;
            max-inline-size: 100%;
            overflow: hidden;
            white-space: nowrap;
            text-overflow: ellipsis;
        }

        h2 {
            flex: 1 1 auto;
            margin: 0;
            min-inline-size: 0;
            font-size: 0.9375rem;
            user-select: none;

            /* Once a kind is chosen the heading stops announcing itself
             * and becomes the report's own summary: monospace, because
             * it is a fact about the page, and one line, because a
             * wrapping title is a title that grew a row. */
            &.is-report {
                overflow: hidden;
                font-family: ui-monospace, monospace;
                font-size: 0.75rem;
                font-weight: 400;
                color: var(--muted);
                white-space: nowrap;
                text-overflow: ellipsis;
            }
        }
    }

    /* One line per kind: name, what it is for, what it will collect.
     * Stacked cards turned four choices into a screenful. */
    .menu {
        display: grid;
        gap: 0.2rem;
        margin-block-start: 0.4rem;

        button {
            /* A column for the name, so the descriptions line up
               instead of starting wherever the word above ended. */
            display: grid;
            grid-template-columns: 4.75rem 1fr auto;
            gap: 0.4rem;
            align-items: center;
            min-block-size: 2.25rem;
            padding: 0.3rem 0.45rem;
            text-align: start;
            border-radius: 0.35rem;

            strong { font-size: 0.875rem; }

            /* The hint yields first: it is the least load-bearing part
             * of the row, and the marks must not wrap. */
            span:not(.marks) {
                flex: 1 1 auto;
                min-inline-size: 0;
                overflow: hidden;
                color: var(--muted);
                font-size: 0.75rem;
                white-space: nowrap;
                text-overflow: ellipsis;
            }

            .marks {
                display: flex;
                flex: 0 0 auto;
                gap: 0.1rem;
                margin-inline-start: auto;
            }

            &:hover {
                border-color: var(--accent);
                background: color-mix(in oklab, var(--accent) 8%, var(--raised));
            }
        }
    }

    /* Above the fold of a 21rem panel there is room for one popover and
     * no more, so it is one element that moves. */
    .pop {
        position: fixed;
        inset: 0 auto auto 0;
        max-inline-size: 17rem;
        margin: 0;
        padding: 0.35rem 0.5rem;
        font-size: 0.75rem;
        line-height: 1.35;
        color: var(--ink);
        background: var(--surface);
        border: 1px solid var(--line);
        border-radius: 0.35rem;
        box-shadow: 0 2px 10px rgb(0 0 0 / 0.3);
    }

    textarea {
        /* Down is the only direction it may grow. A textarea resized
         * wider than the panel does not widen the panel -- it hangs out
         * of it and hands the whole window a horizontal scrollbar. */
        resize: vertical;
        inline-size: 100%;
        max-inline-size: 100%;
        min-block-size: calc(3lh + 0.8rem + 2px);
        margin-block-start: 0.4rem;
        padding: 0.4rem;
        font: inherit;
        color: var(--ink);
        background: var(--raised);
        border: 1px solid var(--line);
        border-radius: 0.4rem;
    }

    .total {
        color: var(--muted);
        font-size: 0.78rem;
        font-variant-numeric: tabular-nums;
    }

    /* Even columns rather than a ragged wrap: the number of them comes
     * from the room there is, and the track floor is the longest name
     * the widget has to hold. French words are longer, so the tracks
     * stretch and the count drops by itself -- no breakpoint decides
     * this, and none has to be revisited when a name changes. */
    fieldset {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(min(100%, 6.25rem), 1fr));
        gap: 0.25rem;
        margin: 0.4rem 0 0;
        padding: 0;
        border: 0;
    }

    /* The checkbox stays real — it carries the name and the keyboard —
     * and the chip is what you see. Unchecked reads as drained rather
     * than as a different colour, so the hue still means the channel. */
    .switch {
        cursor: pointer;

        &.is-unavailable {
            cursor: not-allowed;

            .chip {
                color: var(--muted);
                background: transparent;
                box-shadow: inset 0 0 0 1px var(--line);
                opacity: 0.55;
            }
        }

        input {
            position: absolute;
            inline-size: 1px;
            block-size: 1px;
            overflow: hidden;
            clip-path: inset(50%);
        }

        /* Named in full: a letter works in a table of many reports,
         * where a legend sits underneath, but here the switch is the
         * only place the choice is explained.
         *
         * The chip below carries everything a chip is -- the hue, the
         * fill, the weight, the centring. Only what a full name in a
         * fieldset track needs is restated here: a cell that fills its
         * track and centres in it rather than a word that sits on a
         * line, and the room a word like "Diagnostics" wants. The two
         * displays are not a disagreement; they are the same token in a
         * grid and in a sentence. */
        .chip {
            display: grid;
            place-items: center;
            block-size: 100%;
            min-block-size: 1.5rem;
            padding-inline: 0.25em;
            font-size: 0.6875rem;
            /* A name longer than its track wraps inside the chip rather
             * than reaching past it. */
            overflow-wrap: anywhere;
            border-radius: 0.3125rem;
        }

        /* Off is unfilled, not colourless. Draining the hue as well took
         * away the one thing that says WHICH channel the switch is --
         * five of the six are off in a content report, and the row read
         * as six grey boxes. Filled or hollow carries the state; the
         * hue keeps carrying the channel, here and in the report list
         * and on the menu marks, which are the same six colours. */
/* :where() so this cannot outrank .is-unavailable below it:
 * a bare :not(:checked) counts as a class and quietly won,
 * which gave a switch you are not allowed to turn on the
 * same hue as one you simply have not. */
input:where(:not(:checked)) + .chip {
            color: light-dark(oklch(42% 0.07 var(--hue)),
                              oklch(82% 0.06 var(--hue)));
            background: transparent;
            box-shadow: inset 0 0 0 1px light-dark(oklch(72% 0.09 var(--hue)),
                                                   oklch(52% 0.09 var(--hue)));
        }

        input:focus-visible + .chip {
            outline: 2px solid var(--accent);
            outline-offset: 2px;
        }
    }

    .preview {
        max-block-size: 12rem;
        margin-block: 0.4rem 0;
        overflow: auto;
        padding: 0.5rem;
        font-size: 0.75rem;
        background: var(--raised);
        border: 1px solid var(--line);
        border-radius: 0.4rem;
    }

    .actions {
        position: sticky;
        inset-block-end: -0.5rem;
        z-index: 1;
        margin: 0.45rem -0.5rem -0.5rem;
        padding: 0.4rem 0.5rem 0.5rem;
        background: var(--surface);
        border-block-start: 1px solid var(--line);

        display: flex;
        gap: 0.4rem;
        align-items: center;
        justify-content: flex-end;

        button { min-block-size: 2rem; }

        /* Not a button to look at, a way in to the payload -- kept at
         * the far end so the two real actions stay together. */
        .a-preview {
            margin-inline-end: auto;
            min-block-size: 1.75rem;
            padding-inline: 0.2rem;
            font-size: 0.75rem;
            color: var(--muted);
            background: transparent;
            border-color: transparent;

            &:hover { color: var(--ink); border-color: var(--line); }
        }

        /* Cancel discards what you wrote, so it is not neutral — and
         * a blocked Send is grey, which a grey Cancel beside it was
         * indistinguishable from. Outlined rather than filled: it is
         * still the lesser of the two actions. */
        .a-cancel {
            color: var(--danger);
            background: transparent;
            border-color: color-mix(in oklab, var(--danger) 50%, transparent);

            &:hover {
                border-color: var(--danger);
                background: color-mix(in oklab, var(--danger) 10%, transparent);
            }
        }

        /* Send is the one thing this panel exists to do. */
        .a-send {
            color: light-dark(white, black);
            background: var(--accent);
            border-color: transparent;
            font-weight: 600;

            &.is-blocked {
                color: var(--muted);
                background: var(--raised);
                border-color: var(--line);
                cursor: not-allowed;
            }
        }
    }

    /* Where a report ends. The window closes on success -- the thing it
     * was opened to do is done, and leaving it standing invites a second
     * report about the same defect -- so the reference number has to be
     * said somewhere the window no longer is. Top right, away from the
     * launcher the eye has just left, and gone in a few seconds;
     * hovering holds it, since the number is the one thing worth
     * copying.
     *
     * Fixed with both insets written out. Left to inset:auto while
     * hidden it would resolve to its static position inside the host --
     * bottom right -- and every reveal would fly up the page from the
     * launcher. */
    .toast {
        position: fixed;
        inset-block-start: 1rem;
        inset-inline-end: 1rem;
        inline-size: max-content;
        max-inline-size: min(21rem, calc(100vw - 1.5rem));
        padding: 0.5rem 0.7rem;
        color: var(--ink);
        font-size: 0.875rem;
        background: var(--surface);
        border: 1px solid var(--line);
        border-inline-start: 3px solid var(--accent);
        border-radius: 0.4rem;
        box-shadow: 0 2px 16px rgb(0 0 0 / 0.35);
        cursor: pointer;
        animation: toast-in 160ms ease-out;

        &.is-leaving {
            animation: toast-out 200ms ease-in forwards;
        }

        @media (prefers-reduced-motion: reduce) {
            animation: none;

            &.is-leaving { animation: none; }
        }
    }

    @keyframes toast-in {
        from { opacity: 0; translate: 0 -0.4rem; }
    }

    @keyframes toast-out {
        to { opacity: 0; translate: 0 -0.4rem; }
    }

    .result {
        margin-block-start: var(--space);
        padding: 0.5rem;
        border: 1px solid var(--line);
        border-radius: 0.4rem;
        background: var(--raised);
        font-size: 0.875rem;

        /* Everything the panel itself still says is a refusal -- what
         * went right is said by the toast, after the panel has closed --
         * and a refusal must not read as a grey aside. */
        &.is-error {
            color: var(--ink);
            background: color-mix(in oklab, var(--danger) 14%, transparent);
            border-color: var(--danger);
        }
    }

    /* What a chip is, wherever one appears: on a switch, on a menu row,
     * and in the report list this widget's reports end up in. The hue
     * is the channel and the fill is the chip; the shape it takes is
     * the caller's business (see .switch above). */
    .chip {
        --hue: 260;

        display: inline-block;
        min-inline-size: 1.35em;
        padding-inline: 0.2em;
        font-family: inherit;
        font-size: 0.8125rem;
        font-weight: 600;
        text-align: center;
        color: light-dark(oklch(25% 0.03 var(--hue)), oklch(95% 0.02 var(--hue)));
        background: light-dark(oklch(90% 0.055 var(--hue)),
                               oklch(34% 0.05 var(--hue)));
        border-radius: 0.2rem;

        &[data-channel="fragment"]    { --hue: 250; }
        &[data-channel="rules"]       { --hue: 305; }
        &[data-channel="computed"]    { --hue: 195; }
        &[data-channel="diagnostics"] { --hue: 45;  }
        &[data-channel="audit"]       { --hue: 150; }
        &[data-channel="screenshot"]  { --hue: 355; }
    }

    .shot { margin-block-start: 0.6rem; }

    /* A picture answers "how much of the screen" faster than a sentence
     * does, and these three differ by shape rather than by wording. The
     * radio keeps the name, the keyboard and the group semantics; the
     * chosen one is also named in words underneath, so the drawing never
     * has to carry the meaning alone. */
    .scope {
        display: flex;
        gap: 0.25rem;
        align-items: center;
    }

    .scope-option {
        /* Flex, not inline: a label around a block svg still lays out a
         * line box, and the descender space under it made the group
         * eight pixels taller than the icons it holds -- which is what
         * knocked the three of them out of line with the button beside
         * them. */
        display: flex;
        cursor: pointer;

        input {
            position: absolute;
            inline-size: 1px;
            block-size: 1px;
            overflow: hidden;
            clip-path: inset(50%);
        }

        svg {
            display: block;
            /* Small enough that the three of them, the thumbnail and
               the capture button share one row of a 21rem panel. */
            inline-size: 2.375rem;
            block-size: var(--control);
            padding: 0.2rem 0.25rem;
            background: var(--raised);
            border: 1px solid var(--line);
            border-radius: 0.375rem;

            rect {
                fill: none;
                stroke: var(--muted);
                stroke-width: 1.5;
            }

            /* solid: the one part being sent. wash: an area, not a
             * block — filled solid, the page stopped reading as a page. */
            .solid { fill: var(--muted); stroke: none; }
            .wash  { fill: var(--muted); fill-opacity: 0.28; }
            .dashed { stroke-dasharray: 3 2; }
        }

        input:checked + svg {
            border-color: var(--accent);
            background: color-mix(in oklab, var(--accent) 12%, var(--raised));

            rect { stroke: var(--accent); }
            .solid, .wash { fill: var(--accent); }
        }

        input:focus-visible + svg {
            outline: 2px solid var(--accent);
            outline-offset: 2px;
        }

        &.is-unavailable {
            cursor: not-allowed;

            svg { opacity: 0.4; }
        }
    }

    .scope-note {
        margin-block: 0.15rem 0;
        font-size: 0.7rem;
        line-height: 1.3;
        color: var(--muted);
    }

    .scope-name {
        margin-block: 0.25rem 0;
        font-size: 0.75rem;
        color: var(--muted);
    }

    /* Switched on, nothing captured: the one thing left to do before the
     * report is what it claims to be. */
    .a-shot.is-wanted {
        color: light-dark(white, black);
        background: var(--warn);
        border-color: transparent;
        font-weight: 600;
    }

    @media (prefers-reduced-motion: no-preference) {
        .a-shot.is-wanted { animation: shot-pulse 1.6s ease-in-out infinite; }
    }

    @keyframes shot-pulse {
        0%, 100% { box-shadow: 0 0 0 0 color-mix(in oklab, var(--warn) 55%, transparent); }
        50%      { box-shadow: 0 0 0 0.35rem color-mix(in oklab, var(--warn) 0%, transparent); }
    }

    /* Scope, thumbnail, state, action: one row, which grows only when
     * something went wrong and has to be said in words. */
    .shot {
        /* One height for everything standing on this row -- the three
         * scope icons, the thumbnail, the drop button and the capture
         * button. Centred, they still read as four different objects
         * when each sets its own size; sharing the height is what makes
         * them read as one control strip. */
        --control: 1.875rem;

        display: flex;
        flex-wrap: wrap;
        gap: 0.25rem;
        align-items: center;
        margin-block-start: 0.4rem;
    }

    .shot-status {
        /* Its own line, always. Sharing the row made the strip jump
         * between one row and two as the wording changed length --
         * "captured · 826 B · 2 masks" fits, a refusal does not -- and the
         * controls moved under a message that had nothing to do with
         * them. */
        flex: 1 0 100%;
        min-inline-size: 0;
        color: var(--muted);
        font-size: 0.72rem;
        line-height: 1.25;

        /* Nothing to say, nothing to draw: without this an emptied
         * warning leaves its box behind. */
        &:empty { display: none; }

        /* Not cropped and not masked is the one screenshot outcome with a
         * consequence, so it stops looking like a status and starts
         * looking like a warning. */
        &.is-warning {
            padding: 0.25rem 0.4rem;
            color: var(--ink);
            background: color-mix(in oklab, var(--warn) 22%, transparent);
            border: 1px solid var(--warn);
            border-radius: 0.3rem;
        }
    }

    /* Under the line that describes it, at whatever size it is, up to
     * the width of the panel -- a capture worth checking is a capture
     * you can see. Auto inline margins centre it on its own row: they
     * absorb the free space a flex item leaves. */
    .shot-preview {
        flex: 0 0 auto;
        max-inline-size: 100%;
        block-size: auto;
        margin-inline: auto;
        border: 1px solid var(--line);
        border-radius: 0.25rem;
    }

    /* Dropping a capture belongs to the capture, so it sits on it
     * rather than beside it as a word. */
    .a-drop {
        min-block-size: var(--control);
        block-size: var(--control);
        padding-inline: 0.5rem;
        font-size: 0.75rem;
        color: var(--muted);
    }

    /* Takes whatever the icons and Remove leave: it is the action of
     * this row, and a button sized to its own word looked like one
     * option among several. */
    .a-shot {
        flex: 1 1 auto;
        min-block-size: var(--control);
        block-size: var(--control);
        padding-inline: 0.45rem;
        font-size: 0.8125rem;
    }

    /* A fact about the browser, not about this report: it sits in the
     * header, out of the way, and explains itself on hover or focus
     * like every other mark in this panel. */
    /* The pair at the end of the header is a pair: same box, whatever
     * glyph is in it. The close button takes its size from the default
     * button rule, so the warning is squared off to match rather than
     * sized on its own. */
    .a-warn, .a-close {
        display: grid;
        place-items: center;
        min-inline-size: 2.25rem;
        padding-inline: 0.4rem;
    }

    .a-warn {
        color: var(--warn);
        background: transparent;
        border-color: color-mix(in oklab, var(--warn) 45%, transparent);

        &:hover { border-color: var(--warn); }

        svg {
            display: block;
            inline-size: 0.95rem;
            block-size: 0.95rem;
            fill: currentColor;
        }
    }

    /* Where each key would take you, drawn at the same time as the
     * highlight. Dashed and thinner than the selection, so the thing
     * actually selected stays the loudest mark on the page. */
    .ghost {
        position: fixed;
        z-index: 2147483000;
        pointer-events: none;

        /* Three things, because one was not enough on a busy page: a
         * thicker dashed edge, a wash so the EXTENT of a big parent is
         * readable and not just its border, and a pale halo outside the
         * dashes so the colour survives against dark content. */
        outline: 3px dashed var(--ghost);
        outline-offset: 0;
        background: color-mix(in oklab, var(--ghost) 14%, transparent);
        box-shadow: 0 0 0 1px light-dark(rgb(255 255 255 / 0.75),
                                         rgb(0 0 0 / 0.6));

        &.is-parent { --ghost: var(--parent); }
        &.is-child  { --ghost: var(--child); }
        &.is-prev, &.is-next { --ghost: var(--sibling); }
    }

    /* A relation key is dressed as the box it draws: same hue, same
     * 2px edge, same wash. The hue on its own was a thin border on a
     * small glyph and read as decoration. Text stays --ink so the
     * label keeps its contrast against the tint. */
    .picker-help {
        .k-parent, .k-child, .k-sibling {
            border-width: 2px;
            color: var(--ink);
            font-weight: 600;
        }

        .k-parent {
            border-color: var(--parent);
            background: color-mix(in oklab, var(--parent) 22%, transparent);
        }

        .k-child {
            border-color: var(--child);
            background: color-mix(in oklab, var(--child) 22%, transparent);
        }

        .k-sibling {
            border-color: var(--sibling);
            background: color-mix(in oklab, var(--sibling) 22%, transparent);
        }
    }

    /* What the keys do, while they do it. The panel is hidden during
     * picking, so the hint that used to live in it was never seen.
     * pointer-events: none, or it would eat the click it describes. */
    .picker-help, .text-help {
        position: fixed;
        inset-block-start: 0.75rem;
        inset-inline: 0;
        z-index: 2147483003;
        display: flex;
        flex-wrap: wrap;
        gap: 0.35rem 0.9rem;
        justify-content: center;
        inline-size: fit-content;
        max-inline-size: calc(100vw - 1.5rem);
        margin-inline: auto;
        padding: 0.4rem 0.7rem;
        font-size: 0.8125rem;
        color: var(--ink);
        background: var(--surface);
        border: 1px solid var(--line);
        border-radius: 0.4rem;
        box-shadow: 0 2px 12px rgb(0 0 0 / 0.25);
        pointer-events: none;

        /* Two keys, two boxes: without this they touch and read as
           one wide key rather than a pair. */
        kbd + kbd { margin-inline-start: 0.2em; }

        kbd {
            padding-inline: 0.3em;
            font-family: ui-monospace, monospace;
            font-size: 0.9em;
            border: 1px solid var(--line);
            border-radius: 0.2rem;
        }
    }

    /* The picker overlay never takes pointer events: it must not change
     * what the page beneath it does. */
    /* Anchored at the viewport origin and moved with translate. Anchored
     * by inset instead, a hidden overlay has inset:auto and resolves to
     * its static position — inside the host, bottom-right — so every
     * reveal animated in from the debug window. */
    .overlay, .tag {
        position: fixed;
        inset-block-start: 0;
        inset-inline-start: 0;
        pointer-events: none;
    }

    /* A dragged rectangle answers a question an element cannot: "these
     * two things are misaligned", "there is too much space here". It is
     * dashed like the relations and accented like the selection, because
     * it is a selection that happens not to be an element. */
    .region {
        position: fixed;
        inset-block-start: 0;
        inset-inline-start: 0;
        z-index: 2147483001;
        pointer-events: none;
        outline: 2px dashed var(--accent);
        background: color-mix(in oklab, var(--accent) 16%, transparent);
    }

    .overlay {
        z-index: 2147483001;
        outline: 3px solid var(--accent);
        outline-offset: 0;
        background: light-dark(oklch(70% 0.13 255 / 0.26),
                               oklch(70% 0.13 255 / 0.32));
        box-shadow: 0 0 0 1px light-dark(rgb(255 255 255 / 0.8),
                                         rgb(0 0 0 / 0.65));
    }

    .tag {
        z-index: 2147483002;
        inline-size: max-content;
        padding-inline: 0.35rem;
        font-size: 0.75rem;
        color: light-dark(white, black);
        background: var(--accent);
        border-radius: 0.2rem;
    }
}

@layer overrides {
    /* The hidden attribute only works because the UA sheet says
     * display:none, and any author display declaration beats it: .menu
     * is a grid, the panel a block. Last layer wins, so this holds
     * without !important. */
    [hidden] { display: none; }
}

@media (prefers-reduced-motion: no-preference) {
    @layer components {
        .overlay, .tag {
            transition: translate 90ms ease-out,
                        inline-size 90ms ease-out,
                        block-size 90ms ease-out;
        }

        /* The first placement after being hidden is a jump, not a move:
         * there is no previous element to travel from. */
        .overlay.is-placing, .tag.is-placing { transition: none; }
        .panel.is-dragging { transition: none; }
    }
}

/* Compact is a desktop affordance. Where the pointer is a finger,
   the targets go back to the touch floor. */
@media (pointer: coarse) {
    @layer components {
        button { min-block-size: 2.75rem; }
        .menu button { min-block-size: 3rem; }
        .switch .chip { min-inline-size: 2.75rem; min-block-size: 2.75rem; }
    }
}

@media (forced-colors: active) {
    @layer components {
        .overlay { outline-color: Highlight; background: transparent; }
        .launcher, button { border: 1px solid ButtonText; }

        /* On and off were said with a fill, a box-shadow and a border
         * colour, and forced colours override all three: six channel
         * chips read identically, and so did the three scope icons, so
         * the panel could not say what it was about to send. An outline
         * is one of the few things left alone here, so it is what
         * carries the state -- drawn only on what is chosen, since
         * unchecked has nothing to say and a mark on everything says
         * nothing. */
        .switch input:checked + .chip,
        .scope-option input:checked + svg {
            outline: 2px solid Highlight;
        }
    }
}
`;

    const host = document.createElement("div");
    host.id = "corrigenda-widget";
    host.dataset.version = VERSION;
    /* Open, not closed: the CSS isolation is identical either way, and
     * an open root can be inspected and driven from a test. */
    const root = host.attachShadow({ mode: "open" });
    const sheet = new CSSStyleSheet();
    sheet.replaceSync(CSS_TEXT);
    root.adoptedStyleSheets = [sheet];

    root.innerHTML = `
        <button class="launcher a-open" aria-haspopup="dialog">${T.open}</button>
        <div class="panel" role="dialog" aria-label="${T.title}" hidden>
            <header>
                <div class="titles">
                    <h2 class="target">${T.title}</h2>
                    <!-- What is actually running, in the smallest type
                         the panel has. A report about a page is often a
                         report about a build, and the first question
                         anybody asks of an odd capture is which widget
                         and which add-on took it. -->
                    <p class="colophon"></p>
                </div>
                <!-- triangle-exclamation, solid weight, from Font Awesome Free
                     7.3.1. Icons are CC BY 4.0, so the source is named here:
                     https://fontawesome.com/license/free. Drawn rather than
                     typed: a text warning sign renders as a different picture on
                     every platform, and as a colour emoji on some of them, which
                     is not a mark this panel can tint. -->
                <button type="button" class="a-warn" hidden
                        aria-label="${T.noTabCapture}">
                    <svg viewBox="0 0 512 512" aria-hidden="true">
                        <path d="M256 0c14.7 0 28.2 8.1 35.2 21l216 400c6.7 12.4 6.4 27.4-.8 39.5S486.1 480 472 480L40 480c-14.1 0-27.2-7.4-34.4-19.5s-7.5-27.1-.8-39.5l216-400c7-12.9 20.5-21 35.2-21zm0 352a32 32 0 1 0 0 64 32 32 0 1 0 0-64zm0-192c-18.2 0-32.7 15.5-31.4 33.7l7.4 104c.9 12.5 11.4 22.3 23.9 22.3 12.6 0 23-9.7 23.9-22.3l7.4-104c1.3-18.2-13.1-33.7-31.4-33.7z"/>
                    </svg>
                </button>
                <button class="a-close" aria-label="${T.close}">✕</button>
            </header>
            <div class="menu">
                <button class="a-type" value="visual">
                    <strong>${T.visual}</strong><span>${T.visualHint}</span>
                </button>
                <button class="a-type" value="content">
                    <strong>${T.content}</strong><span>${T.contentHint}</span>
                </button>
                <button class="a-type" value="broken">
                    <strong>${T.broken}</strong><span>${T.brokenHint}</span>
                </button>
                <button class="a-type" value="idea">
                    <strong>${T.idea}</strong><span>${T.ideaHint}</span>
                </button>
            </div>
            <form class="report" hidden>
                <!-- maxlength is the endpoint's own limit, said where
                     it can still be obeyed: the schema refuses a
                     message past 8192 characters, and a refusal after
                     the send is a wall of typing lost to a 422 about a
                     field name. -->
                <textarea name="message" required maxlength="8192"
                          placeholder="${T.message}"
                          aria-label="${T.message}"></textarea>
                <fieldset class="channels" aria-label="${T.include}"></fieldset>
                <div class="shot" hidden>
                    <div class="scope" role="radiogroup"
                         aria-label="${T.screenshot}">
                        <label class="scope-option" data-about="${T.scopeNote}" data-scope="element">
                            <input type="radio" name="scope" value="element"
                                   checked aria-label="${T.scopeElement}">
                            <svg viewBox="0 0 24 16" aria-hidden="true">
                                <rect x="1.5" y="1.5" width="21" height="13" rx="1.5"/>
                                <rect class="solid" x="8" y="6" width="8" height="4.5"/>
                            </svg>
                        </label>
                        <label class="scope-option" data-about="${T.scopeNote}" data-scope="viewport">
                            <input type="radio" name="scope" value="viewport"
                                   aria-label="${T.scopeViewport}">
                            <svg viewBox="0 0 24 16" aria-hidden="true">
                                <rect class="wash" x="1.5" y="1.5"
                                      width="21" height="13" rx="1.5"/>
                                <rect x="1.5" y="1.5" width="21" height="13" rx="1.5"/>
                            </svg>
                        </label>
                        <label class="scope-option" data-about="${T.scopeNote}" data-scope="full">
                            <input type="radio" name="scope" value="full"
                                   aria-label="${T.scopeFull}">
                            <svg viewBox="0 0 24 16" aria-hidden="true">
                                <rect class="wash dashed" x="0.75" y="0.75"
                                      width="22.5" height="14.5" rx="1.5"/>
                                <rect x="6" y="4" width="12" height="8" rx="1"/>
                            </svg>
                        </label>
                    </div>
                    <button type="button" class="a-shot">${T.capture}</button>
                    <button type="button" class="a-drop" hidden>${T.drop}</button>
                    <span class="shot-status"></span>
                    <img class="shot-preview" alt="" hidden>
                </div>
                <pre class="preview" hidden></pre>
                <div class="actions">
                    <button type="button" class="a-preview"
                            aria-expanded="false">▸ ${T.previewShort}</button>
                    <span class="total"></span>
                    <button type="button" class="a-cancel">${T.cancel}</button>
                    <button type="submit" class="a-send">${T.send}</button>
                </div>
            </form>
            <p class="result" hidden></p>
        </div>
        <div class="toast" role="status" hidden></div>
        <div class="pop" popover="manual"></div>
        <div class="text-help" hidden>
            <span><kbd>drag</kbd> ${T.helpSelectWords}</span>
            <span><kbd>↵</kbd> ${T.helpConfirmWords}</span>
            <span><kbd>e</kbd> ${T.helpPickInstead}</span>
            <span><kbd>esc</kbd> ${T.helpCancel}</span>
        </div>
        <div class="picker-help" hidden>
            <span><kbd>click</kbd> ${T.helpPick}</span>
            <span><kbd class="k-parent">↑</kbd> ${T.helpParent}</span>
            <span><kbd class="k-child">↓</kbd> ${T.helpChild}</span>
            <span><kbd class="k-sibling">←</kbd><kbd class="k-sibling">→</kbd>
                  ${T.helpSiblings}</span>
            <span><kbd>↵</kbd> ${T.helpConfirm}</span>
            <span><kbd>esc</kbd> ${T.helpCancel}</span>
        </div>
        <div class="ghost is-parent" hidden></div>
        <div class="ghost is-child" hidden></div>
        <div class="ghost is-prev" hidden></div>
        <div class="ghost is-next" hidden></div>
        <div class="region" hidden></div>
        <div class="overlay" hidden></div>
        <div class="tag" hidden></div>
    `;
    /* MoXoW emits this first in <head> and undeferred, so that the
     * listeners above are watching before anything can fail — which
     * means there is no document.body yet. Everything is built either
     * way; only the mounting waits.
     *
     * And in an XML document -- an XSLT-less feed, an SVG opened on its
     * own -- there is no <body> and there never will be one: waiting
     * for DOMContentLoaded there arrived at the same null and threw,
     * and a document that could have been reported on had no widget at
     * all. The root element is a parent like any other. The readyState
     * test is the other half of that: with the event already fired,
     * waiting for it waits forever. */
    const mount = () => {
        const parent = document.body || document.documentElement;
        if (parent) parent.append(host);
    };

    if (document.body || document.readyState !== "loading") mount();
    else addEventListener("DOMContentLoaded", mount, { once: true });

    const $ = (selector) => root.querySelector(selector);
    const panel = $(".panel");
    const menu = $(".menu");
    const form = $(".report");
    const overlay = $(".overlay");
    const tag = $(".tag");
    const result = $(".result");

    /* ---------------------------------------------------------------
     * Capture switches
     * ------------------------------------------------------------- */
    /* Same letters and hues as the report list, so what you switched on
     * here is what you recognise there. The word is the accessible name
     * and the title; the letter is the compact form. */
    const CHANNELS = [
        { key: "fragment", mark: "E", label: T.fragment,
          about: T.aboutFragment },
        { key: "rules", mark: "R", label: T.rules, about: T.aboutRules },
        { key: "computed", mark: "C", label: T.computed,
          about: T.aboutComputed },
        { key: "diagnostics", mark: "D", label: T.diagnostics,
          about: T.aboutDiagnostics },
        { key: "audit", mark: "A", label: T.audit, about: T.aboutAudit },
        { key: "screenshot", mark: "S", label: T.screenshot,
          about: T.aboutScreenshot }
    ];

    for (const c of CHANNELS) {
        const row = document.createElement("label");
        row.className = "switch";
        row.dataset.for = c.key;
        row.dataset.about = c.about;
        row.innerHTML =
            `<input type="checkbox" value="${c.key}" aria-label="${c.label}">` +
            `<span class="chip" data-channel="${c.key}">${c.label}</span>`;
        $(".channels").append(row);
    }

    /* Switch key -> where that channel actually lands in the payload. */
    const FIELD = {
        fragment: "html", rules: "rules", computed: "computed", audit: "audit"
    };

    const NEEDS_ELEMENT = ["fragment", "rules", "computed", "audit"];

    /* An idea has no element, and neither has a cancelled pick — nor a
     * region whose covered elements share no ancestor worth naming.
     * Offering to send its HTML, its rules or its contrast is offering
     * nothing: the switches go unavailable rather than quietly
     * collecting undefined. */
    const syncElementChannels = () => {
        const has = Boolean(picked);
        for (const input of root.querySelectorAll(".channels input")) {
            if (!NEEDS_ELEMENT.includes(input.value)) continue;

            input.disabled = !has;
            if (!has) input.checked = false;
            input.closest(".switch").classList.toggle("is-unavailable", !has);
        }
    };

    const enabled = () =>
        [...root.querySelectorAll(".channels input")]
            .filter((input) => input.checked)
            .map((input) => input.value);

    /* Each kind of report wants different evidence. A typo does not need
     * computed styles; a layout complaint is worthless without the rules
     * that produced it. These are only defaults — every switch stays
     * yours to change before sending. */
    const WANTED = {
        visual:  ["fragment", "rules", "computed", "diagnostics", "audit",
                  "screenshot"],
        content: ["fragment"],
        broken:  ["fragment", "diagnostics"],
        idea:    []
    };

    /* The menu says what each kind will collect, in the same letters and
     * hues as the switches below it and the report list afterwards. */
    for (const button of root.querySelectorAll(".a-type")) {
        const marks = document.createElement("span");
        marks.className = "marks";
        marks.innerHTML = (WANTED[button.value] || [])
            .map((key) => {
                const c = CHANNELS.find((entry) => entry.key === key);
                return `<span class="chip" data-channel="${key}">${c.mark}</span>`;
            }).join("");
        button.append(marks);
    }

    const applyDefaults = () => {
        const wanted = WANTED[type] || [];
        for (const input of root.querySelectorAll(".channels input")) {
            input.checked = wanted.includes(input.value);
        }
    };

    /* ---------------------------------------------------------------
     * State
     * ------------------------------------------------------------- */
    let type = null;
    let picked = null;
    let region = null;
    /* The elements holding the selected words. Reported the same way a
     * region reports what it covered, because it is the same question:
     * which elements is this about? */
    let holders = [];
    let picking = false;
    let dragFromPoint = null;
    let dragged = false;

    const build = () => {
        const on = enabled();
        const payload = {
            schema: 1,
            type,
            page: {
                url: location.href,
                title: document.title,
                site: CFG.site,
                build: CFG.build
            },
            message: form.message.value,
            environment: environment(),
            capture: Object.fromEntries(CHANNELS.map((c) => [c.key, on.includes(c.key)]))
        };

        if (picked || region) {
            const target = {};

            /* A region that covers elements with nothing in common below
             * <body> has no element to describe, and `picked` is null
             * there on purpose (see commonAncestor). The rectangle and
             * what it covered are still the report. */
            if (picked) {
                target.selector = selectorFor(picked);
                target.xpath = xpathFor(picked);
                target.fingerprint = fingerprint(picked, on.includes("fragment"));
                target.rect = rectOf(picked);
                if (on.includes("fragment")) target.html = fragmentHtml(picked);
                if (on.includes("rules")) Object.assign(target, matchedRules(picked));
                if (on.includes("computed")) target.computed = computedStyles(picked);
                if (on.includes("audit")) target.audit = auditOf(picked);
            }
            if (region) {
                /* Page coordinates, as DESIGN 5 says: a rectangle that
                 * meant something only at the scroll position it was
                 * dragged at is not a place anybody can go back to. */
                target.region = {
                    x: Math.round(region.x), y: Math.round(region.y),
                    width: Math.round(region.width),
                    height: Math.round(region.height)
                };
                target.covers = region.elements;
            } else if (holders.length > 1) {
                /* One holder is the picked element itself, and repeating
                 * it as a list of one would say nothing. */
                target.covers = holders.map((el) => selectorFor(el));
            }
            payload.target = target;
        }

        if (on.includes("screenshot") && SHOT.blob) {
            payload.screenshot = {
                scope: SHOT.scope,
                /* Where the pixels came from, said plainly, because the
                 * two paths are not equally trustworthy: the add-on's
                 * capture is asked for and delivered through the page,
                 * so a hostile page can answer in its place. The
                 * reviewer cannot detect that; they can at least be
                 * told which kind of image they are looking at (§6.2). */
                provider: SHOT.provider,
                surface: SHOT.surface,
                mapped: SHOT.scale !== null,
                /* Less than was asked for. The reviewer is looking at
                 * an image that stops somewhere, and whether it stops
                 * because the page stops is exactly the question they
                 * would otherwise have to guess at. */
                partial: SHOT.partial,
                redacted: SHOT.redacted,
                bytes: SHOT.blob.size
            };
        }

        if (on.includes("diagnostics")) {
            payload.diagnostics = {
                errors: DIAG.errors,
                resources: DIAG.resources,
                overflow: overflowReport()
            };
        }
        return payload;
    };

    const humanBytes = (size) =>
        size < 1024 ? `${size} B` : `${Math.round(size / 1024)} kB`;

    const bytes = (value) => humanBytes(new Blob([JSON.stringify(value)]).size);

    const refresh = () => {
        const payload = build();
        $(".preview").textContent = JSON.stringify(payload, null, 2);
        /* Per-channel sizes moved into the title: six numbers in a row
         * this small is noise, and the total is the number that decides
         * anything. */
        for (const c of CHANNELS) {
            const row = root.querySelector(`label[data-for="${c.key}"]`);
            const part = c.key === "screenshot"
                ? SHOT.blob
                : (c.key === "diagnostics"
                    ? payload.diagnostics
                    : payload.target?.[FIELD[c.key]]);
            const size = c.key === "screenshot"
                ? (SHOT.blob ? SHOT.blob.size : null)
                : (part === undefined
                    ? null : new Blob([JSON.stringify(part)]).size);
            row.dataset.size = size === null ? "" : humanBytes(size);
        }

        /* Asked for and not taken: the button that fixes it is lit, and
         * the one that would send an incomplete report is not available
         * until it is either taken or switched off. */
        const owed = enabled().includes("screenshot") && !SHOT.blob;
        $(".a-shot").classList.toggle("is-wanted", owed);
        const send = $(".a-send");
        send.classList.toggle("is-blocked", owed);
        send.ariaDisabled = owed ? "true" : "false";
        send.title = owed ? T.needShot : "";

        const json = new Blob([JSON.stringify(payload)]).size;
        $(".total").textContent =
            humanBytes(json + (SHOT.blob ? SHOT.blob.size : 0));
    };

    /* The page's selection is gone the moment the widget is clicked, so
     * the last real one is remembered as it happens. */
    let lastSelection = null;

    /* The words live in text nodes, and a text node's parent is the
     * element that really holds them -- so a selection spanning three
     * list items reports those three items, not the list that contains
     * them. The common ancestor is still kept as the element to open,
     * the same division of labour a region selection already makes.
     *
     * Boundary points are compared strictly, so the node the selection
     * merely touches -- the one starting exactly where it ends -- is
     * left out; and empty text nodes never count, or every scrap of
     * indentation between two tags would name its parent. */
    const selectedElements = (range) => {
        let root = range.commonAncestorContainer;
        if (root.nodeType !== 1) root = root.parentElement;
        if (!root) return [];

        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        const found = [];

        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            if (!node.textContent.trim()) continue;

            const span = document.createRange();
            span.selectNodeContents(node);
            if (range.compareBoundaryPoints(Range.END_TO_START, span) >= 0) continue;
            if (range.compareBoundaryPoints(Range.START_TO_END, span) <= 0) continue;

            const el = node.parentElement;
            if (el && !host.contains(el) && !found.includes(el)) found.push(el);
        }

        return found.slice(0, 12);
    };

    const readSelection = () => {
        const selection = getSelection();
        if (!selection || selection.isCollapsed) return null;

        const text = selection.toString().trim();
        if (!text) return null;

        const range = selection.getRangeAt(0);
        let node = range.commonAncestorContainer;
        if (node.nodeType !== 1) node = node.parentElement;
        if (!node || host.contains(node)) return null;

        return { text, element: node, elements: selectedElements(range) };
    };

    /* Stamped with the page it was made on. This listener lives as long
     * as the document does, and in a single-page application the
     * document outlives the page: words selected before a route change
     * were still sitting here afterwards, and "Text is wrong" quoted
     * them into a report about a screen they were never on -- with a
     * URL, in the same payload, saying somewhere else entirely. A
     * remembered selection is only good for the address it was made at.
     */
    document.addEventListener("selectionchange", () => {
        const found = readSelection();
        if (found) lastSelection = { ...found, url: location.href };
    });

    const remembered = () => {
        if (!lastSelection) return null;
        if (lastSelection.url === location.href) return lastSelection;

        lastSelection = null;
        return null;
    };

    /* ---------------------------------------------------------------
     * Picker
     * ------------------------------------------------------------- */
    const describe = (el) => {
        const rect = el.getBoundingClientRect();
        const classes = [...el.classList].slice(0, 2).map((c) => "." + c).join("");
        return `${el.localName}${el.id ? "#" + el.id : ""}${classes} · ` +
               `${Math.round(rect.width)}×${Math.round(rect.height)}`;
    };

    /* A relation only earns an outline if it exists, has a box, and is
     * not the widget itself. */
    const ghost = (name, target) => {
        const box = $(`.ghost.is-${name}`);
        const rect = target && !host.contains(target) &&
                     target !== document.documentElement
            ? target.getBoundingClientRect() : null;

        if (!rect || (rect.width < 1 && rect.height < 1)) {
            box.hidden = true;
            return;
        }
        Object.assign(box.style, {
            insetInlineStart: `${rect.x}px`, insetBlockStart: `${rect.y}px`,
            inlineSize: `${rect.width}px`, blockSize: `${rect.height}px`
        });
        box.hidden = false;
    };

    const hideGhosts = () => {
        for (const box of root.querySelectorAll(".ghost")) box.hidden = true;
    };

    const highlight = (el) => {
        const rect = el.getBoundingClientRect();
        const arriving = overlay.hidden;

        /* Placing and revealing in the same frame would animate from
         * wherever the box last was; flush the layout in between. */
        if (arriving) {
            overlay.classList.add("is-placing");
            tag.classList.add("is-placing");
        }

        Object.assign(overlay.style, {
            translate: `${rect.x}px ${rect.y}px`,
            inlineSize: `${rect.width}px`, blockSize: `${rect.height}px`
        });
        overlay.hidden = false;

        tag.textContent = describe(el);
        tag.style.translate =
            `${rect.x}px ${Math.max(0, rect.y - 20)}px`;
        tag.hidden = false;

        if (arriving) {
            overlay.getBoundingClientRect();
            overlay.classList.remove("is-placing");
            tag.classList.remove("is-placing");
        }

        ghost("parent", el.parentElement);
        ghost("child", el.firstElementChild);
        ghost("prev", el.previousElementSibling);
        ghost("next", el.nextElementSibling);
    };

    const regionBox = $(".region");

    /* Drawn where the pointer is, remembered where the page is: the
     * rubber band is a fixed-position box and wants client
     * coordinates, and everything that reads the region afterwards
     * wants page ones (see toClient). */
    const drawRegion = (a, b) => {
        const box = {
            x: Math.min(a.x, b.x), y: Math.min(a.y, b.y),
            width: Math.abs(a.x - b.x), height: Math.abs(a.y - b.y)
        };
        Object.assign(regionBox.style, {
            translate: `${box.x}px ${box.y}px`,
            inlineSize: `${box.width}px`, blockSize: `${box.height}px`
        });
        regionBox.hidden = false;
        return { ...box, x: box.x + scrollX, y: box.y + scrollY };
    };

    /* What the rectangle is over, so a report about an area still names
     * something a maintainer can search for. Elements wholly containing
     * the region are skipped: <body> covers every rectangle and says
     * nothing about this one. */
    const covered = (page) => {
        const box = toClient(page);

        return [...document.querySelectorAll("body *")]
            .filter((el) => {
                if (host.contains(el)) return false;

                const r = el.getBoundingClientRect();
                if (r.width < 1 || r.height < 1) return false;
                if (r.x <= box.x && r.y <= box.y &&
                    r.right >= box.x + box.width &&
                    r.bottom >= box.y + box.height) return false;

                return r.x < box.x + box.width && r.right > box.x &&
                       r.y < box.y + box.height && r.bottom > box.y;
            })
            .slice(0, 12);
    };

    /* Two answers, because they are two questions. The list is the
     * evidence — what the rectangle actually covered. The nearest common
     * ancestor is the thing to open, and giving it to the element
     * channels keeps the matched rules and computed styles meaningful
     * for an area selection instead of switching them off.
     *
     * Unless the answer is <body>, and then it is not an answer. A
     * rectangle dragged across a header and a footer, or across two
     * columns, has no ancestor below the page itself -- and adopting
     * <body> there handed the element channels the whole document: the
     * fragment channel serialised every node on the page (capped at 64
     * KB, so what arrived was the first 64 KB of the site, truncated
     * mid-tag), the rules and computed styles described <body>, and the
     * mini-audit measured the contrast of the page against itself. None
     * of that is about the rectangle somebody dragged. The covers list
     * is the evidence in that case, and it is enough. */
    const commonAncestor = (elements) => {
        if (!elements.length) return null;

        const shared = elements.reduce((a, b) => {
            let node = a;
            while (node && !node.contains(b)) node = node.parentElement;
            return node;
        });

        return !shared || shared === document.body ||
               shared === document.documentElement
            ? null : shared;
    };

    const candidate = (event) => {
        const el = document.elementFromPoint(event.clientX, event.clientY);
        return el && !host.contains(el) && el !== document.documentElement ? el : null;
    };

    const onMove = (event) => {
        if (dragFromPoint) {
            const here = { x: event.clientX, y: event.clientY };
            if (Math.abs(here.x - dragFromPoint.x) > 4 ||
                Math.abs(here.y - dragFromPoint.y) > 4) {
                dragged = true;
                overlay.hidden = true;
                tag.hidden = true;
                hideGhosts();
                region = drawRegion(dragFromPoint, here);
            }
            return;
        }

        const el = candidate(event);
        if (el) { picked = el; highlight(el); }
    };

    const onDown = (event) => {
        dragFromPoint = { x: event.clientX, y: event.clientY };
        dragged = false;
    };

    const onUp = () => {
        dragFromPoint = null;
        if (!dragged) return;

        const inside = covered(region);
        region.elements = inside.map((el) => selectorFor(el));
        picked = commonAncestor(inside);
        stopPicking(true);
    };

    const onClick = (event) => {
        event.preventDefault();
        event.stopPropagation();
        if (dragged) return;      /* the drag already decided */

        const el = candidate(event);
        if (el) picked = el;
        stopPicking(true);
    };

    /* Up and down the tree, because the element worth reporting is
     * usually the container, not the leaf the mouse can reach. */
    const onKey = (event) => {
        /* Stop the event here: the panel's own Escape handler is on the
         * same window and would close the whole widget straight after
         * this one reopened its menu. */
        if (event.key === "Escape") {
            event.preventDefault();
            event.stopPropagation();
            stopPicking(false);
            return;
        }
        if (!picked) return;
        const moves = {
            ArrowUp: () => picked.parentElement,
            ArrowDown: () => picked.firstElementChild,
            ArrowLeft: () => picked.previousElementSibling,
            ArrowRight: () => picked.nextElementSibling
        };
        if (event.key === "Enter") { event.preventDefault(); stopPicking(true); return; }
        const next = moves[event.key]?.();
        if (!next || host.contains(next) || next === document.documentElement) return;
        event.preventDefault();
        picked = next;
        highlight(next);
    };

    /* The cursor belongs to the page, and the page says "hand" over a
     * link and "text" over a paragraph — neither of which is what you
     * are doing. So a rule goes into the document, and comes back out
     * the moment picking ends. It is not the only thing the widget
     * writes there — holdDraggables marks every link and image
     * undraggable for the length of a selection, and a capture hides
     * the host while the shutter is open — but all of it is borrowed
     * for the length of a gesture and given back after it.
     *
     * !important because it has to beat whatever the site sets, and a
     * lone rule on documentElement would not: every element with its own
     * cursor would keep it. */
    let cursorRule = null;

    /* Picking wants the selection out of the way; selecting words wants
     * it back, and wants it even where the page turned it off — a typo
     * in unselectable text is still a typo. */
    const RULES = {
        pick: "*, *::before, *::after { cursor: crosshair !important; " +
              "user-select: none !important; -webkit-user-drag: none !important; }",
        /* -webkit-user-drag as well: the words worth reporting are often
         * inside a link — a card, a thumbnail caption, a menu item — and
         * a link drags before it selects. */
        text: "*, *::before, *::after { cursor: text !important; " +
              "user-select: text !important; -webkit-user-select: text !important; " +
              "-webkit-user-drag: none !important; }"
    };

    /* Firefox decides at mousedown whether a gesture is a link drag, and
     * once it has decided, nothing gives the selection back: measured on
     * the real page, cancelling dragstart stops the drag and still leaves
     * the selection empty, while -webkit-user-drag is ignored outright.
     * Only the draggable ATTRIBUTE, set before the gesture begins, makes
     * words inside a link selectable there -- and links are exactly where
     * the words worth reporting tend to live: cards, captions, menus.
     *
     * Restored to what the page had, attribute by attribute, so a page
     * that deliberately marks something draggable keeps it. */
    let undraggable = [];

    const holdDraggables = () => {
        undraggable = [...document.querySelectorAll("a[href], img, [draggable]")]
            .map((el) => {
                const was = el.getAttribute("draggable");
                el.setAttribute("draggable", "false");
                return [el, was];
            });
    };

    const releaseDraggables = () => {
        undraggable.forEach(([el, was]) => {
            if (was === null) el.removeAttribute("draggable");
            else el.setAttribute("draggable", was);
        });
        undraggable = [];
    };

    /* An XML document has no <head>, and appending to null throws --
     * out of the first line of startPicking, before a single listener
     * was attached. `picking` stayed true, the panel stayed hidden, and
     * Escape went to the handler that ignores keys while picking: a
     * widget that could not be cancelled or closed, on the one kind of
     * page it had nothing else wrong with.
     *
     * Two answers, because the cursor is decoration and the mode is
     * not. The rule goes on the root element where there is no head,
     * and if the document will not take it at all the picker runs
     * anyway with the page's own cursors -- less pleasant, and still a
     * picker. Nothing here is allowed to throw. */
    const takeCursor = (mode) => {
        try {
            cursorRule = document.createElement("style");
            cursorRule.dataset.corrigenda = "cursor";
            cursorRule.textContent = RULES[mode];
            (document.head || document.documentElement).append(cursorRule);
            holdDraggables();
            return true;
        } catch (error) {
            console.warn("corrigenda: this document would not take the " +
                         "picker's cursor rule; picking without it", error);
            /* Whatever half of it landed goes back the same way the end
             * of picking would put it back. */
            releaseCursor();
            return false;
        }
    };

    const releaseCursor = () => {
        cursorRule?.remove();
        cursorRule = null;
        releaseDraggables();
    };

    /* Content is about words, so it selects words. The element picker
     * would ask the reporter to find the box that holds the typo, which
     * is a question about the DOM and not about the sentence.
     *
     * Not selectable? Two answers. The injected rule turns selection
     * back on even where the page disabled it, and where there is
     * genuinely no text to select -- an image, a canvas, an icon font --
     * "e" hands over to the element picker, which is what such a report
     * needed all along. */
    let selecting = false;

    /* Images and links are draggable by default, so a drag begun on one
     * starts the browser's own drag: the rubber band never gets its move
     * events, and a selection never starts. Both modes need this.
     * -webkit-user-drag covers Chrome; this covers everything. */
    const onDragStart = (event) => {
        event.preventDefault();
        event.stopPropagation();
    };

    /* `gesture` says the mode ended on a pointer, which is the only
     * case with a trailing click to swallow -- see stopSelecting. */
    const finishText = (found, gesture = false) => {
        /* Consumed: a later report must not silently quote the words
         * from this one because they were still remembered. */
        lastSelection = null;
        picked = found.element;
        holders = found.elements || [];
        form.message.value = `« ${found.text} » `;
        stopSelecting(gesture);
        panel.hidden = false;
        showForm();
    };

    const onSelectUp = () => {
        const found = readSelection();
        if (found) finishText(found, true);
    };

    const onSelectKey = (event) => {
        if (event.key === "Escape") {
            event.preventDefault();
            event.stopPropagation();
            stopSelecting();
            openPanel(false);
            return;
        }

        if (event.key === "Enter") {
            event.preventDefault();
            event.stopPropagation();
            const found = readSelection() || remembered();
            if (found) finishText(found);
            return;
        }

        /* The way out when there is nothing to select. */
        if (event.key === "e" || event.key === "E") {
            event.preventDefault();
            event.stopPropagation();
            stopSelecting();
            startPicking();
        }
    };

    /* A click inside a link would navigate, taking the page and the
     * report with it. Selection does not need the click, only the
     * mousedown/move/up before it, so swallowing it costs nothing. */
    const onSelectClick = (event) => {
        event.preventDefault();
        event.stopPropagation();
    };

    /* mouseup and pointerup both land before the click they belong to,
     * so tearing the guard down there lets that click through — and on
     * a link that means navigating away with the report half written.
     * One more click is swallowed after either mode ends.
     *
     * Released by an event, never by a timer: a timer races the very
     * click it is meant to catch, and loses whenever the browser takes
     * longer than the timeout to dispatch it. The guard stands until
     * either that click arrives, or a new gesture begins — and a new
     * gesture means the trailing click is never coming. */
    const swallowNextClick = () => {
        const release = () => {
            removeEventListener("click", swallow, true);
            removeEventListener("pointerdown", release, true);
        };

        function swallow(event) {
            event.preventDefault();
            event.stopPropagation();
            release();
        }

        addEventListener("click", swallow, true);
        addEventListener("pointerdown", release, true);
    };

    const startSelecting = () => {
        selecting = true;
        takeCursor("text");
        $(".launcher").hidden = true;
        panel.hidden = true;
        $(".text-help").hidden = false;
        addEventListener("mouseup", onSelectUp, true);
        addEventListener("keydown", onSelectKey, true);
        addEventListener("dragstart", onDragStart, true);
        addEventListener("click", onSelectClick, true);
    };

    /* The guard stopPicking has always had, and this one lacked. A
     * click only trails a gesture that used the pointer: leaving text
     * mode with Enter, with Escape, with "e", or never entering it at
     * all -- the path where words were already selected before the
     * report was opened -- has no click coming, and the guard sat there
     * waiting for one. What it caught instead was the next click
     * somebody made, or the Enter that fires one on a focused button:
     * the first press after a keyboard text report did nothing at all.
     */
    function stopSelecting(gesture) {
        selecting = false;
        releaseCursor();
        $(".text-help").hidden = true;
        removeEventListener("mouseup", onSelectUp, true);
        removeEventListener("keydown", onSelectKey, true);
        removeEventListener("dragstart", onDragStart, true);
        removeEventListener("click", onSelectClick, true);
        if (gesture) swallowNextClick();
    }

    const startPicking = () => {
        picking = true;
        takeCursor("pick");
        $(".launcher").hidden = true;
        panel.hidden = true;
        $(".picker-help").hidden = false;
        addEventListener("mousemove", onMove, true);
        addEventListener("pointerdown", onDown, true);
        addEventListener("dragstart", onDragStart, true);
        addEventListener("pointerup", onUp, true);
        addEventListener("click", onClick, true);
        addEventListener("keydown", onKey, true);
    };

    function stopPicking(keep) {
        picking = false;
        releaseCursor();
        $(".picker-help").hidden = true;
        removeEventListener("mousemove", onMove, true);
        removeEventListener("pointerdown", onDown, true);
        removeEventListener("dragstart", onDragStart, true);
        removeEventListener("pointerup", onUp, true);
        removeEventListener("click", onClick, true);
        removeEventListener("keydown", onKey, true);
        regionBox.hidden = true;
        dragFromPoint = null;
        if (dragged) swallowNextClick();
        overlay.hidden = true;
        tag.hidden = true;
        hideGhosts();
        panel.hidden = false;

        /* Cancelled: back to the menu it was started from. Landing on
         * the form with nothing picked offers to send a report about
         * an element the reporter just declined to choose. */
        if (!keep) {
            picked = null;
            region = null;
            holders = [];
            openPanel(false);
            return;
        }

        showForm();
    }

    /* ---------------------------------------------------------------
     * Dragging. The PANEL moves, never the host: the host also holds
     * the picker overlay, and a transformed ancestor makes its fixed
     * children position against the transform instead of the viewport,
     * which would slide the highlight off whatever it is highlighting.
     *
     * Kept in a variable rather than storage, so the widget still leaves
     * nothing behind on the page it was used on.
     * ------------------------------------------------------------- */
    let offset = { x: 0, y: 0 };
    let dragFrom = null;

    const place = () => {
        panel.style.translate = `${offset.x}px ${offset.y}px`;
    };

    /* The whole window stays visible, not just a corner of it. It is not
     * only dragging that moves an edge past the viewport: the window
     * grows when a screenshot thumbnail lands, when a warning appears,
     * when a hint runs long -- and a window that grew off the bottom
     * hides the very buttons that would send the report.
     *
     * Bottom and right are corrected before top and left, so a window
     * taller than the viewport loses its foot rather than its header:
     * the header is what drags, and what closes. */
    const keepOnScreen = () => {
        if (panel.hidden) return;

        const box = panel.getBoundingClientRect();
        if (!box.width) return;

        const edge = 12;
        let { top, left } = box;

        if (top + box.height > innerHeight - edge) {
            top = innerHeight - edge - box.height;
        }
        if (left + box.width > innerWidth - edge) {
            left = innerWidth - edge - box.width;
        }
        top = Math.max(top, edge);
        left = Math.max(left, edge);

        offset.x += left - box.left;
        offset.y += top - box.top;
        place();
    };

    const header = root.querySelector("header");

    header.addEventListener("pointerdown", (event) => {
        if (event.target.closest("button")) return;

        dragFrom = { x: event.clientX - offset.x, y: event.clientY - offset.y };
        header.setPointerCapture(event.pointerId);
        /* The panel eases its translate, and getBoundingClientRect
         * reports the animating value rather than the target one -- so a
         * clamp measured mid-transition works from where the window used
         * to be, and a fast drag escapes the viewport. Measured in
         * Firefox. The ease is for a window arriving somewhere; a window
         * under the pointer is already where it should be. */
        panel.classList.add("is-dragging");
        event.preventDefault();
    });

    header.addEventListener("pointermove", (event) => {
        if (!dragFrom) return;

        offset = { x: event.clientX - dragFrom.x, y: event.clientY - dragFrom.y };
        /* Applied before it is measured. keepOnScreen corrects the panel
         * from its own rect, and a rect read before place() describes
         * where the window WAS -- so the correction lands one move
         * behind and a fast drag walks straight off the screen.
         * Measured in Firefox, where the events arrive in bigger steps.
         *
         * Clamped as it moves, not once it is dropped: the window should
         * stop at the edge under the pointer, not spring back from it.
         * No drift -- the next move recomputes the offset from the
         * pointer, so the clamp never accumulates. */
        place();
        keepOnScreen();
    });

    const endDrag = () => {
        if (!dragFrom) return;

        dragFrom = null;
        panel.classList.remove("is-dragging");
        keepOnScreen();
    };

    header.addEventListener("pointerup", endDrag);
    header.addEventListener("pointercancel", endDrag);

    /* A pointer released outside the window does not always give its
     * pointerup back to the element that captured it, and a drag that
     * never ends is a window that never gets its final clamp. Both of
     * these say the same thing twice, on purpose. */
    header.addEventListener("lostpointercapture", endDrag);
    addEventListener("pointerup", endDrag, true);
    addEventListener("resize", keepOnScreen);

    /* Content decides the height, so content has to be watched: the form
     * replacing the menu, a screenshot arriving, a warning box opening.
     * Only the translate changes here, so this cannot feed itself. */
    new ResizeObserver(keepOnScreen).observe(panel);

    /* ---------------------------------------------------------------
     * Panel flow
     * ------------------------------------------------------------- */
    /* The title bar carries the report instead of announcing itself: a
     * heading that reads "Report a page defect" tells the reporter what
     * they already knew when they opened it, and cost a row that the
     * target then cost again. Long targets are clipped to one line and
     * the whole thing is on the title, which the header already needs
     * for nothing else. */
    const showTarget = () => {
        const target = $(".target");
        let line = T[type] || T.title;

        if (picked) line += ` · ${describe(picked)}`;
        if (region) {
            line += ` · ${T.regionCovers} ${region.elements.length}`;
        } else if (holders.length > 1) {
            line += ` · ${T.across} ${holders.length} ${T.elements}`;
        }

        target.textContent = line;
        target.title = line;
        target.classList.add("is-report");
    };

    const showForm = () => {
        menu.hidden = true;
        form.hidden = false;
        showTarget();
        syncElementChannels();
        syncShot();
        showScope();
        refresh();
        form.message.focus();
    };

    /* -------------------------------------------------------------
     * The toast. It says one thing, once, after the window has gone.
     * ------------------------------------------------------------- */
    const toast = $(".toast");
    let toastTimer = null;

    /* Long enough to read a reference number, short enough that it is
     * gone before it is in the way. The pointer holds it for anyone
     * who wants to copy the number. */
    const LINGER = 4000;

    const dismiss = () => {
        clearTimeout(toastTimer);
        toastTimer = null;
        toast.hidden = true;
        toast.classList.remove("is-leaving");
    };

    /* With motion turned off there is no fade to end, so the timer has
     * to remove it itself; otherwise the toast would sit there for good.
     */
    const still = matchMedia("(prefers-reduced-motion: reduce)");

    const linger = () => {
        clearTimeout(toastTimer);
        toastTimer = setTimeout(
            () => (still.matches ? dismiss()
                                 : toast.classList.add("is-leaving")),
            LINGER);
    };

    /* A live region has to be live before the words land in it. Written
     * while the box was still display:none and unhidden afterwards, the
     * text was already there when the region appeared -- and a
     * role="status" announces a CHANGE, so a screen reader had nothing
     * to announce and the one thing this widget says out loud, the
     * reference number, was said to nobody. Empty and visible first,
     * worded on the next frame. */
    const notify = (text) => {
        toast.classList.remove("is-leaving");
        toast.textContent = "";
        toast.hidden = false;
        requestAnimationFrame(() => {
            /* Dismissed inside that frame -- a click, or the next
             * report -- and these words belong to nothing. */
            if (toast.hidden) return;

            toast.textContent = text;
        });
        linger();
    };

    /* The animation is what ends it, not a second timer: a toast the
     * pointer rested on has had its timer restarted, and only the
     * animation it actually finished should remove it. */
    toast.addEventListener("animationend", (event) => {
        if (event.animationName === "toast-out") dismiss();
    });
    toast.addEventListener("click", dismiss);
    toast.addEventListener("pointerenter", () => {
        clearTimeout(toastTimer);
        toast.classList.remove("is-leaving");
    });
    toast.addEventListener("pointerleave", linger);

    /* moveFocus is false when the widget opens itself: taking focus from
     * whatever the page had is rude, and nobody asked for it by clicking. */
    const openPanel = (moveFocus = true) => {
        dismiss();
        /* The launcher is the way back in, so it has nothing to say
         * while you are already in. */
        $(".launcher").hidden = true;
        panel.hidden = false;
        menu.hidden = false;
        form.hidden = true;
        result.hidden = true;
        const target = $(".target");
        target.textContent = T.title;
        target.title = "";
        target.classList.remove("is-report");

        /* Nothing to choose here, so the menu goes and the reason
         * stays. This is a fact about the page, not about the report,
         * and it is known before a word is typed -- said afterwards, by
         * the endpoint, it costs a whole message and comes back as a
         * schema error about page.url. */
        if (!REPORTABLE) {
            menu.hidden = true;
            result.textContent = T.notReportable;
            result.classList.add("is-error");
            result.hidden = false;
        }

        if (moveFocus) root.querySelector(".a-close").focus();
    };

    const closePanel = () => {
        $(".launcher").hidden = false;
        panel.hidden = true;
        picked = null;
        region = null;
        holders = [];
        type = null;
        /* Dismissed is dismissed. Three things used to survive it and
         * each of them made the next report a little bit the last one's:
         * a selection made before this report was opened, still ready to
         * be quoted into the next one; `refused`, which meant one press
         * of Remove switched off automatic capture for the rest of the
         * page's life, though its own comment promised "opening the next
         * report is a fresh ask"; and `shotError`, which held the scope
         * line hostage to a failure nobody could see any more. */
        lastSelection = null;
        refused = false;
        shotError = null;
        clearShot();
        form.reset();
        /* SHOT.scope is not a form control, so form.reset() put the
         * radios back to the markup's default and left the scope on
         * whatever the last report chose: the next one showed "element"
         * and cropped the whole surface. The radio is the part somebody
         * can see, so the radio decides -- and syncScopes then takes the
         * crops away again if this browser cannot do them, which is the
         * other half of keeping the two in step. */
        SHOT.scope = root.querySelector(".scope input:checked")?.value ||
                     DEFAULT_SCOPE;
        syncScopes();
        showScope();
        $(".launcher").focus();
    };

    root.querySelector(".a-open").addEventListener("click", () => openPanel());
    root.querySelector(".a-close").addEventListener("click", closePanel);
    root.querySelector(".a-cancel").addEventListener("click", closePanel);

    /* DESIGN 9 promises focus trapped in the panel and restored on
     * close, and only the second half was ever built: Tab off the Send
     * button landed in the page underneath, which is the page being
     * reported on -- a link there navigates, and the half-written
     * report goes with it. This is a dialog, and a dialog keeps what it
     * was given until it hands it back.
     *
     * The stops are counted on every keypress rather than at open time:
     * the menu becomes a form, a capture grows a Remove button, the
     * scopes go disabled when no add-on answers. A list taken once is
     * wrong by the second Tab.
     *
     * Restoring to the launcher on close stays as it is, and is not the
     * usual "return it to whatever had it": the launcher is this
     * widget's own anchor and the way back in, and it is where the
     * reporter was before they opened this. */
    const focusables = () =>
        [...panel.querySelectorAll(
            "button, [href], input, select, textarea, [tabindex]")]
            .filter((el) => !el.disabled && el.tabIndex >= 0 &&
                            !el.closest("[hidden]") &&
                            el.getClientRects().length);

    panel.addEventListener("keydown", (event) => {
        if (event.key !== "Tab") return;

        const stops = focusables();
        if (!stops.length) return;

        /* Inside a shadow root the focused node is the ROOT's
         * activeElement; document.activeElement only ever says "the
         * host element", which is true and useless. */
        const here = root.activeElement;
        const first = stops[0];
        const last = stops.at(-1);

        if (event.shiftKey ? here === first : here === last) {
            event.preventDefault();
            (event.shiftKey ? last : first).focus();
        }
    });

    for (const button of root.querySelectorAll(".a-type")) {
        button.addEventListener("click", () => {
            type = button.value;
            applyDefaults();

            if (type === "idea") { showForm(); return; }

            /* Text already selected needs no mode at all. */
            const already = type === "content" ? remembered() : null;
            if (already) {
                finishText(already);
                return;
            }

            if (type === "content") { startSelecting(); return; }

            startPicking();
        });
    }

    const shotStatus = $(".shot-status");
    const shotPreview = $(".shot-preview");

    function clearShot() {
        /* Whatever is still being encoded belongs to the report this
         * clears, and must not arrive in the next one. */
        shotAge += 1;
        SHOT.blob = null;
        SHOT.scale = null;
        SHOT.redacted = 0;
        SHOT.partial = false;
        SHOT.provider = null;
        /* The capture that was in flight will not reach its own finally
         * -- it is stale by the time it lands -- so the button is given
         * back here, where nothing is happening by definition. */
        $(".a-shot").disabled = false;
        shotStatus.textContent = "";
        shotStatus.classList.remove("is-warning");
        shotPreview.hidden = true;
        if (shotPreview.src) URL.revokeObjectURL(shotPreview.src);
        shotPreview.removeAttribute("src");
        $(".a-drop").hidden = true;
        $(".a-shot").textContent = T.capture;
    }

    /* Why the add-on's own capture failed, when it did and the share
     * dialog was reached instead. Held apart from the dialog's own
     * error because they are different questions and only one of them
     * is worth reporting. */
    let bridgeError = null;

    /* Taken by the button, and taken without one when the add-on is
     * there. Same routine either way: what differs is who asked. */
    const takeShot = async () => {
        const button = $(".a-shot");
        /* Which report this picture is for. Everything below runs after
         * an await, so nothing it touches may be touched at all once the
         * number has moved. */
        const mine = shotAge;
        /* Decided before the failure path clears the shot, which moves
         * the number itself: what the finally must know is whether this
         * capture was still wanted when it landed, not what clearing it
         * did afterwards. */
        let live = true;
        button.disabled = true;
        shotError = null;
        bridgeError = null;
        shotStatus.textContent = "…";
        try {
            const { mapped, stale } = await capture(mine);
            if (stale) { live = false; return; }
            if (!SHOT.blob) { shotStatus.textContent = T.shotBig; return; }
            /* Capture again, and again, and the blob behind every
             * previous thumbnail is still held: an object URL keeps its
             * blob alive until it is revoked, and a two-megabyte WebP
             * per press adds up on a page nobody reloads. Remove does
             * this through clearShot; recapture never did. */
            if (shotPreview.src) URL.revokeObjectURL(shotPreview.src);
            shotPreview.src = URL.createObjectURL(SHOT.blob);
            shotPreview.hidden = false;
            $(".a-drop").hidden = false;
            button.textContent = T.recapture;
            const surface = SHOT.surface
                ? (SURFACES[SHOT.surface] || (() => T.surfaceUnknown))()
                : null;
            shotStatus.classList.toggle("is-warning", !mapped);
            /* In words, not a glyph: "0 ▮" had to be asked about, and a
             * status line is not where anyone should need a legend. Zero
             * is the page's own fact -- nothing there wanted covering --
             * so it gets a sentence rather than a count of nothing. */
            const masked = SHOT.redacted === 0
                ? T.maskNone
                : `${SHOT.redacted} ` +
                  (SHOT.redacted === 1 ? T.maskOne : T.maskMany);
            shotStatus.textContent = mapped
                ? `${T.shotReady}${surface ? ` · ${surface}` : ""} · ` +
                  `${humanBytes(SHOT.blob.size)} · ${masked}` +
                  `${SHOT.partial ? ` · ${T.shotViewportOnly}` : ""}`
                : `${surface ? `${surface} — ` : ""}${T.shotUnmapped}`;
        } catch (error) {
            /* Failed for a report nobody is looking at any more: the
             * console still gets it, the panel is not told about a
             * capture it never asked for. */
            if (mine !== shotAge) {
                live = false;
                console.warn("corrigenda: a dismissed capture failed", error);
                return;
            }

            /* Said, not swallowed. This used to be a bare `catch` and a
             * fixed sentence, which meant a capture that failed for a
             * reason the browser had explained arrived as "no
             * screenshot" and nothing else -- to the one person in a
             * position to report it. The console line carries the whole
             * error; the panel carries as much of it as a line can. */
            console.warn("corrigenda: capture failed", error);

            /* A cancelled share dialog is not a fault and its
             * DOMException says nothing a reader can use -- "not
             * allowed by the user agent in the current context" is the
             * browser's way of saying somebody pressed Cancel. Ours
             * says that in words. Anything else is unexpected enough to
             * be worth quoting.
             *
             * What is worth adding either way is why the add-on did not
             * take the picture, since reaching this dialog at all means
             * it did not. */
            const expected = error?.name === "NotAllowedError" ||
                             error?.name === "AbortError";
            const why = expected
                ? ""
                : String(error?.message || error || "").trim();

            clearShot();
            shotError = [
                T.shotDenied,
                why && `— ${why.slice(0, 80)}`,
                bridgeError && `· ${T.helperFailed} ${bridgeError.slice(0, 80)}`
            ].filter(Boolean).join(" ");
            shotStatus.textContent = shotError;
        } finally {
            if (live) {
                button.disabled = false;
                refresh();
            }
        }
    };

    /* With the add-on there is no dialog to answer and no surface to
     * pick: the picture is taken in a few milliseconds, of the element
     * already chosen. Asking for a button press on top of that is asking
     * someone to confirm the screenshot they just switched on.
     *
     * Without it, the button stays. getDisplayMedia raises a share
     * dialog, and a page that raises one nobody asked for is a page
     * whose next permission gets refused out of habit.
     *
     * `refused` is what makes the remove button mean something: taken
     * away by hand, a shot is not silently taken again. Switching the
     * channel off and on, or opening the next report, is a fresh ask.
     */
    let refused = false;

    const autoShot = () => {
        if (refused || SHOT.blob) return;
        /* Not "an add-on is installed" but "the add-on answered here".
         * On the strength of the marker alone this would raise the
         * browser's share dialog, unasked, on every page where the
         * add-on is present but the site was never granted. */
        if (helperAnswers !== true) return;
        if (provider() !== PROVIDERS.extension) return;
        if (!enabled().includes("screenshot")) return;

        takeShot();
    };

    const syncShot = () => {
        const wanted = enabled().includes("screenshot");
        $(".shot").hidden = !wanted;

        if (!wanted) {
            clearShot();
            /* Switched off and on is a fresh question, so last time's
               answer goes with it. */
            shotError = null;
            refused = false;
            return;
        }

        syncScopes();

        /* Asked here rather than once at load: an add-on can be
         * installed, granted, revoked or updated while the page is open,
         * and this is the moment its answer matters. */
        askHelper().then(() => {
            syncScopes();
            autoShot();
        });
    };

    /* A native title is slow to appear, cannot be styled and never shows
     * on focus. One popover, moved to whichever switch is under the
     * pointer or the caret. */
    const pop = $(".pop");

    /* showPopover on an open popover throws InvalidStateError, and so
     * does hidePopover on a closed one -- and the throw does not stop
     * at the popover: it comes out of the middle of the handler that
     * called it, so everything that handler had left to do never
     * happened. Hover and focus interleave freely here (pointer onto a
     * switch the caret is already on, tab away from a switch the
     * pointer is still over) and both edges arrive twice or in the
     * wrong order. Asking the element what state it is in costs
     * nothing and is the only thing that survives every ordering. */
    const hidePop = () => {
        if (pop.matches(":popover-open")) pop.hidePopover();
    };

    const showPop = (element, text) => {
        pop.textContent = text;
        if (!pop.matches(":popover-open")) pop.showPopover();

        const anchor = element.getBoundingClientRect();
        const box = pop.getBoundingClientRect();
        const x = Math.min(Math.max(8, anchor.x + anchor.width / 2 - box.width / 2),
                           innerWidth - box.width - 8);

        /* Below the thing it explains, where it covers what comes next
         * rather than the message you are still typing. Above only when
         * there is no room below. */
        const below = anchor.bottom + 6;
        const y = below + box.height <= innerHeight - 8
            ? below
            : Math.max(8, anchor.y - box.height - 6);
        pop.style.translate = `${x}px ${y}px`;
    };

    const describeSwitch = (row) => {
        const size = row.dataset.size;
        showPop(row, `${row.querySelector("input").ariaLabel} — ` +
                     `${row.dataset.about}${size ? ` · ${size}` : ""}`);
    };

    /* The header warning is hidden until the browser proves it cannot
     * crop, and then it is the only place that says so. */
    const warnButton = root.querySelector(".a-warn");

    for (const event of ["pointerenter", "focusin"]) {
        warnButton.addEventListener(event,
                                    () => showPop(warnButton, warnButton.dataset.about));
    }

    for (const event of ["pointerleave", "focusout"]) {
        warnButton.addEventListener(event, hidePop);
    }

    for (const event of ["pointerenter", "focusin"]) {
        form.addEventListener(event, (e) => {
            const row = e.target.closest(".switch, .scope-option");
            if (row) describeSwitch(row);
        }, true);
    }

    for (const event of ["pointerleave", "focusout"]) {
        form.addEventListener(event, (e) => {
            if (e.target.closest?.(".switch, .scope-option")) hidePop();
        }, true);
    }

    root.querySelector(".channels").addEventListener("change", () => {
        syncShot();
        refresh();
    });

    const SCOPE_NAMES = {
        element: T.scopeElement, viewport: T.scopeViewport, full: T.scopeFull
    };

    /* The chosen scope has no line of its own any more, so it says its
     * name where the status will be anyway -- and steps aside the moment
     * there is a real result to report. */
    /* The scope a report starts on, and the one it returns to when the
     * widget has had to leave it. */
    const DEFAULT_SCOPE = "element";
    let scopeForced = false;

    /* What went wrong last time, if anything, held until something
     * happens that could put it right. Without this the message lasted
     * as long as it took the next redraw to run -- and the redraw that
     * follows a late answer from the add-on is exactly the one that
     * follows a failed capture, so the reason was written and wiped
     * inside the same second and the reader saw nothing at all. */
    let shotError = null;

    const showScope = () => {
        if (SHOT.blob || shotError) return;

        shotStatus.textContent = SCOPE_NAMES[SHOT.scope];
    };

    /* Offering a crop this browser cannot perform is a promise it will
     * break at capture time, so the two cropping scopes are taken away
     * rather than left to fail -- and given back the moment an add-on
     * makes them real. */
    /* What is running, under the title. Two builds and no prose.
     *
     * The add-on's build is not the widget's: it is installed rather
     * than served, so the two move separately and a report that came
     * out oddly is usually a question about which pair was in play.
     */
    /* And where it goes, when that is somewhere else. The endpoint is
     * the page's to choose -- data-endpoint on the tag, or a
     * link[rel=corrigenda] the page carries -- and the POST goes out
     * with credentials, so a page can address the report, and the
     * reporter's session, at an origin they never picked. Nothing in a
     * script can fix that: the widget is a guest and the page is the
     * host. What it can do is stop being quiet about it, in the line
     * that already says what is running. Same origin says nothing,
     * because there is nothing there to say. */
    const sayWhatIsRunning = () => {
        const helper = helperVersion
            ? `add-on ${helperVersion}`
            : (extension() ? T.helperSilent : T.helperNone);
        const colophon = $(".colophon");

        colophon.textContent = `corrigenda ${VERSION} · ${helper}`;
        if (!CROSS_ORIGIN) return;

        /* Its own line, whole or not at all: an origin is one word,
         * and riding the version line it either wrapped mid-hostname
         * or pushed the line to three. The ellipsis cuts it when the
         * panel is narrower than the name; the title keeps it entire. */
        const where = document.createElement("span");
        where.className = "destination";
        where.textContent = `→ ${ENDPOINT.origin}`;
        where.title = ENDPOINT.origin;
        colophon.append(where);
    };

    const syncScopes = () => {
        const able = tabCapture();
        sayWhatIsRunning();

        for (const input of root.querySelectorAll(".scope input")) {
            const off = !able && input.value !== "full";
            input.disabled = off;
            if (off) input.checked = false;
            input.closest(".scope-option").classList
                 .toggle("is-unavailable", off);
        }

        /* "full" is sometimes a choice and sometimes all that is left,
         * and only the second is undone. Cropping to the element is the
         * default because it is what a report is usually about; when it
         * is taken away -- no add-on, or one that has not answered yet
         * -- the scope falls back, and when it comes back, so does the
         * default. Somebody who picked "no crop" while it was theirs to
         * pick keeps it: scopeForced is only set where the widget
         * overrode a choice rather than followed one. */
        if (!able) {
            if (SHOT.scope !== "full") scopeForced = true;
            SHOT.scope = "full";
            root.querySelector(".scope input[value=full]").checked = true;
        } else if (scopeForced) {
            scopeForced = false;
            SHOT.scope = DEFAULT_SCOPE;
            root.querySelector(`.scope input[value=${DEFAULT_SCOPE}]`)
                .checked = true;
            showScope();
        }

        /* Said once, in the header, where it belongs: it is a fact
         * about the browser and not about this report, and as a
         * permanent paragraph it re-explained itself on every
         * screenshot anyone ever took here. */
        /* No marker means one of two things and a page cannot tell
         * which: the bridge is registered only for origins the add-on
         * has been granted, so "installed but not allowed here" and
         * "not installed" are the same silence -- and Firefox means it,
         * since its extension UUID is per profile and nothing can probe
         * for a resource either. That message names both remedies.
         *
         * A marker present says which contract the bridge speaks, and
         * those two cases differ: too old to talk to, or running with
         * the permission revoked under it. Read raw rather than through
         * extension(), which answers null for the first -- the very
         * case that wants its own sentence. */
        const marked = Number(
            document.documentElement.dataset.corrigendaCapture);
        const warn = $(".a-warn");

        let about = T.noTabCapture;
        if (Number.isFinite(marked) && marked > 0) {
            about = marked < HELPER_REQUIRED ? T.helperOutdated
                                             : T.helperNotHere;
        }

        warn.hidden = able;
        warn.dataset.about = about;
        warn.setAttribute("aria-label", about);
    };

    syncScopes();
    askHelper().then(() => syncScopes());
    helperArrived = syncScopes;

    /* The crop and the redaction happen at capture time, so a new scope
     * needs a new capture rather than silently keeping the old image. */
    $(".scope").addEventListener("change", (event) => {
        /* Chosen, so nothing here gets to change it back. */
        scopeForced = false;
        shotError = null;
        SHOT.scope = event.target.value;
        clearShot();
        showScope();
        refresh();
        /* Choosing a scope is asking for a picture of it, so a scope
         * changed after a removal counts as asking again. */
        refused = false;
        autoShot();
    });

    showScope();


    $(".a-shot").addEventListener("click", takeShot);


    $(".a-drop").addEventListener("click", () => {
        refused = true;
        clearShot();
        showScope();
        refresh();
    });

    /* A <details> summary is a row whether or not it is open. As a
     * button in the footer it costs nothing until it is wanted. */
    root.querySelector(".a-preview").addEventListener("click", (event) => {
        const pre = $(".preview");
        pre.hidden = !pre.hidden;
        event.target.setAttribute("aria-expanded", String(!pre.hidden));
        /* The payload opens above this button, not below it, so the open
         * caret points up at what it opened. */
        event.target.textContent = `${pre.hidden ? "▸" : "▴"} ${T.previewShort}`;
    });

    /* A variable, not form.dataset.timer: a timer id is not markup, and
     * kept there it was written into the form as an attribute and read
     * back out as a string for clearTimeout to coerce again. */
    let messageTimer = null;

    form.message.addEventListener("input", () => {
        clearTimeout(messageTimer);
        messageTimer = setTimeout(refresh, 250);
    });

    addEventListener("keydown", (event) => {
        if (event.key === "Escape" && !picking && !selecting && !panel.hidden) {
            closePanel();
        }
    });

    /* ---------------------------------------------------------------
     * Transport
     * ------------------------------------------------------------- */
    const gzip = async (text) => {
        const stream = new Blob([text]).stream()
            .pipeThrough(new CompressionStream("gzip"));
        return new Response(stream).blob();
    };

    /* What went wrong, in a line. The body was being pasted in whole,
     * and when the endpoint is not mounted on this host that body is an
     * entire 404 page -- several kilobytes of sitemap in a box the size
     * of a business card, with the one useful fact (the URL it asked
     * for) nowhere in it. Text bodies are quoted, briefly; HTML is not
     * quoted at all, because a page that renders is never an
     * explanation. */
    const failure = async (response) => {
        const where = ENDPOINT.href;
        const type = response.headers.get("content-type") || "";
        let detail = "";

        if (type.includes("json")) {
            const body = await response.json().catch(() => null);
            detail = body?.error ? String(body.error) : "";
        } else if (type.startsWith("text/plain")) {
            detail = (await response.text()).trim();
        }

        return `${response.status} ${response.statusText}` +
               `${detail ? ` — ${detail.slice(0, 200)}` : ""} · ${where}`;
    };

    /* An endpoint on another host is a different protection space, and
     * "same-origin" sends nothing to it -- so a report to a central
     * endpoint would arrive unauthenticated and be refused, with the
     * browser refusing to show why. "include" carries the credentials
     * the reporter already has for that host; the endpoint answers only
     * origins it recognises, which is what makes that safe to ask for.
     *
     * Same-origin stays same-origin: "include" would also attach
     * credentials on a redirect off-site, and there is no reason to
     * widen the common case for the sake of the rare one.
     *
     * (CROSS_ORIGIN is resolved at the top of this file, beside the
     * endpoint itself: the panel names the destination origin under the
     * title before anything is sent, and needed the answer long before
     * the transport did.) */
    const post = async (body, headers) => {
        const response = await fetch(CFG.endpoint, {
            method: "POST",
            credentials: CROSS_ORIGIN ? "include" : "same-origin",
            headers: headers || undefined,
            body
        });
        if (!response.ok) throw new Error(await failure(response));
        return response.json();
    };

    const send = async (payload) => {
        const json = JSON.stringify(payload);
        const report = window.CompressionStream
            ? await gzip(json)
            : new Blob([json], { type: "application/json" });

        if (!SHOT.blob) {
            return post(report, { "content-type": "application/json" });
        }
        /* No content-type header here on purpose: fetch has to set the
         * multipart boundary itself. */
        const form = new FormData();
        form.append("report", report, "report.json.gz");
        form.append("screenshot", SHOT.blob, "screenshot.webp");
        return post(form, null);
    };

    /* Loaded on purpose — by a bookmarklet, or by a tag on a page being
     * worked on — so the menu is what you came for. The launcher stays
     * as the way back after closing. */
    openPanel(false);

    form.addEventListener("submit", async (event) => {
        event.preventDefault();

        /* aria-disabled rather than disabled: the button keeps its place
         * in the tab order and can say why it will not act. */
        if (enabled().includes("screenshot") && !SHOT.blob) {
            result.textContent = T.needShot;
            result.classList.add("is-error");
            result.hidden = false;
            $(".a-shot").focus();
            return;
        }

        const button = root.querySelector(".a-send");
        button.disabled = true;
        button.textContent = T.sending;
        try {
            const answer = await send(build());
            /* Done is done: the window closes, and what it has to
             * say afterwards is one line and a reference number.
             * Left open, it invited a second report about the
             * same defect. */
            closePanel();
            notify(`${T.thanks} ${answer.id}`);
        } catch (error) {
            result.textContent = `${T.failed} ${error.message}`;
            result.classList.add("is-error");
            result.hidden = false;
        } finally {
            button.disabled = false;
            button.textContent = T.send;
        }
    });
})();
