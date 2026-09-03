extends Node3D

## 视角对比 demo：同一套战斗逻辑（时钟/判定/谱面/顿帧完全不变），
## 只把渲染层从 2D 色块换成 3D 场景 + 固定侧视机位。
##
## 目的：回答"3D 的空间感值不值那个成本"，跟 song_fight.gd（2D 版）对照着玩。
## 角色是胶囊体，不建模不绑骨——这一步只测空间感，不测美术。
##
## 镜头**不自由旋转**，只做推近/微移，保证读招可读性不受影响
## （反例：《燕云十六声》被批"判定与锁定挺迷"，问题就出在自由镜头上）。

const CHART_HAND := "res://charts/qian_si_xi.chart.json"
const SONG_PATH := "res://audio/qian_si_xi.ogg"
const MAP_PATH := "res://audio/qian_si_xi.map.json"

const QI_MAX := 8
const CHORUS_MULTIPLIER := 2.0
const ENDING_TRIGGER_MARGIN_BEATS := 2.0
const ENDING_FADE_SEC := 10.0

const CAM_BASE_Z := 8.0
const CAM_CHORUS_Z := 6.0          # 副歌推近
const PLAYER_X := -2.0
const ENEMY_X := 2.0

@onready var music: AudioStreamPlayer = $Music
@onready var clock: BeatClock = $BeatClock
@onready var sfx: Sfx = $Sfx
@onready var camera: Camera3D = $Camera3D
@onready var player_mesh: MeshInstance3D = $World/Player
@onready var enemy_mesh: MeshInstance3D = $World/Enemy
@onready var player_mat: StandardMaterial3D = player_mesh.get_surface_override_material(0)
@onready var enemy_mat: StandardMaterial3D = enemy_mesh.get_surface_override_material(0)

@onready var readout: Label = $UI/Readout
@onready var banner: Label = $UI/Banner
@onready var section_label: Label = $UI/SectionLabel
@onready var note_lane: Control = $UI/NoteLane

var _map: SongMap
var _chart: Chart
var _section: int = SongMap.Section.INTRO
var _prev_section: int = -1
var _consumed: Dictionary = {}

var _hitstop_left: float = 0.0
var _shake_amount: float = 0.0
var _white_flash: float = 0.0

var _player_hp: int = 100
var _player_lunge: float = 0.0
var _player_flash: float = 0.0
var _block_hold: float = 0.0
var _qi: int = 0

var _enemy_hp: int = 6000
var _enemy_hp_max: int = 6000
var _enemy_flash: float = 0.0
var _enemy_recoil: float = 0.0

var _combo: int = 0
var _best_combo: int = 0
var _perfect: int = 0
var _good: int = 0
var _whiff: int = 0
var _blocked: int = 0
var _hit_taken: int = 0
var _finishers: int = 0
var _missed_strikes: int = 0
var _last_offset_ms: float = 0.0
var _banner_life: float = 0.0

var _start_sec: float = 0.0
var _last_chart_beat: float = 0.0
var _ending: bool = false
var _ending_timer: float = 0.0

var _cam_z: float = CAM_BASE_Z
var _cam_target_z: float = CAM_BASE_Z


func _ready() -> void:
	_map = SongMap.load_from(MAP_PATH)
	_chart = Chart.load_from(CHART_HAND)
	if _chart == null:
		_chart = Chart.new()
	music.stream = load(SONG_PATH)
	clock.bpm = _map.bpm
	clock.beats_per_bar = _map.beats_per_bar
	clock.first_beat_sec = _map.first_beat_sec
	clock.setup(music)
	note_lane.set_meta("owner_script", self)
	note_lane.draw.connect(_draw_note_lane)

	if not _chart.events.is_empty():
		var d := 60.0 / _map.bpm
		var first: float = _chart.events[0]["beat"]
		var last: float = _chart.events[-1]["beat"]
		_start_sec = maxf(0.0, _map.first_beat_sec + (first - 8.0) * d)
		_last_chart_beat = last

	_start_fight()


func _start_fight() -> void:
	_player_hp = 100
	_enemy_hp = _enemy_hp_max
	_combo = 0; _best_combo = 0
	_perfect = 0; _good = 0; _whiff = 0; _blocked = 0; _hit_taken = 0
	_finishers = 0; _missed_strikes = 0; _qi = 0
	_hitstop_left = 0.0
	_prev_section = -1
	_consumed.clear()
	_ending = false
	_ending_timer = 0.0
	banner.text = ""
	clock.stop()
	clock.start(_start_sec)


func _now_beat() -> float:
	return clock.beat_time() / clock.beat_duration()


