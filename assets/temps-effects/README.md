# temps 动效参考

参考项目为 Konrad Michalik 维护的 [temps v2](https://github.com/konradmichalik/temps)，固定版本为 [89bdff520f662fe75095b59ef13d5a4e2368322c](https://github.com/konradmichalik/temps/commit/89bdff520f662fe75095b59ef13d5a4e2368322c)。该版本的 [README](https://github.com/konradmichalik/temps/blob/89bdff520f662fe75095b59ef13d5a4e2368322c/README.md#-license) 声明采用 MIT 许可。固定版本的目录树没有独立的 LICENSE 或 COPYING 文件，package.json 没有 license 字段。这里以公开的动效规格为参考，用 SwiftUI 重新实现，仓库内没有引入其代码文件、截图或第三方天气图标。

- [背景粒子和闪电](https://github.com/konradmichalik/temps/blob/89bdff520f662fe75095b59ef13d5a4e2368322c/src/lib/components/effects/EffectsLayer.svelte) 提供 48 条雨线、36 片雪、各自错开的运动节奏，以及靠近底缘渐隐的布局。晴夜保留三颗星的方位和闪烁节奏。应用内的雷电保留罕见的短时节奏，亮度变化限在右侧局部，白天粒子颜色和雪花尺寸按卡片适配。
- [三层波形过渡](https://github.com/konradmichalik/temps/blob/89bdff520f662fe75095b59ef13d5a4e2368322c/src/lib/components/effects/Waves.svelte) 提供 22、34 和 50 秒的平移周期，以及 7、9 和 11 秒的波峰变化周期。应用按天气卡片的尺寸、圆角和昼夜色板重新绘制曲线。

0.2.0 在这些参考之上，结合 [Apple iPhone 天气图标分类](https://support.apple.com/en-ie/guide/iphone/iph4305794fb/ios) 与 [天气场景说明](https://www.apple.com/newsroom/2021/09/ios-15-is-available-today/)，调整雨雪档位、远近云层、按风向移动的风带和雷电辨识度。数值和天气分类按 [Open-Meteo 数据](https://open-meteo.com/en/docs) 选择。没有使用 Apple 的图形或视频资源。
