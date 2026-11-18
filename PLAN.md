# skills_mk2 重構計畫

- 基準版本：tag `0.7`（`1549b88`）。任何一步出問題都可以退回這一版。
- 最後更新：2026-11-18

## 目標

1. 拆分 2975 行的主檔，通用函式集中管理。
2. 所有技能共用一套框架，一個技能一個檔案。
3. 全面改用 SourcePawn 新語法。
4. 技能中的延遲步驟改由框架統一排程，不再由各技能自己 `CreateTimer`。

## 已決定事項

| # | 決定 | 說明 |
|---|------|------|
| 1 | 目錄全部收進 `src/scripting/skills_mk2/`，入口是 `main.sp` | 不採用「`skills_mk2.sp` + 同名資料夾」、扁平前綴、模組放 `include/` 這三種方案 |
| 2 | 全面使用 `#pragma newdecls required` | 第三方 include 放在 pragma 之前 |
| 3 | 技能框架用「註冊 callback 表」實作 | SourcePawn 的 `methodmap` 不能覆寫方法，做不到真正的繼承；不拆成多個 `.smx` 插件 |
| 4 | 第 1、2 步只動結構，遊戲行為維持不變 | bug 統一在第 3 步修，每項各自一個 commit |
| 5 | 延遲步驟的取消時機 | 第 1、2 步維持現狀：施法者死亡、換圖後仍照樣觸發。第 3 步改成施法者死亡時取消、換圖時取消。框架在第 2 步就要支援取消 |
| 6 | 每一步一個 commit | 每步都要能單獨編譯、上伺服器測 |

## 目標目錄結構

```
src/scripting/
├─ include/                第三方 .inc（ammo、l4d2_weapon_stocks），維持不動
└─ skills_mk2/
   ├─ main.sp              入口：myinfo、include、所有 SourceMod / left4dhooks forward 統一分派
   ├─ config.sp            常數
   ├─ util.sp              通用純函式（沒有自己的狀態）
   ├─ core/
   │  ├─ globals.sp        跨模組共用的全域狀態（第 1 步過渡用，第 2 步拆掉）
   │  ├─ skill_base.sp     技能框架：註冊、狀態機、持續／冷卻、中斷、切換、清理分派
   │  ├─ scheduler.sp      延遲步驟排程（第 2 步新增）
   │  ├─ player.sp         玩家狀態事件、無敵、受傷 hook
   │  ├─ mp.sp             MP 增減、回復、腎上腺素
   │  ├─ hud.sp            技能提示文字與 MP 條
   │  ├─ commands.sp       skill1 / skill2 / change_skill / drop / fix / sm_skills_fillmp
   │  └─ precache.sp       資源預載（第 2 步拆進各技能的 onPrecache 後移除）
   ├─ fx/                  有自己狀態與清理的效果系統
   │  ├─ particle.sp   glow.sp   timescale.sp   screen.sp
   │  └─ magic_circle.sp   atmosphere.sp
   ├─ lib/
   │  ├─ weapons.sp        丟槍、彈藥、給物品（drop 指令和偷竊共用）
   │  ├─ dissolve.sp       Silvers 的 Dissolve Infected（forward 移到 main.sp）
   │  └─ resourcemanager.sp
   └─ skills/
      ├─ explosion.sp   explosion_ex.sp   mana_shield.sp
      └─ eagle_eye.sp   steal.sp          turn_undead.sp
```

編譯指令（在 `src/scripting/` 底下執行，輸出檔名不變）：

```
spcomp skills_mk2/main.sp -o ../plugins/skills_mk2.smx
```

命名規則：
- 整個插件是同一個編譯單元，所有名稱共用一個命名空間。
- 檔案內部使用的變數與函式一律宣告為 `static`。
- 對外的函式加模組前綴，例如 `Glow_`、`TurnUndead_`、`Skill_`。

## 編譯器限制（spcomp 1.12.0.7207 實測）

