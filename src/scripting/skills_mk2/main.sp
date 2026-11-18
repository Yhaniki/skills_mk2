// skills_mk2 入口
//
// 編譯（在 src/scripting/ 底下）：
//   spcomp skills_mk2/main.sp -o ../plugins/skills_mk2.smx
//
// 這個檔案只負責：插件資訊、include 順序、所有 SourceMod / left4dhooks forward 的分派。
// 同一個 forward 在整個插件只能定義一次，所以統一寫在這裡，再呼叫各模組的函式。

// ---- 第三方 include：必須放在 newdecls 之前（部分仍是舊語法）----
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <left4dhooks>
#include <l4d2_weapon_stocks>
#include <ammo>
#tryinclude <ResourceManager>
//LMC
#undef REQUIRE_PLUGIN
#tryinclude <LMCCore>
#define REQUIRE_PLUGIN

#pragma semicolon 1
#pragma newdecls required

// ---- 模組：全域變數必須先宣告才能使用，順序不能任意調換 ----
// 函式可以前向引用；互相需要對方狀態的模組改用函式存取（例如 Hud_Refresh、MP_StopBoost）
#include "config.sp"
#include "util.sp"
#include "fx/particle.sp"
#include "fx/glow.sp"
#include "fx/timescale.sp"
#include "fx/screen.sp"
#include "fx/magic_circle.sp"
#include "fx/atmosphere.sp"
#include "lib/resourcemanager.sp"
#include "lib/weapons.sp"
#include "lib/dissolve.sp"
#include "core/player.sp"
#include "core/mp.sp"
#include "core/skill_base.sp"
#include "core/scheduler.sp"
#include "skills/explosion.sp"
#include "skills/mana_shield.sp"
#include "skills/eagle_eye.sp"
#include "skills/steal.sp"
#include "skills/turn_undead.sp"
#include "skills/explosion_ex.sp"
#include "core/hud.sp"
#include "core/commands.sp"

public Plugin myinfo = {
	name = "[KONOSUBA_SKILLS]",
	author = "MKLUO, Eithwa",
	description = "skills system of konosuba",
	version = PLUGIN_VERSION,
	url = "https://github.com/Yhaniki/skills_mk2"
};

//===========================================================
//====================== 插件生命週期 =======================
//===========================================================

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	return Dissolve_AskPluginLoad2(error, err_max);
}

public void OnLibraryAdded(const char[] sName)
{
	Dissolve_OnLibraryAdded(sName);
}

public void OnLibraryRemoved(const char[] sName)
{
	Dissolve_OnLibraryRemoved(sName);
}

public void OnPluginStart()
{
	PrintToServer("=============Plugin Start===============");
//------------------------------
	LoadTranslations("skills_mk2.phrases");
	ManaShield_InitMeleeDetour();

	State_Slow = false;
	for (int i = 0; i < MAXENTITIES; i++)
	{
		State_Glow[i] = false;
	}
	for (int i = 0; i < MAX_PLAYERS + 1; i++)
	{
		Invulnerable[i] = false;
		Skill_InitClient(i);
		g_iMagicCircleRef[i] = INVALID_ENT_REFERENCE;
		g_fMagicCircleYaw[i] = 0.0;
	}
	Weapons_Init();
//------------------------------
	// 註冊順序就是選單順序；玩家選的技能存的是編號，換圖、reload 後要對得上，所以不能任意調換
	int explosion = Explosion_Register();
	ManaShield_Register();
	EagleEye_Register();
	Steal_Register();
	TurnUndead_Register();
	ExplosionEx_Register(explosion);    // 爆裂的替代技能（skill2），不在選單裡

	// 同一事件有多個 hook 時依註冊順序呼叫，順序不能變
	// （player_death：Event_StateTransition → Event_MPleech → Event_DeathUnglow）
	HookEvent("player_disconnect",			Event_StateTransition);
	HookEvent("player_spawn",				Event_StateTransition);
	HookEvent("player_death",				Event_StateTransition);
	HookEvent("player_incapacitated",		Event_StateTransition);
	HookEvent("revive_success",				Event_StateTransition);
	HookEvent("map_transition",				Event_StateTransition);
	HookEvent("player_transitioned",		Event_StateTransition);
	HookEvent("player_afk",					Event_StateTransition, EventHookMode_Pre);
	HookEvent("player_death",				Event_MPleech);
	HookEvent("heal_success",				Event_MPGain);
	HookEvent("adrenaline_used",			Event_MPGain);
	HookEvent("pills_used",					Event_MPGain);
	// HookEvent("player_hurt", 				Event_DmgReducedByManaShield);
	HookEvent("player_death", 				Event_DeathUnglow);
	HookEvent("infected_death", 			Event_DeathUnglow);
	HookEvent("round_start",				Event_SkillsRoundStart, EventHookMode_PostNoCopy);

	RegConsoleCmd("skill1",					Event_SkillStateTransition);
	RegConsoleCmd("skill2",					Event_SkillStateTransition);
	RegConsoleCmd("change_skill",			Event_SkillStateTransition);
	RegConsoleCmd("drop",					Event_SkillStateTransition);
	RegConsoleCmd("fix",					Event_SkillStateTransition);

	// 管理員：瞬間將所有真人玩家魔力補滿（控制台或遊戲內均需 ADMFLAG_ROOT）
	RegAdminCmd("sm_skills_fillmp", Cmd_SkillsFillAllMP, ADMFLAG_ROOT, "[skills_mk2] Instant max MP for all human players.");

	HookEvent("gameinstructor_nodraw", Event_NoDraw, EventHookMode_PostNoCopy);
	HookEvent("gameinstructor_draw", Event_Draw, EventHookMode_PostNoCopy);
	Dissolve_Init();
	CheckPlayerConnections();

	// reload 時把上一次執行殘留的遊戲狀態全部清掉
	Skills_ReloadCleanup();
}

public void OnPluginEnd()
{
	Dissolve_OnPluginEnd();
	Skills_PluginEndCleanup();
	ManaShield_RestoreMeleeRange();
}

public void OnConfigsExecuted()
{
	Dissolve_OnConfigsExecuted();
}

public void OnMapStart()
{
	Skills_Precache();
	Dissolve_OnMapStart();
	CheckPlayerConnections();
	ResetMagicAtmosphere();
}

public void OnMapEnd()
{
	Dissolve_OnMapEnd();
	Skills_MapEndCleanup();
}

//===========================================================
//========================= 玩家 ============================
//===========================================================

public void OnClientConnected(int client)
{
	Player_OnClientConnected(client);
}

public void OnClientPostAdminCheck(int client)
{
	Player_OnClientPostAdminCheck(client);
}

public void OnClientDisconnect(int client)
{
	Player_OnClientDisconnect(client);
}

public void OnEntityDestroyed(int entity)
{
	Glow_OnEntityDestroyed(entity);
}

//===========================================================
//================= left4dhooks：無敵處理 ===================
//===========================================================

public Action L4D_OnGrabWithTongue(int victim, int attacker)
{
	return Invuln_Block(victim);
}

public Action L4D_OnPouncedOnSurvivor(int victim, int attacker)
{
	return Invuln_Block(victim);
}

public Action L4D2_OnJockeyRide(int victim, int attacker)
{
	return Invuln_Block(victim);
}

public Action L4D2_OnStartCarryingVictim(int victim, int attacker)
{
	return Invuln_Block(victim);
}

public Action L4D2_OnPummelVictim(int attacker, int victim)
{
	return Invuln_OnPummelVictim(attacker, victim);
}
