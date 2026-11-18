// 技能框架：註冊、施放、狀態機（準備 → 施放中 → 冷卻 → 準備）、切換、中斷、清理分派、資源預載
//
// 每個技能是 skills/ 底下的一個檔案，用 Skill_Register 註冊，再用 Skill_On* 掛上需要的 hook：
//   onStart       施放時（被動技能是啟用時）。在下一個 frame 呼叫，跟原本的 CreateTimer(0.0, ...) 一樣是延後執行
//   onEnd         持續時間結束，或被動技能被切換掉
//   onTick        HUD 每 0.5 秒更新時，只呼叫目前選用的技能
//   onCleanup     各種清理時機，原因見 SkillCleanup；每個技能都會呼叫
//   onTakeDamage  玩家受傷時，每個技能都會呼叫
//   onPrecache    OnMapStart 預載資源
// 延遲步驟用 core/scheduler.sp 的 Skill_Schedule。
//
// 技能狀態、持續／冷卻 timer 都是這個檔案的 static：技能檔只能讀（Skill_GetState），不能改。

enum skill_state { SKILL_CD = 2, SKILL_ACT = 1, SKILL_RDY = 0 }

#define SKILL_PASSIVE   (1 << 0)    // 被動技能：選用時就啟用，沒有持續時間、冷卻與 MP 消耗
#define SKILL_HIDDEN    (1 << 1)    // 不出現在選單，只能當作其他技能的替代技能（skill2）

enum SkillCleanup
{
	SKILL_CLEANUP_CONNECT,      // 玩家連線，重設狀態
	SKILL_CLEANUP_INTERRUPT,    // 死亡、斷線、重新初始化（Interrupt_Skill）
	SKILL_CLEANUP_TRANSITION,   // 過關（map_transition）
	SKILL_CLEANUP_ROUND_START,  // 回合重開（投票重開等不走 OnMapEnd 的重置）
	SKILL_CLEANUP_MAP_END,      // 換圖
	SKILL_CLEANUP_RELOAD,       // 插件 reload：OnPluginStart 清掉上一次執行殘留的遊戲狀態
	SKILL_CLEANUP_PLUGIN_END    // 插件卸載
}

typedef SkillClientHook = function void (int client);
typedef SkillCleanupHook = function void (int client, SkillCleanup reason);
typedef SkillDamageHook = function float (int client, float damage);
typedef SkillPrecacheHook = function void ();

enum struct SkillDef
{
	char name[MAXSKILLNAME];
	float duration;
	float cooldown;
	float mpcost;
	int flags;
	int alt;                // skill2 施放的替代技能，-1 表示沒有
	Function onStart;
	Function onEnd;
	Function onTick;
	Function onCleanup;
	Function onTakeDamage;
	Function onPrecache;
}

static SkillDef s_Skills[MAXSKILLS];
static int s_iSkillCount;

// 每位玩家
static int s_iSkill[MAX_PLAYERS + 1];           // 目前選用的技能
static int s_iAltUsing[MAX_PLAYERS + 1];        // 正在施放／冷卻的替代技能，-1 表示沒有
static skill_state s_iState[MAX_PLAYERS + 1];
static float s_fLastUseTime[MAX_PLAYERS + 1];
static Handle s_hDuration[MAX_PLAYERS + 1];
static Handle s_hCooldown[MAX_PLAYERS + 1];

//===========================================================
//========================= 註冊 ============================
//===========================================================

