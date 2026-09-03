# Godot Breaking Changes

*Last verified: 2026-08-31*

只记录**超出 LLM 训练数据**的版本（4.7+）。4.4–4.6 在训练数据内，风险低。

---

## 4.6 → 4.7

官方说法：4.6 的项目迁移到 4.7 大体安全，但存在破坏性变更、行为变更和默认值变更。

### 音频（与本项目直接相关）

| 变更 | 影响 |
|---|---|
| `AudioEffectSpectrumAnalyzer.tap_back_pos` **被移除** | 若做频谱可视化（节拍指示器可能用到）不能再用此属性 |
| `AudioStreamPlayer.area_mask` 默认值从 `1` 改为 `0` | 音频总线覆盖功能默认关闭，需要手动重新配置 |

### 输入（与本项目直接相关）

| 变更 | 影响 |
|---|---|
| 鼠标/键盘的 `InputEvent` device ID 从 `0` 改为常量 `InputEvent.DEVICE_ID_MOUSE` / `DEVICE_ID_KEYBOARD` | 避免与手柄 ID 冲突。**判断输入来源的代码不能再假设 device == 0** |

### 2D 渲染

| 变更 | 影响 |
|---|---|
| `CanvasItem` 移除了线条抗锯齿羽化 | 线条比 4.6 更细，需要手动加宽 |
| `RichTextLabel.add_image` / `update_image` 尺寸参数由 `int` 改为 `float` | 调用处需改 |
| `RichTextLabel` 的 `width_in_percent` / `height_in_percent` 更名为 `width_unit` / `height_unit`，类型改为 `RichTextLabel.ImageUnit` | 调用处需改 |
| 默认字体描边颜色由白改黑 | 视觉差异 |

### 动画

| 变更 | 影响 |
|---|---|
| `AnimationNodeBlendSpace1D/2D` 的布尔 `sync` 属性改为 `SyncMode` 枚举 | 已有项目需手动调整 |
| `Animation.length` 类型 float → double | C# 二进制不兼容（GDScript 项目无影响） |
| `AnimationNodeBlendSpace*.add_blend_point` 新增可选 `name` 参数 | 向后兼容 |

### GDScript 语言

| 变更 | 影响 |
|---|---|
| 打包数组（PackedArray）设置元素时**不再触发整个属性的 setter** | 依赖此副作用的代码会静默失效 |
| 重写方法现在会继承父方法的类型化返回值 | 需要显式 `return` 语句，否则报错 |

### 物理（Jolt）

| 变更 | 影响 |
|---|---|
| `WorldBoundaryShape3D` 平面距离的正负号解释反转 | 3D 项目需检查 |
| `SoftBody3D` 默认质量 `0` → `1` kg；线性刚度与阻尼行为改变 | |
| `Area3D` 现在会上报与 `SoftBody3D` 的重叠 | |

### 其他默认值与平台

| 变更 | 影响 |
|---|---|
| 新项目默认窗口拉伸模式：`disabled` → `canvas_items` | 新建项目时的默认行为变了 |
| macOS 最低要求提升至 11 (Big Sur) | |
| Android OBB 支持移除 | 需迁移到 Play Asset Delivery 或 PCK 分包（本项目不涉及） |
| `SceneMultiplayer` 缓存协议变更 | 本项目无多人，不涉及 |

---

## Sources

- https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.7.html
- https://godotengine.org/releases/4.7/
