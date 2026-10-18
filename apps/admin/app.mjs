import { canRevoke, canReviewAppeal, createClient, dateText, imageSource, label, platformNumber, recoveryEstimate, requireUUID } from './core.mjs';

const content = document.getElementById('content');
const sessionBox = document.getElementById('session');
const notice = document.getElementById('notice');
let me = null, page = 'cases', viewVersion = 0, inputNumber = 0;
const client = createClient({ onExpired: () => { me = null; viewVersion++; renderLogin(); } });

function el(tag, text, className) {
  const node = document.createElement(tag);
  if (text !== undefined && text !== null) node.textContent = String(text);
  if (className) node.className = className;
  return node;
}
function add(parent, ...children) { parent.append(...children.filter(Boolean)); return parent; }
function button(text, action, className) {
  const node = el('button', text, className); node.type = 'button'; node.addEventListener('click', action); return node;
}
function announce(message = '', error = false) {
  notice.textContent = message; notice.className = error ? 'notice error' : 'notice'; notice.hidden = !message;
  notice.setAttribute('role', error ? 'alert' : 'status');
}
function showError(error) { announce(error instanceof Error ? error.message : '暂时无法完成，请重新加载。', true); }
function field(title, control, helper) {
  const wrapper = el('div', null, 'field');
  control.id = `field-${++inputNumber}`;
  const caption = el('label', title); caption.htmlFor = control.id; add(wrapper, caption, control);
  if (helper) { const help = el('p', helper, 'helper'); help.id = `${control.id}-help`; control.setAttribute('aria-describedby', help.id); wrapper.append(help); }
  return wrapper;
}
function input(type = 'text') { const node = el('input'); node.type = type; return node; }
function select(options) {
  const node = el('select'); for (const [value, text] of options) { const option = el('option', text); option.value = value; node.append(option); } return node;
}
function reasonInput() { const node = el('textarea'); node.required = true; node.maxLength = 500; return node; }
function status(value) { return el('span', label(value), `status${['ENDED', 'ACCEPTED', 'REJECTED'].includes(value) ? ' ended' : ''}`); }
function section(title) { return add(el('section', null, 'section'), el('h2', title)); }
function materialImages(parent, images, prefix) {
  if (!Array.isArray(images) || !images.length) return;
  const group = el('div', null, 'images');
  images.forEach((item, index) => {
    const source = imageSource(item);
    if (!source) { group.append(el('p', '图片格式不可展示，请核对授权材料。', 'muted')); return; }
    const image = el('img'); image.src = source; image.alt = `${prefix} ${index + 1}`; image.loading = 'lazy'; image.decoding = 'async';
    // Only validated raster data URLs are accepted. No server-provided link is followed.
    const preview = button('', () => {
      const dialog = el('dialog', null, 'image-dialog'); const original = el('img'); original.src = source; original.alt = `${prefix} ${index + 1}原图`;
      const close = button('关闭图片', () => dialog.close()); add(dialog, close, original); document.body.append(dialog);
      dialog.addEventListener('close', () => dialog.remove(), { once: true }); dialog.showModal();
    }, 'image-button'); preview.setAttribute('aria-label', `查看${prefix} ${index + 1}原图`); preview.append(image); group.append(preview);
  }); parent.append(group);
}
function applyBusy(form, busy) {
  form.setAttribute('aria-busy', String(busy));
  for (const node of form.querySelectorAll('button, input, select, textarea')) node.disabled = busy;
}
function watchForm(form, handler) {
  let busy = false;
  form.addEventListener('submit', async event => {
    event.preventDefault(); if (busy || !form.reportValidity()) return;
    busy = true; applyBusy(form, true); announce();
    try { await handler(); } catch (error) { showError(error); }
    finally { busy = false; applyBusy(form, false); }
  });
}
function clearSession() { me = null; viewVersion++; sessionBox.replaceChildren(); content.replaceChildren(); }
async function logout() {
  clearSession(); announce(); renderLogin();
  const current = viewVersion;
  try { await client.logout(); if (current === viewVersion) announce('已退出。'); }
  catch { if (current === viewVersion) { announce('本页登录信息已清除，服务器退出结果尚待确认。请保留本页并点击“重新确认退出”。', true); sessionBox.append(button('重新确认退出', retryLogout)); } }
}
async function retryLogout() {
  // The client retains only a logout capability after clearing its bearer.
  try { await client.logout(); announce('服务器已确认退出。'); sessionBox.replaceChildren(); }
  catch (error) { showError(error); }
}
function renderLogin() {
  sessionBox.replaceChildren();
  const box = el('section', null, 'login');
  add(box, el('h1', '进入审核工作台'), el('p', '使用已获授权的社区管理账号登录。', 'muted'));
  const form = el('form'); const username = input(); username.required = true; username.autocomplete = 'username'; username.minLength = 6; username.maxLength = 24; username.pattern = '[a-z][a-z0-9_]{5,23}';
  const password = input('password'); password.required = true; password.autocomplete = 'current-password'; password.maxLength = 1024;
  const submit = el('button', '登录', 'primary full'); submit.type = 'submit';
  add(form, field('用户名', username), field('密码', password), submit);
  add(box, form, el('p', '本页关闭或刷新后需重新登录。请使用专用管理账号。', 'helper'));
  const secure = location.protocol === 'https:' && globalThis.crypto?.subtle;
  if (!secure) { submit.disabled = true; box.append(el('p', '请通过本站 HTTPS 地址打开工作台。', 'warning')); }
  watchForm(form, async () => {
    const current = ++viewVersion;
    try { const identity = await client.login(username.value, password.value); if (current !== viewVersion) return; me = identity; password.value = ''; page = 'cases'; announce(); renderWorkbench(); }
    finally { password.value = ''; }
  }); content.replaceChildren(box);
}
function renderWorkbench() {
  viewVersion++;
  sessionBox.replaceChildren(el('span', `${label(me.role)} ${platformNumber(me.platformNumber)}`), button('退出', logout));
  const names = { cases: '举报案件', appeals: '申诉复核', accounts: '账号与处罚', roles: '权限管理' };
  const heading = add(el('div', null, 'heading'), add(el('div'), el('h1', names[page]), el('p', '依据授权证据作出处理，每次操作均保留记录。', 'muted')));
  const tabs = el('nav', null, 'tabs'); tabs.setAttribute('aria-label', '审核工作区');
  for (const [key, text] of Object.entries(names)) {
    if (key === 'roles' && me.role !== 'ADMIN') continue;
    const tab = button(text, () => { page = key; announce(); renderWorkbench(); }, page === key ? 'current' : '');
    if (page === key) tab.setAttribute('aria-current', 'page'); tabs.append(tab);
  }
  const body = el('div'); content.replaceChildren(heading, tabs, body);
  if (page === 'cases' || page === 'appeals') renderQueue(body, page); else if (page === 'accounts') renderAccounts(body); else renderRoles(body);
}
function renderQueue(parent, kind) {
  const current = viewVersion;
  const workspace = el('div', null, 'workspace'); const queue = el('aside', null, 'queue');
  const list = el('div', null, 'queue-list'); const detail = el('article', null, 'detail');
  detail.append(el('p', kind === 'cases' ? '从左侧选择案件，核查举报时的内容和材料。' : '从左侧选择申诉，核对原处罚及本次材料。', 'empty'));
  const refresh = button('刷新', () => load(false));
  add(queue, add(el('div', null, 'queue-head'), el('h2', kind === 'cases' ? '案件列表' : '待复核申诉'), refresh), list);
  add(workspace, queue, detail); parent.append(workspace);
  let nextBefore = null, items = [], selected = null, requestVersion = 0;
  async function choose(item) {
    selected = item.id; const version = ++requestVersion;
    for (const row of list.querySelectorAll('button[data-record]')) row.setAttribute('aria-pressed', String(row.dataset.record === selected));
    detail.replaceChildren(el('p', '正在加载授权材料…', 'busy'));
    try {
      const record = await client.request(`/api/v1/moderation/${kind}/${requireUUID(item.id)}`);
      if (current !== viewVersion || version !== requestVersion) return;
      for (const row of list.querySelectorAll('button[data-record]')) {
        if (row.dataset.record === selected) row.querySelector('.status')?.replaceWith(status(record.state));
      }
      if (kind === 'cases') renderCase(detail, record, () => choose(item), current); else renderAppeal(detail, record, () => choose(item), current);
    } catch (error) { if (current === viewVersion && version === requestVersion) { detail.replaceChildren(el('p', '材料未加载，不能提交处理。', 'empty')); showError(error); } }
  }
  async function load(append) {
    refresh.disabled = true;
    if (!append) { list.replaceChildren(el('p', '正在加载…', 'busy')); items = []; nextBefore = null; }
    try {
      const query = new URLSearchParams({ limit: '50' }); if (append && nextBefore) query.set('before', nextBefore);
      const data = await client.request(`/api/v1/moderation/${kind}?${query}`);
      if (current !== viewVersion) return;
      items.push(...(Array.isArray(data.items) ? data.items : [])); nextBefore = data.nextBefore ?? null;
      list.replaceChildren();
      if (!items.length) list.append(el('p', kind === 'cases' ? '暂无举报案件。收到举报后会显示在这里。' : '暂无待复核申诉。', 'empty'));
      for (const item of items) {
        const row = button('', () => choose(item), 'queue-item'); row.dataset.record = item.id; row.setAttribute('aria-pressed', String(item.id === selected));
        add(row, status(item.state), el('strong', kind === 'cases' ? `工单 ${item.number ?? '待核对'}` : `申诉 ${item.ordinal ?? 1}/3`), el('div', kind === 'cases' ? label(item.reason) : `${label(item.action)} · ${platformNumber(item.platformNumber)}`, 'meta'), el('div', dateText(item.createdAt), 'meta')); list.append(row);
      }
      if (nextBefore) list.append(button('加载更早记录', () => load(true), 'pager'));
    } catch (error) { if (current === viewVersion) { list.replaceChildren(button('加载失败，点击重试', () => load(false), 'pager')); showError(error); } }
    finally { refresh.disabled = false; }
  }
  void load(false);
}
function renderCase(parent, record, reload, current) {
  parent.replaceChildren();
  const header = add(el('div', null, 'heading'), add(el('div'), el('h2', `工单 ${record.number ?? '待核对'}`), el('p', `目标账号 ${platformNumber(record.platformNumber)} · ${dateText(record.createdAt)}`, 'meta')), status(record.state));
  parent.append(header);
  const evidence = section('举报时的内容');
  const snapshot = add(el('div', null, 'evidence'), el('h3', record.evidence?.title ?? '帖子'), el('p', record.evidence?.body ?? '暂无可展示的文字材料。', 'body'));
  materialImages(snapshot, record.evidence?.images, '内容证据'); evidence.append(snapshot); parent.append(evidence);
  const reports = section('举报材料');
  for (const report of record.reports ?? []) {
    const group = add(el('div', null, 'report'), el('h3', label(report.reason)), el('p', report.description || '未补充说明。'), el('p', dateText(report.createdAt), 'meta'));
    materialImages(group, report.images, '举报补充图片'); reports.append(group);
  }
  if (!record.reports?.length) reports.append(el('p', '暂无补充材料。', 'muted'));
  parent.append(reports);
  if (record.state === 'ENDED') {
    parent.append(add(el('div', null, 'result'), el('h3', label(record.outcome ?? '已结束')), el('p', record.explanation ?? '请查看操作记录。')));
  } else {
    const controls = section('处理案件');
    if (record.state === 'PENDING') controls.append(button('开始处理', async () => {
      try { await client.command(`/api/v1/moderation/cases/${requireUUID(record.id)}/claim`, { expectedVersion: record.version }); if (current === viewVersion) { announce('已进入处理状态。'); await reload(); } }
      catch (error) { if (current === viewVersion) showError(error); }
    }, 'primary'));
    else controls.append(el('p', '核查材料后选择处理措施，并说明依据。', 'muted'));
    const form = el('form', null, 'inline-form');
    const action = select([['DISMISS', '未发现违规，结束案件'], ['TAKEDOWN', '下架本案帖子'], ['MUTE', '下架并限时禁言'], ...(me.role === 'ADMIN' ? [['BAN', '下架并封禁账号']] : [])]);
    const days = select([['1', '1 天'], ['3', '3 天'], ['7', '7 天'], ['30', '30 天']]); days.value = '3';
    const period = field('本次期限', days); const why = reasonInput();
    const estimate = el('p', null, 'helper'); const effect = el('p', null, 'warning');
    const submit = el('button', '确认处理', 'primary'); submit.type = 'submit';
    let sanctions = record.sanctions ?? [];
    let estimateReady = false;
    function update() {
      const timed = ['MUTE', 'BAN'].includes(action.value); period.hidden = !timed;
      if (action.value === 'BAN' && ![...days.options].some(o => o.value === '0')) { const forever = el('option', '永久'); forever.value = '0'; days.append(forever); }
      if (action.value !== 'BAN') { if (days.value === '0') days.value = '3'; [...days.options].find(o => o.value === '0')?.remove(); }
      effect.hidden = !timed;
      effect.textContent = action.value === 'BAN' ? '封禁后保留处罚通知与申诉入口，其余社区功能暂停；本案帖子同时下架。' : '禁言对账号全部身份生效，暂停发帖、评论、编辑、私信和点赞；本案帖子同时下架。';
      estimate.hidden = !timed;
      const result = recoveryEstimate(sanctions, action.value, Number(days.value));
      estimate.textContent = estimateReady ? `考虑现有处罚：社区访问预计恢复 ${result.community}；发言权限预计恢复 ${result.speaking}。以服务端实际提交时刻为准，各项处罚独立计时。` : '正在核对现有处罚，核对完成前不能提交账号处罚。';
      submit.disabled = timed && !estimateReady;
    }
    action.addEventListener('change', update); days.addEventListener('change', update);
    add(form, field('处理措施', action), period, effect, estimate, field('处理原因', why, '说明事实与处理依据。结果将发送给相关用户，不能包含举报人信息。'), submit);
    watchForm(form, async () => {
      if (['MUTE', 'BAN'].includes(action.value) && !estimateReady) throw new Error('请先核对现有处罚。');
      if (!why.value.trim()) { why.focus(); throw new Error('请填写处理原因。'); }
      await client.command(`/api/v1/moderation/cases/${requireUUID(record.id)}/decision`, { expectedVersion: record.version, action: action.value, days: ['MUTE', 'BAN'].includes(action.value) ? Number(days.value) : 0, reason: why.value.trim() });
      if (current === viewVersion) { announce('案件已处理。'); await reload(); }
    }); controls.append(form); parent.append(controls); update();
    void client.request(`/api/v1/moderation/accounts?number=${encodeURIComponent(record.platformNumber ?? '')}`).then(data => {
      if (current !== viewVersion || !parent.contains(form)) return;
      const account = data.items?.find(item => item.platformNumber === record.platformNumber);
      if (!account) throw new Error('未取得目标账号的处罚记录。'); sanctions = account.sanctions ?? []; estimateReady = true; update();
    }).catch(() => { if (current === viewVersion && parent.contains(form)) { estimate.textContent = '无法核对现有处罚，请重新加载案件后再提交账号处罚。'; estimateReady = false; } });
  }
  const audit = section('操作记录'); audit.append(el('p', '正在加载…', 'muted')); parent.append(audit);
  void loadAudit(audit, record.id, current);
}
async function loadAudit(parent, caseId, current) {
  try {
    const data = await client.request(`/api/v1/moderation/audit?caseId=${requireUUID(caseId)}`);
    if (current !== viewVersion || !parent.isConnected) return;
    parent.replaceChildren(el('h2', '操作记录'));
    for (const event of data.items ?? []) parent.append(add(el('div', null, 'audit'), el('strong', `${label(event.action)} · 操作人 ${platformNumber(event.actorNumber)}`), el('p', event.reason ?? ''), el('p', `${dateText(event.createdAt)} · 目标 ${platformNumber(event.targetNumber)}`, 'meta')));
    if (!data.items?.length) parent.append(el('p', '暂无操作记录。', 'muted'));
  } catch { if (current === viewVersion && parent.isConnected) parent.append(el('p', '操作记录暂未加载，可重新选择本案重试。', 'muted')); }
}
function renderAppeal(parent, appeal, reload, current) {
  parent.replaceChildren(add(el('div', null, 'heading'), add(el('div'), el('h2', `申诉 ${appeal.ordinal ?? 1}/3`), el('p', `目标账号 ${platformNumber(appeal.platformNumber)} · ${label(appeal.action)}`, 'meta')), status(appeal.state)));
  const materials = section('本次申诉材料');
  for (const material of appeal.materials ?? []) {
    const group = add(el('div', null, 'report'), el('p', material.description ?? material.text ?? material.body ?? '未补充文字。'), el('p', dateText(material.createdAt), 'meta')); materialImages(group, material.images, '申诉图片'); materials.append(group);
  }
  if (!appeal.materials?.length) materials.append(el('p', '暂无可展示材料。', 'muted'));
  parent.append(materials);
  if (appeal.explanation) parent.append(add(el('div', null, 'result'), el('p', appeal.explanation)));
  if (canReviewAppeal(me, appeal)) {
    const controls = section('独立复核'); const form = el('form', null, 'inline-form'); const decision = select([['false', '维持本次处罚'], ['true', '申诉通过，撤销对应处罚']]); const why = reasonInput();
    const submit = el('button', '确认复核结果', 'primary'); submit.type = 'submit';
    add(form, field('复核结果', decision), field('复核理由', why), el('p', '通过后只撤销对应处罚；作者已主动删除或仍有其他下架原因的内容不恢复。', 'helper'), submit);
    watchForm(form, async () => {
      if (!why.value.trim()) throw new Error('请填写复核理由。');
      await client.command(`/api/v1/moderation/appeals/${requireUUID(appeal.id)}/decision`, { expectedVersion: appeal.version, accept: decision.value === 'true', reason: why.value.trim() });
      if (current === viewVersion) { announce('复核结果已保存。'); await reload(); }
    }); add(controls, form); parent.append(controls);
  } else if (!['ACCEPTED', 'REJECTED', 'ENDED'].includes(appeal.state)) parent.append(el('p', me.platformNumber === appeal.originalActorNumber ? '你是原处理人，本次申诉须由另一名有相应权限的人员复核。' : '当前角色无权复核本项处罚。申诉继续保留待复核。', 'warning'));
  if (appeal.caseId) parent.append(button('查看原案件与证据', async () => {
    try { const record = await client.request(`/api/v1/moderation/cases/${requireUUID(appeal.caseId)}`); if (current === viewVersion) { renderCase(parent, record, async () => {}, current); parent.prepend(button('返回申诉', reload)); } }
    catch (error) { if (current === viewVersion) showError(error); }
  }));
}
function renderAccounts(parent) {
  const current = viewVersion; const search = el('form', null, 'search'); const number = input(); number.inputMode = 'numeric'; number.pattern = '[0-9]{6}'; number.maxLength = 6; number.required = true;
  const submit = el('button', '查找账号', 'primary'); submit.type = 'submit'; add(search, field('六位平台编号', number), submit); const results = el('div'); add(parent, search, results);
  async function loadAccounts() {
    const data = await client.request(`/api/v1/moderation/accounts?number=${encodeURIComponent(number.value)}`); if (current !== viewVersion) return;
    results.replaceChildren(); if (!data.items?.length) results.append(el('p', '未找到可访问的账号。', 'empty'));
    for (const account of data.items ?? []) {
      const box = add(el('article', null, 'account'), el('h2', `账号 ${platformNumber(account.platformNumber)}`), add(el('div', null, 'summary'), el('span', `状态：${label(account.state)}`), el('span', `已确认违规：${Number.isInteger(account.violationCount) ? account.violationCount : '—'}`), el('span', `注册：${dateText(account.createdAt)}`)));
      box.append(el('h3', '处罚记录', 'section'));
      for (const sanction of account.sanctions ?? []) {
        const row = add(el('section', null, 'sanction'), el('strong', label(sanction.action)), el('p', sanction.reason ?? ''), el('p', `${dateText(sanction.startsAt)} 至 ${sanction.endsAt ? dateText(sanction.endsAt) : '永久'}${sanction.revokedAt ? ` · 已撤销 ${dateText(sanction.revokedAt)}` : ''}`, 'meta'));
        if (canRevoke(me, sanction)) {
          const form = el('form', null, 'inline-form'); const why = reasonInput(); const revoke = el('button', '撤销此项处罚', 'danger'); revoke.type = 'submit'; add(form, field('撤销原因', why), revoke);
          watchForm(form, async () => { if (!why.value.trim()) throw new Error('请填写撤销原因。'); await client.command(`/api/v1/moderation/sanctions/${requireUUID(sanction.id)}/revoke`, { reason: why.value.trim() }); if (current === viewVersion) { await loadAccounts(); announce('已撤销此项处罚，其他有效处罚继续执行。'); } }); row.append(form);
        } else if (!sanction.revokedAt && me.platformNumber === sanction.actorNumber) row.append(el('p', '此项由你作出，撤销须由另一名有相应权限的人员处理。', 'helper'));
        box.append(row);
      }
      if (!account.sanctions?.length) box.append(el('p', '暂无处罚记录。', 'muted')); results.append(box);
    }
  }
  watchForm(search, loadAccounts);
}
function renderRoles(parent) {
  if (me.role !== 'ADMIN') { parent.append(el('p', '仅管理员可管理权限。', 'empty')); return; }
  const current = viewVersion;
  const form = el('form', null, 'inline-form'); const number = input(); number.inputMode = 'numeric'; number.pattern = '[0-9]{6}'; number.maxLength = 6; number.required = true;
  const role = select([['REVIEWER', '审核员'], ['ADMIN', '管理员'], ['NONE', '撤销管理权限']]); const why = reasonInput(); const submit = el('button', '保存权限变更', 'primary'); submit.type = 'submit';
  add(form, field('目标平台编号', number), field('管理角色', role), field('变更原因', why), el('p', '审核员负责案件、下架及限时禁言；管理员额外负责封禁、解封和权限管理。', 'helper'), submit);
  watchForm(form, async () => { if (!why.value.trim()) throw new Error('请填写变更原因。'); await client.command(`/api/v1/moderation/roles/${number.value}`, { role: role.value, reason: why.value.trim() }, 'PUT'); if (current === viewVersion) { announce(`已更新账号 ${number.value} 的管理权限。`); if (number.value === me.platformNumber) { const identity = await client.request('/api/v1/moderation/me'); me = { role: identity.role, platformNumber: identity.platformNumber }; if (!['ADMIN', 'REVIEWER'].includes(me.role)) await logout(); else renderWorkbench(); } } }); parent.append(form);
}

renderLogin();
