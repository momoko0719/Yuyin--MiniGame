extends Node2D

## 《牵丝戏》一场戏 —— 谱面驱动的战斗，接上真实美术。
##
## 三个从试玩里长出来的设计决定：
##
## 1. **谱面由人跟着音乐敲出来**，不是机械取模。机械周期在拍网格上精确，
##    但跟乐句无关，玩起来别扭。
##
## 2. **音符是挂在丝线上的铃铛**（歌词："盘铃声清脆"），轨道在戏台上方，
##    读作提线架。不做全屏掉落轨道（视线会离开角色），也不做贴身收缩环
##    （密集节奏时几个环叠一起分不出先后，实测问题）。
##
## 3. **手臂是"出招时才出现的动作姿态"，不是常驻骨骼。**
##    傀儡本来就是啪地摆出一个姿势 —— 这既省掉了关节对齐，也正是这首歌的美学。

const SONG_PATH := "res://audio/qian_si_xi.ogg"
const MAP_PATH := "res://audio/qian_si_xi.map.json"
const CHART_PATH := "res://charts/qian_si_xi.chart.json"
const NOTE_STRIKE := preload("res://art/ui/note_strike.png")
const NOTE_BLOCK := preload("res://art/ui/note_block.png")

const QI_MAX := 8
const CHORUS_MULTIPLIER := 2.0
const LANE_Y := 200.0
const BELL_DROP := 54.0          # 铃铛统一挂在这个高度（不再分高低，避免混淆）
const LANE_LOOKAHEAD_BEATS := 4.0
const LANE_PX_PER_BEAT := 150.0
const BELL_SCALE := 0.072
const TUNING_PATH := "res://tuning.json"
const SECTIONS_PATH := "res://sections_override.json"
const LEAD_IN_BARS := 2
const ENDING_TRIGGER_MARGIN_BEATS := 2.0
const ENDING_FADE_SEC := 10.0

# 两种铃在贴图上很接近，所以靠强着色区分：斩=青，格挡=朱
const COL_STRIKE := Color(0.45, 1.0, 1.0)
const COL_BLOCK := Color(1.0, 0.32, 0.28)
const COL_STRING := Color(0.95, 0.90, 0.78)

## 调试台可调的部件
const TUNE_TARGETS := [
	"World/Player", "World/Player/Body", "World/Player/ArmSword",
	"World/Enemy", "World/Enemy/Body", "World/Enemy/ArmRaise",
	"World/Slash", "World/Lanterns/L0", "World/Lanterns/L1",
	"World/BgFar", "World/BgMid", "World/BgFore",
]

@onready var music: AudioStreamPlayer = $Music
@onready var clock: BeatClock = $BeatClock
@onready var sfx: Sfx = $Sfx
@onready var world: Node2D = $World
@onready var player: Node2D = $World/Player
@onready var player_arm: Sprite2D = $World/Player/ArmSword
@onready var enemy: Node2D = $World/Enemy
@onready var enemy_body: Sprite2D = $World/Enemy/Body
@onready var enemy_arm: Sprite2D = $World/Enemy/ArmRaise
@onready var slash: Sprite2D = $World/Slash
@onready var lanterns: Node2D = $World/Lanterns
@onready var lane: Control = $UI/Lane
@onready var readout: Label = $UI/Readout
@onready var banner: Label = $UI/Banner
@onready var section_label: Label = $UI/SectionLabel

var _map: SongMap
var _chart: Chart
var _section: int = SongMap.Section.INTRO
var _prev_section: int = -1
var _consumed: Dictionary = {}

var _hitstop_left: float = 0.0
var _shake: float = 0.0
var _white_flash: float = 0.0

var _player_home := Vector2.ZERO
var _enemy_home := Vector2.ZERO
var _player_home_rot: float = 0.0
var _enemy_home_rot: float = 0.0
var _broken: float = 0.0             # 破防程度 0~1，用于"丝线松了"的垂下姿态
var _player_lunge: float = 0.0
var _player_flash: float = 0.0
var _block_hold: float = 0.0
var _enemy_flash: float = 0.0
var _enemy_recoil: float = 0.0
var _enemy_raise: float = 0.0        # 傀儡师抬手（牵丝预兆）
var _slash_life: float = 0.0
var _qi: int = 0

