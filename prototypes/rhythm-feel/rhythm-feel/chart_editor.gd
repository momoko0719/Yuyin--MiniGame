extends Node2D

## 制谱编辑器 —— 分段循环、边听边敲、逐个微调。
##
## 为什么不用自动生成：
## 试过了，不行。古风流行的节奏骨架在**人声**上（"兰花指捻红尘似水"，
## 每个字就是一个节奏点），而抒情曲的鼓又稀又软，
## 基于打击乐的自动检测几乎没有信号可抓，挑出来是噪声。
## 学术界最好的模型（Transformer + 1.4 万张谱面）也承认它
## "在生成低难度稀疏谱面时彻底失败" —— 而稀疏正是我们要的。
## 剪映的自动卡点同样是"给候选 + 人工修"。
##
## 所以：人工制谱，工具负责把人工做得舒服。
##
## 背景那条曲线是**人声能量包络** —— 尖峰就是字的位置，照着它放音符。

const SONGS := [
	{
		"name": "牵丝戏",
		"audio": "res://audio/qian_si_xi.ogg",
		"map": "res://audio/qian_si_xi.map.json",
		"envelope": "res://audio/qian_si_xi.envelope.json",
		"chart": "res://charts/qian_si_xi.chart.json",
	},
	{
		"name": "霍元甲",
		"audio": "res://audio/huo_yuan_jia.ogg",
		"map": "res://audio/huo_yuan_jia.map.json",
		"envelope": "res://audio/huo_yuan_jia.envelope.json",
		"chart": "res://charts/huo_yuan_jia.chart.json",
	},
	{
		"name": "北去一刀",
		"audio": "res://audio/bei_qu_yi_dao.ogg",
		"map": "res://audio/bei_qu_yi_dao.map.json",
		"envelope": "res://audio/bei_qu_yi_dao.envelope.json",
		"chart": "res://charts/bei_qu_yi_dao.chart.json",
	},
]

const COL_STRIKE := Color(0.55, 0.82, 1.0)
const COL_BLOCK := Color(0.95, 0.42, 0.42)
const COL_SEL := Color(1.0, 0.95, 0.5)
const NUDGE := 0.25          # 微调步长（1/4 拍）

@onready var music: AudioStreamPlayer = $Music
@onready var clock: BeatClock = $BeatClock
@onready var sfx: Sfx = $Sfx
@onready var readout: Label = $UI/Readout
@onready var hint: Label = $UI/Hint

var _song_index: int = 0
var _map: SongMap
var _chart: Chart
var _env: Dictionary = {}

var _block_bars: int = 4          # 一段几小节
var _block_index: int = 0
var _playing: bool = false
var _loop: bool = true
var _armed: bool = false          # 是否记录敲击（先听后敲）
var _speed: float = 1.0
var _selected: int = -1
var _saved_life: float = 0.0
var _flash_strike: float = 0.0
var _flash_block: float = 0.0
var _dragging: bool = false
var _drag_moved: bool = false

## 试听反馈：播放时音符自己发声，跟音乐一叠就知道对不对。
## 眼睛看不出 30 毫秒的偏差，耳朵能。
var _note_sound: bool = true
var _metronome: bool = false
var _played: Dictionary = {}          # 本轮已发声的音符下标
var _last_metro_beat: int = -999


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://charts")
	_load_song(0)


func _load_song(idx: int) -> void:
	_song_index = posmod(idx, SONGS.size())
	var s: Dictionary = SONGS[_song_index]
	_map = SongMap.load_from(s["map"])
	if _map == null:
		push_error("曲目地图加载失败：%s" % s["map"])
		return
	music.stream = load(s["audio"])
	clock.bpm = _map.bpm
	clock.beats_per_bar = _map.beats_per_bar
	clock.first_beat_sec = _map.first_beat_sec
	clock.setup(music)

	_env = {}
	if FileAccess.file_exists(s["envelope"]):
		var f := FileAccess.open(s["envelope"], FileAccess.READ)
		var d: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(d) == TYPE_DICTIONARY:
			_env = d

	_chart = Chart.load_from(s["chart"])
	if _chart == null:
		_chart = Chart.new()
		_chart.quantize = 4
	_chart.song = String(s["audio"]).get_file()
	_chart.bpm = _map.bpm
	_chart.first_beat_sec = _map.first_beat_sec

	_block_index = 0
	_selected = -1
	_stop()


# ---------------------------------------------------------------- 段落

