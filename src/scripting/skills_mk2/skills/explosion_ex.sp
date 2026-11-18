// 隱藏版爆裂 EXPLOSION ☆爆裂★（skill2 指令施放）
static float explosion_ex_delay_secs = 25.0;

// EX 爆裂★ 追蹤：timer handles + particle entity refs + 爆炸座標
static Handle g_hExExplosionTimer[MAX_PLAYERS + 1];
static Handle g_hExAfterTimer[MAX_PLAYERS + 1];
static float  g_fExPos[MAX_PLAYERS + 1][3];
static int    g_iExGlowBigRef[MAX_PLAYERS + 1]; // PARTICLE_EX_GLOW_BIG
static int    g_iExGlowRef[MAX_PLAYERS + 1];    // PARTICLE_EX_GLOW (ParticleFollow)
static int    g_iExLightRef[MAX_PLAYERS + 1];   // PARTICLE_EX_LIGHT (ParticleFollow)
static int    g_iExDynLightRef[MAX_PLAYERS + 1];// light_dynamic 強光照亮魔法陣

void ExplosionEx_Register()
{
	RegisterSkill("EXPLOSION ☆爆裂★", Timer_Skill_EX_Start, Timer_Skill_EX_End, Timer_Skill_EX_Ready, explosion_ex_delay_secs+2.0, 2.0, 100.0);
}

// OnPluginStart 時重置追蹤用的 handle / ref
void ExplosionEx_InitState(int client)
{
	g_hExExplosionTimer[client] = null;
	g_hExAfterTimer[client]     = null;
	g_iExGlowBigRef[client]     = INVALID_ENT_REFERENCE;
	g_iExGlowRef[client]        = INVALID_ENT_REFERENCE;
	g_iExLightRef[client]       = INVALID_ENT_REFERENCE;
	g_iExDynLightRef[client]    = INVALID_ENT_REFERENCE;
}

static float beaPos[3];
void NukeExplosion(int attacker, const float vPos[3] = NULL_VECTOR)
{
	const float distanceConstant = 13888.0;
	beaPos[0] = vPos[0];
	beaPos[1] = vPos[1];
	beaPos[2] = vPos[2];
	int particle = CreateEntityByName("info_particle_system");
	if (particle != -1)
	{
		// int type = GetConVarInt(g_hParticle);
		int type = 2;
		if (type == 1)
		{
			DispatchKeyValue(particle, "effect_name", PARTICLE_NUKE1);
		}
		else if (type == 2)
		{
			DispatchKeyValue(particle, "effect_name", PARTICLE_NUKE2);
		}

		DispatchSpawn(particle);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "start");

		TeleportEntity(particle, vPos, NULL_VECTOR, NULL_VECTOR);

		SetVariantString("OnUser1 !self:Kill::45.0:-1");
		AcceptEntityInput(particle, "AddOutput");
		AcceptEntityInput(particle, "FireUser1");
	}

	float Pos[3];
	char tName[64];
	int g_hNukeRadius = 99999;
	for (int i = 1; i <= GetEntityCount(); i++)
	{
		if (!IsValidEntity(i))
			continue;

		DataPack DP = new DataPack();
		DP.WriteCell(attacker);
		DP.WriteCell(i);
		float time = 0.0;
		if (IsValidClient(i) && GetClientTeam(i) == 3)
		{
			Fade(i, 255, 50, 80, 100, 800, 1);
			GetEntPropVector(i, Prop_Send, "m_vecOrigin", Pos);
			time = GetVectorDistance(vPos, Pos) / distanceConstant;
			if (GetVectorDistance(beaPos, Pos) > g_hNukeRadius)
				return;
			CreateTimer(time, ShockWave, DP);
		}
		if (IsValidClient(i) && GetClientTeam(i) == 2)
		{
			Fade(i, 255, 120, 80, 100, 800, 1);
			GetEntPropVector(i, Prop_Send, "m_vecOrigin", Pos);
			time = GetVectorDistance(vPos, Pos) / distanceConstant;
			if (GetVectorDistance(beaPos, Pos) > g_hNukeRadius)
				return;
			CreateTimer(time, ShockWave, DP);
		}
		else
		{
			GetEntityClassname(i, tName, sizeof(tName));
			if (StrEqual(tName, "witch", false))
			{
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Pos);
				time = GetVectorDistance(vPos, Pos) / distanceConstant;
				CreateTimer(time, ShockWave, DP);
			}
			else if (StrEqual(tName, "infected", false))
			{
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Pos);
				time = GetVectorDistance(vPos, Pos) / distanceConstant;
				CreateTimer(time, ShockWave, DP);
			}
			else if (StrEqual(tName, "prop_physics", false))
			{
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Pos);
				time = GetVectorDistance(vPos, Pos) / distanceConstant;
				CreateTimer(time, ShockWave, DP);
			}
			else if (StrEqual(tName, "prop_physics_multiplayer", false))
			{
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Pos);
				time = GetVectorDistance(vPos, Pos) / distanceConstant;
				CreateTimer(time, ShockWave, DP);
			}
			else if (StrEqual(tName, "prop_physics_override", false))
			{
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Pos);
				time = GetVectorDistance(vPos, Pos) / distanceConstant;
				CreateTimer(time, ShockWave, DP);
			}
		}
	}
}

