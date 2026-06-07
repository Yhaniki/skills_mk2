//*****************************************************************
//  -------------------------------------------------------------  *
//  *** Magic Atmosphere ***                                       *
//  施放魔法時切換天氣氛圍：濃霧 / 變暗 / 改色調 / 雷聲              *
//  -------------------------------------------------------------  *
//  對外介面：                                                       *
//    ApplyMagicAtmosphere()        - 套用魔法氛圍                   *
//    RestoreMagicAtmosphere()      - 立刻還原為原本天氣             *
//    ScheduleRestoreAtmosphere(t)  - t 秒後自動還原（會取消舊排程） *
//    ResetMagicAtmosphere()        - 換地圖時重置內部狀態           *
//*****************************************************************
#if defined _magic_atmosphere_included
	#endinput
#endif
#define _magic_atmosphere_included

// netprop／暫時字串最長別名約 42 足夠（SP 1.12：函式參數的字元陣列必須有固定長度）
#define MAG_ATM_NAME 52

// 內部狀態
static bool   s_bAtmosphereOn     = false;
static int    s_iPostProcessRef   = INVALID_ENT_REFERENCE; // postprocess_controller
static float  s_fOriFogStart      = -1.0;
static float  s_fOriFogEnd        = -1.0;
static float  s_fOriFogMaxDensity = -1.0;
static int    s_iOriFogColorR     = -1;
static int    s_iOriFogColorG     = -1;
static int    s_iOriFogColorB     = -1;
static bool   s_bOriFogEnabled    = false;
static float  s_fOriFogFarZ       = -1.0;
static bool   s_bFogBacked        = false;
static Handle s_hRestoreTimer     = null;

// env_tonemap：備份修改前數值，用 SetEntPropFloat 還原（L4D2 對 Set…「-1」常無效，會殘留暗畫面）
static bool   s_bOriToneValid         = false;
static float  s_fOriToneAeMin         = 0.0;
static float  s_fOriToneAeMax         = 0.0;
static float  s_fOriToneBloom         = 0.0;
static float  s_fOriTonePercentTarget = 0.0;
static float  s_fOriTonePercentBright = 0.0;
static float  s_fOriToneMinAvgLum     = 0.0;
static bool   s_bOriAeMin             = false;
static bool   s_bOriAeMax             = false;
static bool   s_bOriBloom             = false;
static bool   s_bOriPctTarget         = false;
static bool   s_bOriPctBright         = false;
static bool   s_bOriMinAvg            = false;
static PropType s_typeAeMin           = Prop_Send;
static PropType s_typeAeMax           = Prop_Send;
static PropType s_typeBloom           = Prop_Send;
static PropType s_typePctTarget       = Prop_Send;
static PropType s_typePctBright       = Prop_Send;
static PropType s_typeMinAvg          = Prop_Send;
static char   s_sPropAeMin[MAG_ATM_NAME];
static char   s_sPropAeMax[MAG_ATM_NAME];
static char   s_sPropBloom[MAG_ATM_NAME];
static char   s_sPropPctTarget[MAG_ATM_NAME];
static char   s_sPropPctBright[MAG_ATM_NAME];
static char   s_sPropMinAvg[MAG_ATM_NAME];

stock void ToneClearBackup()
{
	s_bOriAeMin     = false;
	s_bOriAeMax     = false;
	s_bOriBloom     = false;
	s_bOriPctTarget = false;
	s_bOriPctBright = false;
	s_bOriMinAvg    = false;
	s_bOriToneValid = false;
	s_sPropAeMin[0] = 0;
	s_sPropAeMax[0] = 0;
	s_sPropBloom[0] = 0;
	s_sPropPctTarget[0] = 0;
	s_sPropPctBright[0] = 0;
	s_sPropMinAvg[0] = 0;
}

// 依序試 Prop_Send / Prop_Data，與兩個備用屬性名
stock bool ToneBindOne(int tonemap,
	char cand0[MAG_ATM_NAME],
	char cand1[MAG_ATM_NAME],
	float &saved,
	PropType &ptype,
	char nameDst[MAG_ATM_NAME])
{
	for (new pass = 0; pass <= 1; ++pass)
	{
		PropType tt = (pass == 0) ? Prop_Send : Prop_Data;
		for (new c = 0; c <= 1; ++c)
		{
			char tmp[MAG_ATM_NAME];
			if (c == 0)
				strcopy(tmp, sizeof tmp, cand0);
			else
				strcopy(tmp, sizeof tmp, cand1);

			if (!tmp[0])
				continue;

			if (!HasEntProp(tonemap, tt, tmp))
				continue;

			saved = GetEntPropFloat(tonemap, tt, tmp);
			ptype = tt;
			strcopy(nameDst, MAG_ATM_NAME, tmp);
			return true;
		}
	}
	return false;
}

