extends Node2D

## 战斗手感验证台 v2
##
## 核心律动（v1 缺的就是这个）：
##   **每一拍你都要做点什么。敌人出招那一拍格挡，其余的拍斩。**
## 武器决定你在"自己的拍"上出几刀 —— 单刀每拍一刀，双刀每拍四刀。
## 这就是支柱四「武器 = 音符密度和落点」。
##
## 全是色块。打击感来自顿帧、震屏、受击反馈，不来自画面好看。

const PLAYER_X_RATIO := 0.30
const ENEMY_X_RATIO := 0.70
const GROUND_Y_RATIO := 0.68
const BOX_W := 90.0
const BOX_H := 190.0
const QI_MAX := 8

const COL_BG := Color(0.09, 0.09, 0.12)
const COL_PLAYER := Color(0.55, 0.82, 1.0)
const COL_ENEMY := Color(0.95, 0.42, 0.42)
const COL_TELEGRAPH := Color(1.0, 0.75, 0.25)
const COL_QI := Color(1.0, 0.9, 0.4)
const COL_STRIKE_BEAT := Color(0.55, 0.82, 1.0)
const COL_BLOCK_BEAT := Color(0.95, 0.42, 0.42)

@onready var music: AudioStreamPlayer = $Music
@onready var clock: BeatClock = $BeatClock
@onready var readout: Label = $UI/Readout
@onready var banner: Label = $UI/Banner
@onready var sfx: Sfx = $Sfx

var _click_120: AudioStream = preload("res://audio/click_120.wav")
var _click_100: AudioStream = preload("res://audio/click_100.wav")

# --- 可运行时调整的参数 ---
var _attack_period: int = 4          # 敌人几拍打一次
var _first_attack_beat: int = 4

# --- 顿帧 / 震屏 ---
var _hitstop_left: float = 0.0
var _shake_amount: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _white_flash: float = 0.0        # 终结斩全屏白闪

# --- 玩家 ---
var _player_hp: int = 100
var _player_lunge: float = 0.0
var _player_flash: float = 0.0
var _block_hold: float = 0.0
var _qi: int = 0

# --- 敌人 ---
var _enemy_hp: int = 600
var _enemy_flash: float = 0.0
var _enemy_recoil: float = 0.0
var _next_attack_beat: int = 4
var _resolved_attack_beat: int = -999

# --- 统计 ---
var _combo: int = 0
var _best_combo: int = 0
var _perfect: int = 0
var _good: int = 0
var _whiff: int = 0
var _blocked: int = 0
var _hit_taken: int = 0
var _finishers: int = 0
var _last_offset_ms: float = 0.0
var _banner_life: float = 0.0


func _ready() -> void:
	clock.setup(music)
	_start_fight()


func _start_fight() -> void:
	_player_hp = 100
	_enemy_hp = 600
	_combo = 0
	_best_combo = 0
	_perfect = 0
	_good = 0
	_whiff = 0
	_blocked = 0
	_hit_taken = 0
	_finishers = 0
	_qi = 0
	_next_attack_beat = _first_attack_beat
	_resolved_attack_beat = -999
	_hitstop_left = 0.0
	banner.text = ""
	clock.stop()
	clock.start()


# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	# 顿帧冻结画面与逻辑，但**绝不冻结音乐**。
	# 时钟读的是音频播放位置，所以歌曲时间照常推进，解冻后画面跳到正确位置。
	if _hitstop_left > 0.0:
		_hitstop_left -= delta
		_white_flash = maxf(0.0, _white_flash - delta * 2.5)
		_update_readout()
		queue_redraw()
		return

	_resolve_enemy_attack()
	_decay(delta)
	_update_shake(delta)
	_update_readout()
	queue_redraw()


func _decay(delta: float) -> void:
	_player_lunge = maxf(0.0, _player_lunge - delta * 7.0)
	_player_flash = maxf(0.0, _player_flash - delta * 5.0)
	_enemy_flash = maxf(0.0, _enemy_flash - delta * 5.0)
	_enemy_recoil = maxf(0.0, _enemy_recoil - delta * 5.0)
	_block_hold = maxf(0.0, _block_hold - delta)
	_white_flash = maxf(0.0, _white_flash - delta * 2.5)
	_banner_life = maxf(0.0, _banner_life - delta)
	if _banner_life <= 0.0:
		banner.text = ""


