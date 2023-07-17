#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <left4dhooks>

int WeaponAmmoOffset[view_as<int>(ID_WEAPON_MAX)];
StringMap g_smWeaponNameID;
enum WeaponID
{
	ID_NONE,
	ID_PISTOL,
	ID_DUAL_PISTOL,
	ID_SMG,
	ID_PUMPSHOTGUN,
	ID_RIFLE,
	ID_AUTOSHOTGUN,
	ID_HUNTING_RIFLE,
	ID_SMG_SILENCED,
	ID_SMG_MP5,
	ID_CHROMESHOTGUN,
	ID_MAGNUM,
	ID_AK47,
	ID_RIFLE_DESERT,
	ID_SNIPER_MILITARY,
	ID_GRENADE,
	ID_SG552,
	ID_M60,
	ID_AWP,
	ID_SCOUT,
	ID_SPASSHOTGUN,
	ID_WEAPON_MAX
}

void SetWeaponNameId()
{
	g_smWeaponNameID = CreateTrie();
	g_smWeaponNameID.SetValue("", ID_NONE);
	g_smWeaponNameID.SetValue("weapon_pistol", ID_PISTOL);
	g_smWeaponNameID.SetValue("weapon_smg", ID_SMG);
	g_smWeaponNameID.SetValue("weapon_pumpshotgun", ID_PUMPSHOTGUN);
	g_smWeaponNameID.SetValue("weapon_rifle", ID_RIFLE);
	g_smWeaponNameID.SetValue("weapon_autoshotgun", ID_AUTOSHOTGUN);
	g_smWeaponNameID.SetValue("weapon_hunting_rifle", ID_HUNTING_RIFLE);
	g_smWeaponNameID.SetValue("weapon_smg_silenced", ID_SMG_SILENCED);
	g_smWeaponNameID.SetValue("weapon_smg_mp5", ID_SMG_MP5);
	g_smWeaponNameID.SetValue("weapon_shotgun_chrome", ID_CHROMESHOTGUN);
	g_smWeaponNameID.SetValue("weapon_pistol_magnum", ID_MAGNUM);
	g_smWeaponNameID.SetValue("weapon_rifle_ak47", ID_AK47);
	g_smWeaponNameID.SetValue("weapon_rifle_desert", ID_RIFLE_DESERT);
	g_smWeaponNameID.SetValue("weapon_sniper_military", ID_SNIPER_MILITARY);
	g_smWeaponNameID.SetValue("weapon_grenade_launcher", ID_GRENADE);
	g_smWeaponNameID.SetValue("weapon_rifle_sg552", ID_SG552);
	g_smWeaponNameID.SetValue("weapon_rifle_m60", ID_M60);
	g_smWeaponNameID.SetValue("weapon_sniper_awp", ID_AWP);
	g_smWeaponNameID.SetValue("weapon_sniper_scout", ID_SCOUT);
	g_smWeaponNameID.SetValue("weapon_shotgun_spas", ID_SPASSHOTGUN);
	
	WeaponAmmoOffset[ID_NONE] = 0;
	WeaponAmmoOffset[ID_PISTOL] = 0;
	WeaponAmmoOffset[ID_DUAL_PISTOL] = 0;
	WeaponAmmoOffset[ID_SMG] = 5;
	WeaponAmmoOffset[ID_PUMPSHOTGUN] = 7;
	WeaponAmmoOffset[ID_RIFLE] = 3;
	WeaponAmmoOffset[ID_AUTOSHOTGUN] = 8;
	WeaponAmmoOffset[ID_HUNTING_RIFLE] = 9;
	WeaponAmmoOffset[ID_SMG_SILENCED] = 5;
	WeaponAmmoOffset[ID_SMG_MP5] = 5;
	WeaponAmmoOffset[ID_CHROMESHOTGUN] = 7;
	WeaponAmmoOffset[ID_MAGNUM] = 0;
	WeaponAmmoOffset[ID_AK47] = 3;
	WeaponAmmoOffset[ID_RIFLE_DESERT] = 3;
	WeaponAmmoOffset[ID_SNIPER_MILITARY] = 10;
	WeaponAmmoOffset[ID_GRENADE] = 17;
	WeaponAmmoOffset[ID_SG552] = 3;
	WeaponAmmoOffset[ID_M60] = 6;
	WeaponAmmoOffset[ID_AWP] = 10;
	WeaponAmmoOffset[ID_SCOUT] = 10;
	WeaponAmmoOffset[ID_SPASSHOTGUN] = 8;
}

WeaponID GetWeaponID(int weapon, const char[] weapon_name)
{
	WeaponID index = ID_NONE;

	if ( g_smWeaponNameID.GetValue(weapon_name, index) )
	{
		if(index == ID_PISTOL)
		{
			if( GetEntProp(weapon, Prop_Send, "m_isDualWielding") > 0) //dual pistol
			{
				return ID_DUAL_PISTOL;
			}

			return ID_PISTOL;
		}

		return index;
	}

	return index;
}

// int GetWeaponAmmo(int client, int offest)
// {
//     return GetEntData(client, ammoOffset+(offest*4));
// } 
public int GetWeaponAmmo(int client)
{
	if (!IsValidAliveSurvivor(client))
		return -1;
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"); //抓人類目前裝彈的武器
	if (weapon <= 0 || !IsValidEntity(weapon))
	{
		return -1;
	}
	int ammoOffset = FindSendPropInfo("CCSPlayer", "m_iAmmo");
	static char sWeaponName[32];
	GetEntityClassname(weapon, sWeaponName, sizeof(sWeaponName));
	WeaponID weaponid = GetWeaponID(weapon, sWeaponName);

	int offset = WeaponAmmoOffset[weaponid];
	return GetEntData(client, ammoOffset+(offset*4));
}

void SetWeaponAmmo(int client, int weapon, int ammo)
{
	int ammoOffset = FindSendPropInfo("CCSPlayer", "m_iAmmo");
	static char sWeaponName[32];
	GetEntityClassname(weapon, sWeaponName, sizeof(sWeaponName));
	WeaponID weaponid = GetWeaponID(weapon, sWeaponName);
	int offset = WeaponAmmoOffset[weaponid];
	SetEntData(client, ammoOffset+(offset*4), ammo);
}

//how to check clip when more then one people use the same weapon?
public int GetWeaponClip(int client)
{
	int clip = -1;
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"); //抓人類目前裝彈的武器
	if (weapon <= 0 || !IsValidEntity(weapon))
	{
		return -1;
	}
	if(HasEntProp(weapon, Prop_Send, "m_iClip1"))
	{
		clip =  GetEntProp(weapon, Prop_Send, "m_iClip1");
	}
	return clip;
}

public void SetWeaponClip(int weapon, int clip)
{
	if(HasEntProp(weapon, Prop_Send, "m_iClip1"))
	{
		SetEntProp(weapon, Prop_Send, "m_iClip1", clip);
	}
}

bool IsValidAliveSurvivor(int client) 
{
	if ( 1 <= client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client)) 
		return true;
	return false; 
}