# Utter 行业词库、上下文偏置与可重复评测调研

> 日期：2026-08-24
> 状态：研究结论与评测门禁提案；**没有把尚未跑过的真实音频评测写成“已通过”**
> 范围：桌面语音输入的行业术语增强，医疗优先；兼顾本地 Apple Speech、Whisper/Qwen 与可选云端 ASR
> 证据口径：`[事实]` 来自官方标准、政府/专业组织或厂商原始文档；`[建议]` 是针对 Utter 的产品与工程判断；`[未知]` 表示原始页面没有给出足以支持商业再分发的许可。

## 1. 结论先行

1. `[事实]` 主流 ASR 的“行业词库”本质是**上下文偏置**，不是输入法式的全量词典替换。Apple 建议 contextual phrases 尽量只有一两个词、总数不超过 100；Google 明确提醒 boost 越高越容易产生假阳性；火山也要求避免单字、常见词和无实体意义的高频词。[Apple `contextualStrings`](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings)、[Google PhraseSet boost](https://cloud.google.com/speech-to-text/docs/reference/rest/v1/projects.locations.phraseSets)、[火山引擎热词](https://www.volcengine.com/docs/6561/155739?lang=zh)
2. `[建议]` Utter 不应把几千或几万条行业词全部塞进每次解码，而应维护一个有来源的完整行业包，再按语言、当前 App/窗口、屏幕词、最近使用和用户个人词典，**每次动态选择最多 100 条短词**送给 Apple；Whisper/Qwen 使用同一选择结果映射到各自的 prompt/context。
3. `[建议]` 首批内置顺序应为：**医疗 + IT/网络安全（P0）**，然后金融、能源（P1），航空航天（P2）。医疗感知价值最高，但中文权威资源的商业再分发权最不清晰；IT/网络安全有微软多语言术语和 NIST JSON，最容易形成许可可审计的第二个行业包。
4. `[事实]` 医疗领域不能把“权威”与“可随 App 分发”混为一谈。SNOMED CT 要求供应商成为 Affiliate 并管理 sublicense；WHO ICD-11 是 CC BY-ND 3.0 IGO；术语在线明确标注版权所有；国家卫健委下载页没有为 App 内置词库给出明确再分发许可。[SNOMED 供应商许可](https://docs.snomed.org/snomed-ct-practical-guides/vendor-introduction-to-snomed-ct/7-licensing)、[ICD-11 许可](https://icd.who.int/docs/icd-api/license/)、[术语在线](https://www.termonline.cn/)、[国家卫健委疾病代码表](https://www.nhc.gov.cn/mohwsbwstjxxzx/dczlxz/201809/8e46a2feccac441a9d080fce33aba60d.shtml)
5. `[建议]` 第一版医疗包应只使用许可已核清的 MeSH/LOINC 子集和团队原创、经医学专家复核的中文 spoken-form 映射；不得抓取术语在线、SNOMED 或国家临床版整表后直接打包。
6. `[建议]` “测试通过”必须表示同一批真实录音在**行业包关闭/开启**两种条件下做配对比较，同时满足术语召回提升、通用 CER/WER 不退化、负样例不误吸附、数字/单位完全保真和延迟门禁。单元测试、TTS 样例或几个手工口述只证明管线可运行，不能证明行业识别效果已通过。

## 2. 官方 ASR 能力说明了怎样的产品形态

| 能力 | 官方事实 | 对 Utter 的直接含义 |
|---|---|---|
| Apple 运行时短语 | `SFSpeechRecognitionRequest.contextualStrings` 和 macOS 新 Speech framework 的 `AnalysisContext.contextualStrings` 用于提高系统词表外短语的识别概率；建议一到两个词，总计不超过 100。[旧 API](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings)、[新 API](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings) | 每次只挑最相关的 100 条，不能把全行业包直接送入 Apple ASR。 |
| Apple 自定义语言模型 | `SFCustomLanguageModelData` 能加入带 count 的偏置短语，以及用 X-SAMPA 表示的自定义发音；已有系统词汇或不支持的音素会被忽略。[训练数据对象](https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata)、[自定义发音](https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata/custompronunciation)、[加权短语](https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata/phrasecount) | 稳定行业包可在运行时短语 A/B 通过后，再升级为按 locale/version 编译的本地语言模型；发音不是简单别名字段。 |
| Whisper 初始提示 | OpenAI Whisper 官方实现提供 `initial_prompt`，并把它编码成首窗 prompt tokens；prompt 受模型文本上下文预算约束。[官方 `transcribe.py`](https://github.com/openai/whisper/blob/main/whisper/transcribe.py) | 传规范拼写和短术语序列，不传定义、说明或“请正确识别”之类编辑指令。每段滚动且严格限 token。 |
| Qwen3-ASR context | Qwen 官方 API toolkit 的 `--context` 是“引导 ASR、改善特定术语识别”的文本上下文。[Qwen3-ASR Toolkit](https://github.com/QwenLM/Qwen3-ASR-Toolkit) | 与 Whisper 共用经过净化和限量的 context 文本；是否支持当前本地运行器仍须以实际版本和调用链验证。 |
| 火山热词表 | 官方文档支持中英文，每表最多 5000 个热词、每词少于 10 个字、权重 1–10；数字/特殊符号要转为口述形式，并明确要求避免常见词和无实体高频词。[热词管理](https://www.volcengine.com/docs/6561/155739?lang=zh) | 源数据应同时保存 `canonical` 与 `spokenForms`；向火山发送时做供应商特定序列化，不能把供应商约束污染通用词库。 |
| Google PhraseSet | PhraseSet/CustomClass 用于提高稀有词和常用短语概率；官方称推荐 boost 通常为 0–20，并明确更高 boost 会提高假阳性风险，建议二分调参。[模型适配](https://cloud.google.com/speech-to-text/docs/adaptation-model)、[PhraseSet API](https://cloud.google.com/speech-to-text/docs/reference/rest/v1/projects.locations.phraseSets) | 必须有“词未出现”的负样例；权重只能由评测调出，不能按词库来源主观设成最高。 |
| AWS 自定义词表 | Amazon Transcribe 表格包含 `Phrase` 与 `DisplayAs`；当前官方说明 `IPA` 和 `SoundsLike` 已不再支持并会被忽略，`DisplayAs` 可保存 C++ 等符号形式。[自定义词表表格](https://docs.aws.amazon.com/transcribe/latest/dg/custom-vocabulary-create-table.html) | 通用 schema 可保留 spoken form，但供应商 adapter 必须声明真实支持范围；不能因为字段存在就声称该引擎使用了发音。 |

由这些接口可以得到一个稳定结论：**行业包是候选词来源，ASR adapter 决定如何偏置，后处理器只做有证据的规范化**。三者需要分层，否则很容易出现“词库里有某词，所以把所有近音普通词都替换成它”的误改。

## 3. 可用行业术语源与再分发边界

### 3.1 医疗：权威资源多，但许可必须逐源处理

| 资源 | 能提供什么 | 可再分发性判断 | 第一版用法 |
|---|---|---|---|
| NLM MeSH | 生物医学主题词、同义词和层级；NLM 提供 XML、RDF、MARC 下载及 API。[MeSH 下载](https://www.nlm.nih.gov/databases/download/mesh.html) | **有条件可用。** NLM 条款要求显著注明来源；再分发者要保持最新版本，或明确说明不是最新数据。NLM 同时提醒数据可能包含在美国或美国之外受版权保护的材料。[NLM 数据条款](https://www.nlm.nih.gov/databases/download.html) | 优先抽取 descriptor/entry term 的英文规范拼写和同义词；保留 production year、ID、源 URL 和 NLM acknowledgement。不要打包 scope note/第三方文本。 |
| LOINC | 实验室检查与临床观察的代码、long common name、short name、display name。[LOINC](https://loinc.org/) | **有条件可用。** 官方许可允许商业/非商业使用、复制和分发，但要求产品内 notice、版本/发布日期；带第三方版权的行必须一并保留相应 notice，Part/RSNA/SNOMED 关联还有额外限制。[LOINC License](https://loinc.org/license) | 只取最常听写的检验/生命体征名称；构建时排除或单独审计 `EXTERNAL_COPYRIGHT_NOTICE` 非空记录，随 App 提供要求的 notice。 |
| WHO ICD-11 | 疾病分类，多语言内容与 API；官方 API 首页提供注册访问和本地部署选项。[ICD API](https://icd.who.int/icdapi) | **先不打包。** 内容是 CC BY-ND 3.0 IGO；官方说明映射、crosswalk 和翻译不在通用许可内，需要另行书面协议。[许可页](https://icd.who.int/docs/icd-api/license/)、[许可说明 PDF](https://icd.who.int/en/docs/icd11-license.pdf) | 可用作人工核对来源；在法务确认“抽取子集 + 添加 spoken form”是否构成改编前，不纳入可再分发包。 |
| SNOMED CT | 广泛的临床概念、描述和关系。[获取 SNOMED CT](https://www.snomed.org/get-snomed) | **不可作为无条件内置包。** 产品供应商需成为 Affiliate；向用户提供含 SNOMED 的产品还要管理 sublicense，非成员地区可能收费和申报。[供应商许可指南](https://docs.snomed.org/snomed-ct-practical-guides/vendor-introduction-to-snomed-ct/7-licensing) | 只作为未来持牌企业版选项；不放入普通安装包和公共测试语料。 |
| 全国科技名词委 / 术语在线 | 国务院授权的科技名词审定机构；官网称已审定公布 60 万条规范名词，术语在线称汇聚 80 多万条。[全国科技名词委](https://www.cnctst.cn/)、[术语在线服务介绍](https://new.termonline.cn/languageCommittee/) | **未知，默认不可再分发。** 委员会官网和术语在线均标明版权所有，未找到允许商业 App 批量抓取、修改和再分发的公开许可。[术语在线](https://www.termonline.cn/) | 中文词形的人工核对与专家审核入口；未经书面许可不抓整库、不复制定义、不把搜索结果批量打包。 |
| 国家卫健委 / 国家中医药管理局公开附件 | 疾病分类国家临床版使用线索、中医病证分类与临床诊疗术语附件。[疾病分类标准说明](https://www.nhc.gov.cn/mohwsbwstjxxzx/s8553/201610/25a695abe55c464897777c30290cc4d3.shtml)、[中医术语通知及附件](https://www.gov.cn/zhengce/zhengceku/2020-11/24/content_5563703.htm) | **未知。** 公开下载与政策要求使用不等于授权第三方 App 批量复制、改写和再分发；原始页面未给出适用于该场景的许可。 | 作为需求/规范核对；若要入包，先取得权利方书面确认，并固定具体附件版本与校验和。 |
| RxNorm | 美国药品规范名称、RXCUI 等；NLM 提供 full release 和 current prescribable content。[RxNorm files](https://www.nlm.nih.gov/research/umls/rxnorm/docs/rxnormfiles.html) | **不适合直接整包。** full release 需要 UMLS 协议，且可能含第三方专有词表；NLM FAQ 说明即使 RxNorm 本身不收费，源词表仍可能需要额外许可。[RxNorm FAQ](https://www.nlm.nih.gov/research/umls/rxnorm/faq.html) | 只在逐行 source vocabulary 审计后考虑美国药名子集；中国市场药品名应另找有明确许可的权威来源。 |

医疗包的实用边界：它是**听写辅助，不是诊断编码器**。疾病名、药名、检验名和术式即使拼写正确，也不能证明医学事实或编码正确；任何数字、剂量、左右侧、阴阳性和否定词都必须保真，并允许用户快速回看原始识别。

### 3.2 适合作为后续内置包的其他行业

| 优先级 | 行业与来源 | 权威性和数据形态 | 许可/风险 | 建议 |
|---|---|---|---|---|
| P0 | IT/软件：Microsoft Terminology | 微软官方称术语可作为 IT glossary 基础，支持近 100 种语言并提供 TBX 下载，适合直接取得 `zh-CN ↔ en-US` 规范界面和技术词。[术语资源](https://learn.microsoft.com/en-us/globalization/reference/microsoft-terminology) | 官方 Globalization License 授予使用、复制和分发权，但要求下游条款至少同等保护、显示版权 notice，并含 indemnity 条款；上线前需把条件落实到 App 许可和第三方 notices。[许可](https://learn.microsoft.com/en-us/globalization/license-agreement) | 与医疗同时做 P0。只选技术名词，不把完整产品句子当词条；保留 Microsoft attribution。 |
| P0 | 网络安全：NIST CSRC Glossary | NIST 官方在线 glossary 聚合 NIST/CNSSI 标准、指南和技术出版物术语，提供每日更新 JSON；页面当前显示 10,000+ term records，并提示同一词可能有多种来源定义。[NIST Glossary](https://csrc.nist.gov/glossary) | NIST 网页除明确标注版权内容外视为公共信息，可分发/复制并建议署名；但 glossary 也聚合其他来源，不能把所有定义自动视为 NIST 原创。[NIST reuse](https://www.nist.gov/copyrights-disclaimers) | 优先取 term/abbreviation，不打包定义；按 source document 去重，保留 NIST/CNSSI 来源，过滤第三方版权标记。 |
| P1 | 金融：EDM Council FIBO | 专业组织维护的金融业务本体，覆盖实体、贷款、证券、衍生品、指数、市场数据；官方 ontology guide 说明其目标包含金融术语标准化，发布 ontology 使用 MIT。[FIBO repo](https://github.com/edmcouncil/fibo)、[Ontology Guide](https://github.com/edmcouncil/fibo/blob/master/ONTOLOGY_GUIDE.md) | MIT 许可清晰；标签以英文为主，自动机翻不能冒充行业规范中文。 | 提取 release maturity 的 `rdfs:label`/synonym，中文由金融专家与公开可授权来源复核。优先高频产品、指标和机构词，不把关系本体整体塞入 ASR。 |
| P1 | 能源：U.S. EIA Glossary | 美国能源信息署官方 glossary，覆盖煤、电力、天然气、核能、石油、可再生能源等分类。[EIA Glossary](https://www.eia.gov/tools/glossary/index.php) | EIA 明确允许使用/分发其网站数据、文件、数据库和信息产品，建议注明来源与日期；第三方受保护材料例外。[EIA copyrights and reuse](https://www.eia.gov/about/copyrights_reuse.php) | 许可风险低，适合做英文能源包；中文名称需独立复核并标注翻译责任方。 |
| P2 | 航空/航天：FAA Pilot/Controller Glossary + NASA Thesaurus | FAA glossary 当前有约 1,300 个空管通信术语；NASA Thesaurus 提供 SKOS、OWL、ZThes、CSV/TXT 的完整机器可读下载。[FAA glossary](https://www.faa.gov/air_traffic/publications/atpubs/pcg_html/)、[NASA Thesaurus](https://www.sti.nasa.gov/nasa-thesaurus/) | 美国政府内容通常可复用，但 FAA 明确混入标记为 `[ICAO]` 的术语，NASA/FAA 页面也可能包含第三方材料；全球分发前应过滤并做一次源级许可审计。航空又是安全关键场景。 | 先做内部 benchmark，不作为第一批默认开启；排除 `[ICAO]`/第三方来源，用户主动选择后启用。 |
| P2 | 欧盟公共事务/法律：EuroVoc | 欧盟出版局维护的 24 个欧盟语言加 3 个候选国语言的多学科词库，提供多种 RDF/SKOS/XML/Excel 发布格式。[EuroVoc](https://op.europa.eu/en/web/eu-vocabularies/dataset/-/resource?uri=http%3A%2F%2Fpublications.europa.eu%2Fresource%2Fdataset%2Feurovoc) | 欧委会有开放复用文件政策，但具体数据包仍应读取其版本 metadata/rights；没有中文，中文翻译不能继承原标签权威性。[欧委会文件复用决定](https://eur-lex.europa.eu/legal-content/EN/ALL/?uri=CELEX%3A32011D0833) | 仅在欧洲语言用户需求明确时加入，不占首批中文资源。 |

## 4. 首批内置包建议

### 4.1 P0：医疗

`[建议]` 完整包目标不是越大越好，而是覆盖高价值、易错、常用且可授权的术语。第一版建议按以下桶采样，每条都要有至少一个真实音频回归样例：

- 疾病/症候与常用别称：例如规范名、临床简称、容易与普通词混淆的近音词。
- 检验与生命体征：LOINC 高频项目、完整中文名、常见英文缩写；数值和单位不作为可自由替换文本。
- 常用通用名药物：仅纳入许可来源清楚的通用名；商品名和不同市场药名另表管理。
- 手术/检查/治疗：长术式、英文缩写和中英混说。
- 解剖部位、左右侧、分级、阴阳性、给药途径：这些属于高风险保护项，宁可不改也不能猜。

完整行业包可以有数百至数千条，但 Apple 单次激活集合仍不得超过 100。默认行业包不能覆盖医院内部简称、医生姓名、院内药品商品名和科室模板，这些应由组织词库/个人词典覆盖，优先级高于内置行业包。

### 4.2 P0：IT/网络安全

`[建议]` 这是最适合验证通用框架的第二个包：中英混说、大小写、缩写和符号形式多，且 Microsoft TBX 与 NIST JSON 都是机器可读官方来源。优先覆盖：

- 操作系统、云服务、网络协议、编程语言和常见工具名；
- 认证、加密、漏洞、威胁建模、零信任等安全术语；
- `canonical` 与口述形式分开，例如显示 `Kubernetes`，口述可记录为用户实际读法；
- C++、C#、IPv6 等符号词必须通过引擎 adapter 转换，不能让通用清洗删除符号。

### 4.3 P1：金融与能源

金融词通常涉及数值、百分比、币种、期限和否定条件，能源词通常涉及单位、化学式和缩写。两者都应复用医疗的“保护数字/单位 + 负样例”门禁。FIBO/EIA 只提供英文权威基础；中文正式发布前必须由相应行业人员复核，不应直接把机器翻译标为 `approved`。

## 5. 词库数据模型与构建规则

W3C SKOS 把 `prefLabel`、`altLabel`、`hiddenLabel` 分开；这很适合作为 canonical、可显示别名和只用于匹配的口述形式的概念基础。[SKOS Reference](https://www.w3.org/TR/skos-reference/)、[SKOS Primer](https://www.w3.org/TR/skos-primer/Overview.html)

建议的最小运行时条目：

```json
{
  "id": "medical:loinc:4548-4",
  "industry": "medical",
  "locale": "zh-CN",
  "canonical": "糖化血红蛋白",
  "aliases": ["血红蛋白 A1c", "HbA1c"],
  "spokenForms": ["糖化血红蛋白", "艾尺比艾万西"],
  "doNotReplace": ["糖化血红蛋白数值", "阴性", "阳性"],
  "baseWeight": 0.6,
  "sourceId": "LOINC:4548-4",
  "sourceVersion": "<pinned release>",
  "sourceURL": "https://loinc.org/4548-4/",
  "licenseId": "LicenseRef-LOINC",
  "redistribution": "conditional",
  "reviewStatus": "needs-medical-review"
}
```

上例只说明字段，不代表该中文 spoken form 已获医学/语音学审核，也不代表该 LOINC 行没有第三方 notice。

构建规则：

1. `locale` 使用 BCP 47 标签，不用含糊的 `Chinese`/`English`；BCP 47 定义了语言标签结构与语义。[RFC 5646](https://www.rfc-editor.org/info/rfc5646/)
2. `canonical` 是最终可显示形式；`aliases` 可以显示；`spokenForms` 只用于 ASR/context 匹配，默认不能直接覆盖输出。
3. 每个同形异义概念独立 ID；不能仅以字符串做主键。
4. 统一做 Unicode normalization，但原始 spelling 仍须保留；Unicode UAX #15 说明 NFC/NFKC 的等价与兼容分解差异。[Unicode normalization](https://unicode.org/reports/tr15/)
5. 每个 source 有单独 manifest：版本、下载时间、原始 URL、校验和、许可全文/URL、attribution、允许字段、排除条件、是否允许翻译/修改/商业分发。
6. `licenseId` 优先使用 SPDX short identifier；非 SPDX 许可用稳定的 `LicenseRef-*`，不能为了方便把自定义条款写成 `CC0` 或 `MIT`。[SPDX License List](https://spdx.org/licenses/)
7. 构建器默认拒绝 `redistribution = unknown/restricted` 的条目进入 App bundle；内部研究集和可分发产品集必须物理分离。
8. 定义、scope note 和例句默认不进入运行时包。ASR 只需要短词、别名、发音和少量权重；少复制文本也降低许可和包体风险。

## 6. 建议的识别与后处理链路

```text
用户选择行业包
  → 合并组织词库、个人词典、当前屏幕/窗口候选
  → 按 locale、近期度、稀有度、当前上下文和历史命中选 Top-K
  → 引擎 adapter（Apple contextualStrings / Whisper prompt / Qwen context / 云端热词表）
  → 原始 ASR
  → 仅基于 ASR 候选、canonical/alias 与上下文做忠实规范化
  → 数字、单位、左右侧、阴阳性、否定词和药物剂量 guard
  → 最终文本 + 本地质量诊断
```

关键约束：

- 常见词、单字、否定词和数字不参与正向 boost。
- 同一概念的多个 spoken form 共享总权重，避免枚举越多权重越高。
- 行业包只改变候选概率，不允许 LLM 因“医学上更合理”而补充未说出的诊断、剂量、结论或动作。
- 当词典命中与原始声学结果冲突或后处理 guard 失败时，回退原始 ASR，不进行强制替换。
- 离线行业版的词库选择、prompt 生成、评测日志和更新都应留在本机；远程 ASR 只有用户显式启用时才上传其所需热词。
- 行业包版本随评测结果一起固定。换源版本、翻译、权重、模型或 prompt 都视为新的待评测配置。

## 7. 可重复评测标准

### 7.1 评测设计

`[事实]` NIST SCTK 的 `sclite` 按插入、删除、替换进行标准 ASR 对齐计分；其文档还指出普通话在词边界不明确时常以字符错误为主要指标。[SCTK `sclite`](https://github.com/usnistgov/SCTK/blob/master/doc/sclite.htm)、[Mandarin scoring options](https://github.com/usnistgov/SCTK/blob/master/doc/options.htm)

`[建议]` 每个行业使用冻结的音频 corpus，对完全相同的音频、模型、解码参数运行两次：

- `control`：行业包关闭，个人词典和其他上下文保持相同；
- `treatment`：只打开指定行业包；
- raw ASR 与 processed text 分别计分，不能用后处理改善掩盖 ASR 退化；
- 按 utterance ID 做配对差异，报告 95% paired-bootstrap confidence interval；区间跨过门禁时结论为“证据不足”，而不是“通过”。

首期每个行业至少包含：

| 分层 | 最低规模 | 目的 |
|---|---:|---|
| 术语正样例 | 200 条 utterance，至少 300 次目标术语出现 | 测 canonical/alias 的 exact recall；每个目标词至少 3 个不同上下文，不用背诵词表。 |
| 近音负样例 | 100 条 utterance | 目标行业词**没有被说出**，但包含常见词、近音词或相邻领域词，测误吸附。 |
| 通用回归 | 100 条 utterance | 日常聊天、邮件、开发文本、静音/短音频，确认开启行业包没有伤害一般输入。 |
| 高风险槽位 | 100 条 utterance | 数字、单位、剂量、左右侧、阴阳性、否定、日期、币种/百分比，要求 exact fidelity。 |

真实录音至少覆盖 10 名说话人、男女声、不同年龄/口音、内置麦与常见蓝牙/USB 麦、安静与两档噪声。TTS 可用于确定性 CI smoke test，但不能代替真实口音和声学条件。

### 7.2 指标

| 指标 | 定义 | 为什么需要 |
|---|---|---|
| 中文 CER / 英文 WER | 与冻结 reference 做字符/词编辑距离；分 raw ASR 与 processed 两套报告。 | 防止只挑术语样例而整体退化。 |
| Term Exact Recall | `正确出现的目标 canonical 数 / reference 中目标 canonical 数`；多次出现逐 occurrence 计数，不只看“本条是否出现过”。 | 衡量行业词真正被识别的比例。当前 evaluator 的 `terms exact` 是 per-record presence，正式门禁应升级为 occurrence 级。 |
| Term False Insertion Rate | `未说目标词但输出了行业词的负样例数 / 负样例数`，同时列出混淆对。 | 直接发现 boost 过高和盲目后处理替换。 |
| Protected Fidelity | 数字、单位、药物剂量、左右侧、阴阳性、否定、URL/email/path 的有序 exact match；新增、删除、交换都失败。 | 行业正确拼写不能以改变事实为代价。 |
| Term CER | 只在 reference 的目标术语 span 上做字符编辑距离。 | exact recall 不区分错一个字和完全错词，Term CER 用于诊断。 |
| Latency / RTF | 端到端 p50/p95，另报 ASR、context selection、post-process；长音频报告 real-time factor。 | 防止大词库造成可感知延迟。 |
| Empty/negative hallucination | 静音、非本行业语音及近音负样例中的新增字符/行业词。 | 发现词库把无关输入吸向行业术语。 |

仓库已有 `scripts/evaluate-voice-quality.py`，当前已能报告 CER、英文 WER、per-record `terms exact`、数字/URL/email/path 保真、静音幻觉和 p50/p95。行业评测至少还需要在 corpus 或对比层补充：`industry`、`condition`、`pair_id`、`negative_terms`、`speaker_id`、`device/noise`，并把术语 presence 升级为 occurrence/span 级。

### 7.3 “通过”的产品门禁

以下阈值是 `[建议]` 的首期 release gate，不是厂商或标准组织给出的通用行业标准：

1. 术语正样例 exact recall：开启后 **≥ 90%**，且相对关闭状态绝对提升 **≥ 10 个百分点**；若 control 已 ≥ 90%，则允许以不低于 control 1 个百分点的非劣结论通过。
2. 每个行业子桶（疾病/药名/检验/术式等）exact recall **≥ 85%**，不能用大量容易词掩盖某一高风险桶失败。
3. 通用回归集 CER/WER 相对 control 的绝对恶化 **≤ 0.3 个百分点**，并且 paired-bootstrap 95% CI 上界不超过该值。
4. 近音负样例 Term False Insertion Rate **≤ 0.5%**，且比 control 增加不超过 0.5 个百分点。
5. 高风险槽位的 exact fidelity **100%**；任何剂量、数字、单位、左右侧、阴阳性或否定翻转都直接失败，不以平均分抵消。
6. 静音集不得新增行业词；空 reference 输出字符数为 0。
7. 开启行业包新增的端到端 p95 延迟 **≤ 100 ms**；同一模型/音频上的 p95 RTF 不恶化超过 5%。
8. 固定随机种子或确定性解码配置重复 3 次，逐条最终文本一致；非确定性云端引擎则报告三次均值、最差值和版本/endpoint，不只报最好一次。

只要任何高风险门禁失败，结论应是“词库管线可运行，但该行业包未通过质量门禁”。

### 7.4 样例设计

以下句子是原创评测模板，仅用于说明覆盖方式，不是医学建议或第三方词库内容：

| 行业 | 正样例 | 对应负样例/保护点 |
|---|---|---|
| 医疗 | “患者的糖化血红蛋白是百分之七点二。” | “请把糖化的步骤写清楚。”不能吸成医学词；`7.2%` 必须保真。 |
| 医疗 | “右侧股骨颈骨折，否认药物过敏。” | “左/右”“否认/存在”任何翻转直接失败。 |
| 医疗中英混说 | “计划做 PCI，继续服用 atorvastatin。” | 缩写大小写和药名拼写可增强，但不得新增剂量。 |
| IT/安全 | “Kubernetes 的 Ingress Controller 使用 mTLS。” | 普通句“控制器进来了”不能因 context 输出 `Ingress Controller`。 |
| 金融 | “净资产收益率是百分之十二点五，期限三年。” | `12.5%`、三年与币种/方向必须 exact。 |
| 能源 | “光伏逆变器的额定功率是五十千瓦。” | `50 kW` 可规范化，但不能变成 15 kW 或 MW。 |
| 航空 | “保持三千英尺，联系进近管制。” | 高度、航向、频率属于零容忍槽位；该包未通过前不默认开启。 |

每个目标术语还应覆盖：单独出现、句首/句中/句尾、多词短语、缩写逐字读/整体读、中英切换、同一句两个行业词、不同语速、停顿拆分、噪声、近音普通词。训练/调权样例与最终 holdout 说话人和句子必须分离。

## 8. 测试层级与交付定义

### 8.1 无音频的确定性测试

- source manifest：所有 bundled source 必须有版本、URL、校验和、许可与 redistribution 状态；unknown/restricted 条目构建失败。
- schema：ID 唯一、locale 合法、canonical 非空、alias/spoken form 去重、Unicode normalization 后无碰撞。
- selector：Apple Top-K 不超过 100；常见词/否定词/数字不会被选；个人/组织词典优先于行业包；跨 locale 不泄漏。
- adapter：同一条目对 Apple、Whisper、Qwen、火山/AWS 产生符合各自限制的输出；不支持 IPA/SoundsLike 的引擎不会伪称使用。
- post-process：只有完整词边界或中文明确子串/候选证据才规范化，不做级联替换，不改变保护项。
- license notices：LOINC、Microsoft、NLM、NIST/EIA/FIBO 等 attribution 随实际入包来源生成，禁止 logo/商标误用和“官方认可 Utter”暗示。

### 8.2 真实音频评测

真实音频评测必须保存：App commit、行业包 version/checksum、源版本、ASR 模型 ID、decoder 参数、prompt/context、macOS/硬件、输入设备、音频 checksum、control/treatment 原始输出、processed 输出、逐条 diff 和聚合报告。这样才能复现某个“通过”结论。

### 8.3 可接受的交付声明

- 仅完成 schema、数据包和单元测试：**“行业词库功能已接通，确定性测试通过；真实识别提升尚未验证。”**
- 跑过少量开发者口述：**“smoke test 通过；不代表行业评测通过。”**
- 完成第 7 节冻结 corpus、配对报告和全部门禁：**“该词库版本在指定模型、设备和 corpus 上通过；不外推到其他模型/语言/医院或安全关键用途。”**

## 9. 上线前仍需确认的事项

1. 取得中文医疗术语的商业再分发书面许可，或由医学专家基于可授权来源独立编写、复核第一版中文 canonical/spoken forms。
2. 对每条 LOINC 记录检查第三方 copyright 字段，并把要求的 notice 放到产品许可与下载页。
3. 审核 Microsoft Globalization License 的下游条款和 indemnity 是否与现有 App EULA/开源分发方式兼容。
4. 确认当前 macOS 26 Apple Speech 的 custom language model 对目标 zh-CN locale 的实际支持、编译体积和首次加载延迟；官方 API 存在不等于每个 locale 都适合发布。
5. 固定 Qwen/Whisper 本地运行器版本并验证 context 真正进入了调用链；命令行/上游支持不等于当前 app adapter 已接入。
6. 由医疗、金融、能源等行业专家审批各自高风险保护词与允许的 display normalization。
7. 建立来源更新策略：自动发现新版本可以，但任何词条增删、翻译或权重变化都先生成 diff、重跑许可检查和完整 corpus，再发布。

## 10. 本次实现与验证结果

本次实现内置了医疗、法律、金融财会和软件技术四个中文种子包，每包 30 个项目自编术语。外部权威页面只作为规范核对引用，不复制其代码集、定义或原始语料；每个引用在运行时清单中明确标为 `reference-only` / `not-redistributed`。四个包仍标记为 `project-seed-needs-domain-review`，不能据此宣称已经得到医疗、法律或金融专业审核。

运行时链路已接到：

- 设置页行业选择；
- Apple / Whisper 已有的短语上下文入口，个人词条排在行业词之前，总数仍限制为 100；
- 直出和智能整理前的非级联、精确错写规范化，个人规则优先；
- LLM 的“只纠正明确出现术语、不得从词表补事实”约束；
- 个人词典、行业词库和来源元数据的确定性测试。

2026-08-24 的确定性 corpus 结果（词库 `2026.08.24-v1`，SHA-256 `d9da4adc01a814d9f0eb54d5d9f6c6788365d7affca55f83536b6838f8b8452c`）：

| 指标 | 关闭行业纠错 | 开启行业纠错 | 本层门槛 | 结果 |
|---|---:|---:|---:|---|
| 目标术语 exact recall | 20.59% | 100.00% | 开启后 ≥ 90%，绝对提升 ≥ 10 个百分点 | 通过 |
| 绝对提升 | — | +79.41 个百分点 | ≥ 10 个百分点 | 通过 |
| 非目标文本原样保留 | — | 100.00% | 100% | 通过 |
| 单包 ASR context | — | ≤ 100 条 | ≤ 100 条 | 通过 |

这些结果来自人为构造的错写文本，用于验证 schema、选择、优先级和后处理管线，**不等于第 7 节的真实音频 ASR 质量通过**。真实行业效果仍需要冻结 corpus 上的 control/treatment 配对音频评测；当前环境仅配置 Command Line Tools，且缺少 `metal` 编译器，无法运行依赖 MLX 的完整 SwiftPM XCTest。可在安装带 Metal Toolchain 的完整 Xcode 后执行：

```bash
./scripts/test-industry-lexicons.sh
swift test --filter IndustryLexiconTests
```
