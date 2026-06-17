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
