"""导出歌曲的能量包络，供制谱编辑器当背景参考。

为什么需要：
古风流行的节奏骨架在**人声**上，不在鼓上 ——
"兰花指捻红尘似水"，每一个字就是一个节奏点。
抒情曲的鼓又稀又软，自动检测几乎抓不到信号，
但人声在混音里是最响的，能量包络的尖峰就是字的位置。

制谱时把这条曲线画在轨道背景上，**你能看见每个字在哪**，
再决定哪个字放斩、哪个字放格挡。

输出：按拍细分采样的归一化能量数组（JSON）。

用法:
    python tools/make_envelope.py <音频> <songmap.json> [输出.json] [--sub 8]
"""

import argparse
import json
import os

import librosa
import numpy as np


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("audio")
    ap.add_argument("songmap")
    ap.add_argument("out", nargs="?", default=None)
    ap.add_argument("--sub", type=int, default=8,
                    help="每拍采样点数，默认 8（三十二分音符精度）")
    a = ap.parse_args()

    out_path = a.out or os.path.splitext(a.audio)[0] + ".envelope.json"

    with open(a.songmap, "r", encoding="utf-8") as f:
        smap = json.load(f)
    bpm = float(smap["bpm"])
    first_beat = float(smap["first_beat_sec"])
    beat_dur = 60.0 / bpm

    print("loading %s ..." % a.audio)
    y, sr = librosa.load(a.audio, sr=None, mono=True)
    duration = float(librosa.get_duration(y=y, sr=sr))

    # 谐波成分 ≈ 人声与旋律（去掉鼓的冲击），抒情曲里这条更能反映"字"
    y_harm = librosa.effects.harmonic(y, margin=2.0)

    hop = 256
    onset_all = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
    onset_voc = librosa.onset.onset_strength(y=y_harm, sr=sr, hop_length=hop)
    rms = librosa.feature.rms(y=y, hop_length=hop)[0]

    n = min(len(onset_all), len(onset_voc), len(rms))
    times = librosa.frames_to_time(np.arange(n), sr=sr, hop_length=hop)

    def norm(x):
        x = np.asarray(x[:n], dtype=float)
        m = x.max()
        return x / m if m > 0 else x

    onset_all = norm(onset_all)
    onset_voc = norm(onset_voc)
    rms = norm(rms)

    # 在拍细分网格上采样（取局部最大，容忍几毫秒误差）
    step = beat_dur / a.sub
    grid_t = np.arange(first_beat, duration, step)
    idx = np.clip(np.searchsorted(times, grid_t), 0, n - 1)
    win = max(1, int(0.020 * sr / hop))

    def sample(arr):
        return [
            round(float(arr[max(0, i - win):min(n, i + win + 1)].max()), 4)
            for i in idx
        ]

    out = {
        "file": os.path.basename(a.audio),
        "bpm": round(bpm, 4),
        "first_beat_sec": round(first_beat, 4),
        "sub": a.sub,
        "start_beat": 0.0,
        "count": len(grid_t),
        "onset": sample(onset_all),      # 全频段冲击（鼓 + 字）
        "vocal": sample(onset_voc),      # 谐波冲击 ≈ 字
        "rms": sample(rms),              # 整体响度
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)

    print("  采样点 %d   每拍 %d 点   覆盖 %.1f 秒"
          % (len(grid_t), a.sub, duration - first_beat))
    print("  写入 %s" % out_path)


if __name__ == "__main__":
    main()
