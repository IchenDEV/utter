// Renders <promo>/scene/index.html frame by frame through headless Chromium.
//   node render.mjs <promoDir> --out <file.mp4>            full video (no audio)
//   node render.mjs <promoDir> --stills 2.5,10 --dir <qa>   QA stills
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import puppeteer from "puppeteer-core";

const promoDir = resolve(process.argv[2]);
const sceneDir = resolve(promoDir, "scene");
const cues = JSON.parse(readFileSync(resolve(sceneDir, "cues.json"), "utf8"));
const arg = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : fallback;
};

const browser = await puppeteer.launch({
  executablePath: process.env.CHROMIUM || "/usr/bin/chromium",
  headless: true,
  args: ["--allow-file-access-from-files", "--force-color-profile=srgb", "--font-render-hinting=none", "--hide-scrollbars"],
});
const page = await browser.newPage();
await page.setViewport({ width: cues.width, height: cues.height, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(resolve(sceneDir, "index.html")).href, { waitUntil: "load" });
await page.evaluate((c) => window.initScene(c), cues);

const shot = async (t) => {
  await page.evaluate((x) => window.renderAt(x), t);
  return page.screenshot({ type: "png", optimizeForSpeed: true });
};

const stills = arg("stills");
if (stills) {
  const dir = resolve(arg("dir", resolve(promoDir, "qa")));
  mkdirSync(dir, { recursive: true });
  for (const t of stills.split(",").map(Number)) {
    await page.evaluate((x) => window.renderAt(x), t);
    await page.screenshot({ path: resolve(dir, `t${t.toFixed(2).padStart(5, "0")}.png`) });
  }
} else {
  const out = resolve(arg("out", resolve(promoDir, "dist/video-only.mp4")));
  mkdirSync(dirname(out), { recursive: true });
  const ff = spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(cues.fps), "-i", "-",
    "-c:v", "libx264", "-preset", "slow", "-crf", "14", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out],
    { stdio: ["pipe", "inherit", "inherit"] });
  const total = Math.round(cues.duration * cues.fps);
  for (let f = 0; f < total; f++) {
    const buf = await shot(f / cues.fps);
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once("drain", r));
    if (f % 60 === 0) process.stdout.write(`frame ${f}/${total}\n`);
  }
  ff.stdin.end();
  await new Promise((r) => ff.on("close", r));
}
await browser.close();