// 回傳技能編號；註冊順序就是選單順序，也是 Skill_GetCurrent 回傳的值
int Skill_Register(const char[] name, float duration, float cooldown, float mpcost, int flags = 0)
{
	if (s_iSkillCount == MAXSKILLS) return -1;
	int skill = s_iSkillCount++;

	strcopy(s_Skills[skill].name, MAXSKILLNAME, name);
	if (flags & SKILL_PASSIVE)
	{
		duration = 0.0;
		cooldown = 0.0;
		mpcost = 0.0;
	}
	s_Skills[skill].duration = duration;
	s_Skills[skill].cooldown = cooldown;
	s_Skills[skill].mpcost = mpcost;
	s_Skills[skill].flags = flags;
	s_Skills[skill].alt = -1;
	s_Skills[skill].onStart = INVALID_FUNCTION;
	s_Skills[skill].onEnd = INVALID_FUNCTION;
	s_Skills[skill].onTick = INVALID_FUNCTION;
	s_Skills[skill].onCleanup = INVALID_FUNCTION;
	s_Skills[skill].onTakeDamage = INVALID_FUNCTION;
	s_Skills[skill].onPrecache = INVALID_FUNCTION;
	return skill;
}

void Skill_OnStart(int skill, SkillClientHook fn)         { s_Skills[skill].onStart = fn; }
void Skill_OnEnd(int skill, SkillClientHook fn)           { s_Skills[skill].onEnd = fn; }
void Skill_OnTick(int skill, SkillClientHook fn)          { s_Skills[skill].onTick = fn; }
void Skill_OnCleanup(int skill, SkillCleanupHook fn)      { s_Skills[skill].onCleanup = fn; }
void Skill_OnTakeDamage(int skill, SkillDamageHook fn)    { s_Skills[skill].onTakeDamage = fn; }
void Skill_OnPrecache(int skill, SkillPrecacheHook fn)    { s_Skills[skill].onPrecache = fn; }

// skill2 指令施放的替代技能。HUD 在 MP 足夠施放替代技能時，改顯示替代技能的名稱與 MP 條
void Skill_SetAlt(int base, int alt)
{
	s_Skills[base].alt = alt;
}

//===========================================================
//======================== 查詢 =============================
//===========================================================

int Skill_GetCurrent(int client)            { return s_iSkill[client]; }
skill_state Skill_GetState(int client)      { return s_iState[client]; }
float Skill_GetLastUseTime(int client)      { return s_fLastUseTime[client]; }
int Skill_GetAlt(int skill)                 { return s_Skills[skill].alt; }
float Skill_GetMPCost(int skill)            { return s_Skills[skill].mpcost; }

// 正在作用的技能：施放替代技能（skill2）後到冷卻結束前是替代技能，其他時候是目前選用的技能
int Skill_GetUsing(int client)
{
	return s_iAltUsing[client] >= 0 ? s_iAltUsing[client] : s_iSkill[client];
}

void Skill_GetDef(int skill, SkillDef def)
{
	def = s_Skills[skill];
}

//===========================================================
//======================= hook 呼叫 =========================
//===========================================================

static void Skill_CallClient(Function fn, int client)
{
	if (fn == INVALID_FUNCTION) return;
	Call_StartFunction(null, fn);
	Call_PushCell(client);
	Call_Finish();
}

// 由 core/hud.sp 每 0.5 秒呼叫
void Skill_CallTick(int client)
{
	Skill_CallClient(s_Skills[s_iSkill[client]].onTick, client);
}

// 由 core/player.sp 的受傷 hook 呼叫
float Skills_OnTakeDamage(int client, float damage)
{
	for (int i = 0; i < s_iSkillCount; i++)
	{
		if (s_Skills[i].onTakeDamage == INVALID_FUNCTION) continue;
		Call_StartFunction(null, s_Skills[i].onTakeDamage);
		Call_PushCell(client);
		Call_PushFloat(damage);
		Call_Finish(damage);
	}
	return damage;
}

void Skills_Cleanup(int client, SkillCleanup reason)
{
	for (int i = 0; i < s_iSkillCount; i++)
	{
		if (s_Skills[i].onCleanup == INVALID_FUNCTION) continue;
		Call_StartFunction(null, s_Skills[i].onCleanup);
		Call_PushCell(client);
		Call_PushCell(reason);
		Call_Finish();
	}
}

