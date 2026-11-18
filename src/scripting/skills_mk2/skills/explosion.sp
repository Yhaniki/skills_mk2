// 爆裂 Explosion：瞄準位置延遲爆炸，對範圍內殭屍造成傷害

void Explosion_Register()
{
	RegisterSkill("Explosion 爆裂" ,Timer_Skill_Explosion_Start, Timer_Skill_Null_End, Timer_Skill_Null_Ready, 3.0, 2.0, 30.0);
}

public Action Timer_Skill_Explosion_Start(Handle timer, any client)
{
	PrepareAndEmitSoundtoAll("skills\\explosion.mp3", .entity = client, .volume = 1.0);

	GlowForSecs(client, 100, 0, 0, 1.5*time_weight);
	ExplodeAim(client, 1.5*time_weight);

	PrintToChatAll("\x04%N \x01EXPLOSION!", client);

	return Plugin_Stop;
}

void ExplodeAim(int client, float delay)
{
	float Pos[3];
	if (GetAimOrigin(client, Pos, 10.0) == 0) return;

	//ExplodeAtPos(Pos);

	DataPack DP = new DataPack();
	DP.WriteCell(client);
	DP.WriteCell(Pos[0]);
	DP.WriteCell(Pos[1]);
	DP.WriteCell(Pos[2]);

	CreateParticle(PARTICLE_EXPLOSION, delay + 1.0, Pos);
	CreateTimer(delay, Timer_ExplodeAimDelay, DP);
}

int ComputeExploDmg(float dist)
{
	const int maxDamage = 500;
	int dmg = RoundToNearest(maxDamage * RoundToNearest(EXPLOSION_DIST - dist) / EXPLOSION_DIST);
	if (dmg < 0) dmg = 0;
	return dmg;
}

public Action Timer_ExplodeAimDelay(Handle timer, DataPack DP)
{
	DP.Reset();
	int client = DP.ReadCell();
	float Pos[3];
	Pos[0] = DP.ReadCell();
	Pos[1] = DP.ReadCell();
	Pos[2] = DP.ReadCell();

	PropaneAtPos(Pos);
	int dmg = 0;
	float distance = 0.0;

	for (int i = 1; i <= GetEntityCount(); i++)
	{
		if (!IsValidEntity(i)) continue;
		if (IsWitch(i) || IsInf(i) || IsAliveSpecialInf(i))
		{
			distance = GetEntityPosDistance(i, Pos);
			if (distance <= EXPLOSION_DIST)
			{
				dmg = ComputeExploDmg(distance);
				DealDamage(i, dmg, client, DMG_BURN);
			}
		}
	}
	return Plugin_Stop;
}

void PropaneAtPos(float Pos[3])
{
	int prop = CreateEntityByName("prop_physics");
	DispatchKeyValue(prop, "model", "models/props_junk/propanecanister001a.mdl");
	DispatchSpawn(prop);
	TeleportEntity(prop, Pos, NULL_VECTOR, NULL_VECTOR);
	ActivateEntity(prop);
	AcceptEntityInput(prop, "break");
}
