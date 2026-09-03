class_name Sfx
extends Node

## 音效播放池。
##
## 用池是因为连段时音效会重叠 —— 单个 AudioStreamPlayer 会把前一声切掉，
## 打十六分音符连打时听起来会"吃音"。
##
## 音量优先级来自调研结论：格挡音 > 击中音 > 攻击音 > 喊话。
## 具体数值烘焙在 tools/make_sfx.py 的 gain 里，这里再叠一层 dB 微调。

const POOL_SIZE := 12

const SWING := preload("res://audio/sfx/swing.wav")
const HIT_LIGHT := preload("res://audio/sfx/hit_light.wav")
const HIT_HEAVY := preload("res://audio/sfx/hit_heavy.wav")
const HIT_FINISHER := preload("res://audio/sfx/hit_finisher.wav")
const BLOCK := preload("res://audio/sfx/block.wav")
const BLOCK_PERFECT := preload("res://audio/sfx/block_perfect.wav")
const HURT := preload("res://audio/sfx/hurt.wav")
const METRO_HI := preload("res://audio/sfx/metro_hi.wav")   # 小节第一拍
const METRO_LO := preload("res://audio/sfx/metro_lo.wav")   # 其余拍

var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


func play(stream: AudioStream, volume_db: float = 0.0,
		pitch_variation: float = 0.0) -> void:
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	# 轻微随机音高，避免连打时听起来像复读机
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()