var _player_hp: int = 100
var _enemy_hp: int = 6000
var _enemy_hp_max: int = 6000

var _combo: int = 0
var _best_combo: int = 0
var _perfect: int = 0
var _good: int = 0
var _whiff: int = 0
var _blocked: int = 0
var _hit_taken: int = 0
var _finishers: int = 0
var _missed: int = 0
var _last_offset_ms: float = 0.0
var _banner_life: float = 0.0

var _start_sec: float = 0.0
var _last_chart_beat: float = 0.0
var _ending: bool = false
var _ending_timer: float = 0.0

## 调试台：运行时摆位置/大小/旋转，存进 tuning.json，下次自动加载
var _debug: bool = false
var _tune_idx: int = 0
var _tune_msg: String = ""
var _tune_msg_life: float = 0.0


func _ready() -> void:
	_map = SongMap.load_from(MAP_PATH)
	if _map == null:
		push_error("曲目地图加载失败：%s" % MAP_PATH)
		return
	_chart = Chart.load_from(CHART_PATH)
	if _chart == null:
		push_warning("没有谱面 %s" % CHART_PATH)
		_chart = Chart.new()

	music.stream = load(SONG_PATH)
	clock.bpm = _map.bpm
	clock.beats_per_bar = _map.beats_per_bar
	clock.first_beat_sec = _map.first_beat_sec
	clock.setup(music)

	_load_tuning()
	_load_sections_override()
	_player_home = player.position
	_enemy_home = enemy.position
	_player_home_rot = player.rotation
	_enemy_home_rot = enemy.rotation
	lane.draw.connect(_draw_lane)

	if not _chart.events.is_empty():
		var d := 60.0 / _map.bpm
		var first: float = _chart.events[0]["beat"]
		_last_chart_beat = _chart.events[-1]["beat"]
		var lead := float(LEAD_IN_BARS * _map.beats_per_bar)
		_start_sec = maxf(0.0, _map.first_beat_sec + (first - lead) * d)

	_start_fight()


func _start_fight() -> void:
	_player_hp = 100
	_enemy_hp = _enemy_hp_max
	_combo = 0; _best_combo = 0
	_perfect = 0; _good = 0; _whiff = 0
	_blocked = 0; _hit_taken = 0; _finishers = 0; _missed = 0
	_qi = 0
	_hitstop_left = 0.0
	_prev_section = -1
	_consumed.clear()
	_ending = false
	_ending_timer = 0.0
	music.volume_db = 0.0
	banner.text = ""
	clock.stop()
	clock.start(_start_sec)


func _now_beat() -> float:
	return clock.beat_time() / clock.beat_duration()


# ---------------------------------------------------------------- 谱面查询

func _nearest(role: int, now: float) -> int:
	var best := -1
	var best_d := INF
	for i in _chart.events.size():
		if _consumed.has(i):
			continue
		var e: Dictionary = _chart.events[i]
		if int(e["role"]) != role:
			continue
		var d: float = absf(float(e["beat"]) - now)
		if d < best_d:
			best_d = d
			best = i
	return best


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


# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	_tune_msg_life = maxf(0.0, _tune_msg_life - delta)

	if _debug:
		# 调参时冻住战斗，强制显示手臂方便对位。
		# 注意 modulate 也要复位 —— 傀儡师手臂平时靠 modulate.a 做淡入淡出，
		# 只设 visible 的话它仍然是全透明的（踩过这个坑）。
		player_arm.visible = true
		player_arm.modulate = Color.WHITE
		enemy_arm.visible = true
		enemy_arm.modulate = Color.WHITE
		enemy_body.modulate = Color.WHITE
		player.modulate = Color.WHITE
		slash.visible = true
		slash.modulate = Color(1, 1, 1, 0.85)
		world.position = Vector2.ZERO
		lane.queue_redraw()
		return

	if _ending:
		_ending_timer += delta
		music.volume_db = lerpf(0.0, -40.0, clampf(_ending_timer / ENDING_FADE_SEC, 0.0, 1.0))
		_decay(delta)
		_apply_visuals(delta)
		lane.queue_redraw()
		return

	# 顿帧冻结画面与逻辑，但**绝不冻结音乐** —— 时钟读的是音频播放位置。
	if _hitstop_left > 0.0:
		_hitstop_left -= delta
		_white_flash = maxf(0.0, _white_flash - delta * 2.5)
		lane.queue_redraw()
		return

	_update_section()
	_expire_events()
	_check_ending()
	_decay(delta)
	_apply_visuals(delta)
	_update_readout()
	lane.queue_redraw()


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
		_shake = 16.0
		sfx.play(Sfx.BLOCK_PERFECT, 0.0, 0.0)
		_show_banner("破 防   伤害 x%.0f" % CHORUS_MULTIPLIER, Color(1.0, 0.85, 0.4), 52)
	elif _section == SongMap.Section.BRIDGE:
		_show_banner("转阶段", Color(0.65, 0.85, 1.0), 36)
	_prev_section = _section


func _expire_events() -> void:
	var now := _now_beat()
	var tol := Judgment.GOOD_MS / 1000.0 / clock.beat_duration()
	for i in _chart.events.size():
		if _consumed.has(i):
			continue
		var e: Dictionary = _chart.events[i]
		if now - float(e["beat"]) <= tol:
			continue
		_consumed[i] = true
		if int(e["role"]) == Chart.Role.BLOCK:
			# 谱面说了算：你手工放了格挡音符，敌人就在那里出招。
			# 副歌只是"伤害翻倍 + 视觉变化"的修饰，不能覆盖手编的谱
			# （自动检测的段落边界不可靠，曾把 70 秒都标成副歌）。
			_take_hit()
		elif int(e["role"]) == Chart.Role.STRIKE:
			_missed += 1
			_combo = 0


func _decay(delta: float) -> void:
	_player_lunge = maxf(0.0, _player_lunge - delta * 6.0)
	_player_flash = maxf(0.0, _player_flash - delta * 4.0)
	_enemy_flash = maxf(0.0, _enemy_flash - delta * 4.0)
	_enemy_recoil = maxf(0.0, _enemy_recoil - delta * 4.5)
	_block_hold = maxf(0.0, _block_hold - delta)
	_slash_life = maxf(0.0, _slash_life - delta * 5.0)
	_white_flash = maxf(0.0, _white_flash - delta * 2.5)
	_shake = maxf(0.0, _shake - delta * 55.0)
	_banner_life = maxf(0.0, _banner_life - delta)
	if _banner_life <= 0.0:
		banner.text = ""

	# 傀儡师抬手：下一个格挡点临近时抬起，是牵丝的预兆
	var up := _upcoming(Chart.Role.BLOCK, _now_beat(), 1.2)
	var want := 0.0
	if up != INF:
		want = clampf(1.0 - (up - _now_beat()) / 1.2, 0.0, 1.0)
	_enemy_raise = lerpf(_enemy_raise, want, delta * 12.0)


