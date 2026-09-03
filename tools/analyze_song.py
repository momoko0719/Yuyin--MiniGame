"""分析歌曲，产出游戏用的「曲目地图」(song map)。

回答两个问题，玩家不需要口头告诉我们任何数字：
  1. BPM 是多少、第一拍在第几秒（**自动检测，机器比人准**）
  2. 主歌/副歌大致在哪（**自动检测只能给候选，最终要人耳确认**）

设计前提（见 design/gdd/game-concept.md）：
  **拍子网格来自歌曲，谱面内容来自 BOSS。**
  所以我们不需要手写音符谱面 —— 只需要 BPM + 段落边界，
  敌人出什么招由 BOSS 行为逻辑决定。这让制谱成本极低。
  （Dead as Disco 的做法相同：自由模式只有 BPM 同步，故事模式才加段落标注。）

用法:
    python tools/analyze_song.py <音频文件> [输出.json]
"""

import json
import os
import sys

import librosa
import numpy as np

BEATS_PER_BAR = 4
N_SEGMENTS = 8          # 结构分段的候选数量


def refine_phase(y, sr, bpm, first_beat):
    """定位拍网格的相位，并给出置信度。

    做法：在一个拍周期内扫描所有候选相位，把 onset 强度包络在
    「该相位下的所有网格点」上采样求和，取总能量最大的相位。
    这直接回答"拍点在哪"，而且对真实歌曲有效。

    置信度用 z 分数（最佳相位比平均相位高出几个标准差），
    而不是圆均值集中度 —— 后者只在纯节拍器上成立：
    真实歌曲的 onset 散布在八分、十六分音符上，集中度天然低，
    用节拍器的标准去量真歌会必然误判。
    """
    hop = 512
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
    env_times = librosa.frames_to_time(
        np.arange(len(onset_env)), sr=sr, hop_length=hop)
    if len(onset_env) < 16:
        return first_beat, 0.0

    period = 60.0 / bpm
    duration = float(env_times[-1])
    n_phase = 200
    scores = np.zeros(n_phase)

    for i in range(n_phase):
        phase = period * i / n_phase
        grid = np.arange(phase, duration, period)
        idx = np.searchsorted(env_times, grid)
        idx = idx[(idx > 0) & (idx < len(onset_env))]
        if len(idx) == 0:
            continue
        scores[i] = float(np.mean(onset_env[idx]))

    best_i = int(np.argmax(scores))
    best_phase = period * best_i / n_phase
    sd = float(np.std(scores))
    confidence = 0.0 if sd < 1e-9 else float((scores[best_i] - np.mean(scores)) / sd)

    # 把 first_beat 对齐到最佳相位（保持在同一个拍格内）
    aligned = best_phase
    return aligned, confidence


def detect_beats(y, sr):
    """返回 (bpm, beat_times)。"""
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    bpm, beat_frames = librosa.beat.beat_track(
        onset_envelope=onset_env, sr=sr, units="frames", trim=False)
    beat_times = librosa.frames_to_time(beat_frames, sr=sr)
    return float(np.atleast_1d(bpm)[0]), beat_times


def refine_bpm(beat_times, detected_bpm):
    """用相邻拍间隔的中位数复核 BPM —— 比单一估计稳。"""
    if len(beat_times) < 4:
        return detected_bpm
    intervals = np.diff(beat_times)
    # 去掉离群值（漏拍/多拍）
    med = float(np.median(intervals))
    keep = intervals[(intervals > med * 0.6) & (intervals < med * 1.4)]
    if len(keep) == 0:
        return detected_bpm
    return 60.0 / float(np.mean(keep))


def detect_sections(y, sr, n=N_SEGMENTS):
    """结构分段。返回 [(start_sec, rms_energy), ...]

    注意：这是**候选**，不是结论。自动结构分析对流行乐的
    主歌/副歌判断并不可靠，最终必须人耳确认。
    """
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
    bounds = librosa.segment.agglomerative(chroma, n)
    bound_times = librosa.frames_to_time(bounds, sr=sr)

    rms = librosa.feature.rms(y=y)[0]
    rms_times = librosa.frames_to_time(np.arange(len(rms)), sr=sr)

    out = []
    total = librosa.get_duration(y=y, sr=sr)
    edges = list(bound_times) + [total]
    for i in range(len(bound_times)):
        a, b = edges[i], edges[i + 1]
        mask = (rms_times >= a) & (rms_times < b)
        energy = float(np.mean(rms[mask])) if mask.any() else 0.0
        out.append((float(a), float(b), energy))
    return out


