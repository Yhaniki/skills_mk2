// 技能的延遲步驟排程
//
// DataPack data = Skill_Schedule(skill, client, delay, step);
//   delay 秒後呼叫 step(client, data)。回傳的 DataPack 給技能寫入步驟需要的資料（例如瞄準座標），
//   step 收到時已經讀到這些資料的開頭。DataPack 由 SourceMod 自動釋放（CreateDataTimer）。
// - 玩家斷線（userid 對不上）或步驟已被取消時，step 不會被呼叫。
// - 施法者死亡、斷線、過關、換圖、回合重開時，框架用 Skill_CancelAllSteps 取消該玩家所有還沒觸發的步驟（PLAN 決定 #5）。
// - Skill_CancelSteps(client, skill) 只取消某個技能的步驟（隱藏版爆裂再次施放前取消上一次的爆炸）。
//
// 步驟資料不能放在技能檔的 static 陣列：切換技能會把冷卻重置成 2 秒，
// 同一位玩家可能有兩次施放的步驟同時在等（例如偷竊延遲 5.2 秒），共用陣列會互相覆蓋。

typedef SkillStep = function void (int client, DataPack data);

#define SKILL_MAX_STEPS 16

static Handle s_hStep[MAX_PLAYERS + 1][SKILL_MAX_STEPS];
static int    s_iStepSkill[MAX_PLAYERS + 1][SKILL_MAX_STEPS];
static int    s_iSerial[MAX_PLAYERS + 1][MAXSKILLS];

DataPack Skill_Schedule(int skill, int client, float delay, SkillStep step)
{
	int slot = -1;
	for (int i = 0; i < SKILL_MAX_STEPS; i++)
	{
		if (s_hStep[client][i] == null)
		{
			slot = i;
			break;
		}
	}
	if (slot == -1)
		LogError("[skills_mk2] client %d 同時等待的延遲步驟超過 %d 個，這個步驟無法取消", client, SKILL_MAX_STEPS);

	DataPack data;
	Handle timer = CreateDataTimer(delay, Timer_SkillStep, data);
	data.WriteCell(client);
	data.WriteCell(slot);
	data.WriteCell(GetClientUserId(client));
	data.WriteCell(skill);
	data.WriteCell(s_iSerial[client][skill]);
	data.WriteFunction(step);
	if (slot != -1)
	{
		s_hStep[client][slot] = timer;
		s_iStepSkill[client][slot] = skill;
	}
	return data;
}

void Skill_CancelSteps(int client, int skill)
{
	s_iSerial[client][skill]++;
	for (int i = 0; i < SKILL_MAX_STEPS; i++)
	{
		if (s_hStep[client][i] != null && s_iStepSkill[client][i] == skill)
			delete s_hStep[client][i];
	}
}

void Skill_CancelAllSteps(int client)
{
	for (int skill = 0; skill < MAXSKILLS; skill++)
		s_iSerial[client][skill]++;
	for (int i = 0; i < SKILL_MAX_STEPS; i++)
	{
		if (s_hStep[client][i] != null)
			delete s_hStep[client][i];
	}
}

static Action Timer_SkillStep(Handle timer, DataPack data)
{
	data.Reset();
	int client = data.ReadCell();
	int slot   = data.ReadCell();
	int userid = data.ReadCell();
	int skill  = data.ReadCell();
	int serial = data.ReadCell();
	Function step = data.ReadFunction();

	// 先依 slot 把自己從清單移除。不能靠 userid 找 slot：玩家斷線時會找不到，留下殭屍 handle（見 1549b88）
	if (slot != -1 && s_hStep[client][slot] == timer)
		s_hStep[client][slot] = null;

	if (GetClientOfUserId(userid) != client || s_iSerial[client][skill] != serial)
		return Plugin_Stop;

	Call_StartFunction(null, step);
	Call_PushCell(client);
	Call_PushCell(data);
	Call_Finish();
	return Plugin_Stop;
}
