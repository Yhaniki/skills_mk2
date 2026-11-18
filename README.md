# skills_mk2

## 依賴
- SourceMod 1.12（開發與測試用 1.12.0.7207）
- Metamod:Source 1.12（開發與測試用 1.12.0-dev+1219）
- [Left 4 DHooks Direct](https://forums.alliedmods.net/showthread.php?t=321696)
- [L4D2-Competitive-Framework](https://github.com/Attano/L4D2-Competitive-Framework)

## 編譯
+ 原始碼都在 `scripting/skills_mk2/` 資料夾內，入口是 `main.sp`
+ 進入 `sourcemod/scripting` 目錄後執行以下指令：

```
.\spcomp.exe skills_mk2/main.sp -o ../plugins/skills_mk2.smx
```

## 常用指令
```
sm plugins reload skills_mk2
sm plugins refresh skills_mk2
sm_version
meta_vertion
```

## 綁定方法
+ 技能指令
    + change_skill 技能清單
    + skill1 施放技能
    + skill2 施放隱藏版爆裂
+ 綁定
    + 遊戲內按`~`打開控制台，輸入綁定按鍵命令
    + bind "按鍵" "指令"
    + 範例
        ```
        bind "x" "change_skill"
        ```
## 目前技能
+ 爆裂: 惠惠的爆裂魔法。
+ 魔心護盾: 使用4MP抵銷1傷害，~~但用近戰武器無傷害。~~
+ 鷹眼: 時間減慢，可以偵查周圍的所有殭屍。
+ 偷竊: 可以對準殭屍或者隊友施放，隨機拿取物品。
+ 淨化: 淨化周圍殭屍，~~施放完後會吸引更多殭屍過來。~~
+ 隱藏版爆裂: 消費100MP使用skill2，施放隱藏版爆裂。施放過程中無敵，~~結束後會因魔力枯竭倒地。~~

## 原始碼結構

```
scripting/skills_mk2/
├─ main.sp              入口：插件資訊、include 順序、所有 SourceMod / left4dhooks forward 的分派
├─ config.sp            常數
├─ util.sp              通用函式（實體判斷、距離、瞄準、傷害、預載）
├─ core/
│  ├─ skill_base.sp     技能框架：註冊、施放、狀態機、切換、中斷、清理、預載
│  ├─ scheduler.sp      技能的延遲步驟排程
│  ├─ player.sp         玩家狀態、受傷 hook、無敵
│  ├─ mp.sp             MP 增減、回復、腎上腺素
│  ├─ hud.sp            技能提示文字與 MP 條
│  └─ commands.sp       skill1 / skill2 / change_skill / drop / fix / sm_skills_fillmp
├─ fx/                  效果：粒子、發光、慢動作、畫面震動、腳下魔法陣、天氣
├─ lib/                 武器、Dissolve Infected、ResourceManager
├─ skills/              一個技能一個檔案
└─ test/                自動測試用的測試版入口與測試腳本（正式版不會包含）
```

## 新增技能

1. 在 `skills/` 新增一個檔案，例如 `skills/fireball.sp`：

    ```sourcepawn
    // 火球 Fireball：1 秒後在瞄準位置爆炸
    static int s_iFireball;

    int Fireball_Register()
    {
        // 名稱、持續秒數、冷卻秒數、MP 消耗
        s_iFireball = Skill_Register("Fireball 火球", 3.0, 5.0, 25.0);
        Skill_OnStart(s_iFireball, Fireball_OnStart);
        Skill_OnPrecache(s_iFireball, Fireball_OnPrecache);
        return s_iFireball;
    }

    static void Fireball_OnPrecache()
    {
        SetupMaterial("sound\\skills\\fireball.mp3");
        SetupSound("skills\\fireball.mp3", true);
    }

    static void Fireball_OnStart(int client)
    {
        float pos[3];
        if (GetAimOrigin(client, pos, 10.0) == 0) return;
        PrintToChatAll("\x04%N \x01Fireball!", client);

        // 延遲步驟交給框架排程；步驟需要的資料寫在回傳的 DataPack
        DataPack data = Skill_Schedule(s_iFireball, client, 1.0, Fireball_StepBlast);
        data.WriteFloat(pos[0]);
        data.WriteFloat(pos[1]);
        data.WriteFloat(pos[2]);
    }

    static void Fireball_StepBlast(int client, DataPack data)
    {
        float pos[3];
        pos[0] = data.ReadFloat();
        pos[1] = data.ReadFloat();
        pos[2] = data.ReadFloat();
        PropaneAtPos(pos);
    }
    ```

2. 在 `main.sp` 的 `skills/` include 區加上 `#include "skills/fireball.sp"`，並在 `OnPluginStart` 的技能註冊區最後加一行 `Fireball_Register();`。註冊順序就是選單順序。

技能檔只要實作用得到的 hook：

| hook | 時機 |
|------|------|
| `Skill_OnStart` | 施放時（被動技能是啟用時） |
| `Skill_OnEnd` | 持續時間結束，或被動技能被切換掉 |
| `Skill_OnTick` | HUD 每 0.5 秒更新時（目前選用的技能） |
| `Skill_OnCleanup` | 中斷、過關、換圖、回合重開、reload、卸載（原因見 `SkillCleanup`） |
| `Skill_OnTakeDamage` | 玩家受傷時 |
| `Skill_OnPrecache` | 載入地圖時預載資源 |

其他設定：`Skill_Register` 的最後一個參數可以給 `SKILL_PASSIVE`（被動技能，選用時就啟用）或 `SKILL_HIDDEN`（不出現在選單）；`Skill_SetAlt(技能, 替代技能)` 設定 skill2 施放的替代技能（爆裂 → 隱藏版爆裂）。技能狀態由框架管理，技能檔只能用 `Skill_GetState` 讀取。

施法者死亡、斷線、過關、換圖、回合重開時，框架會取消還沒觸發的延遲步驟。

## 自動測試

`tools/servertest/` 會在本機的 L4D2 dedicated server 上自動測試，不需要進遊戲（需要 Python 3）。伺服器資料夾用 `--server` 或環境變數 `L4D2_SERVER_DIR` 指定。

```
# 插件生命週期：開機、換圖、reload、unload/load
python tools/servertest/servertest.py smoke --smx 要測的.smx --out 輸出資料夾

# 用 bot 跑技能：先編譯測試版（在 sourcemod/scripting 底下）
.\spcomp.exe skills_mk2/test/main_test.sp -o skills_mk2_test.smx
python tools/servertest/servertest.py skills --smx skills_mk2_test.smx --out 輸出資料夾

# 比對兩次 skills 的結果（例如修改前後）
python tools/servertest/compare.py 修改前的輸出資料夾 修改後的輸出資料夾
```

測試期間會暫時換掉伺服器的 `plugins/skills_mk2.smx`，結束後還原；伺服器只綁 `127.0.0.1:27115`。粒子、魔法陣、天氣、HUD 外觀、音效、近戰揮空還是要進遊戲看。

## 開發中
- [x] 惠惠：升級原本的爆裂技能（施放過程中改變天氣狀態）
- [x] 和真：偷竊 → 偷取隊友或者殭屍的物品（完成）
- [x] 阿克婭：淨化 → 殺死周圍殭屍（完成）
- [x] 達克尼斯：魔心護盾（完成）

![人物模型圖片](https://steamuserimages-a.akamaihd.net/ugc/2050869154880058882/DBD4D61BC104B63608AF593F81527625CB9EDBCC/?imw=5000&imh=5000&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=false)
