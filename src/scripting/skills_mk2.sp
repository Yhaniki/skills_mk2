#define SKILL_DEBUG                     (false)
#define USING_EXPLOSION_EX              (true)
#define GAMEDATA_MELEE                  ("l4d2_melee_range")
#define TURN_UNDEAD_DIST                (1000.0)
#define EXPLOSION_DIST                  (300.0)
#define MAX_WEAPONS                     (12)
#define ALL_WEAPONS                     (47)
#define WEAPON_TYPE_NUM                 (5)
#define MP_INC_PERSEC                   (0.5)
#define MP_BAR_SIZE                     (25.0)
#define MP_MAX                          (100.0)
#define MAX_STEAL_AMMO                  (350)
#define MIN_STEAL_AMMO                  (50)
#define ITEMNAME                        (64)
#define ITEMNUM                         (64)
#define MAXCMD                          (64)
#define MAXSKILLNAME                    (64)
#define MAXSKILLS                       (64)
#define MAXENTITIES                     (4096)
#define PANIC_SEC                       (120.0)
#define PARTICLE_EXPLOSION              ("Skill_Explosion")
#define PARTICLE_EAGLEEYE               ("Skill_EagleEye")
#define PARTICLE_TURNUNDEAD             ("Skill_Turn_Undead")
#define PARTICLE_FX_AFTER_EXPLOSION     ("fx_after_explosion")
#define PARTICLE_FX_EXPLOSION_RING      ("fx_explosion_ring")
#define PARTICLE_EX_GLOW                ("b_glow_2")
#define PARTICLE_EX_LIGHT               ("fire_glow_01")
//#define PARTICLE_ELEC                  ("electrical_arc_01_parent")
//#define PARTICLE_WARP                  ("electrical_arc_01_system")

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <left4dhooks>
#include "resourcemanager.sp"
// #include "damage.sp"
#include "l4d_dissolve_infected.sp"

enum player_state { PLAYER_ALIVE = 2, PLAYER_INCAP = 1, PLAYER_DEAD = 0 }

new bool:State_Connection[MAXPLAYERS + 1];
new bool:State_Transition[MAXPLAYERS + 1];
new player_state:State_Player[MAXPLAYERS + 1];

new bool:State_Adrenaline_Boost[MAXPLAYERS + 1];
new bool:State_ManaShield[MAXPLAYERS + 1];

enum skill_state { SKILL_CD = 2, SKILL_ACT = 1, SKILL_RDY = 0 }

new Skill[MAXPLAYERS + 1];
new skill_state:Skill_State[MAXPLAYERS + 1];
new Float:Skill_LastUseTime[MAXPLAYERS + 1];
new Float:Skill_MP[MAXPLAYERS + 1];

new Handle:Skill_Notify_Timer[MAXPLAYERS + 1];
new Handle:Skill_Duration_Timer[MAXPLAYERS + 1];
new Handle:Skill_Cooldown_Timer[MAXPLAYERS + 1];
new Handle:Skill_Notify_Ani_Timer[MAXPLAYERS + 1];
new Skill_Notify_Ani_State[MAXPLAYERS + 1];

new Handle:Skill_MPrecover_Timer[MAXPLAYERS + 1];
new Handle:Skill_Adrenaline_Boost_Timer[MAXPLAYERS + 1];

new bool:State_Glow[MAXENTITIES];
new Handle:Glow_Timer[MAXENTITIES];
new bool:State_Freeze[MAXENTITIES];
new Handle:Freeze_Timer[MAXENTITIES];
bool Invulnerable[MAXENTITIES];
int Skill_Delay_Cnt[MAXENTITIES];
new Handle:Skill_Delay_Timer[MAXENTITIES];
new Slow_Ent;
new bool:State_Slow;
new Handle:Slow_Timer;
bool State_TurnUndead;
new Handle:TurnUndead_Timer;

enum skill_type { TYPE_NORMAL = 0, TYPE_PASSIVE = 1 }

new skill_type:Skill_Type[MAXSKILLS];

new String:Skill_Name[MAXSKILLS][MAXSKILLNAME];
new Timer:Timer_Skill_Start[MAXSKILLS];
new Timer:Timer_Skill_End[MAXSKILLS];
new Timer:Timer_Skill_Ready[MAXSKILLS];
new Float:Skill_Cooldown[MAXSKILLS];
new Float:Skill_Duration[MAXSKILLS];
new Float:Skill_MPcost[MAXSKILLS];
new skill_num = 0;
float explosion_ex_delay_secs = 25.0;
Handle g_hDetour;

public Plugin:MyInfo = {
	name = "Skills",
	author = "MKLUO",
	description = "",
	version = "",
	url = ""
}

static char g_sWeaponNames[ALL_WEAPONS][] = 
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

static char g_sWeaponTranslate[ALL_WEAPONS][] = 
{
	"自動霰彈槍",
	"榴彈發射器" ,
	"獵槍",
	"手槍" ,
	"麥格農手槍" ,
	"泵式霰彈槍" ,
	"M-16突擊步槍" ,
	"AK47" ,
	"SCAR戰術步槍" ,
	"M60機槍" ,
	"SG552步槍" ,
	"鉻管霰彈槍",
	"戰術霰彈槍" ,
	"烏茲衝鋒槍" ,
	"MP5衝鋒槍" ,
	"滅音衝鋒槍" ,
	"麥格農狙擊槍",
	"狙擊步槍" ,
	"斯泰爾斥侯步槍" ,

	"球棒",
	"板球棒",
	"鐵撬",
	"電吉他",
	"消防斧",
	"平底鍋",
	"高爾夫球棒",
	"武士刀",
	"砍刀",
	"警棍",
	"小刀",

	"電鋸",

	"腎上腺素",
	"電擊器",
	"急救包",
	"止痛藥",

	"煙火",
	"瓦斯桶",
	"氧氣瓶",
	"煤氣罐",

	"汽油彈",
	"土製炸彈",
	"膽汁罐",

	"彈藥",
	"高爆彈藥",
	"燃燒彈藥",

	"小矮人",
	"可樂"
};

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
ConVar g_hCvarMeleeRange, g_hCvarPanicForever;
int g_iStockRange;
MRESReturn TestMeleeSwingCollisionPre(int pThis, Handle hReturn)
{
	if( IsValidEntity(pThis) )
	{
		int owner = GetEntPropEnt(pThis, Prop_Send, "m_hOwnerEntity");
		if(StrEqual(Skill_Name[Skill[owner]], "Mana Shield 魔心護盾"))
			g_hCvarMeleeRange.SetInt(10);
		else
			g_hCvarMeleeRange.SetInt(g_iStockRange);
	}

	return MRES_Ignored;
}

MRESReturn TestMeleeSwingCollisionPost(int pThis, Handle hReturn)
{
	g_hCvarMeleeRange.SetInt(g_iStockRange);
	return MRES_Ignored;
}
Handle g_hSDKUnVomit;
public OnPluginStart() {
	PrintToServer("=============Plugin Start===============");
//------------------------------
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "gamedata/%s.txt", GAMEDATA_MELEE);
	if( FileExists(sPath) == false ) SetFailState("\n==========\nMissing required file: \"%s\".\nRead installation instructions again.\n==========", sPath);

	Handle hGameData = LoadGameConfigFile(GAMEDATA_MELEE);
	if( hGameData == null ) SetFailState("Failed to load \"%s.txt\" gamedata.", GAMEDATA_MELEE);

	g_hDetour = DHookCreateFromConf(hGameData, "CTerrorMeleeWeapon::TestMeleeSwingCollision");
	delete hGameData;

	GameData hGameData2 = new GameData("l4d_unvomit");
	if( hGameData2 == null ) SetFailState("Failed to load gamedata: l4d_unvomit.txt");
	StartPrepSDKCall(SDKCall_Player);
	if( PrepSDKCall_SetFromConf(hGameData2, SDKConf_Signature, "CTerrorPlayer::OnITExpired") == false ) SetFailState("Failed to find signature: CTerrorPlayer::OnITExpired");
	g_hSDKUnVomit = EndPrepSDKCall();
	if( g_hSDKUnVomit == null ) SetFailState("Failed to create SDKCall: CTerrorPlayer::OnITExpired");

	delete hGameData2;


	if( !g_hDetour )
		SetFailState("Failed to find \"CTerrorMeleeWeapon::GetPrimaryAttackActivity\" signature.");

	if( !DHookEnableDetour(g_hDetour, false, TestMeleeSwingCollisionPre) )
		SetFailState("Failed to detour pre \"CTerrorMeleeWeapon::TestMeleeSwingCollision\".");

	if( !DHookEnableDetour(g_hDetour, true, TestMeleeSwingCollisionPost) )
		SetFailState("Failed to detour post \"CTerrorMeleeWeapon::TestMeleeSwingCollision\".");

	g_hCvarMeleeRange = FindConVar("melee_range");
	g_hCvarPanicForever = FindConVar("director_panic_forever");
	g_hCvarPanicForever.SetBool(false, false, false);
	g_iStockRange = g_hCvarMeleeRange.IntValue;
	if (State_TurnUndead && TurnUndead_Timer != null)
	{
		KillTimer(TurnUndead_Timer);
	}
	State_TurnUndead = false;
	State_Slow = false;
	for(int i=0; i<MAXENTITIES; i++)
	{
		State_Glow[i]=false;
		State_Freeze[i]=false;
		Invulnerable[i]=false;
		Skill_Delay_Cnt[i] = 0;
		Skill_Delay_Timer[i] = INVALID_HANDLE;
	}
