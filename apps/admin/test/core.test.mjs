import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, webcrypto } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { caseActions, APIError, canRevoke, canReviewAppeal, createClient, decodeToken, encodeBytes, imageSource, platformNumber, recoveryEstimate, revokeSecret } from '../core.mjs';

const token = encodeBytes(new Uint8Array(32).fill(13));
const me = { role: 'REVIEWER', platformNumber: '000123' };
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const ok = () => new Response(null, { status: 204 });
function authenticated(extra = async () => json({})) {
  const calls = [];
  const client = createClient({ cryptoAPI: webcrypto, fetcher: async (path, init) => {
    calls.push({ path, init });
    if (path === '/api/v1/auth/sessions') return json({ accountId: 'must-not-display', sessionToken: token, expiresAt: '2026-11-01T00:00:00Z' }, 201);
    if (path === '/api/v1/moderation/me') return json({ ...me, username: 'private-login', email: 'must-not-display', otherIdentities: ['must-not-display'] });
    return extra(path, init);
  } }); return { client, calls };
}

test('real login contract and response allowlist keep account mapping out of UI state', async () => {
  const { client, calls } = authenticated();
  assert.deepEqual(await client.login('reviewer_a', 'private password phrase'), me);
  const request = calls[0]; const body = JSON.parse(request.init.body);
  assert.equal(request.path, '/api/v1/auth/sessions');
  assert.deepEqual(Object.keys(body).sort(), ['installationId', 'password', 'username']);
  assert.equal(body.installationId.length, 22);
  assert.equal(request.init.headers['Idempotency-Key'].length, 43);
  assert.equal(request.init.headers.Authorization, undefined);
  assert.equal(calls[1].init.headers.Authorization, `Bearer ${token}`);
  for (const { init } of calls) {
    assert.equal(init.credentials, 'omit'); assert.equal(init.mode, 'same-origin');
    assert.equal(init.redirect, 'error'); assert.equal(init.cache, 'no-store');
  }
});

test('only canonical 32-byte session tokens are accepted', () => {
  assert.equal(decodeToken(token).length, 32);
  assert.throws(() => decodeToken(token + '=')); assert.throws(() => decodeToken('A'.repeat(42)));
  assert.throws(() => decodeToken('A'.repeat(42) + 'B'));
});

test('logout uses existing one-way domain and retains only capability for retry', async () => {
  const expected = createHash('sha256').update('HNUHOLE/SESSION-REVOKE/V1\0').update(Buffer.alloc(32, 13)).digest('base64url');
  assert.equal(await revokeSecret(token, webcrypto), expected);
  let failures = 1;
  const { client, calls } = authenticated(async () => { if (failures--) throw new Error('transport down'); return ok(); });
  await client.login('reviewer_a', 'phrase');
  await assert.rejects(client.logout(), error => error.status === 0);
  await assert.rejects(client.request('/api/v1/moderation/me'), error => error.status === 401);
  await client.logout();
  const sent = calls.filter(c => c.path === '/api/v1/auth/session-revocations');
  assert.equal(sent.length, 2); assert.equal(sent[0].init.headers.Authorization, `SessionRevoke ${expected}`);
  assert.equal(sent[1].init.headers.Authorization, sent[0].init.headers.Authorization);
  assert.equal(sent[0].init.body, undefined);
});

test('unknown commands preserve UUID and payload; changed material cannot create a duplicate', async () => {
  let fail = true;
  const { client, calls } = authenticated(async () => { if (fail) { fail = false; throw new Error('lost response'); } return json({ state: 'ENDED' }); });
  await client.login('reviewer_a', 'phrase');
  const path = '/api/v1/moderation/cases/case-id/decision'; const body = { expectedVersion: 3, action: 'MUTE', days: 3, reason: '核查证据后处理' };
  await assert.rejects(client.command(path, body), error => error.status === 0);
  await assert.rejects(client.command(path, { ...body, days: 7 }), /上次操作结果尚待核对/);
  assert.deepEqual(await client.command(path, body), { state: 'ENDED' });
  const commands = calls.filter(c => c.path === path).map(c => JSON.parse(c.init.body));
  assert.equal(commands.length, 2); assert.deepEqual(commands[0], commands[1]);
  assert.match(commands[0].commandId, /^[0-9a-f-]{36}$/);
});

test('definitive concurrency conflict can be refreshed while server failure retains operation', async () => {
  let code = 503;
  const { client, calls } = authenticated(async () => json({ error: { code: 'STATE_CHANGED' } }, code));
  await client.login('reviewer_a', 'phrase');
  const path = '/api/v1/moderation/cases/item/decision'; const body = { expectedVersion: 1, reason: 'reason' };
  await assert.rejects(client.command(path, body), error => error.status === 503);
  code = 409; await assert.rejects(client.command(path, body), error => error.status === 409);
  code = 200; await client.command(path, { ...body, expectedVersion: 2 });
  const commands = calls.filter(c => c.path === path).map(c => JSON.parse(c.init.body));
  assert.equal(commands[0].commandId, commands[1].commandId); assert.notEqual(commands[1].commandId, commands[2].commandId);
});

