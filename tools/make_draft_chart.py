"""从音频自动生成谱面初稿。

从零敲一首 4 分半的歌是"表演"，不是"编辑"。
这个工具先给一份**已经跟音乐对齐的草稿**，人只需要改哪儿不对劲。

做法：
  1. HPSS 分离出打击乐轨（把人声和旋律的干扰去掉）
  2. 在拍网格上采样打击强度
  3. **强度最高的点 → block（他出招）**，每小节最多 1~2 个
  4. 其余有足够强度的拍 → strike（我斩）

这仍然符合「拍子网格来自歌曲」：所有事件都锁在网格点上，
只是「哪些网格点有事件」现在由鼓点强度决定，而不是取模运算。

用法:
    python tools/make_draft_chart.py <音频> <songmap.json> <输出chart.json> [选项]

选项:
    --sub N          每拍细分数，默认 2（八分音符）
    --blocks-per-bar N   每小节几个格挡点，默认 1
    --strike-thresh F    斩的强度阈值 0~1，默认 0.25（越低音符越密）
    --start-sec F / --end-sec F   只生成这个区间
"""

import argparse
import json
import os

import librosa
import numpy as np


def build(audio_path, songmap_path, out_path, sub, blocks_per_bar,
          strike_thresh, start_sec, end_sec):
    with open(songmap_path, "r", encoding="utf-8") as f:
        smap = json.load(f)

    bpm = float(smap["bpm"])
    first_beat = float(smap["first_beat_sec"])
    beats_per_bar = int(smap.get("beats_per_bar", 4))
    beat_dur = 60.0 / bpm

    print("loading %s ..." % audio_path)
    y, sr = librosa.load(audio_path, sr=None, mono=True)
    duration = float(librosa.get_duration(y=y, sr=sr))

    # 只留打击乐 —— 人声和旋律会污染 onset 检测
    print("separating percussive ...")
    y_perc = librosa.effects.percussive(y, margin=3.0)

    hop = 256          # 比默认 512 更细，定位更准
    env = librosa.onset.onset_strength(y=y_perc, sr=sr, hop_length=hop)
    env_times = librosa.frames_to_time(np.arange(len(env)), sr=sr, hop_length=hop)
    if env.max() > 0:
        env = env / env.max()

    # 在细分网格上采样强度
    step = beat_dur / sub
    lo = start_sec if start_sec is not None else first_beat
    hi = end_sec if end_sec is not None else duration
    grid_times = np.arange(max(lo, first_beat), hi, step)
    idx = np.searchsorted(env_times, grid_times)
    idx = np.clip(idx, 0, len(env) - 1)
    # 取网格点附近的局部最大值，容忍几毫秒误差
    win = max(1, int(0.030 * sr / hop))
    strengths = np.array([
        float(env[max(0, i - win):min(len(env), i + win + 1)].max())
        for i in idx
    ])
    grid_beats = (grid_times - first_beat) / beat_dur

    # ---- block：每小节取强度最高的 N 个网格点 ----
    events = []
    used = set()
    bar_of = np.floor(grid_beats / beats_per_bar).astype(int)
    for bar in np.unique(bar_of):
        mask = np.where(bar_of == bar)[0]
        if len(mask) == 0:
            continue
        order = mask[np.argsort(-strengths[mask])]
        picked = 0
        for i in order:
            if picked >= blocks_per_bar:
                break
            if strengths[i] < 0.15:
                break
            b = round(grid_beats[i] * sub) / sub
            events.append({"beat": b, "role": "block"})
            used.add(i)
            picked += 1

    # ---- strike：其余强度够的网格点 ----
    block_beats = {round(e["beat"] * sub) for e in events}
    for i in range(len(grid_beats)):
        if i in used:
            continue
        if strengths[i] < strike_thresh:
            continue
        key = round(grid_beats[i] * sub)
        if key in block_beats:
            continue
        events.append({"beat": key / sub, "role": "strike"})

    events.sort(key=lambda e: e["beat"])

    out = {
        "song": os.path.basename(audio_path),
        "bpm": round(bpm, 4),
        "first_beat_sec": round(first_beat, 4),
        "quantize": sub,
        "event_count": len(events),
        "_generated": "tools/make_draft_chart.py — 初稿，需人工在录制器里修",
        "events": [{"beat": round(e["beat"], 4), "role": e["role"]} for e in events],
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)

    n_block = sum(1 for e in events if e["role"] == "block")
    n_strike = len(events) - n_block
    span = (events[-1]["beat"] - events[0]["beat"]) * beat_dur if events else 0.0
    print()
    print("=" * 62)
    print("  %s" % os.path.basename(out_path))
    print("=" * 62)
    print("  BPM %.2f   细分 1/%d 拍   每小节 %d 个格挡点" % (bpm, sub, blocks_per_bar))
    print("  事件   格挡 %d   斩 %d   合计 %d" % (n_block, n_strike, len(events)))
    print("  覆盖   %.1f 秒 (第 %.1f ~ %.1f 拍)"
          % (span, events[0]["beat"] if events else 0,
             events[-1]["beat"] if events else 0))
    print("  平均密度 %.2f 个/拍"
          % (len(events) / max(1.0, (events[-1]["beat"] - events[0]["beat"]))
             if events else 0.0))
    print()
    print("  写入 %s" % out_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("audio")
    ap.add_argument("songmap")
    ap.add_argument("out")
    ap.add_argument("--sub", type=int, default=2)
    ap.add_argument("--blocks-per-bar", type=int, default=1)
    ap.add_argument("--strike-thresh", type=float, default=0.25)
    ap.add_argument("--start-sec", type=float, default=None)
    ap.add_argument("--end-sec", type=float, default=None)
    a = ap.parse_args()
    build(a.audio, a.songmap, a.out, a.sub, a.blocks_per_bar,
          a.strike_thresh, a.start_sec, a.end_sec)


if __name__ == "__main__":
    main()
