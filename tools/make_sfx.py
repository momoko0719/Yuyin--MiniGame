"""生成战斗音效（WAV）。

原型阶段用程序合成，不用外部素材。正式版会换成实录音源
（《怪物猎人：世界》的做法是去大自然实地取材、用真实武器材料录音）。

分层结构来自调研结论 —— 物理攻击音是三段：
    破空声 → 碰撞声 → 液体飞溅声
这里把三层直接烘焙进单个文件，运行时不再叠加。

音量优先级（调研结论）：格挡音 > 击中音 > 攻击音 > 喊话

用法:
    python tools/make_sfx.py <输出目录>
"""

import math
import os
import random
import struct
import sys
import wave

SR = 44100
PEAK = 32767


# ---------------------------------------------------------------- 基础层

def _blank(duration):
    return [0.0] * int(SR * duration)


def _mix(base, layer, offset=0.0, gain=1.0):
    start = int(SR * offset)
    for i, v in enumerate(layer):
        j = start + i
        if 0 <= j < len(base):
            base[j] += v * gain
    return base


def noise(duration, decay, cutoff_smoothing=0):
    """噪声爆发。cutoff_smoothing 越大越闷（简易低通）。"""
    n = int(SR * duration)
    raw = [random.uniform(-1.0, 1.0) for _ in range(n)]
    if cutoff_smoothing > 0:
        smoothed = []
        acc = 0.0
        k = 1.0 / (cutoff_smoothing + 1)
        for v in raw:
            acc += (v - acc) * k
            smoothed.append(acc)
        raw = smoothed
        peak = max(abs(v) for v in raw) or 1.0
        raw = [v / peak for v in raw]
    return [raw[i] * math.exp(-i / SR * decay) for i in range(n)]


def thump(f_start, f_end, duration, decay):
    """低频闷响 —— 打击感里"沉"的那部分，玩家用身体感觉而不是耳朵。"""
    n = int(SR * duration)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / n
        f = f_start + (f_end - f_start) * t
        phase += 2.0 * math.pi * f / SR
        out.append(math.sin(phase) * math.exp(-i / SR * decay))
    return out


def metallic(base_freq, duration, decay, partials=(1.0, 2.37, 3.41, 4.83, 6.11)):
    """金属撞击 —— 非谐波泛音，刀剑相击的"铛"。"""
    n = int(SR * duration)
    out = [0.0] * n
    for k, ratio in enumerate(partials):
        f = base_freq * ratio
        amp = 1.0 / (k + 1.3)
        d = decay * (1.0 + k * 0.35)
        for i in range(n):
            out[i] += math.sin(2.0 * math.pi * f * i / SR) * amp * math.exp(-i / SR * d)
    peak = max(abs(v) for v in out) or 1.0
    return [v / peak for v in out]


def swoosh(duration):
    """破空声 —— 由闷到亮再收，模拟刀刃划过空气。"""
    n = int(SR * duration)
    raw = [random.uniform(-1.0, 1.0) for _ in range(n)]
    out = []
    acc = 0.0
    for i, v in enumerate(raw):
        t = i / n
        # 平滑系数随时间变化 = 简易可变低通
        k = 0.02 + 0.5 * math.sin(math.pi * t) ** 2
        acc += (v - acc) * k
        env = math.sin(math.pi * t) ** 1.6
        out.append(acc * env)
    peak = max(abs(v) for v in out) or 1.0
    return [v / peak for v in out]


# ---------------------------------------------------------------- 成品

def make_swing():
    """攻击挥空 —— 只有破空声，音量最低。"""
    buf = _blank(0.20)
    _mix(buf, swoosh(0.18), 0.0, 0.45)
    return buf


def make_hit(weight):
    """命中。weight: 'light' | 'heavy' | 'finisher'

    三段结构：破空 → 碰撞 → 飞溅
    """
    cfg = {
        "light":    dict(dur=0.30, swoosh_g=0.35, crack_g=0.75, thump_g=0.55,
                         thump_f=(150, 60), spray_g=0.22, decay=42),
        "heavy":    dict(dur=0.45, swoosh_g=0.40, crack_g=0.95, thump_g=0.85,
                         thump_f=(120, 42), spray_g=0.32, decay=30),
        "finisher": dict(dur=0.85, swoosh_g=0.45, crack_g=1.00, thump_g=1.00,
                         thump_f=(95, 28), spray_g=0.45, decay=16),
    }[weight]

    buf = _blank(cfg["dur"])
    # 1. 破空（命中前）
    _mix(buf, swoosh(0.10), 0.0, cfg["swoosh_g"])
    # 2. 碰撞瞬间：高频撕裂 + 低频闷响
    _mix(buf, noise(0.09, cfg["decay"] * 2.2), 0.055, cfg["crack_g"])
    _mix(buf, thump(cfg["thump_f"][0], cfg["thump_f"][1],
                    cfg["dur"] * 0.7, cfg["decay"]), 0.055, cfg["thump_g"])
    # 3. 液体飞溅（尾巴）
    _mix(buf, noise(cfg["dur"] * 0.55, cfg["decay"] * 0.8, cutoff_smoothing=6),
         0.085, cfg["spray_g"])
    if weight == "finisher":
        # 终结斩额外一层更低的余韵
        _mix(buf, thump(55, 24, 0.7, 7), 0.06, 0.5)
    return buf


def make_block(perfect):
    """格挡 —— 金属相击。音量最大（调研：格挡音 > 击中音 > 攻击音）。"""
    if perfect:
        buf = _blank(0.60)
        _mix(buf, noise(0.03, 240), 0.0, 0.9)                 # 撞击瞬间
        _mix(buf, metallic(1450, 0.55, 9), 0.004, 1.0)        # 亮，长余韵
        _mix(buf, metallic(2900, 0.30, 20), 0.004, 0.45)      # 火花
        _mix(buf, thump(130, 60, 0.20, 40), 0.0, 0.5)
    else:
        buf = _blank(0.32)
        _mix(buf, noise(0.025, 300), 0.0, 0.7)
        _mix(buf, metallic(900, 0.26, 26), 0.004, 0.8)        # 闷，短
        _mix(buf, thump(110, 55, 0.16, 50), 0.0, 0.45)
    return buf


def make_hurt():
    """玩家受击。"""
    buf = _blank(0.40)
    _mix(buf, noise(0.10, 30, cutoff_smoothing=3), 0.0, 0.8)
    _mix(buf, thump(90, 35, 0.35, 16), 0.0, 0.9)
    return buf


# ---------------------------------------------------------------- 输出

def write(path, samples, gain=1.0):
    peak = max(abs(v) for v in samples) or 1.0
    norm = gain / peak
    data = b"".join(
        struct.pack("<h", max(-PEAK, min(PEAK, int(v * norm * PEAK))))
        for v in samples)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data)
    print("  wrote %-22s %5.2f s" % (os.path.basename(path), len(samples) / SR))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    random.seed(20260901)

    p = lambda name: os.path.join(out_dir, name)

    # gain 体现调研里的音量优先级
    write(p("swing.wav"), make_swing(), 0.40)
    write(p("hit_light.wav"), make_hit("light"), 0.72)
    write(p("hit_heavy.wav"), make_hit("heavy"), 0.86)
    write(p("hit_finisher.wav"), make_hit("finisher"), 1.00)
    write(p("block.wav"), make_block(False), 0.90)
    write(p("block_perfect.wav"), make_block(True), 1.00)
    write(p("hurt.wav"), make_hurt(), 0.80)


if __name__ == "__main__":
    main()
