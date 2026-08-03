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
const stub = (grants) => `
    // A content script at document_start runs once the parser has made
    // the documentElement; an init script here runs before that, so the
    // marker waits for the element it goes on. The widget is deferred,
    // so it still reads the marker before it draws anything.
    (function mark() {
        if (document.documentElement) {
            document.documentElement.dataset.corrigendaCapture = "0.1.0-stub";
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

        if (m.type === "ping") return reply({ type: "pong", version: "stub" });
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

const open = async (page, grants) => {
    await page.addInitScript(stub(grants));
    await page.goto(URL, { waitUntil: 'load' });
    await page.waitForSelector('#corrigenda-widget .menu:not([hidden])');
    await page.click('#corrigenda-widget .a-type[value="visual"]');
    await page.click('figcaption.caption');
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

    await instance.close();
};

(async () => {
    for (const [name, browser, path] of BROWSERS) await check(name, browser, path);
})();
