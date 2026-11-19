// skills_mk2 自動測試腳本
//
// 只會編進測試版（test/main_test.sp），正式版不包含這個檔案。
// 由 tools/servertest/servertest.py skills 透過 RCON 下 `sm_skilltest <階段>` 驅動，
// 結果寫到 addons/sourcemod/logs/skills_test.log，再用 tools/servertest/compare.py 跟基準版比對。
//
// 測試用 bot 施放技能。測試版入口把 IsFakeClient 換成永遠回傳 false 的版本，
// 所以技能系統會把 bot 當成真人處理；PrintHintText / PrintToChat(All) 也換成會記 log 的版本。
//
// 這個檔案讀技能系統的狀態：Skill_GetCurrent()、Skill_GetState()、Skill_MP、Invulnerable、
// State_ManaShield、State_Slow、State_Player，並呼叫 Skill_Change() 與受傷 hook Event_Hurt。
// 重構時若改了這些名稱，要同步修改這裡；0.7 的基準版沒有前兩個函式，由它的測試版入口補上。

#pragma semicolon 1
#pragma newdecls required

#define TEST_BOTS 4
#define TEST_MAX_COMMONS 128

static char  s_sLog[PLATFORM_MAX_PATH];
static int   s_iBot[TEST_BOTS];
static float s_vHome[TEST_BOTS][3];
static char  s_sPhase[32];
static char  s_sScen[48];
static int   s_iLine;
static char  s_sHint[MAXPLAYERS + 1][256];

// dissolve 階段：測試生出來的普通殭屍、施法者、普通殭屍的 player_death 次數（Event_MPleech 就是靠這個事件給 MP）
static int   s_iCommon[TEST_MAX_COMMONS];
static int   s_iCommonN;
static int   s_iPurifier;
static int   s_iInfDeaths;
static int   s_iInfDeathsBy;

// 偷女巫：測試生出來的女巫（reference）、生女巫的 bot、witch_harasser_set 的次數與最後驚嚇她的人
static int   s_iWitch = INVALID_ENT_REFERENCE;
static int   s_iWitchCaster;
static int   s_iHarassN;
static int   s_iHarasser;

// 近戰：hold 的 bot 不移動、固定視角、只照劇本揮刀；揮刀次數、近戰判定次數、畫面中央文字的次數
static bool  s_bHold[MAXPLAYERS + 1];
static float s_vHoldAng[MAXPLAYERS + 1][3];
static int   s_iSwingTicks[MAXPLAYERS + 1];
static float s_fSwingId[MAXPLAYERS + 1];
static int   s_iSwingN[MAXPLAYERS + 1];
static int   s_iMeleeCalls[MAXPLAYERS + 1];
static int   s_iCenterN[MAXPLAYERS + 1];
static Handle s_hMeleeDetour;

//===========================================================
//========================= 劇本 ============================
//===========================================================
// 指令：
//   scen 名稱            開始一個情境（之後的 log 都標上這個名稱）
//   home                 記下目前 bot 的位置，prep / respawn 會傳回這裡
//   findbots             重新找 bot（換圖、踢人之後），並幫 bot 掛上受傷 hook
//   prep                 所有 bot：死了就復活、倒地就救起、回到原位、補滿血、看向地板
//   mp <k|all> <值>      設定 MP
//   cmd <k> <指令>       讓 bot 執行指令（skill1 / skill2 / change_skill …）
//   change <k> <技能>    Skill_Change（選單選擇技能）
//   dmg <k> <傷害>       對 bot 造成傷害（攻擊者是世界，會經過受傷 hook，跟殭屍攻擊一樣），記下前後血量
//   face <k> <t>         把 bot t 移到 bot k 面前並讓 k 瞄準 t（偷竊隊友要瞄得準，結果才固定）
//   rescue <k>           除了 k 以外的 bot：死了就復活、倒地就救起、回到原位（隱藏版爆裂會炸倒所有隊友，
//                        不救起來的話施法者結束時倒地 → 全員倒地 → 任務失敗、回合重開）
//   kill <k> / respawn <k> / revive <k> / kick <k> / addbot
//   bw <k>               讓 bot 進入黑白狀態（倒地次數到上限，再倒地就會死）；prep 會清掉
//   hp <k> <值>          設定血量（倒地時是倒地血量）
//   restart              投票重開回合（L4D_RestartScenarioFromVote）
//   cvar <名稱> <值>     設定 cvar（可以設 cheat cvar）
//   cvarreset <名稱>     cvar 恢復預設值
//   commons <k> <n>      在 bot k 周圍 80～600 單位的地板上生 n 隻普通殭屍，並把 k 記成施法者、死亡計數歸零
//   purify <k>           對每一隻生出來的普通殭屍呼叫 Turn_Undead（跟淨化第 2.5 秒的步驟一樣），攻擊者是 bot k
//   killcommons <k>      用一般傷害打死每一隻生出來的普通殭屍（不經過淨化），攻擊者是 bot k
//   dcount <名稱>        記錄生出來的普通殭屍還剩幾隻、溶解器數量、普通殭屍的 player_death 次數、b1 的 MP
//   witch <k>            在 bot k 前方的地板生一隻女巫（盡量離 200 單位），女巫被驚嚇的次數歸零
//   aimwitch <k>         讓 bot k 瞄準女巫的身體中心
//   wcount <名稱>        記錄女巫還在不在、血量、怒氣、生女巫的 bot 是否瞄著她、被驚嚇幾次、最後是誰驚嚇她
//   killwitch            刪掉女巫
//   give <k> <物品>      給 bot 物品並切換過去
//   melee <k> <名稱>     給 bot 近戰武器（fireaxe、katana…）並切換過去
//   approach <k> <距離>  把 bot k 移到女巫前方「距離」單位、瞄準女巫，並 hold
//   hold <k>             bot k 不移動、固定目前的視角、不按任何按鍵（只照劇本揮刀）；prep 會解除
//   swing <k>            bot k 揮一刀（按住攻擊鍵 4 個 tick，要先 hold）
//   mcount <k> <名稱>    記錄 bot k 揮了幾刀、近戰判定被呼叫幾次、畫面中央文字幾次、女巫血量、melee_range（記完歸零）
//   weapons <k> <名稱>   記錄 bot 每一格的武器、手上的武器、主武器備用彈藥，以及 150 單位內地上沒人拿的武器
//   cp <名稱>            記錄檢查點（每個 bot 的技能狀態與 HUD 文字）
//   wait <秒>            等待
//
// 技能編號：0 爆裂、1 魔心護盾、2 鷹眼、3 偷竊、4 淨化（5 是隱藏版爆裂，只能用 skill2）
// 時間：爆裂 3+2 秒、鷹眼 7+2、偷竊 6+2、淨化 3.5+2、隱藏版爆裂 27+2（持續+冷卻）
// 檢查點都放在兩個事件中間，至少留 0.3 秒誤差。

