# 本地语音质量评测

在 macOS 26 的 Apple Silicon Mac 上运行。先在模型页安装所需模型，并记下
完整目录和模型 ID。评测只使用指定的本地资产；缺失或损坏的资产会终止运行。
构建步骤需要已有的 SwiftPM 依赖，模型推理不下载资产或调用远端服务。

## 整理、术语和事实保护

固定语料 [voice-reliability.jsonl](evals/voice-reliability.jsonl) 包含 56 个用例、
88 次运行：8 个宣传片示例各运行 5 次，另有清单、叙事、回复、翻译，以及
20 个合法删减和 20 个固定新增事实候选。固定候选用于验证防线，报告会与
完整模型生成区分。

```bash
bash scripts/evaluate-voice.sh \
  --corpus docs/evals/voice-reliability.jsonl \
  --model '/absolute/path/to/installed/model' \
  --model-id 'mlx-community/Qwen3.5-2B-4bit' \
  --output /tmp/utter-voice-warm.jsonl
```

输出路径必须不存在，且不能位于模型目录内。加 `--cold` 可在每次运行前
卸载模型；使用另一个输出路径保留冷、热两份结果。
默认最多 100 次运行、每次 120 秒、总计 3600 秒、每次最多预留 4096 个输出
token。自定义风格的主生成与事实检查共用该预算。可用 `--max-runs`、
`--case-timeout`、`--total-timeout` 和 `--max-tokens` 明确调整。
超时会取消并等待工作清理，清理时间可能超过截止时间；不提前释放仍在使用的资产。

报告包含生产提示词、生成候选、最终文本、回退原因和分段耗时，因此只使用
合成或已经获准的样本。评测宿主不录音、不读取真实屏幕、不写入光标、历史
或个人词典。屏幕、词典和上下文由语料注入。
Qwen 使用所选行业词库与个人词典的共享快照，再限制为最多 8 个词和有限
上下文长度；不保证每次包含整份词库，也不将上下文传递视为识别收益。
旁边的 `.manifest.json` 记录提交、模型资产指纹、预算和预期运行数。
指纹包含文件大小、修改时间和 JSON 内容摘要，不是所有模型权重的内容校验和。
中断或失败留下 `partial` 状态，不能作为完成报告。

## 音频识别

在 JSONL 用例加入 `audio_file`，并提供整个语音参数组：

```bash
bash scripts/evaluate-voice.sh \
  --corpus /absolute/path/to/audio-corpus.jsonl \
  --model '/absolute/path/to/text-model' \
  --model-id 'mlx-community/Qwen3.5-2B-4bit' \
  --speech-provider whisper \
  --speech-model '/absolute/path/to/whisper-large-v3' \
  --speech-model-id large-v3 \
  --output /tmp/utter-audio.jsonl
```

支持 `whisper`、`qwen`、`firered`、`mega`；MLX 语音模型 ID 必须属于应用
目录中的对应模型。Whisper 目录必须包含匹配 variant 的本地 tokenizer。
相对音频路径按语料目录解析，每段不超过 10 分钟。`faithful_reference` 是
人工转写，`asr_text` 记录实际识别结果。没有 `audio_file` 的用例直接使用
语料文本，不提供识别质量证据。

## 评分与复核

```bash
python3 scripts/evaluate-voice-quality.py /tmp/utter-voice-warm.jsonl
```

评分包含已有字符/术语指标和 `acceptance`。词面差异不等同于新增事实；
自定义风格允许删除信息。工程门槛要求完整报告、全部宣传片示例、至少 95%
合法删减通过、20 个新增事实候选全部回退。

复核每条最终文本与源文的事实和对象关系，在报告副本中填入：

```json
{"semantic_review":"approved","fact_review":{"added_facts":[],"object_mismatches":[]}}
```

发现问题则标为 `rejected`，并在对应数组中描述事实新增或对象错配。
复制报告时同步复制同名 `.manifest.json`，或通过 `--manifest` 指向原始 manifest。
仅当工程门槛与逐条复核都通过时，`acceptance_pass` 才为 true。
缺失运行、未复核样本和普通 CI 测试均不能替代真实模型质量结果。

## 松开按键至确认插入的耗时

会话以 Notice 级别记录 ID、终点和耗时，不记录口述或生成正文。系统日志会
按容量轮换，并非永久存储。日志等级的持久化行为见
[Apple 日志说明](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code)。
导出 macOS 日志后统计：

```bash
log show --last 10m --style ndjson \
  --predicate 'subsystem == "com.opentype.voiceinput"' \
  | python3 scripts/evaluate-session-performance.py -
```

报告分别列出终点数量，仅确认插入的会话计入完成延迟 p50/p95；复制、失败、
取消和结果不确定不计为成功插入。无按键释放时间的操作不计为零毫秒。
模型页基准使用生产提示词，按短/中/长和冷/热分组显示样本数与 p50/p95。