func _beats_per_block() -> float:
	return float(_block_bars * _map.beats_per_bar)


func _block_start_beat() -> float:
	return _block_index * _beats_per_block()


func _block_end_beat() -> float:
	return _block_start_beat() + _beats_per_block()


func _block_count() -> int:
	var total_beats := (_map.duration_sec - _map.first_beat_sec) / clock.beat_duration()
	return maxi(1, int(ceil(total_beats / _beats_per_block())))


func _beat_to_sec(beat: float) -> float:
	return _map.first_beat_sec + beat * clock.beat_duration()


func _play_block() -> void:
	_playing = true
	music.pitch_scale = _speed
	_played.clear()
	_last_metro_beat = -999
	clock.start(_beat_to_sec(_block_start_beat()))


func _stop() -> void:
	_playing = false
	clock.stop()


func _goto_block(i: int) -> void:
	_block_index = clampi(i, 0, _block_count() - 1)
	_selected = -1
	if _playing:
		_play_block()


func _now_beat() -> float:
	return clock.beat_time() / clock.beat_duration()


# ---------------------------------------------------------------- 坐标映射
# 画和点击必须共用同一套映射，否则点不准

func _lane_x0() -> float:
	return 60.0


func _lane_w() -> float:
	return get_viewport_rect().size.x - 120.0


func _lane_cy() -> float:
	return get_viewport_rect().size.y * 0.44


func _lane_half() -> float:
	return 90.0


func _beat_to_x(beat: float) -> float:
	return _lane_x0() + _lane_w() * (beat - _block_start_beat()) / _beats_per_block()


func _x_to_beat(x: float) -> float:
	var rel := (x - _lane_x0()) / _lane_w()
	return _block_start_beat() + rel * _beats_per_block()


func _note_pos(i: int) -> Vector2:
	var e: Dictionary = _chart.events[i]
	var is_strike := int(e["role"]) == Chart.Role.STRIKE
	return Vector2(_beat_to_x(float(e["beat"])),
		_lane_cy() - 34.0 if is_strike else _lane_cy() + 34.0)


## 鼠标位置下的音符下标，没有则 -1
func _pick_note(pos: Vector2) -> int:
	var best := -1
	var best_d := 22.0
	for i in _block_event_indices():
		var d := pos.distance_to(_note_pos(i))
		if d < best_d:
			best_d = d
			best = i
	return best


func _in_lane(pos: Vector2) -> bool:
	var in_x := pos.x >= _lane_x0() and pos.x <= _lane_x0() + _lane_w()
	return in_x and absf(pos.y - _lane_cy()) <= _lane_half()


# ---------------------------------------------------------------- 鼠标

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_down(mb.position)
			else:
				_dragging = false
				_drag_moved = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var i := _pick_note(mb.position)
			if i >= 0:
				_chart.events.remove_at(i)
				_selected = -1
	elif event is InputEventMouseMotion and _dragging:
		_drag_to((event as InputEventMouseMotion).position)


func _on_left_down(pos: Vector2) -> void:
	if not _in_lane(pos):
		return
	var i := _pick_note(pos)
	if i >= 0:
		_selected = i
		_dragging = true
		_drag_moved = false
		return
	# 点空白 = 新建音符：上半是斩，下半是格挡
	var role := Chart.Role.STRIKE if pos.y < _lane_cy() else Chart.Role.BLOCK
	_chart.add(_x_to_beat(pos.x), role)
	_chart.sort()
	_selected = _pick_note(Vector2(_beat_to_x(_chart.snap(_x_to_beat(pos.x))),
		_lane_cy() - 34.0 if role == Chart.Role.STRIKE else _lane_cy() + 34.0))
	_dragging = _selected >= 0
	_drag_moved = false


func _drag_to(pos: Vector2) -> void:
	if _selected < 0 or _selected >= _chart.events.size():
		return
	var e: Dictionary = _chart.events[_selected]
	var beat := clampf(_chart.snap(_x_to_beat(pos.x)),
		_block_start_beat(), _block_end_beat() - 0.001)
	var role := Chart.Role.STRIKE if pos.y < _lane_cy() else Chart.Role.BLOCK
	if not is_equal_approx(float(e["beat"]), beat) or int(e["role"]) != role:
		_drag_moved = true
	e["beat"] = beat
	e["role"] = role
	_resync_selection(beat, role)
	_played.erase(_selected)      # 拖走之后允许重新发声


