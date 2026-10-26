# Run5 外盘隔离与离线依赖准备

**Status:** blocked
**Authorization:** 继承用户整体授权，仅表示本轮准备工作已获授权，未代表实际验收通过。

实测准备完成；SwiftPM 离线初始化、compiler 外盘落点、完整 build 和 swift test 均为 **not-run**。不会把源码复制或 help 输出报为工程通过。Run4 是磁盘保护 exit -2，未发现可据此修改的代码错误。本轮没有产品源码修改。

## 已实测

- 重新核验既有外盘 identity、APFS、挂载、可写和空间，仅创建任务独占 `EXTERNAL_TASK_ROOT`。拒绝旧目录及 symlink；专属 scratch/modulecache/clangcache/temp/packagecache/config/security 的写入、fsync、读回和 SHA 校验通过。
- 已安装 Swift 6.2.3 的 build/package help 确认 scratch/cache/config/security、禁止自动更新解析/预取/prebuilts 和 jobs 选项；swiftc/clang help 确认 module-cache 选项。仅执行 help/version，没有编译探针。未选择或执行 Xcode，其既有 developer directory 只核验存在。
- Package.resolved 的全部 19 pins 对应本 worktree checkout HEAD，clean 且本地 bare repositories 包含确切 commit。包含递归 Git 子模块的精确源码快照已放入任务 scratch/checkouts，共 8254 文件、145334442 bytes，逐文件读回 SHA 一致。没有复制 `.git`、认证、整个全局缓存、原生产线源码或 workspace-state。
- HEAD `ed4234b41764be8346ae58cdc63011c8f26a0f1e`。tracked binary diff SHA256 `11b3c4932766a8fdd6cfda1e243193c06afb1ce6b38c686baf94698ec27e8a83`。完整 846 文件源码/script/resource manifest SHA256 `de6b2fe41b205b259748fc91df8dea7189b1a2dc2c8fba4f0e8d232d875efc50`，与 Run4 逐文件一致。git diff --check 通过。

## 未执行与准确阻塞

最初 Data 可用 10,649,055,232 bytes，低于固定保护线 10,737,418,240 bytes，所以只做非编译准备。22:39:09Z 读到恢复后的 11,201,437,696 bytes，最终准备读数 11179929600 bytes；此时距命令收尾及 native 目标已不足三分钟，没有启动 build 或最后启动测试。没有等待空间恢复、降低阈值、删除 Data 文件或再次重试磁盘保护。

快照是源码快照，尚无 SwiftPM 注册所需 Git 元数据。packagecache 只有写读探针，没有宣称已缓存可用依赖；没有复制绝对 workspace-state。SwiftPM describe/resolve/build 和本地 source override 均未执行。因此离线初始化还未成立，不能直接执行配置草案期待离线成功。

`configuration-only.json` 保存精确 command/env 和落点，全部本机绝对路径及 volume identity 只在 ignored raw 中。配置草案使用本进程 TMPDIR/SWIFTPM_MODULECACHE_OVERRIDE/CLANG_MODULE_CACHE_PATH，SwiftPM scratch/cache/config/security 及显式 Swift/Clang modulecache。后续需先从已验证本地 repos 补建 Git working copies 或任务专属 mirrors，并让真实 SwiftPM 离线初始化验证；不改 Package.swift/lock/global config/HOME，不允许联网 fetch。再核验 Data >=10GiB、保留至少三分钟自身 PGID 监督窗口，运行一次无 target/product 限制的完整 swift build，jobs2、关闭 prebuilts/解析更新/预取，以日志证明实际外盘 compiler 落点。

swift test、basic checks、release-style build、UI/宿主/焦点/隐私/设备均 not-run。basic 脚本含 Swift 编译执行路径，不在不足监督窗口中启动。源码未改，未写父独占 plan/spec/verification/workflow/Run5-state。

## 证据与命令

raw 根 `.local/voicecursor-research/run5-preparation/`。`command-records.json` 保存每条实际 command/env/start/end/exit/PID/PGID/logSHA256；全部原始日志、19份 source manifests、`dependencies.json`、`full-source-manifest-after.json`、`configuration-only.json` 和 `external-mapping.json` 留在该根。日志哈希总索引 `evidence-hashes.json`。启动命令 `python3 .local/voicecursor-research/run5-preparation/prepare.py`，两次 `--resume` 只修准备脚本的仓库名歧义和 Git 子模块目录处理；失败原始结果仍保留。不是重试 build 或重新扩预算。

最终准备监督开始 2026-10-07T22:39:58.234891+00:00，结束 2026-10-07T22:40:15.352968+00:00，exit0。每条工具命令自身 PGID 监督、最多15秒，并受22:40:40Z累计截止约束。自身命令进程组清空；终态快照见 `process-terminal.json`。不留 watcher、daemon 或子 Agent。native completedAt 和 deadline 达标由父宿主核验，报告写入时间不等于 native 终态。