// OnMapStart、過關時預載資源
void Skills_Precache()
{
	PrintToServer("=============Material Setup=============");
	// 多個技能共用的資源
	Timescale_Precache();
	SetupMaterial("particles\\skill_fx.pcf");
	PrecacheParticle(PARTICLE_MAGIC_CIRCLE);
	for (int i = 0; i < s_iSkillCount; i++)
	{
		if (s_Skills[i].onPrecache == INVALID_FUNCTION) continue;
		Call_StartFunction(null, s_Skills[i].onPrecache);
		Call_Finish();
	}
	PrintToServer("===========Material Setup End===========");
}

// start 延後到下一個 frame 執行（原本是 CreateTimer(0.0, ...)）
static void Skill_StartNextFrame(int skill, int client)
{
	RequestFrame(Frame_SkillStart, (skill << 8) | client);
}

static void Frame_SkillStart(int data)
{
	Skill_CallClient(s_Skills[data >> 8].onStart, data & 0xFF);
}

//===========================================================
//======================== 狀態機 ===========================
//===========================================================

// OnPluginStart 時呼叫
void Skill_InitClient(int client)
{
	s_iAltUsing[client] = -1;
}

void Init_Skill(int client)
{
	Hud_Start(client);
	MP_StartRecover(client);
	if (s_iSkill[client] < 0 || s_iSkill[client] > s_iSkillCount - 1)
		s_iSkill[client] = 0;
	Skill_MP[client] = INIT_MP;

	if (s_Skills[s_iSkill[client]].flags & SKILL_PASSIVE)
		Skill_Trigger(client);
}

void Delete_Skill(int client)
{
	Hud_Stop(client);
	MP_StopRecover(client);
	Interrupt_Skill(client);
}

// skill1：施放目前選用的技能
void Skill_Cast(int client)
{
	int skill = s_iSkill[client];
	switch (s_iState[client])
	{
		case SKILL_RDY:
		{
			if (MP_Decrease(client, s_Skills[skill].mpcost))
			{
				Skill_StartNextFrame(skill, client);
				Skill_Trigger(client);
			}
			else
			{
				PrintToChat(client, "魔力不足");
			}
		}
		case SKILL_ACT:
		{
			PrintToChat(client, "技能施放中");
		}
		case SKILL_CD:
		{
			PrintToChat(client, "技能冷卻中");
		}
	}
}

// skill2：施放目前技能的替代技能（爆裂 → 隱藏版爆裂）。跟 skill1 一樣要在準備好的狀態才能施放
void Skill_CastAlt(int client)
{
	int alt = s_Skills[s_iSkill[client]].alt;
	if (alt < 0 || Skill_MP[client] < s_Skills[alt].mpcost) return;

	switch (s_iState[client])
	{
		case SKILL_ACT:
		{
			PrintToChat(client, "技能施放中");
			return;
		}
		case SKILL_CD:
		{
			PrintToChat(client, "技能冷卻中");
			return;
		}
	}

	if (MP_Decrease(client, s_Skills[alt].mpcost))
	{
		s_iAltUsing[client] = alt;
		Skill_StartNextFrame(alt, client);
		Skill_Trigger(client);
	}
	else
	{
		PrintToChat(client, "魔力不足");
	}
}

// 進入施放中：一般技能開始計算持續與冷卻，被動技能啟用
void Skill_Trigger(int client)
{
	int skill = Skill_GetUsing(client);
	s_iState[client] = SKILL_ACT;
	if (s_Skills[skill].flags & SKILL_PASSIVE)
	{
		Skill_StartNextFrame(skill, client);
	}
	else
	{
		s_fLastUseTime[client] = GetGameTime();
		s_hCooldown[client] = CreateTimer(s_Skills[skill].cooldown + s_Skills[skill].duration, Timer_SkillReady, client);
		s_hDuration[client] = CreateTimer(s_Skills[skill].duration, Timer_SkillEnd, (skill << 8) | client);
	}
	Hud_Refresh(client, true);
}

