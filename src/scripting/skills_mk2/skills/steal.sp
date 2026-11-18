// 偷竊 Steal：對準隊友偷走手上武器，或對準殭屍隨機取得物品

void Steal_Register()
{
	RegisterSkill("Steal 偷竊" ,Timer_Skill_Steal_Start, Timer_Skill_Null_End, Timer_Skill_Null_Ready, 6.0, 2.0, 20.0);// Float:skill_duration, Float:skill_cooldown, Float:skill_mpcost
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
		else if (IsAliveInf(entityId) || IsAliveSpecialInf(entityId)||IsWitch(entityId))
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
public Action Timer_Skill_Steal_Start(Handle timer, any client)
{
	// FakeClientCommand(client, "give katana");
	PrepareAndEmitSoundtoAll("skills\\steal.mp3", .entity = client, .volume = 1.0);
	PrintToChatAll("\x04%N \x01STEAL!", client);

	GlowForSecs(client, 0, 100, 0, 6.0*time_weight);//rgb sec
	// Skill_Steal(client);
	int entityId = GetClientAimTarget(client, false);//return Entity
	DataPack DP = new DataPack();
	DP.WriteCell(client);
	DP.WriteCell(entityId);
	DP.WriteCell(CheckStealType(entityId));
	CreateTimer(5.2*time_weight, Skill_Steal, DP);
	return Plugin_Stop;
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

public Action Skill_Steal(Handle timer, DataPack DP)
{
	DP.Reset();
	int client = DP.ReadCell();
	int entityId = DP.ReadCell();
	int type = DP.ReadCell();
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
			int weaponIdx = GetRandomInt(0, MAX_WEAPONS - 1);
			int idx = GetItemIdx(weaponIdx);
			if (idx >= 0)
			{
				char wname[MAXCMD];
				GetWeaponTranslate(idx, LANG_SERVER, wname, sizeof(wname));
				PrintToChatAll("\x04%N \x01從 \x04殭屍 \x01身上偷了 \x04%s", client, wname);
			}
			else
			{
				PrintToChatAll("\x04%N \x01從 \x04殭屍 \x01身上偷了 \x04%s", client, g_sWeapons[weaponIdx]);
			}
			// PrintToChatAll("\x04%N \x01從殭屍身上偷了 %s", client, g_sWeapons[weaponIdx]);
			SetItemToPlayer(client, g_sWeapons[weaponIdx], idx, -1,-1);
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
	return Plugin_Stop;
}