def label_sections(sections):
    """按能量高低猜测段落类型。

    副歌通常是全曲能量最高的段落，前奏/间奏最低。
    这只是启发式，标签供人工复核。
    """
    if not sections:
        return []
    energies = np.array([s[2] for s in sections])
    hi = float(np.percentile(energies, 70))
    lo = float(np.percentile(energies, 30))

    labeled = []
    for idx, (a, b, e) in enumerate(sections):
        if idx == 0:
            name = "intro"          # 前奏：对峙、试探
        elif e >= hi:
            name = "chorus"         # 副歌：破防爆发窗口
        elif e <= lo:
            name = "bridge"         # 间奏/桥段：BOSS 转阶段、喘息
        else:
            name = "verse"          # 主歌：读招、攒气
        labeled.append(dict(name=name, start_sec=round(a, 3),
                            end_sec=round(b, 3), energy=round(e, 5)))
    return labeled


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    path = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(path)[0] + ".songmap.json"

    print("loading %s ..." % path)
    y, sr = librosa.load(path, sr=None, mono=True)
    duration = float(librosa.get_duration(y=y, sr=sr))

    bpm_raw, beat_times = detect_beats(y, sr)
    bpm = refine_bpm(beat_times, bpm_raw)
    raw_first = float(beat_times[0]) if len(beat_times) else 0.0
    first_beat, phase_strength = refine_phase(y, sr, bpm, raw_first)
    # 归一化到第一个非负拍点
    period = 60.0 / bpm
    while first_beat < 0:
        first_beat += period
    while first_beat >= period:
        first_beat -= period

    sections = label_sections(detect_sections(y, sr))

    song_map = {
        "file": os.path.basename(path),
        "duration_sec": round(duration, 3),
        "bpm": round(bpm, 3),
        "bpm_raw_estimate": round(bpm_raw, 3),
        "first_beat_sec": round(first_beat, 4),
        "first_beat_uncorrected_sec": round(raw_first, 4),
        "phase_confidence": round(phase_strength, 3),
        "beats_per_bar": BEATS_PER_BAR,
        "beat_count": int(len(beat_times)),
        "sections": sections,
        "_note": "sections 为自动检测的候选，需人耳复核后再用",
    }

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(song_map, f, ensure_ascii=False, indent=2)

    # ---- 报告 ----
    print()
    print("=" * 62)
    print("  %s" % os.path.basename(path))
    print("=" * 62)
    print("  时长        %.2f s" % duration)
    print("  BPM         %.2f   (librosa 原始估计 %.2f)" % (bpm, bpm_raw))
    print("  一拍        %.1f ms" % (60000.0 / bpm))
    print("  第一拍      %.4f s   (校正前 %.4f s，修正 %+.1f ms)"
          % (first_beat, raw_first, (first_beat - raw_first) * 1000.0))
    if phase_strength >= 3.0:
        verdict = "拍点非常清晰"
    elif phase_strength >= 1.5:
        verdict = "拍点清晰，可用"
    else:
        verdict = "偏弱 —— 鼓点不够明确，判定可能会飘"
    print("  相位置信度  %.2f sigma   %s" % (phase_strength, verdict))
    print("  检测到拍数  %d" % len(beat_times))
    print()
    print("  段落候选（需人耳复核）：")
    print("  %-9s %8s %8s %10s" % ("类型", "起", "止", "能量"))
    for s in sections:
        print("  %-9s %7.2fs %7.2fs %10.5f"
              % (s["name"], s["start_sec"], s["end_sec"], s["energy"]))
    print()
    print("  写入 %s" % out_path)


if __name__ == "__main__":
    main()
