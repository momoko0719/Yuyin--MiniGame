extends Node2D

## 谱面录制器 —— 跟着音乐敲一遍，编排出这场武打。
##
## 空格 = 我斩    J = 他打我（该格挡）
## 敲下的时间点会自动吸附到十六分音符网格上，所以不用敲得很准，
## 跟着感觉走就行。
##
## 录完按 Enter 存盘，song_fight 会自动读取。

const SONGS := [
	{
		"name": "牵丝戏",
		"audio": "res://audio/qian_si_xi.ogg",
		"map": "res://audio/qian_si_xi.map.json",
		"chart": "res://charts/qian_si_xi.chart.json",
	},
	{
		"name": "霍元甲",
		"audio": "res://audio/huo_yuan_jia.ogg",
		"map": "res://audio/huo_yuan_jia.map.json",
		"chart": "res://charts/huo_yuan_jia.chart.json",
	},
	{
		"name": "北去一刀",
		"audio": "res://audio/bei_qu_yi_dao.ogg",
		"map": "res://audio/bei_qu_yi_dao.map.json",
		"chart": "res://charts/bei_qu_yi_dao.chart.json",
	},
]

const COL_STRIKE := Color(0.55, 0.82, 1.0)
const COL_BLOCK := Color(0.95, 0.42, 0.42)

@onready var music: AudioStreamPlayer = $Music
@onready var clock: BeatClock = $BeatClock
@onready var sfx: Sfx = $Sfx
@onready var readout: Label = $UI/Readout
@onready var hint: Label = $UI/Hint

var _song_index: int = 0
var _map: SongMap
var _chart: Chart
var _recording: bool = false
var _flash_strike: float = 0.0
var _flash_block: float = 0.0
var _saved_life: float = 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://charts")
	_load_song(0)


func _load_song(idx: int) -> void:
	_song_index = idx % SONGS.size()
	var s: Dictionary = SONGS[_song_index]
	_map = SongMap.load_from(s["map"])
	if _map == null:
		push_error("曲目地图加载失败：%s" % s["map"])
		return
	music.stream = load(s["audio"])
	clock.bpm = _map.bpm
	clock.beats_per_bar = _map.beats_per_bar
	clock.first_beat_sec = _map.first_beat_sec

	# 已有谱面就接着编辑，没有就新建
	_chart = Chart.load_from(s["chart"])
	if _chart == null:
		_chart = Chart.new()
	_chart.song = String(s["audio"]).get_file()
	_chart.bpm = _map.bpm
	_chart.first_beat_sec = _map.first_beat_sec

	clock.setup(music)
	_recording = false
	clock.stop()


func _start() -> void:
	_recording = true
	clock.start()


func _stop() -> void:
	_recording = false
	clock.stop()


func _process(delta: float) -> void:
	_flash_strike = maxf(0.0, _flash_strike - delta * 6.0)
	_flash_block = maxf(0.0, _flash_block - delta * 6.0)
	_saved_life = maxf(0.0, _saved_life - delta)
	_update_readout()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE:
			if _recording:
				_tap(Chart.Role.STRIKE)
			else:
				_start()
		KEY_J:
			if _recording:
				_tap(Chart.Role.BLOCK)
		KEY_BACKSPACE:
			_chart.remove_last()
		KEY_ENTER, KEY_KP_ENTER:
			_save()
		KEY_R:
			_stop()
			_load_song(_song_index)
		KEY_TAB:
			_stop()
			_load_song(_song_index + 1)
		KEY_DELETE:
			_chart.events.clear()
		KEY_ESCAPE:
			get_tree().quit()


func _tap(role: Chart.Role) -> void:
	var beat := clock.beat_time() / clock.beat_duration()
	_chart.add(beat, role)
	if role == Chart.Role.STRIKE:
		_flash_strike = 1.0
		sfx.play(Sfx.HIT_LIGHT, -8.0, 0.05)
	else:
		_flash_block = 1.0
		sfx.play(Sfx.BLOCK, -8.0, 0.05)


func _save() -> void:
	var s: Dictionary = SONGS[_song_index]
	if _chart.save_to(s["chart"]):
		_saved_life = 2.0


