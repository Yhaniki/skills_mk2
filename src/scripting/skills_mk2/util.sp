// 通用純函式：實體判斷、距離、瞄準、傷害、timer 工具
// 這裡的函式不持有自己的狀態；有狀態的效果系統放在 fx/

// 安全刪除 timer 並歸零 handle，避免換圖後殭屍 handle
// 注意：SourceMod 對「自然結束的 timer」會自動回收 handle，但 plugin 端的變數不會自動歸零
// → callback 結束時必須自行 set null，否則這裡的 delete 會踩到 invalid handle
stock void SafeDeleteTimer(Handle &h)
{
	Handle tmp = h;
	h = null; // 先歸零，避免 delete 失敗後變數仍指向殭屍 handle
	if (tmp == null) return;
	delete tmp;
}

//===========================================================
//======================== 實體判斷 =========================
//===========================================================

bool IsPlayer(int client)
{
	if ((client < 1) || (client > MAX_PLAYERS)) return false;
	if (client>0&&IsValidEntity(client)&&IsFakeClient(client)) return false;
	return true;
}

bool IsAlive(int entity)
{
	if(!IsValidEntity(entity))return false;
	if(!IsInf(entity)&&!IsWitch(entity)&&!IsSpecialInf(entity))return false;
	int hp = GetEntProp(entity, Prop_Data, "m_iHealth");
	if(hp<=0) return false;
	else return true;
}

bool IsWitch(int entity)
{
	if(!IsValidEntity(entity))return false;
	char str[MAXCMD];
	GetEdictClassname(entity, str, MAXCMD);
	return StrEqual(str, "witch");
}

// 活著的特感（含 Tank）。用 MaxClients：特感 bot 的 client index 可能超過 MAX_PLAYERS
bool IsAliveSpecialInf(int client)
{
	if (client > MaxClients || client <= 0)
	return false;
	return (IsClientInGame(client) == true)
	&& (IsPlayerAlive(client) == true)
	&& (GetClientTeam(client) == 3);
}

// 普通殭屍（不檢查是否活著）
bool IsInf(int client)
{
	if(!IsValidEntity(client))return false;
	char str[MAXCMD];
	GetEdictClassname(client, str, MAXCMD);
	return StrEqual(str, "infected");
}

bool IsSpecialInf(int client)
{
	if (client > MAX_PLAYERS || client <= 0) return false;
	return (IsClientInGame(client) == true)
	&& (GetClientTeam(client) == 3);
}

bool IsAliveHumanPlayer(int client)
{
	return (IsClientInGame(client) == true)
	&& (IsFakeClient(client) == false)
	&& (IsPlayerAlive(client) == true)
	&& (GetClientTeam(client) == 2);
}

bool IsIncapped(int client)
{
	return view_as<bool>(GetEntProp(client, Prop_Send, "m_isIncapacitated"));
}

bool IsSurvivor(int client)
{ return (GetClientTeam(client) == 2 || GetClientTeam(client) == 4); }

bool IsValidClient(int client, bool replaycheck = true)
{
	if (client > 0 && client <= MAX_PLAYERS && IsClientInGame(client))
	{
		if (replaycheck)
		{
			if (IsClientSourceTV(client) || IsClientReplay(client)) return false;
		}
		return true;
	}
	return false;
}

bool RealValidEntity(int entity)
{ return (entity > 0 && IsValidEntity(entity)); }

//===========================================================
//======================== 位置與瞄準 =======================
//===========================================================

int GetAimOrigin(int client, float hOrigin[3], float back_offset)
{
	float vAngles[3], fOrigin[3];
	GetClientEyePosition(client, fOrigin);
	GetClientEyeAngles(client, vAngles);

	//PrintToChatAll("%f %f %f", vAngles[0], vAngles[1], vAngles[2]);

	Handle trace = TR_TraceRayFilterEx(fOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

	if(TR_DidHit(trace))
	{
		TR_GetEndPosition(hOrigin, trace);

		float offset[3];

		offset[0] = hOrigin[0] - fOrigin[0];
		offset[1] = hOrigin[1] - fOrigin[1];
		offset[2] = hOrigin[2] - fOrigin[2];

		NormalizeVector(offset, offset);

		hOrigin[0] -= offset[0] * back_offset;
		hOrigin[1] -= offset[1] * back_offset;
		hOrigin[2] -= offset[2] * back_offset;

		delete trace;
		return 1;
	}

	delete trace;
	return 0;
}

bool TraceEntityFilterPlayer(int entity, int contentsMask)
{
	if (entity > MAX_PLAYERS) {
		return true;
	} else {
		return IsAliveSpecialInf(entity);
	}
}

// 取得實體的世界座標
// 玩家被 parent 時 (Jockey 騎乘 / Charger 抓 / Smoker 拉 / Hunter 撲)
// m_vecOrigin 會變成相對父實體的座標，必須改用 GetClientAbsOrigin 才能拿到世界座標
stock bool GetEntityWorldOrigin(int entity, float pos[3])
{
	if (entity >= 1 && entity <= MaxClients) {
		if (!IsClientInGame(entity)) return false;
		GetClientAbsOrigin(entity, pos);
		return true;
	}
	if (!IsValidEntity(entity)) return false;
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
	return true;
}

float GetEntityPosDistance(int entity, const float pos[3])
{
	float Pos1[3];
	if (!GetEntityWorldOrigin(entity, Pos1)) return 0.0;
	return GetVectorDistance(Pos1, pos);
}

//===========================================================
//========================= 其他 ============================
//===========================================================

// 加進下載表並預載（音效、粒子檔、模型、材質）
void SetupMaterial(const char[] file)
{
	AddFileToDownloadsTable(file);
	PrecacheGeneric(file);
}

void StripAndExecuteClientCommand(int client, const char[] command, const char[] arguments)
{
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s", command, arguments);
	SetCommandFlags(command, flags);
}

// 用 point_hurt 對目標造成傷害（原 damage.sp）
void DealDamage(int victim, int damage, int attacker = 0, int dmg_type = DMG_GENERIC, const char[] weapon = "")
{
	//if(victim>0 && IsValidEdict(victim) && IsClientInGame(victim) && IsPlayerAlive(victim) && damage>0)
	if(victim>0 && IsValidEdict(victim) && damage>0)
	{
		char dmg_str[16];
		IntToString(damage,dmg_str,16);
		char dmg_type_str[32];
		IntToString(dmg_type,dmg_type_str,32);
		int pointHurt=CreateEntityByName("point_hurt");
		if(pointHurt)
		{
			DispatchKeyValue(victim,"targetname","war3_hurtme");
			DispatchKeyValue(pointHurt,"DamageTarget","war3_hurtme");
			DispatchKeyValue(pointHurt,"Damage",dmg_str);
			DispatchKeyValue(pointHurt,"DamageType",dmg_type_str);
			if(!StrEqual(weapon,""))
			{
				DispatchKeyValue(pointHurt,"classname",weapon);
			}
			DispatchSpawn(pointHurt);
			AcceptEntityInput(pointHurt,"Hurt",(attacker>0)?attacker:-1);
			DispatchKeyValue(pointHurt,"classname","point_hurt");
			DispatchKeyValue(victim,"targetname","war3_donthurtme");
			RemoveEdict(pointHurt);
		}
	}
}
