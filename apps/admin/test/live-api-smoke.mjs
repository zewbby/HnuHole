// Real Go C + SQL browser probe. The caller owns all synthetic accounts/data.
// Usage: node live-api-smoke.mjs fixture.json output.json
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { validUUID } from '../core.mjs';

let browser, stage = 'FIXTURE_VALIDATION', outputPath;
const checks = { loopbackHTTPS: false, login: false, caseSelected: false, claimed: false, muteThreeDays: false, ended: false, auditVisible: false, noExternalRequests: false, noPageErrors: false, logout: false };
const result = { schemaVersion: 1, status: 'FAIL', passed: false, checks, artifacts: {} };
try {
  if (process.argv.length !== 4) throw new Error('configuration required');
  outputPath = resolve(process.argv[3]);
  const fixture = JSON.parse(await readFile(resolve(process.argv[2]), 'utf8'));
  const playwrightModule = process.env.PLAYWRIGHT_MODULE || fixture.playwrightModule;
  if (!playwrightModule) throw new Error('configuration required');
  const target = new URL(fixture.url);
  assert.equal(target.protocol, 'https:');
  assert.ok(['127.0.0.1', 'localhost', '[::1]'].includes(target.hostname));
  assert.ok(!target.username && !target.password && !target.search && !target.hash && ['/', '/admin', '/admin/'].includes(target.pathname));
  assert.ok(validUUID(fixture.caseId));
  assert.ok(typeof fixture.reviewerUsername === 'string' && /^[a-z][a-z0-9_]{5,23}$/.test(fixture.reviewerUsername));
  assert.ok(typeof fixture.reviewerPassword === 'string' && fixture.reviewerPassword.length > 0);
  assert.ok(typeof fixture.outputDirectory === 'string' && fixture.outputDirectory.length > 0);
  checks.loopbackHTTPS = true;
  const directory = resolve(fixture.outputDirectory); await mkdir(directory, { recursive: true });
  const screenshot = join(directory, 'live-moderation-ended.png');
  const { chromium } = createRequire(import.meta.url)(playwrightModule);
  stage = 'BROWSER_START';
  browser = await chromium.launch({ executablePath: process.env.ADMIN_UI_BROWSER || fixture.browserExecutable || undefined, headless: true });
  // This exception belongs only to the caller's synthetic self-signed loopback
  // context. It never changes the OS trust store or the app's HTTPS guard.
  const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 1080 } });
  const page = await context.newPage(); page.setDefaultTimeout(20000); page.setDefaultNavigationTimeout(30000);
  let pageErrors = 0, externalRequests = 0;
  page.on('pageerror', () => { pageErrors++; });
  page.on('request', request => { if (new URL(request.url()).origin !== target.origin) externalRequests++; });
  stage = 'REAL_PAGE_LOGIN';
  await page.goto(`${target.origin}/admin`);
  await page.getByLabel('用户名', { exact: true }).fill(fixture.reviewerUsername);
  await page.getByLabel('密码', { exact: true }).fill(fixture.reviewerPassword);
  await page.getByRole('button', { name: '登录', exact: true }).click();
  await page.getByRole('heading', { name: '举报案件', exact: true }).waitFor(); checks.login = true;
  stage = 'CASE_SELECTION';
  const selected = page.locator(`button[data-record="${fixture.caseId}"]`);
  for (let attempt = 0; attempt < 10; attempt++) {
    await page.locator('.queue .queue-item, .queue .empty').first().waitFor();
    if (await selected.count()) break;
    const older = page.getByRole('button', { name: '加载更早记录', exact: true });
    if (!await older.count()) break;
    const response = page.waitForResponse(value => new URL(value.url()).pathname === '/api/v1/moderation/cases');
    await older.click(); await (await response).finished();
  }
  await selected.click(); await page.getByRole('heading', { name: '举报时的内容', exact: true }).waitFor(); checks.caseSelected = true;
  stage = 'CASE_CLAIM';
  const claim = page.getByRole('button', { name: '开始处理', exact: true });
  if (await claim.count()) {
    await claim.click();
    await page.getByText('已进入处理状态。', { exact: true }).waitFor();
    // The announcement precedes the awaited detail reload. Wait for the new
    // authoritative form before selecting controls in it.
    await page.locator('.detail .heading .status').filter({ hasText: '处理中' }).waitFor();
    checks.claimed = true;
  }
  stage = 'MUTE_DECISION';
  await page.getByLabel('处理措施', { exact: true }).selectOption('MUTE');
  await page.getByLabel('本次期限', { exact: true }).selectOption('3');
  await page.getByText(/考虑现有处罚/).waitFor();
  await page.getByLabel('处理原因', { exact: true }).fill('合成联调：依据本案举报证据，下架并禁言三天。');
  const response = page.waitForResponse(value => new URL(value.url()).pathname === `/api/v1/moderation/cases/${fixture.caseId}/decision` && value.request().method() === 'POST');
  await page.getByRole('button', { name: '确认处理', exact: true }).click();
  const decisionResponse = await response; assert.equal(decisionResponse.status(), 200);
  const submitted = decisionResponse.request().postDataJSON();
  assert.equal(submitted.action, 'MUTE'); assert.equal(submitted.days, 3);
  const decision = await decisionResponse.json(); assert.equal(decision.state, 'ENDED');
  checks.muteThreeDays = true;
  await page.locator('.detail .heading .status').filter({ hasText: '已结束' }).waitFor(); checks.ended = true;
  stage = 'AUDIT_CHECK';
  await page.locator('.detail .audit strong').filter({ hasText: '账号禁言' }).first().waitFor(); checks.auditVisible = true;
  await page.screenshot({ path: screenshot, fullPage: true }); result.artifacts.screenshot = screenshot;
  stage = 'LOGOUT'; await page.getByRole('button', { name: '退出', exact: true }).click(); await page.getByText('已退出。', { exact: true }).waitFor(); checks.logout = true;
  checks.noExternalRequests = externalRequests === 0; checks.noPageErrors = pageErrors === 0;
  assert.ok(checks.noExternalRequests && checks.noPageErrors);
  result.status = 'PASS_REAL_C_HTTPS_UI'; result.passed = true; stage = 'COMPLETE';
} catch {
  // Never print Playwright error objects: locator diagnostics can contain the
  // supplied synthetic password or response text. Only a fixed stage is saved.
  result.status = 'FAIL_REAL_C_HTTPS_UI'; result.failedStage = stage; process.exitCode = 1;
} finally {
  await browser?.close().catch(() => {});
  if (outputPath) { await mkdir(dirname(outputPath), { recursive: true }); await writeFile(outputPath, JSON.stringify(result, null, 2) + '\n'); }
  process.stdout.write(result.passed ? 'PASS_REAL_C_HTTPS_UI\n' : `FAIL_REAL_C_HTTPS_UI ${stage}\n`);
}
