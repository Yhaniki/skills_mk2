// 跨模組共用的全域狀態
//
// SourcePawn 的全域變數必須先宣告才能使用（函式可以前向引用），
// core/ 與 skills/ 之間互相使用的狀態集中在這裡，並且最早 include。
// 只在單一檔案用到的狀態，宣告在該檔案並加 static。
// 第 2 步改寫成技能框架後，這個檔案會拆掉，改成各模組私有 + 函式存取。

enum player_state { PLAYER_ALIVE = 2, PLAYER_INCAP = 1, PLAYER_DEAD = 0 }
enum skill_state { SKILL_CD = 2, SKILL_ACT = 1, SKILL_RDY = 0 }
enum skill_type { TYPE_NORMAL = 0, TYPE_PASSIVE = 1 }

// 玩家狀態（core/player.sp）
bool State_Connection[MAX_PLAYERS + 1];
bool State_Transition[MAX_PLAYERS + 1];
player_state State_Player[MAX_PLAYERS + 1];
bool Invulnerable[MAX_PLAYERS + 1];

// MP（core/mp.sp）
float Skill_MP[MAX_PLAYERS + 1];
bool State_Adrenaline_Boost[MAX_PLAYERS + 1];
Handle Skill_Adrenaline_Boost_Timer[MAX_PLAYERS + 1];

// 魔心護盾（skills/mana_shield.sp）
bool State_ManaShield[MAX_PLAYERS + 1];

// 每位玩家的技能狀態（core/skill_base.sp）
int Skill[MAX_PLAYERS + 1];
skill_state Skill_State[MAX_PLAYERS + 1];
float Skill_LastUseTime[MAX_PLAYERS + 1];
bool Skill_EX_Using[MAX_PLAYERS + 1];
Handle Skill_Notify_Timer[MAX_PLAYERS + 1];
Handle Skill_Duration_Timer[MAX_PLAYERS + 1];
Handle Skill_Cooldown_Timer[MAX_PLAYERS + 1];
int Skill_Notify_Ani_State[MAX_PLAYERS + 1];

// 技能註冊表（core/skill_base.sp）
skill_type Skill_Type[MAXSKILLS];
char Skill_Name[MAXSKILLS][MAXSKILLNAME];
float Skill_Cooldown[MAXSKILLS];
float Skill_Duration[MAXSKILLS];
float Skill_MPcost[MAXSKILLS];
int skill_num = 0;
int hiddenExplosionNum = 0;
