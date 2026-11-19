// 爆裂 Explosion：瞄準位置延遲爆炸，對範圍內殭屍造成傷害

static int s_iExplosion;

int Explosion_Register()
{
	s_iExplosion = Skill_Register("Skill_Explosion", 3.0, 2.0, 30.0);
	Skill_OnStart(s_iExplosion, Explosion_OnStart);
	Skill_OnPrecache(s_iExplosion, Explosion_OnPrecache);
	return s_iExplosion;
}

static void Explosion_OnPrecache()
{
	SetupMaterial("sound\\skills\\explosion.mp3");
	SetupSound("skills\\explosion.mp3", true);
	PrecacheParticle(PARTICLE_EXPLOSION);
}

static void Explosion_OnStart(int client)
{
	PrepareAndEmitSoundtoAll("skills\\explosion.mp3", .entity = client, .volume = 1.0);

	GlowForSecs(client, 100, 0, 0, 1.5*time_weight);
	ExplodeAim(client, 1.5*time_weight);

	PrintToChatAll("\x04%N \x01EXPLOSION!", client);
}

void ExplodeAim(int client, float delay)
{
	float Pos[3];
	if (GetAimOrigin(client, Pos, 10.0) == 0) return;

	//ExplodeAtPos(Pos);

	CreateParticle(PARTICLE_EXPLOSION, delay + 1.0, Pos);
	DataPack data = Skill_Schedule(s_iExplosion, client, delay, Explosion_StepBlast);
	data.WriteFloat(Pos[0]);
	data.WriteFloat(Pos[1]);
	data.WriteFloat(Pos[2]);
}

int ComputeExploDmg(float dist)
{
	const int maxDamage = 500;
	int dmg = RoundToNearest(maxDamage * RoundToNearest(EXPLOSION_DIST - dist) / EXPLOSION_DIST);
	if (dmg < 0) dmg = 0;
	return dmg;
}

static void Explosion_StepBlast(int client, DataPack data)
{
	float Pos[3];
	Pos[0] = data.ReadFloat();
	Pos[1] = data.ReadFloat();
	Pos[2] = data.ReadFloat();

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
