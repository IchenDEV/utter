// Local voice input promo: hold fn and speak -> cleaned text at cursor -> local models on this Mac.
let M = {};

function buildScene(cues) {
  const stage = $("stage");
  const desk = buildDesk(stage);
  buildWindow(desk, {
    id: "win", x: 400, y: 150, w: 1120, h: 660, title: "# 发布评审", sub: "6 位成员",
    side: '<div class="grp">频道</div><div class="item sel"># 发布评审</div><div class="item"># 设计</div><div class="item"># 后端</div><div class="grp">私信</div><div class="item">林岚</div><div class="item">周远</div>',
    body: msgHTML("林岚", "#e0896b", "10:12", "评审会时间定了吗？") + msgHTML("周远", "#5fa58a", "10:15", "接口文档也麻烦同步一下，我想提前过一遍。"),
    field: { id: "field", ph: "发消息到 # 发布评审" },
  });
  buildHud(desk, "hud");
  buildSpoken(desk, "spoken", cues.speech);
  el("div", "", undefined, desk).id = "veil";
  el("div", "", undefined, stage).id = "desk-frame";

  stage.insertAdjacentHTML("beforeend", `
    <div id="privacy">
      <div class="pv-label" id="pvMac">这台 Mac</div>
      <div class="pv-node" id="pvN0"><div class="ic">${ICON.mic}</div><div class="t">你的声音</div><div class="d">麦克风输入</div></div>
      <div class="pv-node wide" id="pvN1"><div class="ic">${ICON.transcribing}</div><div class="t">本地语音识别</div><div class="d">Qwen3-ASR · Whisper<br>FireRed · Apple 设备端</div></div>
      <div class="pv-node wide" id="pvN2"><div class="ic">${ICON.chip}</div><div class="t">本地文字整理</div><div class="d">Qwen3.5 · Qwen3<br>Gemma 4 · Gemma 3（MLX）</div></div>
      <div class="pv-node" id="pvN3"><div class="ic">${ICON.cursor}</div><div class="t">写入当前应用</div><div class="d">出现在光标处</div></div>
      <div class="pv-link" id="pvL0"></div><div class="pv-link" id="pvL1"></div><div class="pv-link" id="pvL2"></div>
      <div class="pv-shot" id="pvShotA"><img src="../../promo-kit/assets/ui-asr-engines.png" width="920" height="112"></div>
      <div class="pv-shot" id="pvShotB"><img src="../../promo-kit/assets/ui-llm-current-row.png" width="920" height="62"></div>
    </div>`);
  buildOverlay(stage, { l1: "离线语音输入", l2: "你的声音，留在你的 Mac" });
}

function setupScene(cues) {
  const desk = $("desk");
  $("chip").querySelector(".ic").innerHTML = ICON.check;
  $("chip").querySelector(".ic").style.color = "#5b6ff0";
  measureSpoken("spoken");
  M.target = measureFieldTarget("field", cues.result, desk);
}

function camera(t, E) {
  const K = (f) => keys(t, f);
  const k0 = E.keyDown;
  return {
    s: K([[1.5, 1], [2.3, 1.2], [k0, 1.2], [k0 + 0.8, 1.45], [E.done + 0.1, 1.45], [E.done + 0.9, 1.2], [E.zoomOut, 1.2], [E.zoomOut + 1.1, 0.66], [E.endCard, 0.66], [E.endCard + 0.8, 0.56]]),
    fx: 960,
    fy: K([[1.5, 540], [2.3, 470], [k0, 470], [k0 + 0.8, 708], [E.done + 0.1, 708], [E.done + 0.9, 470], [E.zoomOut, 470], [E.zoomOut + 1.1, 590]]),
  };
}

