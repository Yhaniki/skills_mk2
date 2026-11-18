// 慢動作（func_timescale）
int Slow_Ent;
bool State_Slow;
Handle Slow_Timer;
float time_weight = 1.0;

// 地圖是否正在執行。換圖載入時 round_start 會比 OnMapStart 先觸發，
// 那時 worldspawn 已經存在，但 CreateEntityByName 會丟「Cannot create new entity when no map is running」
static bool s_bMapRunning;

void Timescale_OnPluginStart()
{
	// 伺服器剛開機、還沒有地圖時 worldspawn 不存在；reload 時地圖已經在跑
	s_bMapRunning = FindEntityByClassname(-1, "worldspawn") != INVALID_ENT_REFERENCE;
}

void Timescale_OnMapStart() { s_bMapRunning = true; }
void Timescale_OnMapEnd()   { s_bMapRunning = false; }

// 刪所有舊 func_timescale，然後建一個 desiredTimescale=1.0 + 超高 acceleration 的新 entity
// 引擎刪掉舊 entity 不會自動還原速度，必須主動 Start 一個指向 1.0 的 entity 來覆蓋
void RestoreTimeScale()
{
	PrintToServer("[skills_mk2] RestoreTimeScale called (State_Slow=%d Slow_Ent=%d)", State_Slow, Slow_Ent);

	// 先清掉所有現存的（包含前次 reset entity 殘留）
	// 注意：移除後不重置 ent，繼續往後搜尋；重置成 -1 會重頭找到同一個 entity → 無限迴圈
	int found = 0;
	int ent   = -1;
	while ((ent = FindEntityByClassname(ent, "func_timescale")) != INVALID_ENT_REFERENCE)
	{
		if (IsValidEntity(ent)) { RemoveEntity(ent); found++; }
	}
	PrintToServer("[skills_mk2] Removed %d func_timescale(s)", found);

	// CreateEntityByName 需要地圖正在運行：伺服器開機時的 OnPluginStart、換圖載入時的 round_start 都還沒有
	if (!s_bMapRunning)
	{
		PrintToServer("[skills_mk2] No map running, skip func_timescale creation");
		Slow_Ent    = 0;
		State_Slow  = false;
		time_weight = 1.0;
		return;
	}

	// 建一個「瞬間拉回 1.0」的 func_timescale
	int reset = CreateEntityByName("func_timescale");
	if (reset > 0 && IsValidEntity(reset))
	{
		DispatchKeyValue(reset, "desiredTimescale",     "1.0");
		DispatchKeyValue(reset, "acceleration",         "99999.0");
		DispatchKeyValue(reset, "minBlendRate",         "0.0");
		DispatchKeyValue(reset, "blendDeltaMultiplier", "99999.0");
		DispatchSpawn(reset);
		AcceptEntityInput(reset, "Start");
		PrintToServer("[skills_mk2] Reset func_timescale started (ent=%d)", reset);
		// 0.5s 後刪掉；若 plugin 在此之前 unload，下次 RestoreTimeScale 會找到並清理
		CreateTimer(0.5, Timer_KillTimescaleReset, EntIndexToEntRef(reset));
	}

	Slow_Ent    = 0;
	State_Slow  = false;
	time_weight = 1.0;
}

public Action Timer_KillTimescaleReset(Handle timer, int ref)
{
	int e = EntRefToEntIndex(ref);
	if (e != INVALID_ENT_REFERENCE && IsValidEntity(e))
		RemoveEntity(e);
	return Plugin_Stop;
}

// 慢動作開始／結束的音效（鷹眼、隱藏版爆裂共用）
void Timescale_Precache()
{
	SetupMaterial("sound\\skills\\slomo.mp3");
	SetupSound("skills\\slomo.mp3", true);

	SetupMaterial("sound\\skills\\slomo_end.mp3");
	SetupSound("skills\\slomo_end.mp3", true);
}

// 慢動作提早結束（照常播放結束音效）
void Timescale_EndNow()
{
	if (Slow_Timer != null)
		TriggerTimer(Slow_Timer);
}

void SlowForSecs(float time, int client)
{
	if (State_Slow && Slow_Timer != null) delete Slow_Timer;
	State_Slow = true;
	time_weight = 0.6;
	PrepareAndEmitSoundtoAll("skills\\slomo.mp3", .entity = client, .volume = 1.0);

	Slow_Ent = CreateEntityByName("func_timescale");
	DispatchKeyValue(Slow_Ent, "desiredTimescale", "0.6");
	DispatchKeyValue(Slow_Ent, "acceleration", "0.3");
	DispatchKeyValue(Slow_Ent, "minBlendRate", "0.1");
	DispatchKeyValue(Slow_Ent, "blendDeltaMultiplier", "1.0");
	DispatchSpawn(Slow_Ent);
	AcceptEntityInput(Slow_Ent, "Start");

	Slow_Timer = CreateTimer(time, Timer_Unslow, client);
}

public Action Timer_Unslow(Handle timer, any client)
{
	PrepareAndEmitSoundtoAll("skills\\slomo_end.mp3", .entity = client, .volume = 1.0);
	RestoreTimeScale();
	Slow_Timer = null;
	return Plugin_Stop;
}