func _update_readout() -> void:
	var s: Dictionary = SONGS[_song_index]
	var t := clock.song_time()
	var total := _map.duration_sec if _map != null else 0.0
	readout.text = "\n".join([
		"%s   BPM %.1f   吸附到 1/%d 拍   %d:%02d / %d:%02d"
			% [s["name"], clock.bpm, _chart.quantize,
			   int(t) / 60, int(t) % 60, int(total) / 60, int(total) % 60],
		"",
		"已记录   斩 %d 个   格挡 %d 个   合计 %d"
			% [_chart.count(Chart.Role.STRIKE),
			   _chart.count(Chart.Role.BLOCK),
			   _chart.events.size()],
		"状态     %s" % ("● 录制中" if _recording else "○ 待机（空格开始）"),
	])
	hint.text = "空格 = 我斩    J = 他打我    Backspace = 撤销    Enter = 存盘" \
		+ "    Tab = 换歌    R = 重录    Delete = 清空    ESC = 退出"
	if _saved_life > 0.0:
		hint.text = "已存盘 →  " + String(s["chart"])


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.08, 0.08, 0.11), true)
	if _map == null:
		return

	_draw_beat_grid(vp)
	_draw_chart_lane(vp)
	_draw_tap_targets(vp)


## 当前小节的拍格，跟着音乐脉动
func _draw_beat_grid(vp: Vector2) -> void:
	var n := clock.beats_per_bar
	var beat := clock.current_beat()
	var prog := clock.beat_progress()
	var bar_start := beat - posmod(beat, n)
	var spacing := 64.0
	var x0 := vp.x * 0.5 - spacing * (n - 1) * 0.5
	for i in n:
		var b := bar_start + i
		var p := Vector2(x0 + spacing * i, vp.y * 0.30)
		var is_now := b == beat
		var pulse := (1.0 - prog) if is_now else 0.0
		var c := Color(1, 1, 1, 0.16 + pulse * 0.7)
		if i == 0:
			c = Color(1.0, 0.85, 0.4, c.a)
		draw_circle(p, 9.0 + pulse * 12.0, c)


## 谱面轨道：滚动显示已记录的事件，当前位置在中间
func _draw_chart_lane(vp: Vector2) -> void:
	var lane_y := vp.y * 0.58
	var center_x := vp.x * 0.5
	var px_per_beat := 90.0
	var now_beat := clock.beat_time() / clock.beat_duration()

	draw_line(Vector2(0, lane_y), Vector2(vp.x, lane_y), Color(1, 1, 1, 0.10), 2.0)

	# 网格线（每拍一条，小节线更亮）
	var first := int(floor(now_beat - center_x / px_per_beat))
	var last := int(ceil(now_beat + center_x / px_per_beat))
	for b in range(first, last + 1):
		var x := center_x + (b - now_beat) * px_per_beat
		var is_bar := posmod(b, clock.beats_per_bar) == 0
		draw_line(Vector2(x, lane_y - 26), Vector2(x, lane_y + 26),
			Color(1, 1, 1, 0.22 if is_bar else 0.08), 2.0 if is_bar else 1.0)

	# 事件
	for e in _chart.events:
		var eb: float = e["beat"]
		if eb < first - 1 or eb > last + 1:
			continue
		var x := center_x + (eb - now_beat) * px_per_beat
		var role: int = e["role"]
		var c := COL_STRIKE if role == Chart.Role.STRIKE else COL_BLOCK
		var y := lane_y - 14.0 if role == Chart.Role.STRIKE else lane_y + 14.0
		draw_circle(Vector2(x, y), 8.0, c)

	# 当前位置竖线
	draw_line(Vector2(center_x, lane_y - 40), Vector2(center_x, lane_y + 40),
		Color.WHITE, 2.0)


func _draw_tap_targets(vp: Vector2) -> void:
	var y := vp.y * 0.80
	_target(Vector2(vp.x * 0.35, y), COL_STRIKE, _flash_strike, "空格 · 我斩")
	_target(Vector2(vp.x * 0.65, y), COL_BLOCK, _flash_block, "J · 他打我")


func _target(pos: Vector2, color: Color, flash: float, _label: String) -> void:
	var r := 46.0 + flash * 14.0
	draw_circle(pos, r, Color(color.r, color.g, color.b, 0.12 + flash * 0.7))
	draw_arc(pos, r, 0, TAU, 48, color, 3.0)
