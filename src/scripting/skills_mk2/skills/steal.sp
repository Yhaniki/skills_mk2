// 偷竊 Steal：對準隊友偷走手上武器，或對準殭屍、特感、女巫隨機取得物品（偷女巫會把她驚醒）

static int s_iSteal;

int Steal_Register()
{
	s_iSteal = Skill_Register("Steal 偷竊", 6.0, 2.0, 20.0);
	Skill_OnStart(s_iSteal, Steal_OnStart);
	Skill_OnPrecache(s_iSteal, Steal_OnPrecache);
	return s_iSteal;
}

static void Steal_OnPrecache()
{
	SetupMaterial("sound\\skills\\steal.mp3");
	SetupSound("skills\\steal.mp3", true);
}

// 從殭屍身上偷到的物品表
static char g_sWeapons[MAX_WEAPONS][] =
{
	"weapon_rifle",
	"weapon_autoshotgun",
	"weapon_hunting_rifle",
	"weapon_smg",
	"weapon_pumpshotgun",
	"weapon_pistol",
	"weapon_molotov",
	"weapon_pipe_bomb",
	"weapon_first_aid_kit",
	"weapon_pain_pills",
	// "weapon_katana",
	"weapon_pistol" ,
	"weapon_pistol_magnum"
};

int CheckStealType(int entityId)
{
	char target[MAXCMD];
	int result = -1;

	if (entityId < 0 || !IsValidEntity(entityId))
	{
		result = -1;
	}
	else
	{
		GetEdictClassname(entityId, target, MAXCMD);
		if ((StrEqual(target, "player")) &&
			(IsPlayerAlive(entityId) == true) &&
			(GetClientTeam(entityId) != 3))
		{
			result = 0;
		}
		else if (IsInf(entityId) || IsAliveSpecialInf(entityId)||IsWitch(entityId))
		{
			result = 1;
		}
		else
		{
			result = -1;
		}
	}
	return result;
}
static void Steal_OnStart(int client)
{
	// FakeClientCommand(client, "give katana");
	PrepareAndEmitSoundtoAll("skills\\steal.mp3", .entity = client, .volume = 1.0);
	PrintToChatAll("\x04%N \x01STEAL!", client);

	GlowForSecs(client, 0, 100, 0, 6.0*time_weight);//rgb sec
	// Skill_Steal(client);
	int entityId = GetClientAimTarget(client, false);//return Entity
	DataPack data = Skill_Schedule(s_iSteal, client, 5.2*time_weight, Steal_StepSteal);
	data.WriteCell(entityId);
	data.WriteCell(CheckStealType(entityId));
	// 女巫偷到的瞬間要驚嚇她。5.2 秒內女巫可能死掉、實體編號被別的東西重用，所以存 reference
	data.WriteCell(IsWitch(entityId) ? EntIndexToEntRef(entityId) : INVALID_ENT_REFERENCE);
}

// 施法者對女巫造成 1 點傷害：女巫受到倖存者攻擊就會驚醒，並把攻擊者當成目標
static void Steal_StartleWitch(int client, int witchRef)
{
	int witch = EntRefToEntIndex(witchRef);
	if (witch == INVALID_ENT_REFERENCE || GetEntProp(witch, Prop_Data, "m_iHealth") <= 0) return;
	SDKHooks_TakeDamage(witch, client, client, 1.0, DMG_BULLET);
}

int GetItemIdx(int idx)
{
	int rst = -1;
	for(int i=0; i<ALL_WEAPONS; i++)
	{
		if(StrEqual(g_sWeapons[idx], g_sWeaponNames[i]))
		{
			rst = i;
			break;
		}
	}
	return rst;
}

