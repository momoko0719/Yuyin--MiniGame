"""把人耳确认的段落时间点，合成为最终的「曲目地图」。

工作流（每首歌只需两步）：
  1. python tools/analyze_song.py <音频>      -> 自动测 BPM 和首拍
  2. python tools/make_songmap.py <自动map> "<段落>"  -> 人耳确认段落边界

段落边界会**自动吸附到最近的小节线**（玩家报的秒数不需要精确）。

设计前提：拍子网格来自歌曲，谱面内容来自 BOSS。
所以一首歌的制作成本只有「BPM（自动）+ 段落边界（人耳）」，
不需要手工摆放任何音符。

段落类型：
  intro   前奏     对峙、试探，教玩家听拍
  verse   主歌     攻防往来，读招攒气
  pre     导歌     压迫感上升，BOSS 准备破防
  chorus  副歌     **破防爆发窗口 —— 伤害翻倍**
  bridge  桥段     BOSS 转阶段，喘息
  outro   尾声     处决 / 收尾

用法:
    python tools/make_songmap.py <auto.songmap.json> "0:intro,6:verse,37.5:chorus,..."
    时间支持 "1:05" 或 "65" 两种写法。
"""

import json
import os
import sys

VALID = {"intro", "verse", "pre", "chorus", "bridge", "outro"}

SECTION_CN = {
    "intro": "前奏 · 对峙",
    "verse": "主歌 · 读招攒气",
    "pre": "导歌 · 压迫上升",
    "chorus": "副歌 · 破防爆发",
    "bridge": "桥段 · 转阶段",
    "outro": "尾声 · 收尾",
}


def parse_time(text):
    """支持 '1:05' 和 '65' 两种写法。"""
    text = text.strip()
    if ":" in text:
        m, s = text.split(":", 1)
        return float(m) * 60.0 + float(s)
    return float(text)


def snap_to_bar(t, first_beat, beat_dur, beats_per_bar):
    """吸附到最近的小节线。"""
    bar_dur = beat_dur * beats_per_bar
    idx = round((t - first_beat) / bar_dur)
    idx = max(0, idx)
    return first_beat + idx * bar_dur, int(idx)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    auto_path = sys.argv[1]
    spec = sys.argv[2]

    with open(auto_path, "r", encoding="utf-8") as f:
        auto = json.load(f)

    bpm = float(auto["bpm"])
    first_beat = float(auto["first_beat_sec"])
    beats_per_bar = int(auto.get("beats_per_bar", 4))
    duration = float(auto["duration_sec"])
    beat_dur = 60.0 / bpm

    entries = []
    for chunk in spec.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        t_raw, name = chunk.split(":", 1) if chunk.count(":") == 1 else \
            (chunk.rsplit(":", 1)[0], chunk.rsplit(":", 1)[1])
        name = name.strip().lower()
        if name not in VALID:
            print("未知段落类型 %r，可用：%s" % (name, ", ".join(sorted(VALID))))
            sys.exit(1)
        entries.append((parse_time(t_raw), name))

    entries.sort(key=lambda e: e[0])

    sections = []
    for i, (t_raw, name) in enumerate(entries):
        start, bar_idx = snap_to_bar(t_raw, first_beat, beat_dur, beats_per_bar)
        end = duration
        if i + 1 < len(entries):
            end, _ = snap_to_bar(entries[i + 1][0], first_beat, beat_dur, beats_per_bar)
        sections.append({
            "name": name,
            "start_sec": round(start, 4),
            "end_sec": round(end, 4),
            "start_bar": bar_idx,
            "start_beat": bar_idx * beats_per_bar,
            "reported_sec": round(t_raw, 2),
            "snap_shift_ms": round((start - t_raw) * 1000.0, 1),
        })

    out = {
        "file": auto["file"],
        "duration_sec": round(duration, 3),
        "bpm": round(bpm, 4),
        "beat_duration_sec": round(beat_dur, 6),
        "first_beat_sec": round(first_beat, 4),
        "beats_per_bar": beats_per_bar,
        "phase_confidence_sigma": auto.get("phase_confidence"),
        "sections": sections,
    }

    out_path = auto_path.replace(".songmap.json", ".map.json")
    if out_path == auto_path:
        out_path = os.path.splitext(auto_path)[0] + ".map.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)

    # ---- 报告 ----
    print()
    print("=" * 72)
    print("  %s   BPM %.2f   一拍 %.1f ms   一小节 %.2f s"
          % (out["file"], bpm, beat_dur * 1000.0, beat_dur * beats_per_bar))
    print("=" * 72)
    print("  %-16s %9s %9s %7s %10s"
          % ("段落", "起", "止", "小节", "吸附修正"))
    for s in sections:
        print("  %-16s %8.2fs %8.2fs %7d %+9.1fms"
              % (SECTION_CN[s["name"]], s["start_sec"], s["end_sec"],
                 s["start_bar"], s["snap_shift_ms"]))
    print()
    print("  写入 %s" % out_path)


if __name__ == "__main__":
    main()
