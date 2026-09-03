# Godot Engine — Version Reference

| Field | Value |
|-------|-------|
| **Engine Version** | Godot 4.7.2 |
| **Release Date** | 2026-08-26 (4.7.2 patch); 4.7.0 released ~June 2026 |
| **Project Pinned** | 2026-08-31 |
| **Last Docs Verified** | 2026-08-31 |
| **LLM Knowledge Cutoff** | May 2026 |
| **Risk Level** | **HIGH** — 4.7 released after the knowledge cutoff |

## Knowledge Gap Warning

训练数据覆盖到 Godot ~4.6（2026 年 1 月）。**4.7 整个大版本的改动模型不知道。**
在建议任何 Godot API 之前，先查本目录下的 `breaking-changes.md` 和 `deprecated-apis.md`。
不确定的 API 一律用 WebSearch 核实，不要凭记忆写。

## Post-Cutoff Version Timeline

| Version | Release | Risk | Key Theme |
|---------|---------|------|-----------|
| 4.4 | ~Mid 2025 | LOW (in training data) | Jolt physics option, FileAccess return types |
| 4.5 | ~Late 2025 | LOW (in training data) | AccessKit 无障碍、可变参数、`@abstract`、shader baker、SMAA |
| 4.6 | Jan 2026 | LOW (in training data) | Jolt 成为默认、glow 重做、Windows 默认 D3D12、IK 恢复 |
| **4.7** | **~Jun 2026** | **HIGH — 超出训练数据** | HDR 输出、AreaLight3D、Scene Paint、新 Asset Store、Control 偏移变换、设备 ID 常量 |
| 4.7.1 | 2026-07-13 | — | patch |
| 4.7.2 | 2026-08-26 | — | patch（当前锁定版本） |

## 本项目最关键的引擎知识

**节奏判定的时间基准** — 见 `modules/audio-timing.md`。
这是整个项目手感成败的技术核心，写任何判定代码前必读。

## Verified Sources

- 官方文档（4.7）: https://docs.godotengine.org/en/4.7/
- 4.6→4.7 迁移指南: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.7.html
- 4.7 发布说明: https://godotengine.org/releases/4.7/
- 音频同步教程: https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html
- Changelog: https://github.com/godotengine/godot/blob/master/CHANGELOG.md