static char s_sMain[][] =
{
	"home",
	"scen init",
	"prep",
	"mp all 100",
	"wait 1.0",
	"cp ready",

	// 爆裂：施放 → 施放中再按 → 冷卻中再按 → 準備好
	"scen explosion",
	"cmd 0 skill1",
	"wait 0.3",
	"cp act",
	"cmd 0 skill1",
	"wait 3.2",
	"cp cd",
	"cmd 0 skill1",
	"wait 2.0",
	"cp rdy",

	// 魔力不足
	"scen no_mp",
	"mp 0 10",
	"cmd 0 skill1",
	"wait 0.5",
	"cp after",

	// skill2 的條件：MP 不到 100、目前技能不是爆裂
	"scen skill2_conditions",
	"mp 0 50",
	"cmd 0 skill2",
	"wait 0.5",
	"cp lowmp",
	"mp 1 100",
	"change 1 2",
	"wait 0.3",
	"cp changed",
	"cmd 1 skill2",
	"wait 2.5",
	"cp rdy",

	// 鷹眼（慢動作 6 秒）
	"scen eagle_eye",
	"mp 1 100",
	"cmd 1 skill1",
	"wait 0.3",
	"cp act",
	"wait 6.05",
	"cp slow_end",
	"wait 1.25",
	"cp cd",
	"wait 2.0",
	"cp rdy",

	// 偷竊：瞄準隊友 b0，偷走他手上的武器
	"scen steal",
	"mp 2 100",
	"change 2 3",
	"wait 2.5",
	"cp rdy0",
	"face 2 0",
	"cmd 2 skill1",
	"wait 0.3",
	"cp act",
	"wait 5.2",
	"cp stolen",
	"wait 1.0",
	"cp cd",
	"wait 2.0",
	"cp rdy",
	"prep",

	// 淨化：2.5 秒後淨化，再 1 秒後引來屍潮
	"scen turn_undead",
	"mp 3 100",
	"change 3 4",
	"wait 2.5",
	"cmd 3 skill1",
	"wait 0.3",
	"cp act",
	"wait 2.5",
	"cp aimed",
	"wait 1.2",
	"cp rush",
	"wait 2.0",
	"cp rdy",

	// 魔心護盾（被動）：MP 夠就抵銷傷害，不夠就照常受傷
	"scen mana_shield",
	"change 0 1",
	"wait 0.5",
	"cp on",
	"mp 0 100",
	"dmg 0 10",
	"wait 0.3",
	"cp absorbed",
	"mp 0 5",
	"dmg 0 10",
	"wait 0.3",
	"cp not_enough",
	"mp 0 100",
	"change 0 0",
	"wait 0.3",
	"cp off",
	"wait 2.5",
	"cp rdy",
	"prep",

	// 施放中切換技能
	"scen change_mid_cast",
	"mp 0 100",
	"cmd 0 skill1",
	"wait 0.5",
	"cp act",
	"change 0 2",
	"wait 0.3",
	"cp changed",
	"wait 2.5",
	"cp rdy",
	"change 0 0",
	"wait 2.5",
	"cp back",

	// 施放中倒地
	"scen incap_mid_cast",
	"mp 0 100",
	"cmd 0 skill1",
	"wait 0.5",
	"dmg 0 300",
	"wait 0.5",
	"cp incapped",
	"cmd 0 skill1",
	"wait 4.5",
	"cp rdy",
	"revive 0",
	"wait 0.5",
	"cp revived",
	"prep",

	// 施放中死亡（b1 目前是鷹眼）
	"scen death_mid_cast",
	"mp 1 100",
	"cmd 1 skill1",
	"wait 0.5",
	"kill 1",
	"wait 0.5",
	"cp dead",
	"cmd 1 skill1",
	"wait 0.3",
	"respawn 1",
	"wait 1.0",
	"cp respawned",
	"wait 6.0",
	"cp later",
	"prep",

	// 隱藏版爆裂完整流程：24 秒爆炸（會炸死其他 bot）、27 秒結束後施法者倒地
	"scen ex",
	"mp 0 100",
	"wait 0.6",
	"cp before",
	"cmd 0 skill2",
	"wait 0.3",
	"cp act",
	"dmg 0 50",
	"wait 0.3",
	"cp invuln_dmg",
	"cmd 0 skill1",
	"wait 24.0",
	"cp nuke",
	"rescue 0",
	"wait 2.9",
	"cp end",
	"wait 2.0",
	"cp rdy",
	"revive 0",
	"prep",
	"wait 1.0",
	"cp after",

	// 隱藏版爆裂施放中死亡（PLAN 第 3 步：無敵與 EX 狀態可能不會重置）
	"scen ex_death",
	"mp 0 100",
	"cmd 0 skill2",
	"wait 2.0",
	"kill 0",
	"wait 0.5",
	"cp dead",
	"respawn 0",
	"wait 1.0",
	"cp respawned",
	"wait 22.0",
	"rescue 0",
	"wait 1.0",
	"cp after_nuke",
	"prep",
	"mp 0 100",
	"wait 1.0",
	"cp mp_set",
	"cmd 0 skill1",
	"wait 3.5",
	"cp cast_after",
	"wait 27.0",
	"cp later",
	"revive 0",
	"prep",
	"wait 3.0",
	"cp final",

	// 淨化後 1 秒內斷線（Timer_UndeadRush 用的是 client index）
	"scen kick_turn_undead",
	"mp 3 100",
	"cmd 3 skill1",
	"wait 2.8",
	"kick 3",
	"wait 2.0",
	"cp kicked",
	"addbot",
	"wait 5.0",
	"findbots",
	"prep",
	"wait 1.0",
	"cp newbot",

	// 施放中、冷卻中用 skill2，施放中開技能選單（第 3 步起會被擋下並提示）
	"scen cast_guards",
	"mp 0 100",
	"cmd 0 skill1",
	"wait 0.3",
	"mp 0 100",
	"cmd 0 skill2",
	"cmd 0 change_skill",
	"wait 0.3",
	"cp act",
	"wait 3.0",
	"mp 0 100",
	"cmd 0 skill2",
	"wait 0.3",
	"cp cd",
	"wait 2.0",
	"cp rdy",
};

// 換圖、reload、重開回合之前：b0 施放隱藏版爆裂，3 秒後交給 servertest.py
static char s_sExPrep[][] =
{
	"findbots",
	"scen ex_prep",
	"prep",
	"mp 0 100",
	"cmd 0 skill2",
	"wait 3.0",
	"cp casting",
};

// reload 或換圖之後：確認狀態已清乾淨，而且原本 24 / 27 秒的延遲步驟不會再觸發
static char s_sAfter[][] =
{
	"findbots",
	"home",
	"scen after",
	"wait 1.0",
	"cp start",
	"wait 27.0",
	"cp later",
	"prep",
	"mp 0 100",
	"cmd 0 skill1",
	"wait 0.3",
	"cp cast",
	"wait 5.5",
	"cp rdy",
};

// 隱藏版爆裂施放中投票重開回合
static char s_sExRestart[][] =
{
	"findbots",
	"scen ex_restart",
	"prep",
	"mp 0 100",
	"cmd 0 skill2",
	"wait 3.0",
	"cp casting",
	"restart",
	"wait 12.0",
	"findbots",
	"home",
	"cp after_restart",
	"wait 15.0",
	"cp later",
	"prep",
	"mp 0 100",
	"cmd 0 skill1",
	"wait 0.3",
	"cp cast",
	"wait 5.5",
	"cp rdy",
};

// 隱藏版爆裂的施法者在施放中被打倒或打死的情況（指令只擋死亡與過關，倒地、黑白都能施放）
// 測試 bot 看著腳下，爆炸點就在施法者腳邊。爆炸在第 24 秒，持續時間在第 27 秒結束
// prep 後先等 1 秒：剛被救起來馬上受到的傷害會被遊戲忽略，倒地不了
static char s_sExDown[][] =
{
	"findbots",
	"home",
	// 倒地時施放（倒地血量 300）
	"scen ex_incap_cast",
	"prep",
	"wait 1.0",
	"mp 0 100",
	"dmg 0 300",
	"wait 0.5",
	"cp incapped",
	"cmd 0 skill2",
	"wait 0.3",
	"cp act",
	"wait 23.4",
	"cp pre_nuke",
	"wait 0.6",
	"cp nuke",
	"rescue 0",
	"wait 2.9",
	"cp end",
	"wait 2.0",
	"cp rdy",
	"prep",
	"wait 1.0",
	"cp after",

	// 倒地時施放，倒地血量只剩 60
	"scen ex_incap_low",
	"prep",
	"wait 1.0",
	"mp 0 100",
	"dmg 0 300",
	"wait 0.5",
	"hp 0 60",
	"cp incapped",
	"cmd 0 skill2",
	"wait 0.3",
	"cp act",
	"wait 23.4",
	"cp pre_nuke",
	"wait 0.6",
	"cp nuke",
	"rescue 0",
	"wait 2.9",
	"cp end",
	"wait 2.0",
	"cp rdy",
	"prep",
	"wait 1.0",
	"cp after",

	// 黑白（倒地次數到上限，再倒地就會死）時施放
	"scen ex_bw_cast",
	"prep",
	"wait 1.0",
	"bw 0",
	"mp 0 100",
	"cmd 0 skill2",
	"wait 0.3",
	"cp act",
	"wait 23.4",
	"cp pre_nuke",
	"wait 0.6",
	"cp nuke",
	"rescue 0",
	"wait 2.9",
	"cp end",
	"wait 2.0",
	"cp rdy",
	"prep",
	"wait 1.0",
	"cp after",
};

// 淨化殺普通殭屍時 dissolve 槽（MAX_DISSOLVE）的影響。nb_stop 讓殭屍和 bot 都不動，避免 bot 先把殭屍打死
// 前三個情境直接呼叫 Turn_Undead，最後一個實際施放淨化（b3 看著腳下，淨化中心在腳邊）
static char s_sDissolve[][] =
{
	"findbots",
	"home",
	"prep",
	"cvar nb_stop 1",
	"cvar nb_blind 1",

	"scen dissolve_10",
	"commons 3 10",
	"wait 1.0",
	"mp 1 0",
	"dcount spawned",
	"purify 3",
	"dcount t0",
	"wait 0.5",
	"dcount t0.5",
	"wait 0.5",
	"dcount t1",
	"wait 1.0",
	"dcount t2",
	"wait 1.0",
	"dcount t3",
	"wait 1.0",

	"scen dissolve_40",
	"commons 3 40",
	"wait 1.0",
	"mp 1 0",
	"dcount spawned",
	"purify 3",
	"dcount t0",
	"wait 0.5",
	"dcount t0.5",
	"wait 0.5",
	"dcount t1",
	"wait 1.0",
	"dcount t2",
	"wait 1.0",
	"dcount t3",
	"wait 1.0",

	"scen dissolve_100",
	"commons 3 100",
	"wait 1.0",
	"mp 1 0",
	"dcount spawned",
	"purify 3",
	"dcount t0",
	"wait 0.5",
	"dcount t0.5",
	"wait 0.5",
	"dcount t1",
	"wait 1.0",
	"dcount t2",
	"wait 1.0",
	"dcount t3",
	"wait 1.0",

	"scen purify_cast_40",
	"change 3 4",
	"wait 2.5",
	"prep",
	"commons 3 40",
	"wait 1.0",
	"mp 1 0",
	"mp 3 100",
	"dcount spawned",
	"cmd 3 skill1",
	"wait 2.8",
	"dcount t0.3",
	"wait 0.7",
	"dcount t1",
	"wait 2.0",
	"dcount t3",

	// 對照：不是淨化殺的普通殭屍照常給全隊 MP
	"scen normal_kill_10",
	"commons 3 10",
	"wait 1.0",
	"mp 1 0",
	"dcount spawned",
	"killcommons 3",
	"dcount t0",
	"wait 1.0",
	"dcount t1",

	"cvar nb_stop 0",
	"cvar nb_blind 0",
};

