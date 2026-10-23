export const LABELS = Object.freeze({
  PENDING: '待处理', PROCESSING: '处理中', ENDED: '已结束', ACCEPTED: '申诉通过', REJECTED: '申诉未通过',
  REVIEWER: '审核员', ADMIN: '管理员', NONE: '无管理权限', DISMISS: '未发现违规',
  TAKEDOWN: '内容下架', MUTE: '账号禁言', BAN: '账号封禁', ACTIVE: '正常', CLOSED: '已注销',
  UPHELD: '举报成立', DISMISSED: '未发现违规', TARGET_DELETED: '内容已删除，本次举报已结束', RESET_NICKNAME: '重置违规昵称', RESET_AVATAR: '重置违规头像',
  CLAIM: '开始审核', REVERSED: '原处理已撤销', REVOKE: '撤销处罚', 'APPEAL-DECISION': '申诉复核', ROLE: '变更管理权限',
  ADVERTISING: '广告引流', HARASSMENT: '辱骂骚扰', PRIVACY: '泄露隐私', FRAUD: '诈骗', ILLEGAL: '色情或违法内容', OTHER: '其他',
});
export const label = value => LABELS[value] ?? String(value ?? '—');
export const platformNumber = value => /^\d{6}$/.test(value ?? '') ? value : '—';
export const validUUID = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
export function requireUUID(value) { if (!validUUID(value)) throw new Error('资源编号无效，请重新加载。'); return value; }
export function dateText(value) { if (!value) return '—'; const date = new Date(value); return Number.isNaN(date.valueOf()) ? '时间待核对' : date.toLocaleString('zh-CN', { hour12: false }); }
export function imageSource(value) {
  if (!value || !['image/png', 'image/jpeg', 'image/webp', 'image/gif'].includes(value.mime) || typeof value.base64 !== 'string' || value.base64.length > 16 * 1024 * 1024 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value.base64) || !value.base64.length) return null;
  return `data:${value.mime};base64,${value.base64}`;
}
export function recoveryEstimate(sanctions, action, days, now = Date.now()) {
  const end = action === 'BAN' && Number(days) === 0 ? Infinity : now + Number(days) * 86400000;
  const until = kinds => sanctions.filter(s => !s.revokedAt && kinds.includes(s.action)).reduce((max, s) => {
    const at = s.endsAt ? Date.parse(s.endsAt) : Infinity;
    return !Number.isNaN(at) && at > now ? Math.max(max, at) : max;
  }, kinds.includes(action) ? end : now);
  const describe = at => at === Infinity ? '永久，须经授权解除' : at <= now ? '无有效限制' : dateText(at);
  return { community: describe(until(['BAN'])), speaking: describe(until(['BAN', 'MUTE'])) };
}
export function canReviewAppeal(me, appeal) { return (me.role === 'ADMIN' || (me.role === 'REVIEWER' && appeal.action !== 'BAN')) && me.platformNumber !== appeal.originalActorNumber && !['ACCEPTED', 'REJECTED', 'ENDED'].includes(appeal.state); }
export function canRevoke(me, sanction) { return !sanction.revokedAt && (me.role === 'ADMIN' || (me.role === 'REVIEWER' && sanction.action !== 'BAN')) && me.platformNumber !== sanction.actorNumber; }
export class APIError extends Error {
  constructor(status, code) { super(status === 0 ? '操作结果尚未确认。请保留本页，使用原操作重试核对。' : ({ 400: '输入格式不正确，请检查后重试。', 401: '登录已失效，请重新登录。', 403: '当前账号无此操作权限，或账号状态已改变。', 404: '记录不存在或当前不可访问。', 409: '记录已被处理或状态已变化，请重新加载核对。', 422: '输入不符合要求，请检查原因和期限。', 429: '操作过于频繁，请稍后重试。', 503: '服务暂不可用，操作结果可能尚未确认。请使用原操作核对。' }[status] ?? '服务暂时无法完成操作，请稍后核对。')); this.status = status; this.code = code; }
}
export function encodeBytes(bytes) { return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', ''); }
export function decodeToken(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(value)) throw new Error('登录响应无效。');
  const bytes = Uint8Array.from(atob(value.replaceAll('-', '+').replaceAll('_', '/') + '='), c => c.charCodeAt(0));
  if (bytes.length !== 32 || encodeBytes(bytes) !== value) throw new Error('登录响应无效。');
  return bytes;
}
export async function revokeSecret(token, cryptoAPI = globalThis.crypto) {
  const domain = new TextEncoder().encode('HNUHOLE/SESSION-REVOKE/V1\0');
  const input = new Uint8Array(domain.length + 32); input.set(domain); input.set(decodeToken(token), domain.length);
  return encodeBytes(new Uint8Array(await cryptoAPI.subtle.digest('SHA-256', input)));
}
export function createClient({ fetcher = globalThis.fetch, cryptoAPI = globalThis.crypto, onExpired = () => {} } = {}) {
  let token = null, generation = 0;
  const pending = new Map();
  const revocations = new Set();
  const random = length => encodeBytes(cryptoAPI.getRandomValues(new Uint8Array(length)));
  async function send(path, { method = 'GET', body, headers = {} } = {}) {
    if (!path.startsWith('/api/v1/') || path.includes('..') || path.includes('#')) throw new Error('请求地址无效。');
    let response;
    const controller = new AbortController(); const deadline = setTimeout(() => controller.abort(), 30000);
    try { response = await fetcher(path, { method, signal: controller.signal, mode: 'same-origin', credentials: 'omit', cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer', headers: { Accept: 'application/json', ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...headers }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) }); }
    catch { throw new APIError(0, 'UNKNOWN'); }
    finally { clearTimeout(deadline); }
    const result = response.status === 204 ? null : await response.json().catch(() => null);
    if (!response.ok) throw new APIError(response.status, result?.error?.code ?? result?.code ?? 'REQUEST_FAILED');
    if (response.status !== 204 && (!result || typeof result !== 'object')) throw new APIError(0, 'INVALID_RESPONSE');
    return result;
  }
  async function request(path, options = {}) {
    if (!token) throw new APIError(401, 'SESSION_INVALID');
    const active = generation;
    try {
      const result = await send(path, { ...options, headers: { ...options.headers, Authorization: `Bearer ${token}` } });
      if (generation !== active) throw new APIError(401, 'SESSION_CHANGED');
      return result;
    } catch (error) {
      if (generation === active && error.status === 401) { token = null; generation++; pending.clear(); onExpired(); }
      throw error;
    }
  }
  async function finishLogouts() {
    for (const secret of revocations) { await send('/api/v1/auth/session-revocations', { method: 'POST', headers: { Authorization: `SessionRevoke ${secret}` } }); revocations.delete(secret); }
  }
  async function logout() {
    const old = token; token = null; generation++; pending.clear();
    if (old) revocations.add(await revokeSecret(old, cryptoAPI));
    await finishLogouts();
  }
  return {
    async login(username, password) {
      token = null; generation++; pending.clear();
      const active = generation;
      await finishLogouts();
      const session = await send('/api/v1/auth/sessions', { method: 'POST', body: { username, password, installationId: random(16) }, headers: { 'Idempotency-Key': random(32) } });
      decodeToken(session.sessionToken);
      if (generation !== active) throw new APIError(401, 'SESSION_CHANGED');
      token = session.sessionToken;
      try {
        const me = await request('/api/v1/moderation/me');
        if (!['REVIEWER', 'ADMIN'].includes(me.role) || !/^\d{6}$/.test(me.platformNumber ?? '')) throw new APIError(403, 'ROLE_REQUIRED');
        return { role: me.role, platformNumber: me.platformNumber };
      } catch (error) { if (generation === active) await logout().catch(() => {}); throw error; }
    },
    request, logout,
    async command(path, body, method = 'POST') {
      const fingerprint = JSON.stringify(body);
      const prior = pending.get(path);
      if (prior && prior.fingerprint !== fingerprint) throw new Error('上次操作结果尚待核对，请保持原选项和原因重试，或先重新加载记录。');
      const intent = prior ?? { fingerprint, commandId: cryptoAPI.randomUUID() };
      pending.set(path, intent);
      try { const result = await request(path, { method, body: { commandId: intent.commandId, ...body } }); pending.delete(path); return result; }
      catch (error) { if (error.status >= 400 && error.status < 500) pending.delete(path); throw error; }
    },
  };
}

export function caseActions(record, role) {
  const dm = Boolean(record.conversationId);
  return [['DISMISS', '未发现违规，结束案件'], ...(dm ? [] : [['TAKEDOWN', '下架本案内容'], ['RESET_NICKNAME', '重置本案身份的违规昵称'], ['RESET_AVATAR', '重置本案身份的违规头像']]), ['MUTE', dm ? '限时禁言' : '下架并限时禁言'], ...(role === 'ADMIN' ? [['BAN', dm ? '封禁账号' : '下架并封禁账号']] : [])];
}
