# Godot Deprecated / Removed APIs

*Last verified: 2026-08-31*
*Applies to: Godot 4.7.2*

写代码前查这张表。左边的一律不要用。

---

## 已移除（Removed）

| 不要用 | 改用 | 起始版本 |
|---|---|---|
| `AudioEffectSpectrumAnalyzer.tap_back_pos` | 已完全移除，无直接替代。频谱可视化需另寻方案 | 4.7 |
| Android OBB 导出 | Play Asset Delivery 或 PCK 分包 | 4.7 |

## 已废弃（Deprecated）

| 不要用 | 改用 | 起始版本 |
|---|---|---|
| `Node.auto_translate` | `Node.auto_translate_mode` | 4.7 |

## 更名 / 改签名（Renamed / Signature Changed）

| 旧 | 新 | 说明 |
|---|---|---|
| `RichTextLabel.width_in_percent` | `RichTextLabel.width_unit` | 类型改为 `RichTextLabel.ImageUnit` |
| `RichTextLabel.height_in_percent` | `RichTextLabel.height_unit` | 类型改为 `RichTextLabel.ImageUnit` |
| `RichTextLabel.add_image(...)` 尺寸参数 `int` | `float` | |
| `RichTextLabel.update_image(...)` 尺寸参数 `int` | `float` | |
| `AnimationNodeBlendSpace1D/2D.sync`（bool） | `SyncMode` 枚举 | |

## 不要再假设的常量值

| 旧假设 | 现在 | 说明 |
|---|---|---|
| 鼠标事件 `device == 0` | `InputEvent.DEVICE_ID_MOUSE` | 4.7 起改用常量，避免与手柄 ID 冲突 |
| 键盘事件 `device == 0` | `InputEvent.DEVICE_ID_KEYBOARD` | 同上 |

## 默认值变更（不是废弃，但会静默改变行为）

| 属性 | 旧默认 | 新默认 |
|---|---|---|
| `AudioStreamPlayer.area_mask` | `1` | `0` |
| `SoftBody3D` mass | `0` | `1` kg |
| 新项目窗口拉伸模式 | `disabled` | `canvas_items` |
| 字体描边颜色 | 白 | 黑 |

---

## Sources

- https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.7.html
- https://godotengine.org/releases/4.7/
