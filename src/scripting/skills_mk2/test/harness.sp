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

static char  s_sLog[PLATFORM_MAX_PATH];
static int   s_iBot[TEST_BOTS];
static float s_vHome[TEST_BOTS][3];
static char  s_sPhase[32];
static char  s_sScen[48];
static int   s_iLine;
static char  s_sHint[MAXPLAYERS + 1][256];

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
//   restart              投票重開回合（L4D_RestartScenarioFromVote）
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
	RegServerCmd("sm_skilltest", Cmd_SkillTest, "skills_mk2 自動測試：sm_skilltest <main|ex_prep|after_reload|after_map|ex_restart|finish>");
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
}

static void T_Prep(int k)
{
	int b = s_iBot[k];
	if (b <= 0 || !IsClientInGame(b)) return;
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
