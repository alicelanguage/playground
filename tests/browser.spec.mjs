import { test, expect } from '@playwright/test';
import { writeFile } from 'node:fs/promises';

test('returning mobile clients never load an old unversioned runtime manifest', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const unversioned = [];
  await page.route(/\/(?:_framework\/dotnet|main|embed|worker|runtime|assets)\.js(?:\?|$)/, route => {
    unversioned.push(route.request().url());
    return route.abort();
  });
  await page.goto('/');
  await expect(page.locator('#stage-code')).toContainText('public static void Main', { timeout: 120000 });
  await page.locator('#source').fill('6 * 7');
  await page.locator('#run').click();
  await expect(page.locator('#execution-value')).toContainText('42');
  expect(unversioned).toEqual([]);
});

test('startup downloads compressed runtime assets once within its transfer budget', async ({ page }) => {
  const responses = [];
  page.on('response', response => {
    if (/\.(?:dll|wasm)(?:\.gz)?$/.test(new URL(response.url()).pathname)) {
      responses.push({ url: response.url(), bytes: Number(response.headers()['content-length'] ?? 0) });
    }
  });
  await page.goto('/');
  await expect(page.locator('#stage-code')).toContainText('public static void Main', { timeout:120000 });
  const assemblies = responses.filter(r => /\.dll(?:\.gz)?$/.test(new URL(r.url).pathname));
  const bytes = responses.reduce((sum, r) => sum + r.bytes, 0);
  const report = test.info().outputPath('runtime-transfer.json');
  await writeFile(report, JSON.stringify({ assemblies: assemblies.length, bytes, responses }, null, 2));
  await test.info().attach('runtime-transfer', { path: report, contentType: 'application/json' });
  expect(assemblies.length).toBeGreaterThan(0);
  expect(assemblies.every(r => r.url.endsWith('.dll.gz'))).toBe(true);
  expect(new Set(assemblies.map(r => r.url)).size).toBe(assemblies.length);
  expect(bytes).toBeLessThan(24 * 1024 * 1024);
});

test('the static artifact compiles and executes on browser .NET', async ({ page }) => {
  await page.goto('/__tests');
  await expect(page.locator('body')).toHaveAttribute('data-passed', 'true', {timeout:150000});
  await expect(page.locator('#report')).toContainText('Generated IL executed in browser .NET');
});

test('editor, inspection tabs, diagnostics, Stop and restart', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('#run')).toBeEnabled({ timeout:120000 });
  await expect(page.locator('#stage-code')).toContainText('public static void Main', {timeout:30000});
  await page.locator('#run').click();
  await expect(page.locator('#console-output')).toContainText('Hello from Alice!');
  await expect(page.locator('#execution-value')).toContainText('55');
  for (const [stage,text] of [['hir','CallExpr'],['mir','MFor'],['il','IL_'],['csharp','public static void Main']]) {
    await page.locator(`[data-stage="${stage}"]`).click();
    await expect(page.locator('#stage-code')).toContainText(text);
  }
  await page.locator('#examples').selectOption('safety');
  await expect(page.locator('.diagnostic')).toBeVisible();
  await page.locator('.diagnostic').click();
  await expect(page.locator('#source')).toBeFocused();
  await page.locator('#source').fill('while true\nend');
  await page.locator('#run').click();
  await expect(page.locator('#stop')).toBeEnabled();
  await page.locator('#stop').click();
  await expect(page.locator('#notice')).toContainText('Program stopped');
  await expect(page.locator('#source')).toHaveValue('while true\nend');
  await page.locator('#source').fill('puts 42');
  await page.locator('#run').click();
  await expect(page.locator('#console-output')).toHaveText('42\n', {timeout:120000});
  await page.reload();
  await expect(page.locator('#source')).toHaveValue('puts 42');
});

