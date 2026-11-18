// 魔心護盾 Mana Shield（被動技能）：用 MP 抵銷傷害；開啟時近戰揮空

bool State_ManaShield[MAX_PLAYERS + 1];   // core/hud.sp 的 MP 條也會讀

static int s_iManaShield;
static Handle g_hDetour;
static ConVar g_hCvarMeleeRange/*, g_hCvarPanicForever*/;
static int g_iStockRange = 150; //set a default value

int ManaShield_Register()
{
	s_iManaShield = Skill_Register("Mana Shield 魔心護盾", 0.0, 0.0, 0.0, SKILL_PASSIVE);
	Skill_OnStart(s_iManaShield, ManaShield_OnStart);
	Skill_OnEnd(s_iManaShield, ManaShield_OnEnd);
	Skill_OnTick(s_iManaShield, ManaShield_OnTick);
	Skill_OnCleanup(s_iManaShield, ManaShield_OnCleanup);
	Skill_OnTakeDamage(s_iManaShield, ManaShield_OnTakeDamage);
	return s_iManaShield;
}

//===========================================================
//=================== 近戰揮空（DHooks） ====================
//===========================================================

// OnPluginStart 時呼叫：載入 gamedata、掛 detour、記下原本的 melee_range
void ManaShield_InitMeleeDetour()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "gamedata/%s.txt", GAMEDATA_MELEE);
	if( FileExists(sPath) == false ) SetFailState("\n==========\nMissing required file: \"%s\".\nRead installation instructions again.\n==========", sPath);

	Handle hGameData = LoadGameConfigFile(GAMEDATA_MELEE);
	if( hGameData == null ) SetFailState("Failed to load \"%s.txt\" gamedata.", GAMEDATA_MELEE);
	g_hDetour = DHookCreateFromConf(hGameData, "CTerrorMeleeWeapon::TestMeleeSwingCollision");
	delete hGameData;
	if( !g_hDetour )
		SetFailState("Failed to find \"CTerrorMeleeWeapon::GetPrimaryAttackActivity\" signature.");
	if( !DHookEnableDetour(g_hDetour, false, TestMeleeSwingCollisionPre) )
		SetFailState("Failed to detour pre \"CTerrorMeleeWeapon::TestMeleeSwingCollision\".");
	if( !DHookEnableDetour(g_hDetour, true, TestMeleeSwingCollisionPost) )
		SetFailState("Failed to detour post \"CTerrorMeleeWeapon::TestMeleeSwingCollision\".");

	g_hCvarMeleeRange = FindConVar("melee_range");
	// g_hCvarPanicForever = FindConVar("director_panic_forever");
	// g_hCvarPanicForever.SetBool(false, false, false);
	g_iStockRange = g_hCvarMeleeRange.IntValue;
}

// 插件卸載時還原 melee_range
void ManaShield_RestoreMeleeRange()
{
	if (g_hCvarMeleeRange != null)
		g_hCvarMeleeRange.SetInt(g_iStockRange);
}

MRESReturn TestMeleeSwingCollisionPre(int pThis, Handle hReturn)
{
	if( IsValidEntity(pThis) )
	{
		int owner = GetEntPropEnt(pThis, Prop_Send, "m_hOwnerEntity");
		if(State_ManaShield[owner])
		{
			g_hCvarMeleeRange.SetInt(10);
			PrintToChat(owner,"Miss!");
		}
		else
		{
			g_hCvarMeleeRange.SetInt(g_iStockRange);
		}
	}

	return MRES_Ignored;
}

MRESReturn TestMeleeSwingCollisionPost(int pThis, Handle hReturn)
{
	g_hCvarMeleeRange.SetInt(g_iStockRange);
	return MRES_Ignored;
}

//===========================================================
//========================= 技能 ============================
//===========================================================

static void ManaShield_OnStart(int client)
{
	// GlowForSecs(client, 100, 100, 0, 10.0);
	if(!IsValidEntity(client) || !HasEntProp(client, Prop_Send, "m_glowColorOverride"))return;
	State_Glow[client] = true;
	int glowcolor = 255 | (255 << 8) | (0 << 16);
	SetEntProp(client, Prop_Send, "m_glowColorOverride", glowcolor);
	SetEntProp(client, Prop_Send, "m_iGlowType", 3);

	State_ManaShield[client] = true;
	//PrintToChatAll("%N - Mana Shield!", client);
	Hud_Refresh(client, false);
}

// 被切換成其他技能時
static void ManaShield_OnEnd(int client)
{
	State_ManaShield[client] = false;
}

// HUD 每 0.5 秒：護盾被清掉（回合重開等）就重新啟用；發光被清掉就補上
static void ManaShield_OnTick(int client)
{
	if(!State_ManaShield[client])
		Skill_Trigger(client);
	else if(!State_Glow[client] && IsPlayerAlive(client))
	{
		// if(!IsValidEntity(client) || !HasEntProp(client, Prop_Send, "m_glowColorOverride"))return Plugin_Stop;
		State_Glow[client] = true;
		int glowcolor = 255 | (255 << 8) | (0 << 16);
		SetEntProp(client, Prop_Send, "m_glowColorOverride", glowcolor);
		SetEntProp(client, Prop_Send, "m_iGlowType", 3);
	}
}

static void ManaShield_OnCleanup(int client, SkillCleanup reason)
{
	switch (reason)
	{
		case SKILL_CLEANUP_CONNECT, SKILL_CLEANUP_ROUND_START, SKILL_CLEANUP_MAP_END:
		{
			State_ManaShield[client] = false;
		}
		case SKILL_CLEANUP_RELOAD, SKILL_CLEANUP_PLUGIN_END:
		{
			if (State_ManaShield[client]) UnGlow(client);
			State_ManaShield[client] = false;
		}
	}
}

static float ManaShield_OnTakeDamage(int client, float damage)
{
	if (!State_ManaShield[client]) return damage;
	return DmgReduce(client, damage);
}

// MP 足夠時把傷害歸零
float DmgReduce(int client, float dmg)
{
	const float dmgGain = 4.0;
	float result = dmg;
	float mpCost = dmg * dmgGain;
	if (IsAliveHumanPlayer(client) && MP_Decrease(client, mpCost))
	{
		result = 0.0;
	}
	if (!Hud_Refresh(client, false))
		Player_OnClientConnected(client);
	return result;
}
