// 技能系統：註冊、施放、切換、中斷、清理
//
// 過渡期：這個檔案暫時使用 `#pragma newdecls optional`。
// 技能 callback 目前存在 `Timer:` tag 陣列，再強轉交給 CreateTimer；
// 新語法不允許把存起來的 Function 交給 CreateTimer，所以這段舊寫法只能留在這裡。
// 第 2 步改寫成技能框架時，整個檔案會轉成新語法。
#pragma newdecls optional

static Timer:Timer_Skill_Start[MAXSKILLS];
static Timer:Timer_Skill_End[MAXSKILLS];
static Timer:Timer_Skill_Ready[MAXSKILLS];

static Handle Skill_Notify_Ani_Timer[MAX_PLAYERS + 1];
static Handle Skill_MPrecover_Timer[MAX_PLAYERS + 1];

//===========================================================
//========================= 註冊 ============================
//===========================================================

RegisterSkill(String:skill_name[MAXSKILLNAME],
					Timer:timer_skill_start,
					Timer:timer_skill_end,
					Timer:timer_skill_ready,
					Float:skill_duration, Float:skill_cooldown, Float:skill_mpcost)
{
	if (skill_num == MAXSKILLS) return;

	Skill_Name[skill_num] = skill_name;

	Timer_Skill_Start[skill_num] = timer_skill_start;
	Timer_Skill_End[skill_num] = timer_skill_end;
	Timer_Skill_Ready[skill_num] = timer_skill_ready;

	if (skill_cooldown <= 0.0) {
		Skill_Type[skill_num] = TYPE_PASSIVE;
		Skill_Duration[skill_num] = 0.0;
		Skill_Cooldown[skill_num] = 0.0;
		Skill_MPcost[skill_num] = 0.0;
	} else {
		Skill_Type[skill_num] = TYPE_NORMAL;
		Skill_Duration[skill_num] = skill_duration;
		Skill_Cooldown[skill_num] = skill_cooldown;
		Skill_MPcost[skill_num] = skill_mpcost;
	}

	skill_num++;
}

// 以 0 秒 timer 觸發技能的 start callback（core/commands.sp 施放時使用）
void Skill_StartTimer(int skill, int client)
{
	CreateTimer(0.0, Timer:Timer_Skill_Start[skill], client);
}

//===========================================================
//====================== Skill System =======================
//===========================================================

void Init_Skill(int client)
{
	if(Skill_Notify_Timer[client]!=null)
		delete Skill_Notify_Timer[client];
	if(Skill_Notify_Ani_Timer[client]!=null)
		delete Skill_Notify_Ani_Timer[client];
	if(Skill_MPrecover_Timer[client]!=null)
		delete Skill_MPrecover_Timer[client];
	Skill_Notify_Timer[client] = CreateTimer(0.5, Skill_Notify, client, TIMER_REPEAT);
	Skill_Notify_Ani_State[client] = 0;
	Skill_Notify_Ani_Timer[client] = CreateTimer(0.5, Skill_Notify_Ani, client, TIMER_REPEAT);
	Skill_MPrecover_Timer[client] = CreateTimer(1.0, Skill_MPrecover, client, TIMER_REPEAT);
	// PrintToChatAll("Timer for %N created!", client);
	if(Skill[client]<0||Skill[client]>skill_num-1)
		Skill[client] = 0;
	Skill_MP[client] = INIT_MP;

	if (Skill_Type[Skill[client]] == TYPE_PASSIVE)
		Skill_Trigger(client);
}

void Delete_Skill(int client)
{
	if(Skill_Notify_Timer[client]!=null)
		delete Skill_Notify_Timer[client];
	if(Skill_Notify_Ani_Timer[client]!=null)
		delete Skill_Notify_Ani_Timer[client];
	if(Skill_MPrecover_Timer[client]!=null)
		delete Skill_MPrecover_Timer[client];

	// if(Skill_Cooldown_Timer[client]!=null)
	// 	delete Skill_Cooldown_Timer[client];
	// if(Skill_Duration_Timer[client]!=null)
	// 	delete Skill_Duration_Timer[client];
	Interrupt_Skill(client);
}

void Skill_Trigger(int client)
{
	int skill_using = Skill[client];
	if(Skill_EX_Using[client])
	{
		skill_using = skill_num-1;
	}
	switch (Skill_Type[skill_using])
	{
		case TYPE_NORMAL:
		{
			Skill_State[client] = SKILL_ACT;
			Skill_LastUseTime[client] = GetGameTime();

			Skill_Cooldown_Timer[client] = CreateTimer(Skill_Cooldown[skill_using] + Skill_Duration[skill_using], Timer_Skill_Ready[skill_using], client);
			Skill_Duration_Timer[client] = CreateTimer(Skill_Duration[skill_using], Timer: Timer_Skill_End[skill_using], client);
		}
		case TYPE_PASSIVE:
		{
			Skill_State[client] = SKILL_ACT;
			CreateTimer(0.0, Timer: Timer_Skill_Start[skill_using], client);
		}
	}

	TriggerTimer(Skill_Notify_Timer[client], true);
}

public int Skill_Change_Menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		Skill_Change(param1, param2);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

void Skill_Change_Menu(int client)
{
	Menu menu = new Menu(Skill_Change_Menu_Handler);
	menu.SetTitle("Choose a Skill...");
	for (int i = 0; i < skill_num-1; ++i) {//TODO: hidden explosion full option
		char skill_msg[MAXCMD] = "";
		Format(skill_msg, MAXCMD, "  %s", Skill_Name[i]);
		menu.AddItem("", skill_msg);
	}
	menu.ExitButton = false;
	menu.Display(client, 20);
}

