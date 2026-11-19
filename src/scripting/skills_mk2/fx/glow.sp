// 實體發光（輪廓光）
//
// 伺服器只會把 PVS 裡的 entity 傳給玩家（普通殭屍、女巫的傳送旗標是 FL_EDICT_PVSCHECK，發光也不會改變）。
// 隔著牆、不在 PVS 裡的殭屍熄掉或死掉時，玩家收不到這個更新，畫面會停在最後收到的狀態，光就一直留著。
// 所以熄掉時暫時加上 FL_EDICT_ALWAYS，多傳 GLOW_SEND_ALL_SECS 秒，確定每個玩家都收到之後再拿掉。
// 玩家（倖存者、特感）的傳送由遊戲自己的 ShouldTransmit 決定（FULLCHECK），不去動它。
#define GLOW_SEND_ALL_SECS 2.0

bool State_Glow[MAXENTITIES];
Handle Glow_Timer[MAXENTITIES];

// 由這裡加上 FL_EDICT_ALWAYS 的 entity（reference，沒有是 0）與拿掉旗標的 timer
static int    s_iSendAllRef[MAXENTITIES];
static Handle s_hSendAllTimer[MAXENTITIES];

void GlowForSecs(int entity, int r, int g, int b, float time)
{
	if(!IsValidEntity(entity))return;
	if (entity <= 0 || entity >= MAXENTITIES) return;
	// 被 UnGlow 熄掉時 timer 不會刪，這裡一律刪掉，舊 timer 才不會提早把新的光熄掉
	delete Glow_Timer[entity];
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
	if (entity < 0 || entity >= MAXENTITIES)
		return;

	// entity 要被刪掉了，不用再熄光或多傳；timer 也刪掉，免得編號被新的 entity 重用後熄到它
	State_Glow[entity] = false;
	delete Glow_Timer[entity];
	delete s_hSendAllTimer[entity];
	s_iSendAllRef[entity] = 0;
}

public Action Timer_Unglow(Handle timer, any entity)
{
	Glow_Timer[entity] = null;
	UnGlow(entity);
	return Plugin_Stop;
}

void UnGlow(int entity)
{
	// 死亡時遊戲已經把 m_iGlowType 清成 0，所以 State_Glow 也要算「有亮」
	bool wasGlowing = State_Glow[entity];
	State_Glow[entity] = false;

	if (!IsValidEntity(entity)) return;
	if (!HasEntProp(entity, Prop_Send, "m_iGlowType")) return;
	if (GetEntProp(entity, Prop_Send, "m_iGlowType") != 0) wasGlowing = true;
	SetEntProp(entity, Prop_Send, "m_iGlowType", 0);
	// 鷹眼結束時會對所有殭屍呼叫，只有真的亮過的才需要多傳
	if (wasGlowing) Glow_SendToAll(entity);
}

// 熄光（或死亡）的狀態要送到每個玩家：暫時傳給所有人，GLOW_SEND_ALL_SECS 秒後恢復原本的傳送方式
static void Glow_SendToAll(int entity)
{
	if (entity <= MaxClients || entity >= MAXENTITIES || !IsValidEdict(entity)) return;

	int ref = EntIndexToEntRef(entity);
	if (s_iSendAllRef[entity] != ref)
	{
		int flags = GetEdictFlags(entity);
		if (flags & FL_EDICT_ALWAYS) return;  // 本來就傳給所有人，不用處理
		SetEdictFlags(entity, flags | FL_EDICT_ALWAYS);
		s_iSendAllRef[entity] = ref;
	}
	delete s_hSendAllTimer[entity];
	s_hSendAllTimer[entity] = CreateTimer(GLOW_SEND_ALL_SECS, Timer_GlowSendAllEnd, entity);
}

static Action Timer_GlowSendAllEnd(Handle timer, any entity)
{
	s_hSendAllTimer[entity] = null;
	int ref = s_iSendAllRef[entity];
	s_iSendAllRef[entity] = 0;
	if (ref && EntRefToEntIndex(ref) == entity)
		SetEdictFlags(entity, GetEdictFlags(entity) & ~FL_EDICT_ALWAYS);
	return Plugin_Stop;
}

// 換圖：清掉所有發光的狀態與 timer（entity 都會被刪掉，旗標不用還原）
void Glow_MapEndCleanup()
{
	for (int i = 0; i < MAXENTITIES; i++)
	{
		SafeDeleteTimer(Glow_Timer[i]);
		SafeDeleteTimer(s_hSendAllTimer[i]);
		State_Glow[i]     = false;
		s_iSendAllRef[i] = 0;
	}
}

// 插件卸載：還在多傳的 entity 把 FL_EDICT_ALWAYS 拿掉（timer 會跟著插件消失）
void Glow_PluginEndCleanup()
{
	for (int i = MaxClients + 1; i < MAXENTITIES; i++)
	{
		int ref = s_iSendAllRef[i];
		s_iSendAllRef[i] = 0;
		if (ref && EntRefToEntIndex(ref) == i)
			SetEdictFlags(i, GetEdictFlags(i) & ~FL_EDICT_ALWAYS);
	}
}

// player_death：特感、倖存者看 userid；普通殭屍、女巫的 userid 是 0，要看 entityid
// 遊戲在死亡時就會把 m_iGlowType 清成 0，這裡要做的是清掉 State_Glow，並把死亡的狀態送到每個玩家
public void Event_DeathUnglow(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim <= 0)
		victim = event.GetInt("entityid");
	if (victim <= 0 || victim >= MAXENTITIES)
		return;

	if (State_Glow[victim]) UnGlow(victim);
}