function renderPrivacy(t, E) {
  const T = E.privacy, out = 1 - seg(t, E.endCard, E.endCard + 0.5);
  $("veil").style.opacity = 0.9 * seg(t, T - 0.2, T + 0.3);
  const pv = $("privacy");
  pv.style.display = t < T - 0.1 || out <= 0 ? "none" : "block";
  pv.style.opacity = out;
  const rise = (a) => { const p = ease.out(seg(t, a, a + 0.4)); return { opacity: p, transform: `translateY(${(1 - p) * 18}px)` }; };
  const widths = [200, 300, 300, 200], gap = 50;
  let x = 960 - (widths.reduce((a, b) => a + b, 0) + gap * 3) / 2;
  css($("pvMac"), { left: "366px", top: "186px", ...rise(T) });
  widths.forEach((w, i) => {
    const a = T + 0.2 + i * 0.22;
    css($(`pvN${i}`), { left: `${x}px`, top: "290px", width: `${w}px`, ...rise(a) });
    if (i < 3) css($(`pvL${i}`), { left: `${x + w + 8}px`, top: "382px", width: `${gap - 16}px`, transform: `scaleX(${ease.inOut(seg(t, a + 0.15, a + 0.4))})` });
    x += w + gap;
  });
  css($("pvShotA"), { left: `${960 - 460}px`, top: "520px", ...rise(T + 1.2) });
  css($("pvShotB"), { left: `${960 - 460}px`, top: "648px", ...rise(T + 1.45) });
}

window.renderAt = function renderAt(t) {
  const C = window.CUES, E = C.events;
  const cam = camera(t, E);
  const tf = cameraTransform(cam);
  const radius = (26 * clamp((1 - cam.s) / 0.34)) / Math.max(cam.s, 0.01);
  const deskOut = 1 - seg(t, E.endCard, E.endCard + 0.5);
  css($("desk"), { transform: tf, borderRadius: `${radius}px`, opacity: deskOut,
    boxShadow: cam.s < 1 ? `0 ${40 / cam.s}px ${90 / cam.s}px rgba(40,42,90,${0.28 * clamp((1 - cam.s) * 3)})` : "none" });
  css($("desk-frame"), { transform: tf, borderRadius: `${radius}px`, opacity: deskOut, borderWidth: `${3 / cam.s}px`,
    borderColor: `rgba(123,127,242,${0.75 * seg(t, E.zoomOut + 0.8, E.zoomOut + 1.4)})` });

  setWifi(true);
  renderWindowIn("win", t, E.windowIn);
  const beat = { in: E.hudIn, keyUp: E.keyUp, out: E.hudOut, speechStart: E.speechStart, tokens: C.speech,
    phases: hudPhases(E.keyUp, E.processing, E.inserting, E.done) };
  renderHud("hud", t, beat);
  renderSpoken("spoken", t, { start: E.speechStart, cx: 960, y: 850, P: E.processing,
    fly: { t: E.inserting, x: M.target.x, y: M.target.y - 3, scale: 19 / 24 } });
  renderField("field", t, { focus: E.windowIn + 0.5, land: E.inserting + 0.45, text: C.result });
  renderPrivacy(t, E);

  renderHeadline(t, [[0.15, E.windowIn + 0.1, "说出来，就是文字", "Utter · 在你的 Mac 上本地运行"]]);
  renderCaption(t, [[E.keyDown - 0.3, E.keyUp, "按住 <em>fn</em>，自然地说"], [E.keyUp + 0.05, E.inserting - 0.1, "松开，<em>在本机</em>识别并整理"],
    [E.inserting, E.zoomOut + 0.4, "整理好的文字，<em>直接写进当前应用</em>"], [E.zoomOut + 0.5, E.endCard - 0.3, "选你喜欢的<em>本地模型</em>，全程在这台 Mac 上"]]);
  renderKeys(t, [[E.keyDown, E.keyUp, ["fn"]]]);
  renderChip(t, E.privacy + 1.7, E.endCard - 0.3, "装好模型后，断网也能用");
  renderFoot(t, [[E.windowIn + 0.3, E.zoomOut + 0.3, "界面为动画重建，非实时录屏 · 实际速度取决于设备与模型 · 示例文本"],
    [E.zoomOut + 0.5, E.endCard - 0.3, "截图来自 Utter 设置界面（“豆包”为联网选项）· 本地模式需预先下载模型"]]);
  renderEnd(t, E.endCard + 0.25);
};
