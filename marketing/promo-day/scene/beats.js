// Per-frame rendering for the day-in-the-life promo.
window.renderAt = function renderAt(t) {
  const C = window.CUES, S = C.scenes;
  const idx = Math.max(0, S.findIndex((s, i) => t >= s.start && (i === S.length - 1 || t < S[i + 1].start)));
  const sc = S[idx];

  for (const s of S) {
    const on = s === sc;
    $(`place_${s.place}`).style.display = on ? "" : "none";
    $(`placefg_${s.place}`).style.display = on ? "" : "none";
    $(`w_${s.id}`).style.opacity = on ? 1 : 0;
  }
  animateIllus(t);
  setWifi(!sc.offline);

  const p = dollyProgress(t, sc);
  const push = idx === 0 ? 0.06 * ease.inOut(seg(t, 0, sc.dollyIn)) : 0.03 * seg(t, sc.start, sc.dollyIn);
  const s = Math.exp(lerp(0, Math.log(S_IN), p)) * (1 + push * (1 - p));
  css($("world"), { transform: cameraTransform({ s, fx: 960, fy: lerp(540, SCREEN.y + SCREEN.h / 2, p) }),
    opacity: 1 - seg(t, C.endCard, C.endCard + 0.5) });
  const si = lerp(1, 1.12, p);
  css($("desk"), { transform: `scale(${SCREEN.w / 1920}) ${cameraTransform({ s: si, fx: 960, fy: 1080 - 540 / si })}` });
  $("dip").style.opacity = Math.max(0, ...S.slice(1).map((x) => 1 - Math.abs(t - x.start) / 0.22));

  renderField(`f_${sc.id}`, t, { focus: sc.dollyIn + 0.6, land: sc.inserting + 0.45, text: sc.result });
  for (const x of S) {
    renderSpoken(`sp_${x.id}`, t, {
      start: x.speechStart, cx: 960, y: 850, labels: x.labels, P: x.morph ? x.processing : null,
      fly: x.morph ? { t: x.inserting, x: M[x.id].x, y: M[x.id].y - 3, scale: (x.id === "chat" ? 19 : 21) / 24 } : null,
      out: x.inserting + 0.4,
    });
  }
  if (t >= sc.keyDown - 0.3 && t < sc.hudOut + 0.6) {
    renderHud("hud", t, { in: sc.keyDown + 0.1, keyUp: sc.keyUp, out: sc.hudOut, speechStart: sc.speechStart, tokens: sc.tokens,
      phases: hudPhases(sc.keyUp, sc.processing, sc.inserting, sc.done, sc.kind || "formatting") });
  } else {
    $("hud").style.opacity = 0;
    $("hudGlow").style.opacity = 0;
    drawMenuIcon(t, false, 0);
  }
  renderKeys(t, S.map((x) => [x.keyDown, x.keyUp, x.kind === "translating" ? ["fn", "shift"] : ["fn"]]));

  renderHeadline(t, [[0.2, 2.75, "一天要写多少字？", "消息、纪要、邮件、周报……"]]);
  renderTag(t, S.map((x, i) => [i === 0 ? 2.8 : x.start + 0.15, (S[i + 1] ? S[i + 1].start : C.endCard) - 0.15, x.clock, x.where]));
  renderCaption(t, S.map((x, i) => [i === 0 ? 2.9 : x.start + 0.3, (S[i + 1] ? S[i + 1].start : C.endCard) - 0.2, x.caption]));
  const A = "界面为动画重建 · 示例文本";
  renderFoot(t, S.map((x, i) => [i === 0 ? 2.9 : x.start + 0.3, (S[i + 1] ? S[i + 1].start : C.endCard) - 0.2,
    x.id === "reply" ? "语音指令会读取屏幕文字（需屏幕录制权限）· 示例文本" : x.offline ? "本地处理模式 · 需预先安装本地模型 · 示例文本" : A]));
  const last = S[S.length - 1];
  renderChip(t, last.start + 0.5, C.endCard - 0.2, "离线运行 · 本地模型 Qwen3-ASR + Qwen3.5");
  renderEnd(t, C.endCard + 0.3);
};
