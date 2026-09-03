class_name Judgment
extends RefCounted

## 判定与顿帧规则。
##
## 判定窗口是从实测推导的，不是抄标准音游：
## 开发机实测人工敲击波动（标准差）±29.5ms，而标准音游 Perfect 窗口只有 ±16~30ms
## —— 按那个标准，开发者本人都打不准。
## 人类 + 键盘 + 系统的固有抖动消不掉，所以窗口必须开宽。
## 对应支柱一：节奏决定你打得多狠，不决定你死不死。

enum Grade { PERFECT, GOOD, WHIFF }

const PERFECT_MS := 60.0
const GOOD_MS := 120.0

## 顿帧时长用「音符时值」定义，不用秒。
## 这样顿帧结束的那一刻正好落在一个音符位置上，
## 那个"凝滞"既是打击感也是节奏本身；并且自动适配任何 BPM。
const HITSTOP_LIGHT := 1.0 / 16.0   # 轻击
const HITSTOP_HEAVY := 1.0 / 8.0    # 重击 / 完美格挡
const HITSTOP_BREAK := 1.0 / 4.0    # 破防
const HITSTOP_FINISH := 3.0 / 8.0   # 终结技（稀有，所以重，但比半拍略短，减少打断感）


static func grade(offset_ms: float) -> Grade:
	var a := absf(offset_ms)
	if a <= PERFECT_MS:
		return Grade.PERFECT
	if a <= GOOD_MS:
		return Grade.GOOD
	return Grade.WHIFF


static func grade_name(g: Grade) -> String:
	match g:
		Grade.PERFECT: return "完美"
		Grade.GOOD: return "命中"
		_: return "空挥"


static func grade_color(g: Grade) -> Color:
	match g:
		Grade.PERFECT: return Color(1.0, 0.85, 0.35)
		Grade.GOOD: return Color(0.6, 0.85, 1.0)
		_: return Color(0.55, 0.55, 0.6)


## 顿帧秒数 = 拍长 × 音符时值
static func hitstop_seconds(beat_duration: float, fraction: float) -> float:
	return beat_duration * fraction
