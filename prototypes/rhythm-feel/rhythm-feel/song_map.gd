class_name SongMap
extends RefCounted

## 曲目地图 —— 由 tools/analyze_song.py + tools/make_songmap.py 生成。
##
## 设计前提：**拍子网格来自歌曲，谱面内容来自 BOSS。**
## 所以这里只有 BPM、首拍、段落边界，**没有任何音符谱面**。
## 敌人出什么招由 BOSS 行为逻辑决定，只要落在拍网格上就自动踩点。

enum Section { INTRO, VERSE, PRE, CHORUS, BRIDGE, OUTRO }

const SECTION_FROM_STRING := {
	"intro": Section.INTRO,
	"verse": Section.VERSE,
	"pre": Section.PRE,
	"chorus": Section.CHORUS,
	"bridge": Section.BRIDGE,
	"outro": Section.OUTRO,
}

const SECTION_LABEL := {
	Section.INTRO: "前奏 · 对峙",
	Section.VERSE: "主歌 · 读招攒气",
	Section.PRE: "导歌 · 压迫上升",
	Section.CHORUS: "副歌 · 破防爆发",
	Section.BRIDGE: "桥段 · 转阶段",
	Section.OUTRO: "尾声 · 收尾",
}

var file: String = ""
var bpm: float = 120.0
var first_beat_sec: float = 0.0
var beats_per_bar: int = 4
var duration_sec: float = 0.0
var sections: Array = []          # [{section: Section, start: float, end: float}]


static func load_from(path: String) -> SongMap:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SongMap: 打不开 %s" % path)
		return null
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("SongMap: %s 不是合法 JSON" % path)
		return null

	var m := SongMap.new()
	m.file = data.get("file", "")
	m.bpm = float(data.get("bpm", 120.0))
	m.first_beat_sec = float(data.get("first_beat_sec", 0.0))
	m.beats_per_bar = int(data.get("beats_per_bar", 4))
	m.duration_sec = float(data.get("duration_sec", 0.0))
	for s in data.get("sections", []):
		m.sections.append({
			"section": SECTION_FROM_STRING.get(s.get("name", "verse"), Section.VERSE),
			"start": float(s.get("start_sec", 0.0)),
			"end": float(s.get("end_sec", 0.0)),
		})
	return m


func section_at(t: float) -> Section:
	for s in sections:
		var a: float = s["start"]
		var b: float = s["end"]
		if t >= a and t < b:
			var kind: int = s["section"]
			return kind as Section
	if sections.is_empty():
		return Section.OUTRO
	var last: int = sections[-1]["section"]
	return last as Section


func section_end(t: float) -> float:
	for s in sections:
		var a: float = s["start"]
		var b: float = s["end"]
		if t >= a and t < b:
			return b
	return duration_sec


func label(sec: Section) -> String:
	return SECTION_LABEL.get(sec, "?")