## 排序会打乱下标，按拍位和角色找回选中项
func _resync_selection(beat: float, role: int) -> void:
	_chart.sort()
	for i in _chart.events.size():
		var same_beat := is_equal_approx(float(_chart.events[i]["beat"]), beat)
		if same_beat and int(_chart.events[i]["role"]) == role:
			_selected = i
			return


# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	_flash_strike = maxf(0.0, _flash_strike - delta * 6.0)
	_flash_block = maxf(0.0, _flash_block - delta * 6.0)
	_saved_life = maxf(0.0, _saved_life - delta)

	if _playing:
		_tick_audition()

	if _playing and _loop and _now_beat() >= _block_end_beat():
		_play_block()          # 循环回到本段开头

	_update_readout()
	queue_redraw()


## 播放头经过音符时发声；节拍器每拍一响。
## 判定用音频时钟不用帧，否则试听本身就是错的。
func _tick_audition() -> void:
	var now := _now_beat()

	if _note_sound:
		for i in _block_event_indices():
			if _played.has(i):
				continue
			var beat: float = _chart.events[i]["beat"]
			if beat > now:
				continue
			_played[i] = true
			if int(_chart.events[i]["role"]) == Chart.Role.STRIKE:
				_flash_strike = 1.0
				sfx.play(Sfx.HIT_LIGHT, -6.0, 0.0)
			else:
				_flash_block = 1.0
				sfx.play(Sfx.BLOCK, -6.0, 0.0)

	if _metronome:
		var b := int(floor(now))
		if b != _last_metro_beat and now >= _block_start_beat():
			_last_metro_beat = b
			var is_bar := posmod(b, _map.beats_per_bar) == 0
			sfx.play(Sfx.METRO_HI if is_bar else Sfx.METRO_LO, -10.0, 0.0)


# ---------------------------------------------------------------- 输入

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE:
			if _playing and _armed:
				_tap(Chart.Role.STRIKE)
			else:
				_toggle_play()
		KEY_J:
			if _playing and _armed:
				_tap(Chart.Role.BLOCK)
		KEY_A:      _armed = not _armed
		KEY_L:      _loop = not _loop
		KEY_S:      _note_sound = not _note_sound
		KEY_M:      _metronome = not _metronome
		KEY_COMMA:  _goto_block(_block_index - 1)
		KEY_PERIOD: _goto_block(_block_index + 1)
		KEY_MINUS:  _set_speed(_speed - 0.25)
		KEY_EQUAL:  _set_speed(_speed + 0.25)
		KEY_1:      _set_block_bars(2)
		KEY_2:      _set_block_bars(4)
		KEY_3:      _set_block_bars(8)
		KEY_LEFT:   _select_step(-1)
		KEY_RIGHT:  _select_step(1)
		KEY_Z:      _nudge(-NUDGE)
		KEY_X:      _nudge(NUDGE)
		KEY_T:      _toggle_role()
		KEY_C:      _delete_selected()
		KEY_BACKSPACE: _delete_selected_or_last()
		KEY_DELETE: _clear_block()
		KEY_ENTER, KEY_KP_ENTER: _save()
		KEY_TAB:    _load_song(_song_index + 1)
		KEY_R:      _play_block()
		KEY_ESCAPE: get_tree().quit()


func _toggle_play() -> void:
	if _playing:
		_stop()
	else:
		_play_block()


func _set_speed(v: float) -> void:
	_speed = clampf(v, 0.5, 1.5)
	music.pitch_scale = _speed


func _set_block_bars(n: int) -> void:
	var anchor := _block_start_beat()
	_block_bars = n
	_block_index = int(anchor / _beats_per_block())
	_selected = -1
	if _playing:
		_play_block()


func _tap(role: Chart.Role) -> void:
	_chart.add(_now_beat(), role)
	if role == Chart.Role.STRIKE:
		_flash_strike = 1.0
		sfx.play(Sfx.HIT_LIGHT, -10.0, 0.04)
	else:
		_flash_block = 1.0
		sfx.play(Sfx.BLOCK, -10.0, 0.04)


# ---------------------------------------------------------------- 编辑

func _block_event_indices() -> Array:
	var a := _block_start_beat()
	var b := _block_end_beat()
	var out: Array = []
	for i in _chart.events.size():
		var beat: float = _chart.events[i]["beat"]
		if beat >= a and beat < b:
			out.append(i)
	return out


