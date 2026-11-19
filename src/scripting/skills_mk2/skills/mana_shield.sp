// 魔心護盾 Mana Shield（被動技能）：用 MP 抵銷傷害；開啟時近戰揮空

bool State_ManaShield[MAX_PLAYERS + 1];   // core/hud.sp 的 MP 條也會讀

#define SHIELD_MELEE_RANGE (10)           // 護盾開啟時的近戰距離（遊戲預設的 melee_range 是 70）

static int s_iManaShield;
static Handle g_hDetour;
static ConVar g_hCvarMeleeRange/*, g_hCvarPanicForever*/;
static int s_iSavedRange = -1;            // 近戰判定期間暫存原本的 melee_range；-1 表示目前沒有縮短
static int s_iSavedFlags;
static float s_fMissSwing[MAX_PLAYERS + 1];   // 已經顯示過 MISS 的那一刀（近戰武器的 m_flNextPrimaryAttack，換一刀才會變）
static const float s_vMissMins[3] = {-8.0, -8.0, -8.0};
static const float s_vMissMaxs[3] = { 8.0,  8.0,  8.0};

int ManaShield_Register()
{
	s_iManaShield = Skill_Register("Skill_ManaShield", 0.0, 0.0, 0.0, SKILL_PASSIVE);
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

// 近戰有沒有砍中，伺服器和客戶端各算一次，都用 melee_range：
// - 伺服器：在 CTerrorMeleeWeapon::TestMeleeSwingCollision（一刀會呼叫二十幾次）期間把 melee_range 縮短，
//   只影響護盾玩家的這一刀，其他人照常。
// - 客戶端：會自己預測有沒有砍中，預測砍中就先在自己畫面上噴血。所以要另外用 SendConVarValue 把縮短後的
//   距離送給護盾玩家（只影響他自己的預測），不然會「沒有傷害卻噴血」（issue #10）。
// melee_range 是 replicated cvar，伺服器改值時引擎會廣播給所有客戶端，會把送給護盾玩家的值蓋回去，
// 所以伺服器端縮短期間暫時拿掉 FCVAR_REPLICATED。

// OnPluginStart 時呼叫：載入 gamedata、掛 detour
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
	// 別的插件或管理員改了 melee_range 時，引擎會廣播新的值，要再送一次縮短的距離給護盾玩家
	g_hCvarMeleeRange.AddChangeHook(ManaShield_OnMeleeRangeChanged);
	// g_hCvarPanicForever = FindConVar("director_panic_forever");
	// g_hCvarPanicForever.SetBool(false, false, false);
}

// 近戰判定結束時，以及插件卸載時（萬一判定到一半）：還原 melee_range 與它的 flags
void ManaShield_RestoreMeleeRange()
{
	if (s_iSavedRange < 0) return;
	g_hCvarMeleeRange.SetInt(s_iSavedRange);
	g_hCvarMeleeRange.Flags = s_iSavedFlags;
	s_iSavedRange = -1;
}

// 沒有縮短時的 melee_range
static int ManaShield_NormalRange()
{
	return s_iSavedRange >= 0 ? s_iSavedRange : g_hCvarMeleeRange.IntValue;
}

static void ManaShield_OnMeleeRangeChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (s_iSavedRange >= 0) return;   // 自己在近戰判定期間改的
	for (int i = 1; i <= MAX_PLAYERS; i++)
		if (State_ManaShield[i]) ManaShield_SyncClient(i);
}

// 護盾玩家的客戶端用縮短後的距離預測近戰，其他時候用伺服器的值
static void ManaShield_SyncClient(int client)
{
	if (g_hCvarMeleeRange == null || !IsClientInGame(client) || IsFakeClient(client)) return;
	char value[16];
	IntToString(State_ManaShield[client] ? SHIELD_MELEE_RANGE : ManaShield_NormalRange(), value, sizeof(value));
	SendConVarValue(client, g_hCvarMeleeRange, value);
}

MRESReturn TestMeleeSwingCollisionPre(int pThis, Handle hReturn)
{
	if (!IsValidEntity(pThis)) return MRES_Ignored;
	int owner = GetEntPropEnt(pThis, Prop_Send, "m_hOwnerEntity");
	if (owner < 1 || owner > MAX_PLAYERS || !State_ManaShield[owner]) return MRES_Ignored;

	if (s_iSavedRange < 0)
	{
		s_iSavedRange = g_hCvarMeleeRange.IntValue;
		s_iSavedFlags = g_hCvarMeleeRange.Flags;
		g_hCvarMeleeRange.Flags = s_iSavedFlags & ~FCVAR_REPLICATED;
	}
	ManaShield_ShowMiss(owner, pThis, s_iSavedRange);
	g_hCvarMeleeRange.SetInt(SHIELD_MELEE_RANGE);
	return MRES_Ignored;
}

MRESReturn TestMeleeSwingCollisionPost(int pThis, Handle hReturn)
{
	ManaShield_RestoreMeleeRange();
	return MRES_Ignored;
}

// 這一刀用原本的距離會砍到殭屍、女巫或特感的話，在畫面中央顯示 MISS，一刀只顯示一次
// （以前每次判定都 PrintToChat，一刀會在聊天室刷二十幾行，連揮空氣也會刷）
static void ManaShield_ShowMiss(int client, int weapon, int range)
{
	float swing = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
	if (swing == s_fMissSwing[client]) return;

	float eye[3], ang[3], dir[3], end[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, ang);
	GetAngleVectors(ang, dir, NULL_VECTOR, NULL_VECTOR);
	for (int i = 0; i < 3; i++) end[i] = eye[i] + dir[i] * float(range);
	TR_TraceHullFilter(eye, end, s_vMissMins, s_vMissMaxs, MASK_SHOT, ManaShield_TraceNotSelf, client);
	if (!TR_DidHit()) return;
	int hit = TR_GetEntityIndex();
	bool target = (hit >= 1 && hit <= MaxClients) ? IsSpecialInf(hit) : (IsInf(hit) || IsWitch(hit));
	if (!target) return;

	s_fMissSwing[client] = swing;
	PrintCenterText(client, "MISS");
}

static bool ManaShield_TraceNotSelf(int entity, int contentsMask, any client)
{
	return entity != client;
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
	ManaShield_SyncClient(client);
	//PrintToChatAll("%N - Mana Shield!", client);
	Hud_Refresh(client, false);
}

// 被切換成其他技能時
static void ManaShield_OnEnd(int client)
{
	State_ManaShield[client] = false;
	ManaShield_SyncClient(client);
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
	bool wasOn = State_ManaShield[client];
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
	s_fMissSwing[client] = 0.0;
	// 客戶端的近戰距離送回伺服器的值（還在用魔心護盾的話，HUD 每 0.5 秒會重新啟用、再送一次縮短的距離）。
	// 剛連線的玩家還不在遊戲中，SyncClient 會略過：斷線時客戶端會把 replicated cvar 還原成預設值
	if (wasOn) ManaShield_SyncClient(client);
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
