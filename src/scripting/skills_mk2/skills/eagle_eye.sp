// 鷹眼 Eagle Eye：時間減慢，偵測並標示周圍所有殭屍

void EagleEye_Register()
{
	RegisterSkill("Eagle Eye 鷹眼" ,Timer_Skill_EagleEye_Start, Timer_Skill_EagleEye_End, Timer_Skill_Null_Ready, 7.0, 2.0, 40.0);
}

// 施放期間由 core/hud.sp 每 0.5 秒呼叫一次，持續標示新進入範圍的殭屍
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
	int EntityCount = GetEntityCount();
	for (int i = MAX_PLAYERS + 1; i <= EntityCount; i++)
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

public Action Timer_Skill_EagleEye_End(Handle timer, int client)
{
	Skill_Duration_Timer[client] = null;
	Skill_State[client] = SKILL_CD;
	for (int i = 1; i <= GetEntityCount(); i++)
	{
		if (!IsValidEntity(i)) continue;
		if (IsWitch(i) || IsInf(i) || IsAliveSpecialInf(i))
		{
			UnGlow(i);
		}
	}
	return Plugin_Stop;
}

public Action Timer_Skill_EagleEye_Start(Handle timer, any client)
{
	//PrepareAndEmitSoundtoAll("skills\\eagleeye.mp3", .entity = client, .volume = 1.0);

	GlowForSecs(client, 0, 100, 0, 10.0);
	SlowForSecs(6.0, client);
	ParticleFollow(PARTICLE_EAGLEEYE, client, 1.0);
	DetectInfect(client);
	PrintToChatAll("\x04%N \x01Eagle Eye!", client);

	return Plugin_Stop;
}