func _select_step(dir: int) -> void:
	var ids := _block_event_indices()
	if ids.is_empty():
		_selected = -1
		return
	if _selected == -1 or not ids.has(_selected):
		_selected = ids[0] if dir > 0 else ids[-1]
		return
	var pos := ids.find(_selected)
	_selected = ids[clampi(pos + dir, 0, ids.size() - 1)]


func _nudge(d: float) -> void:
	if _selected < 0 or _selected >= _chart.events.size():
		return
	var e: Dictionary = _chart.events[_selected]
	e["beat"] = maxf(0.0, float(e["beat"]) + d)
	_chart.sort()
	# sort 之后下标会变，重新按拍位找回选中项
	var target: float = e["beat"]
	for i in _chart.events.size():
		if is_equal_approx(float(_chart.events[i]["beat"]), target) \
				and int(_chart.events[i]["role"]) == int(e["role"]):
			_selected = i
			break


func _toggle_role() -> void:
	if _selected < 0 or _selected >= _chart.events.size():
		return
	var e: Dictionary = _chart.events[_selected]
	e["role"] = Chart.Role.BLOCK if int(e["role"]) == Chart.Role.STRIKE \
		else Chart.Role.STRIKE


func _delete_selected() -> void:
	if _selected < 0 or _selected >= _chart.events.size():
		return
	_chart.events.remove_at(_selected)
	_selected = -1


## 有选中就删选中，没有就删本段最后一个
func _delete_selected_or_last() -> void:
	if _selected >= 0 and _selected < _chart.events.size():
		_delete_selected()
	else:
		_delete_last_in_block()


func _delete_last_in_block() -> void:
	var ids := _block_event_indices()
	if ids.is_empty():
		return
	_chart.events.remove_at(ids[-1])
	_selected = -1


func _clear_block() -> void:
	var ids := _block_event_indices()
	ids.reverse()
	for i in ids:
		_chart.events.remove_at(i)
	_selected = -1


func _save() -> void:
	var s: Dictionary = SONGS[_song_index]
	if _chart.save_to(s["chart"]):
		_saved_life = 2.0


# ---------------------------------------------------------------- 显示

func _update_readout() -> void:
	var s: Dictionary = SONGS[_song_index]
	var ids := _block_event_indices()
	var t := _beat_to_sec(_block_start_beat())
	readout.text = "\n".join([
		"%s   BPM %.1f   一拍 %.0f ms   第 %d / %d 段（%d 小节）   起 %d:%02d"
			% [s["name"], clock.bpm, clock.beat_duration() * 1000.0,
			   _block_index + 1, _block_count(), _block_bars,
			   int(t) / 60, int(t) % 60],
		"本段 %d 个   全曲 %d 个   速度 %.2fx   循环 %s   试听音 %s   节拍器 %s   %s"
			% [ids.size(), _chart.events.size(), _speed,
			   "开" if _loop else "关",
			   "开" if _note_sound else "关",
			   "开" if _metronome else "关",
			   "● 记录中（A 关）" if _armed else "○ 只听不记（A 开记录）"],
	])
	hint.text = "空格 播放/斩   J 格挡   A 记录开关   S 试听音   M 节拍器   L 循环   , . 换段   1/2/3 段长   - = 速度\n" \
		+ "← → 选音符   Z X 左右微调   T 切换类型   C 删除   Backspace 删本段最后一个   Delete 清空本段   Enter 存盘   Tab 换歌   ESC 退出"
	if _saved_life > 0.0:
		hint.text = "已存盘 →  " + String(s["chart"])


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.08, 0.08, 0.11), true)
	if _map == null:
		return
	_draw_block(vp)
	_draw_song_bar(vp)
	_draw_tap_targets(vp)


