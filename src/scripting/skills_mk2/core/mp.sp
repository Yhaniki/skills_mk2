// MP 系統：增減、每秒回復、擊殺吸取、補給品回復、腎上腺素加倍

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
	if (Skill_Notify_Timer[client] != null &&
		Skill_Notify_Timer[client] != INVALID_HANDLE)
	{
		TriggerTimer(Skill_Notify_Timer[client], true);
	}
	else
	{
		Player_OnClientConnected(client);
	}
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
	Skill_Adrenaline_Boost_Timer[client] = CreateTimer(20.0, Skill_Adrenaline_Boost_End, client);
}

public Action Skill_Adrenaline_Boost_End(Handle timer, any client)
{
	Skill_Adrenaline_Boost_Timer[client] = null;
	State_Adrenaline_Boost[client] = false;
	return Plugin_Stop;
}