// 偷女巫：瞄準女巫施放偷竊，第 5.2 秒偷到物品，同時施法者對女巫造成 1 點傷害（血量 1000 → 999）
// 測不到「女巫被嚇醒」：施法者是 bot，bot 造成的傷害（SDKHooks、point_hurt、真的開槍都試過）不會嚇醒女巫，
// 正式版只有真人能施放技能，驚嚇要進遊戲確認。wcount 的 harassed 在這裡會是 0。
// 其他 bot 站在附近時女巫的怒氣會慢慢累積到自己醒來，所以把怒氣累積速度設成 0，避免情境之間互相影響
static char s_sStealWitch[][] =
{
	"findbots",
	"home",
	"prep",
	"cvar z_witch_anger_rate 0",
	"change 2 3",
	"wait 2.5",

	// 先對照：瞄著女巫 6 秒不施放，女巫不應該醒（排除 bot 站太近就把她嚇醒的情況）
	"scen steal_witch",
	"mp 2 100",
	"witch 2",
	"wait 1.0",
	"aimwitch 2",
	"wcount spawned",
	"wait 6.0",
	"aimwitch 2",
	"wcount idle",
	"cmd 2 skill1",
	"wait 0.3",
	"cp act",
	"wait 4.6",
	"wcount t4.9",
	"weapons 2 t4.9",
	"wait 0.6",
	"wcount t5.5",
	"weapons 2 t5.5",
	"cp stolen",
	"killwitch",
	"wait 2.5",
	"prep",
	"wait 1.0",

	// 偷到之前女巫就消失了：照樣偷到東西，也不會出錯
	"scen steal_witch_gone",
	"mp 2 100",
	"witch 2",
	"wait 1.0",
	"aimwitch 2",
	"cmd 2 skill1",
	"wait 2.0",
	"killwitch",
	"wait 3.5",
	"wcount t5.5",
	"cp stolen",
	"wait 2.5",
	"prep",
	"cvarreset z_witch_anger_rate",
};

// 丟槍：skills_mk2 不再處理 drop（下了沒反應），改用伺服器上社群插件 l4d_drop 的 sm_drop
// （伺服器沒裝 l4d_drop 的話 sm_drop 也丟不掉，這個階段的結果就沒有意義）
static char s_sDrop[][] =
{
	"findbots",
	"home",
	"prep",
	"scen drop_cmd",
	"give 0 weapon_smg",
	"wait 2.0",
	"weapons 0 given",
	"cmd 0 drop",
	"wait 1.0",
	"weapons 0 after",

	"scen sm_drop",
	"cmd 0 sm_drop",
	"wait 1.0",
	"weapons 0 after",

	// 雙手手槍：丟一把、留一把
	"scen sm_drop_dual",
	"give 0 weapon_pistol",
	"give 0 weapon_pistol",
	"wait 2.0",
	"weapons 0 given",
	"cmd 0 sm_drop",
	"wait 1.0",
	"weapons 0 after",
	"prep",
};

// 近戰：魔心護盾開啟時近戰揮空（女巫不扣血）、一刀只顯示一次 MISS、護盾玩家客戶端的 melee_range
// bot 被測試腳本 hold 住，只照劇本揮刀；女巫的怒氣累積與「靠太近就驚醒」（預設 100 單位）都關掉
static char s_sMelee[][] =
{
	"findbots",
	"home",
	"prep",
	"cvar z_witch_anger_rate 0",
	"cvar z_witch_personal_space 0",
	"melee 0 fireaxe",
	"wait 1.5",
	"weapons 0 melee",

	// 沒有護盾：砍得到女巫
	"scen melee_normal",
	"change 0 0",
	"wait 0.5",
	"witch 0",
	"wait 1.0",
	"approach 0 45",
	"wait 0.5",
	"mcount 0 start",
	"swing 0",
	"wait 1.5",
	"swing 0",
	"wait 1.5",
	"mcount 0 after",
	"wcount after",
	"killwitch",
	"prep",
	"wait 0.5",

	// 魔心護盾：砍不到女巫
	"scen melee_shield",
	"change 0 1",
	"mp 0 100",
	"wait 0.6",
	"witch 0",
	"wait 1.0",
	"approach 0 45",
	"wait 0.5",
	"mcount 0 start",
	"swing 0",
	"wait 1.5",
	"swing 0",
	"wait 1.5",
	"mcount 0 after",
	"wcount after",
	"killwitch",
	"prep",
	"wait 0.5",

	// 魔心護盾、對著地板揮（前面沒有東西）
	"scen melee_air",
	"hold 0",
	"wait 0.5",
	"mcount 0 start",
	"swing 0",
	"wait 1.5",
	"mcount 0 after",
	"prep",

	// 關掉護盾
	"scen melee_off",
	"change 0 0",
	"wait 0.5",
	"mcount 0 after",
	"cvarreset z_witch_anger_rate",
	"cvarreset z_witch_personal_space",
};

// 鷹眼的發光：施放中打死的殭屍（屍體）還亮不亮、施放結束時是不是全部熄掉、發光時 edict 的傳送旗標
// b2 放鷹眼；nb_stop 讓殭屍和 bot 都不動
static char s_sGlow[][] =
{
	"findbots",
	"home",
	"prep",
	"cvar nb_stop 1",
	"cvar nb_blind 1",
	"gscan start",

	// 施放中打死：屍體的發光
	"scen glow_kill",
	"change 2 2",
	"wait 2.5",
	"commons 2 10",
	"wait 1.0",
	"gcount spawned",
	"mp 2 100",
	"cmd 2 skill1",
	"wait 0.3",
	"gcount act",
	"gscan act",
	"killcommons 2",
	"gcount t0",
	"wait 0.1",
	"gcount t0.1",
	"wait 0.5",
	"gcount t0.6",
	"wait 2.0",
	"gcount t2.6",
	"wait 7.0",

	// 施放結束：全部熄掉
	"scen glow_end",
	"commons 2 10",
	"wait 1.0",
	"mp 2 100",
	"cmd 2 skill1",
	"wait 0.3",
	"gcount act",
	"wait 7.2",
	"gcount end",
	"wait 3.0",
	"gcount after_timer",
	"killcommons 2",
	"wait 2.5",

	// 手動加 FL_EDICT_ALWAYS，遊戲會不會改回去
	"scen force_tx",
	"commons 2 5",
	"wait 1.0",
	"gcount before",
	"forcetx on",
	"gcount t0",
	"wait 1.0",
	"gcount t1",
	"wait 3.0",
	"gcount t4",
	"forcetx off",
	"gcount off",
	"killcommons 2",
	"wait 1.0",

	// 加了 FL_EDICT_ALWAYS 的殭屍被打死，旗標會不會被遊戲改掉
	"scen force_tx_death",
	"commons 2 5",
	"wait 1.0",
	"forcetx on",
	"killcommons 2",
	"gcount t0",
	"wait 0.2",
	"gcount t0.2",
	"wait 1.0",
	"gcount t1.2",
	"forcetx off",

	// 倖存者、特感、女巫的傳送旗標；鷹眼標示女巫、特感後打死
	"scen glow_others",
	"special 2 3",
	"witch 2",
	"wait 1.0",
	"gplayers spawned",
	"mp 2 100",
	"cmd 2 skill1",
	"wait 0.3",
	"gplayers act",
	"killothers 2",
	"gplayers t0",
	"wait 0.2",
	"gplayers t0.2",
	"wait 1.0",
	"gplayers t1.2",
	"wait 7.0",
	"gplayers end",
	"killwitch",
	"gscan end",
	"cvarreset nb_stop",
	"cvarreset nb_blind",
};

static char s_sFinish[][] =
{
	"scen finish",
	"cp final",
};

static bool T_GetLine(int idx, char[] line, int maxlen)
{
	if (StrEqual(s_sPhase, "main"))
	{
		if (idx >= sizeof(s_sMain)) return false;
		strcopy(line, maxlen, s_sMain[idx]);
	}
	else if (StrEqual(s_sPhase, "ex_prep"))
	{
		if (idx >= sizeof(s_sExPrep)) return false;
		strcopy(line, maxlen, s_sExPrep[idx]);
	}
	else if (StrEqual(s_sPhase, "after_reload") || StrEqual(s_sPhase, "after_map"))
	{
		if (idx >= sizeof(s_sAfter)) return false;
		strcopy(line, maxlen, s_sAfter[idx]);
	}
	else if (StrEqual(s_sPhase, "ex_restart"))
	{
		if (idx >= sizeof(s_sExRestart)) return false;
		strcopy(line, maxlen, s_sExRestart[idx]);
	}
	else if (StrEqual(s_sPhase, "ex_down"))
	{
		if (idx >= sizeof(s_sExDown)) return false;
		strcopy(line, maxlen, s_sExDown[idx]);
	}
	else if (StrEqual(s_sPhase, "dissolve"))
	{
		if (idx >= sizeof(s_sDissolve)) return false;
		strcopy(line, maxlen, s_sDissolve[idx]);
	}
	else if (StrEqual(s_sPhase, "steal_witch"))
	{
		if (idx >= sizeof(s_sStealWitch)) return false;
		strcopy(line, maxlen, s_sStealWitch[idx]);
	}
	else if (StrEqual(s_sPhase, "drop"))
	{
		if (idx >= sizeof(s_sDrop)) return false;
		strcopy(line, maxlen, s_sDrop[idx]);
	}
	else if (StrEqual(s_sPhase, "melee"))
	{
		if (idx >= sizeof(s_sMelee)) return false;
		strcopy(line, maxlen, s_sMelee[idx]);
	}
	else if (StrEqual(s_sPhase, "glow"))
	{
		if (idx >= sizeof(s_sGlow)) return false;
		strcopy(line, maxlen, s_sGlow[idx]);
	}
	else if (StrEqual(s_sPhase, "finish"))
	{
		if (idx >= sizeof(s_sFinish)) return false;
		strcopy(line, maxlen, s_sFinish[idx]);
	}
	else
	{
		return false;
	}
	return true;
}

//===========================================================
//========================= 執行 ============================
//===========================================================

