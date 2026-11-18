// MP 系統：增減、每秒回復、擊殺吸取、補給品回復、腎上腺素加倍

float Skill_MP[MAX_PLAYERS + 1];
bool State_Adrenaline_Boost[MAX_PLAYERS + 1];

static Handle s_hBoost[MAX_PLAYERS + 1];
static Handle s_hRecover[MAX_PLAYERS + 1];

bool MP_Decrease(int client, float mp)
{
	if (Skill_MP[client] < mp) {
		return false;
	} else {
#if (!SKILL_DEBUG)
		Skill_MP[client] -= mp;
#endif
		return true;
	}
}

void MP_Increase(int client, float mp)
{
	if (State_Adrenaline_Boost[client]) {
		Skill_MP[client] += mp * 2.0;
	} else {
		Skill_MP[client] += mp;
	}
	if (Skill_MP[client] > MP_MAX) Skill_MP[client] = MP_MAX;
	if (!Hud_Refresh(client, true))
		Player_OnClientConnected(client);
}

void MP_StartRecover(int client)
{
	if (s_hRecover[client] != null)
		delete s_hRecover[client];
	s_hRecover[client] = CreateTimer(1.0, Skill_MPrecover, client, TIMER_REPEAT);
}

void MP_StopRecover(int client)
{
	SafeDeleteTimer(s_hRecover[client]);
}

// 每秒回復（TIMER_REPEAT，必須回傳 Plugin_Continue）
public Action Skill_MPrecover(Handle timer, any client)
{
	MP_Increase(client, MP_INC_PERSEC);
	return Plugin_Continue;
}

public void Event_MPleech(Event event, const char[] name, bool dontBroadcast)
{
	//PrintToChatAll("Leeching?");
	int client = GetClientOfUserId(event.GetInt("userid"));
	int entity = event.GetInt("entityid");
	if (IsSpecialInf(client)) {
		for (int i = 1; i <= MAX_PLAYERS; i++) {
			if (State_Connection[i]) MP_Increase(i, 5.0);
		}
	} else if (IsInf(entity)) {
		for (int i = 1; i <= MAX_PLAYERS; i++) {
			if (State_Connection[i]) MP_Increase(i, 0.5);
		}
	}
}

public void Event_MPGain(Event event, const char[] name, bool dontBroadcast)
{
	int client;
	if (StrEqual(name, "heal_success")) {
		client = GetClientOfUserId(event.GetInt("subject"));
		if (State_Connection[client]) MP_Increase(client, 100.0);
	} else if (StrEqual(name, "pills_used")) {
		client = GetClientOfUserId(event.GetInt("subject"));
		if (State_Connection[client]) MP_Increase(client, 50.0);
	} else if (StrEqual(name, "adrenaline_used")) {
		client = GetClientOfUserId(event.GetInt("userid"));
		if (State_Connection[client]) {
			MP_Increase(client, 25.0);
			Skill_Adrenaline_Boost(client);
		}
	}
}

void Skill_Adrenaline_Boost(int client)
{
	State_Adrenaline_Boost[client] = true;
	s_hBoost[client] = CreateTimer(20.0, Skill_Adrenaline_Boost_End, client);
}

public Action Skill_Adrenaline_Boost_End(Handle timer, any client)
{
	s_hBoost[client] = null;
	State_Adrenaline_Boost[client] = false;
	return Plugin_Stop;
}

// 中斷技能、換圖、回合重開時取消腎上腺素加倍
void MP_StopBoost(int client)
{
	SafeDeleteTimer(s_hBoost[client]);
	State_Adrenaline_Boost[client] = false;
}