## 全世界都在打拍子 —— 即使玩家音感不好，眼睛也能跟上（Hi-Fi Rush 原则）
func _apply_visuals(delta: float) -> void:
	var shake_v := Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake) * 0.5)
	world.position = shake_v

	# 灯笼跟着拍子轻摇
	var pulse := 1.0 - clock.beat_progress()
	var t := Time.get_ticks_msec() * 0.001
	for i in lanterns.get_child_count():
		var l := lanterns.get_child(i) as Sprite2D
		l.rotation = sin(t * 1.1 + i * 2.0) * 0.045 + pulse * 0.02
		l.modulate = Color(1, 1, 1, 0.85 + pulse * 0.15)

	# 玩家：出刀前冲 + 格挡下蹲
	var blocking := _block_hold > 0.0
	player.position = _player_home + Vector2(_player_lunge * 46.0, 0)
	player.rotation = _player_home_rot + _player_lunge * 0.05
	player.scale = Vector2(1.0, 0.96 if blocking else 1.0)
	player.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.4, 0.4), _player_flash)
	player_arm.visible = _player_lunge > 0.05
	player_arm.rotation = lerpf(0.45, -0.15, _player_lunge)

	# 敌人：受击后退是「改变对手动作」，打击感最核心的一环。
	# 破防不做"压扁"（真实立绘上会变成人被压瘪，很怪），
	# 改成**丝线松了、傀儡前倾垂下** —— 更符合提线木偶的设定。
	var broken := _section == SongMap.Section.CHORUS
	_broken = lerpf(_broken, 1.0 if broken else 0.0, delta * 4.0)
	enemy.position = _enemy_home + Vector2(_enemy_recoil * 30.0, _broken * 16.0)
	enemy.rotation = _enemy_home_rot + _broken * 0.13
	enemy.scale = Vector2.ONE
	var tint := Color(1, 1, 1).lerp(Color(1.35, 1.08, 0.72), _broken)
	enemy_body.modulate = tint.lerp(Color(1.5, 1.5, 1.5), _enemy_flash)
	enemy_arm.visible = _enemy_raise > 0.06
	enemy_arm.rotation = lerpf(0.55, 0.0, _enemy_raise)
	enemy_arm.modulate = Color(1, 1, 1, clampf(_enemy_raise * 1.4, 0.0, 1.0))

	slash.visible = _slash_life > 0.02
	if slash.visible:
		slash.modulate = Color(1, 1, 1, _slash_life)
		slash.scale = Vector2(0.28 + (1.0 - _slash_life) * 0.10, 0.28)


# ---------------------------------------------------------------- 输入

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey

	if key.keycode == KEY_F1:
		_debug = not _debug
		if _debug:
			clock.stop()
		else:
			player_arm.visible = false
			enemy_arm.visible = false
			slash.visible = false
			_slash_life = 0.0
			_player_home = player.position
			_enemy_home = enemy.position
			_start_fight()
		return

	if _debug:
		_debug_input(key)
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
		KEY_M:            _mark_chorus()
		KEY_ESCAPE: get_tree().quit()


func _attack() -> void:
	if _hitstop_left > 0.0:
		return
	_player_lunge = 1.0
	var now := _now_beat()
	var idx := _nearest(Chart.Role.STRIKE, now)
	_last_offset_ms = 999.0
	if idx >= 0:
		_last_offset_ms = (now - float(_chart.events[idx]["beat"])) * clock.beat_duration() * 1000.0
	var g := Judgment.grade(_last_offset_ms) if idx >= 0 else Judgment.Grade.WHIFF
	var in_chorus := _section == SongMap.Section.CHORUS
	var mult := CHORUS_MULTIPLIER if in_chorus else 1.0

	if g == Judgment.Grade.WHIFF:
		_whiff += 1
		_combo = 0
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
			_land_hit(int(120 * mult), Judgment.HITSTOP_FINISH, 30.0)
			_show_banner("终 结 斩", Color(1.0, 0.95, 0.6), 64)
		else:
			# 副歌本身已是 x2 的奖励窗口，不再攒气 —— 否则终结斩会在连击途中
			# 频繁触发，变成打断而不是奖励（实测问题）。
			if not in_chorus:
				_qi = mini(QI_MAX, _qi + 1)
			sfx.play(Sfx.HIT_HEAVY, -1.0, 0.05)
			_land_hit(int(30 * mult), Judgment.HITSTOP_HEAVY, 13.0)
			_show_banner("完美  x%d" % _combo, Judgment.grade_color(g), 36)
	else:
		_good += 1
		sfx.play(Sfx.HIT_LIGHT, -3.0, 0.07)
		_land_hit(int(12 * mult), Judgment.HITSTOP_LIGHT, 6.0)
		_show_banner("命中  x%d" % _combo, Judgment.grade_color(g), 30)


