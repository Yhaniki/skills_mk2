// 腳下水平魔法陣
// 每位玩家「腳下魔法陣」的 ent ref 與當前 yaw 角度
int g_iMagicCircleRef[MAX_PLAYERS + 1];
float g_fMagicCircleYaw[MAX_PLAYERS + 1];

// 魔法陣的模型與動畫材質
void MagicCircle_Precache()
{
	SetupMaterial(MAGIC_CIRCLE_VTF);
	SetupMaterial(MAGIC_CIRCLE_VMT_GROUND);
	SetupMaterial(MAGIC_CIRCLE_MODEL);
	SetupMaterial("models/konosuba/magic_circle_plane.vvd");
	SetupMaterial("models/konosuba/magic_circle_plane.dx90.vtx");
	if (FileExists(MAGIC_CIRCLE_MODEL, true))
		PrecacheModel(MAGIC_CIRCLE_MODEL, true);
}

// trace ray 過濾：忽略玩家本人
public bool MagicCircle_FilterIgnoreClient(int entity, int contentsMask, any data)
{
	return entity != data;
}

// 從玩家位置往下打 trace 找地板，回傳貼地後的位置（含小 offset 避免 z-fighting）
// trace 失敗時 fallback 用 client origin
stock void GetGroundedFeetPos(int client, float out[3])
{
	float origin[3], end[3];
	GetClientAbsOrigin(client, origin);
	end[0] = origin[0];
	end[1] = origin[1];
	end[2] = origin[2] - 256.0; // 往下 256 單位夠涵蓋樓梯 / 斜坡

	Handle tr = TR_TraceRayFilterEx(origin, end, MASK_SOLID_BRUSHONLY, RayType_EndPoint,
	                                MagicCircle_FilterIgnoreClient, client);
	if (TR_DidHit(tr))
	{
		TR_GetEndPosition(out, tr);
		out[2] += MAGIC_CIRCLE_FOOT_OFFSET;
	}
	else
	{
		out[0] = origin[0];
		out[1] = origin[1];
		out[2] = origin[2] + MAGIC_CIRCLE_FOOT_OFFSET;
	}
	delete tr;
}

// 立即把該玩家身上的魔法陣移除
stock void KillMagicCircle(int client)
{
	if (client < 0 || client > MAX_PLAYERS) return;
	int ent = EntRefToEntIndex(g_iMagicCircleRef[client]);
	if (ent != INVALID_ENT_REFERENCE && IsValidEntity(ent))
	{
		AcceptEntityInput(ent, "kill");
	}
	g_iMagicCircleRef[client] = INVALID_ENT_REFERENCE;
	g_fMagicCircleYaw[client] = 0.0;
}

