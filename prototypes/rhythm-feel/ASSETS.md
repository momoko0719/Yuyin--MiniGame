# 《牵丝戏》一场戏 — 美术素材规格

**全部 2D。** 战斗是横版侧视，位置是演出结果而非玩法输入，3D 不带来玩法价值；
水墨也是 2D 原生的语言。

**放置路径**：`prototypes/rhythm-feel/rhythm-feel/art/`（Godot 项目内，丢进去自动导入）

**关于尺寸**：引擎里会缩放，所以精确像素数不重要，**重要的是长宽比和透明背景**。
下面给的是建议生成尺寸，按你的生图工具支持的档位取最接近的即可。

**关于风格一致性**：所有图**在同一次会话里连续生成**，效果最好。
如果工具支持固定 seed 或参考图，第一张定下来之后后面都沿用。

---

## 角色为什么要拆件

傀儡的关节本来就是分离的——**把角色拆成两件，我用代码旋转关节做动画**，
不需要逐帧动画，而且木偶式的关节运动本身就是这首歌的美学。
这同时避开了 AI 生图最大的坑：多帧之间人物长得不一样。

**拆哪一只手臂？** 侧视角下"左手/右手"是伪问题——只有**靠镜头这一侧**的手臂
看得见，另一只被身体挡住。所以：

- **身体图**：画躯干、头、腿，**以及远端那只手臂**（自然垂着，不需要动）
- **手臂图**：只画**近端那只**（持刀 / 兰花指），它要绕肩关节旋转

---

## 背景为什么大部分要透明

三层背景要做视差纵深，所以**只有最底层不透明，其余全部镂空**，
否则前面的层会把后面的完全盖住（这一点我第一版写错了）。

```
最后 ┌ far.png      不透明，铺满     夜色、雨、远处轮廓
     │ mid.png      ★必须透明★      只有三尺红台本体，四周镂空
     │ lantern×N    透明             代码摆放，跟着拍子摇
     │ 角色 + 特效 + 音符轨道
最前 └ fore.png     透明             只有左右帷幕 + 顶部帘楣，中间全空
```

**灯笼只在单独文件里**，中景图里不要画灯笼——因为灯笼要跟着拍子摇曳，
必须是独立的一件。

---

# P0 — 先给这些就能开工

## 1. 沈砚 · 身体

**文件**：`art/characters/shen_yan/body.png`
**尺寸**：1024 × 1024，**透明背景**
**朝向**：侧身朝右

```
Chinese ink wash painting style, guofeng, muted ink black and paper cream base,
single accent of deep vermilion red, soft rice-paper texture, elegant brushstroke
edges, flat 2D game asset, full body character, transparent background,
no text, no watermark, no shadow on ground.

A young wuxia swordsman standing in side profile facing right, plain worn
dark blue-grey robe, slightly ragged hem, hair tied simply, calm and
determined expression, feet planted in a ready stance.
IMPORTANT: draw the head, torso, both legs, and ONLY the FAR-SIDE arm
(the arm on the far side of the body, hanging relaxed at his side, empty-handed).
The NEAR-SIDE arm — the one closest to the viewer, which would hold a weapon —
must be OMITTED entirely. Leave that shoulder area clean with no arm and no sword.
Marionette-like jointed doll proportions.
```

> 关键：**画远端手臂（垂着、空手），省略近端持刀手臂**。
> 近端手臂是单独一件，我要绕肩关节旋转它做出刀动作。

---

## 2. 沈砚 · 持刀手臂

**文件**：`art/characters/shen_yan/arm_sword.png`
**尺寸**：1024 × 512（横向），**透明背景**
**朝向**：手臂从左侧肩部伸出，刀尖朝右

```
Chinese ink wash painting style, guofeng, muted ink black and paper cream base,
single accent of deep vermilion red, soft rice-paper texture, elegant brushstroke
edges, flat 2D game asset, transparent background, no text, no watermark.

A single human arm holding a Chinese dao (single-edged sabre), extended
horizontally to the right, seen from the side. Sleeve is plain dark blue-grey
worn cloth matching a poor swordsman. The shoulder joint end is at the far
left of the image, the blade tip at the far right. Clean cut at the shoulder,
no torso attached, no second arm.
```

> 关键：**肩关节必须在图片最左端**——我以那个点为轴旋转。刀和手臂是一整件。
> 这是"近端手臂"，跟身体图里那只垂着的远端手臂是两只不同的手。