| 項目 | 結果 | 影響 |
|------|------|------|
| `enum struct` 存 `Function` 欄位；`typedef` 在註冊時檢查簽名 | 可行 | 框架可以用 callback 表實作 |
| 子資料夾的相對 `#include`（從上一層目錄編譯也正確） | 可行 | 目錄結構可行 |
| 子資料夾檔案內的 `static` 變數與函式 | 可行 | 技能私有狀態可以封裝在自己的檔案 |
| `#pragma newdecls` 在檔案內切換 `optional` / `required` | 可行 | 過渡期可以讓個別檔案暫時用舊語法 |
| 全域變數在宣告之前使用 | **不行**（函式可以前向引用） | include 順序要固定；跨模組的狀態放在較早 include 的檔案，或改用函式存取 |
| 存起來的 `Function` 用 `view_as<Timer>` 交給 `CreateTimer` | **不行** | 現在 `RegisterSkill` 用 `Timer:` tag 強轉 callback 的寫法，新語法下無法編譯 |

最後一項的處理方式：第 1 步讓 `core/skill_base.sp` 暫時維持 `#pragma newdecls optional`，第 2 步改寫成框架時再轉新語法。

## 技能框架設計（第 2 步）

框架（相當於父類別）負責：
- 技能註冊與選單
- 狀態機（準備 → 施放中 → 冷卻 → 準備）
- MP 扣除
- 持續與冷卻 timer
- 中斷、切換技能
- HUD 顯示
- 各種清理時機的分派

技能檔只實作需要的 hook，沒用到的不填：

| hook | 時機 | 目前用到的技能 |
|------|------|----------------|
| `onStart` | 施放 | 全部 |
| `onEnd` | 持續時間結束，或被動技能被切換掉 | 魔心護盾、鷹眼、隱藏版爆裂 |
| `onTick` | HUD 每 0.5 秒更新時 | 鷹眼（持續偵測）、魔心護盾（補發光） |
| `onCleanup` | 中斷、死亡、過關、換圖、回合重開、卸載 | 隱藏版爆裂、魔心護盾、淨化 |
| `onTakeDamage` | 玩家受傷 | 魔心護盾 |
| `onPrecache` | `OnMapStart` 預載資源 | 全部 |

其他設定：
- `SKILL_PASSIVE`：被動技能（魔心護盾）。
- `SKILL_HIDDEN`：不出現在選單（隱藏版爆裂）。
- `Skill_SetAlt(base, alt)`：skill2 指令施放的替代技能（爆裂 → 隱藏版爆裂）。HUD 在 MP 足夠時顯示替代技能名稱，取代現在對 `"Explosion 爆裂"` 的字串比對。

規則：
- 技能檔不能修改 `Skill_State`，也不能碰框架的持續／冷卻 timer handle。#13 這類 bug 因此從結構上不會再發生。
- 新增技能只需要新增一個檔案，再加一行註冊。

## 延遲步驟排程設計（第 2 步）

`Skill_Schedule(client, delay, step)` 由框架建立並追蹤 timer：

1. 用 `CreateDataTimer`，DataPack 由 SourceMod 自動釋放。
2. DataPack 記錄 userid、本次施放序號、slot、步驟函式。
3. timer handle 記在該玩家的待執行清單。
4. timer 觸發時，第一件事是依 slot 把自己從清單移除。不能靠 userid 找 slot，玩家斷線時會找不到，這正是 `1549b88` 修的淨化 bug。
5. 確認玩家還在、施放序號沒變，才執行步驟函式。
6. 需要取消時，框架一次刪除清單內所有 timer，並把施放序號加一。

配套做法：
- 步驟需要的資料（例如瞄準座標）存在技能檔自己的 `static` 陣列，不用 DataPack。同一個玩家同時只會有一次施放。
- 單純「N 秒後刪掉 entity」改用 entity I/O（`OnUser1 !self:Kill::N:-1`），交給引擎處理。
- 0 秒延遲（`CreateTimer(0.0, ...)`）改成直接呼叫或 `RequestFrame`。

