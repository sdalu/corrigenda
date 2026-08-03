// Everything here is browser-divergent, which is why it is its own file
// and why it runs twice. The bug that prompted it -- words inside a link
// could not be selected in Firefox -- was invisible for as long as the
// suite only ever ran in Chromium.
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

const panelBox = (page) => page.evaluate(() => {
    const r = document.querySelector('#corrigenda-widget').shadowRoot
        .querySelector('.panel').getBoundingClientRect();
    return { top: Math.round(r.top), left: Math.round(r.left),
             right: Math.round(r.right), bottom: Math.round(r.bottom),
             height: Math.round(r.height) };
});

const headerAt = (page) => page.evaluate(() => {
    const r = document.querySelector('#corrigenda-widget').shadowRoot
        .querySelector('header').getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});

const onScreen = (box, width, height) =>
    box.top >= 0 && box.left >= 0 && box.right <= width && box.bottom <= height;

const dragHeader = async (page, to) => {
    const from = await headerAt(page);
    await page.mouse.move(from.x, from.y);
    await page.mouse.down();
    await page.mouse.move(to.x, to.y, { steps: 12 });
    await page.mouse.up();
};

const open = async (page, type) => {
    await page.goto(URL, { waitUntil: 'load' });
    await page.waitForSelector('#corrigenda-widget .menu:not([hidden])');
    if (type) await page.click(`#corrigenda-widget .a-type[value="${type}"]`);
};

// The shape that broke: a paragraph wrapped in a link, as on the live
// /sessions/ index. Firefox commits to dragging the link at mousedown,
// and no amount of cancelling dragstart afterwards gives the words back.
const selectProse = async (page, selector) => {
    const box = await page.locator(selector).boundingBox();
    await page.mouse.move(box.x + 4, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + 140, box.y + box.height / 2, { steps: 10 });
    await page.mouse.up();
    await page.waitForSelector('#corrigenda-widget .report:not([hidden])',
                               { timeout: 4000 }).catch(() => {});
    return page.evaluate(() => ({
        path: location.pathname,
        message: document.querySelector('#corrigenda-widget')
            .shadowRoot.querySelector('textarea').value,
    }));
};

