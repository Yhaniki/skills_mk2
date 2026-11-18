// 玩家狀態：連線、死亡、倒地、過關、受傷 hook、無敵

enum player_state { PLAYER_ALIVE = 2, PLAYER_INCAP = 1, PLAYER_DEAD = 0 }

bool State_Connection[MAX_PLAYERS + 1];
bool State_Transition[MAX_PLAYERS + 1];
player_state State_Player[MAX_PLAYERS + 1];
bool Invulnerable[MAX_PLAYERS + 1];

static bool Hooked[MAX_PLAYERS + 1];

//===========================================================
//==================== State Transition =====================
//===========================================================

// 由 main.sp 的 OnClientConnected 呼叫；MP 條或技能狀態異常時其他模組也會呼叫來重設
void Player_OnClientConnected(int client)
{
	if (State_Connection[client]) Delete_Skill(client);
	if (!IsPlayer(client)) return;
	State_Connection[client] = true;
	State_Transition[client] = false;
	State_Player[client] = PLAYER_DEAD;
	if ((IsClientInGame(client) == true) &&
		(IsFakeClient(client) == false) &&
		(IsPlayerAlive(client) == true))
		State_Player[client] = PLAYER_ALIVE;
	MP_StopBoost(client);
	Skills_Cleanup(client, SKILL_CLEANUP_CONNECT);
	Hooked[client] = false;
	Init_Skill(client);
	PrintPlayerState("connect", client);
}

void Player_OnClientPostAdminCheck(int client)
{
	if(IsClientInGame(client) && !IsFakeClient(client))
	{
		SDKHook(client, SDKHook_OnTakeDamage, Event_Hurt);
		Hooked[client] = true;
	}
}

void Player_OnClientDisconnect(int client)
{
	if(Hooked[client])
		SDKUnhook(client, SDKHook_OnTakeDamage, Event_Hurt);
	KillMagicCircle(client);
}

void CheckPlayerConnections()
{
	for (int i = 1; i < MAX_PLAYERS; i++) {
		if (IsClientInGame(i)){
			Player_OnClientConnected(i);
			SDKHook(i, SDKHook_OnTakeDamage, Event_Hurt);
		}
	}
}

public void Event_Draw(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i < MAX_PLAYERS; i++) {
		State_Transition[i] = false;
	}
}

public void Event_NoDraw(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i < MAX_PLAYERS; i++) {
		State_Transition[i] = true;
	}
}

public void Event_StateTransition(Event event, const char[] name, bool dontBroadcast)
{
	// map_transition 沒有 userid，需要對所有玩家做清理後直接 return
	if (StrEqual(name, "map_transition"))
	{
		for (int i = 1; i <= MAX_PLAYERS; i++)
		{
			if (!State_Connection[i]) continue;
			State_Transition[i] = true;
			Interrupt_Skill(i);
			Skills_Cleanup(i, SKILL_CLEANUP_TRANSITION);
		}
		return;
	}

	int client = 0;

	if (StrEqual(name, "player_disconnect") ||
		StrEqual(name, "player_spawn") ||
		StrEqual(name, "player_death") ||
		StrEqual(name, "player_incapacitated") ||
		StrEqual(name, "player_transitioned"))
	{
		client = GetClientOfUserId(event.GetInt("userid"));
	}
	else if (StrEqual(name, "revive_success"))
	{
		client = GetClientOfUserId(event.GetInt("subject"));
	}
	else if (StrEqual(name, "player_afk"))
	{
		client = GetClientOfUserId(event.GetInt("player"));
	}

	if (!IsPlayer(client)) return;

	if (StrEqual(name, "player_disconnect")) {
		State_Connection[client] = false;
		State_Player[client] = PLAYER_DEAD;
		Delete_Skill(client);
	} else if (StrEqual(name, "player_transitioned")) {
		State_Transition[client] = false;
		Skills_Precache();
	} else if (StrEqual(name, "player_spawn") || StrEqual(name, "revive_success")) {
		State_Player[client] = PLAYER_ALIVE;
	} else if (StrEqual(name, "player_incapacitated")) {
		State_Player[client] = PLAYER_INCAP;
	} else if (StrEqual(name, "player_death")) {
		State_Player[client] = PLAYER_DEAD;
		Interrupt_Skill(client);
	} else if (StrEqual(name, "player_afk")) {
		UnGlow(client);
	}

	//if (!StrEqual(name, "player_disconnect")) Hud_Refresh(client, true);
	PrintPlayerState(name, client);
}

void PrintPlayerState(const char[] name, int client)
{
	PrintToServer("========== EVENT: %s %N", name, client);
	PrintToServer("========== STATE: %d %d %d", State_Connection[client], State_Transition[client], State_Player[client]);
}

//===========================================================
//========================= 受傷 ============================
//===========================================================

public Action Event_Hurt(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(victim > MAX_PLAYERS || victim < 1)
		return Plugin_Continue;

	if(Invulnerable[victim])
		damage = 0.0;

	damage = Skills_OnTakeDamage(victim, damage);
	return Plugin_Changed;
}

//===========================================================
//========================= 無敵 ============================
//===========================================================

// left4dhooks 的抓人／撲人／騎乘／衝撞 forward 共用：無敵時擋掉
Action Invuln_Block(int victim)
{
	if(Invulnerable[victim])
		return Plugin_Handled;
	else
		return Plugin_Continue;
}

Action Invuln_OnPummelVictim(int attacker, int victim)
{
	// from "left4dhooks_test.sp"
	if(Invulnerable[victim])
	{
		DataPack pack = new DataPack();
		RequestFrame(OnPummelTeleport, pack);
		pack.WriteCell(GetClientUserId(victim));
		pack.WriteCell(GetClientUserId(attacker));

		// To block the stumble animation, uncomment and use the following 2 lines:
		AnimHookEnable(victim, OnPummelOnAnimPre, INVALID_FUNCTION);
		CreateTimer(0.3, Timer_OnPummelResetAnim, GetClientUserId(victim));

		return Plugin_Handled;
	}
	else
		return Plugin_Continue;
}

// To fix getting stuck use this:
void OnPummelTeleport(DataPack pack)
{
	pack.Reset();
	int victim = pack.ReadCell();
	int attacker = pack.ReadCell();
	delete pack;

	victim = GetClientOfUserId(victim);
	if (!victim || !IsClientInGame(victim)) return;

	attacker = GetClientOfUserId(attacker);
	if (!attacker || !IsClientInGame(attacker)) return;

	SetVariantString("!activator");
	AcceptEntityInput(victim, "SetParent", attacker);
	TeleportEntity(victim, view_as<float>({50.0, 0.0, 0.0}), NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(victim, "ClearParent");
}

// To block the stumble animation use the next two functions:
Action OnPummelOnAnimPre(int client, int &anim)
{
	if(Invulnerable[client])
	{
		if (anim == L4D2_ACT_TERROR_SLAMMED_WALL || anim == L4D2_ACT_TERROR_SLAMMED_GROUND)
		{
			anim = L4D2_ACT_STAND;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

Action Timer_OnPummelResetAnim(Handle timer, int client)
{
	// Don't need client userID since
	// it's not going to be validated just removed
	// if ((client = GetClientOfUserId(client)))
	AnimHookDisable(client, OnPummelOnAnimPre);

	return Plugin_Continue;
}