取消時機：
- **第 2 步（維持現狀）：** 只有隱藏版爆裂的延遲步驟會在換圖、回合重開、過關時取消，這是現在 `CleanupEXSkill` 的行為。其他技能的延遲步驟照樣觸發。斷線玩家的步驟直接略過，現在這種情況會報錯，屬於錯誤修正，不算行為改變。
- **第 3 步：** 所有延遲步驟改成施法者死亡、換圖時取消。

## 執行步驟

### 第 1 步：搬家 + 新語法（不改邏輯）

| 新檔案 | 內容來源 |
|--------|----------|
| `main.sp` | `myinfo`、`OnPluginStart`、`OnMapStart`，以及原本在 `l4d_dissolve_infected.sp` 的 `AskPluginLoad2`、`OnLibraryAdded/Removed`、`OnConfigsExecuted`、`OnPluginEnd`、`OnMapEnd`；`OnClient*`、`OnEntityDestroyed`、left4dhooks forward |
| `config.sp` | `skills_mk2.sp` 開頭的 `#define` |
| `util.sp` | `IsPlayer`、`IsInf`、`IsWitch`、`IsAliveSpecialInf` 等判斷；`GetAimOrigin`、`GetEntityWorldOrigin`、距離計算；`SafeDeleteTimer`；`DealDamage`（原 `damage.sp`）；`StripAndExecuteClientCommand` |
| `core/globals.sp` | core/ 與 skills/ 之間互相使用的全域狀態（玩家狀態、MP、技能狀態與註冊表、`State_ManaShield`）。只在單一檔案用到的狀態留在該檔並加 `static` |
| `core/skill_base.sp` | `RegisterSkill`、`Init_Skill`、`Delete_Skill`、`Skill_Trigger`、`Skill_Change` 與選單、`Interrupt_Skill`、`Timer_Skill_Null_End/Ready`、各種 cleanup（暫時 `newdecls optional`） |
| `core/player.sp` | 連線狀態、`Event_StateTransition`、gameinstructor 事件、`Invulnerable` 與 `OnTakeDamage` hook、left4dhooks 無敵處理 |
| `core/mp.sp` | `MP_Increase/Decrease`、回復 timer、`Event_MPleech`、`Event_MPGain`、腎上腺素 |
| `core/hud.sp` | `Skill_Notify`、`Skill_Notify_MPbar`、`Skill_Notify_Ani` |
| `core/commands.sp` | `Event_SkillStateTransition`、`Cmd_SkillsFillAllMP`、指令註冊 |
| `core/precache.sp` | `Setup_Materials`、`SetupMaterial` |
| `fx/particle.sp` | `PrecacheParticle`、`CreateParticle(Ent)`、`ParticleFollow`、`KillParticleRef`、`DeleteParticles` |
| `fx/glow.sp` | `GlowForSecs`、`UnGlow`、`Timer_Unglow`、`Event_DeathUnglow` |
| `fx/timescale.sp` | `SlowForSecs`、`RestoreTimeScale`、`time_weight` |
| `fx/screen.sp` | `Fade`、`Shake`、`StaggerClient` |
| `fx/magic_circle.sp` | 腳下魔法陣全部 |
| `fx/atmosphere.sp` | `magic_atmosphere.sp` |
| `lib/weapons.sp` | 武器名稱翻譯、`DropWeapon`、彈藥存取、`ForceWeaponDrop(BySlot)`、`SetItemToPlayer`、`OnWeaponDrop` forward |
| `lib/dissolve.sp` | `l4d_dissolve_infected.sp`（forward 移到 `main.sp`）、`Turn_Undead` |
| `lib/resourcemanager.sp` | `resourcemanager.sp` |
| `skills/explosion.sp` | 爆裂 start、`ExplodeAim`、`Timer_ExplodeAimDelay`、`ComputeExploDmg`、`PropaneAtPos` |
| `skills/explosion_ex.sp` | 隱藏版爆裂 start/end/ready、`NukeExplosion`、`ShockWave`、`ThrowEntity`、`CleanupEXSkill`、`SpawnExDynamicLight`、`MagicActivates` |
| `skills/mana_shield.sp` | 護盾 start/end、`DmgReduce`、近戰揮空 detour（gamedata `l4d2_melee_range`） |
| `skills/eagle_eye.sp` | 鷹眼 start/end、`DetectInfect` |
| `skills/steal.sp` | 偷竊、掉落表 `g_sWeapons`、`CheckStealType` |
| `skills/turn_undead.sp` | 淨化 start、瞄準延遲、屍潮 timer |