func _land_hit(damage: int, hitstop_fraction: float, shake: float) -> void:
	_enemy_hp = maxi(0, _enemy_hp - damage)
	_enemy_flash = 1.0
	_enemy_recoil = 1.0
	_shake = shake
	_slash_life = 1.0
	slash.position = enemy.position + Vector2(-40, -60)
	slash.rotation = randf_range(-0.35, 0.35)
	_hitstop_left = Judgment.hitstop_seconds(clock.beat_duration(), hitstop_fraction)


func _block() -> void:
	if _hitstop_left > 0.0:
		return
	_block_hold = 0.18
	var now := _now_beat()
	var idx := _nearest(Chart.Role.BLOCK, now)
	if idx < 0:
		return
	var diff_ms: float = (now - float(_chart.events[idx]["beat"])) * clock.beat_duration() * 1000.0
	if absf(diff_ms) > Judgment.GOOD_MS:
		return

	_consumed[idx] = true
	_blocked += 1
	var d := clock.beat_duration()
	if Judgment.grade(diff_ms) == Judgment.Grade.PERFECT:
		_qi = mini(QI_MAX, _qi + 1)
		_shake = 11.0
		sfx.play(Sfx.BLOCK_PERFECT, 0.0, 0.03)
		_hitstop_left = Judgment.hitstop_seconds(d, Judgment.HITSTOP_HEAVY)
		_show_banner("完美格挡", Color(0.6, 1.0, 0.85), 36)
	else:
		# 反应了但没踩准：挡住了，不扣血，只是被推开、没有反击机会。
		_qi = mini(QI_MAX, _qi + 1)
		_shake = 5.0
		sfx.play(Sfx.BLOCK, -2.0, 0.05)
		_hitstop_left = Judgment.hitstop_seconds(d, Judgment.HITSTOP_LIGHT)
		_show_banner("格挡", Color(0.7, 0.85, 0.95), 30)


func _take_hit() -> void:
	_player_hp = maxi(0, _player_hp - 5)
	_hit_taken += 1
	_combo = 0
	_qi = maxi(0, _qi - 2)
	_player_flash = 1.0
	_shake = 9.0
	sfx.play(Sfx.HURT, -2.0, 0.06)
	_show_banner("受击", Color(1.0, 0.4, 0.4), 32)


func _show_banner(text: String, color: Color, size: int) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner.add_theme_font_size_override("font_size", size)
	_banner_life = 0.5


func _update_readout() -> void:
	var total := _perfect + _good + _whiff
	var acc := 0.0 if total == 0 else float(_perfect) * 100.0 / total
	var t := clock.song_time()
	readout.text = "连段 %d (最高 %d)   完美 %d  命中 %d  空挥 %d  漏 %d   完美率 %.0f%%   " \
		% [_combo, _best_combo, _perfect, _good, _whiff, _missed, acc] \
		+ "格挡 %d  受击 %d  终结斩 %d  气 %d/%d   %d:%02d   校准 %+.0f ms   空格=斩 J=格挡 R=重来" \
		% [_blocked, _hit_taken, _finishers, _qi, QI_MAX,
		   int(t) / 60, int(t) % 60, clock.offset_ms]
	section_label.text = _map.label(_section)
	if _section == SongMap.Section.CHORUS:
		section_label.text += "   伤害 x%.0f" % CHORUS_MULTIPLIER


# ---------------------------------------------------------------- 段落覆盖
# 自动检测的段落边界不可靠（曾把 70 秒整段错标成副歌），
# 所以给一个键，在游戏里听到副歌进来的那一刻直接标记，立即生效并存盘。

