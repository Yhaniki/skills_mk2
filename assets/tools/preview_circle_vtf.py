"""
讀取已經是「4 幀動畫格式」的 circle.vtf，
把每一幀分別輸出成 PNG (frame0~frame3.png) 方便人眼確認。
"""
from pathlib import Path
from srctools.vtf import VTF

GAME_ROOT = Path(r"D:\SteamLibrary\steamapps\common\Left 4 Dead 2 Dedicated Server\left4dead2")
VTF_PATH  = GAME_ROOT / "materials" / "particle" / "konosuba" / "circle.vtf"
OUT_DIR   = Path(__file__).parent / "preview"
OUT_DIR.mkdir(parents=True, exist_ok=True)

with open(VTF_PATH, "rb") as f:
    vtf = VTF.read(f)
    print(f"VTF: {vtf.width}x{vtf.height}, {vtf.frame_count} frames")
    for i in range(vtf.frame_count):
        frame = vtf.get(frame=i)
        frame.load()
        img = frame.to_PIL()
        out = OUT_DIR / f"frame{i}.png"
        img.save(out)
        print(f"  -> {out.name} ({img.size})")