其他工作：
- [x] 刪除死碼（都沒有呼叫處）：`FreezeForSecs`、`Timer_Unfreeze`、`State_Freeze`、`Freeze_Timer`、`Event_DmgInflicted`、`Event_PlayerAFK`、`GetEntityEntityDistance`。
- [x] 刪除 `damage.sp` 裡跟 `sdkhooks.inc` 重複的 `DMG_*` 定義（抽查過數值一致），消除 30 個 redefinition warning。
- [x] 搬完後刪除舊檔：`skills_mk2.sp`、`l4d_dissolve_infected.sp`、`magic_atmosphere.sp`、`resourcemanager.sp`、`damage.sp`。
- [x] `HookEvent` 註冊順序維持原樣。同一事件有多個 hook 時依註冊順序呼叫，例如 `player_death` 是 `Event_StateTransition` → `Event_MPleech` → `Event_DeathUnglow`。
- [x] 技能註冊順序維持原樣。`Skill[client]` 存的是索引，而且隱藏版爆裂必須是最後一個。
- [x] `round_start` 的技能清理暫時維持由 dissolve 的 `Event_RoundStart` 呼叫（依賴反向的問題留到第 3 步）。
- [x] README 的編譯指令改成新路徑。
- [x] 驗收：編譯成功、不新增 warning（33 個降到 1 個，剩下的是第三方 `ammo.inc` 原本就有的）。
- [x] 驗收：用比對腳本確認 165 個同名函式正規化後內容相同，其餘差異都是本步刻意的等價轉換（forward 改成分派、`KillTimer` 改 `delete`、補上回傳值）。
- [x] 驗收：用 `tools/servertest` 在本機 dedicated server 自動測試（不需要人進遊戲，見「自動測試」）。冒煙測試（開機後第一次載入、換圖、reload、unload/load）全部通過；bot 技能測試跟 0.7 比對 272 個檢查點，只有 3 項時間／物理雜訊（MP 回復的時間點、慢動作還原用的 entity 存活的 0.5 秒、受傷前的血量）。視覺、音效、真人連線流程還沒驗證，留到重構完成後一次人工測試。

第 1 步實作時的等價轉換（不改變遊戲行為）：
- `KillTimer(x)`、`CloseHandle(x)` 改成 `delete x`（`delete` 會順便把變數歸零）。
- 原本沒寫回傳值的 timer callback 補上回傳值：一次性 timer 回 `Plugin_Stop`；重複 timer（`Skill_Notify`、`Skill_Notify_Ani`、`Skill_MPrecover`）回 `Plugin_Continue`，跟原本隱含的回傳值 0 相同。
- 技能檔內部使用的狀態改成 `static`，其他檔案需要操作時改用函式：`TurnUndead_KillRushTimer`、`ManaShield_RestoreMeleeRange`、`ExplosionEx_InitState`。
- `#tryinclude "ResourceManager"` 與 `#tryinclude <LMCCore>` 移到 `main.sp` 的第三方 include 區，避免伺服器上若有舊語法的同名檔案時，在 newdecls 下編譯失敗。

### 第 2 步：技能框架 + 排程器 + 移植 6 個技能

