// 魔心護盾 Mana Shield（被動技能）：用 MP 抵銷傷害；開啟時近戰揮空

static Handle g_hDetour;
static ConVar g_hCvarMeleeRange/*, g_hCvarPanicForever*/;
static int g_iStockRange = 150; //set a default value

void ManaShield_Register()
{
	RegisterSkill("Mana Shield 魔心護盾" ,Timer_Skill_ManaShield_Start, Timer_Skill_ManaShield_End, Timer_Skill_Null_Ready, 0.0, -1.0, 0.0);
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

public Action Timer_Skill_ManaShield_Start(Handle timer, any client)
{
	// GlowForSecs(client, 100, 100, 0, 10.0);
	if(!IsValidEntity(client) || !HasEntProp(client, Prop_Send, "m_glowColorOverride"))return Plugin_Stop;
	State_Glow[client] = true;
	int glowcolor = 255 | (255 << 8) | (0 << 16);
	SetEntProp(client, Prop_Send, "m_glowColorOverride", glowcolor);
	SetEntProp(client, Prop_Send, "m_iGlowType", 3);

	State_ManaShield[client] = true;
	//PrintToChatAll("%N - Mana Shield!", client);
	TriggerTimer(Skill_Notify_Timer[client]);

	return Plugin_Stop;
}

public Action Timer_Skill_ManaShield_End(Handle timer, any client)
{
	Skill_Duration_Timer[client] = null;
	State_ManaShield[client] = false;

	Skill_State[client] = SKILL_CD;
	if (Skill_Notify_Timer[client] != null)
		TriggerTimer(Skill_Notify_Timer[client]);
	return Plugin_Stop;
}

// 由 core/player.sp 的 Event_Hurt 呼叫：MP 足夠時把傷害歸零
float DmgReduce(int client, float dmg)
{
	const float dmgGain = 4.0;
	float result = dmg;
	float mpCost = dmg * dmgGain;
	if (IsAliveHumanPlayer(client) && MP_Decrease(client, mpCost))
	{
		result = 0.0;
	}
	if(Skill_Notify_Timer[client]!=null)
		TriggerTimer(Skill_Notify_Timer[client]);
	else
		Player_OnClientConnected(client);
	return result;
}
