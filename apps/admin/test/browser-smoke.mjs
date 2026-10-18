// Synthetic HTTPS UI fixture only. This does not replace real C / PostgreSQL integration.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createServer } from 'node:https';
import { execFileSync } from 'node:child_process';
import { readFile, writeFile, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { encodeBytes } from '../core.mjs';

if (!process.env.PLAYWRIGHT_MODULE || !process.env.ADMIN_UI_TEST_ROOT) throw new Error('Set PLAYWRIGHT_MODULE and an isolated ADMIN_UI_TEST_ROOT. Optional: ADMIN_UI_BROWSER and OPENSSL_BIN.');
const { chromium } = createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE);
const root = resolve(process.env.ADMIN_UI_TEST_ROOT); await mkdir(root, { recursive: true });
const temporary = await mkdtemp(join(root, 'fixture-'));
const caseId = '10000000-0000-4000-8000-000000000001';
const appealId = '20000000-0000-4000-8000-000000000001';
const sanctionId = '30000000-0000-4000-8000-000000000001';
const token = encodeBytes(new Uint8Array(32).fill(13));
const stamp = '2026-10-18T04:30:00Z';
const hostile = '<img src=x onerror="window.evidenceExecuted=true">';
const raster = { mime: 'image/png', base64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5mQAAAAASUVORK5CYII=' };
let role = 'REVIEWER', state = 'PENDING', version = 1, appealState = 'PENDING', revoked = false;
const commands = [], errors = [], requests = [];
const record = () => ({ id: caseId, number: 'R202610180001', postId: '40000000-0000-4000-8000-000000000001', platformNumber: '000125', reason: 'HARASSMENT', state, version, createdAt: stamp, outcome: state === 'ENDED' ? 'MUTE' : null, explanation: '已核查证据。', evidence: { title: '校园讨论中的违规内容', body: hostile, images: [raster] }, reports: [{ reason: 'HARASSMENT', description: '说明仅用于核查本案。', images: [], createdAt: stamp }], sanctions: [] });
const appeal = () => ({ id: appealId, caseId, sanctionId, state: appealState, ordinal: 1, version: 1, platformNumber: '000125', action: 'MUTE', originalActorNumber: '000999', createdAt: stamp, materials: [{ description: '请结合原帖重新核查。', createdAt: stamp, images: [] }] });
const sanctions = () => [{ id: sanctionId, action: 'MUTE', reason: '已确认违规。', actorNumber: '000999', startsAt: stamp, endsAt: '2026-10-21T04:30:00Z', revokedAt: revoked ? stamp : null }];
let server, browser;
try {
  await writeFile(join(temporary, 'openssl.cnf'), '[req]\ndistinguished_name=dn\nx509_extensions=v3\nprompt=no\n[dn]\nCN=localhost\n[v3]\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n');
  execFileSync(process.env.OPENSSL_BIN || 'openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-config', join(temporary, 'openssl.cnf'), '-keyout', join(temporary, 'key.pem'), '-out', join(temporary, 'cert.pem'), '-days', '1'], { stdio: 'ignore' });
  const assets = new Map([['/admin', ['index.html', 'text/html']], ['/admin/', ['index.html', 'text/html']], ['/admin/app.mjs', ['app.mjs', 'text/javascript']], ['/admin/core.mjs', ['core.mjs', 'text/javascript']], ['/admin/styles.css', ['styles.css', 'text/css']]]);
  server = createServer({ key: await readFile(join(temporary, 'key.pem')), cert: await readFile(join(temporary, 'cert.pem')) }, async (req, res) => {
    try {
      const url = new URL(req.url, 'https://localhost');
      if (assets.has(url.pathname)) {
        const [file, mime] = assets.get(url.pathname); res.writeHead(200, { 'Content-Type': `${mime}; charset=utf-8`, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': "frame-ancestors 'none'" }); res.end(await readFile(new URL(`../${file}`, import.meta.url))); return;
      }
      let body = ''; for await (const chunk of req) body += chunk; const payload = body ? JSON.parse(body) : {};
      const respond = (value, status = 200) => { res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(status === 204 ? undefined : JSON.stringify(value)); };
      if (url.pathname === '/api/v1/auth/sessions') { role = payload.username === 'admin_test' ? 'ADMIN' : 'REVIEWER'; state = 'PENDING'; version = 1; respond({ sessionToken: token, accountId: 'PRIVATE-ACCOUNT-MAPPING', expiresAt: '2030-01-01T00:00:00Z' }, 201); return; }
      if (url.pathname === '/api/v1/auth/session-revocations') { respond(null, 204); return; }
      if (url.pathname === '/api/v1/moderation/me') { respond({ role, platformNumber: '000123', email: 'PRIVATE-EMAIL', otherIdentities: ['PRIVATE-OTHER-MASK'] }); return; }
      if (url.pathname === '/api/v1/moderation/cases') { respond({ items: [record()] }); return; }
      if (url.pathname === `/api/v1/moderation/cases/${caseId}`) { respond(record()); return; }
      if (url.pathname.endsWith('/claim')) { state = 'PROCESSING'; version++; commands.push(payload); respond(record()); return; }
      if (url.pathname.endsWith(`/cases/${caseId}/decision`)) { state = 'ENDED'; version++; commands.push(payload); respond(record()); return; }
      if (url.pathname === '/api/v1/moderation/appeals') { respond({ items: [appeal()] }); return; }
      if (url.pathname === `/api/v1/moderation/appeals/${appealId}`) { respond(appeal()); return; }
      if (url.pathname.endsWith(`/appeals/${appealId}/decision`)) { appealState = payload.accept ? 'ACCEPTED' : 'REJECTED'; commands.push(payload); respond(appeal()); return; }
      if (url.pathname === '/api/v1/moderation/accounts') { respond({ items: [{ platformNumber: '000125', state: 'ACTIVE', createdAt: stamp, violationCount: 1, sanctions: sanctions() }] }); return; }
      if (url.pathname.endsWith('/revoke')) { revoked = true; commands.push(payload); respond(sanctions()[0]); return; }
      if (url.pathname === '/api/v1/moderation/audit') { respond({ items: [{ actorNumber: '000999', targetNumber: '000125', action: 'MUTE', reason: '已核查材料。', createdAt: stamp, caseId }] }); return; }
      if (url.pathname.startsWith('/api/v1/moderation/roles/')) { commands.push(payload); respond({ platformNumber: url.pathname.split('/').at(-1), role: payload.role }); return; }
      respond({}, 404);
    } catch { res.writeHead(500); res.end(); }
  });
  await new Promise(resolveListen => server.listen(0, '127.0.0.1', resolveListen));
  const origin = `https://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch({ executablePath: process.env.ADMIN_UI_BROWSER || undefined, headless: true });
  const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 1080 } });
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => requests.push(request.url()));
  await page.goto(`${origin}/admin`);
  await page.getByLabel('用户名', { exact: true }).fill('reviewer_test'); await page.getByLabel('密码', { exact: true }).fill('synthetic fixture password'); await page.getByRole('button', { name: '登录', exact: true }).click();
  await page.getByRole('button', { name: /工单 R202610180001/ }).click();
  await page.getByRole('heading', { name: '举报时的内容' }).waitFor();
  assert.equal(await page.locator('.body').textContent(), hostile); assert.equal(await page.locator('img[onerror]').count(), 0);
  assert.equal(await page.getByRole('button', { name: '权限管理', exact: true }).count(), 0);
  assert.equal(await page.getByLabel('处理措施', { exact: true }).locator('option[value="BAN"]').count(), 0);
  assert.doesNotMatch(await page.locator('body').innerText(), /PRIVATE-EMAIL|PRIVATE-ACCOUNT-MAPPING|PRIVATE-OTHER-MASK/);
  await page.getByRole('button', { name: '查看内容证据 1原图', exact: true }).click(); await page.getByRole('button', { name: '关闭图片', exact: true }).click();
  await page.getByRole('button', { name: '开始处理', exact: true }).click(); await page.getByText('已进入处理状态。', { exact: true }).waitFor();
  await page.getByLabel('处理措施', { exact: true }).selectOption('MUTE');
  await page.getByText(/考虑现有处罚/).waitFor(); await page.getByLabel('处理原因', { exact: true }).fill('根据本案证据作出三天禁言。');
  await page.screenshot({ path: join(root, 'reviewer-case.png'), fullPage: true });
  await page.getByRole('button', { name: '确认处理', exact: true }).click(); await page.getByText('案件已处理。', { exact: true }).waitFor();
  await page.getByRole('button', { name: '申诉复核', exact: true }).click(); await page.getByRole('button', { name: /申诉 1\/3/ }).click();
  await page.getByLabel('复核结果', { exact: true }).selectOption('true'); await page.getByLabel('复核理由', { exact: true }).fill('核查新材料后撤销对应处罚。'); await page.getByRole('button', { name: '确认复核结果', exact: true }).click(); await page.getByText('复核结果已保存。', { exact: true }).waitFor();
  await page.getByRole('button', { name: '账号与处罚', exact: true }).click(); await page.getByLabel('六位平台编号', { exact: true }).fill('000125'); await page.getByRole('button', { name: '查找账号', exact: true }).click();
  await page.getByLabel('撤销原因', { exact: true }).fill('独立核查后撤销。'); await page.getByRole('button', { name: '撤销此项处罚', exact: true }).click(); await page.getByText('已撤销此项处罚，其他有效处罚继续执行。', { exact: true }).waitFor();
  await page.getByRole('button', { name: '退出', exact: true }).click(); await page.getByRole('heading', { name: '进入审核工作台' }).waitFor();
  await page.getByLabel('用户名', { exact: true }).fill('admin_test'); await page.getByLabel('密码', { exact: true }).fill('synthetic fixture password'); await page.getByRole('button', { name: '登录', exact: true }).click();
  await page.getByRole('button', { name: /工单 R202610180001/ }).click(); await page.getByLabel('处理措施', { exact: true }).selectOption('BAN'); await page.getByLabel('本次期限', { exact: true }).selectOption('0');
  await page.getByText(/永久，须经授权解除/).waitFor(); await page.getByLabel('处理原因', { exact: true }).fill('管理员依据核查结果处理。');
  await page.screenshot({ path: join(root, 'admin-case.png'), fullPage: true });
  await page.getByRole('button', { name: '权限管理', exact: true }).click(); await page.getByLabel('目标平台编号', { exact: true }).fill('000126'); await page.getByLabel('变更原因', { exact: true }).fill('授权专用审核账号。'); await page.getByRole('button', { name: '保存权限变更', exact: true }).click(); await page.getByText('已更新账号 000126 的管理权限。', { exact: true }).waitFor();
  await page.setViewportSize({ width: 390, height: 844 }); await page.screenshot({ path: join(root, 'admin-narrow.png'), fullPage: true });
  assert.equal(await page.locator('html').evaluate(node => node.scrollWidth <= window.innerWidth), true);
  assert.equal(commands.some(c => c.action === 'MUTE' && c.days === 3), true); assert.equal(commands.some(c => c.accept === true), true); assert.equal(commands.some(c => c.role === 'REVIEWER'), true);
  assert.equal(commands.every(c => typeof c.commandId === 'string'), true); assert.equal(requests.every(url => url.startsWith(origin)), true); assert.deepEqual(errors, []);
  await page.getByRole('button', { name: '退出', exact: true }).click();
  console.log(JSON.stringify({ result: 'PASS_SYNTHETIC_HTTPS_UI', commands: commands.length, noExternalRequests: true, pageErrors: errors.length, screenshots: ['reviewer-case.png', 'admin-case.png', 'admin-narrow.png'] }));
} finally {
  await browser?.close(); await new Promise(resolveClose => server ? server.close(resolveClose) : resolveClose());
  const checked = resolve(temporary); if (!checked.startsWith(root + '\\') && !checked.startsWith(root + '/')) throw new Error('Temporary TLS cleanup escaped the test root.');
  await rm(checked, { recursive: true, force: true });
}
