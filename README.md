<p align="center">
  <h1 align="center">余音 · Yuyin</h1>
  <p align="center">
    古风江湖的节奏战斗游戏 —— 你在用一首歌杀人。
    <br />
    <em>A guofeng wuxia rhythm-combat game. You kill with a song.</em>
  </p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/engine-Godot%204.7.2-478cbf?logo=godotengine&logoColor=white" alt="Godot 4.7.2">
  <img src="https://img.shields.io/badge/language-GDScript-355570" alt="GDScript">
  <img src="https://img.shields.io/badge/platform-PC%20%2F%20Steam-lightgrey" alt="PC">
  <img src="https://img.shields.io/badge/status-prototype-orange" alt="Prototype">
</p>

---

## 这是什么

一个**古风节奏战斗游戏**的原型。核心是一句话：

> **打击的爽，和卡上拍子的爽，必须是同一下。**

不是"打架时放着音乐"，而是刀落下的那一瞬间，物理上的沉和音乐上的准同时发生，
分不出哪个是哪个。**一首歌就是一场 BOSS 战**——曲式结构就是战斗结构：
前奏对峙、主歌读招攒气、副歌破防爆发。

演示内容是《牵丝戏》的一场戏：**傀儡师与提线**。手工编排了 14 段谱面、137 个音符。

## 核心设计

| | |
|---|---|
| **顿帧用音符时值定义，不用秒** | 轻击 1/16 拍、完美斩 1/8 拍、终结斩 3/8 拍。顿帧结束的那一刻正好落在音符位置上——**那个"凝滞"既是打击感也是节奏本身**，并且自动适配任何 BPM |
| **节奏是奖励，不是及格线** | 漏拍只是伤害低、不进连段，绝不扣血。判定窗口 Perfect ±60ms / Good ±120ms，比标准音游宽一倍 |
| **音符是挂在丝线上的铃铛** | 歌词里"盘铃声清脆"。轨道读作戏台上方的提线架，不做全屏掉落音符——视线要留在角色身上 |
| **谱面由人跟着音乐敲出来** | 机械周期在拍网格上精确，但跟乐句无关，玩起来别扭。古风流行的节奏骨架在**人声**上 |

## 跑起来

需要 [Godot 4.7.2](https://godotengine.org/)。用 Godot 打开
`prototypes/rhythm-feel/rhythm-feel/`，按 F5。

| 键 | 作用 |
|---|---|
| 空格 | 斩 |
| J | 格挡 |
| `[` `]` `0` | 判定校准 ∓5ms / 归零 |
| M | 标记副歌起点 |
| F1 | 调试台（摆位置/大小/旋转，存盘后自动套用） |
| R / ESC | 重来 / 退出 |

> **音频说明**：仓库**不含**《牵丝戏》《霍元甲》的音频——它们是商业版权音乐。
> 随仓库附带的 `bei_qu_yi_dao.ogg`（Suno 生成）可以直接用。
> 想用自己的歌，见 [原型 README](prototypes/rhythm-feel/README.md) 的说明。

## 目录

```
design/gdd/game-concept.md      游戏概念文档（含竞品分析）
design/narrative/               主题曲歌词与曲式映射
prototypes/rhythm-feel/         Godot 原型 + 完整开发记录
  ├── README.md                 ← 所有验证结论都在这里
  ├── ASSETS.md                 美术素材规格与 AI 生成 prompt
  └── rhythm-feel/              Godot 项目本体
tools/                          音频分析、曲目地图、包络导出、音效合成
docs/engine-reference/godot/    Godot 4.7 版本参考（含节奏同步专用模块）
```

## 已验证的结论

完整记录见 **[prototypes/rhythm-feel/README.md](prototypes/rhythm-feel/README.md)**，摘要：

- **音频时钟必须用音频播放位置，不能用渲染帧**。实测渲染帧计时 30 秒漂移 +12.4ms，
  一首 3.5 分钟的歌会漂到约 87ms
- **判定窗口要比标准音游宽得多**。实测人工敲击波动 ±29.5ms，而标准音游 Perfect
  窗口只有 ±16–30ms——按那个标准，开发者本人都打不准
- **顿帧量化到音符时值成立**，是这个项目最独特的一条
- **自动生成谱面对抒情曲不可行**——古风流行的节奏在人声不在鼓上。学术界最好的
  模型也承认"在生成低难度稀疏谱面时彻底失败"，改为人工制谱 + 工具辅助
- **"换武器=换音符密度"被证伪**——那只是难度分级，不是玩法差异。改为
  「每个对手改变节奏本身」

## 工具链

制谱不是靠自动生成，是靠一套让人做得舒服的工具：

```bash
python tools/analyze_song.py <音频>              # BPM、首拍、拍点置信度
python tools/make_songmap.py <auto.json> "0:intro,64:chorus"
python tools/make_envelope.py <音频> <map.json>  # 人声能量包络，制谱时的背景参考
python tools/make_sfx.py <输出目录>              # 程序合成打击音效
```

外加 `chart_editor.tscn`——分段循环播放、试听音、鼠标拖拽微调的制谱编辑器。

---

## 致谢

本项目的开发流程使用了
**[Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios)**
（MIT）提供的 Claude Code 技能与代理框架——从 `/brainstorm` 构思、`/setup-engine`
配置引擎，到 `/prototype` 的原型阶段规范，都走的它的工作流。仓库里的
`.claude/` 目录来自该项目。

音乐《牵丝戏》原唱：银临 / Aki 阿杰。仅在本地原型中用于手感验证，未随仓库分发。

## License

MIT
