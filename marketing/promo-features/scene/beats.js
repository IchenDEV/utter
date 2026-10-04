// Per-frame rendering for the feature promo.
const cap = (s) => s[0].toUpperCase() + s.slice(1);

function sideRows(B) {
  return [
    [B.list.winIn + 0.2, B.list.winOut - 0.1, "list"],
    [B.command.winIn + 0.2, B.command.winOut - 0.1, "command"],
    [B.translate.winIn + 0.2, B.translate.winOut - 0.1, "translate"],
    [B.lexicon.winIn + 0.2, B.lexicon.winOut - 0.1, "lexicon"],
  ];
}

function renderSide(t, B) {
  const row = activeRow(t, sideRows(B)), card = $("side");
  if (!row) { card.style.opacity = 0; return; }
  const id = row[2];
  const [title, opts] = SIDE[id === "list" ? "command" : id];
  let sel = 0;
  if (id === "list") sel = 1;
  if (id === "command") sel = t < B.command.modeSwitch ? 1 : 2;
  if (id === "lexicon") sel = t < B.lexicon.select ? 0 : 4;
  setHTML(card.querySelector(".ttl"), title);
  setHTML(card.querySelector(".opts"), opts.map((o, i) => `<div class="opt${i === sel ? " on" : ""}"><span class="dot"></span>${o}</div>`).join(""));
  const p = window01(t, row[0], row[1], 0.3, 0.25);
  css(card, { opacity: p, transform: `translateX(${(1 - ease.out(seg(t, row[0], row[0] + 0.4))) * 24}px)` });
}

function renderStyle(t, S) {
  const rise = (a) => { const p = ease.out(seg(t, a, a + 0.4)) * (1 - seg(t, S.end - 0.35, S.end)); return { opacity: p, transform: `translateY(${(1 - p) * 20}px)` }; };
  css($("cmpRaw"), rise(S.start + 0.1));
  css($("cmpArrow"), rise(S.start + 0.5));
  css($("cmpOut"), rise(S.start + 0.6));
  const pro = t >= S.professional;
  $("segCasual").classList.toggle("on", t >= S.casual && !pro);
  $("segPro").classList.toggle("on", pro);
  const text = $("cmpText");
  setHTML(text, t < S.casual ? "" : pro ? S.professional_text : S.casual_text);
  const switchAt = pro ? S.professional : S.casual;
  text.style.opacity = ease.out(seg(t, switchAt, switchAt + 0.3));
}

function renderModels(t, Mo) {
  for (const [id, a] of [["mAsr", Mo.start + 0.1], ["mLlm", Mo.start + 0.4], ["mRemote", Mo.start + 0.7]]) {
    const p = ease.out(seg(t, a, a + 0.45)) * (1 - seg(t, Mo.end - 0.35, Mo.end));
    css($(id), { opacity: p, transform: `translateY(${(1 - p) * 24}px)` });
  }
}

window.renderAt = function renderAt(t) {
  const C = window.CUES, B = C.beats;
  const active = Object.values(B).find((b) => t >= b.winIn && t < b.winOut);
  const s = t < 2.3 ? 1 : lerp(1, 1.12, ease.inOut(seg(t, 2.3, 2.9))) + (active ? 0.03 * ease.inOut(seg(t, active.winIn, active.winOut)) : 0);
  css($("desk"), { transform: cameraTransform({ s, fx: 960, fy: 1080 - 540 / s }), opacity: 1 - seg(t, C.endCard, C.endCard + 0.4) });

  for (const [id, b] of Object.entries(B)) {
    renderWindowIn(`w${cap(id)}`, t, b.winIn, b.winOut - 0.35);
    renderField(M[id].field, t, { focus: b.winIn + 0.4, land: b.inserting + 0.45, text: b.result });
    renderSpoken(`sp_${id}`, t, {
      start: b.speechStart, cx: 960, y: 850, labels: b.labels,
      P: b.morph ? b.processing : null,
      fly: b.morph ? { t: b.inserting, x: M[id].target.x, y: M[id].target.y - 3, scale: 21 / 24 } : null,
      out: b.inserting + 0.4,
    });
  }
  const hb = Object.values(B).find((b) => t >= b.keyDown - 0.3 && t < b.hudOut + 0.6);
  if (hb) {
    renderHud("hud", t, { in: hb.keyDown + 0.1, keyUp: hb.keyUp, out: hb.hudOut, speechStart: hb.speechStart, tokens: hb.tokens,
      phases: hudPhases(hb.keyUp, hb.processing, hb.inserting, hb.done, hb.kind || "formatting") });
  } else {
    $("hud").style.opacity = 0;
    $("hudGlow").style.opacity = 0;
    drawMenuIcon(t, false, 0);
  }
  renderKeys(t, Object.values(B).map((b) => [b.keyDown, b.keyUp, b.kind === "translating" ? ["fn", "shift"] : ["fn"]]));
  renderSide(t, B);
  renderStyle(t, C.style);
  renderModels(t, C.models);

  renderHeadline(t, [[0.15, 2.45, "不只是语音输入", "整理 · 指令 · 翻译 · 术语，都从按住 fn 开始"]]);
  renderTag(t, [[B.list.winIn, B.list.winOut, "01", "智能整理"], [B.command.winIn, B.command.winOut, "02", "语音指令"],
    [B.translate.winIn, B.translate.winOut, "03", "翻译听写"], [B.lexicon.winIn, C.style.start, "04", "行业词库"],
    [C.style.start, C.style.end, "05", "表达风格"], [C.models.start, C.models.end, "06", "模型随你选"]]);
  renderCaption(t, [[B.list.winIn + 0.1, B.list.winOut - 0.1, "口述清单，<em>自动整理成条目</em>"],
    [B.command.winIn + 0.05, B.command.winOut - 0.1, "语音指令：<em>读懂屏幕，替你起草回复</em>"],
    [B.translate.winIn + 0.05, B.translate.winOut - 0.1, "按住 fn + shift：<em>说中文，写英文</em>"],
    [B.lexicon.winIn + 0.05, B.lexicon.winOut - 0.1, "行业词库：<em>专业术语，一次写对</em>"],
    [C.style.start + 0.05, C.style.end - 0.1, "同一句话，<em>口语或专业</em>随你切换"],
    [C.models.start + 0.05, C.models.end - 0.1, "本地模型随你选，<em>也能接入自己的 API</em>"]]);
  const A = "界面为动画重建 · 示例文本 · 实际效果取决于所选模型";
  renderFoot(t, [[B.list.winIn + 0.1, B.list.winOut - 0.1, A],
    [B.command.winIn + 0.05, B.command.winOut - 0.1, "语音指令会读取屏幕文字（需屏幕录制权限）· 示例文本"],
    [B.translate.winIn + 0.05, B.lexicon.winOut - 0.1, A],
    [C.style.start + 0.05, C.style.end - 0.1, "示例文本 · 选“自定义”可编写自己的整理提示词"],
    [C.models.start + 0.05, C.models.end - 0.1, "模型列表来自 Utter 设置 · 使用远程 API 时，文本会发送给所选服务商"]]);
  renderEnd(t, C.endCard + 0.2);
};
