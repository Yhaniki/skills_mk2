// 鷹眼 Eagle Eye：時間減慢，偵測並標示周圍所有殭屍

static int s_iEagleEye;

int EagleEye_Register()
{
	s_iEagleEye = Skill_Register("Eagle Eye 鷹眼", 7.0, 2.0, 40.0);
	Skill_OnStart(s_iEagleEye, EagleEye_OnStart);
	Skill_OnEnd(s_iEagleEye, EagleEye_OnEnd);
	Skill_OnTick(s_iEagleEye, EagleEye_OnTick);
	Skill_OnPrecache(s_iEagleEye, EagleEye_OnPrecache);
	return s_iEagleEye;
}

static void EagleEye_OnPrecache()
{
	SetupMaterial("sound\\skills\\eagleeye.mp3");
	SetupSound("skills\\eagleeye.mp3", true);
	PrecacheParticle(PARTICLE_EAGLEEYE);
}

// 施放期間每 0.5 秒持續標示新進入範圍的殭屍
static void EagleEye_OnTick(int client)
{
	if (Skill_GetState(client) == SKILL_ACT)
		DetectInfect(client);
}

void DetectInfect(int client)
{
	const float durningTime = 10.0;
	// This number of seconds is longer than eagleeye's casting time,
	// so that it will not be interrupted during the casting process.
	float range = EAGLE_EYE_RANGE;
	float pos[3];

	GetClientAbsOrigin(client, pos);

	for(int i = 1; i <= MAX_PLAYERS; i++)
	{
		if(!IsClientInGame(i) || !IsPlayerAlive(i) || State_Glow[i]) continue;

		if (GetClientTeam(i) == 3)
		{
			if (GetEntityPosDistance(i, pos) <= range)
			{
				GlowForSecs(i, 150, 100, 0, durningTime);
			}
		}
	}
	// GetEntityCount() 是 entity 的數量，不是最大的編號，中間有空號時會漏掉後面的殭屍
	int maxEnt = GetMaxEntities();
	for (int i = MAX_PLAYERS + 1; i < maxEnt; i++)
	{
		if (!IsValidEntity(i) || !IsAlive(i) || State_Glow[i])
			continue;

		if (IsWitch(i))
		{
			if (GetEntityPosDistance(i, pos) <= range)
			{
				GlowForSecs(i, 255, 255, 255, durningTime);
			}
		}
		else if (IsInf(i))
		{
			if (GetEntityPosDistance(i, pos) <= range)
			{
				GlowForSecs(i, 200, 0, 0, durningTime);
			}
		}
	}
}

static void EagleEye_OnEnd(int client)
{
	int maxEnt = GetMaxEntities();
	for (int i = 1; i < maxEnt; i++)
	{
		if (!IsValidEntity(i)) continue;
		if (IsWitch(i) || IsInf(i) || IsAliveSpecialInf(i))
		{
			UnGlow(i);
		}
	}
}

static void EagleEye_OnStart(int client)
{
	//PrepareAndEmitSoundtoAll("skills\\eagleeye.mp3", .entity = client, .volume = 1.0);

	GlowForSecs(client, 0, 100, 0, 10.0);
	SlowForSecs(6.0, client);
	ParticleFollow(PARTICLE_EAGLEEYE, client, 1.0);
	DetectInfect(client);
	PrintToChatAll("\x04%N \x01Eagle Eye!", client);
}