stock void SnapshotTonemapBeforeModify(int tonemap)
{
	char cn0[MAG_ATM_NAME];
	char cn1[MAG_ATM_NAME];

	ToneClearBackup();

	strcopy(cn0, sizeof cn0, "m_flCustomAutoExposureMin");
	strcopy(cn1, sizeof cn1, "m_flAutoExposureMin");
	s_bOriAeMin = ToneBindOne(tonemap, cn0, cn1, s_fOriToneAeMin, s_typeAeMin, s_sPropAeMin);

	strcopy(cn0, sizeof cn0, "m_flCustomAutoExposureMax");
	strcopy(cn1, sizeof cn1, "m_flAutoExposureMax");
	s_bOriAeMax = ToneBindOne(tonemap, cn0, cn1, s_fOriToneAeMax, s_typeAeMax, s_sPropAeMax);

	strcopy(cn0, sizeof cn0, "m_flCustomBloomScale");
	strcopy(cn1, sizeof cn1, "m_flBloomScale");
	s_bOriBloom = ToneBindOne(tonemap, cn0, cn1, s_fOriToneBloom, s_typeBloom, s_sPropBloom);

	strcopy(cn0, sizeof cn0, "m_flCustomTonemapPercentTarget");
	strcopy(cn1, sizeof cn1, "m_flTonemapPercentTarget");
	s_bOriPctTarget = ToneBindOne(tonemap, cn0, cn1, s_fOriTonePercentTarget, s_typePctTarget, s_sPropPctTarget);

	strcopy(cn0, sizeof cn0, "m_flCustomTonemapPercentBrightPixels");
	strcopy(cn1, sizeof cn1, "m_flTonemapPercentBrightPixels");
	s_bOriPctBright = ToneBindOne(tonemap, cn0, cn1, s_fOriTonePercentBright, s_typePctBright, s_sPropPctBright);

	strcopy(cn0, sizeof cn0, "m_flCustomTonemapMinAvgLum");
	strcopy(cn1, sizeof cn1, "m_flTonemapMinAvgLum");
	s_bOriMinAvg = ToneBindOne(tonemap, cn0, cn1, s_fOriToneMinAvgLum, s_typeMinAvg, s_sPropMinAvg);

	s_bOriToneValid = (s_bOriAeMin || s_bOriAeMax || s_bOriBloom ||
	                   s_bOriPctTarget || s_bOriPctBright || s_bOriMinAvg);
}

stock bool ToneRestoreField(int tonemap, bool saved, PropType tt, char prop[MAG_ATM_NAME], float val)
{
	if (!saved || prop[0] == '\0')
		return false;
	SetEntPropFloat(tonemap, tt, prop, val);
	return true;
}

stock void ToneApplySnapshot(int tonemap)
{
	ToneRestoreField(tonemap, s_bOriAeMin,     s_typeAeMin,      s_sPropAeMin,     s_fOriToneAeMin);
	ToneRestoreField(tonemap, s_bOriAeMax,     s_typeAeMax,      s_sPropAeMax,     s_fOriToneAeMax);
	ToneRestoreField(tonemap, s_bOriBloom,     s_typeBloom,      s_sPropBloom,      s_fOriToneBloom);
	ToneRestoreField(tonemap, s_bOriPctTarget, s_typePctTarget,  s_sPropPctTarget,s_fOriTonePercentTarget);
	ToneRestoreField(tonemap, s_bOriPctBright, s_typePctBright, s_sPropPctBright,s_fOriTonePercentBright);
	ToneRestoreField(tonemap, s_bOriMinAvg,    s_typeMinAvg,     s_sPropMinAvg,     s_fOriToneMinAvgLum);
}

