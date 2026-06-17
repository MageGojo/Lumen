let currentTab = null;
let settings = { intercept: true, sniff: true };

function send(msg) {
  return new Promise((resolve) => chrome.runtime.sendMessage(msg, resolve));
}

async function getActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab;
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

const KIND_CLASS = {
  下载: 'k-dl',
  HLS: 'k-hls',
  DASH: 'k-hls',
  视频: 'k-video',
  音频: 'k-audio',
};

function nameOf(item) {
  if (item.name) return item.name;
  if (item.title) return item.title;
  try {
    const p = new URL(item.url).pathname.split('/').filter(Boolean).pop();
    if (p) return decodeURIComponent(p);
  } catch (e) {}
  return item.host || item.url;
}

function setStatus(ok) {
  const dot = document.getElementById('dot');
  const text = document.getElementById('statusText');
  dot.className = 'dot ' + (ok ? 'on' : 'off');
  text.textContent = ok ? '已连接' : '应用未运行';
}

function setToggle(on) {
  const t = document.getElementById('intercept');
  t.classList.toggle('on', on);
  t.querySelector('.knob').textContent = on ? '接管中' : '已关闭';
}

function toast(message, ok) {
  const el = document.getElementById('toast');
  el.textContent = message;
  el.className = 'toast ' + (ok ? 'ok' : 'err');
  clearTimeout(el._t);
  el._t = setTimeout(() => {
    el.className = 'toast';
  }, 2600);
}

async function sendItem(item, btn) {
  if (btn) {
    btn.disabled = true;
    btn.textContent = '发送中…';
  }
  const res = await send({
    type: 'send',
    payload: { url: item.url, referer: item.referer, title: item.title || item.name, kind: item.kind },
  });
  if (btn) {
    btn.disabled = false;
    btn.textContent = '发送';
  }
  toast((res && res.message) || (res && res.ok ? '已发送' : '发送失败'), res && res.ok);
}

function makeCard(item, sentAlready) {
  const card = document.createElement('div');
  card.className = 'item';

  const meta = document.createElement('div');
  meta.className = 'meta';
  const badge = document.createElement('span');
  badge.className = 'badge ' + (KIND_CLASS[item.kind] || 'k-dl');
  badge.textContent = item.kind || '下载';
  meta.appendChild(badge);
  if (item.host) {
    const h = document.createElement('span');
    h.className = 'hostname';
    h.textContent = item.host;
    meta.appendChild(h);
  }
  if (item.size) {
    const size = document.createElement('span');
    size.className = 'size';
    size.textContent = humanSize(item.size);
    meta.appendChild(size);
  }
  card.appendChild(meta);

  const name = document.createElement('div');
  name.className = 'name';
  name.textContent = nameOf(item);
  name.title = item.url;
  card.appendChild(name);

  const row = document.createElement('div');
  row.className = 'row';
  const dl = document.createElement('button');
  dl.className = 'primary grow';
  dl.textContent = sentAlready ? '重发' : '发送';
  dl.addEventListener('click', () => sendItem(item, dl));
  const copy = document.createElement('button');
  copy.textContent = '复制';
  copy.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(item.url);
      copy.textContent = '已复制';
      setTimeout(() => (copy.textContent = '复制'), 1400);
    } catch (e) {
      toast('复制失败', false);
    }
  });
  row.appendChild(dl);
  row.appendChild(copy);
  card.appendChild(row);
  return card;
}

function section(title) {
  const h = document.createElement('div');
  h.className = 'section';
  h.textContent = title;
  return h;
}

function render(captures, media) {
  const list = document.getElementById('list');
  list.innerHTML = '';

  if (!captures.length && !media.length) {
    const div = document.createElement('div');
    div.className = 'empty';
    div.textContent = settings.intercept
      ? '已接管浏览器下载。\n现在在网页点任意下载,就会自动发到 Lumen。'
      : '下载接管已关闭。\n打开上方开关后,浏览器下载会自动交给 Lumen。';
    list.appendChild(div);
    return;
  }

  if (captures.length) {
    list.appendChild(section('最近接管 / 发送'));
    for (const it of captures) list.appendChild(makeCard(it, true));
  }
  if (media.length) {
    list.appendChild(section('本页媒体'));
    for (const it of media) list.appendChild(makeCard(it, false));
  }
}

async function refresh() {
  currentTab = await getActiveTab();
  const res = await send({ type: 'state', tabId: currentTab ? currentTab.id : null });
  if (!res) {
    setStatus(false);
    return;
  }
  settings = res.settings || settings;
  setStatus(res.online);
  setToggle(settings.intercept);
  render(res.captures || [], res.media || []);
}

document.getElementById('intercept').addEventListener('click', async () => {
  settings.intercept = !settings.intercept;
  setToggle(settings.intercept);
  await send({ type: 'setSettings', values: { intercept: settings.intercept } });
  refresh();
});

document.getElementById('parsePage').addEventListener('click', async (e) => {
  const btn = e.currentTarget;
  if (!currentTab || !currentTab.url) return;
  btn.disabled = true;
  btn.textContent = '发送中…';
  const res = await send({
    type: 'send',
    payload: { url: currentTab.url, title: currentTab.title || '' },
  });
  btn.disabled = false;
  btn.textContent = '解析当前页面';
  toast((res && res.message) || (res && res.ok ? '已发送' : '发送失败'), res && res.ok);
});

document.getElementById('clear').addEventListener('click', async () => {
  await send({ type: 'clear', tabId: currentTab ? currentTab.id : null });
  render([], []);
});

document.getElementById('openOptions').addEventListener('click', () => {
  chrome.runtime.openOptionsPage();
});

refresh();
setInterval(refresh, 1800);
