// 粒子特效：預載、建立、跟隨玩家、刪除
void PrecacheParticle(const char[] sEffectName)
{
	static int table = INVALID_STRING_TABLE;
	if( table == INVALID_STRING_TABLE )
	{
		table = FindStringTable("ParticleEffectNames");
	}

	if( FindStringIndex(table, sEffectName) == INVALID_STRING_INDEX )
	{
		bool save = LockStringTables(false);
		AddToStringTable(table, sEffectName);
		LockStringTables(save);
	}
}

Action DeleteParticles(Handle timer, int ref)
{
	int entity = EntRefToEntIndex(ref);
	if(entity == INVALID_ENT_REFERENCE) return Plugin_Continue;

	AcceptEntityInput(entity, "stop");
	AcceptEntityInput(entity, "kill");
	return Plugin_Continue;
}

// 建立粒子並自動定時刪除（內部使用 entity ref 而非 raw index）
// 回傳 entity index（-1 代表失敗），若需追蹤請在外部轉 EntIndexToEntRef
int CreateParticleEnt(const char[] particlename, float time, const float Pos[3])
{
	int particle = CreateEntityByName("info_particle_system");
	if (!IsValidEntity(particle)) return -1;

	DispatchKeyValue(particle, "scale", "");
	DispatchKeyValue(particle, "effect_name", particlename);
	DispatchKeyValue(particle, "targetname", "particle");
	TeleportEntity(particle, Pos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(particle);
	ActivateEntity(particle);
	AcceptEntityInput(particle, "Enable");
	AcceptEntityInput(particle, "start");
	CreateTimer(time, DeleteParticles, EntIndexToEntRef(particle));
	return particle;
}

void CreateParticle(const char[] particlename, float time, const float Pos[3])
{
	CreateParticleEnt(particlename, time, Pos);
}

// 建立跟隨玩家的粒子，回傳 entity ref（INVALID_ENT_REFERENCE 代表失敗）
int ParticleFollow(char[] particleName, int client, float time)
{
	float pos[3];
	if(GetClientTeam(client) == 2 && IsPlayerAlive(client))
	{
		int entity = CreateEntityByName("info_particle_system");
		DispatchKeyValue(entity, "effect_name", particleName);
		GetEntPropVector(client, Prop_Send, "m_vecOrigin", pos);
		TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(entity);
		SetVariantString("!activator");
		AcceptEntityInput(entity, "SetParent", client);
		ActivateEntity(entity);
		AcceptEntityInput(entity, "Start");

		int ref = EntIndexToEntRef(entity);
		CreateTimer(time, DeleteParticles, ref);
		return ref;
	}
	return INVALID_ENT_REFERENCE;
}

// 安全殺掉一個 entity ref 指向的 particle
stock void KillParticleRef(int &ref)
{
	if (ref == INVALID_ENT_REFERENCE) return;
	int ent = EntRefToEntIndex(ref);
	if (ent != INVALID_ENT_REFERENCE && IsValidEntity(ent))
	{
		AcceptEntityInput(ent, "stop");
		AcceptEntityInput(ent, "kill");
	}
	ref = INVALID_ENT_REFERENCE;
}
