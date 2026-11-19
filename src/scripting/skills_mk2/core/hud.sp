// HUD：技能提示文字與 MP 條

static Handle s_hNotify[MAX_PLAYERS + 1];   // 每 0.5 秒更新 HUD
static Handle s_hAni[MAX_PLAYERS + 1];      // 每 0.5 秒推進「準備好」的 > < 動畫
static int    s_iAni[MAX_PLAYERS + 1];

void Hud_Start(int client)
{
	if (s_hNotify[client] != null)
		delete s_hNotify[client];
	if (s_hAni[client] != null)
		delete s_hAni[client];
	s_hNotify[client] = CreateTimer(0.5, Skill_Notify, client, TIMER_REPEAT);
	s_iAni[client] = 0;
	s_hAni[client] = CreateTimer(0.5, Skill_Notify_Ani, client, TIMER_REPEAT);
}

void Hud_Stop(int client)
{
	SafeDeleteTimer(s_hNotify[client]);
	SafeDeleteTimer(s_hAni[client]);
}

// 立刻更新一次 HUD。reset 為 true 時重新計算下一次 0.5 秒更新的時間。
// 還沒有 HUD timer（玩家尚未初始化）時回傳 false，由呼叫端決定要不要重新初始化
bool Hud_Refresh(int client, bool reset)
{
	if (s_hNotify[client] == null) return false;
	TriggerTimer(s_hNotify[client], reset);
	return true;
}

// 每 0.5 秒更新（TIMER_REPEAT，必須回傳 Plugin_Continue）
public Action Skill_Notify(Handle timer, any client)
{
	if (State_Transition[client] || (State_Player[client] == PLAYER_DEAD) || !IsClientInGame(client) || !IsPlayer(client)) return Plugin_Continue;

	char str[MAXCMD] = "";
	char state[MAXCMD] = "";
	char name[MAXCMD] = "";         // 準備好時顯示的名稱（MP 夠施放替代技能時是替代技能）
	char curName[MAXCMD] = "";
	char activeName[MAXCMD] = "";
	int curSkill = Skill_GetCurrent(client);
	int activeSkill = Skill_GetUsing(client);
	SkillDef cur, active;
	Skill_GetDef(curSkill, cur);
	Skill_GetDef(activeSkill, active);
	// 名稱與狀態文字用這位玩家的語言
	Skill_GetName(curSkill, client, curName, sizeof(curName));
	Skill_GetName(activeSkill, client, activeName, sizeof(activeName));

	// 目前技能每 0.5 秒要做的事（魔心護盾補啟用與發光、鷹眼持續偵測）
	Skill_CallTick(client);

	// MP 足夠施放替代技能（skill2）時顯示替代技能的名稱
	if (cur.alt >= 0 && Skill_MP[client] >= Skill_GetMPCost(cur.alt))
	{
		Skill_GetName(cur.alt, client, name, sizeof(name));
	}
	else
	{
		strcopy(name, MAXCMD, curName);
	}
	switch (Skill_GetState(client)) {
		case SKILL_RDY: {
			if (Skill_MP[client] < active.mpcost) {
				Format(str, MAXCMD, "%s", curName);
			} else {
				switch (s_iAni[client]) {
					case 0: {
						Format(str, MAXCMD, ">    %s    <", name);
					}
					case 1: {
						Format(str, MAXCMD, " >   %s   < ", name);
					}
					case 2: {
						Format(str, MAXCMD, "  >  %s  <  ", name);
					}
				}
			}
			if(Skill_MP[client] >= active.mpcost)
			{
				Format(state, MAXCMD, " ");
			}else
			{
				Format(state, MAXCMD, "%T", "Hud_NoMana", client, active.mpcost);
			}
		}
		case SKILL_ACT: {
			Format(str, MAXCMD, " -  %s  - ", activeName);
			Format(state, MAXCMD, "%T", "Hud_Active", client);
		}
		case SKILL_CD: {
			float time = (active.cooldown + active.duration - (GetGameTime() - Skill_GetLastUseTime(client)));
			Format(str, MAXCMD, "%s", activeName);
			Format(state, MAXCMD, "%T", "Hud_Cooldown", client, time);
		}
	}
	Skill_Notify_MPbar(str, state, client);
	return Plugin_Continue;
}

void Skill_Notify_MPbar(const char[] str, const char[] state, int client)
{
	char bar[MAXCMD] = "";
	char dot[MAXCMD] = "";
	float resolution = MP_BAR_SIZE/MP_MAX;
	if(Invulnerable[client])
	{
		Skill_MP[client]=0.0;
	}
	int alt = Skill_GetAlt(Skill_GetCurrent(client));
	bool altReady = alt >= 0 && Skill_MP[client] >= Skill_GetMPCost(alt);
	int bar_amount = RoundToFloor(Skill_MP[client] * resolution);
	for (int i = 0; i < bar_amount; i++) {
		if (State_Adrenaline_Boost[client]) {
			Format(dot, MAXCMD, "%s/", dot);
		}
		else if (altReady)
		{
			if(i<13){
				Format(dot, MAXCMD, "%s▓", dot);
			}
		}
		else {
			Format(bar, MAXCMD, "%s|", bar);
		}
	}
	if (State_ManaShield[client]) {
		Format(dot, MAXCMD, "%s) ", dot);
	}
	float weight = 1.2;
	int size = RoundToFloor((MP_BAR_SIZE - bar_amount)*weight);
	// PrintToServer("%d size",size);
	for (int i = 0; i <size; i++) {
		Format(dot, MAXCMD, "%s ", dot);
	}

	// 過場中不顯示：每 0.5 秒重送提示文字會讓畫面一直閃。
	// 只擋顯示，上面把 MP 歸零、技能的 tick 都照常執行。
	// 畫面上最後一則 MP 條不主動清掉，讓它自己淡掉。不要用 PrintHintText(client, "") 清：
	// L4D2 客戶端收到空的提示會顯示殘留的記憶體內容，變成一個裝著亂碼的小框（全隊倒地、任務失敗時看得到）
	if (Player_InCutscene(client))
		return;
	PrintHintText(client, "%s\n[%s%s] MP %d\n%s", str, bar, dot, RoundToFloor(Skill_MP[client]),state);
}

// 選單提示的 > < 動畫（TIMER_REPEAT，必須回傳 Plugin_Continue）
public Action Skill_Notify_Ani(Handle timer, any client)
{
	s_iAni[client]++;
	if (s_iAni[client] > 2) s_iAni[client] = 0;
	Hud_Refresh(client, true);
	return Plugin_Continue;
}