//------------------------------
	//Setup_Materials();
	RegisterSkill("Explosion 爆裂" ,Timer_Skill_Explosion_Start, Timer_Skill_Null_End, Timer_Skill_Null_Ready, 1.0, 2.0, 30.0);
	RegisterSkill("Mana Shield 魔心護盾" ,Timer_Skill_ManaShield_Start, Timer_Skill_ManaShield_End, Timer_Skill_Null_Ready, 0.0, -1.0, 0.0);
	RegisterSkill("Eagle Eye 鷹眼" ,Timer_Skill_EagleEye_Start, Timer_Skill_Null_End, Timer_Skill_Null_Ready, 5.0, 2.0, 40.0);
	RegisterSkill("Steal 偷竊" ,Timer_Skill_Steal_Start, Timer_Skill_Null_End, Timer_Skill_Null_Ready, 7.0, 2.0, 20.0);// Float:skill_duration, Float:skill_cooldown, Float:skill_mpcost
	RegisterSkill("Sacred Turn Undead 淨化" , Timer_Skill_TurnUndead_Start, Timer_Skill_Null_End, Timer_Skill_Null_Ready, 3.5, 2.0, 50.0);
	RegisterSkill("爆裂ex" , Timer_Skill_EX_Start, Timer_Skill_EX_End, Timer_Skill_Null_Ready, explosion_ex_delay_secs, 2.0, 1.0);
	//RegisterSkill("Sixth Sense 第六感" ,Timer_Skill_EagleEye_Start, Timer_Skill_EagleEye_End, Timer_Skill_Null_Ready, 10.0, 60.0, 80.0);

	//Function: OnClientConnected
	HookEvent("player_disconnect",		Event_StateTransition);
	HookEvent("player_spawn",				Event_StateTransition);
	HookEvent("player_death",				Event_StateTransition);
	HookEvent("player_incapacitated",	Event_StateTransition);
	HookEvent("revive_success",			Event_StateTransition);
	HookEvent("map_transition",			Event_StateTransition);
	HookEvent("player_transitioned",		Event_StateTransition);

	HookEvent("player_death",				Event_MPleech);
	
	HookEvent("heal_success",				Event_MPGain);
	HookEvent("adrenaline_used",			Event_MPGain);
	HookEvent("pills_used",					Event_MPGain);

	HookEvent("player_hurt", 				Event_DmgReducedByManaShield);
	
	HookEvent("player_death", 				Event_DeathUnglow);
	
	RegConsoleCmd("skill1",					Event_SkillStateTransition);
	RegConsoleCmd("change_skill",			Event_SkillStateTransition);
	RegConsoleCmd("drop",					Event_SkillStateTransition);
	RegConsoleCmd("fix",					Event_SkillStateTransition);
	//HookEvent("player_hurt", 			Event_DmgInflicted);
	//HookEvent("infected_hurt", 			Event_DmgInflicted);
	HookEvent("gameinstructor_nodraw", Event_NoDraw, EventHookMode_PostNoCopy);
	HookEvent("gameinstructor_draw", Event_Draw, EventHookMode_PostNoCopy);
	TurnUndeadInit();
	CheckPlayerConnections();
}

public CheckPlayerConnections() {
	for (new i = 1; i < MaxClients; i++) {
		if (IsClientInGame(i)) OnClientConnected(i);
	}
}

public OnMapStart() {
	Setup_Materials();
	TrunUndeadMapStart();
	if (State_TurnUndead && TurnUndead_Timer != null)
	{
		KillTimer(TurnUndead_Timer);
	}
}

public Setup_Materials() {
	PrintToServer("=============Material Setup=============");
	SetupMaterial("sound\\skills\\explosion.mp3");
	SetupSound("skills\\explosion.mp3", true);
	
	SetupMaterial("sound\\skills\\eagleeye.mp3");
	SetupSound("skills\\eagleeye.mp3", true);
	
	SetupMaterial("sound\\skills\\slomo.mp3");
	SetupSound("skills\\slomo.mp3", true);
	
	SetupMaterial("sound\\skills\\slomo_end.mp3");
	SetupSound("skills\\slomo_end.mp3", true);

	SetupMaterial("sound\\skills\\steal.mp3");
	SetupSound("skills\\steal.mp3", true);

	SetupMaterial("sound\\skills\\turn_undead.mp3");
	SetupSound("skills\\turn_undead.mp3", true);

	SetupMaterial("sound\\skills\\explosion_full.mp3");
	SetupSound("skills\\explosion_full.mp3", true);

	SetupMaterial("particles\\skill_fx.pcf");
	SetupMaterial("particles\\ex.pcf");

	PrecacheParticle(PARTICLE_EXPLOSION);
	PrecacheParticle(PARTICLE_EAGLEEYE);
	PrecacheParticle(PARTICLE_FX_AFTER_EXPLOSION);
	PrecacheParticle(PARTICLE_FX_EXPLOSION_RING);
	PrecacheParticle(PARTICLE_TURNUNDEAD);
	PrecacheParticle(PARTICLE_EX_GLOW);
	PrecacheParticle(PARTICLE_EX_LIGHT);

	PrintToServer("===========Material Setup End===========");
}

public SetupMaterial(const char[] file) {
	AddFileToDownloadsTable(file);
	PrecacheGeneric(file);
}

//===========================================================
//======================= Particles =========================
//===========================================================

