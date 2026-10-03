// Frame-space overlay renderers driven by [start, end, ...] tables.
function setHTML(node, html) {
  if (node.dataset.k !== html) { node.innerHTML = html; node.dataset.k = html; }
}

function renderCaption(t, rows) {
  const row = activeRow(t, rows), node = $("caption");
  if (!row) { node.style.opacity = 0; return; }
  setHTML(node, row[2]);
  css(node, { opacity: window01(t, row[0], row[1], 0.3, 0.25),
    transform: `translateX(-50%) translateY(${(1 - ease.out(seg(t, row[0], row[0] + 0.4))) * 14}px)` });
}

function renderHeadline(t, rows) {
  const row = activeRow(t, rows), node = $("headline");
  if (!row) { node.style.opacity = 0; return; }
  setHTML(node.querySelector(".h"), row[2]);
  setHTML(node.querySelector(".s"), row[3] || "");
  if (row[4]) css(node, row[4]);
  css(node, { opacity: window01(t, row[0], row[1], 0.4, 0.25),
    transform: `translateY(${(1 - ease.outExpo(seg(t, row[0], row[0] + 0.6))) * 30}px)` });
}

// Feature tag in the top-left corner: [start, end, "01", "智能整理"].
function renderTag(t, rows) {
  const row = activeRow(t, rows), node = $("tag");
  if (!row) { node.style.opacity = 0; return; }
  setHTML(node.querySelector(".num"), row[2]);
  setHTML(node.querySelector(".tx"), row[3]);
  css(node, { opacity: window01(t, row[0], row[1], 0.3, 0.25), transform: `translateX(${(1 - ease.out(seg(t, row[0], row[0] + 0.4))) * -16}px)` });
}

function renderFoot(t, rows) {
  const row = activeRow(t, rows), node = $("foot");
  node.style.opacity = row ? window01(t, row[0], row[1], 0.3, 0.25) : 0;
  if (row) setHTML(node, row[2]);
}

function renderChip(t, a, b, text) {
  const node = $("chip");
  node.style.opacity = window01(t, a, b, 0.35, 0.25);
  if (text) setHTML(node.querySelector("span"), text);
}

// Key press rows: [down, up, ["fn"] | ["fn", "shift"]].
function renderKeys(t, rows) {
  const node = $("keys");
  const row = rows.find(([down, up]) => t >= down - 0.5 && t < up + 0.8);
  if (!row) { node.style.opacity = 0; return; }
  const [down, up, caps] = row;
  setHTML(node, caps.map((c) => KEYCAP[c]).join('<span class="plus">+</span>') + '<span class="lbl"></span>');
  node.style.opacity = window01(t, down - 0.45, up + 0.75, 0.25, 0.3);
  const press = t >= up ? 1 - ease.out(seg(t, up, up + 0.12)) : ease.out(seg(t, down, down + 0.08));
  node.querySelectorAll(".cap").forEach((cap) => css(cap, {
    transform: `translateY(${8 * press}px)`,
    boxShadow: `0 0 0 1px rgba(0,0,0,.08), 0 ${10 - 8 * press}px 0 #c9cbd2, 0 ${18 - 10 * press}px 30px rgba(30,30,60,.2)`,
    background: press > 0.5 ? "linear-gradient(180deg,#f1f2ff,#e2e5fb)" : "",
  }));
  node.querySelector(".lbl").textContent = t < up ? "按住" : "松开";
}

function renderEnd(t, t0) {
  const end = $("end");
  if (t < t0) { end.style.opacity = 0; return; }
  end.style.opacity = 1;
  const pop = (sel, a, dy = 22) => {
    const n = end.querySelector(sel);
    if (!n) return;
    const p = ease.out(seg(t, a, a + 0.5));
    css(n, { opacity: p, transform: `translateY(${(1 - p) * dy}px)` });
  };
  const s = ease.spring(seg(t, t0, t0 + 0.7));
  css(end.querySelector("img"), { opacity: seg(t, t0, t0 + 0.25), transform: `scale(${lerp(0.82, 1, s)})` });
  pop(".name", t0 + 0.2);
  pop(".l1", t0 + 0.45);
  pop(".l2", t0 + 0.8);
  pop(".feat", t0 + 1.15, 12);
  pop(".url", t0 + 1.35, 14);
  pop(".meta", t0 + 1.6, 10);
}

function renderWindowIn(id, t, tIn, tOut = 1e9) {
  const p = ease.out(seg(t, tIn, tIn + 0.45)) * (1 - ease.inOut(seg(t, tOut, tOut + 0.35)));
  css($(id), { opacity: p, transform: `translateY(${(1 - p) * 22}px) scale(${lerp(0.97, 1, p)})` });
}