---

## 3. 傀儡师 · 身体

**文件**：`art/characters/puppeteer/body.png`
**尺寸**：1024 × 1024，**透明背景**
**朝向**：侧身朝左

```
Chinese ink wash painting style, guofeng, muted ink black and paper cream base,
strong deep vermilion red and antique gold accents, soft rice-paper texture,
elegant brushstroke edges, flat 2D game asset, full body character,
transparent background, no text, no watermark, no shadow on ground.

A puppeteer master standing in side profile facing left, elaborate painted
opera-style robe in vermilion and gold, ornate but frayed at the edges,
tall and still, face partly obscured, theatrical and eerie presence.
IMPORTANT: draw the head, torso, lower robe, and ONLY the FAR-SIDE arm
(the arm on the far side of the body, hanging still at his side).
The NEAR-SIDE arm — the one closest to the viewer, which would be raised —
must be OMITTED entirely. Leave that shoulder area clean with no arm.
Marionette-like jointed doll proportions.
```

> 歌词里"**你褴褛我彩绘**"——沈砚朴素破旧，傀儡师彩绘华丽。
> 生成时把这个对比拉满，两个人站一起画面才有戏。

---

## 4. 傀儡师 · 抬起的手臂（兰花指）

**文件**：`art/characters/puppeteer/arm_raise.png`
**尺寸**：1024 × 512（横向），**透明背景**
**朝向**：手臂从右侧肩部伸出，手在左端

```
Chinese ink wash painting style, guofeng, muted ink black and paper cream base,
deep vermilion red and antique gold accents, soft rice-paper texture, elegant
brushstroke edges, flat 2D game asset, transparent background, no text, no watermark.

A single elegant arm in an ornate vermilion and gold opera sleeve, extended
to the left, ending in a slender hand posed in the classical Chinese
"orchid finger" gesture (lanhua zhi), fingertips delicately raised.
The shoulder joint end is at the far right of the image, the hand at the far left.
Clean cut at the shoulder, no torso attached, no second arm. No strings drawn.
```

> 关键：**肩关节必须在图片最右端**。**不要画丝线**——丝线我用代码画，
> 因为它需要动态拉伸和断裂。这个手势是牵丝的起手预兆。
> 这是"近端手臂"，跟身体图里那只垂着的远端手臂是两只不同的手。

---

## 5. 背景 · 远景

**文件**：`art/background/far.png`
**尺寸**：2560 × 1440，**不透明**（这是唯一一张不透明的图，它是整个画面的底）

```
Chinese ink wash painting style, guofeng, muted ink black and deep indigo night,
soft rice-paper texture, atmospheric and empty, flat 2D game background layer,
no characters, no text, no watermark.

A rainy night seen from far away, faint silhouettes of tall hanging silk
curtains receding into darkness, very dim, heavy negative space, fine rain
streaks, almost monochrome with only the faintest warm glow deep in the distance.
```

---

## 6. 背景 · 中景（三尺红台）

**文件**：`art/background/mid.png`
**尺寸**：2048 × 1152，**必须透明**（舞台以外全部镂空）

```
Chinese ink wash painting style, guofeng, ink black outlines with deep vermilion
red lacquer, soft rice-paper texture, flat 2D game asset,
transparent background, no text, no watermark.

An isolated small red wooden puppet theatre stage (three-foot red stage) seen
from the side, worn lacquered vermilion wood, a low platform with carved edges,
silk curtains tied open at both far ends of the platform, wet floorboards.
The stage sits in the LOWER portion of the image.
Everything around and above the stage must be fully transparent — no sky,
no background, no ground beyond the stage itself, no lanterns.
```

> **必须透明**，否则会把远景整个盖住（视差就白做了）。
> **不要画灯笼**——灯笼是单独一件，因为它要跟着拍子摇。
> 角色会站在这一层前面，所以舞台**中间区域留空**，别放细节。

---

## 7. 背景 · 前景（帷幕框边）

**文件**：`art/background/fore.png`
**尺寸**：2560 × 1440，**必须透明**（中间大面积镂空）