// 在玩家腳下生成持續 duration 秒的水平魔法陣
//   scale       : 大小倍率 (1.0 = mdl 原始 64x64 單位)
//   rotateSpeed : 每秒旋轉度數 (正:逆時針, 負:順時針)
//
// 為什麼「不 SetParent」：
//   parent 機制每 frame 會用 compose(parent.abs, local) 重算 child.abs，
//   parent 的視角 pitch 變化會把 prop 拉斜，看起來像立起來。
//   不 parent 直接每 tick 用 TeleportEntity 設世界座標 + 世界角度，
//   prop.abs 永遠由我們強制鎖在 (0, yaw_accum, 0)，絕對水平。
//
// 平滑性：
//   TeleportEntity 走 SetAbsOrigin / SetAbsAngles，會正確 networked 給 client。
//   Client 端對 m_vecOrigin / m_angRotation 預設有插值 (cl_interp)，
//   所以 30Hz 更新在 client 看到的還是平滑連續移動。
void MagicCircleAtFeet(int client, float duration, float scale = 7.2, float rotateSpeed = 35.0)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client)) return;
	if (!FileExists(MAGIC_CIRCLE_MODEL, true))
	{
		// 還沒部署 mdl 時直接靜默跳過，不要中斷爆裂流程
		LogMessage("[skills_mk2] %s 不存在，跳過腳下魔法陣。請先部署模型。", MAGIC_CIRCLE_MODEL);
		return;
	}

	KillMagicCircle(client); // 避免疊加到舊的

	int prop = CreateEntityByName("prop_dynamic_override");
	if (prop == -1) return;

	DispatchKeyValue(prop, "model", MAGIC_CIRCLE_MODEL);
	DispatchKeyValue(prop, "solid", "0");
	DispatchKeyValue(prop, "DefaultAnim", "idle");
	DispatchKeyValue(prop, "disableshadows", "1");
	DispatchKeyValue(prop, "disablereceiveshadows", "1");
	DispatchKeyValue(prop, "spawnflags", "256"); // ignore +use

	char buf[16];
	FormatEx(buf, sizeof buf, "%.3f", scale);
	DispatchKeyValue(prop, "modelscale", buf);

	DispatchSpawn(prop);
	ActivateEntity(prop);

	// 白色不染色：讓貼圖原本的紅色直接發光，不會被再乘一次紅
	SetEntityRenderMode(prop, RENDER_TRANSADDFRAMEBLEND);
	SetEntityRenderColor(prop, 255, 255, 255, 255);

	// 初始位置：trace 往下找真實地板再 +MAGIC_CIRCLE_FOOT_OFFSET，避免浮空 / 穿地
	float pos[3];
	GetGroundedFeetPos(client, pos);

	float zeroAng[3] = {0.0, 0.0, 0.0};
	TeleportEntity(prop, pos, zeroAng, NULL_VECTOR);

	g_iMagicCircleRef[client] = EntIndexToEntRef(prop);
	g_fMagicCircleYaw[client] = 0.0;

	// timer 每 tick 同時更新「位置」+「世界角度」，兩個一起鎖死
	DataPack dp = new DataPack();
	dp.WriteCell(GetClientUserId(client));
	dp.WriteFloat(rotateSpeed);
	dp.WriteFloat(GetGameTime() + duration);
	CreateTimer(MAGIC_CIRCLE_TICK, Timer_UpdateMagicCircle, dp,
		TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
}

// 每 tick 更新位置 (跟玩家腳下) + 世界角度 (永遠 0,0,0 + yaw)
public Action Timer_UpdateMagicCircle(Handle timer, DataPack dp)
{
	dp.Reset();
	int userid       = dp.ReadCell();
	float rotateSpeed = dp.ReadFloat();
	float endTime    = dp.ReadFloat();

	int client = GetClientOfUserId(userid);
	if (client <= 0 || !IsClientInGame(client))
	{
		if (client > 0) KillMagicCircle(client);
		return Plugin_Stop;
	}
	if (g_iMagicCircleRef[client] == INVALID_ENT_REFERENCE)
		return Plugin_Stop;

	int prop = EntRefToEntIndex(g_iMagicCircleRef[client]);
	if (prop == INVALID_ENT_REFERENCE)
	{
		g_iMagicCircleRef[client] = INVALID_ENT_REFERENCE;
		return Plugin_Stop;
	}

	if (!IsPlayerAlive(client) || GetGameTime() >= endTime)
	{
		KillMagicCircle(client);
		return Plugin_Stop;
	}

	// 累進 yaw
	g_fMagicCircleYaw[client] += rotateSpeed * MAGIC_CIRCLE_TICK;
	if (g_fMagicCircleYaw[client] >= 360.0)  g_fMagicCircleYaw[client] -= 360.0;
	if (g_fMagicCircleYaw[client] < 0.0)     g_fMagicCircleYaw[client] += 360.0;

	// 同時設位置 + 世界角度 (沒 parent，所以 abs 不會被任何人拉走)
	// 每 tick 重新 trace 地板，斜坡 / 樓梯時魔法陣會服貼
	float pos[3];
	GetGroundedFeetPos(client, pos);

	float ang[3];
	ang[0] = 0.0;                       // pitch: 永遠平躺
	ang[1] = g_fMagicCircleYaw[client]; // yaw  : 我們自己控
	ang[2] = 0.0;                       // roll : 永遠不歪

	TeleportEntity(prop, pos, ang, NULL_VECTOR);
	return Plugin_Continue;
}