void ThrowEntity(int entity)
{
	float Pos[3];
	float qqAA[3];
	float qqDA[3];
	float qqVv[3];
	float g_hNukeRadius = 999999.0;
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", Pos);
	if (GetVectorDistance(beaPos, Pos) > g_hNukeRadius)
		return;
	MakeVectorFromPoints(beaPos, Pos, qqAA);
	GetVectorAngles(qqAA, qqDA);
	qqDA[0] = qqDA[0] - 40.0;
	GetAngleVectors(qqDA, qqVv, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(qqVv, qqVv);
	ScaleVector(qqVv, 1200.0);
	TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, qqVv);
}

float ComputeShakeDmg(float maxDamage, float distance, float range)
{
	distance/=1000.0;
	float dmg = maxDamage/(distance*distance);
	if (dmg < 0.0) dmg = 0.0;
	if(distance>range) dmg = 0.0;
	return dmg;
}

public Action ShockWave(Handle timer, DataPack DP)
{
	float g_hNukeDamage = 20000.0;
	float nukeDamageRange = 5000.0;
	char tName[64];

	DP.Reset();
	int attacker = DP.ReadCell();
	int entity = DP.ReadCell();

	if (!IsValidEntity(entity))
		return Plugin_Continue;
	float distance = GetEntityPosDistance(entity, beaPos);
	float damage = ComputeShakeDmg(g_hNukeDamage, distance, nukeDamageRange);
	if (IsValidClient(entity) && GetClientTeam(entity) == 3)//special infected
	{
		damage*=damage;
		IgniteEntity(entity, 999.9);
		if (!IsFakeClient(entity))
			EmitSoundToClient(entity, NUKE_SOUND);

		ThrowEntity(entity);

		if (!IsFakeClient(entity))
			Shake(entity, 32.0);

		switch (GetRandomInt(0, 1))
		{
		case 0:
			SDKHooks_TakeDamage(entity, attacker, attacker, damage, DMG_BURN);
		case 1:
			SDKHooks_TakeDamage(entity, attacker, attacker, damage, DMG_BLAST);
		}
	}
	if (IsValidClient(entity) && GetClientTeam(entity) == 2)//survivor
	{
		if (!IsFakeClient(entity))
			EmitSoundToClient(entity, NUKE_SOUND);
		StaggerClient(GetClientUserId(entity), beaPos);
		if (!IsFakeClient(entity))
			Shake(entity, 32.0);
		damage *= 0.07;
		switch (GetRandomInt(0, 1))
		{
		case 0:
			SDKHooks_TakeDamage(entity, attacker, attacker, damage, DMG_BURN);
		case 1:
			SDKHooks_TakeDamage(entity, attacker, attacker, damage, DMG_BLAST);
		}
	}
	else
	{
		GetEntityClassname(entity, tName, sizeof(tName));
		if (StrEqual(tName, "witch", false))
		{
			IgniteEntity(entity, 999.9);
			switch (GetRandomInt(0, 1))
			{
			case 0:
				SDKHooks_TakeDamage(entity, attacker, attacker, damage, DMG_BURN);
			case 1:
				SDKHooks_TakeDamage(entity, attacker, attacker, damage, DMG_BLAST);
			}
		}
		else if (StrEqual(tName, "infected", false))
		{
			IgniteEntity(entity, 999.9);
			switch (GetRandomInt(0, 1))
			{
			case 0:
				SDKHooks_TakeDamage(entity, attacker, attacker, damage, DMG_BURN);
			case 1:
				SDKHooks_TakeDamage(entity, attacker, attacker, damage, DMG_BLAST);
			}
		}

		else if (StrEqual(tName, "prop_physics", false))
		{
			IgniteEntity(entity, 999.9);
			ThrowEntity(entity);
		}
		else if (StrEqual(tName, "prop_physics_multiplayer", false))
		{
			IgniteEntity(entity, 999.9);
			ThrowEntity(entity);
		}
		else if (StrEqual(tName, "prop_physics_override", false))
		{
			IgniteEntity(entity, 999.9);
			ThrowEntity(entity);
		}
	}

	return Plugin_Handled;
}