func _update_shake(delta: float) -> void:
	# 只做平移（相当于 3D 的 Pitch/Yaw），不做旋转（Roll 会让人晕）。
	_shake_amount = maxf(0.0, _shake_amount - delta * 60.0)
	if _shake_amount > 0.1:
		_shake_offset = Vector2(
			randf_range(-_shake_amount, _shake_amount),
			randf_range(-_shake_amount, _shake_amount) * 0.6)
	else:
		_shake_offset = Vector2.ZERO


# ---------------------------------------------------------------- 律动

## 这一拍是不是敌人的出招拍（该格挡）
func _is_block_beat(beat: int) -> bool:
	if beat < _first_attack_beat:
		return false
	return (beat - _first_attack_beat) % _attack_period == 0


# ---------------------------------------------------------------- 敌人

## 起手预兆提前一拍开始 —— 玩家既能看见（预兆条）也能听见（拍子）。
func _telegraph_progress() -> float:
	var t := clock.song_time()
	var d := clock.beat_duration()
	var land := _next_attack_beat * d
	var start := land - d
	if t < start or t > land:
		return 0.0
	return (t - start) / d


func _resolve_enemy_attack() -> void:
	var d := clock.beat_duration()
	var land := _next_attack_beat * d
	if clock.song_time() > land + Judgment.GOOD_MS / 1000.0:
		if _resolved_attack_beat != _next_attack_beat:
			_resolved_attack_beat = _next_attack_beat
			_take_hit()
		_next_attack_beat += _attack_period


func _take_hit() -> void:
	_player_hp = maxi(0, _player_hp - 8)
	_hit_taken += 1
	_combo = 0
	_qi = maxi(0, _qi - 2)
	_player_flash = 1.0
	_shake_amount = 9.0
	sfx.play(Sfx.HURT, -2.0, 0.06)
	_show_banner("受击", Color(1.0, 0.4, 0.4), 34)


# ---------------------------------------------------------------- 输入

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE: _attack()
		KEY_J:     _block()
		KEY_R:     _start_fight()
		KEY_1:     _set_bpm(100.0, _click_100)
		KEY_2:     _set_bpm(120.0, _click_120)
		KEY_3:     _set_period(4)
		KEY_4:     _set_period(2)
		KEY_ESCAPE: get_tree().quit()


func _set_bpm(bpm: float, stream: AudioStream) -> void:
	clock.bpm = bpm
	music.stream = stream
	_start_fight()


func _set_period(p: int) -> void:
	_attack_period = p
	_start_fight()


func _attack() -> void:
	if _hitstop_left > 0.0:
		return
	_last_offset_ms = clock.offset_to_nearest_beat_ms()
	var g := Judgment.grade(_last_offset_ms)
	_player_lunge = 1.0

	match g:
		Judgment.Grade.PERFECT:
			var finisher := _qi >= QI_MAX
			_combo += 1
			_best_combo = maxi(_best_combo, _combo)
			_perfect += 1
			if finisher:
				_qi = 0
				_finishers += 1
				_white_flash = 1.0
				sfx.play(Sfx.HIT_FINISHER, 0.0, 0.02)
				_land_hit(90, Judgment.HITSTOP_FINISH, 34.0)
				_show_banner("终 结 斩", Color(1.0, 0.95, 0.6), 72)
			else:
				_qi = mini(QI_MAX, _qi + 1)
				sfx.play(Sfx.HIT_HEAVY, -1.0, 0.05)
				_land_hit(24, Judgment.HITSTOP_HEAVY, 14.0)
				_show_banner("完美  x%d" % _combo, Judgment.grade_color(g), 40)
		Judgment.Grade.GOOD:
			_combo += 1
			_best_combo = maxi(_best_combo, _combo)
			_good += 1
			sfx.play(Sfx.HIT_LIGHT, -3.0, 0.07)
			_land_hit(10, Judgment.HITSTOP_LIGHT, 6.0)
			_show_banner("命中  x%d" % _combo, Judgment.grade_color(g), 34)
		_:
			_whiff += 1
			_combo = 0
			sfx.play(Sfx.SWING, -8.0, 0.10)   # 挥空只有破空声，音量最低
			# 空挥不扣血、不惩罚，只是没打中 —— 支柱一。
			_show_banner("空挥", Judgment.grade_color(g), 28)


