// DOM builders shared by every promo. Builders run once; renderers only touch styles.
function buildDesk(parent, appName = "团队聊天") {
  const desk = el("div", "desk", `
    <div class="menubar">
      <div class="left"><b>${appName}</b><span>文件</span><span>编辑</span><span>显示</span><span>窗口</span><span>帮助</span></div>
      <div class="right">
        <div class="mb-icon"><div id="mbMic">${ICON.mic}</div><div class="bars" id="mbBars">${"<i></i>".repeat(5)}</div></div>
        <div class="mb-icon" id="mbWifi"><div class="mb-hi" id="mbWifiHi"></div><div id="mbWifiOn">${ICON.wifi}</div><div id="mbWifiOff" style="opacity:0">${ICON.wifiOff}</div></div>
        <div class="mb-icon bat"><div>${ICON.battery}</div></div>
        <div class="mb-icon"><div>${ICON.search}</div></div>
        <div class="mb-icon"><div>${ICON.controls}</div></div>
        <span>周五 10:24</span>
      </div>
    </div>`, parent);
  desk.id = "desk";
  return desk;
}

function setWifi(on) {
  $("mbWifiOn").style.opacity = on ? 1 : 0;
  $("mbWifiOff").style.opacity = on ? 0 : 1;
}

// opts: { id, x, y, w, h, side, title, sub, body, field: { id, ph } }
function buildWindow(parent, o) {
  const field = o.field
    ? `<div class="field" id="${o.field.id}"><div class="hl"></div><span class="ph">${o.field.ph || ""}</span><span class="txt"></span><span class="caret"></span></div>`
    : "";
  const w = el("div", "win", `
    <div class="lights"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i></div>
    ${o.side ? `<div class="side">${o.side}</div>` : ""}
    <div class="main">
      <div class="head" style="${o.side ? "" : "padding-left:110px"}">${o.title || ""}${o.sub ? ` <span>${o.sub}</span>` : ""}</div>
      <div class="body">${o.body || ""}</div>
      ${field}
    </div>`, parent);
  w.id = o.id;
  css(w, { left: `${o.x}px`, top: `${o.y}px`, width: `${o.w}px`, height: `${o.h}px`, opacity: 0 });
  return w;
}

const msgHTML = (name, color, time, text) =>
  `<div class="msg"><div class="avatar" style="background:${color}">${name[0]}</div><div><div class="who">${name}<span>${time}</span></div><div class="txt">${text}</div></div></div>`;

// HUD centred on x with its bottom edge at `bottom` (desk coordinates).
function buildHud(parent, id, x = 960, bottom = 1056) {
  const glow = el("div", "hud-glow", undefined, parent);
  glow.id = `${id}Glow`;
  css(glow, { left: `${x - 200}px`, top: `${bottom - 116}px` });
  const hud = el("div", "hud", `
    <div class="rec"><div class="hbtn cancel">${ICON.xmark}</div><canvas width="126" height="42"></canvas><div class="hbtn confirm">${ICON.check}</div></div>
    <div class="status"><div class="ic"></div><span></span></div>`, parent);
  hud.id = id;
  css(hud, { left: `${x}px`, top: `${bottom - 40}px` });
  return hud;
}

function buildPointer(parent) {
  const p = el("div", "pointer", ICON.pointer, parent);
  p.id = "pointer";
  return p;
}

const KEYCAP = {
  fn: `<div class="key"><div class="cap"><span class="fn">fn</span><span class="gl">${ICON.globe}</span></div></div>`,
  shift: `<div class="key wide"><div class="cap"><span class="sh">${ICON.shift}</span><span class="word">shift</span></div></div>`,
};

// end: { l1, l2, feat?, meta }
function buildOverlay(stage, end) {
  stage.insertAdjacentHTML("beforeend", `
    <div id="headline"><div class="h"></div><div class="s"></div></div>
    <div id="tag"><span class="num"></span><span class="tx"></span></div>
    <div id="caption"></div>
    <div id="keys"></div>
    <div id="chip"><div class="ic">${ICON.wifiOff}</div><span>Wi-Fi 已关闭 · 离线运行</span></div>
    <div id="foot"></div>
    <div id="end">
      <img src="../../promo-kit/assets/app-icon.png" alt="">
      <div class="name">Utter</div>
      <div class="l1">${end.l1}</div>
      <div class="l2"><em>${end.l2}</em></div>
      ${end.feat ? `<div class="feat">${end.feat}</div>` : ""}
      <div class="url">utter.idevlab.dev</div>
      <div class="meta">${end.meta || "macOS 26+ · Apple Silicon · MIT 开源"}</div>
    </div>`);
}