public void OnAllPluginsLoaded()
{
	BuildPath(Path_SM, s_sLog, sizeof(s_sLog), "logs/skills_test.log");
	RegServerCmd("sm_skilltest", Cmd_SkillTest, "skills_mk2 自動測試：sm_skilltest <main|ex_down|ex_prep|after_reload|after_map|ex_restart|dissolve|steal_witch|drop|melee|glow|finish>");
	HookEvent("player_death", T_Event_Death);
	HookEvent("witch_harasser_set", T_Event_WitchHarasser);
	HookEvent("infected_death", T_Event_InfDeath);

	// 另外掛一個近戰判定的 detour，只用來計數（技能系統自己的 detour 照常運作）
	Handle gd = LoadGameConfigFile(GAMEDATA_MELEE);
	if (gd != null)
	{
		s_hMeleeDetour = DHookCreateFromConf(gd, "CTerrorMeleeWeapon::TestMeleeSwingCollision");
		delete gd;
		if (s_hMeleeDetour != null) DHookEnableDetour(s_hMeleeDetour, false, T_MeleeSwingPre);
	}
}

static MRESReturn T_MeleeSwingPre(int pThis, Handle hReturn)
{
	if (!s_sPhase[0] || !IsValidEntity(pThis)) return MRES_Ignored;
	int owner = GetEntPropEnt(pThis, Prop_Send, "m_hOwnerEntity");
	if (owner < 1 || owner > MaxClients || !s_bHold[owner]) return MRES_Ignored;
	s_iMeleeCalls[owner]++;
	// 同一刀的 m_flNextPrimaryAttack 不變，換一刀才會變
	float id = GetEntPropFloat(pThis, Prop_Send, "m_flNextPrimaryAttack");
	if (id != s_fSwingId[owner])
	{
		s_fSwingId[owner] = id;
		s_iSwingN[owner]++;
		float ang[3];
		GetClientEyeAngles(owner, ang);
		char who[8];
		T_Who(owner, who, sizeof(who));
		T_Log("SWING %s/%s %s pitch=%.0f yaw=%.0f", s_sPhase, s_sScen, who, ang[0], ang[1]);
	}
	return MRES_Ignored;
}

// hold 的 bot：不移動、視角固定、只按劇本要的攻擊鍵、手上一定拿近戰武器（有的話）
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (client < 1 || client > MaxClients || !s_bHold[client]) return Plugin_Continue;
	buttons = 0;
	if (s_iSwingTicks[client] > 0)
	{
		buttons = IN_ATTACK;
		s_iSwingTicks[client]--;
	}
	vel[0] = 0.0;
	vel[1] = 0.0;
	vel[2] = 0.0;
	for (int i = 0; i < 3; i++) angles[i] = s_vHoldAng[client][i];
	TeleportEntity(client, NULL_VECTOR, s_vHoldAng[client], NULL_VECTOR);
	int m = GetPlayerWeaponSlot(client, 1);
	if (m > 0 && GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") != m)
	{
		char cls[32];
		GetEntityClassname(m, cls, sizeof(cls));
		if (StrEqual(cls, "weapon_melee")) weapon = m;
	}
	return Plugin_Changed;
}

static void T_Event_WitchHarasser(Event event, const char[] name, bool dontBroadcast)
{
	if (!s_sPhase[0]) return;
	int who = GetClientOfUserId(event.GetInt("userid"));
	s_iHarassN++;
	s_iHarasser = who;
	char tag[8];
	T_Who(who, tag, sizeof(tag));
	T_Log("HARASS %s/%s ours=%d by=%s first=%d", s_sPhase, s_sScen,
		EntRefToEntIndex(s_iWitch) == event.GetInt("witchid"), tag, event.GetBool("first"));
}

// glow 階段：記下死亡事件帶的欄位、事件當下殭屍的 m_iGlowType（Event_DeathUnglow 在這之前已經執行）
static void T_Event_InfDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!StrEqual(s_sPhase, "glow")) return;
	int id = event.GetInt("infected_id");
	T_Log("INFDEATH %s/%s infected_id=%d is_infected=%d glow=%d", s_sPhase, s_sScen, id, IsInf(id),
		IsInf(id) ? GetEntProp(id, Prop_Send, "m_iGlowType") : -1);
}

static void T_Event_Death(Event event, const char[] name, bool dontBroadcast)
{
	if (StrEqual(s_sPhase, "glow"))
	{
		int ent = event.GetInt("entityid");
		int victim = GetClientOfUserId(event.GetInt("userid"));
		if (victim <= 0) victim = ent;
		char cls[32];
		if (victim > 0 && IsValidEntity(victim)) GetEntityClassname(victim, cls, sizeof(cls));
		T_Log("PDEATH %s/%s userid=%d entityid=%d victim=%d cls=%s glow=%d flags=0x%x", s_sPhase, s_sScen, event.GetInt("userid"), ent,
			victim, cls, (victim > 0 && HasEntProp(victim, Prop_Send, "m_iGlowType")) ? GetEntProp(victim, Prop_Send, "m_iGlowType") : -1,
			(victim > 0 && IsValidEdict(victim)) ? GetEdictFlags(victim) : -1);
	}
	if (!s_sPhase[0] || !IsInf(event.GetInt("entityid"))) return;
	s_iInfDeaths++;
	if (s_iPurifier > 0 && GetClientOfUserId(event.GetInt("attacker")) == s_iPurifier)
		s_iInfDeathsBy++;
}

static Action Cmd_SkillTest(int args)
{
	GetCmdArg(1, s_sPhase, sizeof(s_sPhase));
	char probe[8];
	if (!T_GetLine(0, probe, sizeof(probe)))
	{
		PrintToServer("[skilltest] 沒有這個階段：%s", s_sPhase);
		s_sPhase[0] = '\0';
		return Plugin_Handled;
	}
	strcopy(s_sScen, sizeof(s_sScen), "-");
	s_iLine = 0;
	T_Log("PHASE %s", s_sPhase);
	T_FindBots();
	T_Run();
	return Plugin_Handled;
}

static void T_Run()
{
	char line[128];
	while (T_GetLine(s_iLine++, line, sizeof(line)))
	{
		float wait = T_Exec(line);
		if (wait > 0.0)
		{
			CreateTimer(wait, Timer_T_Continue);
			return;
		}
	}
	T_Log("== %s DONE ==", s_sPhase);
	if (StrEqual(s_sPhase, "finish"))
		T_Log("== DONE ==");
}

static Action Timer_T_Continue(Handle timer)
{
	T_Run();
	return Plugin_Stop;
}

static int T_Bot(const char[] arg)
{
	int k = StringToInt(arg);
	if (k < 0 || k >= TEST_BOTS) return 0;
	int b = s_iBot[k];
	if (b <= 0 || !IsClientInGame(b)) return 0;
	return b;
}

