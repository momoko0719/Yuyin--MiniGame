"""生成节拍器测试音轨（WAV）。

原型阶段用来验证节拍时钟的准确度：能听见"哒"，也能看见画面闪，
两者对不对得上一测便知。

用法:
    python tools/make_click_track.py <输出路径> [bpm] [时长秒] [每小节拍数]
"""

import math
import struct
import sys
import wave

SAMPLE_RATE = 44100
BIT_DEPTH_MAX = 32767


def click(freq: float, duration: float, amplitude: float) -> list[int]:
    """一记短促的、指数衰减的正弦音。"""
    n = int(SAMPLE_RATE * duration)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        envelope = math.exp(-t * 45.0)  # 快速衰减，听感干脆
        sample = math.sin(2.0 * math.pi * freq * t) * envelope * amplitude
        out.append(int(sample * BIT_DEPTH_MAX))
    return out


def build(bpm: float, seconds: float, beats_per_bar: int) -> bytes:
    total = int(SAMPLE_RATE * seconds)
    buf = [0] * total

    beat_duration = 60.0 / bpm
    accent = click(1600.0, 0.05, 0.85)   # 每小节第一拍，高音
    normal = click(1000.0, 0.04, 0.55)   # 其余拍，低一点

    beat_index = 0
    while True:
        start = int(beat_index * beat_duration * SAMPLE_RATE)
        if start >= total:
            break
        sound = accent if beat_index % beats_per_bar == 0 else normal
        for i, s in enumerate(sound):
            if start + i < total:
                buf[start + i] = max(-BIT_DEPTH_MAX,
                                     min(BIT_DEPTH_MAX, buf[start + i] + s))
        beat_index += 1

    return b"".join(struct.pack("<h", s) for s in buf)


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    path = sys.argv[1]
    bpm = float(sys.argv[2]) if len(sys.argv) > 2 else 120.0
    seconds = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0
    beats_per_bar = int(sys.argv[4]) if len(sys.argv) > 4 else 4

    data = build(bpm, seconds, beats_per_bar)

    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(data)

    print(f"wrote {path}")
    print(f"  bpm={bpm}  seconds={seconds}  beats_per_bar={beats_per_bar}")
    print(f"  beat duration = {60.0 / bpm * 1000.0:.2f} ms")


if __name__ == "__main__":
    main()