// 尚無對應 SendProp 備份時，嘗試 void「UseDefault」(名稱隨分支而異，未知的 input 通常被忽略)
stock void ToneTryVoidDefaults(int tonemap)
{
	AcceptEntityInput(tonemap, "UseDefaultBloomScale");
	AcceptEntityInput(tonemap, "UseDefaultToneMapPercentTarget");
	AcceptEntityInput(tonemap, "UseDefaultTonemapPercentBrightPixels");
	AcceptEntityInput(tonemap, "UseDefaultTonemapMinAvgLum");
	AcceptEntityInput(tonemap, "UseDefaultAutoExposureMin");
	AcceptEntityInput(tonemap, "UseDefaultAutoExposureMax");
}

stock void ApplyMagicAtmosphere()
{
	if (s_bAtmosphereOn) return;

	int fog = FindEntityByClassname(-1, "env_fog_controller");
	if (fog != -1)
	{
		s_fOriFogStart      = GetEntPropFloat(fog, Prop_Send, "m_fog.start");
		s_fOriFogEnd        = GetEntPropFloat(fog, Prop_Send, "m_fog.end");
		s_fOriFogMaxDensity = GetEntPropFloat(fog, Prop_Send, "m_fog.maxdensity");

		int color = GetEntProp(fog, Prop_Send, "m_fog.colorPrimary");
		s_iOriFogColorR = color & 0xFF;
		s_iOriFogColorG = (color >> 8)  & 0xFF;
		s_iOriFogColorB = (color >> 16) & 0xFF;
		s_bOriFogEnabled = view_as<bool>(GetEntProp(fog, Prop_Send, "m_fog.enable"));
		s_fOriFogFarZ    = GetEntPropFloat(fog, Prop_Send, "m_fog.farz");
		s_bFogBacked = true;

		// Fog start 1500 + end 2000：魔法陣 (通常 < 800) 完全在霧外，遠景開始變黑
		SetVariantString("1500");
		AcceptEntityInput(fog, "SetStartDist");
		SetVariantString("2000");
		AcceptEntityInput(fog, "SetEndDist");
		SetVariantString("1.0");
		AcceptEntityInput(fog, "SetMaxDensity");

		// 關鍵：farz 強制截斷 2200 外的所有像素為 fog color，包含 skybox
		// 比 fog density 更暴力 → 真正讓天空變黑
		SetVariantString("2200");
		AcceptEntityInput(fog, "SetFarZ");
		// 純黑帶一點紫，讓魔法陣的紅 / 橘對比更強烈
		SetVariantString("5 2 12");
		AcceptEntityInput(fog, "SetColor");
		SetVariantString("5 2 12");
		AcceptEntityInput(fog, "SetColorSecondary");
		AcceptEntityInput(fog, "TurnOn");
	}

	// 完全不動 tonemap autoexposure：
	// 經測試任何 exposure 改動都會讓 particle 被 HDR 壓暗。
	// 維持地圖原本 tonemap → particle 顯色最鮮豔，天空黑由 fog 完成。
	// 僅輕度加 bloom 強化發光暈染。
	int tonemap = FindEntityByClassname(-1, "env_tonemap_controller");
	if (tonemap != -1)
	{
		SnapshotTonemapBeforeModify(tonemap);
		SetVariantString("2.0");
		AcceptEntityInput(tonemap, "SetBloomScale");
	}

	// === l4d2_storm 同款大殺器 ===
	// (1) SetLightStyle(0, "a") → 全地圖預設光源 (style 0) 改最暗 ("a"=最暗, "m"=正常, "z"=最亮)
	//     →整個世界 brush 都變黑，但 particle 自發光不受影響 → 對比拉到極限
	SetLightStyle(0, "a");

	// (2) postprocess_controller → 真正的 post-process effect，加 vignette 邊角暗化 + grain 顆粒感
	if (s_iPostProcessRef == INVALID_ENT_REFERENCE || !IsValidEntity(EntRefToEntIndex(s_iPostProcessRef)))
	{
		int pp = CreateEntityByName("postprocess_controller");
		if (pp != -1)
		{
			DispatchKeyValue(pp, "targetname",                "magic_atmosphere_pp");
			DispatchKeyValue(pp, "vignettestart",             "0.6");  // 邊緣多遠開始暗
			DispatchKeyValue(pp, "vignetteend",               "1.4");
			DispatchKeyValue(pp, "vignetteblurstrength",      "0.5");
			DispatchKeyValue(pp, "topvignettestrength",       "1");
			DispatchKeyValue(pp, "localcontraststrength",     "-0.5"); // 負值 = 降對比 → 配合 light style 變暗
			DispatchKeyValue(pp, "localcontrastedgestrength", "-0.3");
			DispatchKeyValue(pp, "grainstrength",             "1");
			DispatchKeyValue(pp, "fadetime",                  "1");
			DispatchKeyValue(pp, "spawnflags",                "1");    // master = 強制所有玩家套用

			float vPos[3] = {0.0, 0.0, 0.0};
			DispatchSpawn(pp);
			ActivateEntity(pp);
			TeleportEntity(pp, vPos, NULL_VECTOR, NULL_VECTOR);
			AcceptEntityInput(pp, "TurnOn");
			s_iPostProcessRef = EntIndexToEntRef(pp);
		}
	}

	EmitSoundToAll("ambient/atmosphere/thunder1.wav");

	s_bAtmosphereOn = true;
}