static float T_Exec(const char[] line)
{
	char a[4][64];
	int n = ExplodeString(line, " ", a, sizeof(a), sizeof(a[]));
	int b = n > 1 ? T_Bot(a[1]) : 0;

	if (StrEqual(a[0], "wait"))
	{
		return StringToFloat(a[1]);
	}
	else if (StrEqual(a[0], "scen"))
	{
		strcopy(s_sScen, sizeof(s_sScen), a[1]);
		T_Log("BEGIN %s/%s", s_sPhase, s_sScen);
	}
	else if (StrEqual(a[0], "home"))
	{
		for (int k = 0; k < TEST_BOTS; k++)
			if (s_iBot[k] > 0 && IsClientInGame(s_iBot[k]))
				GetClientAbsOrigin(s_iBot[k], s_vHome[k]);
	}
	else if (StrEqual(a[0], "findbots"))
	{
		T_FindBots();
	}
	else if (StrEqual(a[0], "prep"))
	{
		for (int k = 0; k < TEST_BOTS; k++)
			T_Prep(k);
	}
	else if (StrEqual(a[0], "mp"))
	{
		float v = StringToFloat(a[2]);
		for (int k = 0; k < TEST_BOTS; k++)
		{
			int c = s_iBot[k];
			if (c > 0 && IsClientInGame(c) && (StrEqual(a[1], "all") || StringToInt(a[1]) == k))
				Skill_MP[c] = v;
		}
	}
	else if (StrEqual(a[0], "cmd"))
	{
		if (b) FakeClientCommand(b, a[2]);
	}
	else if (StrEqual(a[0], "change"))
	{
		if (b) Skill_Change(b, StringToInt(a[2]));
	}
	else if (StrEqual(a[0], "dmg"))
	{
		// bypassHooks 預設是 true，會略過 OnTakeDamage hook；這裡要測無敵與魔心護盾，所以設成 false
		if (b)
		{
			int before = GetClientHealth(b);
			SDKHooks_TakeDamage(b, 0, 0, StringToFloat(a[2]), DMG_GENERIC, -1, NULL_VECTOR, NULL_VECTOR, false);
			T_Log("DMG %s/%s b%s %s hp=%d->%d", s_sPhase, s_sScen, a[1], a[2], before, IsClientInGame(b) ? GetClientHealth(b) : -1);
		}
	}
	else if (StrEqual(a[0], "kill"))
	{
		if (b) ForcePlayerSuicide(b);
	}
	else if (StrEqual(a[0], "respawn"))
	{
		if (b && !IsPlayerAlive(b)) T_Respawn(StringToInt(a[1]));
	}
	else if (StrEqual(a[0], "face"))
	{
		int t = T_Bot(a[2]);
		if (b && t) T_Face(b, t);
	}
	else if (StrEqual(a[0], "rescue"))
	{
		int keep = StringToInt(a[1]);
		for (int k = 0; k < TEST_BOTS; k++)
			if (k != keep)
				T_Prep(k);
	}
	else if (StrEqual(a[0], "revive"))
	{
		if (b && IsPlayerAlive(b) && T_IsIncapped(b)) L4D_ReviveSurvivor(b);
	}
	else if (StrEqual(a[0], "kick"))
	{
		if (b) KickClient(b, "skilltest");
		s_iBot[StringToInt(a[1])] = 0;
	}
	else if (StrEqual(a[0], "addbot"))
	{
		ServerCommand("sb_add");
	}
	else if (StrEqual(a[0], "restart"))
	{
		char map[64];
		GetCurrentMap(map, sizeof(map));
		L4D_RestartScenarioFromVote(map);
	}
	else if (StrEqual(a[0], "bw"))
	{
		if (b)
		{
			SetEntProp(b, Prop_Send, "m_currentReviveCount", FindConVar("survivor_max_incapacitated_count").IntValue);
			SetEntProp(b, Prop_Send, "m_bIsOnThirdStrike", 1);
		}
	}
	else if (StrEqual(a[0], "cvar"))
	{
		ConVar cv = FindConVar(a[1]);
		if (cv != null) cv.SetString(a[2]);
		else T_Log("FAIL 找不到 cvar：%s", a[1]);
	}
	else if (StrEqual(a[0], "cvarreset"))
	{
		ConVar cv = FindConVar(a[1]);
		if (cv != null) cv.RestoreDefault();
		else T_Log("FAIL 找不到 cvar：%s", a[1]);
	}
	else if (StrEqual(a[0], "commons"))
	{
		if (b) T_SpawnCommons(b, StringToInt(a[2]));
	}
	else if (StrEqual(a[0], "purify"))
	{
		if (b)
		{
			int called = 0;
			for (int i = 0; i < s_iCommonN; i++)
			{
				int e = EntRefToEntIndex(s_iCommon[i]);
				if (e == INVALID_ENT_REFERENCE) continue;
				Turn_Undead(e, b);
				called++;
			}
			T_Log("PURIFY %s/%s called=%d", s_sPhase, s_sScen, called);
		}
	}
	else if (StrEqual(a[0], "killcommons"))
	{
		if (b)
		{
			for (int i = 0; i < s_iCommonN; i++)
			{
				int e = EntRefToEntIndex(s_iCommon[i]);
				if (e != INVALID_ENT_REFERENCE)
					DealDamage(e, GetEntProp(e, Prop_Data, "m_iHealth") + 5, b, DMG_BULLET);
			}
		}
	}
	else if (StrEqual(a[0], "dcount"))
	{
		T_DissolveCount(a[1]);
	}
	else if (StrEqual(a[0], "gcount"))
	{
		T_GlowCount(a[1]);
	}
	else if (StrEqual(a[0], "gscan"))
	{
		T_GlowScan(a[1]);
	}
	else if (StrEqual(a[0], "special"))
	{
		// 在 b 前方 150 單位生一隻特感（zombieClass：1 smoker、3 hunter…）
		if (b)
		{
			float org[3], ang[3], fwd[3];
			GetClientAbsOrigin(b, org);
			GetClientEyeAngles(b, ang);
			ang[0] = 0.0;
			GetAngleVectors(ang, fwd, NULL_VECTOR, NULL_VECTOR);
			for (int i = 0; i < 2; i++) org[i] += fwd[i] * 150.0;
			int si = L4D2_SpawnSpecial(StringToInt(a[2]), org, ang);
			T_Log("SPECIAL %s/%s class=%s client=%d", s_sPhase, s_sScen, a[2], si);
		}
	}
	else if (StrEqual(a[0], "gplayers"))
	{
		T_GlowPlayers(a[1]);
	}
	else if (StrEqual(a[0], "killothers"))
	{
		// 打死測試生出來的女巫和所有特感，攻擊者是 b
		if (b)
		{
			int w = EntRefToEntIndex(s_iWitch);
			if (w != INVALID_ENT_REFERENCE) DealDamage(w, 5000, b, DMG_BULLET);
			for (int i = 1; i <= MaxClients; i++)
				if (IsAliveSpecialInf(i)) ForcePlayerSuicide(i);
		}
	}
	else if (StrEqual(a[0], "forcetx"))
	{
		bool on = StrEqual(a[1], "on");
		for (int i = 0; i < s_iCommonN; i++)
		{
			int e = EntRefToEntIndex(s_iCommon[i]);
			if (e == INVALID_ENT_REFERENCE) continue;
			int fl = GetEdictFlags(e);
			SetEdictFlags(e, on ? (fl | FL_EDICT_ALWAYS) : (fl & ~FL_EDICT_ALWAYS));
		}
	}
	else if (StrEqual(a[0], "witch"))
	{
		if (b) T_SpawnWitch(b);
	}
	else if (StrEqual(a[0], "aimwitch"))
	{
		if (b) T_AimWitch(b);
	}
	else if (StrEqual(a[0], "wcount"))
	{
		T_WitchCount(a[1]);
	}
	else if (StrEqual(a[0], "killwitch"))
	{
		int w = EntRefToEntIndex(s_iWitch);
		if (w != INVALID_ENT_REFERENCE) RemoveEntity(w);
		s_iWitch = INVALID_ENT_REFERENCE;
	}
	else if (StrEqual(a[0], "give"))
	{
		if (b)
		{
			if (GivePlayerItem(b, a[2]) == -1) T_Log("FAIL give：%s", a[2]);
			FakeClientCommand(b, "use %s", a[2]);
		}
	}
	else if (StrEqual(a[0], "weapons"))
	{
		if (b) T_Weapons(b, a[2]);
	}
	else if (StrEqual(a[0], "melee"))
	{
		if (b) T_GiveMelee(b, a[2]);
	}
	else if (StrEqual(a[0], "approach"))
	{
		if (b) T_Approach(b, StringToFloat(a[2]));
	}
	else if (StrEqual(a[0], "hold"))
	{
		if (b)
		{
			GetClientEyeAngles(b, s_vHoldAng[b]);
			s_bHold[b] = true;
		}
	}
	else if (StrEqual(a[0], "swing"))
	{
		if (b) s_iSwingTicks[b] = 4;
	}
	else if (StrEqual(a[0], "mcount"))
	{
		if (b) T_MeleeCount(b, a[2]);
	}
	else if (StrEqual(a[0], "hp"))
	{
		if (b) SetEntityHealth(b, StringToInt(a[2]));
	}
	else if (StrEqual(a[0], "cp"))
	{
		T_Checkpoint(a[1]);
	}
	else
	{
		T_Log("FAIL 劇本指令不認得：%s", line);
	}
	return 0.0;
}

static void T_FindBots()
{
	int n = 0;
	for (int i = 1; i <= MaxClients && n < TEST_BOTS; i++)
	{
		if (IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == 2)
			s_iBot[n++] = i;
	}
	for (int k = n; k < TEST_BOTS; k++)
		s_iBot[k] = 0;
	if (n < TEST_BOTS)
		T_Log("FAIL 只找到 %d 個倖存者 bot", n);

	// 真人在 OnClientPostAdminCheck 掛受傷 hook；bot 觸發這個 forward 時還不在遊戲中，所以不會掛上。
	// 這裡補掛一次（先 unhook，避免跟 reload 時 CheckPlayerConnections 掛的重複），無敵和魔心護盾才會對 bot 生效
	for (int k = 0; k < n; k++)
	{
		SDKUnhook(s_iBot[k], SDKHook_OnTakeDamage, Event_Hurt);
		SDKHook(s_iBot[k], SDKHook_OnTakeDamage, Event_Hurt);
	}
	char names[256];
	for (int k = 0; k < TEST_BOTS; k++)
	{
		if (s_iBot[k] > 0)
			Format(names, sizeof(names), "%s b%d=%N", names, k, s_iBot[k]);
	}
	T_Log("BOTS%s", names);
}

static bool T_TraceNoPlayers(int entity, int contentsMask, any data)
{
	return entity > MaxClients;
}

// 找一個前方 120 單位內沒有障礙的方向，把 t 放在 b 前方 60 單位，b 瞄準 t 的胸口
static void T_Face(int b, int t)
{
	float org[3], start[3], end[3], dir[3], tpos[3];
	GetClientAbsOrigin(b, org);
	bool found = false;
	for (int d = 0; d < 8 && !found; d++)
	{
		float yaw = DegToRad(d * 45.0);
		dir[0] = Cosine(yaw);
		dir[1] = Sine(yaw);
		dir[2] = 0.0;
		start = org;
		start[2] += 40.0;
		for (int i = 0; i < 3; i++) end[i] = start[i] + dir[i] * 120.0;
		TR_TraceRayFilter(start, end, MASK_PLAYERSOLID, RayType_EndPoint, T_TraceNoPlayers);
		if (!TR_DidHit())
		{
			for (int i = 0; i < 3; i++) tpos[i] = org[i] + dir[i] * 60.0;
			found = true;
		}
	}
	if (!found)
	{
		T_Log("FAIL face：找不到空位");
		return;
	}
	float zero[3], aim[3], ang[3];
	TeleportEntity(t, tpos, NULL_VECTOR, zero);
	for (int i = 0; i < 3; i++) aim[i] = tpos[i] - org[i];
	aim[2] += 40.0 - 62.0;  // 從 b 的眼睛（約 62）看向 t 的胸口（約 40）
	GetVectorAngles(aim, ang);
	TeleportEntity(b, NULL_VECTOR, ang, NULL_VECTOR);
}

static bool T_IsIncapped(int client)
{
	return GetEntProp(client, Prop_Send, "m_isIncapacitated") != 0;
}

static void T_Respawn(int k)
{
	int b = s_iBot[k];
	L4D_RespawnPlayer(b);
	T_Place(k);
}

