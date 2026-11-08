# 图形来源

菜单栏和预报图标使用 [weather-iconic 原版 SVG](temps/SOURCE.md)，构建包随附许可证。自绘备用图标位于 `source/WeatherIcon.swift`。面板天气场景用 SwiftUI 绘制，设计出处见 [temps 动效参考](temps-effects/README.md)。天气类别使用 Open-Meteo 的 WMO 天气代码。

Finder 应用图标通过内置 imagegen 生成。[透明 PNG 原稿](AppIcon.png)和 [macOS 图标](AppIcon.icns)都纳入 Git。使用 `sips` 生成 16、32、128、256、512 点的 1× 与 2× 图像，再用 `iconutil` 封装。

生成提示词：

> Use case: logo-brand. Create one polished macOS application icon for a small weather menu bar utility. Straight-on flat square 1024 × 1024 icon asset with a genuinely transparent canvas outside one centered rounded-square tile. Tile fills about 84% of the canvas, with a softly curved continuous silhouette and a rich dusk blue to deep teal gradient, faint horizon glow and subtle glass edge. Center one generously sized sculpted cool-white cloud, slightly asymmetrical, overlapping a simple warm apricot sun disc behind its upper left. The cloud looks like soft satin glass or porcelain, with one clean silhouette and restrained depth. Keep sun and cloud shapes strongly separated, compact and readable at 16–32 pixels. Restrained macOS feel, refined contrast, soft illumination, fresh visual identity. Deliver the icon by itself, facing directly forward, no tilt, no surrounding objects, no drop shadow outside the tile, no border frame, no symbols beyond the cloud and sun, no text, no lettering, no watermark.
