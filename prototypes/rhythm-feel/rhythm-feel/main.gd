extends Node2D

## 节拍时钟验证台。
##
## 回答三个问题：
##   1. 音频时钟准不准？（左边方块 vs 耳朵听到的"哒"）
##   2. 用渲染帧计时会漂多少？（右边方块 vs 左边方块）
##   3. 这台机器 + 这副耳机的真实延迟是多少？（按空格敲拍子，看统计）

const CLOCK_COLOR := Color(0.35, 0.85, 1.0)
const NAIVE_COLOR := Color(1.0, 0.45, 0.35)
const BOX_SIZE := 160.0

@onready var music: AudioStreamPlayer = $Music
@onready var clock: BeatClock = $BeatClock
@onready var readout: Label = $UI/Readout

# 错误示范：用渲染帧 delta 累加出来的"歌曲时间"
var _naive_time: float = 0.0
var _naive_beat: int = -1

var _clock_flash: float = 0.0
var _naive_flash: float = 0.0

# 敲击统计
var _taps: Array[float] = []
var _last_tap_ms: float = 0.0


func _ready() -> void:
	clock.setup(music)
	clock.beat_hit.connect(_on_beat)
	clock.start()


func _on_beat(_beat_index: int) -> void:
	_clock_flash = 1.0


func _process(delta: float) -> void:
	# 错误示范同步推进
	if music.playing:
		_naive_time += delta
		var nb := int(floor(_naive_time / clock.beat_duration()))
		if nb != _naive_beat:
			_naive_beat = nb
			_naive_flash = 1.0

	_clock_flash = maxf(0.0, _clock_flash - delta * 6.0)
	_naive_flash = maxf(0.0, _naive_flash - delta * 6.0)

	_update_readout()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_tap()
		elif event.keycode == KEY_R:
			_restart()
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()


func _tap() -> void:
	_last_tap_ms = clock.offset_to_nearest_beat_ms()
	_taps.append(_last_tap_ms)
	if _taps.size() > 40:
		_taps.pop_front()


func _restart() -> void:
	_naive_time = 0.0
	_naive_beat = -1
	_taps.clear()
	clock.stop()
	clock.start()


func _tap_average() -> float:
	if _taps.is_empty():
		return 0.0
	var sum := 0.0
	for t in _taps:
		sum += t
	return sum / _taps.size()


func _tap_spread() -> float:
	## 标准差 —— 衡量你敲得稳不稳，也反映系统抖动
	if _taps.size() < 2:
		return 0.0
	var avg := _tap_average()
	var sum := 0.0
	for t in _taps:
		sum += (t - avg) * (t - avg)
	return sqrt(sum / _taps.size())


func _update_readout() -> void:
	var drift_ms := (_naive_time - clock.song_time()) * 1000.0
	readout.text = "\n".join([
		"BPM %.0f    一拍 %.1f ms" % [clock.bpm, clock.beat_duration() * 1000.0],
		"",
		"[音频时钟]  %8.3f s   第 %d 拍" % [clock.song_time(), clock.current_beat()],
		"[渲染帧计时] %8.3f s   第 %d 拍" % [_naive_time, _naive_beat],
		"渲染帧累计漂移   %+.1f ms   <- 这就是为什么不能用帧计时" % drift_ms,
		"",
		"AudioServer.get_output_latency()      %6.2f ms" % (AudioServer.get_output_latency() * 1000.0),
		"AudioServer.get_time_since_last_mix() %6.2f ms" % (AudioServer.get_time_since_last_mix() * 1000.0),
		"混音率 %d Hz          FPS %d" % [AudioServer.get_mix_rate(), Engine.get_frames_per_second()],
		"抖动丢弃次数 %d" % clock.jitter_discards,
		"",
		"敲击 %d 次   最近 %+.1f ms   平均 %+.1f ms   波动 ±%.1f ms"
			% [_taps.size(), _last_tap_ms, _tap_average(), _tap_spread()],
		"",
		"空格 = 跟着响声敲    R = 重来    ESC = 退出",
	])


func _draw() -> void:
	var vp := get_viewport_rect().size
	var y := vp.y * 0.62
	_draw_box(Vector2(vp.x * 0.32, y), CLOCK_COLOR, _clock_flash, "音频时钟")
	_draw_box(Vector2(vp.x * 0.68, y), NAIVE_COLOR, _naive_flash, "渲染帧计时")


func _draw_box(center: Vector2, color: Color, flash: float, _label: String) -> void:
	var half := BOX_SIZE * (0.5 + flash * 0.18)
	var rect := Rect2(center - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
	var c := color
	c.a = 0.18 + flash * 0.82
	draw_rect(rect, c, true)
	draw_rect(rect, color, false, 2.0)