- [ ] 用框架改寫 `core/skill_base.sp`（轉新語法），新增 `core/scheduler.sp`。
- [ ] 6 個技能一次移植完。狀態機只能有一套，不讓新舊並存。
- [ ] 移除技能名稱字串比對（`Skill_Notify`、`Skill_Notify_MPbar`、skill2 指令）。
- [ ] 隱藏版爆裂改成 `SKILL_HIDDEN` + 爆裂的 alt，移除 `Skill_EX_Using`、`hiddenExplosionNum`、`skill_num-1` 這類特例。
- [ ] 魔心護盾改成 `SKILL_PASSIVE` + `onTakeDamage` + `onTick`。
- [ ] `Setup_Materials` 拆進各技能的 `onPrecache`，移除 `core/precache.sp`。
- [ ] 五份重複的清理（換圖、回合重開、卸載、reload、中斷）改由框架依原因分派 `onCleanup`。
- [ ] 各技能的 DataPack 改成排程器加 `static` 陣列。
- [ ] 行為維持不變的重點：
  - skill2 照舊不檢查冷卻，第 3 步才修。
  - 延遲步驟的取消時機照「延遲步驟排程設計」裡的第 2 步規則。
- [ ] 驗收：編譯成功，並跑完伺服器測試清單。

### 第 3 步：修 bug（每項一個 commit）

- [ ] 延遲步驟在施法者死亡、換圖時取消（決定 #5）。回合重開是否也要取消，實作時再確認。
- [ ] 施放隱藏版爆裂中死亡或斷線時，`Interrupt_Skill` 刪掉了持續／冷卻 timer，`Timer_Skill_EX_End/Ready` 不會執行，`Invulnerable` 和 `Skill_EX_Using` 都不會重置。復活後 MP 會一直被歸零（`Skill_Notify_MPbar` 在無敵時把 MP 設為 0），一般爆裂也會改走隱藏版的計時。（讀碼推論，待實測）
- [ ] skill2 不檢查冷卻：一般爆裂施放中或冷卻中仍能放隱藏版，兩組 timer 會互相覆蓋。
- [ ] `change_skill` 的判斷用了 `Skill_Type[skill_num]`（超出註冊範圍），「技能施放中」分支永遠走不到。
- [ ] `Skill_Change` 呼叫 `TriggerTimer` 前沒檢查 null（第 2 步重寫後確認是否還存在）。
- [ ] `Timer_UndeadRush` 用 client index，放完淨化後 1 秒內斷線會報錯（第 2 步排程器上線後確認）。
- [ ] `round_start` 的技能清理寫在 dissolve 的 `Event_RoundStart` 裡，只有 `l4d_dissolve_allow=1` 時才會執行；改成技能模組自己 hook。
- [ ] `Hooked[MAX_PLAYERS]` 少一格，第 18 號玩家會陣列越界。
- [ ] `Event_Draw`、`Event_NoDraw`、`CheckPlayerConnections` 的迴圈用 `i < MAX_PLAYERS`，少跑最後一位玩家。
- [ ] 移除淨化的 `[淨化DBG]` 除錯輸出。
- [ ] 合併重複函式：`IsInf` 與 `IsAliveInf` 完全相同（後者其實沒檢查是否活著）；`IsAliveSpecialInf` 與 `IsAliveSpecialInf2` 重複。
- [ ] 確認各技能的 DataPack 洩漏在第 2 步後都已消失，特別是 `NukeExplosion` 對每個 entity 各 `new` 一個 DataPack 的寫法。
- [ ] 淨化殺普通殭屍的結果取決於有沒有搶到 dissolve 槽（`lib/dissolve.sp` 的 `Turn_Undead`）。（讀碼推論，待實測）
  - 有空槽：不呼叫 `DealDamage`，只交給溶解器處理。溶解器最後那一擊的 10000 傷害被 `OnCommonDamage` 擋掉，殭屍改由溶解器 `UTIL_Remove` 或 2.5 秒後的 `Kill` 靜默移除，不會觸發 `player_death`。所以不會給全隊 0.5 MP（`Event_MPleech`），也不算施法者的擊殺。
  - 槽滿（同時超過 25 隻）：走 `DealDamage`，正常死亡，會給 MP。
  - 結果是：同一次淨化，前 25 隻普通殭屍不給 MP，第 26 隻起才給。實測確認後再決定要不要統一改成「先 `DealDamage`，再掛溶解特效」，Witch 現在就是這種寫法。