func _nearest_event(role: int, now: float) -> Array:
	var best_i := -1
	var best_d := INF
	for i in _chart.events.size():
		if _consumed.has(i):
			continue
		var e: Dictionary = _chart.events[i]
		if int(e["role"]) != role:
			continue
		var b: float = e["beat"]
		var d: float = absf(b - now)
		if d < best_d:
			best_d = d
			best_i = i
	return [best_i, best_d]


func _upcoming(role: int, now: float, lookahead: float) -> float:
	var best := INF
	for i in _chart.events.size():
		if _consumed.has(i):
			continue
		var e: Dictionary = _chart.events[i]
		if int(e["role"]) != role:
			continue
		var b: float = e["beat"]
		if b >= now - 0.15 and b - now <= lookahead and b < best:
			best = b
	return best


func _process(delta: float) -> void:
	if _ending:
		_ending_timer += delta
		var fade_t := clampf(_ending_timer / ENDING_FADE_SEC, 0.0, 1.0)
		music.volume_db = lerpf(0.0, -40.0, fade_t)
		_decay(delta)
		_update_camera(delta)
		note_lane.queue_redraw()
		return

	if _hitstop_left > 0.0:
		_hitstop_left -= delta
		_white_flash = maxf(0.0, _white_flash - delta * 2.5)
		_apply_visuals()
		_update_readout()
		note_lane.queue_redraw()
		return

	_update_section()
	_expire_events()
	_check_ending()
	_decay(delta)
	_update_camera(delta)
	_apply_visuals()
	_update_readout()
	note_lane.queue_redraw()


func _check_ending() -> void:
	if _chart.events.is_empty():
		return
	if _now_beat() < _last_chart_beat + ENDING_TRIGGER_MARGIN_BEATS:
		return
	if _consumed.size() < _chart.events.size():
		return
	_ending = true
	_ending_timer = 0.0


func _update_section() -> void:
	_section = _map.section_at(clock.song_time())
	if _section == _prev_section:
		return
	if _section == SongMap.Section.CHORUS:
		_white_flash = 0.8
		_shake_amount = 0.35
		sfx.play(Sfx.BLOCK_PERFECT, 0.0, 0.0)
		_show_banner("破 防   伤害 x%.0f" % CHORUS_MULTIPLIER, Color(1.0, 0.85, 0.4), 54)
		_cam_target_z = CAM_CHORUS_Z
	else:
		_cam_target_z = CAM_BASE_Z
		if _section == SongMap.Section.BRIDGE:
			_show_banner("转阶段", Color(0.65, 0.85, 1.0), 38)
	_prev_section = _section


func _expire_events() -> void:
	var now := _now_beat()
	var tol := Judgment.GOOD_MS / 1000.0 / clock.beat_duration()
	for i in _chart.events.size():
		if _consumed.has(i):
			continue
		var e: Dictionary = _chart.events[i]
		var b: float = e["beat"]
		if now - b <= tol:
			continue
		_consumed[i] = true
		if int(e["role"]) == Chart.Role.BLOCK and _section != SongMap.Section.CHORUS:
			_take_hit()
		elif int(e["role"]) == Chart.Role.STRIKE:
			_missed_strikes += 1
			_combo = 0


func _decay(delta: float) -> void:
	_player_lunge = maxf(0.0, _player_lunge - delta * 7.0)
	_player_flash = maxf(0.0, _player_flash - delta * 5.0)
	_enemy_flash = maxf(0.0, _enemy_flash - delta * 5.0)
	_enemy_recoil = maxf(0.0, _enemy_recoil - delta * 5.0)
	_block_hold = maxf(0.0, _block_hold - delta)
	_white_flash = maxf(0.0, _white_flash - delta * 2.5)
	_banner_life = maxf(0.0, _banner_life - delta)
	_shake_amount = maxf(0.0, _shake_amount - delta * 5.0)
	if _banner_life <= 0.0:
		banner.text = ""


## 镜头只做推近/微移，绝不自由旋转 —— 保住读招可读性。
func _update_camera(delta: float) -> void:
	_cam_z = lerpf(_cam_z, _cam_target_z, delta * 2.0)
	var shake_x := randf_range(-_shake_amount, _shake_amount)
	var shake_y := randf_range(-_shake_amount, _shake_amount) * 0.6
	camera.position = Vector3(shake_x, 1.6 + shake_y, _cam_z)
	camera.look_at(Vector3(0, 1.2, 0), Vector3.UP)