func _mark_chorus() -> void:
	var t := clock.song_time()
	var f := FileAccess.open(SECTIONS_PATH, FileAccess.WRITE)
	if f == null:
		_tune_msg = "段落存盘失败"
		_tune_msg_life = 2.0
		return
	f.store_string(JSON.stringify({"chorus_start_sec": snappedf(t, 0.01)}, "  "))
	f.close()
	_rebuild_sections(t)
	_tune_msg = "副歌起点已标记 %d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]
	_tune_msg_life = 3.0
	_show_banner("副歌起点 %d:%05.2f" % [int(t) / 60, fmod(t, 60.0)],
		Color(0.7, 1.0, 0.8), 34)


func _load_sections_override() -> void:
	if not FileAccess.file_exists(SECTIONS_PATH):
		return
	var f := FileAccess.open(SECTIONS_PATH, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) == TYPE_DICTIONARY and d.has("chorus_start_sec"):
		_rebuild_sections(float(d["chorus_start_sec"]))


## 段落极简化：前奏 → 主歌 → 副歌。战斗只覆盖谱面区间，不需要更细。
func _rebuild_sections(chorus_start: float) -> void:
	var first_note_sec := _map.first_beat_sec
	if not _chart.events.is_empty():
		first_note_sec = _map.first_beat_sec 			+ float(_chart.events[0]["beat"]) * (60.0 / _map.bpm)
	_map.sections = [
		{"section": SongMap.Section.INTRO, "start": 0.0, "end": first_note_sec},
		{"section": SongMap.Section.VERSE, "start": first_note_sec, "end": chorus_start},
		{"section": SongMap.Section.CHORUS, "start": chorus_start, "end": _map.duration_sec},
	]
	_prev_section = -1


# ---------------------------------------------------------------- 调试台
# F1 开关。摆好之后按 S 存盘，下次启动自动套用 —— 不用手改场景文件。

func _tune_node() -> Node2D:
	return get_node_or_null(TUNE_TARGETS[_tune_idx]) as Node2D


func _debug_input(key: InputEventKey) -> void:
	var n := _tune_node()
	if n == null:
		return
	var step := 10.0 if key.shift_pressed else 1.0
	match key.keycode:
		KEY_TAB:
			var dir := -1 if key.shift_pressed else 1
			_tune_idx = posmod(_tune_idx + dir, TUNE_TARGETS.size())
		KEY_LEFT:  n.position.x -= step
		KEY_RIGHT: n.position.x += step
		KEY_UP:    n.position.y -= step
		KEY_DOWN:  n.position.y += step
		KEY_Q:     n.scale *= (0.99 if key.shift_pressed else 0.999)
		KEY_E:     n.scale *= (1.01 if key.shift_pressed else 1.001)
		KEY_Z:     n.rotation -= deg_to_rad(1.0 if key.shift_pressed else 0.2)
		KEY_C:     n.rotation += deg_to_rad(1.0 if key.shift_pressed else 0.2)
		KEY_S:     _save_tuning()
		KEY_ESCAPE: get_tree().quit()


