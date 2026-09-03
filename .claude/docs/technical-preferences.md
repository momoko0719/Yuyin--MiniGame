# Technical Preferences

<!-- Populated by /setup-engine. Updated as the user makes decisions throughout development. -->
<!-- All agents reference this file for project-specific standards and conventions. -->

## Engine & Language

- **Engine**: Godot 4.7.2
- **Language**: GDScript
- **Rendering**: Forward+ (Godot 4 default, PC target)
- **Physics**: Jolt (default since Godot 4.6)

## Input & Platform

<!-- Written by /setup-engine. Read by /ux-design, /ux-review, /test-setup, /team-ui, and /dev-story -->
<!-- to scope interaction specs, test helpers, and implementation to the correct input methods. -->

- **Target Platforms**: PC (Windows first, Steam)
- **Input Methods**: Keyboard/Mouse, Gamepad
- **Primary Input**: Keyboard
- **Gamepad Support**: Partial (optional alternative, not the design target)
- **Touch Support**: None
- **Platform Notes**:
  - **节奏判定必须以音频播放位置为时间基准，绝不能用渲染帧。**
    60fps 一帧 = 16.7ms，而音游 Perfect 窗口通常是 ±16–30ms。
    用帧计时判定精度天然废掉一半。
  - **必须提供全局校准偏移（global offset）设置**，不同设备音频延迟差异很大。
  - 手柄为可选辅助输入。无线手柄有额外延迟，需要独立的校准偏移。
  - 所有战斗操作必须能用键盘完成，不得有仅手柄可用的功能。

## Naming Conventions

GDScript standard conventions:

- **Classes**: PascalCase (e.g., `PlayerController`)
- **Variables**: snake_case (e.g., `move_speed`)
- **Functions**: snake_case (e.g., `take_damage()`)
- **Signals/Events**: snake_case, past tense (e.g., `health_changed`, `beat_hit`)
- **Files**: snake_case matching class (e.g., `player_controller.gd`)
- **Scenes/Prefabs**: PascalCase matching root node (e.g., `PlayerController.tscn`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_HEALTH`, `PERFECT_WINDOW_MS`)

## Performance Budgets

- **Target Framerate**: 60 fps — **hard floor, not a target**
- **Frame Budget**: 16.6 ms
- **Draw Calls**: < 500 (generous for stylized 2D/2.5D)
- **Memory Ceiling**: 2 GB

> **为什么帧率对本项目是硬性要求**：顿帧时长精确到 1/16 拍。
> 120 BPM 下 1/16 拍 = 31ms ≈ 不到 2 帧。帧率不稳会导致顿帧时长忽长忽短，
> 玩家会感觉"这一刀有时候沉有时候飘"却说不出原因。
> **普通动作游戏掉帧只是卡，本项目掉帧是手感失真。**

## Testing

- **Framework**: Deferred — 见 `/test-setup`。项目默认 **gdUnit4**
  （已预设于 `coding-standards.md` 与 CI 配置：
  `godot --headless --script tests/gdunit4_runner.gd`）
- **Minimum Coverage**: Deferred — 见 `/test-setup`
- **Required Tests**: 顿帧时长计算、判定窗口、BPM/音符时值换算、伤害与连段公式
- **推迟理由**: 原型阶段代码是一次性的；且核心验证问题（"砍在拍子上爽不爽"）
  无法自动化测试，只能靠实际游玩。真正值得测的是后续确定性计算。

## Forbidden Patterns

<!-- Add patterns that should never appear in this project's codebase -->
- **禁止用渲染帧（`_process` delta 累加）作为节奏判定的时间基准** —
  必须使用 `AudioStreamPlayer.get_playback_position()` 或等价的音频时钟
- [其余待补 — 随架构决策逐条添加]

## Allowed Libraries / Addons

<!-- Add approved third-party dependencies here -->
- [None configured yet — add as dependencies are approved]

## Architecture Decisions Log

<!-- Quick reference linking to full ADRs in docs/architecture/ -->
- [No ADRs yet — use /architecture-decision to create one]

## Engine Specialists

<!-- Written by /setup-engine when engine is configured. -->
<!-- Read by /code-review, /architecture-decision, /architecture-review, and team skills -->
<!-- to know which specialist to spawn for engine-specific validation. -->

- **Primary**: godot-specialist
- **Language/Code Specialist**: godot-gdscript-specialist (all .gd files)
- **Shader Specialist**: godot-shader-specialist (.gdshader files, VisualShader resources)
- **UI Specialist**: godot-specialist (no dedicated UI specialist — primary covers all UI)
- **Additional Specialists**: godot-gdextension-specialist (GDExtension / native C++ bindings only)
- **Routing Notes**: Invoke primary for architecture decisions, ADR validation, and
  cross-cutting code review. Invoke GDScript specialist for code quality, signal
  architecture, static typing enforcement, and GDScript idioms. Invoke shader
  specialist for material design and shader code. Invoke GDExtension specialist only
  when native extensions are involved.

### File Extension Routing

<!-- Skills use this table to select the right specialist per file type. -->
<!-- If a row says [TO BE CONFIGURED], fall back to Primary for that file type. -->

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| Game code (.gd files) | godot-gdscript-specialist |
| Shader / material files (.gdshader, VisualShader) | godot-shader-specialist |
| UI / screen files (Control nodes, CanvasLayer) | godot-specialist |
| Scene / prefab / level files (.tscn, .tres) | godot-specialist |
| Native extension / plugin files (.gdextension, C++) | godot-gdextension-specialist |
| General architecture review | godot-specialist |
