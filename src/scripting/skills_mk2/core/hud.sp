// HUD：技能提示文字與 MP 條

// 每 0.5 秒更新（TIMER_REPEAT，必須回傳 Plugin_Continue）
public Action Skill_Notify(Handle timer, any client)
{
	if (State_Transition[client] || (State_Player[client] == PLAYER_DEAD) || !IsClientInGame(client) || !IsPlayer(client)) return Plugin_Continue;

	char str[MAXCMD] = "";
	char state[MAXCMD] = "";
	char name[MAXCMD] = "";
	int skill_using = Skill[client];
	if(Skill_EX_Using[client])
	{
		skill_using = skill_num-1;
	}
	if (StrEqual(Skill_Name[Skill[client]], "Mana Shield 魔心護盾"))
	{
		if(!State_ManaShield[client])
			Skill_Trigger(client);
		else if(!State_Glow[client] && IsPlayerAlive(client))
		{
			// if(!IsValidEntity(client) || !HasEntProp(client, Prop_Send, "m_glowColorOverride"))return Plugin_Stop;
			State_Glow[client] = true;
			int glowcolor = 255 | (255 << 8) | (0 << 16);
			SetEntProp(client, Prop_Send, "m_glowColorOverride", glowcolor);
			SetEntProp(client, Prop_Send, "m_iGlowType", 3);
		}
	}
	else if (StrEqual(Skill_Name[Skill[client]], "Eagle Eye 鷹眼") &&
			 Skill_State[client] == SKILL_ACT)
	{
		DetectInfect(client);
	}
	if ((Skill_MP[client] >= Skill_MPcost[hiddenExplosionNum]) &&
		StrEqual(Skill_Name[Skill[client]], "Explosion 爆裂"))
	{
		Format(name, MAXCMD, "EXPLOSION ☆爆裂★");
	}
	else
	{
		Format(name, MAXCMD, Skill_Name[Skill[client]]);
	}
	switch (Skill_State[client]) {
		case SKILL_RDY: {
			if (Skill_MP[client] < Skill_MPcost[skill_using]) {
				Format(str, MAXCMD, "%s", Skill_Name[Skill[client]]);
			} else {
				switch (Skill_Notify_Ani_State[client]) {
					case 0: {
						Format(str, MAXCMD, ">    %s    <", name);
					}
					case 1: {
						Format(str, MAXCMD, " >   %s   < ", name);
					}
					case 2: {
						Format(str, MAXCMD, "  >  %s  <  ", name);
					}
				}
			}
			if(Skill_MP[client] >= Skill_MPcost[skill_using])
			{
				// Format(state, MAXCMD, "已準備");
				Format(state, MAXCMD, " ");
			}else
			{
				Format(state, MAXCMD, "魔力不足(%-.0fMP)",Skill_MPcost[skill_using]);
			}
		}
		case SKILL_ACT: {
			Format(str, MAXCMD, " -  %s  - ", Skill_Name[skill_using]);
			Format(state, MAXCMD, "施放中");
		}
		case SKILL_CD: {
			float time = (Skill_Cooldown[skill_using] + Skill_Duration[skill_using] - (GetGameTime() - Skill_LastUseTime[client]));
			Format(str, MAXCMD, "%s", Skill_Name[skill_using]);
			Format(state, MAXCMD, "冷卻中 (%-.2fs)", time);
		}
	}
	Skill_Notify_MPbar(str, state, client);
	return Plugin_Continue;
}

void Skill_Notify_MPbar(const char[] str, const char[] state, int client)
{
	char bar[MAXCMD] = "";
	char dot[MAXCMD] = "";
	float resolution = MP_BAR_SIZE/MP_MAX;
	if(Invulnerable[client])
	{
		Skill_MP[client]=0.0;
	}
	int bar_amount = RoundToFloor(Skill_MP[client] * resolution);
	for (int i = 0; i < bar_amount; i++) {
		if (State_Adrenaline_Boost[client]) {
			Format(dot, MAXCMD, "%s/", dot);
		}
		else if ((Skill_MP[client] >= Skill_MPcost[hiddenExplosionNum]) &&
				 StrEqual(Skill_Name[Skill[client]], "Explosion 爆裂"))
		{
			if(i<13){
				Format(dot, MAXCMD, "%s▓", dot);
			}
		}
		else {
			Format(bar, MAXCMD, "%s|", bar);
		}
	}
	if (State_ManaShield[client]) {
		Format(dot, MAXCMD, "%s) ", dot);
	}
	float weight = 1.2;
	int size = RoundToFloor((MP_BAR_SIZE - bar_amount)*weight);
	// PrintToServer("%d size",size);
	for (int i = 0; i <size; i++) {
		Format(dot, MAXCMD, "%s ", dot);
	}
	PrintHintText(client, "%s\n[%s%s] MP %d\n%s", str, bar, dot, RoundToFloor(Skill_MP[client]),state);
}

// 選單提示的 > < 動畫（TIMER_REPEAT，必須回傳 Plugin_Continue）
public Action Skill_Notify_Ani(Handle timer, any client)
{
	Skill_Notify_Ani_State[client]++;
	if (Skill_Notify_Ani_State[client] > 2) Skill_Notify_Ani_State[client] = 0;
	if (Skill_Notify_Timer[client] != null)
		TriggerTimer(Skill_Notify_Timer[client], true);
	return Plugin_Continue;
}
