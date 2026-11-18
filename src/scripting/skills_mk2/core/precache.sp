// 資源預載與下載表（第 2 步拆進各技能的 onPrecache 後移除）

void Setup_Materials()
{
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

	PrecacheSound(NUKE_SOUND, true);

	SetupMaterial("particles\\skill_fx.pcf");
	SetupMaterial("particles\\ex.pcf");
	SetupMaterial("particles\\nuke.pcf");
	SetupMaterial("particles\\nuke2.pcf");
	PrecacheParticle(PARTICLE_EXPLOSION);
	PrecacheParticle(PARTICLE_EXPLOSION2);
	PrecacheParticle(PARTICLE_EAGLEEYE);
	PrecacheParticle(PARTICLE_TURNUNDEAD);
	PrecacheParticle(PARTICLE_EX_GLOW);
	PrecacheParticle(PARTICLE_EX_GLOW_BIG);
	PrecacheParticle(PARTICLE_EX_LIGHT);
	PrecacheParticle(PARTICLE_MAGIC_CIRCLE);
	PrecacheParticle(PARTICLE_NUKE1);
	PrecacheParticle(PARTICLE_NUKE2);

	// 腳下水平魔法陣 (mdl + 動畫材質)
	SetupMaterial(MAGIC_CIRCLE_VTF);
	SetupMaterial(MAGIC_CIRCLE_VMT_GROUND);
	SetupMaterial(MAGIC_CIRCLE_MODEL);
	SetupMaterial("models/konosuba/magic_circle_plane.vvd");
	SetupMaterial("models/konosuba/magic_circle_plane.dx90.vtx");
	if (FileExists(MAGIC_CIRCLE_MODEL, true))
		PrecacheModel(MAGIC_CIRCLE_MODEL, true);
	PrintToServer("===========Material Setup End===========");
}

void SetupMaterial(const char[] file)
{
	AddFileToDownloadsTable(file);
	PrecacheGeneric(file);
}
