// 薄片魔法陣模型 - 編譯成 models/konosuba/magic_circle_plane.mdl
// 編譯方法：用 Crowbar 載入此 .qc，按 Compile 即可
//
// 重點修正紀錄：
//  - 移除 $mostlyopaque  : 這會啟用「兩階段透明渲染」要求 shader 同時支援
//                         opaque/translucent 兩種頂點格式，跟我們的 $additive
//                         材質衝突，會跳 "does not support vertex format" 錯誤
//
// 設計重點：
//   $cdmaterials  -> 模型內部會去找 materials/particle/konosuba/circle_ground.vmt
//   SMD 內 triangle 的材質名「circle_ground」必須和 VMT 檔名相同
//   $staticprop   -> 不會有骨骼運算負擔，伺服器/客戶端壓力小
//   collisionmodel-> 故意不寫，連碰撞都不要（節省效能、不阻擋玩家）

$modelname "konosuba/magic_circle_plane.mdl"
$cdmaterials "particle\konosuba\"

$staticprop

$body Body "magic_circle_plane.smd"
$sequence idle "magic_circle_plane.smd" loop fps 1