// 回到原位、補滿血、看向地板（瞄準點固定，偷竊一定失敗、爆裂打在腳邊）
static void T_Place(int k)
{
	int b = s_iBot[k];
	if (b <= 0 || !IsClientInGame(b) || !IsPlayerAlive(b)) return;
	float ang[3] = {89.0, 0.0, 0.0};
	float zero[3];
	TeleportEntity(b, s_vHome[k], ang, zero);
	SetEntityHealth(b, 100);
	SetEntPropFloat(b, Prop_Send, "m_healthBuffer", 0.0);
	ExtinguishEntity(b);
	// 倒地次數歸零：救起來會累加，累積到上限（黑白）後再倒地就會直接死，情境之間會互相影響
	SetEntProp(b, Prop_Send, "m_currentReviveCount", 0);
	SetEntProp(b, Prop_Send, "m_bIsOnThirdStrike", 0);
}

// 從 b 外圍 80 單位起，每 40 單位一圈往外找：不在牆裡、往下 100 單位內有地板的位置，各生一隻普通殭屍
static void T_SpawnCommons(int b, int n)
{
	s_iCommonN = 0;
	s_iPurifier = b;
	s_iInfDeaths = 0;
	s_iInfDeathsBy = 0;
	if (n > TEST_MAX_COMMONS) n = TEST_MAX_COMMONS;

	float org[3], top[3], bottom[3], pos[3];
	int outside = 0, solid = 0, nofloor = 0, fail = 0;
	GetClientAbsOrigin(b, org);
	for (int ring = 2; ring <= 15 && s_iCommonN < n; ring++)
	{
		float r = ring * 40.0;
		int steps = RoundToFloor(2.0 * FLOAT_PI * r / 40.0);
		for (int s = 0; s < steps && s_iCommonN < n; s++)
		{
			float ang = 2.0 * FLOAT_PI * s / steps;
			top[0] = org[0] + r * Cosine(ang);
			top[1] = org[1] + r * Sine(ang);
			top[2] = org[2] + 40.0;
			if (TR_PointOutsideWorld(top)) { outside++; continue; }
			if (TR_GetPointContents(top) & MASK_SOLID) { solid++; continue; }
			bottom = top;
			bottom[2] = org[2] - 60.0;
			TR_TraceRayFilter(top, bottom, MASK_PLAYERSOLID, RayType_EndPoint, T_TraceNoPlayers);
			if (!TR_DidHit()) { nofloor++; continue; }
			TR_GetEndPosition(pos);
			pos[2] += 2.0;

			int e = CreateEntityByName("infected");
			if (e == -1) { fail++; continue; }
			TeleportEntity(e, pos, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(e);
			ActivateEntity(e);
			s_iCommon[s_iCommonN++] = EntIndexToEntRef(e);
		}
	}
	T_Log("SPAWN %s/%s commons=%d/%d skipped: outside=%d solid=%d nofloor=%d createfail=%d",
		s_sPhase, s_sScen, s_iCommonN, n, outside, solid, nofloor, fail);
}

static void T_DissolveCount(const char[] label)
{
	int exist = 0, alive = 0, inrange = 0;
	float org[3];
	if (s_iPurifier > 0 && IsClientInGame(s_iPurifier)) GetClientAbsOrigin(s_iPurifier, org);
	for (int i = 0; i < s_iCommonN; i++)
	{
		int e = EntRefToEntIndex(s_iCommon[i]);
		if (e == INVALID_ENT_REFERENCE) continue;
		exist++;
		if (GetEntProp(e, Prop_Data, "m_iHealth") > 0)
		{
			alive++;
			if (GetEntityPosDistance(e, org) <= TURN_UNDEAD_DIST) inrange++;
		}
	}
	int slots = 0, dissolvers = 0, ent = -1;
	for (int i = 0; i < MAX_DISSOLVE; i++)
		if (g_iDissolvers[i] && EntRefToEntIndex(g_iDissolvers[i]) != INVALID_ENT_REFERENCE) slots++;
	while ((ent = FindEntityByClassname(ent, "env_entity_dissolver")) != -1) dissolvers++;
	int b1 = s_iBot[1];
	T_Log("DCOUNT %s/%s/%s spawned=%d exist=%d alive=%d alive_inrange=%d slots=%d/%d dissolvers=%d inf_deaths=%d by_caster=%d mp_b1=%.1f",
		s_sPhase, s_sScen, label, s_iCommonN, exist, alive, inrange, slots, MAX_DISSOLVE, dissolvers,
		s_iInfDeaths, s_iInfDeathsBy, (b1 > 0 && IsClientInGame(b1)) ? Skill_MP[b1] : -1.0);
}

// 生出來的普通殭屍：還在幾隻、死了幾隻、m_iGlowType 不是 0 的幾隻（其中死掉的幾隻）、State_Glow、edict 傳送旗標
static void T_GlowCount(const char[] label)
{
	int exist = 0, dead = 0, glow = 0, glowDead = 0, state = 0, always = 0, pvs = 0, dontsend = 0, full = 0;
	char sample[256];
	for (int i = 0; i < s_iCommonN; i++)
	{
		int e = EntRefToEntIndex(s_iCommon[i]);
		if (e == INVALID_ENT_REFERENCE) continue;
		exist++;
		int hp = GetEntProp(e, Prop_Data, "m_iHealth");
		int gt = GetEntProp(e, Prop_Send, "m_iGlowType");
		int fl = GetEdictFlags(e);
		if (hp <= 0) dead++;
		if (gt != 0)
		{
			glow++;
			if (hp <= 0) glowDead++;
		}
		if (State_Glow[e]) state++;
		if (fl & FL_EDICT_ALWAYS) always++;
		else if (fl & FL_EDICT_DONTSEND) dontsend++;
		else if (fl & FL_EDICT_PVSCHECK) pvs++;
		else full++;
		if (i < 3)
			Format(sample, sizeof(sample), "%s [#%d hp=%d glow=%d state=%d flags=0x%x]", sample, e, hp, gt, State_Glow[e], fl);
	}
	T_Log("GCOUNT %s/%s/%s spawned=%d exist=%d dead=%d glow=%d glow_dead=%d state=%d tx_always=%d tx_pvs=%d tx_dontsend=%d tx_fullcheck=%d%s",
		s_sPhase, s_sScen, label, s_iCommonN, exist, dead, glow, glowDead, state, always, pvs, dontsend, full, sample);
}

// 倖存者、特感、女巫：活著沒有、m_iGlowType、State_Glow、edict 傳送旗標
static void T_GlowPlayers(const char[] label)
{
	char buf[1024];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || GetClientTeam(i) < 2) continue;
		Format(buf, sizeof(buf), "%s [%s%d alive=%d glow=%d state=%d flags=0x%x]", buf, GetClientTeam(i) == 3 ? "si" : "sv", i,
			IsPlayerAlive(i), GetEntProp(i, Prop_Send, "m_iGlowType"), State_Glow[i], GetEdictFlags(i));
	}
	int w = EntRefToEntIndex(s_iWitch);
	if (w != INVALID_ENT_REFERENCE)
		Format(buf, sizeof(buf), "%s [witch%d hp=%d glow=%d state=%d flags=0x%x]", buf, w, GetEntProp(w, Prop_Data, "m_iHealth"),
			GetEntProp(w, Prop_Send, "m_iGlowType"), State_Glow[w], GetEdictFlags(w));
	else
		StrCat(buf, sizeof(buf), " [witch gone]");
	T_Log("GPLAYERS %s/%s/%s%s", s_sPhase, s_sScen, label, buf);
}

// GetEntityCount()（使用中的 edict 數）跟實際最大的 entity 編號差多少；編號超過 GetEntityCount() 的普通殭屍有幾隻
static void T_GlowScan(const char[] label)
{
	int count = GetEntityCount(), maxEnt = GetMaxEntities(), highest = 0, holes = 0, infAll = 0, infBeyond = 0;
	for (int i = 1; i < maxEnt; i++)
	{
		if (!IsValidEdict(i))
		{
			holes++;
			continue;
		}
		highest = i;
		if (IsInf(i))
		{
			infAll++;
			if (i > count) infBeyond++;
		}
	}
	// holes 只算 highest 以下的空位
	holes -= (maxEnt - 1 - highest);
	T_Log("GSCAN %s/%s/%s entity_count=%d max_entities=%d highest=%d holes_below=%d infected=%d infected_beyond_count=%d",
		s_sPhase, s_sScen, label, count, maxEnt, highest, holes, infAll, infBeyond);
}

