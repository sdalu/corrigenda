// The widget's side of the extension bridge, without the extension.
//
// A real add-on cannot be loaded into these headless runs, but the part
// worth testing is the client's: does it detect the marker, ask for the
// right rectangle, crop from the rectangle it was GIVEN rather than the
// one it asked for, and fall back when the bridge fails? A stub content
// script answers exactly as extension/content.js does, so all four
// questions get answered here.
const { chromium, firefox } = require('playwright-core');
const BASE = process.env.CHROMIUM ||
    '/root/.claude/tools/playwright-chromium';
const URL = 'http://127.0.0.1:9393/fixture.html';

const BROWSERS = [
    ['chromium', chromium, BASE +
        '/browsers/chromium_headless_shell-1228/chrome-headless-shell-linux64' +
        '/chrome-headless-shell'],
    ['firefox', firefox, BASE + '/browsers/firefox-1532/firefox/firefox'],
];

const ok   = (message) => console.log('ok   ' + message);
const fail = (message) => { console.log('FAIL ' + message); process.exitCode = 1; };

// grants: 'rect' answers with the rectangle asked for (Firefox's
// captureTab), 'viewport' always answers with the viewport (Chrome's
// captureVisibleTab), 'refuse' fails the way a sleeping background page
// does.
// Announces the marker and then says nothing at all -- an add-on
// installed but not granted for this page, or a background half that is
// asleep, revoked or mid-update. The marker is on the element either
// way, which is exactly why it cannot be the whole answer.
const mute = `
    (function mark() {
        if (document.documentElement) {
            document.documentElement.dataset.corrigendaCapture = "2";
        } else {
            setTimeout(mark, 0);
        }
    })();
    window.__captureAsks = [];
`;

const stub = (grants, helper = 2, granted = true) => `
    // A content script at document_start runs once the parser has made
    // the documentElement; an init script here runs before that, so the
    // marker waits for the element it goes on. The widget is deferred,
    // so it still reads the marker before it draws anything.
    (function mark() {
        if (document.documentElement) {
            // the helper contract number, which is what the widget reads
            document.documentElement.dataset.corrigendaCapture = "${helper}";
        } else {
            setTimeout(mark, 0);
        }
    })();
    window.__captureAsks = [];
    addEventListener("message", (event) => {
        const m = event.data;
        if (event.source !== window || m?.source !== "corrigenda") return;
        const reply = (payload) => postMessage(
            { source: "corrigenda-extension", id: m.id, ...payload }, origin);

        if (m.type === "ping") return reply({ type: "pong", helper: ${helper},
                                             version: "stub", granted: ${granted} });
        if (m.type !== "capture") return;

        window.__captureAsks.push(m.rect);
        if ("${grants}" === "refuse")
            return reply({ type: "failed", error: "background asleep" });

        const rect = "${grants}" === "viewport"
            ? { x: scrollX, y: scrollY, width: innerWidth, height: innerHeight }
            : m.rect;

        // a canvas of the right size stands in for the real capture
        const canvas = document.createElement("canvas");
        canvas.width = Math.round(rect.width * m.scale);
        canvas.height = Math.round(rect.height * m.scale);
        const ctx = canvas.getContext("2d");
        ctx.fillStyle = "#cfd8dc";
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        reply({ type: "captured", dataUrl: canvas.toDataURL("image/png"),
                rect, scale: m.scale });
    });
`;

const open = async (page, grants, helper, granted) => {
    await page.addInitScript(stub(grants, helper, granted));
    await page.goto(URL, { waitUntil: 'load' });
    await page.waitForSelector('#corrigenda-widget .menu:not([hidden])');
    await page.click('#corrigenda-widget .a-type[value="visual"]');
    await page.click('figcaption.caption');
};

// What the widget shows without anyone touching the capture button.
const unasked = async (page) => {
    await page.waitForSelector('#corrigenda-widget .shot-preview:not([hidden])',
                               { timeout: 5000 }).catch(() => {});

    return page.evaluate(() => {
        const r = document.querySelector('#corrigenda-widget').shadowRoot;
        return { captured: !r.querySelector('.shot-preview').hidden,
                 status: r.querySelector('.shot-status').textContent.trim(),
                 asks: (window.__captureAsks || []).length };
    });
};