func _apply_visuals() -> void:
	var blocking := _block_hold > 0.0
	player_mesh.position.x = PLAYER_X + _player_lunge * 0.9
	player_mesh.scale = Vector3.ONE * (1.15 if blocking else 1.0)
	var pc := Color(0.55, 0.82, 1.0)
	if _player_flash > 0.0:
		pc = pc.lerp(Color(1, 0.35, 0.35), _player_flash)
	player_mat.albedo_color = pc
	player_mat.emission = pc
	player_mat.emission_energy_multiplier = 0.15 + (0.9 if _qi >= QI_MAX else 0.0) \
		* (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))

	var broken := _section == SongMap.Section.CHORUS
	enemy_mesh.position.x = ENEMY_X + _enemy_recoil * 0.4
	enemy_mesh.scale = Vector3(1.0, 0.78 if broken else 1.0, 1.0)
	var ec := Color(1.0, 0.78, 0.35) if broken else Color(0.95, 0.42, 0.42)
	if _enemy_flash > 0.0:
		ec = ec.lerp(Color.WHITE, _enemy_flash)
	enemy_mat.albedo_color = ec
	enemy_mat.emission = ec
	enemy_mat.emission_energy_multiplier = 0.25


func _take_hit() -> void:
	_player_hp = maxi(0, _player_hp - 5)
	_hit_taken += 1
	_combo = 0
	_qi = maxi(0, _qi - 2)
	_player_flash = 1.0
	_shake_amount = 0.28
	sfx.play(Sfx.HURT, -2.0, 0.06)
	_show_banner("受击", Color(1.0, 0.4, 0.4), 32)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _ending:
		match event.keycode:
			KEY_R, KEY_SPACE: _start_fight()
			KEY_ESCAPE: get_tree().quit()
		return
	match event.keycode:
		KEY_SPACE: _attack()
		KEY_J:     _block()
		KEY_R:     _start_fight()
		KEY_BRACKETLEFT:  clock.offset_ms -= 5.0
		KEY_BRACKETRIGHT: clock.offset_ms += 5.0
		KEY_0:            clock.offset_ms = 0.0
		KEY_ESCAPE: get_tree().quit()


func _attack() -> void:
	if _hitstop_left > 0.0:
		return
	_player_lunge = 1.0
	var now := _now_beat()
	var found := _nearest_event(Chart.Role.STRIKE, now)
	var idx: int = found[0]
	_last_offset_ms = (now - float(_chart.events[idx]["beat"])) \
		* clock.beat_duration() * 1000.0 if idx >= 0 else 999.0
	var g := Judgment.grade(_last_offset_ms) if idx >= 0 else Judgment.Grade.WHIFF
	var in_chorus := _section == SongMap.Section.CHORUS
	var mult := CHORUS_MULTIPLIER if in_chorus else 1.0

	if g == Judgment.Grade.WHIFF:
		_whiff += 1; _combo = 0
		sfx.play(Sfx.SWING, -8.0, 0.10)
		_show_banner("空挥", Judgment.grade_color(g), 26)
		return

	_consumed[idx] = true
	_combo += 1
	_best_combo = maxi(_best_combo, _combo)

	if g == Judgment.Grade.PERFECT:
		_perfect += 1
		if _qi >= QI_MAX:
			_qi = 0
			_finishers += 1
			_white_flash = 1.0
			sfx.play(Sfx.HIT_FINISHER, 0.0, 0.02)
			_land_hit(int(120 * mult), Judgment.HITSTOP_FINISH, 0.55)
			_show_banner("终 结 斩", Color(1.0, 0.95, 0.6), 68)
		else:
			if not in_chorus:
				_qi = mini(QI_MAX, _qi + 1)
			sfx.play(Sfx.HIT_HEAVY, -1.0, 0.05)
			_land_hit(int(30 * mult), Judgment.HITSTOP_HEAVY, 0.22)
			_show_banner("完美  x%d" % _combo, Judgment.grade_color(g), 38)
	else:
		_good += 1
		sfx.play(Sfx.HIT_LIGHT, -3.0, 0.07)
		_land_hit(int(12 * mult), Judgment.HITSTOP_LIGHT, 0.10)
		_show_banner("命中  x%d" % _combo, Judgment.grade_color(g), 32)


func _land_hit(damage: int, hitstop_fraction: float, shake: float) -> void:
	_enemy_hp = maxi(0, _enemy_hp - damage)
	_enemy_flash = 1.0
	_enemy_recoil = 1.0
	_shake_amount = shake
	_hitstop_left = Judgment.hitstop_seconds(clock.beat_duration(), hitstop_fraction)


