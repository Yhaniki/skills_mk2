// 淨化 Sacred Turn Undead：淨化範圍內殭屍，之後引來屍潮

static int s_iTurnUndead;
static Handle Skill_TurnUndead_Timer[MAX_PLAYERS + 1];
static int g_iChase[MAX_PLAYERS + 1];

int TurnUndead_Register()
{
	s_iTurnUndead = Skill_Register("Sacred Turn Undead 淨化", 3.5, 2.0, 50.0);
	Skill_OnStart(s_iTurnUndead, TurnUndead_OnStart);
	Skill_OnCleanup(s_iTurnUndead, TurnUndead_OnCleanup);
	Skill_OnPrecache(s_iTurnUndead, TurnUndead_OnPrecache);
	return s_iTurnUndead;
}

static void TurnUndead_OnPrecache()
{
	SetupMaterial("sound\\skills\\turn_undead.mp3");
	SetupSound("skills\\turn_undead.mp3", true);
	PrecacheParticle(PARTICLE_TURNUNDEAD);
}

// 換圖、回合重開時殺掉屍潮結束 timer
static void TurnUndead_OnCleanup(int client, SkillCleanup reason)
{
	if (reason == SKILL_CLEANUP_MAP_END || reason == SKILL_CLEANUP_ROUND_START)
		SafeDeleteTimer(Skill_TurnUndead_Timer[client]);
}

public Action Timer_UndeadRushEnd(Handle timer, any userid)
{
	// g_hCvarPanicForever.SetBool(false, false, false);
	// PrintToChatAll("\x01屍潮結束");

	// 用 timer 本身比對要歸零的格子，不能用 GetClientOfUserId：
	// 玩家在 PANIC_SEC 內斷線時 client 會是 0，真正那格會留下殭屍 handle，
	// 之後 cleanup 的 SafeDeleteTimer 或下次淨化的 delete 就會丟 Invalid Handle
	for (int i = 1; i <= MAX_PLAYERS; i++)
	{
		if (Skill_TurnUndead_Timer[i] == timer)
			Skill_TurnUndead_Timer[i] = null;
	}

	int client = GetClientOfUserId(userid);
	if( client && IsClientInGame(client) )
	{
		// Chase
		int entity = g_iChase[client];
		g_iChase[client] = 0;
		if( entity && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE )
			RemoveEntity(entity);
	}
	return Plugin_Stop;
}

// 淨化後 1 秒：引來屍潮
static void TurnUndead_StepRush(int client, DataPack data)
{
	// g_hCvarPanicForever.SetBool(false, false, false);
	StripAndExecuteClientCommand(client, "z_spawn_old", "mob");
	L4D_ForcePanicEvent();

	SafeDeleteTimer(Skill_TurnUndead_Timer[client]);
	Skill_TurnUndead_Timer[client] = CreateTimer(PANIC_SEC, Timer_UndeadRushEnd, GetClientUserId(client));
	int entity = CreateEntityByName("info_goal_infected_chase");
	if( entity != -1 )
	{
		g_iChase[client] = EntIndexToEntRef(entity);

		DispatchSpawn(entity);
		float vPos[3];
		GetClientAbsOrigin(client, vPos);
		vPos[2] += 20.0;
		TeleportEntity(entity, vPos, NULL_VECTOR, NULL_VECTOR);

		SetVariantString("!activator");
		AcceptEntityInput(entity, "SetParent", client);

		static char temp[32];
		Format(temp, sizeof temp, "OnUser4 !self:Kill::%f:-1", PANIC_SEC);
		SetVariantString(temp);
		AcceptEntityInput(entity, "AddOutput");
		AcceptEntityInput(entity, "FireUser4");
	}

	PrintToChatAll("\x04%N \x01施放淨化引來屍潮！", client);
}

// 施放後 2.5 秒：淨化瞄準點周圍的殭屍
static void TurnUndead_StepPurify(int client, DataPack data)
{
	float Pos[3];
	Pos[0] = data.ReadFloat();
	Pos[1] = data.ReadFloat();
	Pos[2] = data.ReadFloat();
	CreateParticle(PARTICLE_TURNUNDEAD, 1.0, Pos);
	for (int i = 1; i <= MaxClients; i++) {
		if (IsAliveSpecialInf(i)) {
			float opos[3];
			GetEntityWorldOrigin(i, opos);
			float distance = GetEntityPosDistance(i, Pos);
			// [淨化DBG] 診斷用：確認每個特感的世界座標與距離，抓騎乘 jockey 是否因距離被漏掉
			PrintToServer("[skills_mk2][淨化DBG] loop i=%d absO=(%.0f,%.0f,%.0f) aim=(%.0f,%.0f,%.0f) dist=%.0f inRange=%d",
				i, opos[0], opos[1], opos[2], Pos[0], Pos[1], Pos[2], distance, distance <= TURN_UNDEAD_DIST);
			if (distance <= TURN_UNDEAD_DIST) {
				// workaround：先把範圍內的特感震一下（stagger）
				// 騎乘中的 jockey / 撲人的 hunter / 壓人的 charger 都會因此脫離受害者，
				// 保證受害隊友被解放；jockey 脫離騎乘後，下面 Turn_Undead 的致命傷害也能正常生效
				L4D_StaggerPlayer(i, client, Pos);
				// DealDamage(i, 500 * RoundToNearest(300.0 - distance) / 300, client, DMG_BURN);
				Turn_Undead(i, client);
			}
		}
	}

	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "infected")) != INVALID_ENT_REFERENCE) {
		int health = GetEntProp(entity, Prop_Data, "m_iHealth");
		if (health > 0) {
			if (GetEntityPosDistance(entity, Pos) <= TURN_UNDEAD_DIST) {
				// DealDamage(entity, 1, client, DMG_BURN);
				Turn_Undead(entity, client);
			}
		}
	}
	while ((entity = FindEntityByClassname(entity, "witch")) != INVALID_ENT_REFERENCE) {
		int health = GetEntProp(entity, Prop_Data, "m_iHealth");
		if (health > 0) {
			if (GetEntityPosDistance(entity, Pos) <= TURN_UNDEAD_DIST) {
				// DealDamage(entity, 1, client, DMG_BURN);
				Turn_Undead(entity, client);
			}
		}
	}

	Skill_Schedule(s_iTurnUndead, client, 1.0, TurnUndead_StepRush);
	// PropaneAtPos(Pos);
}

void TurnUndeadAim(int client, float delay)
{
	PrepareAndEmitSoundtoAll("skills\\turn_undead.mp3", .entity = client, .volume = 1.0);
	float Pos[3];
	GetAimOrigin(client, Pos, 0.1);
	Pos[2] += 10;
	// if (GetAimOrigin(client, Pos, 10.0) == 0) return;

	DataPack data = Skill_Schedule(s_iTurnUndead, client, delay, TurnUndead_StepPurify);
	data.WriteFloat(Pos[0]);
	data.WriteFloat(Pos[1]);
	data.WriteFloat(Pos[2]);
}

static void TurnUndead_OnStart(int client)
{
	GlowForSecs(client, 0, 0, 100, 3.5*time_weight);
	TurnUndeadAim(client, 2.5*time_weight);
	PrintToChatAll("\x04%N \x01淨化!", client);
}