## 全部精确依赖

| identity | revision | source manifest SHA256 |
| --- | --- | --- |
| ane-lm | `033472ec12ea796fc7ea4f8cefd7ed456f69900b` | `bd3f271ba88baae32f0de626e07268a6c465ee37c0356fa2691336b92f93d3d1` |
| argmax-oss-swift | `25c62997041c134b03ca82731ce2f6fd2cae1eb9` | `e247e884f6c6ea9aee2ccbc04f6f68640aa88513b0dbed0c5a67bb4d24a7b662` |
| eventsource | `a3a85a85214caf642abaa96ae664e4c772a59f6e` | `9bb356649cd43dff5c7bf95d23fec6cdefffa720a63779d36e8c5ebec9dcb75d` |
| mlx-audio-swift | `d302a5c6080d2bb97bae38c7418f82abb76013b6` | `bcd73c7f49ad49f730f9042dd10c6392de112995c0798ed2951883b2766042e0` |
| mlx-swift | `dc43e62d7055353c7f99fa071a4e71d29dfddc44` | `fbd7842d5394688250f2b81dd74a33f7a2e262d0ddc2b2834314ab25224d1e6c` |
| mlx-swift-lm | `bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57` | `bc20c6c0d0dc6b7915f0c1465f2c5e91744e36d31b1b588fc2f0c38148f86422` |
| swift-argument-parser | `6a52f3251125d74daf04fcbd5e6f08a75d074382` | `b9c48d9a5b5596acd5544c82709d89567a865775054a0ed9b4c56104f633e1f0` |
| swift-asn1 | `eb50cbd14606a9161cbc5d452f18797c90ef0bab` | `5b589d3fc5706da7e4c7f43765cd8119e223736996b9ae4aee9d3ef271098b09` |
| swift-atomics | `b601256eab081c0f92f059e12818ac1d4f178ff7` | `e3608a3ac996f4185b9baedfe5e64d5a4a925189a1de53f5c515dd9f8b6f9483` |
| swift-collections | `fea17c02d767f46b23070fdfdacc28a03a39232a` | `9804a3402b0b36f82d2d1780ba2eb58af70bfb8c6f9d0771569259c22af24943` |
| swift-crypto | `1b6b2e274e85105bfa155183145a1dcfd63331f1` | `640cd1d63d33b96c22114d886c3c354e3487a742274ee650ec2c84ad035824b7` |
| swift-huggingface | `b721959445b617d0bf03910b2b4aced345fd93bf` | `b5ad7b072e4411bda49b1ce74cb846e54babec7a4a59817c72c2cccfb3c15adf` |
| swift-jinja | `0b67ecb79139f6addef8699eff3622808aa6c7dc` | `897bcb0d3a80266762acdacbbd053a95b225c87e809eeede97b46da4314a27c4` |
| swift-nio | `57c0a08a331aaea9f5d7a932ad94ef43be942a95` | `7d0b785605a6ddd4b97c57e5094683f99785fa127f6071c2b995d6abb8355d02` |
| swift-numerics | `0c0290ff6b24942dadb83a929ffaaa1481df04a2` | `1a34e387c2741b9f2c1ce5600de009b8523691a30ee37645f94381aff3c94151` |
| swift-syntax | `9de99a78f099e59caf2b2beec65a4c45d54b2081` | `dc68737684c6d5450752db7099946df63d06da6398e04106bb93cdca55c870f7` |
| swift-system | `7c6ad0fc39d0763e0b699210e4124afd5041c5df` | `8420cc1e7c14d1862d4e5fb43edfb377cc402fdf5c10ddb10371f1fd4a295515` |
| swift-transformers | `2fa33e1f5e7131a7fc64c28e6d161dcec0d24820` | `a28a68ab2af7a99be0f8c5f2373ce38727f2c1515eb7e9abeb3f65cdd6adedb0` |
| yyjson | `8b4a38dc994a110abaec8a400615567bd996105f` | `48a4074d1c0286bbcb42bf5b7d89ee54b6db1f5d9b92220b0ccdf807d6d29d44` |

下一具体动作是补证真实 SwiftPM 离线初始化并完成完整 build。成功后交 Cursor 接原生审阅和 focus/privacy 检查，再做真实宿主验证。移动由原 owner 闭合 T0 并预约设备，manual return 不达标。本轮无 commit/push/PR/release。

SDLC checks pass，exit 0，2026-10-07T22:41:18.284319+00:00 至 2026-10-07T22:41:19.771720+00:00，日志 SHA256 `5ed5fb27bb8a18b455bb5c10b900d0e0b602a1b7dc598eecbd736cacdc07bfc0`。已知自身旧命令 PID/PGID 残留 0。