static void Steal_StepSteal(int client, DataPack data)
{
	int entityId = data.ReadCell();
	int type = data.ReadCell();
	int witchRef = data.ReadCell();
	// 1. Read the type and coordinates of the object aimed by the player
	// new entityId = GetClientAimTarget(client, false);//return Entity
	char item[MAXCMD];
	char target[MAXCMD];

	if (entityId >= 0)
	{
		// PrintToChatAll("entityId %s", target);
		if (type==0)
		{
			GetEdictClassname(entityId, target, MAXCMD);
			if ((StrEqual(target, "player")) &&
				(IsPlayerAlive(entityId) == true) &&
				(GetClientTeam(entityId) != 3))
			{
				// 2. If the player has aimed another client, check the item they are currently holding
				//    Randomly select one item from the client and remove it from their inventory
				int ammo = GetWeaponAmmo(entityId);
				int clip = GetWeaponClip(entityId);
				// PrintToChatAll("ammo %d\n",ammo);
				int weaponIdx = ForceWeaponDrop(entityId);
				if (weaponIdx > 0)
				{
					GetEdictClassname(weaponIdx, item, MAXCMD);
					SetItemToPlayer(client, item, weaponIdx, ammo, clip);
					int idx = GetItemTranslateIdx(item);
					if (idx >= 0)
					{
						char wname[MAXCMD];
						GetWeaponTranslate(idx, LANG_SERVER, wname, sizeof(wname));
						PrintToChatAll("\x04%N \x01從 \x04%N \x01身上偷了 \x04%s", client, entityId, wname);
					}
					else if(weaponIdx<ALL_WEAPONS)
					{
						PrintToChatAll("idx %d all %d %d\n",idx,ALL_WEAPONS,weaponIdx);
						PrintToChatAll("\x04%N \x01從 \x04%N \x01身上偷了 \x04%s", client, entityId, g_sWeaponNames[weaponIdx]);
					}
					else
					{
						if(StrEqual(item, "weapon_melee")==true)
						{
							GetEntPropString(entityId, Prop_Data, "m_strMapSetScriptName", item, MAXCMD);
						}
						PrintToChatAll("\x04%N \x01從 \x04%N \x01身上偷了 \x04%s", client, entityId, item);
					}
				}
				else
				{
					PrintToChatAll("\x04%N \x01偷竊失敗", client);
				}
			}
			else
			{
				PrintToChatAll("\x04%N \x01偷竊失敗", client);
			}
		}
		else if (type==1)
		{
			// 3. If the player has aimed a zombie, randomly choose an item from the item table
			//    The chance of obtaining an item can be based on a predetermined percentage set in the table
			// 女巫跟殭屍一樣從物品表隨機拿，但偷完會驚嚇她（施放時瞄準的是女巫就算，她中途死了也照樣偷到）
			bool fromWitch = (witchRef != INVALID_ENT_REFERENCE);
			char from[16];
			strcopy(from, sizeof(from), fromWitch ? "女巫" : "殭屍");
			int weaponIdx = GetRandomInt(0, MAX_WEAPONS - 1);
			int idx = GetItemIdx(weaponIdx);
			if (idx >= 0)
			{
				char wname[MAXCMD];
				GetWeaponTranslate(idx, LANG_SERVER, wname, sizeof(wname));
				PrintToChatAll("\x04%N \x01從 \x04%s \x01身上偷了 \x04%s", client, from, wname);
			}
			else
			{
				PrintToChatAll("\x04%N \x01從 \x04%s \x01身上偷了 \x04%s", client, from, g_sWeapons[weaponIdx]);
			}
			// PrintToChatAll("\x04%N \x01從殭屍身上偷了 %s", client, g_sWeapons[weaponIdx]);
			SetItemToPlayer(client, g_sWeapons[weaponIdx], idx, -1,-1);
			if (fromWitch)
				Steal_StartleWitch(client, witchRef);
		}
		else
		{
			PrintToChatAll("\x04%N \x01偷竊失敗", client);
		}
	}
	else
	{
		// 4. If the player hasn't aimed at any person, return a failed status
		PrintToChatAll("\x04%N \x01偷竊失敗", client);
	}
}