public Action Timer_ExExplosion(Handle timer, int client)
{
	g_hExExplosionTimer[client] = null;
	NukeExplosion(client, g_fExPos[client]);
	return Plugin_Stop;
}

public Action Timer_Skill_EX_Ready(Handle timer, int client)
{
	Skill_Cooldown_Timer[client] = null;
	Skill_EX_Using[client] = false;
	Skill_State[client] = SKILL_RDY;
	return Plugin_Stop;
}

public Action Timer_Skill_EX_End(Handle timer, any client)
{
	Skill_Duration_Timer[client] = null; // callback 結束 SM 會回收 handle，必須歸零避免殭屍
	Invulnerable[client] = false;
	Skill_State[client] = SKILL_CD;
	if (IsAliveHumanPlayer(client) &&
		!IsIncapped(client))
	{
		L4D_SetPlayerIncappedDamage(client, client);
	}

	RestoreMagicAtmosphere();
	return Plugin_Stop;
}

public Action Timer_ExAfter(Handle timer, int client)
{
	g_hExAfterTimer[client] = null;
	CreateParticle(PARTICLE_EXPLOSION2, 5.0, g_fExPos[client]);
	return Plugin_Stop;
}

// 清理 EX 爆裂★ 相關 timer + particle（換圖 / 玩家死亡 / 中斷技能時呼叫）
void CleanupEXSkill(int client)
{
	SafeDeleteTimer(g_hExExplosionTimer[client]);
	SafeDeleteTimer(g_hExAfterTimer[client]);
	KillParticleRef(g_iExGlowBigRef[client]);
	KillParticleRef(g_iExGlowRef[client]);
	KillParticleRef(g_iExLightRef[client]);
	KillParticleRef(g_iExDynLightRef[client]); // light_dynamic 用同一 helper 也能殺
}