test('mobile layout and automatic termination', async ({ page }) => {
  await page.setViewportSize({width:390,height:844});
  await page.goto('/');
  await expect(page.locator('#run')).toBeEnabled({timeout:120000});
  await page.locator('#source').fill('while true\nend');
  await page.locator('#run').click();
  await expect(page.locator('#notice')).toContainText('Stopped after 15 seconds', {timeout:25000});
  await expect(page.locator('#source')).toHaveValue('while true\nend');
  await page.screenshot({path:'test-results/playground-mobile.png',fullPage:true});
});


test('editor, compiler output and console scroll independently', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('#run')).toBeEnabled({timeout:120000});
  const source = '# padding\n'.repeat(100) + '120.times { |i| puts "' + 'abcdefghij'.repeat(10) + '" }\n42';
  await page.locator('#source').fill(source);
  await page.locator('#run').click();
  await expect(page.locator('#execution-value')).toContainText('42');
  for (const selector of ['#source', '.stage-scroll', '.console']) {
    const metrics = await page.locator(selector).evaluate(el => ({height:el.clientHeight,content:el.scrollHeight,width:el.clientWidth,contentWidth:el.scrollWidth}));
    expect(metrics.content).toBeGreaterThan(metrics.height);
    expect(metrics.contentWidth).toBeGreaterThan(metrics.width);
  }
  await page.locator('#stage-code').press('PageDown');
  await expect.poll(() => page.locator('.stage-scroll').evaluate(el => el.scrollTop)).toBeGreaterThan(0);
  await page.locator('.console').press('PageDown');
  await expect.poll(() => page.locator('.console').evaluate(el => el.scrollTop)).toBeGreaterThan(0);
});

test('every example runs, the editor highlights Alice, and share links round-trip', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('/');
  await expect(page.locator('#run')).toBeEnabled({ timeout:120000 });
  await expect(page.locator('#highlight .t-com').first()).toBeVisible();
  const examples = await page.locator('#examples option').evaluateAll(options => options.map(o => o.value));
  expect(examples.length).toBeGreaterThanOrEqual(8);
  for (const example of examples.filter(e => e !== 'safety')) {
    await page.locator('#examples').selectOption(example);
    await expect(page.locator('#run')).toBeEnabled({ timeout:60000 });
    await page.locator('#run').click();
    await expect(page.locator('.result-status')).toHaveText('Completed', { timeout:60000 });
    await expect(page.locator('#console-output')).not.toContainText('No console output.');
  }
  await page.locator('#source').fill('def twice(n : Int32) : Int32 = n * 2\nputs "#{twice(21)}"');
  await expect(page.locator('#highlight .t-fn').first()).toContainText('twice');
  await expect(page.locator('#highlight .t-str').first()).toBeVisible();
  await page.locator('#share').click();
  await expect.poll(() => page.url()).toContain('#code=');
  const shared = page.url();
  await page.evaluate(() => localStorage.clear());
  const other = await context.newPage();
  await other.goto(shared);
  await expect(other.locator('#source')).toHaveValue('def twice(n : Int32) : Int32 = n * 2\nputs "#{twice(21)}"');
  await expect(other.locator('#run')).toBeEnabled({ timeout:120000 });
  await other.locator('#run').click();
  await expect(other.locator('#console-output')).toHaveText('42\n', { timeout:60000 });
});

test('editor keys: auto-indent, dedent of end, comment toggle', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('#run')).toBeEnabled({ timeout:120000 });
  await page.locator('#source').fill('');
  await page.locator('#source').focus();
  await page.keyboard.type('def f');
  await page.keyboard.press('Enter');
  await page.keyboard.type('1');
  await page.keyboard.press('Enter');
  await page.keyboard.type('end');
  await expect(page.locator('#source')).toHaveValue('def f\n  1\nend');
  await page.keyboard.press('Control+a');
  await page.keyboard.press('Control+/');
  await expect(page.locator('#source')).toHaveValue('# def f\n  # 1\n# end');
});

const token = text => 'u.' + Buffer.from(text).toString('base64url');

