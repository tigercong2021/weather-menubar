# 更新记录 / Changelog

## 2.0.0 · V2.0 — 2026-11-08

包版本 / Package: **2.0.0 (28)**. Changes below are relative to **1.0.1**.

- 新增逐小时降水概率、小时降水趋势图与保守摘要。 / Added hourly precipitation probabilities, an hourly chart and cautious summaries.
- 天气场景扩展至整页，采用原生玻璃材质，增强雨滴、风向、溅水、雨雪与昼夜天空。 / Expanded weather scenes across the panel with native glass, richer precipitation, wind direction, splashes and day/night skies.
- 新增菜单栏服装图标、简短悬停穿搭提示，以及基于当前条件的较强天气说明。 / Added a clothing icon, compact hover advice and brief notes for certain current severe conditions.
- 自动定位支持城市与区县，确认移动后更新主城；天气查询更精细。 / Added district-aware location updates and more precise forecast queries.
- AQI 改为连续、无刻度的当地历史分布色带；换位置重新匹配历史数据。 / Replaced the AQI display with a smooth, tick-free scale adapted to local history and refreshed when location changes.
- 重做关注页：紧凑卡片、选中城市背景、独立详情与原列表返回；窗口自然增高，必要时分页，避免截断城市和详情。 / Redesigned followed cities with compact cards, selected-city backgrounds, dedicated details and return to the original list page; natural sizing and overflow pagination keep content complete.
- 新增按经纬度与当前时刻计算的太阳、月亮、月相与预计最亮星点。银河背景保留为氛围素材。 / Added locally calculated sun, moon, lunar phase and expected brightest-object positions. The Milky Way remains atmospheric imagery.

小时趋势不是分钟级停雨预测；穿搭和天气说明不是官方预警。GitHub 发布源码，测试镜像另行提供。支持 Apple Silicon、macOS 26+；本地临时签名，未经公证，其他 Mac 待实机验证。

Hourly trends are not minute-by-minute rain-stop predictions; clothing and weather notes are not official alerts. GitHub publishes source, with test images supplied separately. Requires Apple Silicon and macOS 26+; ad hoc signed, not notarized, and awaiting testing on other Macs.

## 1.0.1 · 既有基线 / Previous baseline

已有菜单栏天气与摄氏温度、本地天气详情、最多 8 个关注城市及三日预报、AQI、手动城市与自动定位、动效预览和登录启动。

Already included menu bar weather and Celsius temperature, local details, up to eight followed cities with three-day forecasts, AQI, manual and automatic location, animation previews and launch at login.
