// 武器相關：名稱翻譯、彈藥存取、給物品（偷竊用）
// 玩家丟槍不在這個插件裡，改用社群插件 l4d_drop（指令 sm_drop）

void Weapons_Init()
{
	SetWeaponNameId();
}

char g_sWeaponNames[ALL_WEAPONS][] =
{
	"weapon_autoshotgun",
	"weapon_grenade_launcher" ,
	"weapon_hunting_rifle",
	"weapon_pistol" ,
	"weapon_pistol_magnum" ,
	"weapon_pumpshotgun" ,
	"weapon_rifle" ,
	"weapon_rifle_ak47" ,
	"weapon_rifle_desert" ,
	"weapon_rifle_m60" ,
	"weapon_rifle_sg552" ,
	"weapon_shotgun_chrome",
	"weapon_shotgun_spas" ,
	"weapon_smg" ,
	"weapon_smg_mp5" ,
	"weapon_smg_silenced" ,
	"weapon_sniper_awp",
	"weapon_sniper_military" ,
	"weapon_sniper_scout" ,

	"weapon_baseball_bat",
	"weapon_cricket_bat",
	"weapon_crowbar",
	"weapon_electric_guitar",
	"weapon_fireaxe",
	"weapon_frying_pan",
	"weapon_golfclub",
	"weapon_katana",
	"weapon_machete",
	"weapon_tonfa",
	"weapon_knife",

	"weapon_chainsaw",

	"weapon_adrenaline",
	"weapon_defibrillator",
	"weapon_first_aid_kit",
	"weapon_pain_pills",

	"weapon_fireworkcrate",
	"weapon_gascan",
	"weapon_oxygentank",
	"weapon_propanetank",

	"weapon_molotov",
	"weapon_pipe_bomb",
	"weapon_vomitjar",

	"weapon_ammo_spawn",
	"weapon_upgradepack_explosive",
	"weapon_upgradepack_incendiary",

	"weapon_gnome",
	"weapon_cola_bottles"
};

// 透過 translations/skills_mk2.phrases.txt 取得武器翻譯名稱
// idx 對應 g_sWeaponNames 的索引；target 為要翻譯給哪個 client（LANG_SERVER 為伺服器語言）
stock void GetWeaponTranslate(int idx, int target, char[] buffer, int maxlen)
{
	if (idx >= 0 && idx < ALL_WEAPONS)
		Format(buffer, maxlen, "%T", g_sWeaponNames[idx], target);
	else
		strcopy(buffer, maxlen, "");
}

void SetPlayerReserveAmmo(int client, int weapon, int ammo)
{
	int ammotype = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if (ammotype >= 0 )
	{
		SetEntProp(client, Prop_Send, "m_iAmmo", ammo, _, ammotype);
		ChangeEdictState(client, FindDataMapInfo(client, "m_iAmmo"));
	}
}

int GetPlayerReserveAmmo(int client, int weapon)
{
	int ammotype = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if (ammotype >= 0)
	{
		return GetEntProp(client, Prop_Send, "m_iAmmo", _, ammotype);
	}
	return 0;
}

// 偷竊拿到新物品時，把同一格原本的武器丟在地上（備用彈藥跟著武器走，雙手手槍拆成兩把）
static void DropWeapon(int client, int weapon)
{
	static char classname[32];
	GetEntityClassname(weapon, classname, sizeof(classname));
	if (strcmp(classname, "weapon_pistol") == 0 && GetEntProp(weapon, Prop_Send, "m_isDualWielding") > 0)
	{
		int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
		int second_clip = 0;
		if(clip % 2 == 0)
		{
			second_clip = clip / 2;
			clip = clip / 2;
		}
		else
		{
			second_clip = clip / 2 + 1;
			clip = clip / 2;
		}

		RemovePlayerItem(client, weapon);
		RemoveEntity(weapon);

		int single_pistol = CreateEntityByName("weapon_pistol");
		if(single_pistol <= MAX_PLAYERS) return;

		DispatchSpawn(single_pistol);
		EquipPlayerWeapon(client, single_pistol);
		SDKHooks_DropWeapon(client, single_pistol);
		SetEntProp(single_pistol, Prop_Send, "m_iClip1", clip);

		single_pistol = CreateEntityByName("weapon_pistol");
		if(single_pistol <= MAX_PLAYERS) return;

		DispatchSpawn(single_pistol);
		EquipPlayerWeapon(client, single_pistol);
		SetEntProp(single_pistol, Prop_Send, "m_iClip1", second_clip);

		return;
	}

	int ammo = GetPlayerReserveAmmo(client, weapon);
	SDKHooks_DropWeapon(client, weapon);
	SetPlayerReserveAmmo(client, weapon, 0);
	SetEntProp(weapon, Prop_Send, "m_iExtraPrimaryAmmo", ammo);

	// if (!g_isSequel) return;

	if (strcmp(classname, "weapon_defibrillator") == 0)
	{
		int modelindex = GetEntProp(weapon, Prop_Data, "m_nModelIndex");
		SetEntProp(weapon, Prop_Send, "m_iWorldModelIndex", modelindex);
	}
}