public Action:PrecacheParticle(String:particlename[]) {
	new particle = CreateEntityByName("info_particle_system");
	if (IsValidEntity(particle))
	{
		PrintToServer("PAR: %s Precached", particlename);
		DispatchKeyValue(particle, "effect_name", particlename);
		DispatchKeyValue(particle, "targetname", "particle");
		DispatchSpawn(particle);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "start");
		CreateTimer(0.1, DeleteParticles, particle, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action:DeleteParticles(Handle:timer, any:particle) {
	if (IsValidEntity(particle)) {
		new String:classname[64];
		GetEdictClassname(particle, classname, sizeof(classname));
		if (StrEqual(classname, "info_particle_system", false)) {
			AcceptEntityInput(particle, "Kill");
			//PrintToChatAll("DEL PAR");
		}
	}
}

public Action:CreateParticle(String:particlename[], Float:time, Float:Pos[3]) {
	new particle = CreateEntityByName("info_particle_system");
	if (IsValidEntity(particle))
	{
		TeleportEntity(particle, Pos, NULL_VECTOR, NULL_VECTOR);
		DispatchKeyValue(particle, "scale", "");
		DispatchKeyValue(particle, "effect_name", particlename);
		DispatchKeyValue(particle, "targetname", "particle");
		DispatchSpawn(particle);
		ActivateEntity(particle);

		AcceptEntityInput(particle, "Enable");
		AcceptEntityInput(particle, "start");
		CreateTimer(time, DeleteParticles, particle);
	}
}
//===========================================================
//==================== State Transition =====================
//===========================================================

public OnClientConnected(client) {
	if (State_Connection[client]) Delete_Skill(client);
	if (!IsPlayer(client)) return;
	State_Connection[client] = true;
	State_Transition[client] = false;
	State_Player[client] = PLAYER_DEAD;
	if ((IsClientInGame(client) == true) &&
		(IsFakeClient(client) == false) &&
		(IsPlayerAlive(client) == true))
		State_Player[client] = PLAYER_ALIVE;
	State_Adrenaline_Boost[client] = false;
	State_ManaShield[client] = false;

	Init_Skill(client);
	PrintPlayerState("connect", client);
}

public void Event_Draw(Event event, const char[] name, bool dontBroadcast)
{
	for (new i = 1; i < MaxClients; i++) {
		State_Transition[i] = false;
	}
}

public void Event_NoDraw(Event event, const char[] name, bool dontBroadcast)
{
	for (new i = 1; i < MaxClients; i++) {
		State_Transition[i] = true;
	}
}

public Event_StateTransition(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = 0;

	if (StrEqual(name, "player_disconnect") ||
		StrEqual(name, "player_spawn") ||
		StrEqual(name, "player_death") ||
		StrEqual(name, "player_incapacitated") ||
		StrEqual(name, "player_transitioned"))
	{
		client = GetClientOfUserId(GetEventInt(event, "userid"));
	}
	else if (StrEqual(name, "revive_success"))
	{
		client = GetClientOfUserId(GetEventInt(event, "subject"));
	}

	if (!IsPlayer(client)) return;
	
	if (StrEqual(name, "player_disconnect")) {
		State_Connection[client] = false;
		State_Player[client] = PLAYER_DEAD;
		Delete_Skill(client);
	} else if (StrEqual(name, "map_transition")) {
		State_Transition[client] = true;
		Interrupt_Skill(client);
		// for (new i = 0; i < MAXPLAYERS + 1; i++) {
		// 	State_Transition[i] = true;
		// 	Interrupt_Skill(client);
		// }
	} else if (StrEqual(name, "player_transitioned")) {
		State_Transition[client] = false;
		Setup_Materials();
	} else if (StrEqual(name, "player_spawn") || StrEqual(name, "revive_success")) {
		State_Player[client] = PLAYER_ALIVE;
	} else if (StrEqual(name, "player_incapacitated")) {
		State_Player[client] = PLAYER_INCAP; 
	} else if (StrEqual(name, "player_death")) {
		State_Player[client] = PLAYER_DEAD;
		Interrupt_Skill(client);
	}
	
	//if (!StrEqual(name, "player_disconnect")) TriggerTimer(Skill_Notify_Timer[client], true);
	PrintPlayerState(name, client);
}

//===========================================================
//====================== Skill System =======================
//===========================================================

public Init_Skill(client) {
	if(Skill_Notify_Timer[client]!=null)
		delete Skill_Notify_Timer[client];
	if(Skill_Notify_Ani_Timer[client]!=null)
		delete Skill_Notify_Ani_Timer[client];
	if(Skill_MPrecover_Timer[client]!=null)
		delete Skill_MPrecover_Timer[client];
	Skill_Notify_Timer[client] = CreateTimer(0.5, Skill_Notify, client, TIMER_REPEAT);
	Skill_Notify_Ani_State[client] = 0;
	Skill_Notify_Ani_Timer[client] = CreateTimer(0.5, Skill_Notify_Ani, client, TIMER_REPEAT);
	Skill_MPrecover_Timer[client] = CreateTimer(1.0, Skill_MPrecover, client, TIMER_REPEAT);
	// PrintToChatAll("Timer for %N created!", client);
	if(Skill[client]<0||Skill[client]>skill_num-1)
		Skill[client] = 0;
	Skill_MP[client] = 50.0;
	// Skill_Trigger(client);
}

public Delete_Skill(client) {
	if(Skill_Notify_Timer[client]!=null)
		delete Skill_Notify_Timer[client];
	if(Skill_Notify_Ani_Timer[client]!=null)
		delete Skill_Notify_Ani_Timer[client];
	if(Skill_MPrecover_Timer[client]!=null)
		delete Skill_MPrecover_Timer[client];

	// if(Skill_Cooldown_Timer[client]!=null)
	// 	delete Skill_Cooldown_Timer[client];
	// if(Skill_Duration_Timer[client]!=null)
	// 	delete Skill_Duration_Timer[client];
	Interrupt_Skill(client);
}

public Skill_Trigger(client) {
	new skill_using = Skill[client];
	if(Skill_Delay_Cnt[client]>1)
	{
		PrintToChatAll("cnt %d",Skill_Delay_Cnt[client]);
		skill_using = skill_num-1;
		Skill_Delay_Cnt[client]=0;
	}
	switch (Skill_Type[skill_using])
	{
		case TYPE_NORMAL:
		{
			Skill_State[client] = SKILL_ACT;
			Skill_LastUseTime[client] = GetGameTime();

			Skill_Cooldown_Timer[client] = CreateTimer(Skill_Cooldown[skill_using] + Skill_Duration[skill_using], Timer_Skill_Ready[skill_using], client);
			Skill_Duration_Timer[client] = CreateTimer(Skill_Duration[skill_using], Timer: Timer_Skill_End[skill_using], client);
		}
		case TYPE_PASSIVE:
		{
			Skill_State[client] = SKILL_ACT;
			CreateTimer(0.0, Timer: Timer_Skill_Start[skill_using], client);
		}
	}

	TriggerTimer(Skill_Notify_Timer[client], true);
}

public int Skill_Change_Menu_Handler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select)
	{
		Skill_Change(param1, param2);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

public Skill_Change_Menu(client) {
	Menu menu = new Menu(Skill_Change_Menu_Handler);
	menu.SetTitle("Choose a Skill...");
	for (new i = 0; i < skill_num-1; ++i) {//TODO: hidden explosion full option
		new String:skill_msg[MAXCMD] = "";
		Format(skill_msg, MAXCMD, "  %s", Skill_Name[i]);
		menu.AddItem("", skill_msg);
	}
	menu.ExitButton = false;
	menu.Display(client, 20);
}

public Skill_Change(client, skill) {
	SetEntProp(client, Prop_Send, "m_glowColorOverride", 0);
	SetEntProp(client, Prop_Send, "m_iGlowType", 0);
	new skill_using = Skill[client];
	
	if (skill == skill_using) return;
	
	switch (Skill_State[client]) {
		case SKILL_RDY: {
		}
		case SKILL_ACT: {
			if (Skill_Type[skill_using] == TYPE_NORMAL) {
				TriggerTimer(Skill_Duration_Timer[client]);
				TriggerTimer(Skill_Cooldown_Timer[client]);
			}
		}
		case SKILL_CD: {
			TriggerTimer(Skill_Cooldown_Timer[client]);
		}
	}
	
	switch (Skill_Type[skill_using]) {
		case TYPE_NORMAL: {
		}
		case TYPE_PASSIVE: {
			CreateTimer(0.0, Timer:Timer_Skill_End[skill_using], client);
		}
	}

	Skill[client] = skill;
	skill_using = Skill[client];

	switch (Skill_Type[skill_using]) {
		case TYPE_NORMAL: {
			Skill_State[client] = SKILL_CD;
			Skill_LastUseTime[client] = GetGameTime() - Skill_Duration[skill_using];
			Skill_Cooldown_Timer[client] = CreateTimer(Skill_Cooldown[skill_using], Timer:Timer_Skill_Ready[skill_using], client);
		}
		case TYPE_PASSIVE: {
			Skill_State[client] = SKILL_ACT;
			CreateTimer(0.0, Timer:Timer_Skill_Start[skill_using], client);
		}
	}
	TriggerTimer(Skill_Notify_Timer[client], true);
}

public Interrupt_Skill(client) {
	//Delete timers
	new skill_using = Skill[client];
	if (Skill_Type[skill_using]==TYPE_NORMAL)
	{
		if ((Skill_State[client] == SKILL_CD) || (Skill_State[client] == SKILL_ACT)) TriggerTimer(Skill_Cooldown_Timer[client]);
		if (Skill_State[client] == SKILL_ACT) TriggerTimer(Skill_Duration_Timer[client]);
	}
	if (State_Adrenaline_Boost[client]) TriggerTimer(Skill_Adrenaline_Boost_Timer[client]);
	
	Skill_State[client] = SKILL_RDY;
}

public bool CheckExplosion(int client)
{
	bool result = false;
#if USING_EXPLOSION_EX
	if ((Skill_MP[client] >= 99.0||Skill_Delay_Cnt[client]>=1) &&
		StrEqual(Skill_Name[Skill[client]], "Explosion 爆裂"))
	{
		result = true;
		Skill_Delay_Cnt[client]++;
	}
	PrintToChatAll("Skill_MP[client] %f\n",Skill_MP[client]);
	PrintToChatAll("result %d\n",result);
#endif
	return result;
}

public Action:Explosion_Trigger(Handle:timer, int client)
{
	int skill_using = Skill[client];
	Skill_Delay_Cnt[client]=0;
	CreateTimer(0.0, Timer:Timer_Skill_Start[skill_using], client);
	Skill_Trigger(client);
	return Plugin_Stop;
}

public Action:Event_SkillStateTransition(client, args) {
	new String:cmd[MAXCMD];
	GetCmdArg(0, cmd, MAXCMD);
	if (State_Transition[client] || (State_Player[client] == PLAYER_DEAD)) return Plugin_Handled;

	new skill_using = Skill[client];
	if (StrEqual(cmd, "skill1")) {
		switch (Skill_State[client]) {
			case SKILL_RDY: {
				CheckExplosion(client);
				if (MP_Decrease(client, Skill_MPcost[skill_using])) {
#if USING_EXPLOSION_EX
					if (Skill_Delay_Cnt[client] == 1)
					{
						Skill_Delay_Timer[client] = CreateTimer(0.5, Explosion_Trigger, client);
					}
					else if (Skill_Delay_Cnt[client] > 1)
					{
						if (Skill_Delay_Timer[client] != null &&
							Skill_Delay_Timer[client] != INVALID_HANDLE)
						{
							KillTimer(Skill_Delay_Timer[client]);
						}
						Skill_MP[client]=0.0;
						CreateTimer(0.0, Timer:Timer_Skill_Start[skill_num - 1], client);
						Skill_Trigger(client);
					}
					else
#endif
					{
						Skill_Delay_Cnt[client]=0;
						CreateTimer(0.0, Timer:Timer_Skill_Start[skill_using], client);
						Skill_Trigger(client);
					}
				} else {
					PrintToChat(client, "魔力不足");
				}
			}
			case SKILL_ACT: {
				PrintToChat(client, "技能施放中");
			}
			case SKILL_CD: {
				PrintToChat(client, "技能冷卻中");
			}
		}
	}
	else if (StrEqual(cmd, "change_skill"))
	{
		Skill_Change_Menu(client);
	}
	else if (StrEqual(cmd, "drop"))
	{
		// int weapon = GetNowWeapon(client);
		int activeweapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (activeweapon > 0)
				SDKHooks_DropWeapon(client, activeweapon, NULL_VECTOR, NULL_VECTOR);
	}
	else if (StrEqual(cmd, "fix"))
	{
		PrintToChat(client, "Correction Mana Bar");
		OnClientConnected(client);
	}

	TriggerTimer(Skill_Notify_Timer[client], true);
	return Plugin_Handled;
}

public Action:Skill_Notify(Handle:timer, any:client) {
	if (State_Transition[client] || (State_Player[client] == PLAYER_DEAD) || !IsClientInGame(client) || !IsPlayer(client)) return;
	
	new String:str[MAXCMD] = "";
	new skill_using = Skill[client];
	switch (Skill_State[client]) {
		case SKILL_RDY: {
			if (Skill_MP[client] < Skill_MPcost[skill_using]) {
				Format(str, MAXCMD, "%s", Skill_Name[Skill[client]]);
			} else {
				switch (Skill_Notify_Ani_State[client]) {
					case 0: {
						Format(str, MAXCMD, ">    %s    <", Skill_Name[Skill[client]]);
					}
					case 1: {
						Format(str, MAXCMD, " >   %s   < ", Skill_Name[Skill[client]]);
					}
					case 2: {
						Format(str, MAXCMD, " >   %s   < ", Skill_Name[Skill[client]]);
					}
				}
			}
		}
		case SKILL_ACT: {
			Format(str, MAXCMD, " -  %s  - ", Skill_Name[skill_using]);
		}
		case SKILL_CD: {
			Format(str, MAXCMD, "%s", Skill_Name[skill_using],  RoundToCeil(Skill_Cooldown[skill_using] + Skill_Duration[skill_using] - (GetGameTime() - Skill_LastUseTime[client])));
		}
	}
	Skill_Notify_MPbar(str, client);
}

public Skill_Notify_MPbar(const String:str[], client) {
	new String:bar[MAXCMD] = "";
	new String:dot[MAXCMD] = "";
	float resolution = MP_BAR_SIZE/MP_MAX;
	new bar_amount = RoundToFloor(Skill_MP[client] * resolution);
	for (new i = 0; i < bar_amount; i++) {
		if (State_Adrenaline_Boost[client]) {
			Format(dot, MAXCMD, "%s/", dot);
		} else {
			Format(bar, MAXCMD, "%s|", bar);
		}
	}
	if (State_ManaShield[client]) {
		Format(dot, MAXCMD, "%s) ", dot);
	}
	for (new i = 0; i < MP_BAR_SIZE - bar_amount; i++) {
		if (State_ManaShield[client]) {
			Format(dot, MAXCMD, "%s ", dot);
		} else {
			Format(dot, MAXCMD, "%s ", dot);
		}
	}

	PrintHintText(client, "%s\n[%s%s] MP %d", str, bar, dot, RoundToFloor(Skill_MP[client]));
}


public Action:Skill_Notify_Ani(Handle:timer, any:client) {
	Skill_Notify_Ani_State[client]++;
	if (Skill_Notify_Ani_State[client] > 2) Skill_Notify_Ani_State[client] = 0;
	TriggerTimer(Skill_Notify_Timer[client], true);
}

//===========================================================
//======================== MP System ========================
//===========================================================

public bool:MP_Decrease(client, Float:mp) {
if (Skill_MP[client] < mp) {
		return false;
	} else {
#if (!SKILL_DEBUG)
		Skill_MP[client] -= mp;
#endif
		return true;
	}
}

public MP_Increase(client, Float:mp) {
	if (State_Adrenaline_Boost[client]) {
		Skill_MP[client] += mp * 2.0;
	} else {
		Skill_MP[client] += mp;
	}
	if (Skill_MP[client] > MP_MAX) Skill_MP[client] = MP_MAX;
	if (Skill_Notify_Timer[client] != null &&
		Skill_Notify_Timer[client] != INVALID_HANDLE)
	{
		TriggerTimer(Skill_Notify_Timer[client], true);
	}
	else
	{
		OnClientConnected(client);
	}
}

public Action:Skill_MPrecover(Handle:timer, any:client) {
	MP_Increase(client, MP_INC_PERSEC);
}

public Action:Event_MPleech(Handle:event, const String:name[], bool:dontBroadcast) {
	//PrintToChatAll("Leeching?");
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new entity = GetEventInt(event, "entityid");
	if (IsSpecialInf(client)) {
		for (new i = 1; i <= MAXPLAYERS; i++) {
			if (State_Connection[i]) MP_Increase(i, 5.0);
		}
	} else if (IsInf(entity)) {
		for (new i = 1; i <= MAXPLAYERS; i++) {
			if (State_Connection[i]) MP_Increase(i, 0.5);
		}
	}
}

public Action:Event_MPGain(Handle:event, const String:name[], bool:dontBroadcast) {
	new client;
	if (StrEqual(name, "heal_success")) {
		client = GetClientOfUserId(GetEventInt(event, "subject"));
		if (State_Connection[client]) MP_Increase(client, 100.0);
	} else if (StrEqual(name, "pills_used")) {
		client = GetClientOfUserId(GetEventInt(event, "subject"));
		if (State_Connection[client]) MP_Increase(client, 50.0);
	} else if (StrEqual(name, "adrenaline_used")) {
		client = GetClientOfUserId(GetEventInt(event, "userid"));
		if (State_Connection[client]) { 
			MP_Increase(client, 25.0);
			Skill_Adrenaline_Boost(client);
		}
	}
}

public Skill_Adrenaline_Boost(client) {
	State_Adrenaline_Boost[client] = true;
	Skill_Adrenaline_Boost_Timer[client] = CreateTimer(20.0, Skill_Adrenaline_Boost_End, client);
}

public Action:Skill_Adrenaline_Boost_End(Handle:timer, any:client) {
	State_Adrenaline_Boost[client] = false;
}

//===========================================================
//========================= Skills ==========================
//===========================================================

//----------UTIL----------//

public RegisterSkill(String:skill_name[MAXSKILLNAME],
					Timer:timer_skill_start, 
					Timer:timer_skill_end, 
					Timer:timer_skill_ready, 
					Float:skill_duration, Float:skill_cooldown, Float:skill_mpcost)
{
	if (skill_num == MAXSKILLS) return;

	Skill_Name[skill_num] = skill_name;
	
	Timer_Skill_Start[skill_num] = timer_skill_start;
	Timer_Skill_End[skill_num] = timer_skill_end;
	Timer_Skill_Ready[skill_num] = timer_skill_ready;
	
	if (skill_cooldown <= 0.0) {
		Skill_Type[skill_num] = TYPE_PASSIVE;
		Skill_Duration[skill_num] = 0.0;
		Skill_Cooldown[skill_num] = 0.0;
		Skill_MPcost[skill_num] = 0.0;
	} else {
		Skill_Type[skill_num] = TYPE_NORMAL;
		Skill_Duration[skill_num] = skill_duration;
		Skill_Cooldown[skill_num] = skill_cooldown;
		Skill_MPcost[skill_num] = skill_mpcost;
	}
	
	skill_num++;
}

public Action:Timer_Skill_Null_End(Handle:timer, any:client) {
	Skill_State[client] = SKILL_CD;
	if(Skill_Notify_Timer[client]!=null)
		TriggerTimer(Skill_Notify_Timer[client]);
	else
		OnClientConnected(client);
	return Plugin_Stop;
}

public Action:Timer_Skill_Null_Ready(Handle:timer, any:client) {
	Skill_State[client] = SKILL_RDY;
	//PrepareAndEmitSoundToClient("skills\\explosion.mp3", .entity = client, .volume = 1.0);
	if(Skill_Notify_Timer[client]!=null)
		TriggerTimer(Skill_Notify_Timer[client]);
	else
		OnClientConnected(client);
	return Plugin_Handled;
}
//------------------------------------//
//------------隱藏版爆裂---------------//
public Action:Timer_Skill_EX_End(Handle:timer, any:client)
{
	if (IsAliveHumanPlayer(client) &&
		!IsIncapped(client))
	{
		int hp = GetEntProp(client, Prop_Data, "m_iHealth");
		DealDamage(client, hp, client, DMG_BURN);
	}
	Invulnerable[client]=false;
	return Plugin_Stop;
}
public Action:Timer_Skill_EX_Start(Handle:timer, any:client) {
	PrintToChatAll("\x04%N \x01エクスプロージョン!", client);
	new Float:Pos[3];
	GetClientAbsOrigin(client, Pos);
	CreateParticle(PARTICLE_EX_GLOW, explosion_ex_delay_secs, Pos);
	CreateParticle(PARTICLE_EX_LIGHT, explosion_ex_delay_secs, Pos);
	PrepareAndEmitSoundtoAll("skills\\explosion_full.mp3", .entity = client, .volume = 1.0);
	GlowForSecs(client, 255, 0, 0, explosion_ex_delay_secs);
	SlowForSecs(explosion_ex_delay_secs, client);
	FreezeForSecs(client, explosion_ex_delay_secs);
	Invulnerable[client]=true;
	return Plugin_Stop;
}
//------------------------------------//
//------------trun undead-------------//
public Action:Timer_UndeadRushEnd(Handle:timer) {
	State_TurnUndead = false;
	g_hCvarPanicForever.SetBool(false, false, false);
	PrintToChatAll("\x01屍潮結束");
}
StripAndExecuteClientCommand(client, const String:command[], const String:arguments[]) {
	new flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s", command, arguments);
	SetCommandFlags(command, flags);
}
public Action:Timer_UndeadRush(Handle:timer, DataPack:DP) {
	DP.Reset();
	new client = DP.ReadCell();

	g_hCvarPanicForever.SetBool(false, false, false);
	StripAndExecuteClientCommand(client, "z_spawn_old", "mob");
	static int director = INVALID_ENT_REFERENCE;

	if (director == INVALID_ENT_REFERENCE || EntRefToEntIndex(director) == INVALID_ENT_REFERENCE)
	{
		director = FindEntityByClassname(-1, "info_director");
		if (director != INVALID_ENT_REFERENCE)
		{
			director = EntIndexToEntRef(director);
		}
	}

	if (director != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(director, "ForcePanicEvent");
	}
	L4D_CTerrorPlayer_OnVomitedUpon(client, client);
	SDKCall(g_hSDKUnVomit, client);
	g_hCvarPanicForever.SetBool(true, false, false);
	if (State_TurnUndead &&
		TurnUndead_Timer != null &&
		TurnUndead_Timer != INVALID_HANDLE)
	{
		KillTimer(TurnUndead_Timer);
	}
	State_TurnUndead = true;
	TurnUndead_Timer = CreateTimer(PANIC_SEC, Timer:Timer_UndeadRushEnd);
	PrintToChatAll("\x04 %N \x01施放淨化引來屍潮！", client);
}
public Action:Timer_TurnUndeadAimDelay(Handle:timer, DataPack:DP) {
	DP.Reset();
	new client = DP.ReadCell();
	new Float:Pos[3];
	Pos[0] = DP.ReadCell();
	Pos[1] = DP.ReadCell();
	Pos[2] = DP.ReadCell();
	CreateParticle(PARTICLE_TURNUNDEAD, 1.0, Pos);
	for (new i = 1; i < MAXPLAYERS; i++) {
		if (IsAliveSpecialInf(i)) {
			new Float:distance = GetEntityPosDistance(i, Pos);
			if (distance <= TURN_UNDEAD_DIST) {
				// DealDamage(i, 500 * RoundToNearest(300.0 - distance) / 300, client, DMG_BURN);
				Turn_Undead(i, client);
			}
		}
	}
	
	new entity = -1;
	while ((entity = FindEntityByClassname(entity, "infected")) != INVALID_ENT_REFERENCE) {
		new health = GetEntProp(entity, Prop_Data, "m_iHealth");
		if (health > 0) {
			if (GetEntityPosDistance(entity, Pos) <= TURN_UNDEAD_DIST) {
				// DealDamage(entity, 1, client, DMG_BURN);
				Turn_Undead(entity, client);
			}
		}
	}
	while ((entity = FindEntityByClassname(entity, "witch")) != INVALID_ENT_REFERENCE) {
		new health = GetEntProp(entity, Prop_Data, "m_iHealth");
		if (health > 0) {
			if (GetEntityPosDistance(entity, Pos) <= TURN_UNDEAD_DIST) {
				// DealDamage(entity, 1, client, DMG_BURN);
				Turn_Undead(entity, client);
			}
		}
	}

	DataPack DP2 = new DataPack();
	DP2.WriteCell(client);
	CreateTimer(3.0, Timer:Timer_UndeadRush, DP2);
	// PropaneAtPos(Pos);
	
	return Plugin_Stop;
}
public TurnUndeadAim(client, Float:delay) {
	PrepareAndEmitSoundtoAll("skills\\turn_undead.mp3", .entity = client, .volume = 1.0);
	float Pos[3];
	GetAimOrigin(client, Pos, 0.1);
	Pos[2] += 10;
	// if (GetAimOrigin(client, Pos, 10.0) == 0) return;

	DataPack DP = new DataPack();
	DP.WriteCell(client);
	DP.WriteCell(Pos[0]);
	DP.WriteCell(Pos[1]);
	DP.WriteCell(Pos[2]);

	CreateTimer(delay, Timer:Timer_TurnUndeadAimDelay, DP);
}
public Action:Timer_Skill_TurnUndead_Start(Handle:timer, any:client) {
	GlowForSecs(client, 0, 0, 100, 3.5);
	TurnUndeadAim(client, 2.5);
	PrintToChatAll("\x04%N \x01淨化!", client);

	return Plugin_Stop;
}
//------------------------------------//
//--------------steal-----------------//
stock Weapon_GetPrimaryAmmoType(weapon)
{
	return GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType");
}
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
public Action:Timer_Skill_Steal_Start(Handle:timer, any:client) {
	// FakeClientCommand(client, "give katana");
	PrepareAndEmitSoundtoAll("skills\\steal.mp3", .entity = client, .volume = 1.0);
	PrintToChatAll("\x04%N \x01STEAL!", client);
	GlowForSecs(client, 0, 100, 0, 6.0);//rgb sec
	// Skill_Steal(client);
	new entityId = GetClientAimTarget(client, false);//return Entity
	DataPack DP = new DataPack();
	DP.WriteCell(client);
	DP.WriteCell(entityId);
	DP.WriteCell(CheckStealType(entityId));
	CreateTimer(5.2, Timer:Skill_Steal, DP);
	return Plugin_Stop;
}

public int ForceWeaponDropByType(client, type)
{
	int weapon = GetPlayerWeaponSlot(client, type);

	if (weapon > 0)
	{
		char item[MAXCMD];
		GetEdictClassname(weapon, item, MAXCMD);
		if(StrEqual(item, "weapon_melee")==false)
			RemoveEntity(weapon);
		else
			weapon = -1;
	}
	return weapon;
}

public int ForceWeaponDrop(client)
{
	new weapon = GetNowWeapon(client);
	char item[MAXCMD];
	if (weapon >0)
	{
		GetEdictClassname(weapon, item, MAXCMD);
		// PrintToChatAll("weapon %d", weapon);
		if(StrEqual(item, "weapon_melee")==false)
		{
			int activeweapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
			if(activeweapon>0)
			{
				if (StrEqual(item, "weapon_pistol")&&GetEntProp(activeweapon, Prop_Send, "m_isDualWielding"))
				{
					RemoveEntity(weapon);
					// SetItemToPlayer(client, "weapon_pistol");
					new wq = CreateEntityByName("weapon_pistol");
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
			weapon = -1;
	}
	return weapon;
}

public int GetNowWeapon(client)
{
	int weapon = -1;

	weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	// for (new i = 0; i < WEAPON_TYPE_NUM; i++)
	// {
	// 	weapon = GetPlayerWeaponSlot(client, i);
	// 	if (weapon > 0) break;
	// }
	return weapon;
}

public SetItemToPlayer(client, char[] item)
{
	// char weapon[MAXCMD] = "weapon_katana"; //TODO: get random item
	// new wq = CreateEntityByName(weapon);

	new wq = CreateEntityByName(item);
	if (wq > 0)
	{
		DispatchSpawn(wq);
		// EquipPlayerWeapon(client, wq);
		//----------------
		if (StrEqual(item, "weapon_pistol"))
		{
			int activeweapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
			if (activeweapon > 0 && GetEntProp(activeweapon, Prop_Send, "m_isDualWielding"))
			{
				GivePlayerItem(client, "weapon_pistol");
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
			GivePlayerAmmo(client, ammoAmount, Weapon_GetPrimaryAmmoType(weapon), true);
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

public Action:Skill_Steal(Handle:timer, DataPack:DP)
{
	DP.Reset();
	new client = DP.ReadCell();
	new entityId = DP.ReadCell();
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

				int weaponIdx = ForceWeaponDrop(entityId);

				// int weaponType = GetRandomInt(0, WEAPON_TYPE_NUM - 1);
				// int weaponIdx = ForceWeaponDropByType(entityId, weaponType);
				// PrintToChatAll("weaponType %d", weaponType);
				// PrintToChatAll("weaponIdx %d", weaponIdx);
				if (weaponIdx > 0)
				{
					GetEdictClassname(weaponIdx, item, MAXCMD);
					SetItemToPlayer(client, item);
					int idx = GetItemTranslateIdx(item);
					if (idx >= 0)
					{
						PrintToChatAll("\x04%N \x01從 \x04%N \x01身上偷了 \x04%s", client, entityId, g_sWeaponTranslate[idx]);
					}
					else
					{
						PrintToChatAll("\x04%N \x01從 \x04%N \x01身上偷了 \x04%s", client, entityId, g_sWeaponNames[idx]);
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
			// todo
			int weaponIdx = GetRandomInt(0, MAX_WEAPONS - 1);
			int idx = GetItemIdx(weaponIdx);
			if (idx >= 0)
			{
				PrintToChatAll("\x04%N \x01從 \x04殭屍 \x01身上偷了 \x04%s", client, g_sWeaponTranslate[idx]);
			}
			else
			{
				PrintToChatAll("\x04%N \x01從 \x04殭屍 \x01身上偷了 \x04%s", client, g_sWeapons[weaponIdx]);
			}
			// PrintToChatAll("\x04%N \x01從殭屍身上偷了 %s", client, g_sWeapons[weaponIdx]);
			SetItemToPlayer(client, g_sWeapons[weaponIdx]);
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

//------------------------------------//
//----------Explosion (爆裂)----------//
public Action:Timer_Skill_Explosion_Start(Handle:timer, any:client) {
	PrepareAndEmitSoundtoAll("skills\\explosion.mp3", .entity = client, .volume = 1.0);

	GlowForSecs(client, 100, 0, 0, 1.5);
	ExplodeAim(client, 1.5);

	//ExExplodeAim(client, 0.3);
	PrintToChatAll("\x04%N \x01EXPLOSION!", client);

	return Plugin_Stop;
}

//----------Mana Shield (魔心護盾)----------//
public Action:Timer_Skill_ManaShield_Start(Handle:timer, any:client) {
	// GlowForSecs(client, 100, 100, 0, 10.0);
	// int glowcolor = 100 | (100 << 8) | (0 << 16);
	// SetEntProp(client, Prop_Send, "m_glowColorOverride", glowcolor);
	// SetEntProp(client, Prop_Send, "m_iGlowType", 3);
	
	State_ManaShield[client] = true;
	//PrintToChatAll("%N - Mana Shield!", client);
	TriggerTimer(Skill_Notify_Timer[client]);
	
	return Plugin_Stop;
}

public Action:Timer_Skill_ManaShield_End(Handle:timer, any:client) {
	State_ManaShield[client] = false;
	
	Skill_State[client] = SKILL_CD;
	TriggerTimer(Skill_Notify_Timer[client]);
	return Plugin_Stop;
}

public Action:Event_DmgReducedByManaShield(Handle:event, const String:name[], bool:dontBroadcast) {
	int dmg_health = GetEventInt(event, "dmg_health");
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(Invulnerable[client]) return Plugin_Handled;
	if (!State_ManaShield[client]) return Plugin_Continue;
	
	if (IsAliveHumanPlayer(client)) {
		new hp = GetEntProp(client, Prop_Data, "m_iHealth");
		//new maxhp = GetEntProp(client, Prop_Data, "m_iMaxHealth");

		if (MP_Decrease(client, dmg_health * 4.0))
			hp += dmg_health;
		// if (hp > 100) 
		// 	hp = 100;
		SetEntProp(client, Prop_Data, "m_iHealth", hp);
	}
	if(Skill_Notify_Timer[client]!=null)
		TriggerTimer(Skill_Notify_Timer[client]);
	else
		OnClientConnected(client);
	return Plugin_Continue;
}

//----------Eagle Eye (鷹眼)----------//

public Action:Timer_Skill_EagleEye_Start(Handle:timer, any:client) {
	//PrepareAndEmitSoundtoAll("skills\\eagleeye.mp3", .entity = client, .volume = 1.0);
	
	GlowForSecs(client, 0, 100, 0, 10.0);
	EagleEye(client);
	PrintToChatAll("\x04%N \x01Eagle Eye!", client);
	
	return Plugin_Stop;
}

public EagleEye(client) {
	new Float:Range = 2000.0;
	new Float:Pos[3];
	GetAimOrigin(client, Pos, 0.1);
	
	Pos[2] += 10;
	CreateParticle(PARTICLE_EAGLEEYE, 1.0, Pos);
	
	SlowForSecs(6.0, client);
	
	new entity = -1;
	while ((entity = FindEntityByClassname(entity, "infected")) != INVALID_ENT_REFERENCE) {
		if (IsAliveInf(entity)) {
			if (GetEntityPosDistance(entity, Pos) <= Range) {
				GlowForSecs(entity, 200, 0, 0, 6.0);
				//FreezeForSecs(entity, 8.0);
			}
		}
	}
	for (new i = 1; i <= MAXPLAYERS; i++) {
		if (IsAliveSpecialInf(i)) {
			if (GetEntityPosDistance(i, Pos) <= Range) {
				//PrintToChatAll("Special infected found!");
				GlowForSecs(i, 150, 100, 0, 6.0);
			}
		}
	}
}

//===========================================================
//========================== DMG ============================
//===========================================================

public Action:Event_DmgInflicted(Handle:event, const String:name[], bool:dontBroadcast) {
	new Float:dmg;
	if (StrEqual(name, "player_hurt")) {
		dmg = GetEventFloat(event, "dmg_health");
	} else if (StrEqual(name, "infected_hurt")) {
		dmg = GetEventFloat(event, "amount");
	}
	
	if (dmg > 0.0) PrintToChatAll("DMG: %.1f", dmg);
	
	return Plugin_Continue;
}

//===========================================================
//========================== Glow ===========================
//===========================================================

public GlowForSecs(entity, r, g, b, Float:time) {
	if(!IsValidEntity(entity))return;
	if (State_Glow[entity]&&Glow_Timer[entity]!=null) KillTimer(Glow_Timer[entity]);
	State_Glow[entity] = true;

	// new glowcolor = r + g * 256 + b * 65536;
	int glowcolor = r | (g << 8) | (b << 16);
	SetEntProp(entity, Prop_Send, "m_glowColorOverride", glowcolor);
	SetEntProp(entity, Prop_Send, "m_iGlowType", 3);
	Glow_Timer[entity] = CreateTimer(time, Timer:Timer_Unglow, entity);
}

public Action:Timer_Unglow(Handle:timer, any:entity) {
	State_Glow[entity] = false;

	if (!IsValidEntity(entity)) return Plugin_Stop;
	// if (!(IsPlayer(entity) || IsInf(entity) || IsSpecialInf(entity))) return Plugin_Stop;
	if (!HasEntProp(entity, Prop_Send, "m_glowColorOverride")) return Plugin_Stop;
	SetEntProp(entity, Prop_Send, "m_glowColorOverride", 0);
	SetEntProp(entity, Prop_Send, "m_iGlowType", 0);

	return Plugin_Stop;
}

public Action:Event_DeathUnglow(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new entity = GetEventInt(event, "entityid");
	if (IsSpecialInf(client) || IsPlayer(client)) {
		if (State_Glow[client]) TriggerTimer(Glow_Timer[client]);
	} else if (IsInf(entity)) {
		if (State_Glow[entity]) TriggerTimer(Glow_Timer[entity]);
	}
}

//===========================================================
//========================= Freeze ==========================
//===========================================================

public FreezeForSecs(client, Float:time) {
	if (State_Freeze[client] &&
		Freeze_Timer[client] != null &&
		Freeze_Timer[client] != INVALID_HANDLE)
		KillTimer(Freeze_Timer[client]);

	State_Freeze[client] = true;
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 0.0);
	// float speed = GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
	// PrintToChatAll("FREEZE! %f\n",speed);

	Freeze_Timer[client] = CreateTimer(time, Timer:Timer_Unfreeze, client);
}

public Action:Timer_Unfreeze(Handle:timer, any:client) {
	State_Freeze[client] = false;

	if (!IsValidEntity(client)) return Plugin_Stop;
	if (!(IsPlayer(client) || IsInf(client) || IsSpecialInf(client))) return Plugin_Stop;
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
	//AcceptEntityInput(client, "");
	
	return Plugin_Stop;
}

//===========================================================
//====================== Slow Motion ========================
//===========================================================

public SlowForSecs(Float:time, client) {
	if (State_Slow&&Slow_Timer!=null)KillTimer(Slow_Timer);
	
	State_Slow = true;
	
	PrepareAndEmitSoundtoAll("skills\\slomo.mp3", .entity = client, .volume = 1.0);
	
	Slow_Ent = CreateEntityByName("func_timescale");
	DispatchKeyValue(Slow_Ent, "desiredTimescale", "0.6");
	DispatchKeyValue(Slow_Ent, "acceleration", "0.3");
	DispatchKeyValue(Slow_Ent, "minBlendRate", "0.1");
	DispatchKeyValue(Slow_Ent, "blendDeltaMultiplier", "1.0");
	DispatchSpawn(Slow_Ent);
	AcceptEntityInput(Slow_Ent, "Start");

	Slow_Timer = CreateTimer(time, Timer:Timer_Unslow, client);
}

public Action:Timer_Unslow(Handle:timer, any:client) {
	State_Slow = false;

	PrepareAndEmitSoundtoAll("skills\\slomo_end.mp3", .entity = client, .volume = 1.0);
	
	AcceptEntityInput(Slow_Ent, "Stop");

	return Plugin_Stop;
}

//===========================================================
//========================== Util ===========================
//===========================================================

public bool:IsPlayer(client) {
	if ((client < 1) || (client > MAXPLAYERS)) return false;
	if (client>0&&IsFakeClient(client)) return false;
	return true;
}

public PrintPlayerState(const String:name[], client) {	
	PrintToServer("========== EVENT: %s %N", name, client);
	PrintToServer("========== STATE: %d %d %d", State_Connection[client], State_Transition[client], State_Player[client]);
}

public bool:IsAliveInf(client) {
	if(!IsValidEntity(client))return false;
	new String:str[MAXCMD];
	GetEdictClassname(client, str, MAXCMD);
	return StrEqual(str, "infected");
}

public bool IsWitch(int entity)
{
	if(!IsValidEntity(entity))return false;
	new String:str[MAXCMD];
	GetEdictClassname(entity, str, MAXCMD);
	return StrEqual(str, "witch");
}

public bool:IsAliveSpecialInf(client) {
	if (client > MaxClients || client <= 0) 
	return false;
	return (IsClientInGame(client) == true)
	&& (IsPlayerAlive(client) == true)
	&& (GetClientTeam(client) == 3);
}

public bool:IsInf(client) {
	new String:str[MAXCMD];
	GetEdictClassname(client, str, MAXCMD);
	return StrEqual(str, "infected");
}

public bool:IsSpecialInf(client) {
	if (client > MaxClients || client <= 0) return false;
	return (IsClientInGame(client) == true)
	&& (GetClientTeam(client) == 3);
}

public bool:IsAliveHumanPlayer(client) {
	return (IsClientInGame(client) == true)
	&& (IsFakeClient(client) == false)
	&& (IsPlayerAlive(client) == true)
	&& (GetClientTeam(client) == 2);
}

public bool IsIncapped(int client)
{
	return view_as<bool>(GetEntProp(client, Prop_Send, "m_isIncapacitated"));
}

public GetAimOrigin(client, Float:hOrigin[3], Float:back_offset) {
	new Float:vAngles[3], Float:fOrigin[3];
	GetClientEyePosition(client, fOrigin);
	GetClientEyeAngles(client, vAngles);

	//PrintToChatAll("%f %f %f", vAngles[0], vAngles[1], vAngles[2]);
	
	new Handle:trace = TR_TraceRayFilterEx(fOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

	if(TR_DidHit(trace)) 
	{
		TR_GetEndPosition(hOrigin, trace);

		new Float:offset[3];
		
		offset[0] = hOrigin[0] - fOrigin[0];
		offset[1] = hOrigin[1] - fOrigin[1];
		offset[2] = hOrigin[2] - fOrigin[2];
		
		NormalizeVector(offset, offset);
		
		hOrigin[0] -= offset[0] * back_offset;
		hOrigin[1] -= offset[1] * back_offset;
		hOrigin[2] -= offset[2] * back_offset;

		CloseHandle(trace);
		return 1;
	}

	CloseHandle(trace);
	return 0;
}

public bool:TraceEntityFilterPlayer(entity, contentsMask) {
	if (entity > MaxClients) {
		return true;
	} else {
		return IsAliveSpecialInf(entity);
	}
}

public ExplodeAim(client, Float:delay) {
	new Float:Pos[3];
	if (GetAimOrigin(client, Pos, 10.0) == 0) return;

	//ExplodeAtPos(Pos);
	
	DataPack DP = new DataPack();
	DP.WriteCell(client);
	DP.WriteCell(Pos[0]);
	DP.WriteCell(Pos[1]);
	DP.WriteCell(Pos[2]);

	CreateParticle(PARTICLE_EXPLOSION, delay + 1.0, Pos);
	CreateTimer(delay, Timer:Timer_ExplodeAimDelay, DP);
}

public ExExplodeAim(client, Float:delay) {
	new Float:Pos[3];
	if (GetAimOrigin(client, Pos, 10.0) == 0) return;

	CreateParticle(PARTICLE_EXPLOSION, delay + 1.0, Pos);
	
	new stage = 5;
	
	new entity = -1;
	while ((entity = FindEntityByClassname(entity, "infected")) != INVALID_ENT_REFERENCE) {
		if (GetEntityPosDistance(entity, Pos) <= 1000.0) break;
	}
	
	DataPack DP = new DataPack();
	DP.WriteCell(client);
	DP.WriteCell(Pos[0]);
	DP.WriteCell(Pos[1]);
	DP.WriteCell(Pos[2]);
	DP.WriteCell(entity);
	DP.WriteCell(stage);

	CreateTimer(delay, Timer:Timer_ExExplodeAimDelay, DP);
}

int ComputeExploDmg(float dist)
{
	const int weight = 500;
	int dmg = RoundToNearest(weight * RoundToNearest(EXPLOSION_DIST - dist) / EXPLOSION_DIST);
	return dmg;
}

public Action:Timer_ExplodeAimDelay(Handle:timer, DataPack:DP) {
	DP.Reset();
	new client = DP.ReadCell();
	new Float:Pos[3];
	Pos[0] = DP.ReadCell();
	Pos[1] = DP.ReadCell();
	Pos[2] = DP.ReadCell();

	for (new i = 1; i < MAXPLAYERS; i++) {
		if (IsAliveSpecialInf(i)) {
			float distance = GetEntityPosDistance(i, Pos);
			if (distance <= EXPLOSION_DIST) {
				int dmg =  ComputeExploDmg(distance);
				DealDamage(i, dmg, client, DMG_BURN);
			}
		}
	}
	
	new entity = -1;
	while ((entity = FindEntityByClassname(entity, "infected")) != INVALID_ENT_REFERENCE) {
		new health = GetEntProp(entity, Prop_Data, "m_iHealth");
		if (health > 0) {
			if (GetEntityPosDistance(entity, Pos) <= EXPLOSION_DIST) {
				DealDamage(entity, 1, client, DMG_BURN);
			}
		}
	}
	
	PropaneAtPos(Pos);
	
	return Plugin_Stop;
}

public Action:Timer_ExExplodeAimDelay(Handle:timer, DataPack:DP) {
	new Float:chain_delay = 0.2;

	DP.Reset();
	new client = DP.ReadCell();
	new Float:Pos0[3];
	Pos0[0] = DP.ReadCell();
	Pos0[1] = DP.ReadCell();
	Pos0[2] = DP.ReadCell();
	new entity0 = DP.ReadCell();
	new stage = DP.ReadCell();
	
	if ((stage <= 0) || (entity0 == INVALID_ENT_REFERENCE)) return Plugin_Stop;
	
	new Float:Pos[3];
	GetEntPropVector(entity0, Prop_Send, "m_vecOrigin", Pos);
	
	for (new i = 1; i < MAXPLAYERS; i++) {
		if (IsAliveSpecialInf(i)) {
			new Float:distance = GetEntityPosDistance(i, Pos);
			if (distance <= EXPLOSION_DIST) {
				DealDamage(i, ComputeExploDmg(distance), client, DMG_BURN);
			}
		}
	}
	
	new entity = -1;
	while ((entity = FindEntityByClassname(entity, "infected")) != INVALID_ENT_REFERENCE) {
		new health = GetEntProp(entity, Prop_Data, "m_iHealth");
		if (health > 0) {
			if (GetEntityPosDistance(entity, Pos) <= EXPLOSION_DIST) {
				DealDamage(entity, 1, client, DMG_BURN);
			}
		}
	}
	
	//CreateParticle(PARTICLE_EXPLOSION, 1.0 + chain_delay, Pos);
	
	PropaneAtPos(Pos);
	
	while ((entity0 = FindEntityByClassname(entity0, "infected")) != INVALID_ENT_REFERENCE) {
		if (GetEntityPosDistance(entity0, Pos0) <= 1000.0) break;
	}
	
	DP = new DataPack();
	DP.WriteCell(client);
	DP.WriteCell(Pos0[0]);
	DP.WriteCell(Pos0[1]);
	DP.WriteCell(Pos0[2]);
	DP.WriteCell(entity0);
	DP.WriteCell(stage - 1);

	CreateTimer(chain_delay, Timer:Timer_ExExplodeAimDelay, DP);
	
	return Plugin_Stop;
}

public PropaneAtPos(Float:Pos[3]) {
	new prop = CreateEntityByName("prop_physics");
	DispatchKeyValue(prop, "model", "models/props_junk/propanecanister001a.mdl");
	DispatchSpawn(prop);
	TeleportEntity(prop, Pos, NULL_VECTOR, NULL_VECTOR);
	ActivateEntity(prop);
	AcceptEntityInput(prop, "break");
}

public Float:GetEntityEntityDistance(entity1, entity2) {
	new Float:Pos1[3];
	GetEntPropVector(entity1, Prop_Send, "m_vecOrigin", Pos1);
	new Float:Pos2[3];
	GetEntPropVector(entity2, Prop_Send, "m_vecOrigin", Pos2);
	return GetVectorDistance(Pos1, Pos2);
}

public Float:GetEntityPosDistance(entity, Float:pos[3]) {
	new Float:Pos1[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", Pos1);
	return GetVectorDistance(Pos1, pos);
}

public
Action L4D_OnGrabWithTongue(int victim, int attacker)
{
	if(Invulnerable[victim])
		return Plugin_Handled;
	else
		return Plugin_Continue;
}

public
Action L4D_OnPouncedOnSurvivor(int victim, int attacker)
{
	if(Invulnerable[victim])
		return Plugin_Handled;
	else
		return Plugin_Continue;
}

public
Action L4D2_OnJockeyRide(int victim, int attacker)
{
	if(Invulnerable[victim])
		return Plugin_Handled;
	else
		return Plugin_Continue;
}

public
Action L4D2_OnStartCarryingVictim(int victim, int attacker)
{
	if(Invulnerable[victim])
		return Plugin_Handled;
	else
		return Plugin_Continue;
}

public
Action L4D2_OnPummelVictim(int attacker, int victim)
{
	// from "left4dhooks_test.sp"
	if(Invulnerable[victim])
	{
		DataPack pack = new DataPack();
		RequestFrame(OnPummelTeleport, pack);
		pack.WriteCell(GetClientUserId(victim));
		pack.WriteCell(GetClientUserId(attacker));

		// To block the stumble animation, uncomment and use the following 2 lines:
		AnimHookEnable(victim, OnPummelOnAnimPre, INVALID_FUNCTION);
		CreateTimer(0.3, Timer_OnPummelResetAnim, GetClientUserId(victim));

		return Plugin_Handled;
	}
	else
		return Plugin_Continue;
}

// To fix getting stuck use this:
void OnPummelTeleport(DataPack pack)
{
	pack.Reset();
	int victim = pack.ReadCell();
	int attacker = pack.ReadCell();
	delete pack;

	victim = GetClientOfUserId(victim);
	if (!victim || !IsClientInGame(victim)) return;

	attacker = GetClientOfUserId(attacker);
	if (!attacker || !IsClientInGame(attacker)) return;

	SetVariantString("!activator");
	AcceptEntityInput(victim, "SetParent", attacker);
	TeleportEntity(victim, view_as<float>({50.0, 0.0, 0.0}), NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(victim, "ClearParent");
}

// To block the stumble animation use the next two functions:
Action OnPummelOnAnimPre(int client, int &anim)
{
	if(Invulnerable[client])
	{
		if (anim == L4D2_ACT_TERROR_SLAMMED_WALL || anim == L4D2_ACT_TERROR_SLAMMED_GROUND)
		{
			anim = L4D2_ACT_STAND;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

Action Timer_OnPummelResetAnim(Handle timer, int client)
{
	// Don't need client userID since 
	// it's not going to be validated just removed
	// if ((client = GetClientOfUserId(client)))
	AnimHookDisable(client, OnPummelOnAnimPre);

	return Plugin_Continue;
}