## 整段铺在屏幕上（不滚动），所见即所得
func _draw_block(vp: Vector2) -> void:
	var x0 := _lane_x0()
	var w := _lane_w()
	var x1 := x0 + w
	var cy := _lane_cy()
	var half := _lane_half()
	var a := _block_start_beat()
	var n := _beats_per_block()

	var bx := func(beat: float) -> float:
		return _beat_to_x(beat)

	draw_rect(Rect2(Vector2(x0, cy - half), Vector2(w, half * 2.0)),
		Color(1, 1, 1, 0.04), true)

	_draw_envelope(bx, x0, w, cy, half, a, n)

	# 网格：小节线粗，拍线中，半拍线细
	var sub := 2
	var steps := int(n) * sub
	for i in steps + 1:
		var beat := a + float(i) / sub
		var x: float = bx.call(beat)
		var is_bar := fposmod(beat, float(_map.beats_per_bar)) < 0.01
		var is_beat := fposmod(beat, 1.0) < 0.01
		var alpha := 0.30 if is_bar else (0.14 if is_beat else 0.05)
		var wid := 2.0 if is_bar else 1.0
		draw_line(Vector2(x, cy - half), Vector2(x, cy + half),
			Color(1, 1, 1, alpha), wid)
		if is_bar:
			draw_line(Vector2(x, cy - half - 10), Vector2(x, cy - half),
				Color(1.0, 0.85, 0.4, 0.6), 2.0)

	draw_line(Vector2(x0, cy), Vector2(x1, cy), Color(1, 1, 1, 0.10), 1.0)

	# 音符
	for i in _chart.events.size():
		var e: Dictionary = _chart.events[i]
		var beat: float = e["beat"]
		if beat < a or beat >= a + n:
			continue
		var role: int = e["role"]
		var is_strike := role == Chart.Role.STRIKE
		var x: float = bx.call(beat)
		var y := cy - 34.0 if is_strike else cy + 34.0
		var col := COL_STRIKE if is_strike else COL_BLOCK
		if i == _selected:
			draw_circle(Vector2(x, y), 16.0, Color(COL_SEL.r, COL_SEL.g, COL_SEL.b, 0.35))
			draw_arc(Vector2(x, y), 16.0, 0, TAU, 32, COL_SEL, 2.0)
		draw_circle(Vector2(x, y), 10.0, col)

	# 播放头
	if _playing:
		var nb := _now_beat()
		if nb >= a and nb <= a + n:
			var px: float = bx.call(nb)
			draw_line(Vector2(px, cy - half - 14), Vector2(px, cy + half + 14),
				Color.WHITE, 2.0)


## 人声能量包络 —— 尖峰就是"字"的位置
func _draw_envelope(bx: Callable, _x0: float, _w: float, cy: float,
		half: float, a: float, n: float) -> void:
	if _env.is_empty():
		return
	var sub: int = _env.get("sub", 8)
	var voc: Array = _env.get("vocal", [])
	if voc.is_empty():
		return
	var first := int(a * sub)
	var last := int((a + n) * sub)
	var pts := PackedVector2Array()
	for i in range(first, last + 1):
		if i < 0 or i >= voc.size():
			continue
		var beat := float(i) / sub
		var v: float = voc[i]
		pts.append(Vector2(bx.call(beat), cy + half - v * (half * 1.5)))
	if pts.size() >= 2:
		draw_polyline(pts, Color(0.6, 0.85, 0.7, 0.45), 1.5)


func _draw_song_bar(vp: Vector2) -> void:
	var x0 := 60.0
	var w := vp.x - 120.0
	var y := vp.y * 0.80
	draw_rect(Rect2(Vector2(x0, y), Vector2(w, 8.0)), Color(1, 1, 1, 0.08), true)
	# 已有音符的覆盖范围
	var total := (_map.duration_sec - _map.first_beat_sec) / clock.beat_duration()
	for e in _chart.events:
		var beat: float = e["beat"]
		var px := x0 + w * clampf(beat / total, 0.0, 1.0)
		var role: int = e["role"]
		draw_line(Vector2(px, y), Vector2(px, y + 8.0),
			COL_STRIKE if role == Chart.Role.STRIKE else COL_BLOCK, 1.0)
	# 当前段
	var ba := x0 + w * (_block_start_beat() / total)
	var bb := x0 + w * (_block_end_beat() / total)
	draw_rect(Rect2(Vector2(ba, y - 5), Vector2(maxf(bb - ba, 3.0), 18.0)),
		Color(1, 1, 1, 0.22), false, 2.0)


func _draw_tap_targets(vp: Vector2) -> void:
	var y := vp.y * 0.90
	_target(Vector2(vp.x * 0.38, y), COL_STRIKE, _flash_strike)
	_target(Vector2(vp.x * 0.62, y), COL_BLOCK, _flash_block)


func _target(pos: Vector2, color: Color, flash: float) -> void:
	var r := 26.0 + flash * 10.0
	draw_circle(pos, r, Color(color.r, color.g, color.b, 0.10 + flash * 0.7))
	draw_arc(pos, r, 0, TAU, 40, color, 2.0)
