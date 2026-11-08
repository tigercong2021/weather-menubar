# 写实动态天气背景 · 2026-11-08

本目录保存天气菜单栏的 AI 生成天空背景及本机制作记录。背景由用户已有的 Grok 登录订阅通过纯文字提示生成，没有上传本地截图或照片，也没有调用付费 xAI API。2026-11-08，用户授权将 V2.0 应用、必要运行素材和源码公开分发；本说明记录分发范围，不代表已完成上传或发布。

**Created with Grok** — 天空背景为 AI 生成的氛围素材，不是真实摄像、卫星观测或对应地点的实景。来源、使用边界与上游条款见 [ASSET-NOTICE.md](ASSET-NOTICE.md)。

## 公开分发范围

- 应用和公开源码只需包含 `runtime/*.mp4`、`runtime/*.jpg` 及本素材声明。当前共 24 段静音视频、24 张海报，含 12 个场景键及各自横版。
- `runtime/*.validation.json` 含本机绝对路径，不进入应用、DMG 或公开仓库。
- `generated-*/` 原片、提示词和生成日志，历史 `manifest-*.json`、联系表、制作脚本及本机验证记录继续保留本地；公开发布不要求上传这些整个目录。可另行发布仅含相对文件名、来源说明和运行素材哈希的清单。
- GitHub 页面、分发说明及应用内可访问的素材说明应保留可读的 **Created with Grok** 署名。该署名不表示 Grok 或其运营方推荐、审核或担保本应用。
- 下列历史清单中的“本机个人使用、未发布”是原制作任务的状态，不替代本次公开分发范围，也不应改写为已完成发布的记录。

- `generated-20261108/`：9 段原始生成视频与提示词、生成日志。原始视频保持不变。
- `runtime/{key}.mp4` / `.jpg`：整页背景，540 × 960。
- `runtime/{key}-compact.mp4` / `.jpg`：600 × 200 横版，保留先前关注城市卡片试验素材；当前关注页按选中城市使用整页背景。横版按云层或原场景主体位置裁切。
- `manifest-20261108.json`：准确提示词、来源、授权范围、原始件与运行素材 SHA-256、编码及验证记录。
- `portrait-contact-sheet.jpg`、`compact-contact-sheet.jpg`：9 种场景静态检查图。
- `animated-overview.mp4`：9 种实际运行视频组成的动态总览，与静态检查图顺序一致。

场景键：`clear-day`、`clear-night`、`partly-cloudy`、`overcast`、`rain-clouds`、`snow-clouds`、`fog`、`storm-clouds`、`dawn-dusk`。

18 个运行视频均为 H.264、24 fps、无音轨，约 5.458 秒。它们保留正向天气运动，采用 0.6 秒首尾交叉淡化，再裁去开头对应片段形成连续循环，没有倒放。JPEG 是首帧海报，供加载、暂停或减少动态效果时显示；正常动画必须播放 MP4。

已验证分辨率、时长、无音轨、完整解码和原始文件哈希不变。每个运行视频的 22 个四分之一秒采样帧均不同；晴空、夜空、雾和晨昏的运动比较轻，多云、阴天、雪云和暴风云变化更明显。图像与数字检查不能代替实际应用播放体验验收。

制作记录：`validation/prepare_weather_scene_assets.py` 负责生成和验证运行版，`validation/WeatherSceneContactSheet.swift` 负责静态检查图。原制作阶段仅处理本机素材；本次公开分发的来源与权利说明另见 `ASSET-NOTICE.md`，历史文件不覆盖。

## 银河夜景增补 · night-v2

用户进一步明确晴夜需要自然银河星空，多云夜保留银河星带并由轻薄云层遮挡。本批新增 `milky-way-night` 和 `partly-cloudy-night` 两个键，原有 `clear-night`、`partly-cloudy` 及所有首批文件均保留。

- 原片与准确提示词/生成日志：`generated-20261108-night-v2/`。
- 新运行文件：`runtime/{milky-way-night,partly-cloudy-night}.mp4/.jpg` 及对应 `-compact` 版本。
- 整合 11 种资产的新来源与哈希清单：`manifest-20261108-night-v2.json`；首批 `manifest-20261108.json` 保留原样，新清单记录其哈希。
- 对照图：`night-v2-contact-sheet.jpg`、`night-v2-compact-contact-sheet.jpg`。
- 动态对照：`night-v2-animated-overview.mp4`，左晴夜、右薄云夜。

两种夜景使用自然深蓝黑夜空、银灰银河星带和密细星点，没有强月光、紫色霓虹、科幻星云或地面物体。仍使用用户已有 Grok 登录订阅且仅发送文字，没有上传本地图片、使用 API Key 或调用付费 API。

4 段新增运行视频均为 24fps 无音轨 H.264、约 5.458 秒。整页版 540 × 960，横版 600 × 200；为保留细星点，编码质量采用 CRF 21。原片与派生物均完整解码通过，每段 22 个时间采样帧全部不同；两个整页版循环边界的平均灰度差均小于 1/255。海报已人工查看，最终星空亮度与运动感仍以实际应用窗口播放验收为准。

新增登记程序为 `validation/finalize_weather_night_assets.py`。本批登记清单将旧 9 种与新 2 种合并索引，但不覆盖任何旧视频、海报、联系表或清单。

## 无固定太阳的晴空增补 · day-v3

太阳位置改为按当前城市和时间计算后，背景需要避免出现第二个固定太阳。本批通过同一已登录 Grok 订阅、仅发送纯文字，新增 `clear-day-atmosphere`：晴朗蓝天与稀薄高云，没有预置太阳、月亮、星点或固定局部太阳光晕。旧 `clear-day` 原片及全部派生物保持不变。

- 原片与准确提示词/生成日志：`generated-20261108-day-v3/clear-day-atmosphere/`。
- 新运行文件：`runtime/clear-day-atmosphere.mp4/.jpg`（540 × 960），以及 `-compact`（600 × 200）。
- 三时刻取样图：`day-v3-contact-strip.jpg`；海报与取样图已查看，未见太阳或固定局部白晕。
- 整合 12 种资产、24 段运行视频的新来源与哈希清单：`manifest-20261108-day-v3.json`；此前两份清单均保留，前一版清单哈希可追溯。

新运行视频均为约 5.458 秒、24 fps、H.264、无音轨，首尾按相同 0.6 秒正向交叉淡化处理。完整解码、尺寸、原件哈希及所有旧资产哈希检查通过；22 个时间采样帧均不同，整页版每隔一秒的平均灰度差约 2.34/255。这是运动存在的数值证据，最终太阳叠加和实际播放体验由应用窗口验收。

登记程序为 `validation/finalize_weather_day_assets.py`。新增 2 段视频与 2 张海报合计 346,285 字节；不涉及上传本地资料、付费 API 或公开发布。
