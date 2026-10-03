# Utter 宣传片

三支 16:9 / 1920×1080 / 30 fps / 简体中文宣传片，共用同一套渲染引擎。

| 目录 | 时长 | 主题 | 分镜与文案 |
|---|---|---|---|
| `promo-offline/` | 28s | 本地语音输入：说出来就是文字，模型都在本机 | [storyboard](promo-offline/storyboard.md) |
| `promo-features/` | 51s | 功能一览：整理、指令、翻译、词库、风格、可选模型 | [storyboard](promo-features/storyboard.md) |
| `promo-day/` | 58s | 场景故事：产品经理的一天（有人物的插画） | [storyboard](promo-day/storyboard.md) |

## 成片

最终成片和封面放在 `docs/assets/videos/`，官网的“演示视频”区和 README 都直接引用这里的文件：`utter-offline-28s-zh-vo.mp4`、`utter-features-51s-zh-vo.mp4`、`utter-day-58s-zh-vo.mp4`。重新渲染后，把 `promo-*/dist/` 里的新成片和封面复制到这里；如果文件名变了，要同步修改 `docs/index.html` 和两份 README。

## 渲染

```bash
bash scripts/render-promo.sh promo-offline                    # → marketing/promo-offline/dist/<cues.output>
bash scripts/render-promo.sh promo-day --stills 3,12,20       # → marketing/promo-day/qa/*.png
```

依赖：Chromium（可用 `CHROMIUM=/path/to/chrome` 指定）、Node 18+、Python 3 + NumPy + SciPy、ffmpeg。`dist/` 和 `qa/` 不纳入版本库。本地预览：在任一 `scene/` 的上两级目录（`marketing/`）起静态服务，用浏览器打开 `promo-*/scene/index.html`，会循环播放无声画面。

## 结构

| 路径 | 内容 |
|---|---|
| `promo-kit/` | 共用引擎：`lib.js`（缓动、图标、镜头）、`desk.js`（桌面、窗口、HUD、片尾）、`hud.js`（Utter HUD 与波形，移植自 Swift 源码）、`spoken.js`（口述逐词、整理、飞入输入框）、`overlay.js`（字幕、标签、按键、页脚）、`render.mjs`（Chromium 逐帧截图）、`synth.py`（配乐与音效）、`assets/`（图标与真实设置界面截图） |
| `promo-*/scene/cues.json` | 该片唯一的时间表，画面和声音都从这里读；`output` 是成片文件名 |
| `promo-*/scene/*.js` | 该片的场景搭建和逐帧渲染（`renderAt(t)` 只依赖时间 t，保证逐帧确定） |
| `promo-*/score.py` | 该片的配乐与音效编排 |

## 标点规范

- 标题、字幕、标签、页脚、片尾标语：句末不加句号或逗号，句中标点照常；表达语气的问号保留（如“一天要写多少字？”）。
- 正文内容（聊天消息、邮件、口述整理结果、清单条目）：保留完整标点，因为补标点本身就是演示的整理效果。
- 配音稿（`voice.json`）：保留标点，用来控制停顿和语调，不上屏。

## 配音（ElevenLabs）

每支片的 `voice.json` 是配音稿：

- `speaker`：口述者，ElevenLabs 音色 ShanShan，念“按住 fn 说的那句话”。
- `narrator`：旁白，音色 Evan Zhao，只出现在口述结束后的空档里，不和口述重叠。

两者都用 `eleven_v4` 模型，`language_code=zh`。`eleven_multilingual_v2` 会把“离线”读成“吃线”，所以没有采用。

```bash
python3 marketing/promo-kit/voice.py marketing/promo-day          # 生成或复用配音，并按真实音频重排时间线
python3 marketing/promo-kit/voice_check.py marketing/promo-day    # 用 speech-to-text 回检，输出逐句字错率
bash scripts/render-promo.sh promo-day                            # 混音并出片
```

- **缓存**：`voice.py` 只在文案、音色或参数变化时调用 `elevenlabs text-to-speech convert_with_timestamps`。原始音频（`*.raw.mp3`）和字符时间戳（`*.json`）都存在 `voice/` 里，重新出片不需要 ElevenLabs 账号。
- **变速**：eleven_v4 不认 `speed` 参数，所以语速用 ffmpeg `atempo` 在本地调整（口述 1.18 倍、旁白 1.1 倍），时间戳按同样比例缩放。
- **口述对齐**：用字符时间戳重排屏幕上的逐词字幕和 HUD 波形，松开按键的时间放在最后一个字之后 0.3 秒，之后的时间线整体顺延。
- **旁白对齐**：旁白如果会挤进下一段，就把下一段往后推。
- **结果清单**：`voice/manifest.json` 记录每条配音的位置，`check.json` 记录回检结果。

## 声音

除配音外，所有声音都由 `synth.py` 现场合成：一层铺底和弦，演示段加轻底鼓和低音，每段一个铃音，再加少量与画面动作一一对应的 UI 音。录音开始/结束提示音复刻 `SoundPlayer.swift`。有音效时铺底自动压低约 45%，有人声时压低约 60%。除 ElevenLabs 配音外没有第三方素材，也没有系统合成语音。

## 素材授权

图标和截图归本项目所有。字体使用 Noto Sans CJK SC（SIL OFL）。插画（含人物）为 `promo-day/scene/illus.js` 与 `illus-parts.js` 中的手写 SVG。ElevenLabs 的图像生成需要 Pro 套餐，当前 Creator 套餐不可用，因此没有使用 AI 生成画面。
