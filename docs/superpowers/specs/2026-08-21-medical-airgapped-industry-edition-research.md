# Utter 医疗与隔离网行业版研究

> 日期：2026-08-21
> 状态：产品与技术选型研究；尚未完成目标硬件实测、医疗语料验收或法律意见
> 范围：中国大陆医疗机构，以及典型涉密、关键信息基础设施和工业控制内网场景；Windows 11 / Ubuntu 24.04 x86_64、CPU 优先、8 GB 最低内存目标
> 证据标准：仅采用法律法规与政府部门原文、上游项目官方文档、模型作者官方 model card / 仓库。模型作者自报 benchmark 只用于筛选，不视为 Utter 实测。

## 1. 结论先行

1. **第一期应只做“医疗听写与格式整理”，不做诊断、用药建议或临床决策。** 最适合的入口是门急诊/住院病历、检查报告、护理记录和病案编码草稿；所有文本由医务人员确认后再写入正式系统。电子病历规范要求操作人员身份识别、历次操作留痕、准确记录操作时间和人员信息，因此 Utter 不能绕过医院原有电子病历的确认、签名和审计链路（[国家卫健委《电子病历应用管理规范（试行）》](https://www.nhc.gov.cn/wjw/c100175/201702/90f3de8ae03d488cbddf509dc958f75b.shtml)）。
2. **“全离线”有真实价值，但不等于自动合规。** 医疗健康信息属于敏感个人信息；即使音频和文本从不出机，医院仍需落实处理依据、必要性、权限、加密、留存、影响评估和事件响应等义务（[《个人信息保护法》第二十八至三十条、第五十一条、第五十五条](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm)）。
3. **医疗行业法规并未要求所有系统一律物理断网。** 现行规则要求等级保护、数据分类分级、境内开展数据全生命周期活动、境内存储、权限与日志管理，并要求 AI 新技术上线前评估安全风险；离线是降低外传面和第三方依赖的产品方案，不是法规原文中的通用唯一方案（[《医疗卫生机构网络安全管理办法》第六、十三、十八至二十二条](https://app.www.gov.cn/govdata/gov/202208/31/488953/article.html)）。
4. **8 GB 可以设为最低支持目标，但当前不能宣称已经支持。** 固定候选是 `sherpa-onnx + Qwen3-ASR-0.6B INT8 + llama.cpp + Qwen3-0.6B Q8_0`，两套模型静态文件约 1.58 GB；但运行时、激活、KV cache、Utter UI、操作系统和医院业务软件叠加峰值没有上游保证，必须在指定整机上测量后才能发布“8 GB 支持”。
5. **第一版只能内置一个经过验收的固定模型栈。** 候选模型可以在研发阶段竞测，产品界面不暴露模型选择、下载、导入、远程端点或自定义 prompt。若 8 GB 质量门槛无法同时满足，应诚实提高最低配置，不能用更小模型换取未经验证的医疗准确率声明。
6. **后续行业优先级建议为工业制造/能源运维，其次才是涉密政务/国防和泛金融。** 工控指南明确提出分区分域、域间隔离、关闭不必要端口和严格远程访问，产品契合度高；涉密市场的断网需求更强，但还存在保密资质、产品检测、采购和现场服务边界，不能仅凭“离线”进入。

## 2. 事实、推断与未知的标记

- **事实**：来源直接陈述的法规要求、模型参数、文件大小、支持平台或许可条款。
- **推断**：基于事实提出的产品设计、优先级或资源预算，必须用真实项目验证。
- **未知**：第一方来源没有给出、客户差异过大，或本项目尚未实测的事项。

本文不是法律意见。每家医院的网络等级、是否属于关键信息基础设施、处理目的和采购要求均需由客户及其合规/网安负责人确认。

## 3. 医疗行业：为什么适合本地离线版

### 3.1 监管事实与产品含义

| 类型 | 事实 | 对产品的推断 | 不能据此宣称 |
|---|---|---|---|
| 敏感个人信息 | 《个人信息保护法》将医疗健康列为敏感个人信息；处理须有特定目的、充分必要性并采取严格保护措施，原则上还涉及单独同意和额外告知要求（[第二十八至三十条](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm)） | 默认不保存原始音频；转写历史最短化；医院可配置留存策略；共享行业词库不得混入患者姓名、证件号、病历号 | “不联网，所以不适用个人信息保护法” |
| 安全措施与影响评估 | 个人信息处理者应采取分类、加密/去标识化、合理权限、培训与应急预案；处理敏感个人信息应事前进行个人信息保护影响评估并留存记录（[第五十一、五十五、五十六条](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm)） | 交付包需提供数据流图、处理清单、权限/日志/删除策略和风险评估材料模板 | “单机安装即可通过合规审计” |
| 医疗网络与数据 | 医疗机构须做等级保护定级、备案、测评和建设整改；数据全生命周期活动应在境内开展，数据应境内存储，AI 等新技术上线前应评估安全风险（[《医疗卫生机构网络安全管理办法》](https://app.www.gov.cn/govdata/gov/202208/31/488953/article.html)） | 完全本地处理能减少互联网传输与云供应商链路；仍需纳入医院资产、账号、补丁、测评和供应商管理 | “所有医院都依法必须物理隔离”或“离线即通过等保” |
| 健康医疗大数据 | 健康医疗大数据覆盖疾病防治、健康管理过程中产生的数据；责任单位需建立安全制度，采取分类、备份、加密认证，并规范访问、使用和销毁（[国家卫健委国卫规划发〔2018〕23号](https://www.nhc.gov.cn/mohwsbwstjxxzx/s8553/201809/742308fad8ed47fb85b9675ee4b6c6eb.shtml)） | 音频、转写文本、纠错历史、词典命中和诊断日志都应视为数据资产，而不只把最终病历算作数据 | “临时音频不属于管理范围” |
| 电子病历 | 电子病历系统须有专有身份标识、权限、修改留痕和可追溯信息；病历书写应客观、真实、准确、及时、完整（[电子病历规范](https://www.nhc.gov.cn/wjw/c100175/201702/90f3de8ae03d488cbddf509dc958f75b.shtml)、[病历书写基本规范](https://www.nhc.gov.cn/bgt/s10696/201002/8cd7d4d70f4b42da839d2428dcbf723c.shtml)） | Utter 输出只能作为“待确认草稿”；正式提交、签名、版本与审计仍由 HIS/EMR 完成；数字、剂量、阴阳性和否定词应设高风险保护 | “AI 自动生成即可直接成为正式病历” |
| 医疗器械边界 | 国家药监局已发布《人工智能医用软件产品分类界定指导原则》；若产品进入辅助决策或提供临床参考信息，可能落入医疗器械分类管理（[国家药监局 2021 年第 47 号通告](https://www.beijing.gov.cn/zhengce/zhengcefagui/qtwj/202204/t20220408_2669468.html)） | 第一版的预期用途、宣传与功能必须限定为听写、术语规范和格式整理，不提供病灶判断、用药或治疗建议；上线前仍应做正式分类界定评估 | “只要叫输入法就必然不是医疗器械” |
| 生成式 AI | 《生成式人工智能服务管理暂行办法》适用于面向境内公众提供生成内容的服务；企业等研发、应用但未向境内公众提供服务的，不适用该办法（[第二条](https://www.cac.gov.cn/2023-07/13/c_1690898327029107.htm)） | 限定医院内部、非公众服务可能不落入该办法的适用范围，但其他数据、医疗、保密和软件监管义务仍然存在 | “离线模型一律无需任何 AI 合规评估” |

### 3.2 第一阶段适用场景

| 优先级 | 场景 | 价值 | 主要风险与产品约束 |
|---|---|---|---|
| P0 | 门急诊主诉、现病史、查体和处置意见草稿 | 高频短段输入，容易形成专科语料与术语评测集 | 姓名、证件号、剂量和否定词必须保真；用户确认后才写入 EMR |
| P0 | 住院首次病程、日常病程、查房记录草稿 | 文本长、模板稳定，节省键盘录入时间 | 不得补写未口述事实；不得自动推断诊断和方案 |
| P0 | 放射、超声、病理、内镜等检查报告草稿 | 专科词汇密集，行业词库价值清晰 | 左/右、部位、尺寸、单位、阳性/阴性属于高风险 token |
| P1 | 护理记录与交接班草稿 | 可在内网或单机使用，减少重复记录 | 生命体征、出入量、药名剂量须结构化保护；噪声环境需单独评测 |
| P1 | 病案首页诊断/手术名称辅助录入 | 可对齐国家临床版疾病与手术操作术语 | 只做候选和规范名称提示；编码最终选择由有资质人员确认 |
| 暂不做 | 诊断建议、用药指导、治疗方案、自动下医嘱 | 超出“语音输入”边界 | 医疗器械分类、临床安全和责任显著上升；第一期明确禁用 |

### 3.3 医疗词库建议

**推断：** 行业词库应是可审计的确定性资产，不是一个自由编辑 prompt。建议分四层：

1. **国家/行业规范层**：疾病、手术操作、检查检验、计量单位和通用医学术语，逐条保留版本、代码与来源。国家卫健委要求门急诊诊断使用《疾病分类与代码国家临床版》或统一临床医学名词，手术操作使用《手术操作分类代码国家临床版》（[《门（急）诊诊疗信息页质量管理规定（试行）》第十一、十二条](https://www.nhc.gov.cn/yzygj/c100068/202409/a58db40867bf4ea5a34f24a6b0486a9d.shtml)）。这证明术语对齐的重要性，但不自动授予完整数据库的再分发权。
2. **专科层**：内科、外科、影像、病理、护理等独立包；包括规范写法、常见口述别名、拼音/英文缩写、科室、风险等级。
3. **机构层**：医院合法提供并确认的药品、耗材、设备、科室、院区和本地缩写；更新包由医院管理员签名导入。
4. **个人层**：医务人员本人确认的非患者专名和表达偏好；默认不进入机构共享词库。

每条词项至少应包含：`canonical`、`spoken_forms[]`、`category`、`department`、`code?`、`risk_level`、`source`、`source_version`、`license_or_rights`、`updated_at`。高风险项（药名、剂量、单位、左右侧、阴阳性、否定词）只允许由 ASR 证据或确定性规则支持的替换，并显示确认；LLM 不得凭语境新增。

**未知：** 国家临床版代码表、药品/器械数据库和第三方医学名词库的批量复制、商用内置与更新权需要逐库核验。网页可查询或规范要求使用，不等于允许把完整数据打进商业安装包。第一期可先用客户授权词表和少量有明确来源、许可的种子词表。

## 4. 其他典型隔离网/内网行业

“行业属于某类别”不等于其每台终端都必须断网。应按数据、系统和客户认定分层，而不是把行业名称直接当作法规结论。

| 层级 | 典型客户/场景 | 第一方依据 | 事实边界 | 产品判断 |
|---|---|---|---|---|
| A：涉密系统 | 党政机关、国防科技工业、军工科研生产及承担涉密业务的企事业单位 | 2024 年修订的《保守国家秘密法》要求涉密信息系统按涉密程度分级保护，按规定建设、检查合格后使用；禁止在未采取规定保护措施时接入公共网络或交换信息；部分涉密业务单位须取得保密资质（[第二十九至三十二、四十一至四十二条](https://www.beijing.gov.cn/zhengce/zhengcefagui/202402/t20240228_3571751.html)） | 法律并非给普通商业软件一张“离线即可用”的通行证；客户的定密、检查、产品和供应商资质规则优先 | 需求最强但准入最难。未完成保密资质、检测和采购研究前，不作为第二期默认市场，也不能宣传“涉密可用” |
| B：工业控制网 | 制造、能源、化工、矿山、水务等 PLC/DCS/SCADA 环境中的巡检、维修、交接班 | 工信部《工业控制系统网络安全防护指南》要求分区分域、用工业防火墙/网闸做域间隔离，关闭不必要端口，严格控制远程访问并审计（[第 8 至 14 项](https://www.miit.gov.cn/zwgk/zcwj/wjfb/tz/art/2024/art_b9415a5455934902b04961909b1c2873.html)） | 指南允许在采取防护时与管理网/互联网连接，并非对全部工业终端要求物理断网 | 最适合医疗之后验证。词库换成设备、工艺、故障码和安全术语；还需做强噪声、手套操作和离线更新测试 |
| B：关键信息基础设施 | 公共通信、能源、交通、水利、金融、公共服务、电子政务、国防科技工业等被认定的重要系统 | 《关键信息基础设施安全保护条例》列出领域并规定由保护工作部门组织认定；运营者需同步规划安全措施、年度检测评估、优先采购安全可信产品并签安全保密协议（[第二、九至十、十二至二十条](https://xzfg.moj.gov.cn/law/download?LawID=683&type=pdf)） | 只有主管部门依规则认定并通知的系统才是关基，不能因客户属于金融/能源就自动下结论；条例也未普遍要求物理断网 | 可提供“无外联、可审计供应链、离线升级”能力，但项目级安全审查与客户集成要求未知 |
| C：高敏感企业内网 | 半导体/医药研发、法律、审计、金融投研、尚未被认定为关基的企业内部资料 | 通用的数据、个人信息、商业秘密、合同和内部安全政策可能适用；本轮未找到一条把这些行业全部规定为断网的统一法规 | 多数需求来自商业秘密、客户合同、DLP 或采购策略，而非行业统一的物理隔离命令 | 作为市场假设访谈，不写成监管事实；优先验证会议记录、研发日志和专业文档听写是否有足够付费强度 |

第二行业建议优先选择 **工业制造/能源现场记录**。它与医疗共享“专业词密集、不能依赖公网、旧 x86 终端、需离线更新”的技术底座，同时法规证据和应用边界比涉密市场更可操作。

## 5. “全离线”的可验收定义

**推断：** 产品合同中的“全离线”至少应拆成下列可测试要求：

1. 安装包内置固定的 ASR/LLM 权重、Tokenizer、VAD、词库、运行时、许可证文本和 SHA-256 清单；首次启动不下载。
2. 正常运行、许可校验、崩溃处理、日志、模型调用、语音识别和文本整理均不需要 DNS、HTTP、WebSocket、遥测或远程 feature flag。
3. 删除远程 LLM/ASR、模型商店、开放 API/HTTP server、插件、CLI 集成、开发者入口、自定义 prompt 和任意模型导入；只保留医院批准的签名词库包导入。
4. 默认不长期保存原始音频；历史记录、诊断日志和词库按客户策略加密、授权、留存和销毁。应用日志不得记录完整患者口述正文。
5. 更新通过离线签名包完成；先校验发布者签名、包清单、文件哈希、版本和回滚兼容性，再原子切换。需要定义签名密钥轮换、吊销和紧急补丁的离线流程。
6. 可选择两种部署档，但使用同一固定模型：
   - **物理隔离单机**：没有任何网络依赖，更新走受控介质；
   - **医院内网**：仅允许客户白名单内的本地 EMR/管理接口，仍禁止公网流量。
7. 提供可重复的零外联验收：洁净安装后封锁公网运行完整流程，同时在 Windows 与 Ubuntu 上抓取进程树、DNS、TCP/UDP 和文件访问；测试结果中公网请求必须为零。

**事实边界：** 离线仍不替代账号权限、审计、加密、备份、漏洞管理和应急响应。《医疗卫生机构网络安全管理办法》明确把第三方、远程运维、废止设备和数据全生命周期都纳入管理（[第十一至十七、二十二条](https://app.www.gov.cn/govdata/gov/202208/31/488953/article.html)）。

## 6. 跨平台离线运行时与模型候选

### 6.1 ASR 候选

| 候选 | 已核实事实 | 文件/内存证据 | 许可与再分发边界 | 本项目判断 |
|---|---|---|---|---|
| `whisper.cpp` + Whisper small 多语言 | 上游支持 CPU-only、整数权重量化、Linux 和 Windows；Whisper small 为 244M 参数，多语言模型可用（[whisper.cpp README](https://github.com/ggml-org/whisper.cpp)、[OpenAI Whisper model card](https://github.com/openai/whisper/blob/main/model-card.md)） | 上游表列 small 文件 466 MiB、推理内存约 852 MB；medium 为 1.5 GiB、约 2.1 GB（[memory usage](https://github.com/ggml-org/whisper.cpp#memory-usage)） | OpenAI Whisper 仓库与 whisper.cpp 均为 MIT；再分发须保留版权和许可声明（[OpenAI LICENSE](https://github.com/openai/whisper/blob/main/LICENSE)、[whisper.cpp LICENSE](https://github.com/ggml-org/whisper.cpp/blob/master/LICENSE)） | **许可清晰的首选基线。** small 适合 8 GB 试验；medium 只作为质量挑战者。OpenAI 明确要求在具体领域稳健评估，并提示幻觉与语言表现不均，故不可凭通用模型卡宣称医疗准确率 |
| SenseVoiceSmall GGUF | 模型作者官方 GGUF 卡提供 CPU/edge 自包含运行时和 Linux/Windows 预编译入口；支持普通话、粤语、英语、日语、韩语（[官方 GGUF card](https://huggingface.co/FunAudioLLM/SenseVoiceSmall-GGUF)、[官方源模型卡](https://huggingface.co/FunAudioLLM/SenseVoiceSmall)） | 官方 GGUF 卡列 q8 约 235 MB、f16 470 MB、f32 936 MB | GGUF 卡标记 Apache-2.0；源模型卡元数据却显示笼统的 `model-license`，而源代码仓库 LICENSE 是 MIT（[SenseVoice LICENSE](https://github.com/QwenAudio/SenseVoice/blob/main/LICENSE)）。这些标记不足以直接确认源权重、转换权重和运行时三者同一许可 | **性能/中文质量挑战者，暂不进入发布包。** 先取得每个构件的明确许可链和固定版本；模型作者 benchmark 不等于医疗语料或目标 CPU 实测 |
| `sherpa-onnx` + SenseVoice/Paraformer | sherpa-onnx 明确声明识别时无需互联网，支持 x86_64、Linux、Windows 和 C/C++ 等 API；官方文档提供 SenseVoice INT8 模型入口（[项目 README](https://github.com/k2-fsa/sherpa-onnx)、[SenseVoice 文档](https://k2-fsa.github.io/sherpa/onnx/sense-voice/index.html)） | 运行时包较小，但模型峰值内存没有适用于本目标硬件的统一官方表。官方 ModelScope Paraformer 热词版页面列模型包约 921.28 MB，并声明支持热词定制（[官方 model card](https://www.modelscope.cn/models/iic/speech_paraformer-large-contextual_asr_nat-zh-cn-16k-common-vocab8404/)） | sherpa-onnx 代码为 Apache-2.0；每个模型权重必须单独核对。FunASR 代码许可不能替代具体权重许可（[sherpa-onnx LICENSE](https://github.com/k2-fsa/sherpa-onnx/blob/master/LICENSE)） | **行业词命中率挑战者。** 真热词能力对医疗更有吸引力，但在许可、峰值内存和医疗语料结果明确前不打包 |

OpenAI 的 Whisper model card 明确建议部署前在具体上下文和领域做稳健评估，并说明模型可能生成音频中未出现的文本、不同语言表现不均（[官方限制说明](https://github.com/openai/whisper/blob/main/model-card.md#performance-and-limitations)）。因此“通用中文 CER”不能替代医疗场景的药名、剂量、部位和否定词验收。

### 6.2 LLM 候选

| 候选 | 已核实事实 | 文件证据 | 许可 | 本项目判断 |
|---|---|---|---|---|
| `llama.cpp` | 纯 C/C++、支持本地推理、x86 AVX/AVX2/AVX512、1.5 至 8 bit 量化与 CPU backend；有 Windows 和 Linux 安装/构建路径（[README](https://github.com/ggml-org/llama.cpp)、[安装文档](https://github.com/ggml-org/llama.cpp/blob/master/docs/install.md)） | 运行内存随模型、量化、context、KV cache 和构建变化；上游未给本组合的单一峰值保证 | MIT，分发时保留版权和许可文本（[LICENSE](https://github.com/ggml-org/llama.cpp/blob/master/LICENSE)） | **首选固定运行时。** 发布构建关闭网络下载/server 等非产品入口，只暴露进程内或本机受限 API |
| Qwen3-0.6B-GGUF Q8_0 | 作者卡列 0.6B 参数、32,768 context、支持 100+ 语言/方言；官方 GGUF 提供 Windows 与 Linux 的 llama.cpp 用法（[model card](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF)） | 官方卡列 Q8_0 文件 639 MB（[同页 Hardware compatibility](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF)）；峰值 RAM 未给出 | Apache-2.0（[模型 LICENSE](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/blob/main/LICENSE)） | **8 GB 基线。** 只做忠实纠错/格式化，禁用 thinking；小模型质量是否足够完全未知，失败须原文回退 |
| Qwen3-1.7B-GGUF Q8_0 | 作者卡列 1.7B 参数、32,768 context，并给出 llama.cpp 使用方式（[model card](https://huggingface.co/Qwen/Qwen3-1.7B-GGUF)） | 官方卡列 Q8_0 文件 1.83 GB；峰值 RAM 未给出 | Apache-2.0（[模型 LICENSE](https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/blob/main/LICENSE)） | **质量挑战者/16 GB 候选。** 在 8 GB 上可能可启动，但没有证据证明与 EMR、ASR 并行时稳定，不应提前列为 8 GB 默认 |

### 6.3 许可交付清单

**事实：** MIT 许可要求在副本或主要部分中保留版权与许可声明；Apache-2.0 第 4 条要求向接收者提供许可证副本、标明修改、保留适用的版权/专利/商标/归属声明，并在上游含 NOTICE 时处理 NOTICE 归属（[Apache License 2.0 §4](https://www.apache.org/licenses/LICENSE-2.0)）。

**推断：** 每个离线安装包必须生成锁定版本的 SBOM/第三方清单，分别记录：组件名、作者、源码/模型 URL、commit 或 revision、原始哈希、转换脚本与参数、最终文件哈希、代码许可、权重许可、NOTICE、修改说明。模型转换成 GGUF 不会自动消除原权重许可义务。

**发布阻断项：** 任何权重只有仓库标签、没有可归档的许可原文，或源权重与转换仓库许可不一致时，不得打入商业安装包；应先由权利人书面澄清或换用许可链清楚的模型。

## 7. 8 GB CPU-first 方案

### 7.1 建议硬件档

| 项目 | 最低支持目标 | 推荐配置 | 状态 |
|---|---|---|---|
| 操作系统 | Windows 11 x64；Ubuntu 24.04 LTS x86_64 | 同左 | 目标，尚未做安装/输入法兼容验收 |
| CPU | x86_64、4 核 8 线程、AVX2 | 6 核 12 线程或以上、AVX2 | 工程选择；llama.cpp/ggml 支持 AVX/AVX2，但实际速度未知 |
| 内存 | 8 GB | 16 GB | 8 GB 是发布硬门槛，不是已验证事实 |
| 磁盘 | 8 GB 可用空间 | 12 GB 可用空间 | 推断，预留安装、双槽升级、日志与回滚空间 |
| GPU | 不要求 | 可选 NVIDIA，但第一期不得依赖 | CPU-first；GPU 后端不是验收前提 |

### 7.2 固定基线栈

```text
音频采集 / VAD
  -> sherpa-onnx + Qwen3-ASR-0.6B INT8
  -> 术语证据与确定性保护
  -> 卸载或回收 ASR 工作集
  -> llama.cpp + Qwen3-0.6B Q8_0（non-thinking、短 context）
  -> 数字/剂量/单位/侧别/否定词 diff guard
  -> 用户确认
  -> 医院原有 EMR/HIS 提交与审计
```

**事实：** Qwen3-ASR-0.6B INT8 ONNX 静态文件约 941 MB，Qwen3-0.6B Q8_0 为 639 MB，两套模型静态文件合计约 1.58 GB；文件大小不是峰值运行内存。

**推断：** 这套组合是 8 GB 候选而不是质量结论。为了给 Windows、EMR/HIS 和音频/UI 留出空间，应：

- batch 固定为 1，单次只处理一段录音；
- LLM context 第一版限制在 2,048 tokens，输出预算限制为短文本，不使用作者卡的完整 32K context；
- 8 GB 档默认串行运行 ASR 与 LLM，避免两套大权重同时常驻；
- 原始录音按段处理并及时释放，历史文本不进入无限增长的聊天上下文；
- 设进程级内存保护和原文回退；内存不足时宁可跳过 LLM，也不能丢失 ASR 原文；
- 固定可复现的 CPU 构建，至少准备 AVX2 x64 包；不在运行时下载不同 backend。

**未知：** Qwen3-0.6B Q8_0 在 llama.cpp 下的峰值 private working set、首 token 延迟、每秒 token 数，以及 Qwen3-ASR INT8 在中文医疗口述上的实时系数，均需在实际 Windows 11 / Ubuntu 24.04 低配机上测。没有这些结果前，文案只能写“8 GB 目标”，不能写“8 GB 流畅运行”。

### 7.3 8 GB 发布门禁

在至少两台真实 8 GB x86_64 机器（Intel 与 AMD 各一台）上，分别以 Windows 11 和 Ubuntu 24.04 测：

| 门禁 | 必测内容 | 通过标准 |
|---|---|---|
| 零外联 | 冷安装、首次启动、录音、转写、纠错、导出、崩溃、离线更新 | 无公网 DNS/TCP/UDP 请求；无静默下载或远程回退 |
| 内存 | 冷/热启动，1/10/30/60 秒录音，连续 100 次，EMR/浏览器同时打开 | 不触发 OOM、系统明显换页风暴或模型加载失败；记录峰值 RSS/private bytes，具体数值在首轮基线后冻结 |
| 延迟 | ASR RTF、首结果、最终结果、LLM 首 token 与总耗时的 p50/p95 | 由产品确定目标前先出 baseline；不得引用作者或其他硬件速度作为通过证据 |
| 医疗准确性 | 安静/噪声、男女声、普通话/口音、科室分层 | CER、行业词召回、数字/剂量/单位/左右/阴阳性/否定词 exact match；阈值需医疗负责人批准 |
| 忠实度 | 原文与 LLM 输出逐项 diff | 高风险 token 不得无证据增删改；guard 失败 100% 回退原文 |
| 稳定性 | 麦克风切换、休眠唤醒、长时间空闲、磁盘将满、更新回滚 | 不丢录音、不留下半安装状态；日志可诊断且不含完整患者正文 |
| 跨平台输入 | Windows 常用 EMR 与 Ubuntu X11/Wayland 目标应用 | 逐应用记录直接注入/剪贴板 fallback；Linux Wayland 权限限制必须实测，不做泛化承诺 |

## 8. 第一阶段产品边界

### 必须保留

- 一键录音、实时状态、取消与明确失败恢复；
- 固定 ASR、固定 LLM、固定安全 prompt；
- 医疗专科词库与医院签名词库包；
- 忠实纠错、标点、分段和有限模板格式；
- 高风险实体保护、原文对照、人工确认；
- 本地权限、最小化日志、离线更新、版本/哈希/许可证页；
- Windows 11 与 Ubuntu 24.04 的真实安装、输入和卸载路径。

### 必须移除或禁用

- 模型选择、下载、导入、量化和用户自定义模型；
- 远程 ASR/LLM provider、API key、代理、网络 fallback；
- 自定义系统 prompt、开放 HTTP API、插件/MCP/CLI 集成；
- 公开模型目录、开发者选项、遥测、在线登录和云同步；
- 自动诊断、用药/治疗建议、自动下医嘱和未经确认的自动提交。

### 词库不是“模型定制”入口

医院仍需要更新术语，但只能通过受控 schema、来源校验、审批、签名和版本化导入。管理员可增删词项和口述别名，不能更换模型、注入 prompt 或执行代码。每次更新应可预览 diff、回滚并形成审计记录。

## 9. 研发决策顺序

1. 先冻结第一期临床边界与 8 GB 目标硬件，不开始宣传“医疗诊断”或“涉密可用”。
2. 取得 3 至 5 家医院的脱敏/授权语料与术语，覆盖至少门诊、病程和一个报告科室；没有真实语料则不做模型定案。
3. 用同一语料验证固定 Qwen3-ASR-0.6B 的官方参考路径与 sherpa-onnx INT8 CPU 路径；所有速度、内存和准确率都在目标 CPU 上测，其他 ASR 只保留历史对照。
4. 同时完成每个模型、运行时、VAD、Tokenizer 和词库数据的许可链审计。许可不明的候选即使分数最好也不进入安装包。
5. 验证 Qwen3-0.6B 是否能在严格 guard 下提升标点/格式且不破坏高风险 token；若不能，第一版应只用确定性处理，而不是升级到更大 LLM 后强行维持 8 GB 宣称。
6. 选出唯一固定栈，制作 Windows / Ubuntu 完整离线包，跑零外联、内存、质量和 100 次稳定性门禁。
7. 医院网安、医务/病案、信息科和法务共同签署试点边界；试点结果达标后再确定 8 GB 最低配置和公开文案。

## 10. 仍需客户或实测回答的问题

| 未知 | 为什么阻断决策 | 获取方式 |
|---|---|---|
| 医院真实网络形态：单机隔离、院内网、VDI/云桌面、等保等级、是否关基 | 决定安装、更新、日志和 EMR 集成方式 | 信息科/网安访谈与现场网络图 |
| 目标 EMR/HIS 及输入控件 | Windows UI Automation、模拟键入、剪贴板策略差异大；Linux Wayland 更受限 | 选定前三个系统做真实兼容测试 |
| 8 GB 机器实际 CPU 与后台负载 | 同为 8 GB，4 代与 12 代 CPU、EMR/浏览器占用差异巨大 | 客户机器清单 + Intel/AMD 低端基准机 |
| 医疗语料及科室分布 | 通用中文模型成绩不能代表药名、剂量和专科词 | 合法授权、去标识化、医疗负责人复核的音频基准 |
| “全离线”是否允许院内局域网 | 决定是否需要两种部署策略和接口 | 在合同中定义网络边界与验收抓包方式 |
| 模型/词库再分发权 | 直接决定能否把文件放进商业安装包 | 归档许可原文、NOTICE、权利人确认和法务审查 |
| 产品是否可能被认定为医疗器械 | 取决于预期用途、宣传、输出和实际工作流，不由技术命名决定 | 上线前做分类界定与监管咨询 |
| 涉密/关基客户的供应商资质 | 离线能力不代替保密资质、安全审查或客户采购要求 | 仅在确定目标客户后由合规与采购联合核验 |

## 11. 可执行建议

第一期产品定义可暂定为：

> **Utter 医疗离线版**：面向中国大陆医疗机构内网或隔离终端的本地语音输入工具。安装包内置固定模型和医疗词库，不连接公网，不提供模型/提示词定制或开放接口；只生成经医务人员确认的听写与格式整理草稿，不提供诊断、用药或治疗建议。

硬件口径暂定：**Windows 11 / Ubuntu 24.04 x86_64，AVX2，8 GB 最低目标、16 GB 推荐、CPU-first、GPU 非必需目标**。其中“8 GB 最低支持”必须等待第 7.3 节门禁完成后才能转为正式承诺。

## 12. 补充决策：医疗离线版固定全 Qwen 模型栈

> 决策日期：2026-08-21
> 阅读关系：第 6 节中的 Whisper、SenseVoice 和 Paraformer 仅保留为历史候选证据；当前发布决策以本节固定 Qwen 栈为准。
> 名称边界：准确的产品表述应是“**全 Qwen 模型栈**”，而不是“所有软件均由 Qwen 提供”。ASR 与文本模型均为 Qwen，但 CPU 推理仍需 sherpa-onnx、llama.cpp / ONNX Runtime 等非 Qwen 运行时。

### 12.1 决策结论

1. **ASR 固定为 `Qwen3-ASR-0.6B`。** `1.7B` 只作 16 GB 以上质量对照，不进入 8 GB 包；第一期不打包 `Qwen3-ForcedAligner-0.6B`，也不提供非 Qwen ASR 回退。
2. **文本整理与翻译复用同一个 `Qwen3-0.6B-GGUF Q8_0`。** 第一阶段不增加专用翻译模型，整理和翻译按顺序执行，且都使用 non-thinking、短上下文、固定 prompt。
3. **CPU 发布路径优先验证 `sherpa-onnx + Qwen3-ASR-0.6B INT8 ONNX`。** Qwen 官方 Transformers 包保留为参考正确性路径，不作为已经证明的 Windows/Linux 8 GB 交付路径。
4. **8 GB 仍是条件性可行目标，不是已验证规格。** 静态权重预算足够小，但上游没有给出目标操作系统和 CPU 上的进程峰值、长音频峰值、实时系数或与 EMR 并行运行数据。

### 12.2 当前 Qwen ASR 官方型号、参数与边界

| 型号 | 已核实事实 | 8 GB 判断 |
|---|---|---|
| `Qwen3-ASR-0.6B-hf` | Qwen 官方仓库列出 0.6B 与 1.7B 两档，均支持 30 种语言、22 种中文方言，并统一支持 non-streaming/streaming；官方 Hugging Face 仓库显示 Apache-2.0、BF16 safetensors 合计 782,426,112 个参数、仓库约 1.58 GB（[Qwen3-ASR 官方仓库](https://github.com/QwenLM/Qwen3-ASR)、[0.6B-hf model card](https://huggingface.co/Qwen/Qwen3-ASR-0.6B-hf)、[官方仓库元数据](https://huggingface.co/api/models/Qwen/Qwen3-ASR-0.6B-hf)） | **唯一 8 GB ASR 候选。** 名称中的“0.6B”是官方型号档位；全模型 safetensors 参数统计更高，做内存预算时不能简单按 0.6B 乘字节数 |
| `Qwen3-ASR-1.7B-hf` | 官方 Hugging Face 仓库显示 Apache-2.0、BF16 safetensors 合计 2,038,052,480 个参数、仓库约 4.09 GB（[1.7B-hf model card](https://huggingface.co/Qwen/Qwen3-ASR-1.7B-hf)、[官方仓库元数据](https://huggingface.co/api/models/Qwen/Qwen3-ASR-1.7B-hf)） | **排除出 8 GB 发布包。** 4.09 GB 只是文件规模，不含 PyTorch/ONNX Runtime、激活、音频缓冲、LLM、Utter、操作系统和 EMR；没有证据支持其在本目标环境稳定运行 |
| `Qwen3-ForcedAligner-0.6B(-hf)` | Qwen 将它定义为独立的 0.6B 强制对齐模型，用于 11 种语言、最长 5 分钟音频的词/字时间戳；使用时间戳需额外加载该模型（[官方说明](https://github.com/QwenLM/Qwen3-ASR#overview)） | **第一期不内置。** 医疗听写核心路径不需要词级时间戳；增加第二个 0.6B 模型会扩大内存、包体和许可审计面 |

**事实边界：** Qwen 官方通用 benchmark 包含普通话、粤语、方言、噪声等测试，但没有给出中国医疗口述、药名剂量或本项目目标 CPU 的结果（[官方 Evaluation 表](https://github.com/QwenLM/Qwen3-ASR#evaluation)）。因此“支持中文/方言”不能外推成“医疗识别准确”或“8 GB 实时”。

### 12.3 两条离线运行路径

| 路径 | 一手事实 | 判断与未知 |
|---|---|---|
| Qwen 官方 `qwen-asr` / Transformers | 官方说明 `qwen-asr` 提供 Transformers 与 vLLM 两个 backend，并允许把权重预先下载到本地目录；2026-06-26 又发布了原生 Transformers 的 `-hf` 权重。官方参考示例使用 `device_map="cuda:0"`、BF16，并推荐 FlashAttention；实时 streaming 当前只在 vLLM backend 可用（[安装与本地下载](https://github.com/QwenLM/Qwen3-ASR#released-models-description-and-download)、[推理与 streaming](https://github.com/QwenLM/Qwen3-ASR#python-package-usage)） | **可证明“权重能预置并从本地路径加载”，不能证明“Qwen 官方已支持 Windows 11 / Ubuntu 24.04 的 8 GB CPU 产品化”。** 源码保留 CPU device fallback（[官方实现](https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/inference/qwen3_asr.py)），但官方没有该路径的 x86 CPU 内存和速度表。所谓 `Offline` 是非流式推理模式；只有固定本地路径、禁止自动下载并在断网环境验收后，才等于产品要求的“全离线” |
| `sherpa-onnx` + Qwen3-ASR-0.6B INT8 ONNX | sherpa-onnx 官方文档已发布 Qwen3-ASR-0.6B INT8 模型：`conv_frontend.onnx` 42 MB、`decoder.int8.onnx` 721 MB、`encoder.int8.onnx` 174 MB，Tokenizer 约 4.2 MB，模型静态文件合计约 941 MB；示例明确配置 `provider="cpu"`、2 至 3 个线程，并支持 Qwen3 ASR hotwords（[导出物与文件大小](https://k2-fsa.github.io/sherpa/onnx/qwen3-asr/export.html)、[CPU/热词示例](https://k2-fsa.github.io/sherpa/onnx/qwen3-asr/pretrained.html)）。该运行时官方提供 Windows x64 预编译库和 Windows CPU 构建路径，也给出 Linux x64 CPU 构建路径（[Windows x64 预编译库](https://k2-fsa.github.io/sherpa/onnx/install/windows/generated/download/windows_x64.html)、[Windows x64 CPU 构建](https://k2-fsa.github.io/sherpa/onnx/install/windows/generated/build_cpu/windows_x64_cpu_build.html)、[Linux x64 CPU](https://k2-fsa.github.io/sherpa/onnx/install/linux.html)） | **首选发布验证路径。** Windows 11 属于其“Windows 10 或更高版本”范围可作兼容性推断；Ubuntu 24.04 只能由 Linux x64 支持作候选推断，二者仍须实机验收。ONNX 转换代码不是 Qwen 团队仓库，模型包虽由 sherpa-onnx 官方发布，仍须锁定转换脚本、源 revision、量化方法和文件哈希，并审计转换物的许可/NOTICE 后才能商业再分发 |

不应混用 [Qwen3-ASR-Toolkit](https://github.com/QwenLM/Qwen3-ASR-Toolkit)：它是调用 DashScope 的官方 API 工具，需要 API key 和服务端请求，不符合隔离网交付。

**推断：** 8 GB 档先只做“松开按键后出最终文本”的 non-streaming 流程。Qwen 官方 streaming 依赖 vLLM，偏 GPU；sherpa-onnx 提供的是 VAD 分段的 simulated streaming。两者均不足以在未实测前承诺低配 CPU 的实时逐字体验。

### 12.4 翻译：复用 Qwen3-0.6B，不另带专用模型

**事实：** Qwen3-0.6B 官方卡明确列出 0.6B 参数、32,768 context、100+ 语言/方言，并声明具备多语指令与翻译能力；官方 GGUF Q8_0 文件为 639 MB，页面给出 llama.cpp 的 Linux 与 Windows 本地运行方式，许可标记为 Apache-2.0（[Qwen3-0.6B-GGUF 官方 model card](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF)）。

**事实：** 本轮核查的 Qwen 官方 `qwen-mt-turbo` / Qwen-MT 发布页只给出通过 Qwen API、API endpoint 与 key 调用的方式，没有给出可嵌入安装包的开放权重下载路径（[Qwen-MT 官方发布](https://qwenlm.github.io/blog/qwen-mt/)）。该页面只能证明在线服务用法，不能证明 Qwen-MT 可用于本项目的全离线再分发。

**决策推断：** 第一阶段由同一个 Qwen3-0.6B Q8_0 完成两类任务：

- `mode=cleanup`：只做标点、分段、口语冗余清理和已批准格式，不新增医疗事实；
- `mode=translate`：只翻译用户明确选中的文本，同时展示源文与译文，不覆盖 ASR 原文；
- 两种模式都关闭 thinking、限制 2,048 tokens context、固定温度/采样参数，并对药名、剂量、单位、数值、左右侧、阴阳性和否定词做前后校验；
- 翻译结果是待确认草稿，不直接写入正式病历；guard 失败则返回源文和失败原因，不生成“猜测译文”。

**未知：** 官方卡的通用多语能力不是医疗翻译验收。Qwen3-0.6B 对中英医学缩写、拉丁药名、单位和长句的忠实度尚无本项目证据。如果双语医疗测试不达标，应禁用第一期翻译或把正式最低配置提高后再验证更大 Qwen 本地模型；不能改用联网 Qwen-MT 来继续宣称“全离线”。

### 12.5 8 GB 可行边界

| 项目 | 已知静态规模 | 不能从静态规模推出的内容 |
|---|---:|---|
| Qwen3-ASR-0.6B INT8 ONNX | 约 941 MB | ONNX Runtime arena、KV/cache、激活、长音频/VAD 缓冲、实际 private working set |
| Qwen3-0.6B GGUF Q8_0 | 639 MB | llama.cpp KV cache、context、线程 scratch buffer、实际 private working set |
| 两套模型静态文件 | 约 1.58 GB | Windows/Linux、Utter UI、音频栈、EMR/浏览器和安全软件叠加后的整机峰值 |

**推断：** 从文件规模与现有 CPU 路径看，`Qwen3-ASR-0.6B INT8 + Qwen3-0.6B Q8_0` 是合理的 8 GB 工程候选；但上游没有给出该组合的 8 GB 保证，因此发布口径仍只能是“8 GB 目标”。为提高成功概率：

1. ASR batch 固定为 1，VAD 把长录音切成有限长度片段，`max_new_tokens` 随片段设置上限；
2. ASR 与整理/翻译严格串行，进入 LLM 前释放 ASR stream、音频缓冲和可回收工作区；
3. 不加载 1.7B ASR、ForcedAligner、第二个翻译模型、vLLM、Gradio、HTTP server 或 Python 开发环境；
4. LLM context 固定 2,048 tokens，输出设短上限，禁用多轮历史和 thinking；
5. 安装包内固化模型、Tokenizer、运行时、VAD、词库和校验清单，代码只接受本地绝对路径并阻止 Hub/API fallback；
6. 内存不足时保留原始 ASR 文本并跳过整理/翻译，不能静默切换到云端或其他模型。

**发布阻断未知：** 目标 Intel/AMD 机器上的 ASR 峰值 RSS/private bytes、1/10/30/60 秒音频的 p50/p95 RTF、LLM 首 token/总耗时、连续 100 次后的内存回收，以及 Windows 11 与 Ubuntu 24.04 精确发行环境兼容性。第 7.3 节全部门禁仍然适用，并应把原 ASR 名称替换为本节固定 Qwen 栈。

### 12.6 许可与再分发结论

- **事实：** Qwen3-ASR 官方仓库和官方 model card 标记 Apache-2.0；Qwen3-0.6B-GGUF 也标记 Apache-2.0；sherpa-onnx 为 Apache-2.0，llama.cpp 为 MIT（[Qwen3-ASR LICENSE](https://github.com/QwenLM/Qwen3-ASR/blob/main/LICENSE)、[sherpa-onnx LICENSE](https://github.com/k2-fsa/sherpa-onnx/blob/master/LICENSE)、[llama.cpp LICENSE](https://github.com/ggml-org/llama.cpp/blob/master/LICENSE)）。Apache-2.0 允许按条件分发源代码或目标形式，但要求提供许可证副本、标明修改、保留适用归属，并在存在 NOTICE 时传递相关 NOTICE；许可证不授予超出合理来源说明所需的商标使用权（[Apache-2.0 第 4、6 条](https://www.apache.org/licenses/LICENSE-2.0)）。
- **推断：** 按上游许可文本，履行相应条件后存在商业再分发路径，但这不是法务放行结论。必须为 Qwen 原权重、ONNX 转换物、GGUF、两个运行时及其传递依赖分别记录来源 revision、下载哈希、转换/量化脚本与参数、修改说明、LICENSE/NOTICE，并在产品中提供第三方许可页。
- **未知/阻断：** sherpa-onnx 发布的 INT8 Qwen 转换包是否已携带完整的上游许可与修改声明、本项目固定转换 revision 的可复现性，以及依赖包在 Windows/Linux 安装包中的逐项许可尚未审计。完成这三项前，INT8 包只能用于内部原型，不能进入对外商业发布。

### 12.7 覆盖后的固定流水线

```text
本地音频 / VAD
  -> sherpa-onnx + Qwen3-ASR-0.6B INT8（CPU、batch=1、本地热词）
  -> 原文与高风险 token 证据快照
  -> Qwen3-0.6B Q8_0 + llama.cpp
       ├─ cleanup：忠实整理
       └─ translate：显式触发、源译对照
  -> 数字/剂量/单位/侧别/阴阳性/否定词 guard
  -> 医务人员确认
  -> 医院原有 EMR/HIS 提交、签名和审计
```

本节落地后的唯一建议规格是：**Windows 11 / Ubuntu 24.04 x86_64、AVX2、8 GB 最低目标（待门禁）、16 GB 推荐、CPU-first；ASR 固定 Qwen3-ASR-0.6B，整理与翻译固定复用 Qwen3-0.6B，不提供模型选择、模型定制、开放 API 或网络回退。**