func _load_tuning() -> void:
	if not FileAccess.file_exists(TUNING_PATH):
		return
	var f := FileAccess.open(TUNING_PATH, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return
	for path in d.keys():
		var n := get_node_or_null(String(path)) as Node2D
		if n == null:
			continue
		var v: Dictionary = d[path]
		if v.has("pos"):
			n.position = Vector2(float(v["pos"][0]), float(v["pos"][1]))
		if v.has("scale"):
			n.scale = Vector2(float(v["scale"][0]), float(v["scale"][1]))
		if v.has("rot"):
			n.rotation = float(v["rot"])


func _save_tuning() -> void:
	var out := {}
	for path in TUNE_TARGETS:
		var n := get_node_or_null(String(path)) as Node2D
		if n == null:
			continue
		out[path] = {
			"pos": [snappedf(n.position.x, 0.1), snappedf(n.position.y, 0.1)],
			"scale": [snappedf(n.scale.x, 0.0001), snappedf(n.scale.y, 0.0001)],
			"rot": snappedf(n.rotation, 0.0001),
		}
	var f := FileAccess.open(TUNING_PATH, FileAccess.WRITE)
	if f == null:
		_tune_msg = "存盘失败"
		_tune_msg_life = 2.0
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	_tune_msg = "已存盘 → tuning.json"
	_tune_msg_life = 2.0


func _draw_debug(vp: Vector2) -> void:
	var font := ThemeDB.fallback_font
	lane.draw_rect(Rect2(Vector2(0, vp.y - 128), Vector2(vp.x, 128)),
		Color(0, 0, 0, 0.82), true)
	var n := _tune_node()
	var info := "（节点不存在）"
	if n != null:
		info = "pos (%.0f, %.0f)    scale %.4f    rot %.1f°" \
			% [n.position.x, n.position.y, n.scale.x, rad_to_deg(n.rotation)]
	var lines := [
		"调试台  [%d/%d]  %s" % [_tune_idx + 1, TUNE_TARGETS.size(), TUNE_TARGETS[_tune_idx]],
		info,
		"Tab 换部件(Shift 反向)   方向键 移动(Shift ×10)   Q/E 缩放   Z/C 旋转   S 存盘   F1 退出调试",
	]
	var y := vp.y - 104
	for i in lines.size():
		var col := Color(1.0, 0.9, 0.5) if i == 0 else Color(0.88, 0.88, 0.92)
		lane.draw_string(font, Vector2(30, y), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18 if i < 2 else 15, col)
		y += 30
	if _tune_msg_life > 0.0:
		lane.draw_string(font, Vector2(vp.x - 300, vp.y - 104), _tune_msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 1.0, 0.7))
	# 十字准星，帮助对位
	if n != null:
		var g := n.get_global_transform_with_canvas().origin
		lane.draw_line(Vector2(g.x - 26, g.y), Vector2(g.x + 26, g.y), Color(1, 0.9, 0.3, 0.9), 1.5)
		lane.draw_line(Vector2(g.x, g.y - 26), Vector2(g.x, g.y + 26), Color(1, 0.9, 0.3, 0.9), 1.5)


# ---------------------------------------------------------------- 轨道
# 音符是挂在丝线上的铃铛（"盘铃声清脆"），轨道读作戏台上方的提线架。

func _draw_lane() -> void:
	var vp := lane.size
	var cx := vp.x * 0.5
	var now := _now_beat()
	var pulse := 1.0 - clock.beat_progress()      # 每拍脉动，全画面一起打拍子

	# 提线架横梁
	lane.draw_line(Vector2(0, LANE_Y), Vector2(vp.x, LANE_Y),
		Color(COL_STRING.r, COL_STRING.g, COL_STRING.b, 0.30), 2.0)

	# 判定区：一段被照亮的横梁，跟着拍子呼吸
	var glow := 0.10 + pulse * 0.16
	lane.draw_rect(Rect2(Vector2(cx - 46, LANE_Y - 6), Vector2(92, BELL_DROP + 40)),
		Color(1.0, 0.94, 0.78, glow * 0.35), true)

	for i in _chart.events.size():
		var e: Dictionary = _chart.events[i]
		var b: float = e["beat"]
		var d: float = b - now
		if d < -0.9 or d > LANE_LOOKAHEAD_BEATS:
			continue
		var is_strike := int(e["role"]) == Chart.Role.STRIKE
		var nx := cx + d * LANE_PX_PER_BEAT
		var col := COL_STRIKE if is_strike else COL_BLOCK

		var a := 1.0
		if _consumed.has(i):
			a = 0.12
		elif d < 0.0:
			a = 0.4

		# 越近越大 —— 这是"要到了"的主要提示
		var near := clampf(1.0 - absf(d) / LANE_LOOKAHEAD_BEATS, 0.0, 1.0)
		var grow := 0.62 + near * near * 0.55
		# 铃随丝线轻摆
		var sway := sin(Time.get_ticks_msec() * 0.004 + i * 1.7) * 4.0 * (1.0 - near)

		# 丝线
		lane.draw_line(Vector2(nx + sway * 0.4, LANE_Y),
			Vector2(nx + sway, LANE_Y + BELL_DROP - 14.0),
			Color(COL_STRING.r, COL_STRING.g, COL_STRING.b, a * 0.7), 1.6)

		var bp := Vector2(nx + sway, LANE_Y + BELL_DROP)

		# 进入判定窗口时套一圈光环
		if not _consumed.has(i) and absf(d) < 0.34:
			var ring := clampf(1.0 - absf(d) / 0.34, 0.0, 1.0)
			lane.draw_arc(bp, 26.0 + (1.0 - ring) * 16.0, 0, TAU, 28,
				Color(col.r, col.g, col.b, ring * 0.85), 2.0 + ring * 2.0)

		# 铃铛本体（贴图上两种铃很接近，靠强着色区分：斩=青，格挡=朱）
		var tex := NOTE_STRIKE if is_strike else NOTE_BLOCK
		var sz := Vector2(tex.get_width(), tex.get_height()) * BELL_SCALE * grow
		lane.draw_texture_rect(tex, Rect2(bp - sz * 0.5, sz), false,
			Color(col.r, col.g, col.b, a))

	# 判定线
	lane.draw_line(Vector2(cx, LANE_Y - 22), Vector2(cx, LANE_Y + BELL_DROP + 34),
		Color(1, 0.97, 0.9, 0.55 + pulse * 0.45), 3.0)

	_draw_bars(vp)

	if _white_flash > 0.0:
		lane.draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 1, _white_flash * 0.45), true)
	if _tune_msg_life > 0.0 and not _debug:
		lane.draw_string(ThemeDB.fallback_font, Vector2(40, 40), _tune_msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.6, 1.0, 0.75))
	if _debug:
		_draw_debug(vp)
		return
	if _ending:
		_draw_ending(vp)


