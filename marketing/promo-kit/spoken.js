// Spoken words appear in time, optionally get cleaned (strike, collapse, rewrite),
// then fly into the target field. Coordinates are desk-local.
const SPOKEN = {};

function buildSpoken(parent, id, tokens, font = 24) {
  const root = el("div", "spoken", `<div class="label"></div><div class="line" style="font-size:${font}px"></div>`, parent);
  root.id = id;
  const line = root.querySelector(".line");
  tokens.forEach((s) => {
    el("span", "tok", `<span class="a">${s.w}</span>${s.to !== undefined ? `<span class="b">${s.to}</span>` : ""}<span class="strike"></span>`, line);
  });
  SPOKEN[id] = { root, tokens, font, gap: Math.round(font * 0.42) };
}

// Position of `node` in `container`'s unscaled coordinate space.
function localRect(node, container) {
  const r = node.getBoundingClientRect(), c = container.getBoundingClientRect();
  const k = c.width / container.offsetWidth;
  return { x: (r.left - c.left) / k, y: (r.top - c.top) / k, w: r.width / k, h: r.height / k };
}

function measureSpoken(id) {
  const S = SPOKEN[id];
  S.toks = [...S.root.querySelectorAll(".tok")].map((node, i) => {
    const a = node.querySelector(".a").getBoundingClientRect().width;
    const bEl = node.querySelector(".b");
    const k = S.root.getBoundingClientRect().width / S.root.offsetWidth || 1;
    return { ...S.tokens[i], node, wa: a / k, wb: (bEl ? bEl.getBoundingClientRect().width : a) / k };
  });
  S.rawWidth = S.toks.reduce((sum, k) => sum + k.wa, 0) + S.gap * (S.toks.length - 1);
}

// Field text start position, measured with the final text in place.
function measureFieldTarget(fieldId, text, container) {
  const txt = $(fieldId).querySelector(".txt");
  txt.textContent = text;
  const r = localRect(txt, container);
  txt.textContent = "";
  return r;
}

// spec: { start, cx, y, P?, fly?: { t, x, y, scale }, out?, labels?: [raw, clean] }
function renderSpoken(id, t, spec) {
  const S = SPOKEN[id];
  const end = spec.fly ? spec.fly.t + 0.65 : spec.out;
  const show = window01(t, spec.start - 0.1, end, 0.3, spec.fly ? 0.01 : 0.3);
  S.root.style.opacity = show;
  if (show <= 0) return;

  const P = spec.P ?? 1e9;
  const strikeA = P + 0.15, collapseA = P + 0.7, collapseB = P + 1.3;
  const morph = ease.inOut(seg(t, P + 0.8, P + 1.4));
  const settle = ease.inOut(seg(t, collapseA, collapseB + 0.15));
  let total = 0;
  S.toks.forEach((k, i) => {
    const appear = ease.out(seg(t, spec.start + k.t - 0.05, spec.start + k.t + 0.22));
    const w = k.drop ? k.wa * (1 - ease.inOut(seg(t, collapseA + i * 0.02, collapseB))) : lerp(k.wa, k.wb, morph);
    const gap = i === S.toks.length - 1 ? 0 : S.gap * (1 - settle);
    const base = k.drop ? [158, 161, 172] : [76, 79, 92];
    const c = base.map((v, j) => Math.round(lerp(v, [23, 24, 29][j], settle)));
    css(k.node, {
      width: `${w}px`, marginRight: `${gap}px`, color: `rgb(${c.join(",")})`, fontWeight: settle > 0.5 ? 600 : 500,
      opacity: appear * (k.drop ? 1 - seg(t, collapseA, collapseB - 0.2) : 1), transform: `translateY(${(1 - appear) * 10}px)`,
    });
    k.node.querySelector(".strike").style.width = k.drop ? `${100 * ease.out(seg(t, strikeA + i * 0.03, strikeA + 0.3 + i * 0.03))}%` : "0";
    const a = k.node.querySelector(".a"), b = k.node.querySelector(".b");
    if (b) { a.style.opacity = 1 - morph; b.style.opacity = morph; }
    total += w + gap;
  });

  const left = lerp(spec.cx - S.rawWidth / 2, spec.cx - total / 2, settle);
  const f = spec.fly;
  const fly = f ? ease.inOut(seg(t, f.t, f.t + 0.55)) : 0;
  css(S.root, {
    left: `${lerp(left, f ? f.x : left, fly)}px`, top: `${lerp(spec.y, f ? f.y : spec.y, fly)}px`,
    transform: `scale(${lerp(1, f ? f.scale : 1, fly)})`,
  });
  if (f) S.root.style.opacity = show * (1 - seg(t, f.t + 0.4, f.t + 0.6));

  const [raw, clean] = spec.labels || ["你说的", "整理后"];
  const label = S.root.querySelector(".label");
  const cleaned = t >= P + 1.0;
  label.textContent = cleaned ? clean : raw;
  label.style.color = cleaned ? "#5b6ff0" : "#8b8e98";
  label.style.opacity = (1 - fly) * (cleaned ? seg(t, P + 1.0, P + 1.3) : 1 - seg(t, P + 0.75, P + 1.0));
}

// Field: focus ring, blinking caret, text landing at `land` with a soft highlight.
// spec: { focus, land, text, html?, blinkFrom }
function renderField(fieldId, t, spec) {
  const f = $(fieldId);
  const on = t >= spec.land ? seg(t, spec.land, spec.land + 0.2) : 0;
  const txt = f.querySelector(".txt");
  const content = on > 0 ? (spec.html || spec.text) : "";
  if (txt.dataset.k !== String(on > 0)) { txt.innerHTML = content; txt.dataset.k = String(on > 0); }
  txt.style.opacity = on;
  f.querySelector(".ph").style.opacity = 1 - seg(t, spec.land - 0.05, spec.land + 0.05);
  const focused = t >= spec.focus;
  f.classList.toggle("focus", focused);
  const blink = Math.floor((t - (spec.blinkFrom ?? spec.focus)) * 2) % 2 === 0 ? 1 : 0;
  const busy = t > spec.land - 0.6 && t < spec.land + 0.8;
  f.querySelector(".caret").style.opacity = focused ? (busy ? 1 : blink) : 0;
  f.querySelector(".hl").style.opacity = 0.9 * window01(t, spec.land, spec.land + 1.1, 0.15, 0.6);
}