static Action Timer_SkillEnd(Handle timer, int data)
{
	int client = data & 0xFF;
	s_hDuration[client] = null;
	s_iState[client] = SKILL_CD;
	Skill_CallClient(s_Skills[data >> 8].onEnd, client);
	if (!Hud_Refresh(client, false))
		Player_OnClientConnected(client);
	return Plugin_Stop;
}

static Action Timer_SkillReady(Handle timer, int client)
{
	s_hCooldown[client] = null;
	s_iAltUsing[client] = -1;
	s_iState[client] = SKILL_RDY;
	if (!Hud_Refresh(client, false))
		Player_OnClientConnected(client);
	return Plugin_Stop;
}

// 被動技能被切換掉（原本是 CreateTimer(0.0, ...)，一樣延後執行）
static void Frame_PassiveEnd(int data)
{
	int client = data & 0xFF;
	s_iState[client] = SKILL_CD;
	Skill_CallClient(s_Skills[data >> 8].onEnd, client);
	Hud_Refresh(client, false);
}

// 一般技能施放中（被動技能一直是施放中，不算）
static bool Skill_IsCasting(int client)
{
	return s_iState[client] == SKILL_ACT && !(s_Skills[Skill_GetUsing(client)].flags & SKILL_PASSIVE);
}

// change_skill：選單。施放中不能切換技能
void Skill_OpenMenu(int client)
{
	if (Skill_IsCasting(client))
		PrintToChat(client, "技能施放中");
	else
		Skill_Change_Menu(client);
}

static void Skill_Change_Menu(int client)
{
	Menu menu = new Menu(Skill_Change_Menu_Handler);
	menu.SetTitle("Choose a Skill...");
	for (int i = 0; i < s_iSkillCount; ++i)
	{
		if (s_Skills[i].flags & SKILL_HIDDEN) continue;
		char info[8];
		char skill_msg[MAXCMD] = "";
		IntToString(i, info, sizeof(info));
		Format(skill_msg, MAXCMD, "  %s", s_Skills[i].name);
		menu.AddItem(info, skill_msg);
	}
	menu.ExitButton = false;
	menu.Display(client, 20);
}

static int Skill_Change_Menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		// 選單是在施放前打開、施放中才選的
		if (Skill_IsCasting(param1))
			PrintToChat(param1, "技能施放中");
		else
			Skill_Change(param1, StringToInt(info));
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

void Skill_Change(int client, int skill)
{
	UnGlow(client);
	int cur = s_iSkill[client];

	if (skill == cur) return;

	// 立刻結束目前的施放與冷卻（觸發 timer 會執行 end / ready）
	switch (s_iState[client])
	{
		case SKILL_ACT:
		{
			if (!(s_Skills[cur].flags & SKILL_PASSIVE))
			{
				if (s_hDuration[client] != null)
					TriggerTimer(s_hDuration[client]);
				if (s_hCooldown[client] != null)
					TriggerTimer(s_hCooldown[client]);
			}
		}
		case SKILL_CD:
		{
			if (s_hCooldown[client] != null)
				TriggerTimer(s_hCooldown[client]);
		}
	}

	if (s_Skills[cur].flags & SKILL_PASSIVE)
		RequestFrame(Frame_PassiveEnd, (cur << 8) | client);

	s_iSkill[client] = skill;

	// 換上的一般技能從冷卻開始，被動技能直接啟用
	if (s_Skills[skill].flags & SKILL_PASSIVE)
	{
		s_iState[client] = SKILL_ACT;
		Skill_StartNextFrame(skill, client);
	}
	else
	{
		s_iState[client] = SKILL_CD;
		s_fLastUseTime[client] = GetGameTime() - s_Skills[skill].duration;
		s_hCooldown[client] = CreateTimer(s_Skills[skill].cooldown, Timer_SkillReady, client);
	}
	Hud_Refresh(client, true);
}

