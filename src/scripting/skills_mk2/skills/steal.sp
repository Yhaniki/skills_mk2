// 偷竊 Steal：對準隊友偷走手上武器，或對準殭屍、特感、女巫隨機取得物品（偷女巫會把她驚醒）

static int s_iSteal;

int Steal_Register()
{
	s_iSteal = Skill_Register("Skill_Steal", 6.0, 2.0, 20.0);
	Skill_OnStart(s_iSteal, Steal_OnStart);
	Skill_OnPrecache(s_iSteal, Steal_OnPrecache);
	return s_iSteal;
}

static void Steal_OnPrecache()
{
	SetupMaterial("sound\\skills\\steal.mp3");
	SetupSound("skills\\steal.mp3", true);
}

// 從殭屍身上偷到的物品表。偷到時用它當翻譯檔的 key 顯示名稱，所以每一項都要在翻譯檔裡
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
					// 訊息裡的武器名稱：翻譯檔的 key 是 classname，近戰武器的 classname 都是 weapon_melee，
					// 要看腳本名稱（katana → weapon_katana）。翻譯檔沒有的（自訂近戰武器等）直接顯示名稱
					char key[MAXCMD];
					char shown[MAXCMD];
					strcopy(key, sizeof(key), item);
					strcopy(shown, sizeof(shown), item);
					if (StrEqual(item, "weapon_melee"))
					{
						GetEntPropString(weaponIdx, Prop_Data, "m_strMapSetScriptName", shown, sizeof(shown));
						FormatEx(key, sizeof(key), "weapon_%s", shown);
					}
					SetItemToPlayer(client, item, weaponIdx, ammo, clip);
					int idx = GetItemTranslateIdx(key);
					if (idx >= 0)
						Chat_PrintAll("%t", "Chat_StolePlayer", client, entityId, g_sWeaponNames[idx]);
					else
						Chat_PrintAll("%t", "Chat_StolePlayerRaw", client, entityId, shown);
				}
				else
				{
					Chat_PrintAll("%t", "Chat_StealFailed", client);
				}
			}
			else
			{
				Chat_PrintAll("%t", "Chat_StealFailed", client);
			}
		}
		else if (type==1)
		{
			// 3. If the player has aimed a zombie, randomly choose an item from the item table
			//    The chance of obtaining an item can be based on a predetermined percentage set in the table
			// 女巫跟殭屍一樣從物品表隨機拿，但偷完會驚嚇她（施放時瞄準的是女巫就算，她中途死了也照樣偷到）
			bool fromWitch = (witchRef != INVALID_ENT_REFERENCE);
			int weaponIdx = GetRandomInt(0, MAX_WEAPONS - 1);
			int idx = GetItemIdx(weaponIdx);
			char victim[MAXCMD];
			if (fromWitch)
				strcopy(victim, sizeof(victim), "Victim_Witch");
			else
				strcopy(victim, sizeof(victim), "Victim_Infected");
			Chat_PrintAll("%t", "Chat_StoleInfected", client, victim, g_sWeapons[weaponIdx]);
			SetItemToPlayer(client, g_sWeapons[weaponIdx], idx, -1,-1);
			if (fromWitch)
				Steal_StartleWitch(client, witchRef);
		}
		else
		{
			Chat_PrintAll("%t", "Chat_StealFailed", client);
		}
	}
	else
	{
		// 4. If the player hasn't aimed at any person, return a failed status
		Chat_PrintAll("%t", "Chat_StealFailed", client);
	}
}