// 從 b 往 8 個方向找前方沒有障礙、底下有地板的位置（依序試 200、160、120 單位），生一隻面向 b 的女巫
static void T_SpawnWitch(int b)
{
	s_iHarassN = 0;
	s_iHarasser = 0;
	s_iWitchCaster = b;
	float dists[] = {200.0, 160.0, 120.0};
	float org[3], start[3], end[3], dir[3], pos[3], down[3];
	GetClientAbsOrigin(b, org);
	for (int di = 0; di < sizeof(dists); di++)
	{
		for (int d = 0; d < 8; d++)
		{
			float yaw = DegToRad(d * 45.0);
			dir[0] = Cosine(yaw);
			dir[1] = Sine(yaw);
			dir[2] = 0.0;
			start = org;
			start[2] += 40.0;
			for (int i = 0; i < 3; i++) end[i] = start[i] + dir[i] * (dists[di] + 40.0);
			TR_TraceRayFilter(start, end, MASK_PLAYERSOLID, RayType_EndPoint, T_TraceNoPlayers);
			if (TR_DidHit()) continue;
			for (int i = 0; i < 3; i++) pos[i] = start[i] + dir[i] * dists[di];
			down = pos;
			down[2] = org[2] - 60.0;
			TR_TraceRayFilter(pos, down, MASK_PLAYERSOLID, RayType_EndPoint, T_TraceNoPlayers);
			if (!TR_DidHit()) continue;
			TR_GetEndPosition(pos);

			float ang[3];
			ang[1] = d * 45.0 + 180.0;
			int w = CreateEntityByName("witch");
			if (w == -1)
			{
				T_Log("FAIL witch：CreateEntityByName 失敗");
				return;
			}
			TeleportEntity(w, pos, ang, NULL_VECTOR);
			DispatchSpawn(w);
			ActivateEntity(w);
			s_iWitch = EntIndexToEntRef(w);

			// 擋在施法者和女巫中間的隊友移到施法者背後，不然施法者瞄到的是隊友（偷竊會變成偷隊友）
			int moved = 0;
			for (int k = 0; k < TEST_BOTS; k++)
			{
				int o = s_iBot[k];
				if (o <= 0 || o == b || !IsClientInGame(o) || !IsPlayerAlive(o)) continue;
				float op[3];
				GetClientAbsOrigin(o, op);
				float along = (op[0] - org[0]) * dir[0] + (op[1] - org[1]) * dir[1];
				float side = FloatAbs((op[0] - org[0]) * dir[1] - (op[1] - org[1]) * dir[0]);
				if (along < -20.0 || along > dists[di] + 40.0 || side > 60.0) continue;
				moved++;
				float np[3], zero[3];
				np[0] = org[0] - dir[0] * 50.0 * moved;
				np[1] = org[1] - dir[1] * 50.0 * moved;
				np[2] = org[2];
				TeleportEntity(o, np, NULL_VECTOR, zero);
			}
			T_Log("WITCH %s/%s spawned dist=%.0f moved_teammates=%d", s_sPhase, s_sScen, dists[di], moved);
			return;
		}
	}
	T_Log("FAIL witch：找不到空位");
}

