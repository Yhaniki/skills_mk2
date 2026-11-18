// 實體發光（輪廓光）
bool State_Glow[MAXENTITIES];
Handle Glow_Timer[MAXENTITIES];

void GlowForSecs(int entity, int r, int g, int b, float time)
{
	if(!IsValidEntity(entity))return;
	if (entity < MAXENTITIES &&
		entity > 0 &&
		State_Glow[entity] &&
		Glow_Timer[entity] != null)
	{
		delete Glow_Timer[entity];
	}
	State_Glow[entity] = true;

	// new glowcolor = r + g * 256 + b * 65536;
	int glowcolor = r | (g << 8) | (b << 16);
	if (!HasEntProp(entity, Prop_Send, "m_glowColorOverride")) return;
	SetEntProp(entity, Prop_Send, "m_nGlowRange", 3000);
	SetEntProp(entity, Prop_Send, "m_glowColorOverride", glowcolor);
	SetEntProp(entity, Prop_Send, "m_iGlowType", 3);
	AcceptEntityInput(entity, "StartGlowing");
	Glow_Timer[entity] = CreateTimer(time, Timer_Unglow, entity);
}

// 由 main.sp 的 OnEntityDestroyed 呼叫
void Glow_OnEntityDestroyed(int entity)
{
	if (entity < 0)
		return;

	UnGlow(entity);
}

public Action Timer_Unglow(Handle timer, any entity)
{
	UnGlow(entity);
	Glow_Timer[entity] = null;
	return Plugin_Stop;
}

void UnGlow(int entity)
{
	State_Glow[entity] = false;

	if (!IsValidEntity(entity)) return;
	if (!HasEntProp(entity, Prop_Send, "m_iGlowType")) return;
	SetEntProp(entity, Prop_Send, "m_iGlowType", 0);
}

public void Event_DeathUnglow(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int entity = event.GetInt("entityid");
	if (IsSpecialInf(client) ||
		IsPlayer(client)||
		IsInf(entity) ||
		IsWitch(entity))
	{
		if (State_Glow[client]) UnGlow(client);
	}
}
