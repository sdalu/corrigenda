// A report sent to an endpoint on another origin.
//
// This is the arrangement a site gets when it does NOT mount the
// service: the widget is told an endpoint elsewhere, and the browser —
// not the code — decides whether the request happens at all. It sends a
// preflight first (a gzipped body is not a simple request), refuses a
// wildcard once credentials are involved, and hides the reason for any
// failure from the page. So none of it can be checked by reading the
// code; it has to be driven.
//
// Two servers, two origins: the page is served from 127.0.0.1 and the
// endpoint answers on localhost, which the browser treats as a
// different origin while both stay on this machine.
const { chromium, firefox } = require('playwright-core');
const BASE = process.env.CHROMIUM ||
    '/root/.claude/tools/playwright-chromium';

const PAGE     = process.env.PAGE_ORIGIN     || 'http://127.0.0.1:9393';
const ENDPOINT = process.env.ENDPOINT_ORIGIN || 'http://localhost:9397';

const BROWSERS = [
    // Local Network Access is a loopback rule: Chromium refuses a
    // request from one loopback origin to another unless permission
    // is granted, which no headless run can do and no pair of public
    // https hosts is subject to. Turning it off is what makes this
    // test about CORS rather than about localhost.
    ['chromium', chromium, BASE +
        '/browsers/chromium_headless_shell-1228/chrome-headless-shell-linux64' +
        '/chrome-headless-shell',
     ['--disable-features=LocalNetworkAccessChecks,PrivateNetworkAccessChecks']],
    ['firefox', firefox, BASE + '/browsers/firefox-1532/firefox/firefox', []],
];

const ok   = (message) => console.log('ok   ' + message);
const fail = (message) => { console.log('FAIL ' + message); process.exitCode = 1; };

const check = async (name, browser, executablePath, args) => {
    const instance = await browser.launch({ executablePath, args });
    const page = await instance.newPage({ viewport: { width: 900, height: 800 } });

    let allowed = null;
    page.on('response', (r) => {
        if (r.request().method() === 'POST' && r.url().startsWith(ENDPOINT))
            allowed = r.headers()['access-control-allow-origin'];
    });

    // point the widget at the other origin, the way MoXoW's
    // corrigenda="https://tools.sdalu.com|..." does
    await page.route(`${PAGE}/fixture.html`, async (route) => {
        const response = await route.fetch();
        const html = (await response.text()).replace(
            'data-endpoint="/report/"',
            `data-endpoint="${ENDPOINT}/report/"`);
        await route.fulfill({ response, body: html });
    });

    await page.goto(`${PAGE}/fixture.html`, { waitUntil: 'load' });
    await page.waitForSelector('#corrigenda-widget .menu:not([hidden])');
    await page.click('#corrigenda-widget .a-type[value="idea"]');
    await page.waitForSelector('#corrigenda-widget .report:not([hidden])');
    await page.fill('#corrigenda-widget textarea',
                    'sent across origins');
    await page.click('#corrigenda-widget .a-send');
    // Sent, and the window closes behind it: the reference lands in the
    // toast. A refusal leaves the window open and lands in the panel, so
    // both are waited for and whichever arrived is what gets reported.
    const box = await page.waitForSelector(
        '#corrigenda-widget .toast:not([hidden]), ' +
        '#corrigenda-widget .result:not([hidden])',
        { timeout: 10000 }).catch(() => null);

    const said = box ? (await box.textContent()).trim() : '(nothing was said)';

    if (!/Sent\. Reference: \d{8}T/.test(said))
        fail(`${name}: a cross-origin report did not land: ${said}`);
    else ok(`${name}: accepted across origins — ${said}`);

    // Playwright does not surface a preflight as a page request, so
    // this asserts its consequence instead: a gzipped, credentialed
    // POST to another origin only completes when the preflight was
    // answered, and the answer has to name this origin rather than
    // a wildcard.
    if (allowed !== PAGE)
        fail(`${name}: the answer allowed ${JSON.stringify(allowed)}, not ${PAGE}`);
    else ok(`${name}: the answer names this origin, not a wildcard`);

    await instance.close();
};

(async () => {
    for (const [name, browser, path, args] of BROWSERS)
        await check(name, browser, path, args);
})();
