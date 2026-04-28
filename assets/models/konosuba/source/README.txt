==============================================
 magic_circle_plane.mdl  編譯與部署說明
==============================================

這個資料夾是給薄片魔法陣用的「模型原始檔」。
編譯後產生的 .mdl/.vvd/.vtx 才會放進 left4dead2/models/konosuba/。

------------------------------------------------------
A. 編譯（用 Crowbar，最簡單，不用裝 Source SDK）
------------------------------------------------------
1. 下載並開啟 Crowbar:
   https://steamcommunity.com/groups/CrowbarTool
   或 GitHub: https://github.com/UltraTechX/Crowbar-Command-Line

2. 在 Crowbar 上方的 [Set Up Games] 頁籤，
   選 "Left 4 Dead 2"（會自動偵測你已安裝的 Steam 版本）。

3. 切到 [Compile] 頁籤：
   - "QC file" 欄位 -> 選擇本資料夾的 magic_circle_plane.qc
   - "Compile to" 欄位 -> 任意輸出資料夾（例如桌面）
   - 按下 [Compile]

4. 編譯成功後，輸出資料夾會多出 4 個檔（依 dx 版本而定）：
       konosuba/magic_circle_plane.mdl
       konosuba/magic_circle_plane.vvd
       konosuba/magic_circle_plane.dx90.vtx
       konosuba/magic_circle_plane.dx80.vtx       (可有可無)

------------------------------------------------------
B. 部署
------------------------------------------------------
把編譯後的檔案放到：
    left4dead2/models/konosuba/magic_circle_plane.mdl
    left4dead2/models/konosuba/magic_circle_plane.vvd
    left4dead2/models/konosuba/magic_circle_plane.dx90.vtx

把材質貼圖放到：
    left4dead2/materials/particle/konosuba/circle.vtf
    left4dead2/materials/particle/konosuba/circle_ground.vmt
    left4dead2/materials/particle/konosuba/lightwarp/normal.vtf   (這份原本就有)

(circle.vmt 那份是給原本 PCF 粒子用的，跟 circle_ground.vmt 是兩件事，兩個都要保留)

------------------------------------------------------
C. 想改大小 / 形狀 / 高度
------------------------------------------------------
打開 magic_circle_plane.smd，看到 6 行三角形頂點 (-32 ~ +32)。
這是一個 64x64 的正方形薄片，平躺在 z=0 平面。
要改成更大或更小，把所有 32.0 / -32.0 等比例縮放即可。

之後要再生成新尺寸的 mdl，重新跑一次 Crowbar 編譯就好。

------------------------------------------------------
D. 模型內的材質名要對齊
------------------------------------------------------
SMD 裡每個三角形上面那行 "circle_ground" 是材質名，
必須和 materials/particle/konosuba/ 下的 VMT 檔名一樣（無副檔名）。
要改名 -> SMD 跟 VMT 兩邊都要一起改。
