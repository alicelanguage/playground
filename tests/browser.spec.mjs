import { test, expect } from '@playwright/test';

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
