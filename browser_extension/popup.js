let settings = { intercept: true };

function send(msg) {
  return new Promise((resolve) => chrome.runtime.sendMessage(msg, resolve));
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

function setHint(on, online) {
  const el = document.getElementById('hint');
  if (!on) {
    el.innerHTML = '接管已<b>关闭</b>,浏览器下载保持原生方式。';
  } else if (online) {
    el.innerHTML = '<b>接管中</b>:在网页点任意下载,会自动发到 Lumen。';
  } else {
    el.innerHTML = '已开启接管,但<b>未检测到应用</b>。应用未运行时不接管,下载交回浏览器。';
  }
}

async function refresh() {
  const res = await send({ type: 'state' });
  if (!res) {
    setStatus(false);
    setHint(settings.intercept, false);
    return;
  }
  settings = res.settings || settings;
  setStatus(res.online);
  setToggle(settings.intercept);
  setHint(settings.intercept, res.online);
}

document.getElementById('intercept').addEventListener('click', async () => {
  settings.intercept = !settings.intercept;
  setToggle(settings.intercept);
  setHint(settings.intercept, document.getElementById('dot').classList.contains('on'));
  await send({ type: 'setSettings', values: { intercept: settings.intercept } });
  refresh();
});

document.getElementById('openOptions').addEventListener('click', () => {
  chrome.runtime.openOptionsPage();
});

document.getElementById('openRecords').addEventListener('click', () => {
  chrome.runtime.openOptionsPage();
});

refresh();
setInterval(refresh, 2500);