func _draw_bars(vp: Vector2) -> void:
	_bar(Vector2(40, vp.y - 96), Vector2(280, 12), float(_player_hp) / 100.0, COL_STRIKE)
	_bar(Vector2(40, vp.y - 78), Vector2(280, 7), float(_qi) / QI_MAX, Color(1.0, 0.9, 0.45))
	_bar(Vector2(vp.x - 320, vp.y - 96), Vector2(280, 12),
		float(_enemy_hp) / _enemy_hp_max, COL_BLOCK)


func _bar(pos: Vector2, size: Vector2, ratio: float, color: Color) -> void:
	lane.draw_rect(Rect2(pos, size), Color(0, 0, 0, 0.45), true)
	lane.draw_rect(Rect2(pos, Vector2(size.x * clampf(ratio, 0.0, 1.0), size.y)), color, true)


func _draw_ending(vp: Vector2) -> void:
	var fade := clampf(_ending_timer / ENDING_FADE_SEC, 0.0, 1.0)
	lane.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.02, 0.04, ease(fade, 1.6) * 0.94), true)
	if fade < 0.35:
		return
	var a := clampf((fade - 0.35) / 0.65, 0.0, 1.0)
	var font := ThemeDB.fallback_font
	var title := "余音未散"
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 54).x
	lane.draw_string(font, Vector2(vp.x * 0.5 - tw * 0.5, vp.y * 0.34), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color(1.0, 0.92, 0.75, a))

	var total := _perfect + _good + _whiff
	var acc := 0.0 if total == 0 else float(_perfect) * 100.0 / total
	var lines := [
		"完美率 %.0f%%    最高连段 %d" % [acc, _best_combo],
		"完美 %d    命中 %d    格挡 %d    终结斩 %d" % [_perfect, _good, _blocked, _finishers],
	]
	var y := vp.y * 0.46
	for line in lines:
		var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		lane.draw_string(font, Vector2(vp.x * 0.5 - w * 0.5, y), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.88, 0.9, a * 0.9))
		y += 34.0

	if fade >= 1.0:
		var ha := clampf((_ending_timer - ENDING_FADE_SEC) * 1.5, 0.0, 1.0) * a
		var hint := "R / 空格 重新开始      ESC 退出"
		var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		lane.draw_string(font, Vector2(vp.x * 0.5 - hw * 0.5, y + 36.0), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.72, 0.7, 0.72, ha))