const check = async (name, browser, executablePath) => {
    const instance = await browser.launch({ executablePath });
    const page = await instance.newPage({ viewport: { width: 900, height: 700 } });

    await open(page, 'content');
    const linked = await selectProse(page, '.index-simplex p');
    if (linked.path !== '/fixture.html')
        fail(`${name}: selecting inside a link navigated to ${linked.path}`);
    else if (!linked.message.includes('«'))
        fail(`${name}: nothing selected inside a link`);
    else ok(`${name}: words inside a link are selectable`);

    await open(page, 'content');
    const plain = await selectProse(page, 'figcaption.caption');
    if (!plain.message.includes('«')) fail(`${name}: ordinary prose not selectable`);
    else ok(`${name}: ordinary prose is selectable`);

    // A selection crossing a heading and a paragraph is about both of
    // them. The common ancestor is where to open the page; it is not an
    // answer to which elements the words were in.
    await open(page, 'content');
    await page.evaluate(() => {
        const card = document.querySelector('.index-simplex .content');
        const range = document.createRange();
        range.setStart(card.querySelector('h3').firstChild, 0);
        const prose = card.querySelector('p').firstChild;
        range.setEnd(prose, 12);
        getSelection().removeAllRanges();
        getSelection().addRange(range);
    });
    await page.mouse.move(10, 10);
    await page.mouse.down();
    await page.mouse.up();
    await page.keyboard.press('Enter');
    await page.waitForSelector('#corrigenda-widget .report:not([hidden])',
                               { timeout: 4000 }).catch(() => {});
    const payload = JSON.parse(await page.textContent(
        '#corrigenda-widget .preview'));
    const covers = payload.target && payload.target.covers;
    const hint = await page.textContent('#corrigenda-widget .target');
    if (!covers || covers.length !== 2)
        fail(`${name}: text report does not name its elements: ` +
             JSON.stringify(covers));
    else if (!covers.some((s) => s.includes('h3')) ||
             !covers.some((s) => s.includes('p')))
        fail(`${name}: wrong elements named: ${JSON.stringify(covers)}`);
    else if (!/2 elements/.test(hint))
        fail(`${name}: the header does not say how many elements: ${hint}`);
    else ok(`${name}: a selection across two elements names both ` +
            `(${covers.join(', ')})`);

    // The page is borrowed, not kept: whatever it declared is put back.
    await open(page);
    const declared = await page.evaluate(() => {
        const link = document.querySelector('.index-simplex a');
        link.setAttribute('draggable', 'true');
        return link.getAttribute('draggable');
    });
    await page.click('#corrigenda-widget .a-type[value="content"]');
    const during = await page.evaluate(() =>
        document.querySelector('.index-simplex a').getAttribute('draggable'));
    await page.keyboard.press('Escape');
    await page.waitForTimeout(150);
    const after = await page.evaluate(() => ({
        declared: document.querySelector('.index-simplex a').getAttribute('draggable'),
        strays: document.querySelectorAll(
            'a[draggable="false"], img[draggable="false"]').length,
    }));
    if (during !== 'false') fail(`${name}: links still drag in text mode (${during})`);
    else if (after.declared !== declared || after.strays)
        fail(`${name}: draggable not restored ${JSON.stringify(after)}`);
    else ok(`${name}: dragging suppressed while selecting, restored after`);

    // The window keeps all four edges on screen, however it got there.
    await open(page);
    await dragHeader(page, { x: 2000, y: 2000 });
    const corner = await panelBox(page);
    if (!onScreen(corner, 900, 700))
        fail(`${name}: dragged off the bottom-right ${JSON.stringify(corner)}`);
    else ok(`${name}: stays on screen when dragged past a corner`);

    await page.mouse.move(corner.left + 60, corner.top + 10);
    await page.mouse.down();
    await page.mouse.move(-800, -800, { steps: 12 });
    await page.mouse.up();
    const origin = await panelBox(page);
    if (!onScreen(origin, 900, 700))
        fail(`${name}: dragged off the top-left ${JSON.stringify(origin)}`);
    else ok(`${name}: stays on screen when dragged past the origin`);

    // Parked on the bottom edge, then given more to show. The payload
    // preview is the biggest thing this window can open, and opening it
    // must not push the buttons that send the report off the screen.
    await page.click('#corrigenda-widget .a-type[value="idea"]');
    await page.waitForSelector('#corrigenda-widget .report:not([hidden])');
    await page.mouse.move(origin.left + 60, origin.top + 10);
    await page.mouse.down();
    await page.mouse.move(500, 2000, { steps: 10 });
    await page.mouse.up();
    const before = await panelBox(page);
    await page.click('#corrigenda-widget .a-preview');
    await page.waitForTimeout(300);
    const grown = await panelBox(page);
    if (grown.height <= before.height)
        fail(`${name}: the form did not grow the window, so nothing was tested`);
    else if (!onScreen(grown, 900, 700))
        fail(`${name}: grew off the screen ${JSON.stringify(grown)}`);
    else ok(`${name}: stays on screen when content grows it ` +
            `(${before.height} → ${grown.height})`);

    await page.setViewportSize({ width: 520, height: 420 });
    await page.waitForTimeout(300);
    const shrunk = await panelBox(page);
    if (!onScreen(shrunk, 520, 420))
        fail(`${name}: stranded by a smaller viewport ${JSON.stringify(shrunk)}`);
    else ok(`${name}: follows the viewport when it shrinks`);

    await instance.close();
};

(async () => {
    for (const [name, browser, path] of BROWSERS) await check(name, browser, path);
})();
