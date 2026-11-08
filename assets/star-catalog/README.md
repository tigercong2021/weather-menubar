# 亮星目录：来源、许可与本地计算

来源为 David Nash / Astronexus 的 **HYG v4.1**，固定原作者仓库提交 [`c7f7f883fe678cc7680169a50ccd7dcc49b060ce`](https://github.com/astronexus/HYG-Database/tree/c7f7f883fe678cc7680169a50ccd7dcc49b060ce)。该 GitHub 仓库已归档；作者把后续维护迁至 Codeberg。本项目固定使用这个可追溯快照，不声称它是最新星表。

从 119,626 条记录中选择名义视星等 `mag <= 3` 的 179 条恒星，排除太阳。保留全部满足条件的南北天亮星，不按某个城市剪裁，不包含虚构星点。城市和时间由应用本机计算使用，不写入或上传至本目录的获取脚本。

## 许可证和来源

- 原作者在该版本的 [`hyg/CURRENT/LICENSE`](https://github.com/astronexus/HYG-Database/blob/c7f7f883fe678cc7680169a50ccd7dcc49b060ce/hyg/CURRENT/LICENSE) 和 [`hyg/README.md`](https://github.com/astronexus/HYG-Database/blob/c7f7f883fe678cc7680169a50ccd7dcc49b060ce/hyg/README.md) 均指定 **CC BY-SA 4.0**。没有套用旧版 HYG 2.x/3.x 的 CC BY-SA 2.5。
- 原始许可声明保存为 `original/HYG-LICENSE.md`；[Creative Commons 完整许可](https://creativecommons.org/licenses/by-sa/4.0/legalcode.en)原文保存为 `original/CC-BY-SA-4.0.txt`。
- 本目录的筛选 JSON 和 `source/BrightStarCatalog.swift` 内星表数据是 HYG 的派生数据，继续按 **CC BY-SA 4.0** 提供，保留作者、来源、许可及“筛选/字段转换”修改说明。
- 本子集可随天气菜单栏的公开源码和应用分发，但必须保留 David Nash / Astronexus 署名、固定来源、许可及修改说明，让派生星表继续按 CC BY-SA 4.0 提供。应用项目的一般代码许可不替代星表许可，不得对星表施加与该许可冲突的额外限制。本说明不表示数据作者为应用背书。
- 发布包保留本说明、完整 CC BY-SA 4.0 许可和可审阅的 `bright-stars-v41-mag3.json`；公开源码还保留 `source/BrightStarCatalog.swift` 中的数据署名。完整上游 CSV 不是应用运行依赖，无须随应用或 DMG 打包；原始件与历史清单仍在本地保存，筛选可由固定公开上游来源复现。
- 2026-11-08 用户已授权 V2.0 公开分发；历史 manifest 的本机试验状态保留原样。该授权与文件许可不表示已经完成上传或发布。

## 文件与接口

- `original/hygdata_v41.csv`：33,932,548 字节的完整原始 CSV，不修改；SHA-256：`d9f69fd86bbf90a4e4d52b4c5c53eacfa6dfc0bfdef85bfd94f095e0bebe4ebd`。
- `original/HYG-README.md`：原作者字段解释，保留原文。
- `bright-stars-v41-mag3.json`：179 条可审阅派生记录及许可证、坐标系说明。
- `../../source/BrightStarCatalog.swift`：同一脚本生成的静态 `BrightStarCatalog.stars: [BrightStar]`，无需运行时文件加载或网络。
- `manifest-20261108.json`：原件/派生文件/脚本 SHA-256、筛选规则及检查结果。
- `scripts/fetch_hyg_source.py`：仅下载固定公开来源，不上传任何资料，不覆盖已有原件。
- `scripts/prepare_bright_stars.py`：只读原件，验证哈希，复现 JSON、Swift 和 manifest。默认检查；`--write` 仅创建缺失输出，遇到已有不同内容会拒绝覆盖。

接口字段：`id` 是 HYG 稳定编号前缀 `hyg-`；`name` 优先原始通名，再取 Bayer/Flamsteed 名称；`rightAscensionHours` 是 **小时**，`declinationDegrees` 是度，均为 **J2000.0 历元和分点**；`distanceLightYears` 用原作者说明的近似系数 `dist × 3.262` 从秒差距换为光年；`visualMagnitude` 是目录名义 V 波段视星等，数值越低越亮。所有所选距离均有效，没有使用 HYG 的 `>=100000 pc` 缺失视差占位。

## 验证及解释边界

已核验原始哈希、坐标范围、赤经小时/赤纬度对照原始弧度列、唯一 ID、排除太阳、正值有效距离，以及天狼星/老人星/北极星的已知字段。全纬度覆盖采样采用纬度 −90° 至 +90°（步长 5°）、地方恒星时 0 至 23.75 小时（步长 15 分钟）；每个采样点均有目录星高于 66°。该检查说明候选分布覆盖南北天空，不表示星光能穿过云、建筑或地形。

这不是实时测光：变星的瞬时亮度会变化，目录分开的双星分量没有重算为肉眼不可分辨系统的合成亮度。原件保留自行字段，当前静态接口不推进自行；应用负责日期参考系转换及观察者地平坐标。大气消光、云、光污染与地形不在星表中。适用于天气面板的预计亮点试验，不是精密指星或观测测量工具。

在项目根目录执行 `python3 assets/star-catalog/scripts/prepare_bright_stars.py` 可完整复核派生文件一致性，无网络请求。