// 在指定位置 spawn 一個高亮度 light_dynamic，照亮魔法陣四周
// 回傳 entity ref（INVALID_ENT_REFERENCE 代表失敗）
int SpawnExDynamicLight(const float pos[3], float duration)
{
	int light = CreateEntityByName("light_dynamic");
	if (light == -1) return INVALID_ENT_REFERENCE;

	DispatchKeyValue(light, "targetname",        "ex_dynlight");
	DispatchKeyValue(light, "_light",            "255 80 30 255"); // 橘紅高飽和
	DispatchKeyValue(light, "brightness",        "8");              // 8 = 超亮
	DispatchKeyValue(light, "distance",          "900");            // 照射半徑
	DispatchKeyValue(light, "spotlight_radius",  "300");
	DispatchKeyValue(light, "style",             "0");              // 0 = normal
	DispatchKeyValue(light, "_cone",             "0");
	DispatchKeyValue(light, "pitch",             "-90");            // 朝下

	float ang[3] = {90.0, 0.0, 0.0}; // 朝下
	TeleportEntity(light, pos, ang, NULL_VECTOR);
	DispatchSpawn(light);
	ActivateEntity(light);
	AcceptEntityInput(light, "TurnOn");
	// SetLightStyle(0, "a") 會把所有 m_LightStyle=0 的光源變暗 → 改成 13 (unused) 不受影響
	if (HasEntProp(light, Prop_Send, "m_LightStyle"))
		SetEntProp(light, Prop_Send, "m_LightStyle", 13);

	// duration 秒後自動 kill (格式: <output> <target>:<input>:<param>:<delay>:<refire>)
	char outBuf[64];
	FormatEx(outBuf, sizeof outBuf, "OnUser1 !self:Kill::%.2f:-1", duration);
	SetVariantString(outBuf);
	AcceptEntityInput(light, "AddOutput");
	AcceptEntityInput(light, "FireUser1");

	return EntIndexToEntRef(light);
}

void MagicActivates(int client)
{
	g_iExGlowRef[client]  = ParticleFollow(PARTICLE_EX_GLOW, client, explosion_ex_delay_secs);
	g_iExLightRef[client] = ParticleFollow(PARTICLE_EX_LIGHT, client, explosion_ex_delay_secs);

	MagicCircleAtFeet(client, explosion_ex_delay_secs - 0.5, 7.2, 35.0);
}

public Action Timer_Skill_EX_Start(Handle timer, any client)
{
	float Pos[3];
	if (GetAimOrigin(client, Pos, 10.0) == 0) {
		PrintToChatAll("\x04%N \x01施放爆裂失敗", client);
		return Plugin_Stop;
	}
	PrintToChatAll("\x04%N \x01エクスプロージョン!", client);

	// 萬一上次 EX 還沒結束就再施放，先清掉舊的
	CleanupEXSkill(client);

	// 存爆炸座標，讓 delayed timer 讀取（不用 DataPack，避免兩個 timer 共用同一 handle）
	g_fExPos[client][0] = Pos[0];
	g_fExPos[client][1] = Pos[1];
	g_fExPos[client][2] = Pos[2];

	SlowForSecs(explosion_ex_delay_secs, client);
	EmitSoundToAll("skills\\explosion_full.mp3");
	GlowForSecs(client, 255, 0, 0, explosion_ex_delay_secs);
	Invulnerable[client] = true;
	MagicActivates(client);

	ApplyMagicAtmosphere();
	ScheduleRestoreAtmosphere(explosion_ex_delay_secs + 0.5);

	// 追蹤 PARTICLE_EX_GLOW_BIG entity ref，換圖時能主動殺掉
	g_iExGlowBigRef[client] = EntIndexToEntRef(CreateParticleEnt(PARTICLE_EX_GLOW_BIG, explosion_ex_delay_secs, Pos));

	// 在魔法陣中心稍微上方 spawn light_dynamic 強光，視覺對比拉到極大
	float lightPos[3];
	lightPos[0] = Pos[0];
	lightPos[1] = Pos[1];
	lightPos[2] = Pos[2] + 100.0;
	g_iExDynLightRef[client] = SpawnExDynamicLight(lightPos, explosion_ex_delay_secs);

	// 追蹤兩個 delayed timer handle，換圖時能 cancel
	g_hExExplosionTimer[client] = CreateTimer(explosion_ex_delay_secs-1.0, Timer_ExExplosion, client);
	g_hExAfterTimer[client]     = CreateTimer(explosion_ex_delay_secs-1.5, Timer_ExAfter, client);
	return Plugin_Stop;
}
