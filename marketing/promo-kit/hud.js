// Port of WaveformView.swift (light colour scheme) and the OverlayLayout phases.
const WAVE_LAYERS = [
  { e: 0.54, f: 1.55, s: -4.2, p: 1.4, w: 1.05, c: ["rgba(199,41,28,.40)", "rgba(179,97,5,.56)"] },
  { e: 0.72, f: 2.15, s: 5.4, p: 2.8, w: 1.15, c: ["rgba(214,61,26,.56)", "rgba(194,117,5,.72)"] },
  { e: 1.0, f: 1.8, s: 7.2, p: 0, w: 2.2, c: ["rgb(209,43,31)", "rgb(214,99,5)", "rgb(184,125,5)"] },
];

// Status rows Utter shows after release (zh-Hans strings, OverlayLayout widths).
const HUD = {
  transcribing: ["识别中…", "transcribing", 216],
  formatting: ["整理中…", "textformat", 216],
  translating: ["翻译中…", "textformat", 216],
  inserting: ["输入中…", "cursor", 216],
  done: ["完成", "check", 192],
};

function speechLevel(t, start, tokens) {
  let level = 0.04;
  for (const s of tokens) {
    const a = start + s.t, b = a + s.d;
    if (t > a - 0.05 && t < b + 0.12) {
      const env = Math.sin(Math.PI * seg(t, a - 0.05, b + 0.12));
      const jitter = 0.75 + 0.25 * Math.sin(t * 23.0 + s.t * 7) * Math.sin(t * 9.7);
      level = Math.max(level, 0.72 * env * jitter);
    }
  }
  return level;
}

function drawWave(cv, t, level) {
  const ctx = cv.getContext("2d");
  const W = 42, H = 14;
  ctx.setTransform(3, 0, 0, 3, 0, 0);
  ctx.clearRect(0, 0, W, H);
  const energy = 0.14 + Math.pow(clamp(level), 0.72) * 0.86;
  const n = 42, dw = W - 4, cy = H / 2, amp = (H - 4) / 2;
  for (const L of WAVE_LAYERS) {
    const g = ctx.createLinearGradient(0, cy, W, cy);
    L.c.forEach((c, i) => g.addColorStop(i / (L.c.length - 1), c));
    Object.assign(ctx, { strokeStyle: g, lineWidth: L.w, lineCap: "round", lineJoin: "round" });
    ctx.beginPath();
    for (let i = 0; i <= n; i++) {
      const pr = i / n;
      const env = Math.pow(Math.sin(Math.PI * pr), 0.62);
      const fund = Math.sin(pr * Math.PI * 2 * L.f + t * L.s + L.p);
      const harm = Math.sin(pr * Math.PI * 2 * (L.f * 2.35) - t * L.s * 0.44 + L.p);
      const y = cy + amp * energy * L.e * env * (fund * 0.78 + harm * 0.22);
      i === 0 ? ctx.moveTo(2 + dw * pr, y) : ctx.lineTo(2 + dw * pr, y);
    }
    ctx.stroke();
  }
}

// Menu bar status item: mic.fill normally, five orange bars while recording.
function drawMenuIcon(t, recording, level) {
  if (!$("mbMic")) return;
  $("mbMic").style.opacity = recording ? 0 : 1;
  const bars = $("mbBars");
  bars.style.opacity = recording ? 1 : 0;
  [...bars.children].forEach((b, i) => {
    const wave = (Math.sin(t * 10 + (i / 5) * Math.PI * 2) + 1) / 2;
    b.style.height = `${Math.max(3, Math.max(level, 0.18) * 16 * wave)}px`;
  });
}

// beat: { in, keyUp, out, speechStart, tokens, phases: [[t, "transcribing"|...], ...] }
function renderHud(id, t, beat) {
  const hud = $(id);
  const recording = t >= beat.in && t < beat.keyUp;
  const level = recording ? speechLevel(t, beat.speechStart, beat.tokens) : 0;
  if (t >= beat.in - 0.1 && t < beat.out + 0.5) drawMenuIcon(t, recording, level);

  const visible = window01(t, beat.in, beat.out + 0.25, 0.22, 0.25);
  hud.style.opacity = visible;
  $(`${id}Glow`).style.opacity = visible * (0.55 + 0.45 * level);
  if (visible <= 0) return;

  let idx = -1;
  beat.phases.forEach(([pt], i) => { if (t >= pt) idx = i; });
  let width = 148;
  if (t >= beat.keyUp && idx >= 0) {
    const prevW = idx === 0 ? 148 : HUD[beat.phases[idx - 1][1]][2];
    width = lerp(prevW, HUD[beat.phases[idx][1]][2], ease.inOut(seg(t, beat.phases[idx][0], beat.phases[idx][0] + 0.18)));
  }
  const pop = ease.spring(seg(t, beat.in, beat.in + 0.45));
  css(hud, { width: `${width}px`, marginLeft: `${-width / 2}px`, transform: `scale(${lerp(0.9, 1, pop)})` });

  hud.querySelector(".rec").style.opacity = recording ? 1 : 1 - seg(t, beat.keyUp, beat.keyUp + 0.1);
  hud.querySelector(".status").style.opacity = recording ? 0 : seg(t, beat.keyUp + 0.05, beat.keyUp + 0.2);
  if (recording || t - beat.keyUp < 0.25) drawWave(hud.querySelector("canvas"), t, level);
  if (idx >= 0) {
    const [text, icon] = HUD[beat.phases[idx][1]];
    const ic = hud.querySelector(".status .ic");
    if (ic.dataset.k !== icon) { ic.innerHTML = ICON[icon]; ic.dataset.k = icon; }
    ic.style.opacity = icon === "transcribing" ? 0.55 + 0.45 * Math.abs(Math.cos(t * 3.2)) : 1;
    hud.querySelector(".status span").textContent = text;
  }
}

// Builds the usual phase list from compact timings.
function hudPhases(keyUp, processing, inserting, done, kind = "formatting") {
  return [[keyUp + 0.1, "transcribing"], [processing, kind], [inserting, "inserting"], [done, "done"]];
}