func _land_hit(damage: int, hitstop_fraction: float, shake: float) -> void:
	_enemy_hp = maxi(0, _enemy_hp - damage)
	_enemy_flash = 1.0
	_enemy_recoil = 1.0          # 「改变对手动作」= 打击感最核心的一环
	_shake_amount = shake
	_hitstop_left = Judgment.hitstop_seconds(clock.beat_duration(), hitstop_fraction)


func _block() -> void:
	if _hitstop_left > 0.0:
		return
	_block_hold = 0.18
	var d := clock.beat_duration()
	var land := _next_attack_beat * d
	var diff_ms := (clock.song_time() - land) * 1000.0

	if absf(diff_ms) > Judgment.GOOD_MS:
		return   # 空格挡，无事发生（不惩罚）

	_resolved_attack_beat = _next_attack_beat
	_blocked += 1
	if Judgment.grade(diff_ms) == Judgment.Grade.PERFECT:
		_qi = mini(QI_MAX, _qi + 2)
		_shake_amount = 12.0
		sfx.play(Sfx.BLOCK_PERFECT, 0.0, 0.03)   # 格挡音量最大
		_hitstop_left = Judgment.hitstop_seconds(d, Judgment.HITSTOP_HEAVY)
		_show_banner("完美格挡", Color(0.6, 1.0, 0.85), 40)
	else:
		# 反应了但没踩准：**挡住了，不扣血**，只是被推开、没有反击机会。
		_qi = mini(QI_MAX, _qi + 1)
		_shake_amount = 5.0
		sfx.play(Sfx.BLOCK, -2.0, 0.05)
		_hitstop_left = Judgment.hitstop_seconds(d, Judgment.HITSTOP_LIGHT)
		_show_banner("格挡", Color(0.7, 0.85, 0.95), 32)
	_next_attack_beat += _attack_period


func _show_banner(text: String, color: Color, size: int) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner.add_theme_font_size_override("font_size", size)
	_banner_life = 0.6


# ---------------------------------------------------------------- 显示

func _update_readout() -> void:
	var total := _perfect + _good + _whiff
	var acc := 0.0 if total == 0 else float(_perfect) * 100.0 / total
	readout.text = "\n".join([
		"BPM %.0f   一拍 %.0f ms   敌人每 %d 拍出招   判定 完美±%.0f / 命中±%.0f ms"
			% [clock.bpm, clock.beat_duration() * 1000.0, _attack_period,
			   Judgment.PERFECT_MS, Judgment.GOOD_MS],
		"",
		"连段 %d (最高 %d)   完美 %d   命中 %d   空挥 %d   完美率 %.0f%%"
			% [_combo, _best_combo, _perfect, _good, _whiff, acc],
		"格挡 %d   受击 %d   终结斩 %d   最近偏移 %+.1f ms   FPS %d"
			% [_blocked, _hit_taken, _finishers, _last_offset_ms,
			   Engine.get_frames_per_second()],
		"",
		"空格=斩   J=格挡   R=重来   1/2=BPM 100/120   3/4=敌人 4拍/2拍   ESC=退出",
	])


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), COL_BG, true)

	var o := _shake_offset
	var ground := vp.y * GROUND_Y_RATIO
	draw_line(Vector2(0, ground) + o, Vector2(vp.x, ground) + o,
		Color(1, 1, 1, 0.10), 2.0)

	_draw_beat_strip(vp, o)
	_draw_player(vp, ground, o)
	_draw_enemy(vp, ground, o)
	_draw_bars(vp)

	# 终结斩全屏白闪 —— 让它绝不可能被当成"卡了一下"
	if _white_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 1, _white_flash * 0.55), true)