- [ ] `MAX_DISSOLVE`（25）只限制同時播放的溶解特效數量，不影響淨化殺不殺得死。要不要調高，等實測後決定。
  - 原版 changelog 寫 1.11 已經「Reverted MAX_DISSOLVE to 32」，但官方 repo `SilvDev/Dissolve_Infected` 的 1.17 程式碼還是 25。這是原作者那邊的不一致，不是我們改的。
  - changelog 說的「godmode zombies when too many die at once」，比對 1.5 和 1.17 的原始碼後判斷，成因是 1.5 的寫法：`OnCommonDamage` 擋掉**所有**傷害，而且在確認有沒有空槽**之前**就掛上去，又沒有補救的 `Kill`。槽滿或溶解器沒建成功時，殭屍就永遠打不死。
  - 1.17 用三道保護修掉了這個問題，重構時都不能拿掉：① `OnCommonDamage` 只擋溶解器那一擊（`damage == 10000.0` 且 `damagetype == 5982249`，就是 SDK `CEntityDissolve::DissolveThink` 送出的 `DMG_REMOVENORAGDOLL` 加上 `Damage_GetNoPhysicsForce()`）；② 溶解器建成功才掛 hook；③ 目標身上加 `OnUser1 !self:Kill::2.5`，溶解器提早消失也保證移除。
  - 溶解器最後一擊的攻擊者是 `UTIL_PlayerByIndex(1)`，Valve 自己的註解寫著傳 NULL 給 `TakeDamage` 會出事，這很可能就是「不擋會崩潰」的原因（推論，L4D2 的 binary 沒有驗證）。
  - 「29 隻同時溶解開始出問題」這個門檻查不到根據：AlliedModders 討論串拒絕自動讀取，GitHub 上也沒有 1.6～1.12 的版本可以比對。

### 第 4 步：收尾

- [ ] README：相依版本改成 SourceMod 1.12，補上目錄結構與新增技能的方式。
- [ ] `PLUGIN_VERSION`（目前還是 `"0.6"`）。
- [ ] 打 tag、建 release（版本號另議）。

## 重構後的待辦功能

### 多語系

- [ ] 玩家看得到的文字改用 SourceMod 翻譯檔（`translations/skills_mk2.phrases.txt`，`LoadTranslations` 加 `%t` / `%T`）。範圍包含技能名稱、技能選單、HUD 提示與 MP 條、聊天訊息、偷竊掉落與 `lib/weapons.sp` 的武器名稱。
- 前提：第 2 步的「移除技能名稱字串比對」要先完成，不然名稱翻譯後比對就會失效。
- 語言：先支援繁體中文（`zho`）、英文（`en`）、日文（`jp`），預設是繁體中文。玩家語言不在這三種裡面時（包括簡體中文 `chi`）一律顯示繁體中文。
- 注意：SourceMod 找不到玩家語言的翻譯時，會改用伺服器語言（`core.cfg` 的 `ServerLang`，預設是 `en`），所以光靠翻譯檔做不到「預設中文」。實作時再決定要由插件自己判斷玩家語言，還是在 README 請服主把 `ServerLang` 設成 `zho`。

## 伺服器測試清單（每步完成後）

- [ ] 插件載入沒有錯誤，包含伺服器剛開機、還沒載入地圖的情況。
- [ ] 6 個技能各施放一次，HUD 的施放中、冷卻倒數、魔力不足顯示都正確。
- [ ] 隱藏版爆裂：天氣、魔法陣、無敵效果，以及結束後全部恢復。
- [ ] 施放中切換技能、施放中死亡、施放中倒地。
- [ ] 隱藏版爆裂施放中換圖、投票重開回合。
- [ ] 斷線重連後，MP 條和技能都正常。
- [ ] `sm plugins reload skills_mk2` 後狀態正常。
- [ ] 伺服器 console 沒有新的 error 或 exception。