func _block() -> void:
	if _hitstop_left > 0.0:
		return
	_block_hold = 0.18
	var now := _now_beat()
	var found := _nearest_event(Chart.Role.BLOCK, now)
	var idx: int = found[0]
	if idx < 0:
		return
	var diff_ms: float = (now - float(_chart.events[idx]["beat"])) \
		* clock.beat_duration() * 1000.0
	if absf(diff_ms) > Judgment.GOOD_MS:
		return

	_consumed[idx] = true
	_blocked += 1
	var d := clock.beat_duration()
	if Judgment.grade(diff_ms) == Judgment.Grade.PERFECT:
		_qi = mini(QI_MAX, _qi + 1)
		_shake_amount = 0.24
		sfx.play(Sfx.BLOCK_PERFECT, 0.0, 0.03)
		_hitstop_left = Judgment.hitstop_seconds(d, Judgment.HITSTOP_HEAVY)
		_show_banner("完美格挡", Color(0.6, 1.0, 0.85), 38)
	else:
		_qi = mini(QI_MAX, _qi + 1)
		_shake_amount = 0.10
		sfx.play(Sfx.BLOCK, -2.0, 0.05)
		_hitstop_left = Judgment.hitstop_seconds(d, Judgment.HITSTOP_LIGHT)
		_show_banner("格挡", Color(0.7, 0.85, 0.95), 30)


func _show_banner(text: String, color: Color, size: int) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner.add_theme_font_size_override("font_size", size)
	_banner_life = 0.5


func _update_readout() -> void:
	var total := _perfect + _good + _whiff
	var acc := 0.0 if total == 0 else float(_perfect) * 100.0 / total
	readout.text = "\n".join([
		"[3D 视角 demo]   %s   BPM %.1f   校准 %+.0f ms   [ ] 调校准   0 归零"
			% [_map.file, clock.bpm, clock.offset_ms],
		"连段 %d (最高 %d)   完美 %d   命中 %d   空挥 %d   完美率 %.0f%%"
			% [_combo, _best_combo, _perfect, _good, _whiff, acc],
		"格挡 %d   受击 %d   终结斩 %d   气 %d/%d" % [_blocked, _hit_taken, _finishers, _qi, QI_MAX],
	])
	section_label.text = _map.label(_section)
	if _section == SongMap.Section.CHORUS:
		section_label.text += "   伤害 x%.0f" % CHORUS_MULTIPLIER


## 音符轨道照旧用 2D 叠加层画 —— 这部分 3D 化没有意义，HUD 永远是屏幕空间。
func _draw_note_lane() -> void:
	var vp := note_lane.size
	var cx := vp.x * 0.5
	var lane_y := 70.0
	var now := _now_beat()
	var px_per_beat := 150.0

	note_lane.draw_rect(Rect2(Vector2(0, lane_y - 26), Vector2(vp.x, 52)),
		Color(0, 0, 0, 0.25), true)
	note_lane.draw_line(Vector2(0, lane_y), Vector2(vp.x, lane_y), Color(1, 1, 1, 0.08), 1.0)

	for e in _chart.events:
		var b: float = e["beat"]
		var d: float = b - now
		if d < -0.8 or d > 4.0:
			continue
		var nx := cx + d * px_per_beat
		var is_strike := int(e["role"]) == Chart.Role.STRIKE
		var ny := lane_y - 13.0 if is_strike else lane_y + 13.0
		var col := Color(0.55, 0.82, 1.0) if is_strike else Color(0.95, 0.42, 0.42)
		note_lane.draw_circle(Vector2(nx, ny), 7.0, col)

	note_lane.draw_line(Vector2(cx, lane_y - 34), Vector2(cx, lane_y + 34),
		Color(1, 1, 1, 0.85), 2.0)

	if _white_flash > 0.0:
		note_lane.draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 1, _white_flash * 0.5), true)

	if _ending:
		_draw_ending(vp)


func _draw_ending(vp: Vector2) -> void:
	var fade_t := clampf(_ending_timer / ENDING_FADE_SEC, 0.0, 1.0)
	var dark := ease(fade_t, 1.6)
	note_lane.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.03, 0.05, dark * 0.94), true)
	if fade_t < 0.35:
		return
	var text_a := clampf((fade_t - 0.35) / 0.65, 0.0, 1.0)
	var font := ThemeDB.fallback_font
	var title := "余音未散"
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 52).x
	note_lane.draw_string(font, Vector2(vp.x * 0.5 - tw * 0.5, vp.y * 0.36),
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(1.0, 0.92, 0.75, text_a))
	var total := _perfect + _good + _whiff
	var acc := 0.0 if total == 0 else float(_perfect) * 100.0 / total
	var line := "完美率 %.0f%%   最高连段 %d   终结斩 %d" % [acc, _best_combo, _finishers]
	var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, -1, 22).x
	note_lane.draw_string(font, Vector2(vp.x * 0.5 - lw * 0.5, vp.y * 0.48),
		line, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.9, 0.95, text_a * 0.9))