int ForceWeaponDropBySlot(int client, int slot)
{
	int weapon = GetPlayerWeaponSlot(client, slot);

	if (weapon > 0)
	{
		char item[MAXCMD];
		GetEdictClassname(weapon, item, MAXCMD);
		if(StrEqual(item, "weapon_melee")==true)
		{
			GetEntPropString(weapon, Prop_Data, "m_strMapSetScriptName", item, MAXCMD);
		}
		if(StrEqual(item, "weapon_melee")==false)
		{
			// SDKHooks_DropWeapon(client, weapon, NULL_VECTOR, NULL_VECTOR);
			DropWeapon(client, weapon);
		}
		else
		{
			weapon = -1;
		}
	}
	return weapon;
}

int ForceWeaponDrop(int client)
{
	int weapon = GetNowWeapon(client);
	char item[MAXCMD];
	if (weapon >0)
	{
		GetEdictClassname(weapon, item, MAXCMD);
		// PrintToChatAll("weapon %d", weapon);
		if(StrEqual(item, "weapon_melee")==true)
		{
			GetEntPropString(weapon, Prop_Data, "m_strMapSetScriptName", item, MAXCMD);
		}
		if(StrEqual(item, "weapon_melee")==false)
		{
			int activeweapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
			if(activeweapon>0)
			{
				if (StrEqual(item, "weapon_pistol")&&GetEntProp(activeweapon, Prop_Send, "m_isDualWielding"))
				{
					RemoveEntity(weapon);
					// SetItemToPlayer(client, "weapon_pistol",activeweapon,-1,-1);
					int wq = CreateEntityByName("weapon_pistol");
					DispatchSpawn(wq);
					EquipPlayerWeapon(client, wq);
				}
				else
				{
					// SDKHooks_DropWeapon(client, weapon, NULL_VECTOR, NULL_VECTOR);
					RemoveEntity(weapon);
				}
			}
		}
		else
		{
			weapon = -1;
		}
	}
	return weapon;
}

int GetNowWeapon(int client)
{
	int weapon = -1;

	weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	return weapon;
}

stock int Weapon_GetPrimaryAmmoType(int weapon)
{
	return GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType");
}

void SetItemToPlayer(int client, char[] item, int index, int ammo, int clip)
{
	// char weapon[MAXCMD] = "weapon_katana"; //TODO: get random item
	// int wq = CreateEntityByName(weapon);
	WeaponId id = WeaponNameToId(item);
	int slot = GetSlotFromWeaponId(id);
	bool havePistol = false;
	if (slot == 1)
	{
		int wep_Secondary = GetPlayerWeaponSlot(client, slot);
		if(wep_Secondary<=0)return;
		char wepName[MAXCMD];
		GetEdictClassname(wep_Secondary, wepName, MAXCMD);
		if (StrEqual(wepName, "weapon_pistol"))
		{
			havePistol = true;
		}
	}
	if((slot>=0&&slot!=1)||(slot==1&&!havePistol))
	{
		ForceWeaponDropBySlot(client, slot);
	}
	if(StrEqual(item, "weapon_melee")==true)
	{
		GetEntPropString(index, Prop_Data, "m_strMapSetScriptName", item, MAXCMD);
		char cmd[MAXCMD] = "give ";
		StrCat(cmd, MAXCMD, item);
		// PrintToChatAll("cmd %s\n",cmd);
		FakeClientCommand(client, cmd);
	}
	else
	{
		// PrintToChatAll("wq %s\n",item);
		int wq = CreateEntityByName(item);
		// PrintToChatAll("wq %d\n",wq);
		if (wq > 0)
		{
			DispatchSpawn(wq);
			// EquipPlayerWeapon(client, wq);
			//----------------
			if (StrEqual(item, "weapon_pistol"))
			{
				int wep_Secondary = GetPlayerWeaponSlot(client, 1);
				if (wep_Secondary > 0)
				{
					bool m_isDualWielding = view_as<bool>(GetEntProp(wep_Secondary, Prop_Send, "m_isDualWielding"));
					GetEdictClassname(wep_Secondary, item, MAXCMD);

					if (StrEqual(item, "weapon_pistol") &&
						m_isDualWielding)
					{
						GivePlayerItem(client, "weapon_pistol");
					}
				}
				AcceptEntityInput(wq, "use", client);
			}
			else
			{
				EquipPlayerWeapon(client, wq);
			}
			//----------------
			int weapon = GetPlayerWeaponSlot(client, 0);
			if (weapon == wq)
			{
				int ammoAmount = GetRandomInt(MIN_STEAL_AMMO, MAX_STEAL_AMMO);
				if(ammo>=0)ammoAmount = ammo;
				// PrintToChatAll("ammoAmount %d\n",ammoAmount);
				// SetWeaponAmmo(client, weapon, ammoAmount);
				GivePlayerAmmo(client, ammoAmount, Weapon_GetPrimaryAmmoType(weapon), true);
				if(clip>=0) SetWeaponClip(weapon, clip);
			}
		}
	}
}

int GetItemTranslateIdx(char item[MAXCMD])
{
	int rst = -1;
	for(int i=0; i<ALL_WEAPONS; i++)
	{
		if(StrEqual(item, g_sWeaponNames[i]))
		{
			rst = i;
			break;
		}
	}
	return rst;
}