test('embed mode runs a docs code box on load and shows errors', async ({ page }) => {
  await page.goto('/?embed=1&run=1#code=' + token('puts "from the docs"\n6 * 7\n'));
  await expect(page.locator('header')).toBeHidden();
  await expect(page.locator('.tabs')).toBeHidden();
  await expect(page.locator('#console-output')).toContainText('from the docs', { timeout:120000 });
  await expect(page.locator('#execution-value')).toContainText('42');
  await expect(page.locator('#open-playground')).toBeVisible();
  const bad = await page.context().newPage();
  await bad.goto('/?embed=1&run=1&stages=1#code=' + token('val x = 1\nx = 2\n'));
  await expect(bad.locator('.tabs')).toBeVisible();
  await expect(bad.locator('.diagnostic')).toBeVisible({ timeout:120000 });
  await expect(bad.locator('#gutter .ln.bad')).toHaveText('2');
});

test('embed.js turns data-alice-playground blocks into live iframes', async ({ page }) => {
  await page.goto('/404.html');
  await page.setContent('<pre data-alice-playground data-run>puts "embedded"</pre><script type="module" src="http://127.0.0.1:4173/embed.js"></script>');
  const frame = page.frameLocator('iframe');
  await expect(frame.locator('#console-output')).toContainText('embedded', { timeout:120000 });
});

for (const [width, height] of [[1224, 458], [800, 300], [390, 460]]) {
  test(`embed fits its ${width}x${height} iframe without an outer scrollbar`, async ({ page }) => {
    await page.setViewportSize({ width: width + 32, height: 700 });
    await page.goto('/404.html');
    await page.setContent(`<iframe src="/?embed=1&stages=1" style="width:${width}px;height:${height}px;border:0"></iframe>`);
    const frame = page.frameLocator('iframe');
    await expect(frame.locator('body')).toHaveClass(/embed/);
    await frame.locator('html').evaluate(() => document.fonts.ready);
    const metrics = await frame.locator('html').evaluate(el => ({
      height: innerHeight, width: innerWidth, scrollHeight: el.scrollHeight, scrollWidth: el.scrollWidth,
      workspaceBottom: document.querySelector('.workspace').getBoundingClientRect().bottom,
    }));
    expect(metrics.scrollHeight).toBeLessThanOrEqual(metrics.height);
    expect(metrics.scrollWidth).toBeLessThanOrEqual(metrics.width);
    expect(Math.abs(metrics.workspaceBottom - metrics.height)).toBeLessThanOrEqual(1);
    await expect(frame.locator('#run')).toBeVisible();
    if (width === 1224) await page.locator('iframe').screenshot({ path: 'test-results/playground-embed-no-scroll.png' });
    await frame.locator('#source').fill('# scroll inside the editor\n'.repeat(100));
    expect(await frame.locator('#source').evaluate(el => el.scrollHeight > el.clientHeight)).toBe(true);
  });
}

test('autocomplete suggests names while typing and accepts with Tab', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('#run')).toBeEnabled({ timeout:120000 });
  await page.locator('#source').fill('');
  await page.locator('#source').focus();
  await page.keyboard.type('rabbits = 3\nrab');
  await expect(page.locator('#complete')).toBeVisible();
  await expect(page.locator('#complete li').first()).toContainText('rabbits');
  await page.keyboard.press('Tab');
  await page.keyboard.type('.ti');
  await page.keyboard.press('Enter');
  await expect(page.locator('#source')).toHaveValue('rabbits = 3\nrabbits.times');
  await page.keyboard.type('\nMath.Sq');
  await page.keyboard.press('Tab');
  await expect(page.locator('#source')).toHaveValue('rabbits = 3\nrabbits.times\nMath.Sqrt');
});

test('embeds load .NET only when Run is pressed', async ({ page }) => {
  const workers = [];
  page.on('worker', w => workers.push(w));
  await page.goto('/?embed=1#code=' + token('puts "lazy"'));
  await expect(page.locator('#run')).toBeEnabled();
  await expect(page.locator('#console-output')).toContainText('Press ▶ Run');
  await page.waitForTimeout(1500);
  expect(workers.length).toBe(0);
  await page.locator('#run').click();
  await expect(page.locator('#console-output')).toContainText('lazy', { timeout:120000 });
  expect(workers.length).toBe(1);
});