## 节拍条：标出每一拍该做什么。
## 红 = 敌人出招拍（格挡）  蓝 = 你的拍（斩）
## 全世界都在打拍子 —— 即使玩家音感不好，眼睛也能跟上。（Hi-Fi Rush 原则）
func _draw_beat_strip(vp: Vector2, o: Vector2) -> void:
	var n := clock.beats_per_bar
	var beat := clock.current_beat()
	var prog := clock.beat_progress()
	var bar_start := beat - posmod(beat, n)
	var spacing := 58.0
	var start_x := vp.x * 0.5 - spacing * (n - 1) * 0.5

	for i in n:
		var b := bar_start + i
		var p := Vector2(start_x + spacing * i, vp.y * 0.14) + o
		var is_now := b == beat
		var pulse := (1.0 - prog) if is_now else 0.0
		var base := COL_BLOCK_BEAT if _is_block_beat(b) else COL_STRIKE_BEAT
		var c := Color(base.r, base.g, base.b, 0.22 + pulse * 0.78)
		draw_circle(p, 10.0 + pulse * 13.0, c)
		if is_now:
			draw_arc(p, 26.0, 0, TAU, 32, Color(1, 1, 1, 0.35), 2.0)


func _draw_player(vp: Vector2, ground: float, o: Vector2) -> void:
	var x := vp.x * PLAYER_X_RATIO + _player_lunge * 70.0
	var blocking := _block_hold > 0.0
	var w := BOX_W * (1.35 if blocking else 1.0)
	var h := BOX_H * (0.86 if blocking else 1.0)
	var rect := Rect2(Vector2(x - w * 0.5, ground - h) + o, Vector2(w, h))
	var c := COL_PLAYER
	if _player_flash > 0.0:
		c = c.lerp(Color(1, 0.35, 0.35), _player_flash)
	draw_rect(rect, Color(c.r, c.g, c.b, 0.85), true)
	draw_rect(rect, c.lightened(0.4), false, 2.0)

	# 气满：金色描边脉动，告诉你下一记完美斩会变成终结斩
	if _qi >= QI_MAX:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		draw_rect(rect.grow(6.0 + pulse * 5.0), Color(1.0, 0.9, 0.4, 0.35 + pulse * 0.5),
			false, 4.0)

	if _player_lunge > 0.05:
		var y := ground - h * 0.55
		draw_line(Vector2(x + w * 0.5, y) + o,
			Vector2(x + w * 0.5 + 120.0 * _player_lunge, y) + o,
			Color(1, 1, 1, _player_lunge), 4.0)


func _draw_enemy(vp: Vector2, ground: float, o: Vector2) -> void:
	# 受击后退 = 「改变对手动作」
	var x := vp.x * ENEMY_X_RATIO + _enemy_recoil * 34.0
	var rect := Rect2(Vector2(x - BOX_W * 0.5, ground - BOX_H) + o,
		Vector2(BOX_W, BOX_H))
	var c := COL_ENEMY
	if _enemy_flash > 0.0:
		c = c.lerp(Color.WHITE, _enemy_flash)
	draw_rect(rect, Color(c.r, c.g, c.b, 0.85), true)
	draw_rect(rect, c.lightened(0.4), false, 2.0)

	var tp := _telegraph_progress()
	if tp > 0.0:
		var bar_w := 150.0
		var bx := x - bar_w * 0.5
		var by := ground - BOX_H - 34.0
		draw_rect(Rect2(Vector2(bx, by) + o, Vector2(bar_w, 12.0)),
			Color(1, 1, 1, 0.12), true)
		draw_rect(Rect2(Vector2(bx, by) + o, Vector2(bar_w * tp, 12.0)),
			COL_TELEGRAPH, true)
		var lift := tp * 60.0
		draw_line(Vector2(x - BOX_W * 0.5, ground - BOX_H * 0.6) + o,
			Vector2(x - BOX_W * 0.5 - 40.0, ground - BOX_H * 0.6 - lift) + o,
			COL_TELEGRAPH, 5.0)


func _draw_bars(vp: Vector2) -> void:
	_bar(Vector2(40, vp.y - 74), Vector2(300, 16), float(_player_hp) / 100.0, COL_PLAYER)
	_bar(Vector2(40, vp.y - 48), Vector2(300, 10), float(_qi) / QI_MAX, COL_QI)
	_bar(Vector2(vp.x - 340, vp.y - 74), Vector2(300, 16),
		float(_enemy_hp) / 600.0, COL_ENEMY)


func _bar(pos: Vector2, size: Vector2, ratio: float, color: Color) -> void:
	draw_rect(Rect2(pos, size), Color(1, 1, 1, 0.10), true)
	draw_rect(Rect2(pos, Vector2(size.x * clampf(ratio, 0.0, 1.0), size.y)), color, true)
