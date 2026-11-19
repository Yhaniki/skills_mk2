// 玩家與管理員指令：skill1 / skill2 / change_skill / fix / sm_skills_fillmp

public Action Event_SkillStateTransition(int client, int args)
{
	char cmd[MAXCMD];
	GetCmdArg(0, cmd, MAXCMD);
	if (State_Transition[client] || (State_Player[client] == PLAYER_DEAD) || Player_InCutscene(client)) return Plugin_Handled;

	if (StrEqual(cmd, "skill1"))
	{
		Skill_Cast(client);
	}
	else if (StrEqual(cmd, "skill2"))
	{
		Skill_CastAlt(client);
	}
	else if (StrEqual(cmd, "change_skill"))
	{
		Skill_OpenMenu(client);
	}
	else if (StrEqual(cmd, "fix"))
	{
		PrintToChat(client, "%t", "Chat_FixMP");
		Player_OnClientConnected(client);
	}
	Hud_Refresh(client, true);
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
		ReplyToCommand(client, "\x04[skills_mk2]\x01 %t", "Cmd_FillMP", n);

	return Plugin_Handled;
}