const shoot = async (page) => {
    // Wait for the capture itself, not for the words next to it: the
    // status already says which scope is selected before the shutter,
    // and which text lands first is a race the test kept losing.
    await page.click('#corrigenda-widget .a-shot');
    await page.waitForSelector('#corrigenda-widget .shot-preview:not([hidden])',
                               { timeout: 10000 }).catch(() => {});
    await page.waitForFunction(() => !document.querySelector('#corrigenda-widget')
        .shadowRoot.querySelector('.a-shot').disabled,
        null, { timeout: 5000 }).catch(() => {});

    return page.evaluate(() => {
        const r = document.querySelector('#corrigenda-widget').shadowRoot;
        const preview = r.querySelector('.shot-preview');
        return { status: r.querySelector('.shot-status').textContent.trim(),
                 captured: !preview.hidden,
                 asks: window.__captureAsks || [] };
    });
};

const check = async (name, browser, executablePath) => {
    const instance = await browser.launch({ executablePath });

    // 1. the marker is enough: no share dialog is ever opened, and the
    //    scopes Firefox cannot otherwise offer are all available
    let page = await instance.newPage({ viewport: { width: 900, height: 700 } });
    await page.addInitScript(() => {
        navigator.mediaDevices.getDisplayMedia = async () => {
            window.__sharePrompted = true;
            throw new Error('the share dialog should not have been reached');
        };
    });
    await open(page, 'rect');
    const scopes = await page.evaluate(() => [...document.querySelector(
        '#corrigenda-widget').shadowRoot.querySelectorAll('.scope input')]
        .map((input) => !input.disabled));
    const first = await shoot(page);

    if (await page.evaluate(() => Boolean(window.__sharePrompted)))
        fail(`${name}: went to the share dialog with an extension present`);
    else if (!first.captured)
        fail(`${name}: nothing captured through the bridge: ${first.status}`);
    else if (!scopes.every(Boolean))
        fail(`${name}: a scope is still disabled: ${JSON.stringify(scopes)}`);
    else ok(`${name}: captured through the bridge, all three scopes offered`);

    // 2. asking for the whole document asks for the whole document
    await page.click('#corrigenda-widget .scope-option[data-scope="full"]');
    const full = await shoot(page);
    const asked = full.asks.at(-1);
    const wanted = await page.evaluate(() => ({
        width: Math.max(document.documentElement.scrollWidth, innerWidth),
        height: Math.max(document.documentElement.scrollHeight, innerHeight) }));
    if (!asked || Math.abs(asked.width - wanted.width) > 1 ||
        Math.abs(asked.height - wanted.height) > 1)
        fail(`${name}: "no crop" asked for ${JSON.stringify(asked)}, ` +
             `document is ${JSON.stringify(wanted)}`);
    else ok(`${name}: "no crop" asks for the whole document ` +
            `(${Math.round(asked.width)}×${Math.round(asked.height)})`);
    await page.close();

    // 3. a browser that can only give the viewport says so, and is not
    //    cropped as though it had given the page
    page = await instance.newPage({ viewport: { width: 900, height: 700 } });
    await open(page, 'viewport');
    await page.click('#corrigenda-widget .scope-option[data-scope="full"]');
    const partial = await shoot(page);
    if (!partial.captured) fail(`${name}: viewport-only capture produced nothing`);
    else if (!/visible page only/i.test(partial.status))
        fail(`${name}: a cut-down capture did not say so: ${partial.status}`);
    else ok(`${name}: a viewport-only browser is captured and says so`);
    await page.close();

    // 4. a bridge that fails hands the job back to getDisplayMedia
    page = await instance.newPage({ viewport: { width: 900, height: 700 } });
    await page.addInitScript(() => {
        navigator.mediaDevices.getDisplayMedia = async () => {
            window.__fellBack = true;
            const canvas = document.createElement('canvas');
            canvas.width = Math.round(innerWidth * devicePixelRatio);
            canvas.height = Math.round(innerHeight * devicePixelRatio);
            canvas.getContext('2d').fillRect(0, 0, canvas.width, canvas.height);
            return canvas.captureStream(10);
        };
    });
    await open(page, 'refuse');
    const fell = await shoot(page);
    if (!(await page.evaluate(() => Boolean(window.__fellBack))))
        fail(`${name}: a failed bridge did not fall back: ${fell.status}`);
    else if (!fell.captured)
        fail(`${name}: fell back but captured nothing: ${fell.status}`);
    else ok(`${name}: a failed bridge falls back to the share dialog`);
    await page.close();

    // 5. an add-on older than the contract this page requires is not
    //    talked to at all: a message it would read as something else is
    //    worse than no message. It advertises 0; the widget wants 1.
    page = await instance.newPage({ viewport: { width: 900, height: 700 } });
    await page.addInitScript(() => {
        navigator.mediaDevices.getDisplayMedia = async () => {
            window.__fellBack = true;
            const canvas = document.createElement('canvas');
            canvas.width = Math.round(innerWidth * devicePixelRatio);
            canvas.height = Math.round(innerHeight * devicePixelRatio);
            canvas.getContext('2d').fillRect(0, 0, canvas.width, canvas.height);
            return canvas.captureStream(10);
        };
    });
    await open(page, 'rect', 1);
    const old = await shoot(page);
    const oldAbout = await page.evaluate(() =>
        document.querySelector('#corrigenda-widget').shadowRoot
                .querySelector('.a-warn').dataset.about || '');
    const sent = await page.evaluate(() => window.__captureAsks.length);
    if (sent !== 0)
        fail(`${name}: an old helper was sent ${sent} capture request(s)`);
    else if (!(await page.evaluate(() => Boolean(window.__fellBack))))
        fail(`${name}: an old helper was ignored but nothing took over`);
    else if (!old.captured)
        fail(`${name}: fell back from an old helper but captured nothing`);
    else if (name === 'firefox' && !/older than/.test(oldAbout))
        fail(`${name}: an old helper is ignored without saying so: ${oldAbout}`);
    else ok(`${name}: an add-on below the required helper is left alone, and said why`);
    await page.close();

    // 6. with the add-on there is nothing to answer and nothing to
    //    choose, so the picture is taken as soon as the form appears.
    page = await instance.newPage({ viewport: { width: 900, height: 700 } });
    await open(page, 'rect');
    const free = await unasked(page);
    if (!free.captured)
        fail(`${name}: nothing was captured without pressing anything`);
    else if (free.asks !== 1)
        fail(`${name}: expected one capture, got ${free.asks}`);
    else ok(`${name}: the add-on captures without being asked — ${free.status}`);

    // 7. removing it means removing it: the button that takes the shot
    //    away must not be undone by the thing that took it.
    await page.click('#corrigenda-widget .a-drop');
    await page.waitForTimeout(300);
    const gone = await page.evaluate(() => document.querySelector(
        '#corrigenda-widget').shadowRoot.querySelector('.shot-preview').hidden);
    if (!gone) fail(`${name}: a removed screenshot came straight back`);
    else ok(`${name}: removing a screenshot keeps it removed`);
    await page.close();

    // 8. without the add-on nothing happens on its own: getDisplayMedia
    //    raises a share dialog, and a page that raises one unasked is a
    //    page whose next permission gets refused out of habit.
    page = await instance.newPage({ viewport: { width: 900, height: 700 } });
    await page.addInitScript(() => {
        window.__shareAsked = 0;
        navigator.mediaDevices.getDisplayMedia = async () => {
            window.__shareAsked += 1;
            const canvas = document.createElement('canvas');
            canvas.width = Math.round(innerWidth * devicePixelRatio);
            canvas.height = Math.round(innerHeight * devicePixelRatio);
            canvas.getContext('2d').fillRect(0, 0, canvas.width, canvas.height);
            return canvas.captureStream(10);
        };
    });
    await page.goto(URL, { waitUntil: 'load' });
    await page.waitForSelector('#corrigenda-widget .menu:not([hidden])');
    await page.click('#corrigenda-widget .a-type[value="visual"]');
    await page.click('figcaption.caption');
    await page.waitForTimeout(500);
    const prompts = await page.evaluate(() => window.__shareAsked);
    if (prompts !== 0)
        fail(`${name}: the share dialog was raised ${prompts} time(s) unasked`);
    else ok(`${name}: no add-on, no dialog until the button is pressed`);
    await page.close();

    // 9. a marker nobody answers is not an add-on this page can use: the
    //    cropping scopes go, the warning comes back, and nothing is
    //    captured on its own -- which would mean the share dialog.
    page = await instance.newPage({ viewport: { width: 900, height: 700 } });
    await page.addInitScript(() => {
        window.__shareAsked = 0;
        navigator.mediaDevices.getDisplayMedia = async () => {
            window.__shareAsked += 1;
            const canvas = document.createElement('canvas');
            canvas.width = Math.round(innerWidth * devicePixelRatio);
            canvas.height = Math.round(innerHeight * devicePixelRatio);
            canvas.getContext('2d').fillRect(0, 0, canvas.width, canvas.height);
            return canvas.captureStream(10);
        };
    });
    await page.addInitScript(mute);
    await page.goto(URL, { waitUntil: 'load' });
    await page.waitForSelector('#corrigenda-widget .menu:not([hidden])');
    await page.click('#corrigenda-widget .a-type[value="visual"]');
    await page.click('figcaption.caption');
    // the ping gives up after two seconds; nothing should happen before
    // or after it does
    await page.waitForTimeout(3000);
    const silent = await page.evaluate(() => {
        const r = document.querySelector('#corrigenda-widget').shadowRoot;
        return {
            warned: !r.querySelector('.a-warn').hidden,
            scopes: [...r.querySelectorAll('.scope input')].map((i) => !i.disabled),
            shared: window.__shareAsked,
            captured: !r.querySelector('.shot-preview').hidden,
            about: r.querySelector('.a-warn').dataset.about || ''
        };
    });

    // Chrome can crop through getDisplayMedia, so only Firefox loses the
    // scopes and gets the warning; what must hold in both is that a
    // silent bridge takes no picture and raises no dialog.
    if (name === 'firefox' && !/toolbar button/.test(silent.about))
        fail(`${name}: the warning does not mention allowing the add-on here`);
    else if (silent.shared !== 0)
        fail(`${name}: a silent bridge sent us to the share dialog`);
    else if (silent.captured)
        fail(`${name}: something was captured through a bridge that never answered`);
    else if (name === 'firefox' && !silent.warned)
        fail(`${name}: no warning, though nothing here can crop`);
    else if (name === 'firefox' && silent.scopes.filter(Boolean).length !== 1)
        fail(`${name}: cropping scopes offered: ${JSON.stringify(silent.scopes)}`);
    else ok(`${name}: an add-on that does not answer here is not used`);
    await page.close();

    // 9. installed, answering, and not granted this site. The marker is
    //    there and the bridge replies, so everything that looks at the
    //    page says "add-on present" -- but the half that takes the
    //    picture holds no permission here, and says so. This must read
    //    exactly like having no add-on at all: warning up, cropping
    //    withdrawn, nothing captured behind anyone's back.
    page = await instance.newPage({ viewport: { width: 900, height: 700 } });
    await page.addInitScript(() => {
        window.__shareAsked = 0;
        navigator.mediaDevices.getDisplayMedia = async () => {
            window.__shareAsked += 1;
            const canvas = document.createElement('canvas');
            canvas.width = Math.round(innerWidth * devicePixelRatio);
            canvas.height = Math.round(innerHeight * devicePixelRatio);
            canvas.getContext('2d').fillRect(0, 0, canvas.width, canvas.height);
            return canvas.captureStream(10);
        };
    });
    await open(page, 'rect', 2, false);
    await page.goto(URL, { waitUntil: 'load' });
    await page.waitForSelector('#corrigenda-widget .menu:not([hidden])');
    await page.click('#corrigenda-widget .a-type[value="visual"]');
    await page.click('figcaption.caption');
    await page.waitForTimeout(500);
    const ungranted = await page.evaluate(() => {
        const r = document.querySelector('#corrigenda-widget').shadowRoot;
        return {
            warned: !r.querySelector('.a-warn').hidden,
            scopes: [...r.querySelectorAll('.scope input')].map((i) => !i.disabled),
            asks: window.__captureAsks.length,
            shared: window.__shareAsked,
            about: r.querySelector('.a-warn').dataset.about || ''
        };
    });

    if (ungranted.asks !== 0)
        fail(`${name}: asked an ungranted add-on for ${ungranted.asks} capture(s)`);
    else if (name === 'firefox' && !ungranted.warned)
        fail(`${name}: installed but ungranted, and no warning`);
    else if (name === 'firefox' && ungranted.scopes.filter(Boolean).length !== 1)
        fail(`${name}: cropping offered by an ungranted add-on: ${JSON.stringify(ungranted.scopes)}`);
    else if (name === 'firefox' && !/toolbar button/.test(ungranted.about))
        fail(`${name}: the warning does not say the add-on can be allowed here: ${ungranted.about}`);
    else ok(`${name}: an add-on that may not capture here reads as none, and says how to fix it`);
    await page.close();

    // 10. the scope a report starts on. Cropping to the element is the
    //     default; where it cannot be done the widget falls back to
    //     "no crop", and when it becomes possible -- an add-on that
    //     answered late, or one just granted -- the default comes back
    //     rather than leaving somebody on a scope they never chose.
    page = await instance.newPage({ viewport: { width: 900, height: 700 } });
    await open(page, 'rect');
    await page.goto(URL, { waitUntil: 'load' });
    await page.waitForSelector('#corrigenda-widget .menu:not([hidden])');
    await page.click('#corrigenda-widget .a-type[value="visual"]');
    await page.click('figcaption.caption');
    await page.waitForSelector('#corrigenda-widget .scope input:not([disabled])');
    await page.waitForTimeout(400);
    const chosen = await page.evaluate(() => {
        const r = document.querySelector('#corrigenda-widget').shadowRoot;
        return r.querySelector('.scope input:checked')?.value;
    });

    if (chosen !== 'element')
        fail(`${name}: the scope starts on ${chosen}, not the element crop`);
    else ok(`${name}: cropping to the element is where a report starts`);

    //     And what it asked the browser for while it was there: the
    //     element and its 16px margin, not the screenful around it. The
    //     picture is identical either way -- the crop sees to that --
    //     but asking for the viewport meant a full-screen PNG encoded,
    //     carried as a data URL and decoded before anyone saw a
    //     thumbnail, which is seconds on a large display and was
    //     reported as "it takes a long time before taking the
    //     screenshot".
    const onElement = await page.evaluate(() => {
        const box = document.querySelector('figcaption.caption')
                            .getBoundingClientRect();
        return { got: window.__captureAsks?.at(-1),
                 want: { width: Math.round(box.width) + 32,
                         height: Math.round(box.height) + 32 } };
    });

    const off = onElement.got &&
        Math.max(Math.abs(onElement.got.width - onElement.want.width),
                 Math.abs(onElement.got.height - onElement.want.height));

    if (!onElement.got)
        fail(`${name}: nothing was captured for the element crop`);
    else if (off > 2)
        fail(`${name}: asked for ${Math.round(onElement.got.width)}×` +
             `${Math.round(onElement.got.height)}, wanted the element's ` +
             `${onElement.want.width}×${onElement.want.height}`);
    else ok(`${name}: the capture asks for the element ` +
            `(${onElement.want.width}×${onElement.want.height}), not the ` +
            `900×700 around it`);
    await page.close();

    // 11. a capture that fails says why, and goes on saying it. The
    //     reason used to be swallowed by a bare catch, and then -- once
    //     it was not -- wiped by the next redraw, which is the one a
    //     late answer from the add-on triggers. Both faults looked the
    //     same from the outside: a screenshot that did not happen and
    //     nothing on the panel about it.
    page = await instance.newPage({ viewport: { width: 900, height: 700 } });
    await page.addInitScript(() => {
        // no share dialog to fall back to, so the failure is the answer
        navigator.mediaDevices.getDisplayMedia = async () => {
            throw new Error("no sharing in this test");
        };
    });
    await open(page, 'refuse');
    await page.goto(URL, { waitUntil: 'load' });
    await page.waitForSelector('#corrigenda-widget .menu:not([hidden])');
    await page.click('#corrigenda-widget .a-type[value="visual"]');
    await page.click('figcaption.caption');
    await page.waitForTimeout(1500);
    const said = await page.evaluate(() => document
        .querySelector('#corrigenda-widget').shadowRoot
        .querySelector('.shot-status').textContent.trim());

    if (!said)
        fail(`${name}: a capture failed and the panel said nothing`);
    else if (!/asleep|refused|sharing|—/.test(said))
        fail(`${name}: the panel says "${said}", with no reason in it`);
    else ok(`${name}: a failed capture says why — ${said}`);
    await page.close();

    await instance.close();
};

(async () => {
    for (const [name, browser, path] of BROWSERS) await check(name, browser, path);
})();