void Interrupt_Skill(int client)
{
	int cur = s_iSkill[client];
	if (!(s_Skills[cur].flags & SKILL_PASSIVE))
	{
		// 直接 delete，不 TriggerTimer — 換圖後 handle 已被 engine 回收，TriggerTimer 會 crash
		if ((s_iState[client] == SKILL_CD) || (s_iState[client] == SKILL_ACT))
			SafeDeleteTimer(s_hCooldown[client]);

		if (s_iState[client] == SKILL_ACT)
			SafeDeleteTimer(s_hDuration[client]);
	}
	MP_StopBoost(client);
	Skill_CancelAllSteps(client);

	// 在重設狀態之前呼叫，技能可以用 Skill_GetUsing / Skill_GetState 判斷是不是施放到一半
	Skills_Cleanup(client, SKILL_CLEANUP_INTERRUPT);
	s_iState[client] = SKILL_RDY;
	s_iAltUsing[client] = -1;
}

//===========================================================
//========================= 清理 ============================
//===========================================================

void Skills_MapEndCleanup()
{
	// 無條件還原遊戲速度並重置狀態變數
	SafeDeleteTimer(Slow_Timer);
	RestoreTimeScale();
	Slow_Ent = 0;

	// 清理所有玩家 timer 與狀態
	for (int i = 1; i <= MAX_PLAYERS; i++)
	{
		Hud_Stop(i);
		MP_StopRecover(i);
		SafeDeleteTimer(s_hCooldown[i]);
		SafeDeleteTimer(s_hDuration[i]);
		MP_StopBoost(i);
		Skill_CancelAllSteps(i);

		s_iState[i]     = SKILL_RDY;
		s_iAltUsing[i]  = -1;
		Invulnerable[i] = false;

		Skills_Cleanup(i, SKILL_CLEANUP_MAP_END);
	}

	// 清理所有 entity 的 glow timer
	for (int i = 0; i < MAXENTITIES; i++)
	{
		SafeDeleteTimer(Glow_Timer[i]);
		State_Glow[i]   = false;
	}

	// 換圖前先 reset 天氣狀態，避免 s_hRestoreTimer 變殭屍 handle 後被 OnMapStart 再 KillTimer
	ResetMagicAtmosphere();
}

// round_start：捕捉 vote restart / RestartScenario 等不走 OnMapEnd 的軟重置
public void Event_SkillsRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	Skills_RoundStartCleanup();
}

void Skills_RoundStartCleanup()
{
	PrintToServer("[skills_mk2] round_start cleanup: EX + skill timers + timescale");
	RestoreTimeScale();
	for (int i = 1; i <= MAX_PLAYERS; i++)
	{
		// 殺掉所有技能 timer（含 Cooldown / Duration），避免隱藏版爆裂的 end 等 callback 在新回合觸發
		SafeDeleteTimer(s_hCooldown[i]);
		SafeDeleteTimer(s_hDuration[i]);
		MP_StopBoost(i);
		Skill_CancelAllSteps(i);

		s_iState[i]     = SKILL_RDY;
		s_iAltUsing[i]  = -1;
		Invulnerable[i] = false;

		Skills_Cleanup(i, SKILL_CLEANUP_ROUND_START);
	}
}

// OnPluginStart：reload 時把上一次執行殘留的遊戲狀態清掉
void Skills_ReloadCleanup()
{
	RestoreTimeScale();
	for (int i = 1; i <= MAX_PLAYERS; i++)
	{
		if (!IsClientInGame(i)) continue;
		Invulnerable[i] = false;
		Skills_Cleanup(i, SKILL_CLEANUP_RELOAD);
	}
}

void Skills_PluginEndCleanup()
{
	RestoreTimeScale();
	for (int i = 1; i <= MAX_PLAYERS; i++)
	{
		if (!IsClientInGame(i)) continue;
		Invulnerable[i] = false;
		Skills_Cleanup(i, SKILL_CLEANUP_PLUGIN_END);
	}
}
