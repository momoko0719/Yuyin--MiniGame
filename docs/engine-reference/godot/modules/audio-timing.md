# Audio Timing and Rhythm Sync (Godot 4.7)

*Last verified: 2026-08-31*

> **本项目最重要的一份引擎参考。** 写任何节奏判定代码前必读。
> 判定精度是《余音》的生死线：音游 Perfect 窗口通常 ±16–30ms，
> 而 60fps 一帧就是 16.7ms。时间基准搞错，整个游戏的手感就废了。

---

## 1. 绝不能用渲染帧计时

**禁止**用 `_process(delta)` 累加 delta 来推算歌曲进度。理由：

- 帧率会波动，累加误差会持续漂移，越到歌曲后段偏得越多
- 60fps 一帧 = 16.7ms，已经吃掉整个 Perfect 窗口的一半
- 音频和视频是两条独立的时钟，画面卡一下音乐不会等你

这条已写入 `.claude/docs/technical-preferences.md` 的 Forbidden Patterns。

---

## 2. 也不能直接用 `get_playback_position()`

官方文档明确指出：`AudioStreamPlayer.get_playback_position()`
**按音频缓冲区的速率更新，不是每帧更新**，直接拿来做节奏判定会产生抖动（jitter）。

---

## 3. 正确写法（官方推荐）

```gdscript
var time := player.get_playback_position() \
          + AudioServer.get_time_since_last_mix() \
          - AudioServer.get_output_latency()
```

三项的含义：

| 项 | 补偿的是什么 |
|---|---|
| `get_playback_position()` | 音频流当前播放到哪（按缓冲区粒度更新） |
| `AudioServer.get_time_since_last_mix()` | 音频线程上次混音之后又过了多久 |
| `AudioServer.get_output_latency()` | 混音之后到实际发声之间的硬件延迟 |

### 必须做单调性防抖

多线程导致这个值仍可能抖动。**每帧检查它不小于上一帧的值，小了就丢弃，沿用上一帧。**

```gdscript
var _last_song_time := 0.0

func get_song_time() -> float:
    var t := player.get_playback_position() \
           + AudioServer.get_time_since_last_mix() \
           - AudioServer.get_output_latency()
    if t < _last_song_time:
        return _last_song_time  # 抖动，丢弃本帧的值
    _last_song_time = t
    return t
```

---

## 4. 降低输出延迟

**Windows 下把 `Audio/CallbackBufferSize` 从默认 1024 调到 128。**
项目设置路径：`Project Settings → Audio → Driver → Output Latency` 及相关缓冲设置。
这是节奏游戏的常规做法，能显著降低整体延迟。

代价：缓冲区越小，音频线程压力越大，低配机器可能出现爆音。
应作为可调选项暴露给玩家，而不是写死。

---

## 5. 全局校准偏移（必做功能）

不同设备（板载声卡、蓝牙耳机、无线手柄、外接 DAC）的延迟差异可以到几十毫秒。
**必须提供玩家可调的 global offset**，并提供一个校准小工具
（放一段节拍，让玩家跟着敲，统计平均偏差自动写入）。

- 音频偏移与输入偏移建议**分开两个值**：前者补偿"听到的比实际晚"，
  后者补偿"按下去到程序收到"的延迟。
- 无线手柄需要独立于键盘的偏移值（见 technical-preferences.md 的 Platform Notes）。

---

## 6. 参考实现

Godot 官方 demo 项目里有一个 **Rhythm Game & BPM Sync** 示例，
用的正是上面这套 `get_time_since_last_mix` + `get_output_latency` 的方案。
动手前先看它。

---

## 7. 与顿帧的关系（本项目特有）

顿帧（hitstop）**只能冻结画面与游戏逻辑，绝不能暂停音频播放**。
音乐一停整首歌的时间轴就废了。

顿帧时长按音符时值计算（详见 `design/gdd/game-concept.md`）：

```gdscript
# 一拍的秒数
var beat_duration := 60.0 / bpm
# 轻击 = 1/16 拍，重击 = 1/8 拍，破防 = 1/4 拍，终结技 = 1/2 拍
var hitstop := beat_duration * hitstop_fraction
```

冻结画面时继续用 `get_song_time()` 推进歌曲时间轴，
解冻后画面直接跳到正确位置——**顿帧结束的那一刻正好落在一个音符位置上**。

---

## Sources

- https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html
- https://github.com/godotengine/godot/issues/44871 (get_playback_position 更新过慢)
- https://deepwiki.com/godotengine/godot-demo-projects/8.2-rhythm-game-and-bpm-sync
