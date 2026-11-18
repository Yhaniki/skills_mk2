// 玩家與管理員指令：skill1 / skill2 / change_skill / drop / fix / sm_skills_fillmp

public Action Event_SkillStateTransition(int client, int args)
{
	char cmd[MAXCMD];
	GetCmdArg(0, cmd, MAXCMD);
	if (State_Transition[client] || (State_Player[client] == PLAYER_DEAD)) return Plugin_Handled;

	int skill_using = Skill[client];
	if (StrEqual(cmd, "skill1")) {
		switch (Skill_State[client]) {
			case SKILL_RDY: {
				if (MP_Decrease(client, Skill_MPcost[skill_using])) {
					Skill_StartTimer(skill_using, client);
					Skill_Trigger(client);
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
	else if(StrEqual(cmd, "skill2"))
	{
		if ((Skill_MP[client] >= Skill_MPcost[hiddenExplosionNum]) &&
			StrEqual(Skill_Name[Skill[client]], "Explosion 爆裂"))
		{
			if (MP_Decrease(client, Skill_MPcost[hiddenExplosionNum]))
			{
				Skill_EX_Using[client] = true;
				Skill_StartTimer(hiddenExplosionNum, client);
				Skill_Trigger(client);
			}
			else
			{
				PrintToChat(client, "魔力不足");
			}
		}
	}
	else if (StrEqual(cmd, "change_skill"))
	{
		if (Skill_State[client] != SKILL_ACT ||
			Skill_Type[skill_num] != TYPE_PASSIVE)
			Skill_Change_Menu(client);
		else
			PrintToChat(client, "技能施放中");
	}
	else if (StrEqual(cmd, "drop"))
	{
		DropActiveWeapon(client);
	}
	else if (StrEqual(cmd, "fix"))
	{
		PrintToChat(client, "Correction Mana Bar");
		Player_OnClientConnected(client);
	}
	if (Skill_Notify_Timer[client] != null &&
		Skill_Notify_Timer[client] != INVALID_HANDLE)
	{
		TriggerTimer(Skill_Notify_Timer[client], true);
	}
	return Plugin_Handled;
}

// sm_skills_fillmp — 將所有真人玩家魔力設為上限（插件只對非 Bot 初始化技能）
public Action Cmd_SkillsFillAllMP(int client, int args)
{
	int n = 0;
	for (int i = 1; i <= MAX_PLAYERS; i++)
	{
		if (!IsClientInGame(i))
			continue;
		if (!IsPlayer(i))
			continue;
		Skill_MP[i] = MP_MAX;
		n++;
	}

	if (!client)
		PrintToServer("[skills_mk2] Filled MP to max for %d human player(s).", n);
	else
		ReplyToCommand(client, "\x04[skills_mk2]\x01 已將 %d 名玩家的魔力補滿。", n);

	return Plugin_Handled;
}