```
Chinese ink wash painting style, guofeng, dark ink black silk with deep vermilion
red edge, soft rice-paper texture, flat 2D game foreground overlay layer,
transparent background, no text, no watermark.

Heavy silk theatre curtains hanging only along the LEFT and RIGHT edges of the
frame, and a thin decorative valance along the TOP edge. The entire CENTER of the
image must be fully transparent and empty. Slightly out of focus, close to camera.
```

> 关键：**中间必须是全透明的**。这一层盖在最上面，用来把画面框成"一台戏"。

---

## 8. 灯笼（单独一件，用于摇曳和发光）

**文件**：`art/background/lantern.png`
**尺寸**：512 × 1024（竖向），**透明背景**

```
Chinese ink wash painting style, guofeng, deep vermilion red paper with ink black
frame, soft warm inner glow, soft rice-paper texture, flat 2D game asset,
transparent background, no text, no watermark.

A single traditional Chinese hanging paper lantern with a short tassel below,
seen from the side, lit from within with a dim warm glow, hanging from a thin
cord at the top of the image.
```

> 我会复制几个挂在台边，让它们**跟着拍子轻轻摇**——这是 Hi-Fi Rush 那条
> "全世界都在打拍子"的原则，也让画面在静止时也有节奏。

---

## 9. 刀光

**文件**：`art/vfx/slash.png`
**尺寸**：1024 × 512，**透明背景**

```
Chinese ink wash painting style, a single sweeping brushstroke arc, ink black
fading into pale grey at both tips, wet brush texture with visible bristle
streaks and a few ink splatter droplets, flat 2D game VFX asset,
transparent background, no character, no text, no watermark.
```

> 一道弧形笔触。命中时我会把它拉伸、旋转、快速淡出。

---

## 10. 命中火花

**文件**：`art/vfx/spark.png`
**尺寸**：512 × 512，**透明背景**

```
Chinese ink wash painting style, a burst of sharp ink splatter radiating outward
from a single center point, ink black with a few deep vermilion red droplets,
irregular organic brush splatter, flat 2D game VFX asset, transparent background,
no text, no watermark.
```

---

## 11. 音符 · 斩（铃）

**文件**：`art/ui/note_strike.png`
**尺寸**：256 × 256，**透明背景**

```
Chinese ink wash painting style, a single small round bronze bell (traditional
Chinese pan ling) seen from the side, cool blue-green patina, ink outline,
soft rice-paper texture, flat 2D game UI icon, transparent background,
centered, no text, no watermark.
```

> 歌词有"**盘铃声清脆**"——所以音符是挂在丝线上的**铃铛**，不是抽象圆点。

---

## 12. 音符 · 格挡（铃）

**文件**：`art/ui/note_block.png`
**尺寸**：256 × 256，**透明背景**

```
Chinese ink wash painting style, a single small round bronze bell (traditional
Chinese pan ling) seen from the side, deep vermilion red lacquer with gold rim,
ink outline, soft rice-paper texture, flat 2D game UI icon,
transparent background, centered, no text, no watermark.
```

> 跟上一个**造型必须一样，只有颜色不同**——蓝=你的，红=他的。
> 被"夺走"的时候玩家要能一眼看出铃从蓝变红。

---

# 不用生成的（我用代码画，效果更好）

| 元素 | 为什么 |
|---|---|
| **丝线** | 需要动态拉伸、弯曲、断裂——素材做不到，代码画的线可以实时变形 |
| **轨道底/判定线** | 纯几何，代码画更干净且能随节拍脉动 |
| **血条 / 气条** | 同上 |
| **文字**（连段数、结算） | 引擎字体渲染 |

---

# P1 — 有余力再给

| 文件 | 尺寸 | 说明 |
|---|---|---|
| `art/characters/puppeteer/arm_raise_broken.png` | 1024×512 | 破防时手臂垂下的版本 |
| `art/vfx/string_break.png` | 512×512 | 丝线断裂的爆点（也可以用 spark 代替） |
| `art/background/mid_chorus.png` | 2560×1440 | 副歌破防时的舞台变体（灯全亮 / 帷幕扬起） |

---

# 我这边的进度

代码**不依赖美术**——现在的色块版本已经能跑。我会先把牵丝机制和拆件动画的
框架写出来，素材到了直接替换贴图，不用返工。

**还需要你给一个时间点**：歌词里
「**他们迂回误会　我却只由你支配**」这句唱到第几秒？
我想把全曲最大的一次牵丝放在这一句上。报个大概秒数就行，会自动吸附到小节线。
