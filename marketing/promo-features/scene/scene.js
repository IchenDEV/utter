// Feature promo (45 s): smart format, voice command, translation, lexicon, style, models.
const WIN = { x: 420, y: 250, w: 1080, h: 520 };
const ICON_SRC = "../../promo-kit/assets/app-icon.png";
const SIDE = {
  command: ["输出模式", ["原文直出", "智能整理", "语音指令"]],
  translate: ["翻译目标语言", ["英语", "日语", "韩语", "西班牙语", "法语", "德语"]],
  lexicon: ["行业词库", ["通用", "医疗", "法律", "金融财会", "软件技术"]],
};
let M = {};

function buildScene(cues) {
  const stage = $("stage");
  const desk = buildDesk(stage, "Utter 演示");
  const B = cues.beats;
  const win = (id, o) => buildWindow(desk, { id, ...WIN, ...o });
  win("wList", {
    title: "笔记", sub: "本周计划",
    body: '<div class="doc-title">本周计划</div><div class="doc-meta">今天 10:24</div>',
    field: { id: "fList", ph: "开始输入…" },
  });
  win("wCommand", {
    title: "收件箱", sub: "发布会时间",
    body: `<div class="mail-subj">发布会时间</div>
      <div class="mail-from"><div class="avatar" style="background:#7a83d8">王</div><div><b>王总</b><div class="doc-meta" style="margin:0">今天 09:58 · 发给我</div></div></div>
      <div class="mail-body">下周三的发布会，能否提前到周二？请确认。</div>`,
    field: { id: "fCommand", ph: "回复王总…" },
  });
  win("wTranslate", {
    title: "# global-team", sub: "8 位成员",
    side: '<div class="grp">频道</div><div class="item sel"># global-team</div><div class="item"># 设计</div><div class="grp">私信</div><div class="item">Alex</div>',
    body: msgHTML("Alex", "#d98a4e", "10:20", "Hi! Could you share the API docs before Friday?"),
    field: { id: "fTranslate", ph: "Message # global-team" },
  });
  win("wLexicon", {
    title: "部署说明.md", sub: "已编辑",
    body: '<div class="doc-title">上线前检查</div><div class="doc-meta">运维 · 发布</div>',
    field: { id: "fLexicon", ph: "开始输入…" },
  });
  ["fList", "fLexicon"].forEach((id) => $(id).classList.add("plain"));
  buildHud(desk, "hud");
  for (const [id, b] of Object.entries(B)) buildSpoken(desk, `sp_${id}`, b.tokens);

  stage.insertAdjacentHTML("beforeend", `
    <div id="side"><div class="hd"><img src="${ICON_SRC}">Utter 设置</div><div class="ttl"></div><div class="opts"></div></div>
    <div class="cmp" id="cmpRaw" style="left:265px"><div class="lb">你说的</div><div class="tx raw">${cues.style.spoken}</div></div>
    <div id="cmpArrow"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12h15M13 6l6 6-6 6"/></svg></div>
    <div class="cmp" id="cmpOut" style="left:1015px"><div class="lb">语言风格</div>
      <div class="seg"><span id="segCasual">口语</span><span id="segPro">专业</span><span>自定义</span></div>
      <div class="tx" id="cmpText"></div></div>
    <div class="mcard" id="mAsr" style="top:190px"><div class="mh">${ICON.transcribing}语音识别<span>本地运行</span></div>
      <div class="row"><span class="pill local">Qwen3-ASR</span><span class="pill local">Confucius4-R2T2</span><span class="pill local">FireRedASR2</span><span class="pill local">Mega-ASR</span><span class="pill local">WhisperKit</span><span class="pill local">Apple 设备端识别</span></div></div>
    <div class="mcard" id="mLlm" style="top:440px"><div class="mh">${ICON.chip}文字整理<span>本地运行 · MLX</span></div>
      <div class="row"><span class="pill local">Qwen3.5</span><span class="pill local">Qwen3</span><span class="pill local">Gemma 4</span><span class="pill local">Gemma 3</span></div></div>
    <div class="mcard" id="mRemote" style="top:690px"><div class="mh">${ICON.cloud}可选远程 API<span>联网，按需开启</span></div>
      <div class="row"><span class="pill ">OpenAI</span><span class="pill ">Claude</span><span class="pill ">Gemini</span><span class="pill ">OpenRouter</span><span class="pill ">硅基流动</span><span class="pill ">豆包</span><span class="pill ">百炼</span><span class="pill ">MiniMax</span></div></div>`);
  buildOverlay(stage, { l1: "说出来", l2: "就写好了", feat: "智能整理 · 语音指令 · 翻译听写 · 行业词库 · 本地模型" });
}

function setupScene(cues) {
  const desk = $("desk");
  for (const [id, b] of Object.entries(cues.beats)) {
    measureSpoken(`sp_${id}`);
    const fid = `f${id[0].toUpperCase()}${id.slice(1)}`;
    $(`w${id[0].toUpperCase()}${id.slice(1)}`).style.opacity = 1;
    M[id] = { field: fid, target: measureFieldTarget(fid, b.result, desk) };
    $(`w${id[0].toUpperCase()}${id.slice(1)}`).style.opacity = 0;
  }
}
