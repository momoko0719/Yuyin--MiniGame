class_name Chart
extends RefCounted

## 战斗谱面 —— 人工敲出来的攻防节奏。
##
## 为什么需要它：
## 纯靠"敌人每 N 拍出招一次"虽然在拍网格上精确，但**跟音乐的乐句毫无关系**。
## 歌曲有自己的重音、乐句起落和钩子（比如《霍元甲》副歌那句"霍 霍 霍霍"），
## 机械周期一概不知道，玩起来会有种说不出的别扭 ——
## **明明每一下都在拍上，却感觉不对**，因为音乐在说 A，敌人在说 B。
##
## 所以谱面由人跟着音乐敲出来，再吸附到网格上。
## 这仍然符合「拍子网格来自歌曲」：所有事件都锁在网格点上，只是
## **哪些网格点有事件**由人的乐感决定，而不是由取模运算决定。

enum Role { STRIKE, BLOCK }

const ROLE_NAME := {Role.STRIKE: "strike", Role.BLOCK: "block"}
const ROLE_FROM_NAME := {"strike": Role.STRIKE, "block": Role.BLOCK}

var song: String = ""
var bpm: float = 120.0
var first_beat_sec: float = 0.0
var quantize: int = 4                 # 每拍细分数（4 = 十六分音符）
var events: Array = []                # [{beat: float, role: Role}]，按 beat 升序


static func load_from(path: String) -> Chart:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return null

	var c := Chart.new()
	c.song = data.get("song", "")
	c.bpm = float(data.get("bpm", 120.0))
	c.first_beat_sec = float(data.get("first_beat_sec", 0.0))
	c.quantize = int(data.get("quantize", 4))
	for e in data.get("events", []):
		var role_name: String = e.get("role", "strike")
		c.events.append({
			"beat": float(e.get("beat", 0.0)),
			"role": ROLE_FROM_NAME.get(role_name, Role.STRIKE),
		})
	c.sort()
	return c


func save_to(path: String) -> bool:
	sort()
	var out := {
		"song": song,
		"bpm": bpm,
		"first_beat_sec": first_beat_sec,
		"quantize": quantize,
		"event_count": events.size(),
		"events": [],
	}
	for e in events:
		var role: int = e["role"]
		out["events"].append({
			"beat": snappedf(float(e["beat"]), 0.0001),
			"role": ROLE_NAME[role],
		})
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Chart: 写不了 %s" % path)
		return false
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	return true


func sort() -> void:
	events.sort_custom(func(a, b): return float(a["beat"]) < float(b["beat"]))


## 把一个拍位吸附到最近的细分网格点
func snap(beat: float) -> float:
	return roundf(beat * quantize) / float(quantize)


func add(beat: float, role: Role) -> void:
	var b := snap(beat)
	# 同一个网格点上不重复记录同一角色
	for e in events:
		if is_equal_approx(float(e["beat"]), b) and int(e["role"]) == role:
			return
	events.append({"beat": b, "role": role})


func remove_last() -> void:
	if events.is_empty():
		return
	sort()
	events.remove_at(events.size() - 1)


func count(role: Role) -> int:
	var n := 0
	for e in events:
		if int(e["role"]) == role:
			n += 1
	return n


## 返回 beat 之后的第一个指定角色事件的拍位，没有则返回 INF
func next_of(role: Role, after_beat: float) -> float:
	for e in events:
		var b: float = e["beat"]
		if b > after_beat and int(e["role"]) == role:
			return b
	return INF


## 这个拍位上有没有指定角色的事件（容差半个细分）
func has_at(beat: float, role: Role) -> bool:
	var tol := 0.5 / float(quantize)
	for e in events:
		if int(e["role"]) != role:
			continue
		if absf(float(e["beat"]) - beat) <= tol:
			return true
	return false
