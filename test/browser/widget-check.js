const { chromium } = require('playwright-core');
const BASE = process.env.CHROMIUM ||
    '/root/.claude/tools/playwright-chromium';
const SHOTS = process.env.SHOTS || '/var/tmp';
const URL = 'http://127.0.0.1:9393/fixture.html';

const fail = (message) => { console.log('FAIL ' + message); process.exitCode = 1; };

// The switch is a clipped checkbox behind a chip, so a click lands on the
// chip. Tests want a state, not a toggle: set it and announce it.
const setChannel = (page, key, on) => page.evaluate(([k, want]) => {
    const input = document.querySelector('#corrigenda-widget')
        .shadowRoot.querySelector(`.channels input[value="${k}"]`);
    if (input.checked !== want) {
        input.checked = want;
        input.dispatchEvent(new Event('change', { bubbles: true }));
    }
}, [key, on]);

const ok   = (message) => console.log('ok   ' + message);

(async () => {
    const browser = await chromium.launch({
        executablePath: BASE +
            '/browsers/chromium_headless_shell-1228/chrome-headless-shell-linux64' +
            '/chrome-headless-shell',
    });
    const page = await browser.newPage({ viewport: { width: 900, height: 800 } });
    await page.addInitScript(() => {
        navigator.mediaDevices.getDisplayMedia = async () => {
            const canvas = document.createElement('canvas');
            canvas.width = Math.round(innerWidth * devicePixelRatio);
            canvas.height = Math.round(innerHeight * devicePixelRatio);
            const ctx = canvas.getContext('2d');
            const stream = canvas.captureStream(10);
            const paint = () => {
                ctx.fillStyle = '#f2f2f2';
                ctx.fillRect(0, 0, canvas.width, canvas.height);
                ctx.fillStyle = '#c02020';
                ctx.fillRect(20, 20, 240, 80);
            };
            paint();
            const timer = setInterval(paint, 50);
            for (const track of stream.getTracks()) {
                const stop = track.stop.bind(track);
                track.stop = () => { clearInterval(timer); stop(); };
            }
            return stream;
        };
    });

    await page.goto(URL, { waitUntil: 'load' });
    await page.waitForSelector('#corrigenda-widget');
    ok('widget loaded');

    // --- report 1: pick with the mouse -------------------------------
    // No launcher click: the widget opens on its menu, and the launcher
    // is hidden while it is open.
    await page.click('#corrigenda-widget .a-type[value="visual"]');
    await page.click('figcaption.caption');
    await page.fill('#corrigenda-widget textarea', 'Caption is too pale to read');
    // Visual preselects the screenshot channel, and send is blocked while it
    // is on with nothing captured; this scenario does not want an image.
    await setChannel(page, 'screenshot', false);

    const preview = await page.textContent('#corrigenda-widget .preview');
    if (!preview.includes('"schema": 1')) fail('preview does not show the payload');
    else ok('preview shows the payload before sending');

    await page.screenshot({ path: SHOTS + '/corrigenda-form.png' });
    await page.click('#corrigenda-widget .a-send');
    await page.waitForSelector('#corrigenda-widget .result:not([hidden])');
    const first = await page.textContent('#corrigenda-widget .result');
    if (!/Sent\. Reference: \d{8}T/.test(first)) fail('no reference returned: ' + first);
    else ok('report 1 accepted: ' + first.trim());

    await page.screenshot({ path: SHOTS + '/corrigenda-widget.png' });

    // --- report 2: pick with the keyboard ----------------------------
    await page.click('#corrigenda-widget .a-close');
    await page.click('#corrigenda-widget .launcher');
    await page.click('#corrigenda-widget .a-type[value="broken"]');
    await page.hover('figcaption.caption');       // mousemove selects the leaf
    await page.keyboard.press('ArrowUp');         // ... and this the figure
    await page.keyboard.press('Enter');
    await page.fill('#corrigenda-widget textarea', 'Whole figure is misaligned');
    await page.click('#corrigenda-widget .a-send');
    await page.waitForSelector('#corrigenda-widget .result:not([hidden])');
    const second = await page.textContent('#corrigenda-widget .result');
    if (!/Sent\. Reference:/.test(second)) fail('second report rejected: ' + second);
    else ok('report 2 accepted (keyboard pick)');

    // --- report 3: the audit switch, on pale text --------------------
    await page.click('#corrigenda-widget .a-close');
    await page.click('#corrigenda-widget .launcher');
    await page.click('#corrigenda-widget .a-type[value="visual"]');
    await page.click('figcaption.caption');
    await setChannel(page, 'audit', true);
    await page.fill('#corrigenda-widget textarea', 'Contrast check');
    // no image wanted here either
    await setChannel(page, 'screenshot', false);
    await page.click('#corrigenda-widget .a-send');
    await page.waitForSelector('#corrigenda-widget .result:not([hidden])');
    ok('report 3 accepted (audit switch on)');

    // --- report 4: a form must not leak what was typed into it -------
    await page.click('#corrigenda-widget .a-close');
    await page.click('#corrigenda-widget .launcher');
    await page.click('#corrigenda-widget .a-type[value="broken"]');
    await page.hover('input[type="password"]');
    await page.keyboard.press('ArrowUp');   // input -> label
    await page.keyboard.press('ArrowUp');   // label -> form
    await page.keyboard.press('Enter');
    await page.fill('#corrigenda-widget textarea', 'The form does nothing');
    await page.click('#corrigenda-widget .a-send');
    await page.waitForSelector('#corrigenda-widget .result:not([hidden])');
    ok('report 4 accepted (form picked)');

    // --- report 5: the screenshot channel ----------------------------
    await page.click('#corrigenda-widget .a-close');
    await page.click('#corrigenda-widget .launcher');
    await page.click('#corrigenda-widget .a-type[value="visual"]');
    await page.click('figcaption.caption');
    await setChannel(page, 'screenshot', true);
    await page.click('#corrigenda-widget .scope-option[data-scope="viewport"]');
    await page.click('#corrigenda-widget .a-shot');
    await page.waitForSelector('#corrigenda-widget .shot-preview:not([hidden])');

    const shotStatus = await page.textContent('#corrigenda-widget .shot-status');
    if (!/captured/.test(shotStatus)) fail('capture status: ' + shotStatus);
    else ok('screenshot captured: ' + shotStatus.trim());
    // fixture has a password field and a text field; both must be covered
    if (!/2 /.test(shotStatus)) fail('expected 2 redactions: ' + shotStatus);
    else ok('both form fields redacted before upload');

    await page.screenshot({ path: SHOTS + '/corrigenda-shot.png' });
    await page.fill('#corrigenda-widget textarea', 'With a screenshot');
    await page.click('#corrigenda-widget .a-send');
    await page.waitForSelector('#corrigenda-widget .result:not([hidden])');
    const fifth = await page.textContent('#corrigenda-widget .result');
    if (!/Sent\. Reference:/.test(fifth)) fail('multipart send failed: ' + fifth);
    else ok('report 5 accepted (multipart with screenshot)');

    // --- report 6: "the text is wrong" uses the selection -------------
    await page.click('#corrigenda-widget .a-close');
    await page.evaluate(() => {
        const node = document.querySelector('figcaption.caption').firstChild;
        const range = document.createRange();
        range.setStart(node, 0);
        range.setEnd(node, node.length);
        getSelection().removeAllRanges();
        getSelection().addRange(range);
    });
    await page.click('#corrigenda-widget .launcher');
    await page.click('#corrigenda-widget .a-type[value="content"]');

    // the picker must have been skipped: the form is already showing
    await page.waitForSelector('#corrigenda-widget .report:not([hidden])');
    const prefilled = await page.inputValue('#corrigenda-widget textarea');
    if (!/Venetian carnival, 2019/.test(prefilled)) {
        fail('selection not quoted into the message: ' + prefilled);
    } else {
        ok('text report quotes the selection and skips the picker');
    }

    // and it must collect the element only, not styles or rules
    const contentChannels = await page.evaluate(() =>
        [...document.querySelector('#corrigenda-widget').shadowRoot
            .querySelectorAll('.channels input')]
            .filter(i => i.checked).map(i => i.value));
    if (contentChannels.join(',') !== 'fragment') {
        fail('content defaults are ' + contentChannels.join(','));
    } else {
        ok('text report collects the element only');
    }

    await page.fill('#corrigenda-widget textarea', 'Wrong year');
    await page.click('#corrigenda-widget .a-send');
    await page.waitForSelector('#corrigenda-widget .result:not([hidden])');
    ok('report 6 accepted (content, from a selection)');

// --- injected from <head>, as MoXoW emits it ---------------------
// Undeferred and before <body> exists: the widget has to survive
// having no document.body when it runs, or the MoXoW path is dead
// while the bookmarklet keeps working.
{
    const headPage = await browser.newPage({ viewport: { width: 900, height: 700 } });
    const errors = [];
    headPage.on("pageerror", (e) => errors.push(e.message));
    await headPage.goto("http://127.0.0.1:9393/in-head.html", { waitUntil: "load" });
    const mounted = await headPage.evaluate(() =>
        !!document.querySelector("#corrigenda-widget"));
    if (!mounted) fail("head-injected widget never mounted: " + errors.join("; "));
    else if (errors.length) fail("head-injected widget threw: " + errors.join("; "));
    else ok("mounts when injected from <head>, before <body> exists");
    await headPage.close();
}

    // --- a page that only advertises the endpoint --------------------
    // The shape MoXoW emits: a link saying where reports go, and a
    // script tag saying nothing but where the client is. The endpoint
    // used to be on the tag as well, which is two places to say one
    // thing and two places to disagree.
    {
        const linkPage = await browser.newPage({ viewport: { width: 900, height: 700 } });
        const posted = [];
        // URL is the fixture's own constant at the top of this file, so
        // the global constructor is out of reach here: strip the origin
        // by hand rather than shadow-dance around it.
        linkPage.on('request', (r) => {
            if (r.method() === 'POST') {
                posted.push(r.url().replace(/^https?:\/\/[^/]+/, ''));
            }
        });

        await linkPage.goto('http://127.0.0.1:9393/link-only.html', { waitUntil: 'load' });
        await linkPage.waitForSelector('#corrigenda-widget .menu:not([hidden])');
        await linkPage.click('#corrigenda-widget .a-type[value="idea"]');
        await linkPage.waitForSelector('#corrigenda-widget .report:not([hidden])');
        await linkPage.fill('#corrigenda-widget textarea',
                            'found the endpoint on the page');
        await linkPage.click('#corrigenda-widget .a-send');
        await linkPage.waitForFunction(() => !document.querySelector('#corrigenda-widget')
            .shadowRoot.querySelector('.result').hidden, null, { timeout: 8000 })
            .catch(() => {});

        const said = (await linkPage.textContent('#corrigenda-widget .result')).trim();
        if (!/Sent\. Reference: \d{8}T/.test(said))
            fail('a link-only page could not send: ' + said);
        else if (!posted.includes('/.corrigenda/report/'))
            fail('posted somewhere else: ' + JSON.stringify(posted));
        else ok('reads the endpoint off the page when the tag does not say');
        await linkPage.close();
    }

    // --- the widget must not disturb the page it measures ------------
    const stray = await page.evaluate(() =>
        document.body.querySelectorAll('div#corrigenda-widget').length);
    if (stray !== 1) fail('widget host count is ' + stray);
    else ok('widget adds exactly one host element');

    await browser.close();
})();
