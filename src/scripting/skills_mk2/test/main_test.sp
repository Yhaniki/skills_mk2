// skills_mk2 自動測試版入口
//
// 編譯（在 src/scripting/ 底下）：
//   spcomp skills_mk2/test/main_test.sp -o skills_mk2_test.smx
// 用法見 tools/servertest/servertest.py。這個版本只給自動測試用，不要放上正式伺服器。
//
// 跟正式版的差別只有下面三個替換，加上最後 include 的 test/harness.sp：
// - IsFakeClient 永遠回傳 false：技能系統原本會略過 bot，換掉之後 bot 也能施放技能
// - PrintHintText / PrintToChat / PrintToChatAll：照常送出，另外把文字記進測試 log
//
// 第三方 include 要先在這裡 include，替換才不會套用到它們（main.sp 再 include 時會被 include guard 略過）。

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <left4dhooks>
#include <l4d2_weapon_stocks>
#include <ammo>
#tryinclude <ResourceManager>
#undef REQUIRE_PLUGIN
#tryinclude <LMCCore>
#define REQUIRE_PLUGIN

#define SKILLS_TEST
#define IsFakeClient   Test_IsFakeClient
#define PrintHintText  Test_PrintHintText
#define PrintToChat    Test_PrintToChat
#define PrintToChatAll Test_PrintToChatAll

#include "../main.sp"

#undef IsFakeClient
#undef PrintHintText
#undef PrintToChat
#undef PrintToChatAll

#include "harness.sp"
