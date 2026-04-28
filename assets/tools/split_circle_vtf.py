"""
把 2x2 sprite atlas 形式的 circle.vtf 重做成「真.4 幀動畫 VTF」
並另存為 circle_ground.vtf (給模型材質用)，原本 circle.vtf 不動。

關鍵設定：
  L4D2 引擎只認 VTF 7.4 以下。srctools 預設寫 7.5，必須在 save() 時
  明確 override 成 (7, 4) 否則進遊戲會出 "invalid minor version" 錯。

針對 $additive 1 材質的兩個重要修正：
  (A) Premultiply Alpha
      $additive 是直接把 RGB 加進畫面，完全不看 alpha。
      若透明區 (alpha=0) 的 RGB 不是 0，畫面上會看到方塊狀發光區。
      解法：把每個像素的 RGB 預乘 alpha (RGB *= alpha/255)，這樣
      alpha=0 的位置 RGB 會變 0，加進畫面也是 0 (=不發光)。
  (B) Center alignment
      4 幀切出來後，每幀內「圓心」的位置可能略有偏移，動畫切幀會
      看起來在跳。解法：對每幀計算「不透明像素」的重心，把每幀都
      平移到正中央，這樣切幀時圓心穩定。
"""

from pathlib import Path
import numpy as np
from PIL import Image
from srctools.vtf import VTF, ImageFormats, VTFFlags

# === 路徑 ===
GAME_ROOT = Path(r"D:\SteamLibrary\steamapps\common\Left 4 Dead 2 Dedicated Server\left4dead2")
SRC_VTF   = GAME_ROOT / "materials" / "particle" / "konosuba" / "circle.vtf"
OUT_VTF   = GAME_ROOT / "materials" / "particle" / "konosuba" / "circle_ground.vtf"
VTF_VERSION_FOR_L4D2 = (7, 4)


def alpha_bbox(img: Image.Image, threshold: int = 8):
    """回傳 alpha > threshold 的像素的 bounding box (left, top, right, bottom)。
    沒任何不透明像素就回 None。"""
    arr = np.array(img)
    alpha = arr[..., 3]
    ys, xs = np.where(alpha > threshold)
    if len(xs) == 0:
        return None
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def recenter_in_canvas(img: Image.Image) -> Image.Image:
    """把 img 中可見部分平移到 canvas 正中央。"""
    bbox = alpha_bbox(img)
    if bbox is None:
        return img
    cx_src = (bbox[0] + bbox[2]) / 2.0
    cy_src = (bbox[1] + bbox[3]) / 2.0
    cx_dst = img.width  / 2.0
    cy_dst = img.height / 2.0
    dx = int(round(cx_dst - cx_src))
    dy = int(round(cy_dst - cy_src))

    canvas = Image.new("RGBA", img.size, (0, 0, 0, 0))
    canvas.paste(img, (dx, dy), img)
    return canvas


def premultiply_alpha(img: Image.Image) -> Image.Image:
    """把 RGB 預乘 alpha，使 alpha=0 的像素 RGB 也=0。
    這樣後續用 $additive 渲染時，透明區不會發光。"""
    arr = np.array(img, dtype=np.uint16)  # 用 16-bit 暫存避免 overflow
    a = arr[..., 3:4]
    arr[..., :3] = (arr[..., :3] * a + 127) // 255   # +127 做四捨五入
    return Image.fromarray(arr.astype(np.uint8), mode="RGBA")


# === 1. 讀入原 atlas VTF ===
with open(SRC_VTF, "rb") as f:
    src_vtf = VTF.read(f)
    print(f"[讀入] {SRC_VTF.name} -> {src_vtf.width}x{src_vtf.height}, {src_vtf.frame_count} frame(s)")

    src_frame = src_vtf.get(frame=0)
    src_frame.load()
    src_pil = src_frame.to_PIL()

if src_pil.mode != "RGBA":
    src_pil = src_pil.convert("RGBA")

W, H = src_pil.size
hw, hh = W // 2, H // 2

# === 2. 切 4 個象限 ===
raw_quads = [
    src_pil.crop((0,  0,  hw, hh)),     # 左上
    src_pil.crop((hw, 0,  W,  hh)),     # 右上
    src_pil.crop((0,  hh, hw, H)),      # 左下
    src_pil.crop((hw, hh, W,  H)),      # 右下
]

# === 3. 對每幀做：自動置中 + Premultiply Alpha ===
processed = []
for i, q in enumerate(raw_quads):
    bb = alpha_bbox(q)
    centered = recenter_in_canvas(q)
    pma      = premultiply_alpha(centered)
    processed.append(pma)
    print(f"[幀{i}] bbox={bb}  -> 已置中 + 預乘 alpha")

# === 4. 建立新 VTF（VTF 7.4，4 幀，DXT5）===
new_vtf = VTF(
    width   = hw,
    height  = hh,
    version = VTF_VERSION_FOR_L4D2,
    frames  = 4,
    fmt     = ImageFormats.DXT5,
    flags   = VTFFlags.EIGHTBITALPHA,
)

for idx, img in enumerate(processed):
    new_vtf.get(frame=idx).copy_from(img.tobytes("raw", "RGBA"), ImageFormats.RGBA8888)

new_vtf.compute_mipmaps()
print("[mipmaps] 已重新計算")

# === 5. 寫出 ===
with open(OUT_VTF, "wb") as f:
    new_vtf.save(f, version=VTF_VERSION_FOR_L4D2)

with open(OUT_VTF, "rb") as f:
    verify = VTF.read(f, header_only=True)
print(f"[完成] {OUT_VTF.name}  {verify.width}x{verify.height}  "
      f"{verify.frame_count} frames  v{verify.version[0]}.{verify.version[1]}  "
      f"{OUT_VTF.stat().st_size:,} bytes")

# === 6. 也輸出預覽 PNG ===
out_dir = Path(__file__).parent / "preview"
out_dir.mkdir(parents=True, exist_ok=True)
for i, img in enumerate(processed):
    img.save(out_dir / f"frame{i}.png")
print(f"[預覽] 4 張 PNG 已輸出到 {out_dir}")
