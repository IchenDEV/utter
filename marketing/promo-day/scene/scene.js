// Day-in-the-life promo (52 s): five office moments, each pushing into the laptop screen.
const WIN = { x: 420, y: 250, w: 1080, h: 520 };
const S_IN = 1920 / SCREEN.w;
let M = {};

const WINDOWS = {
  chat: {
    title: "# 产品组", sub: "12 位成员",
    side: '<div class="grp">频道</div><div class="item sel"># 产品组</div><div class="item"># 设计评审</div><div class="item"># 发布</div><div class="grp">私信</div><div class="item">周远</div>',
    body: () => msgHTML("周远", "#5fa58a", "09:26", "评审会改时间了吗？议程发我一份～"),
    field: "发消息到 # 产品组",
  },
  notes: { title: "笔记", sub: "评审会纪要", body: () => '<div class="doc-title">评审会纪要</div><div class="doc-meta">今天 11:02 · 产品组</div>', field: "开始输入…", plain: true },
  mail: {
    title: "新邮件", sub: "To: Emma Chen",
    body: () => `<div class="mail-line"><span>收件人</span>Emma Chen &lt;emma@northwind.example&gt;</div><div class="mail-line"><span>主题</span>Re: Feedback on build 2.3</div>
      <div class="mail-quote">Hi! We found two issues in the latest build. When can we expect a fix?</div>`,
    field: "写邮件…",
  },
  reply: {
    title: "收件箱", sub: "合同条款确认",
    body: () => `<div class="mail-subj">合同条款确认</div>
      <div class="mail-from"><div class="avatar" style="background:#c9b07a">法</div><div><b>法务 · 陈律师</b><div class="doc-meta" style="margin:0">今天 16:41</div></div></div>
      <div class="mail-body">合同第 4 条的付款周期，对方希望由 30 天调整为 45 天，请确认是否同意。</div>`,
    field: "回复陈律师…",
  },
  report: { title: "周报.md", sub: "未保存", body: () => '<div class="doc-title">本周周报</div><div class="doc-meta">产品组 · 第 40 周</div>', field: "开始输入…", plain: true },
};

function buildScene(cues) {
  const stage = $("stage");
  const world = el("div", "", "", stage);
  world.id = "world";
  world.innerHTML = `<svg viewBox="0 0 1920 1080" width="1920" height="1080">${defsSVG()}
    ${Object.entries(PLACES).map(([k, f]) => `<g id="place_${k}" style="display:none">${f().bg}</g>`).join("")}${laptopSVG()}
    ${Object.entries(PLACES).map(([k, f]) => `<g id="placefg_${k}" style="display:none">${f().fg}</g>`).join("")}</svg>`;
  const screen = el("div", "", "", world);
  screen.id = "screen";
  css(screen, { left: `${SCREEN.x}px`, top: `${SCREEN.y}px`, width: `${SCREEN.w}px`, height: `${SCREEN.h}px` });
  const desk = buildDesk(screen, "工作台");
  for (const s of cues.scenes) {
    const w = WINDOWS[s.id];
    buildWindow(desk, { id: `w_${s.id}`, ...WIN, title: w.title, sub: w.sub, side: w.side, body: w.body(), field: { id: `f_${s.id}`, ph: w.field } });
    if (w.plain) $(`f_${s.id}`).classList.add("plain");
    buildSpoken(desk, `sp_${s.id}`, s.tokens);
  }
  buildHud(desk, "hud");
  el("div", "", "", stage).id = "dip";
  buildOverlay(stage, { l1: "说出来", l2: "就写好了", feat: "本地模型：Qwen · Gemma · Llama · Whisper" });
}

function setupScene(cues) {
  const desk = $("desk");
  for (const s of cues.scenes) {
    measureSpoken(`sp_${s.id}`);
    $(`w_${s.id}`).style.opacity = 1;
    M[s.id] = measureFieldTarget(`f_${s.id}`, s.result, desk);
    $(`w_${s.id}`).style.opacity = 0;
  }
}

// 0 = wide establishing shot, 1 = laptop screen fills the frame.
function dollyProgress(t, s) {
  let p = ease.inOut(seg(t, s.dollyIn, s.dollyIn + 1.1));
  if (s.dollyOut) p *= 1 - 0.95 * ease.inOut(seg(t, s.dollyOut, s.dollyOut + 1.2));
  return p;
}
