class_name BeatClock
extends Node

## 节拍时钟 —— 整个游戏的时间基准。
##
## 绝不能用渲染帧（累加 _process 的 delta）推算歌曲进度：
## 帧率波动会让误差持续漂移，而音游 Perfect 窗口只有 ±16~30ms，
## 60fps 一帧就已经 16.7ms。
##
## 正确做法（Godot 官方文档推荐）：
##   playback_position + time_since_last_mix - output_latency
## 详见 docs/engine-reference/godot/modules/audio-timing.md

signal beat_hit(beat_index: int)

@export var bpm: float = 120.0
@export var beats_per_bar: int = 4

## 玩家校准偏移（毫秒）。正值 = 判定时间往后推。
## 每台机器、每副耳机都不同，正式版要做校准工具让玩家自己测。
@export var offset_ms: float = 0.0

## 歌曲第一拍的位置（秒）。由 tools/analyze_song.py 自动检测得出。
## 真实歌曲开头几乎总有一小段静音或起拍，不减掉的话整首歌的拍号都会错位。
@export var first_beat_sec: float = 0.0

var _player: AudioStreamPlayer
var _last_time: float = 0.0
var _last_beat: int = -1
var _running: bool = false

## 供调试显示：上一帧的原始值（未做单调性防抖）
var raw_time: float = 0.0
var jitter_discards: int = 0


func setup(player: AudioStreamPlayer) -> void:
	_player = player


func start(from_sec: float = 0.0) -> void:
	if _player == null:
		push_error("BeatClock: 没有设置 AudioStreamPlayer")
		return
	_last_time = from_sec
	_last_beat = -1
	jitter_discards = 0
	_running = true
	_player.play(from_sec)


func stop() -> void:
	_running = false
	if _player != null:
		_player.stop()


## 一拍多少秒
func beat_duration() -> float:
	return 60.0 / bpm


## 当前歌曲时间（秒）。这是唯一可信的时间源。
func song_time() -> float:
	if _player == null or not _player.playing:
		return _last_time

	raw_time = _player.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency() \
		+ offset_ms / 1000.0

	# 多线程导致的抖动：时间不可能倒流，倒流了就丢弃本帧的值。
	if raw_time < _last_time:
		jitter_discards += 1
		return _last_time

	_last_time = raw_time
	return raw_time


## 相对第一拍的时间 —— 所有拍号计算都基于它
func beat_time() -> float:
	return song_time() - first_beat_sec


## 当前是第几拍（从 0 开始）
func current_beat() -> int:
	return int(floor(beat_time() / beat_duration()))


## 当前拍内进度，0.0 = 刚好在拍上，趋近 1.0 = 快到下一拍
func beat_progress() -> float:
	var d := beat_duration()
	return fposmod(beat_time(), d) / d


## 距离最近的拍点有多少毫秒（带符号：负=早了，正=晚了）
## 这就是判定用的数值。
func offset_to_nearest_beat_ms() -> float:
	var d := beat_duration()
	var phase := fposmod(beat_time(), d)
	if phase > d * 0.5:
		phase -= d          # 更接近下一拍，算作"早了"
	return phase * 1000.0


func _process(_delta: float) -> void:
	if not _running:
		return
	var b := current_beat()
	if b != _last_beat:
		_last_beat = b
		beat_hit.emit(b)