static void T_AimWitch(int b)
{
	int w = EntRefToEntIndex(s_iWitch);
	if (w == INVALID_ENT_REFERENCE)
	{
		T_Log("FAIL aimwitch：沒有女巫");
		return;
	}
	float eye[3], pos[3], mins[3], maxs[3], aim[3], ang[3];
	GetClientEyePosition(b, eye);
	GetEntPropVector(w, Prop_Send, "m_vecOrigin", pos);
	GetEntPropVector(w, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(w, Prop_Send, "m_vecMaxs", maxs);
	for (int i = 0; i < 3; i++) aim[i] = pos[i] + (mins[i] + maxs[i]) * 0.5 - eye[i];
	GetVectorAngles(aim, ang);
	TeleportEntity(b, NULL_VECTOR, ang, NULL_VECTOR);
}

static void T_WitchCount(const char[] label)
{
	int w = EntRefToEntIndex(s_iWitch);
	int c = s_iWitchCaster;
	bool casterOk = c > 0 && IsClientInGame(c) && IsPlayerAlive(c);
	int hp = -1, aimed = 0;
	float rage = -1.0;
	if (w != INVALID_ENT_REFERENCE)
	{
		hp = GetEntProp(w, Prop_Data, "m_iHealth");
		if (HasEntProp(w, Prop_Send, "m_rage")) rage = GetEntPropFloat(w, Prop_Send, "m_rage");
		if (casterOk) aimed = (GetClientAimTarget(c, false) == w);
	}
	char by[8] = "-";
	if (s_iHarassN > 0) T_Who(s_iHarasser, by, sizeof(by));
	char caster[8];
	T_Who(c, caster, sizeof(caster));
	T_Log("WCOUNT %s/%s/%s exist=%d hp=%d rage=%.2f %s_aimed=%d harassed=%d by=%s %s_hp=%d %s_incap=%d",
		s_sPhase, s_sScen, label, w != INVALID_ENT_REFERENCE, hp, rage, caster, aimed, s_iHarassN, by,
		caster, casterOk ? GetClientHealth(c) : -1, caster, casterOk && T_IsIncapped(c));
}

static void T_Weapons(int b, const char[] label)
{
	char slots[256], cls[48];
	for (int s = 0; s < 5; s++)
	{
		int w = GetPlayerWeaponSlot(b, s);
		if (w > 0) GetEntityClassname(w, cls, sizeof(cls));
		else strcopy(cls, sizeof(cls), "-");
		Format(slots, sizeof(slots), "%s s%d=%s", slots, s, cls);
	}
	int act = GetEntPropEnt(b, Prop_Send, "m_hActiveWeapon");
	if (act > 0) GetEntityClassname(act, cls, sizeof(cls));
	else strcopy(cls, sizeof(cls), "-");
	int actClip = act > 0 ? GetEntProp(act, Prop_Send, "m_iClip1") : -1;
	int pistol = GetPlayerWeaponSlot(b, 1);
	int dual = pistol > 0 && HasEntProp(pistol, Prop_Send, "m_isDualWielding") ? GetEntProp(pistol, Prop_Send, "m_isDualWielding") : -1;
	int primary = GetPlayerWeaponSlot(b, 0);
	int reserve = primary > 0 ? GetPlayerReserveAmmo(b, primary) : -1;

	// 地上沒人拿的武器（排除地圖上的 weapon_*_spawn 補給點）
	char ground[512], gcls[48];
	float org[3], p[3];
	GetClientAbsOrigin(b, org);
	int n = 0;
	for (int e = MaxClients + 1; e < GetMaxEntities(); e++)
	{
		if (!IsValidEdict(e)) continue;
		GetEdictClassname(e, gcls, sizeof(gcls));
		if (StrContains(gcls, "weapon_") != 0 || StrContains(gcls, "_spawn") != -1) continue;
		if (!HasEntProp(e, Prop_Send, "m_hOwnerEntity") || GetEntPropEnt(e, Prop_Send, "m_hOwnerEntity") != -1) continue;
		GetEntPropVector(e, Prop_Send, "m_vecOrigin", p);
		if (GetVectorDistance(p, org) > 150.0) continue;
		int clip = HasEntProp(e, Prop_Send, "m_iClip1") ? GetEntProp(e, Prop_Send, "m_iClip1") : -1;
		int extra = HasEntProp(e, Prop_Send, "m_iExtraPrimaryAmmo") ? GetEntProp(e, Prop_Send, "m_iExtraPrimaryAmmo") : -1;
		Format(ground, sizeof(ground), "%s %s(clip=%d,extra=%d)", ground, gcls, clip, extra);
		n++;
	}
	// 所有手槍（不限距離）：誰拿著、離 b 多遠、彈匣
	char pistols[512], owner[8];
	int pe = -1;
	while ((pe = FindEntityByClassname(pe, "weapon_pistol")) != -1)
	{
		int o = GetEntPropEnt(pe, Prop_Send, "m_hOwnerEntity");
		if (o > 0 && o <= MaxClients) T_Who(o, owner, sizeof(owner));
		else IntToString(o, owner, sizeof(owner));
		GetEntPropVector(pe, Prop_Send, "m_vecOrigin", p);
		Format(pistols, sizeof(pistols), "%s pistol(owner=%s,dist=%.0f,clip=%d)", pistols, owner,
			GetVectorDistance(p, org), GetEntProp(pe, Prop_Send, "m_iClip1"));
	}
	char who[8];
	T_Who(b, who, sizeof(who));
	T_Log("WEAPONS %s/%s/%s %s%s active=%s(clip=%d) dual=%d reserve=%d ground=%d%s /%s",
		s_sPhase, s_sScen, label, who, slots, cls, actClip, dual, reserve, n, ground, pistols);
}

static void T_GiveMelee(int b, const char[] script)
{
	int flags = GetCommandFlags("give");
	SetCommandFlags("give", flags & ~FCVAR_CHEAT);
	FakeClientCommand(b, "give %s", script);
	SetCommandFlags("give", flags);
	FakeClientCommand(b, "use weapon_melee");

	int m = GetPlayerWeaponSlot(b, 1);
	char cls[48] = "-", name[48] = "-", who[8];
	if (m > 0)
	{
		GetEntityClassname(m, cls, sizeof(cls));
		if (HasEntProp(m, Prop_Data, "m_strMapSetScriptName"))
			GetEntPropString(m, Prop_Data, "m_strMapSetScriptName", name, sizeof(name));
	}
	T_Who(b, who, sizeof(who));
	T_Log("MELEE %s/%s %s slot1=%s script=%s", s_sPhase, s_sScen, who, cls, name);
	if (!StrEqual(cls, "weapon_melee")) T_Log("FAIL melee：給不了 %s", script);
}

// 把 b 移到女巫前方 dist 單位（沿著女巫到 b 的方向）、瞄準女巫身體中心，並 hold
static void T_Approach(int b, float dist)
{
	int w = EntRefToEntIndex(s_iWitch);
	if (w == INVALID_ENT_REFERENCE)
	{
		T_Log("FAIL approach：沒有女巫");
		return;
	}
	float wpos[3], bpos[3], dir[3], pos[3], zero[3];
	GetEntPropVector(w, Prop_Send, "m_vecOrigin", wpos);
	GetClientAbsOrigin(b, bpos);
	dir[0] = bpos[0] - wpos[0];
	dir[1] = bpos[1] - wpos[1];
	NormalizeVector(dir, dir);
	pos[0] = wpos[0] + dir[0] * dist;
	pos[1] = wpos[1] + dir[1] * dist;
	pos[2] = wpos[2] + 2.0;
	TeleportEntity(b, pos, NULL_VECTOR, zero);

	float eye[3], mins[3], maxs[3], aim[3];
	GetClientEyePosition(b, eye);
	GetEntPropVector(w, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(w, Prop_Send, "m_vecMaxs", maxs);
	for (int i = 0; i < 3; i++) aim[i] = wpos[i] + (mins[i] + maxs[i]) * 0.5 - eye[i];
	GetVectorAngles(aim, s_vHoldAng[b]);
	TeleportEntity(b, NULL_VECTOR, s_vHoldAng[b], NULL_VECTOR);
	s_bHold[b] = true;
	char who[8];
	T_Who(b, who, sizeof(who));
	T_Log("APPROACH %s/%s %s dist=%.0f pitch=%.0f witch_box=%.0f..%.0f", s_sPhase, s_sScen, who, dist,
		s_vHoldAng[b][0], mins[2], maxs[2]);
}

static void T_MeleeCount(int b, const char[] label)
{
	int w = EntRefToEntIndex(s_iWitch);
	int hp = w != INVALID_ENT_REFERENCE ? GetEntProp(w, Prop_Data, "m_iHealth") : -1;
	ConVar range = FindConVar("melee_range");
	char cls[32] = "-", who[8];
	int act = GetEntPropEnt(b, Prop_Send, "m_hActiveWeapon");
	if (act > 0) GetEntityClassname(act, cls, sizeof(cls));
	T_Who(b, who, sizeof(who));
	T_Log("MCOUNT %s/%s/%s %s swings=%d calls=%d center=%d witch_hp=%d melee_range=%d replicated=%d shield=%d active=%s",
		s_sPhase, s_sScen, label, who, s_iSwingN[b], s_iMeleeCalls[b], s_iCenterN[b], hp,
		range.IntValue, (range.Flags & FCVAR_REPLICATED) != 0, State_ManaShield[b], cls);
	s_iSwingN[b] = 0;
	s_iMeleeCalls[b] = 0;
	s_iCenterN[b] = 0;
}

static void T_Prep(int k)
{
	int b = s_iBot[k];
	if (b <= 0 || !IsClientInGame(b)) return;
	s_bHold[b] = false;
	s_iSwingTicks[b] = 0;
	if (!IsPlayerAlive(b))
		L4D_RespawnPlayer(b);
	else if (T_IsIncapped(b))
		L4D_ReviveSurvivor(b);
	T_Place(k);
}

//===========================================================
//========================= 紀錄 ============================
//===========================================================

static void T_Log(const char[] format, any ...)
{
	char buf[1024];
	VFormat(buf, sizeof(buf), format, 2);
	LogToFileEx(s_sLog, "%s", buf);
}

static void T_Who(int client, char[] out, int maxlen)
{
	for (int k = 0; k < TEST_BOTS; k++)
	{
		if (s_iBot[k] == client && client > 0)
		{
			Format(out, maxlen, "b%d", k);
			return;
		}
	}
	if (client == 0) strcopy(out, maxlen, "all");
	else Format(out, maxlen, "c%d", client);
}

// 正規化：去掉空白與顏色碼、數字換成 #、連續相同字元合併、▓ 換成 X、換行換成 /
// MP 數值與冷卻秒數每次跑都會有些微差異，只保留「顯示的是什麼」
static void T_Normalize(const char[] src, char[] dst, int maxlen)
{
	char tmp[512];
	strcopy(tmp, sizeof(tmp), src);
	ReplaceString(tmp, sizeof(tmp), "▓", "X");
	ReplaceString(tmp, sizeof(tmp), "\n", "/");
	int j = 0;
	int prev = -1;
	for (int i = 0; tmp[i] != '\0' && j < maxlen - 1; i++)
	{
		int c = tmp[i];
		if (c == ' ') continue;
		if (c > 0 && c < 0x20) continue;
		if (c == '-' && tmp[i + 1] >= '0' && tmp[i + 1] <= '9') continue;
		if (c >= '0' && c <= '9') c = '#';
		if (c == prev && c > 0 && c < 0x80) continue;
		dst[j++] = c;
		prev = c;
	}
	dst[j] = '\0';
}

static void T_Checkpoint(const char[] label)
{
	for (int k = 0; k < TEST_BOTS; k++)
	{
		int b = s_iBot[k];
		if (b <= 0 || !IsClientInGame(b))
		{
			T_Log("CP %s/%s/%s b%d none", s_sPhase, s_sScen, label, k);
			continue;
		}
		bool alive = IsPlayerAlive(b);
		T_Log("CP %s/%s/%s b%d skill=%d state=%d pstate=%d mp=%d inv=%d shield=%d alive=%d incap=%d hp=%d hint=%s",
			s_sPhase, s_sScen, label, k,
			Skill_GetCurrent(b), view_as<int>(Skill_GetState(b)), view_as<int>(State_Player[b]), RoundToFloor(Skill_MP[b]),
			Invulnerable[b], State_ManaShield[b], alive, alive && T_IsIncapped(b), GetClientHealth(b), s_sHint[b]);
	}

	// 全域效果：慢動作、EX 的強光與魔法陣、霧（天氣）
	int timescale = 0, dynlight = 0, circle = 0, ent = -1;
	char buf[PLATFORM_MAX_PATH];
	while ((ent = FindEntityByClassname(ent, "func_timescale")) != -1) timescale++;
	while ((ent = FindEntityByClassname(ent, "light_dynamic")) != -1)
	{
		GetEntPropString(ent, Prop_Data, "m_iName", buf, sizeof(buf));
		if (StrEqual(buf, "ex_dynlight")) dynlight++;
	}
	while ((ent = FindEntityByClassname(ent, "prop_dynamic")) != -1)
	{
		GetEntPropString(ent, Prop_Data, "m_ModelName", buf, sizeof(buf));
		if (StrContains(buf, "magic_circle") != -1) circle++;
	}
	int fogend = -1;
	int fog = FindEntityByClassname(-1, "env_fog_controller");
	if (fog != -1) fogend = RoundToNearest(GetEntPropFloat(fog, Prop_Send, "m_fog.end"));
	T_Log("CPW %s/%s/%s slow=%d timescale_ents=%d dynlight=%d circle=%d fogend=%d",
		s_sPhase, s_sScen, label, State_Slow, timescale, dynlight, circle, fogend);
}

//===========================================================
//===================== 攔截的函式 ==========================
//===========================================================
// test/main_test.sp 用 #define 把技能系統裡的呼叫換成這些函式。
// 先呼叫原本的 native（錯誤行為不變），再記 log。

stock bool Test_IsFakeClient(int client)
{
	IsFakeClient(client);
	return false;
}

stock void Test_PrintHintText(int client, const char[] format, any ...)
{
	char buf[512];
	SetGlobalTransTarget(client);
	VFormat(buf, sizeof(buf), format, 3);
	PrintHintText(client, "%s", buf);
	if (client < 1 || client > MaxClients || !s_sPhase[0]) return;

	char norm[256];
	T_Normalize(buf, norm, sizeof(norm));
	if (StrEqual(norm, s_sHint[client])) return;
	strcopy(s_sHint[client], sizeof(s_sHint[]), norm);
	char who[8];
	T_Who(client, who, sizeof(who));
	T_Log("HINT %s/%s %s %s", s_sPhase, s_sScen, who, norm);
}

stock void Test_PrintCenterText(int client, const char[] format, any ...)
{
	char buf[512];
	SetGlobalTransTarget(client);
	VFormat(buf, sizeof(buf), format, 3);
	PrintCenterText(client, "%s", buf);
	if (client < 1 || client > MaxClients || !s_sPhase[0]) return;
	s_iCenterN[client]++;
	char who[8];
	T_Who(client, who, sizeof(who));
	T_Log("CENTER %s/%s %s %s", s_sPhase, s_sScen, who, buf);
}

// bot 沒有網路通道，SendConVarValue 對 bot 會丟錯誤；只記 log，真人才真的送
stock bool Test_SendConVarValue(int client, ConVar convar, const char[] value)
{
	if (s_sPhase[0])
	{
		char name[64], who[8];
		convar.GetName(name, sizeof(name));
		T_Who(client, who, sizeof(who));
		T_Log("SENDCVAR %s/%s %s %s=%s", s_sPhase, s_sScen, who, name, value);
	}
	if (IsFakeClient(client)) return false;
	return SendConVarValue(client, convar, value);
}

stock void Test_PrintToChat(int client, const char[] format, any ...)
{
	char buf[512];
	SetGlobalTransTarget(client);
	VFormat(buf, sizeof(buf), format, 3);
	PrintToChat(client, "%s", buf);
	T_LogChat(client, buf);
}

stock void Test_PrintToChatAll(const char[] format, any ...)
{
	char buf[512];
	SetGlobalTransTarget(LANG_SERVER);
	VFormat(buf, sizeof(buf), format, 2);
	PrintToChatAll("%s", buf);
	T_LogChat(0, buf);
}

static void T_LogChat(int client, const char[] text)
{
	if (!s_sPhase[0]) return;
	// 換圖後 bot 進場順序會變，訊息裡的名字換成 <bA>（b0）、<bB>（b1）這種代號，
	// 跨次比對才不會因為名字不同而不一致（用字母是因為正規化會把數字換成 #）
	char buf[512], name[MAX_NAME_LENGTH], tag[8];
	strcopy(buf, sizeof(buf), text);
	for (int k = 0; k < TEST_BOTS; k++)
	{
		int b = s_iBot[k];
		if (b <= 0 || !IsClientInGame(b)) continue;
		GetClientName(b, name, sizeof(name));
		FormatEx(tag, sizeof(tag), "<b%c>", 'A' + k);
		ReplaceString(buf, sizeof(buf), name, tag);
	}
	char norm[256], who[8];
	T_Normalize(buf, norm, sizeof(norm));
	T_Who(client, who, sizeof(who));
	T_Log("CHAT %s/%s %s %s", s_sPhase, s_sScen, who, norm);
}