stock void RestoreMagicAtmosphere()
{
	// 若排程還原已跑過，s_bAtmosphereOn 可能已是 false，但備份仍在 → 仍要還原
	if (!s_bAtmosphereOn && !s_bFogBacked && !s_bOriToneValid)
		return;

	int fog = FindEntityByClassname(-1, "env_fog_controller");
	if (fog != -1 && s_bFogBacked)
	{
		char buf[32];

		FormatEx(buf, sizeof(buf), "%f", s_fOriFogStart);
		SetVariantString(buf);
		AcceptEntityInput(fog, "SetStartDist");

		FormatEx(buf, sizeof(buf), "%f", s_fOriFogEnd);
		SetVariantString(buf);
		AcceptEntityInput(fog, "SetEndDist");

		FormatEx(buf, sizeof(buf), "%f", s_fOriFogMaxDensity);
		SetVariantString(buf);
		AcceptEntityInput(fog, "SetMaxDensity");

		FormatEx(buf, sizeof(buf), "%d %d %d", s_iOriFogColorR, s_iOriFogColorG, s_iOriFogColorB);
		SetVariantString(buf);
		AcceptEntityInput(fog, "SetColor");
		SetVariantString(buf);
		AcceptEntityInput(fog, "SetColorSecondary");

		AcceptEntityInput(fog, s_bOriFogEnabled ? "TurnOn" : "TurnOff");

		// 還原 farz：原值 < 0 通常代表「不限制」，傳 -1 給 SetFarZ 達成相同效果
		FormatEx(buf, sizeof(buf), "%f", s_fOriFogFarZ);
		SetVariantString(buf);
		AcceptEntityInput(fog, "SetFarZ");
	}
	s_bFogBacked = false;

	int tonemap = FindEntityByClassname(-1, "env_tonemap_controller");
	if (tonemap != -1 && s_bOriToneValid)
	{
		ToneApplySnapshot(tonemap);
	}
	else if (tonemap != -1)
	{
		ToneTryVoidDefaults(tonemap);
	}
	ToneClearBackup();

	// 還原 light style 0 到預設正常亮度 "m"
	SetLightStyle(0, "m");

	// 移除 postprocess_controller
	if (s_iPostProcessRef != INVALID_ENT_REFERENCE)
	{
		int pp = EntRefToEntIndex(s_iPostProcessRef);
		if (pp != INVALID_ENT_REFERENCE && IsValidEntity(pp))
		{
			AcceptEntityInput(pp, "TurnOff");
			RemoveEntity(pp);
		}
		s_iPostProcessRef = INVALID_ENT_REFERENCE;
	}

	s_bAtmosphereOn = false;
}

stock void ResetMagicAtmosphere()
{
	// 換圖時：light style / postprocess entity 都會被 engine 清掉，但變數可能殘留
	if (s_bAtmosphereOn)
	{
		SetLightStyle(0, "m"); // 保險：避免新地圖一開始仍是暗的
	}
	s_iPostProcessRef = INVALID_ENT_REFERENCE;
	s_bAtmosphereOn = false;
	s_bFogBacked = false;
	ToneClearBackup();
	if (s_hRestoreTimer != null)
	{
		KillTimer(s_hRestoreTimer);
		s_hRestoreTimer = null;
	}
}

stock void ScheduleRestoreAtmosphere(float delay)
{
	if (s_hRestoreTimer != null)
	{
		KillTimer(s_hRestoreTimer);
		s_hRestoreTimer = null;
	}
	s_hRestoreTimer = CreateTimer(delay, Timer_RestoreAtmosphere);
}

public Action Timer_RestoreAtmosphere(Handle timer)
{
	s_hRestoreTimer = null;
	RestoreMagicAtmosphere();
	return Plugin_Stop;
}