test('session expiry discards authenticated state and late responses after logout are refused', async () => {
  let deliver; let expired = false;
  const client = createClient({ cryptoAPI: webcrypto, onExpired: () => { expired = true; }, fetcher: async path => {
    if (path === '/api/v1/auth/sessions') return json({ sessionToken: token }, 201);
    if (path === '/api/v1/moderation/me') return json(me);
    if (path === '/api/v1/auth/session-revocations') return ok();
    if (path.endsWith('/expired')) return json({}, 401);
    return new Promise(resolve => { deliver = resolve; });
  } });
  await client.login('reviewer', 'phrase'); await assert.rejects(client.request('/api/v1/expired'), e => e.status === 401); assert.equal(expired, true);
  await client.login('reviewer', 'phrase'); const late = client.request('/api/v1/moderation/cases'); await client.logout(); deliver(json({ items: ['private evidence'] }));
  await assert.rejects(late, e => e.status === 401);
});

test('pending old login cannot clear a newer session', async () => {
  let resolveOld, count = 0;
  const client = createClient({ cryptoAPI: webcrypto, fetcher: async path => {
    if (path === '/api/v1/auth/sessions') return json({ sessionToken: token }, 201);
    if (path === '/api/v1/moderation/me' && ++count === 1) return new Promise(resolve => { resolveOld = resolve; });
    return json(me);
  } });
  const old = client.login('first', 'phrase'); await new Promise(resolve => setTimeout(resolve, 0));
  await client.login('second', 'phrase'); resolveOld(json(me)); await assert.rejects(old, e => e.status === 401);
  assert.deepEqual(await client.request('/api/v1/moderation/me'), me);
});

test('role controls distinguish reviewer/admin and original decision actor', () => {
  const appeal = { state: 'PENDING', action: 'BAN', originalActorNumber: '000002' };
  assert.equal(canReviewAppeal(me, appeal), false);
  assert.equal(canReviewAppeal({ ...me, role: 'ADMIN' }, appeal), true);
  assert.equal(canReviewAppeal({ role: 'ADMIN', platformNumber: '000002' }, appeal), false);
  assert.equal(canReviewAppeal(me, { ...appeal, action: 'MUTE', state: 'ACCEPTED' }), false);
  assert.equal(canReviewAppeal(me, { ...appeal, action: 'MUTE' }), true);
  assert.equal(canRevoke(me, { action: 'BAN' }), false);
  assert.equal(canRevoke(me, { action: 'MUTE', actorNumber: me.platformNumber }), false);
});

test('overlapping sanctions use maximum end without concatenation and ignore revoked facts', () => {
  const now = Date.parse('2026-10-18T00:00:00Z');
  const existing = [{ action: 'MUTE', endsAt: '2026-10-21T00:00:00Z' }, { action: 'BAN', endsAt: null, revokedAt: '2026-10-17T00:00:00Z' }];
  const result = recoveryEstimate(existing, 'MUTE', 7, now);
  assert.equal(result.community, '无有效限制');
  assert.equal(result.speaking, new Date('2026-10-25T00:00:00Z').toLocaleString('zh-CN', { hour12: false }));
  assert.equal(recoveryEstimate(existing, 'BAN', 0, now).community, '永久，须经授权解除');
  assert.equal(recoveryEstimate([...existing, { action: 'BAN', endsAt: null }], 'MUTE', 1, now).speaking, '永久，须经授权解除');
});

test('raster evidence allowlist rejects executable images and untrusted links', () => {
  assert.equal(imageSource({ mime: 'image/png', base64: 'AQID' }), 'data:image/png;base64,AQID');
  for (const item of [{ mime: 'image/svg+xml', base64: 'PHN2Zz4=' }, { mime: 'text/html', base64: 'AQID' }, { mime: 'image/png', base64: 'javascript:alert(1)' }, { mime: 'image/png', base64: '' }]) assert.equal(imageSource(item), null);
  assert.equal(platformNumber('000123'), '000123'); assert.equal(platformNumber('account-uuid'), '—');
});

test('rendering and assets forbid HTML injection, persistent credentials, third parties and private DTO dumps', async () => {
  const app = await readFile(new URL('../app.mjs', import.meta.url), 'utf8');
  const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
  const css = await readFile(new URL('../styles.css', import.meta.url), 'utf8');
  assert.doesNotMatch(app, /innerHTML|outerHTML|insertAdjacentHTML|localStorage|sessionStorage|document\.cookie|console\./);
  assert.doesNotMatch(app, /JSON\.stringify|\.accountId|\.username|\.email|\.otherIdentities|\.slotId/);
  assert.doesNotMatch(html + css, /https?:\/\/|@import|\son\w+=/);
  assert.match(html, /Content-Security-Policy/); assert.match(app, /textContent/);
  assert.match(css, /focus-visible/); assert.match(html, /aria-live="polite"/);
});

test('transport cannot target another origin', async () => {
  const { client } = authenticated(); await client.login('reviewer', 'phrase');
  await assert.rejects(client.request('https://external.invalid/api/v1/me'), /请求地址无效/);
  await assert.rejects(client.request('/api/v1/../private'), /请求地址无效/);
  assert.ok(new APIError(403, 'DENIED').message.includes('权限'));
});

test('private message cases expose only actions supported by independent authorized evidence', () => {
  assert.deepEqual(caseActions({ conversationId: 'private' }, 'REVIEWER').map(x => x[0]), ['DISMISS', 'MUTE']);
  assert.deepEqual(caseActions({ conversationId: 'private' }, 'ADMIN').map(x => x[0]), ['DISMISS', 'MUTE', 'BAN']);
  assert(caseActions({}, 'REVIEWER').some(x => x[0] === 'TAKEDOWN'));
  assert(!caseActions({ conversationId: 'private' }, 'ADMIN').some(x => /下架/.test(x[1])));
});
