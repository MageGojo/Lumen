const DEFAULTS = {
  port: 8787,
  intercept: true,
  sniff: true,
  minSizeMB: 0,
  skipExt: 'm3u8,mpd',
};

const el = (id) => document.getElementById(id);
const saved = el('saved');

chrome.storage.sync.get(DEFAULTS, (s) => {
  el('intercept').checked = !!s.intercept;
  el('sniff').checked = !!s.sniff;
  el('port').value = s.port;
  el('minSizeMB').value = s.minSizeMB;
  el('skipExt').value = s.skipExt;
});

el('save').addEventListener('click', () => {
  const port = parseInt(el('port').value, 10);
  if (!port || port < 1024 || port > 65535) {
    saved.style.color = '#f43f5e';
    saved.textContent = '请输入 1024-65535 的端口';
    return;
  }
  let minSizeMB = parseInt(el('minSizeMB').value, 10);
  if (isNaN(minSizeMB) || minSizeMB < 0) minSizeMB = 0;

  const values = {
    port,
    intercept: el('intercept').checked,
    sniff: el('sniff').checked,
    minSizeMB,
    skipExt: el('skipExt').value.trim(),
  };
  chrome.storage.sync.set(values, () => {
    saved.style.color = '#38bdf8';
    saved.textContent = '已保存';
    setTimeout(() => (saved.textContent = ''), 2000);
  });
});

// ---- 下载记录(最近接管 / 发送) -------------------------------------------

const recToast = el('recToast');

function send(msg) {
  return new Promise((resolve) => chrome.runtime.sendMessage(msg, resolve));
}

function humanSize(bytes) {
  if (!bytes) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  let n = bytes;
  let i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  return `${n.toFixed(n >= 10 || i === 0 ? 0 : 1)} ${units[i]}`;
}

function nameOf(item) {
  if (item.name) return item.name;
  if (item.title) return item.title;
  try {
    const p = new URL(item.url).pathname.split('/').filter(Boolean).pop();
    if (p) return decodeURIComponent(p);
  } catch (e) {}
  return item.host || item.url;
}

function showRecToast(text) {
  recToast.textContent = text;
  clearTimeout(recToast._t);
  recToast._t = setTimeout(() => (recToast.textContent = ''), 2200);
}

function makeCard(item) {
  const card = document.createElement('div');
  card.className = 'card';

  const top = document.createElement('div');
  top.className = 'top';
  const badge = document.createElement('span');
  badge.className = 'badge';
  badge.textContent = item.kind || '下载';
  top.appendChild(badge);
  if (item.host) {
    const h = document.createElement('span');
    h.className = 'host';
    h.textContent = item.host;
    top.appendChild(h);
  }
  if (item.size) {
    const s = document.createElement('span');
    s.className = 'size';
    s.textContent = humanSize(item.size);
    top.appendChild(s);
  }
  card.appendChild(top);

  const nm = document.createElement('div');
  nm.className = 'nm';
  nm.textContent = nameOf(item);
  nm.title = item.url;
  card.appendChild(nm);

  const row = document.createElement('div');
  row.className = 'row';

  const resend = document.createElement('button');
  resend.textContent = '重新发送';
  resend.addEventListener('click', async () => {
    resend.disabled = true;
    resend.textContent = '发送中…';
    const res = await send({
      type: 'send',
      payload: { url: item.url, referer: item.referer, title: item.title || item.name, kind: item.kind },
    });
    resend.disabled = false;
    resend.textContent = '重新发送';
    showRecToast((res && res.message) || (res && res.ok ? '已发送' : '发送失败'));
  });

  const copy = document.createElement('button');
  copy.className = 'ghost';
  copy.textContent = '复制链接';
  copy.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(item.url);
      copy.textContent = '已复制';
      setTimeout(() => (copy.textContent = '复制链接'), 1400);
    } catch (e) {
      showRecToast('复制失败');
    }
  });

  row.appendChild(resend);
  row.appendChild(copy);
  card.appendChild(row);
  return card;
}

async function renderRecords() {
  const box = el('records');
  const { captures } = await chrome.storage.local.get({ captures: [] });
  box.innerHTML = '';
  if (!captures.length) {
    const empty = document.createElement('div');
    empty.className = 'recEmpty';
    empty.textContent = '还没有记录。开启接管后,在网页点下载就会出现在这里。';
    box.appendChild(empty);
    return;
  }
  for (const it of captures) box.appendChild(makeCard(it));
}

el('clearRecords').addEventListener('click', async () => {
  await send({ type: 'clear' });
  renderRecords();
  showRecToast('已清空');
});

renderRecords();
