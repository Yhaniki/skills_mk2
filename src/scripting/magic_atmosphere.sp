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
static float  s_fOriFogStart      = -1.0;
static float  s_fOriFogEnd        = -1.0;
static float  s_fOriFogMaxDensity = -1.0;
static int    s_iOriFogColorR     = -1;
static int    s_iOriFogColorG     = -1;
static int    s_iOriFogColorB     = -1;
static bool   s_bOriFogEnabled    = false;
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
		s_bFogBacked = true;

		SetVariantString("80");
		AcceptEntityInput(fog, "SetStartDist");
		SetVariantString("1200");
		AcceptEntityInput(fog, "SetEndDist");
		SetVariantString("0.85");
		AcceptEntityInput(fog, "SetMaxDensity");
		SetVariantString("25 15 50");
		AcceptEntityInput(fog, "SetColor");
		SetVariantString("25 15 50");
		AcceptEntityInput(fog, "SetColorSecondary");
		AcceptEntityInput(fog, "TurnOn");
	}

	int tonemap = FindEntityByClassname(-1, "env_tonemap_controller");
	if (tonemap != -1)
	{
		SnapshotTonemapBeforeModify(tonemap);

		SetVariantString("0.05");
		AcceptEntityInput(tonemap, "SetAutoExposureMin");
		SetVariantString("0.20");
		AcceptEntityInput(tonemap, "SetAutoExposureMax");

		SetVariantString("30.0");
		AcceptEntityInput(tonemap, "SetTonemapPercentTarget");
		SetVariantString("1.0");
		AcceptEntityInput(tonemap, "SetTonemapMinAvgLum");

		SetVariantString("8.0");
		AcceptEntityInput(tonemap, "SetTonemapPercentBrightPixels");

		SetVariantString("0.60");
		AcceptEntityInput(tonemap, "SetBloomScale");
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

	s_bAtmosphereOn = false;
}

stock void ResetMagicAtmosphere()
{
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