void Skill_Change(int client, int skill)
{
	UnGlow(client);
	int skill_using = Skill[client];

	if (skill == skill_using) return;

	switch (Skill_State[client]) {
		case SKILL_RDY: {
		}
		case SKILL_ACT: {
			if (Skill_Type[skill_using] == TYPE_NORMAL) {
				TriggerTimer(Skill_Duration_Timer[client]);
				TriggerTimer(Skill_Cooldown_Timer[client]);
			}
		}
		case SKILL_CD: {
			TriggerTimer(Skill_Cooldown_Timer[client]);
		}
	}

	switch (Skill_Type[skill_using]) {
		case TYPE_NORMAL: {
		}
		case TYPE_PASSIVE: {
			CreateTimer(0.0, Timer:Timer_Skill_End[skill_using], client);
		}
	}

	Skill[client] = skill;
	skill_using = Skill[client];

	switch (Skill_Type[skill_using]) {
		case TYPE_NORMAL: {
			Skill_State[client] = SKILL_CD;
			Skill_LastUseTime[client] = GetGameTime() - Skill_Duration[skill_using];
			Skill_Cooldown_Timer[client] = CreateTimer(Skill_Cooldown[skill_using], Timer:Timer_Skill_Ready[skill_using], client);
		}
		case TYPE_PASSIVE: {
			Skill_State[client] = SKILL_ACT;
			CreateTimer(0.0, Timer:Timer_Skill_Start[skill_using], client);
		}
	}
	TriggerTimer(Skill_Notify_Timer[client], true);
}

void Interrupt_Skill(int client)
{
	int skill_using = Skill[client];
	if (Skill_Type[skill_using]==TYPE_NORMAL)
	{
		// 直接 delete，不 TriggerTimer — 換圖後 handle 已被 engine 回收，TriggerTimer 會 crash
		if ((Skill_State[client] == SKILL_CD) || (Skill_State[client] == SKILL_ACT))
			SafeDeleteTimer(Skill_Cooldown_Timer[client]);

		if (Skill_State[client] == SKILL_ACT)
			SafeDeleteTimer(Skill_Duration_Timer[client]);
	}
	if (State_Adrenaline_Boost[client])
	{
		SafeDeleteTimer(Skill_Adrenaline_Boost_Timer[client]);
		State_Adrenaline_Boost[client] = false;
	}

	Skill_State[client] = SKILL_RDY;
}

// 沒有特殊結束／冷卻行為的技能共用
public Action Timer_Skill_Null_End(Handle timer, any client)
{
	Skill_Duration_Timer[client] = null;
	Skill_State[client] = SKILL_CD;
	if(Skill_Notify_Timer[client]!=null)
		TriggerTimer(Skill_Notify_Timer[client]);
	else
		Player_OnClientConnected(client);
	return Plugin_Stop;
}

public Action Timer_Skill_Null_Ready(Handle timer, any client)
{
	Skill_Cooldown_Timer[client] = null;
	Skill_State[client] = SKILL_RDY;
	if(Skill_Notify_Timer[client]!=null)
		TriggerTimer(Skill_Notify_Timer[client]);
	else
		Player_OnClientConnected(client);
	return Plugin_Handled;
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
		SafeDeleteTimer(Skill_Notify_Timer[i]);
		SafeDeleteTimer(Skill_Notify_Ani_Timer[i]);
		SafeDeleteTimer(Skill_MPrecover_Timer[i]);
		SafeDeleteTimer(Skill_Cooldown_Timer[i]);
		SafeDeleteTimer(Skill_Duration_Timer[i]);
		SafeDeleteTimer(Skill_Adrenaline_Boost_Timer[i]);
		TurnUndead_KillRushTimer(i);

		Skill_State[i]            = SKILL_RDY;
		Invulnerable[i]           = false;
		Skill_EX_Using[i]         = false;
		State_Adrenaline_Boost[i] = false;
		State_ManaShield[i]       = false;

		CleanupEXSkill(i); // 殺掉 EX timer + particle
		KillMagicCircle(i);
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

// 由 lib/dissolve.sp 的 Event_RoundStart 呼叫
// 捕捉 vote restart / RestartScenario 等不走 OnMapEnd 的軟重置
void Skills_RoundStartCleanup()
{
	PrintToServer("[skills_mk2] round_start cleanup: EX + skill timers + timescale");
	RestoreTimeScale();
	for (int i = 1; i <= MAX_PLAYERS; i++)
	{
		// 殺掉所有技能 timer（含 Cooldown / Duration），避免 Timer_Skill_EX_End 等 callback 在新回合觸發
		SafeDeleteTimer(Skill_Cooldown_Timer[i]);
		SafeDeleteTimer(Skill_Duration_Timer[i]);
		SafeDeleteTimer(Skill_Adrenaline_Boost_Timer[i]);
		TurnUndead_KillRushTimer(i);

		CleanupEXSkill(i);
		Skill_State[i]            = SKILL_RDY;
		Invulnerable[i]           = false;
		Skill_EX_Using[i]         = false;
		State_Adrenaline_Boost[i] = false;
		State_ManaShield[i]       = false;
		KillMagicCircle(i);
	}
}

void Skills_PluginEndCleanup()
{
	RestoreTimeScale();

	for (int i = 1; i <= MAX_PLAYERS; i++)
	{
		if (!IsClientInGame(i)) continue;
		if (State_ManaShield[i]) UnGlow(i);
		State_ManaShield[i] = false;
		Invulnerable[i]     = false;
		KillMagicCircle(i);
		CleanupEXSkill(i);
	}

	ManaShield_RestoreMeleeRange();
}

#pragma newdecls required
