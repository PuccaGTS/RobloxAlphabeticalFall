--!strict
--[[
	Танцы и жесты: кнопка 💃 внизу экрана открывает ряд движений.

	Зачем в обучающей игре танцы: дети играют рядом друг с другом без чата
	(docs/11-COMPLIANCE.md § 2), и помахать соседу, станцевать на финише или
	посмеяться — это и есть их разговор. Звёзд за это нет и не будет.

	Анимации — стандартные анимации Roblox из скрипта Animate: принадлежат
	Roblox, работают в любом опыте, загружать ничего не надо. У R15 и R6 они
	разные, поэтому два номера. Движение останавливает жест сразу: танец
	не должен мешать бежать.
]]

local Emotes = {}

export type Emote = {
	id: string,
	icon: string,
	title: string,
	r15: number,
	r6: number,
	looped: boolean, -- танцы повторяются, пока ребёнок не двинется; жесты — один раз
}

local LIST: { Emote } = {
	{ id = "wave", icon = "👋", title = "Привет", r15 = 507770239, r6 = 128777973, looped = false },
	{ id = "dance", icon = "💃", title = "Танец", r15 = 507771019, r6 = 182435998, looped = true },
	{
		id = "dance2",
		icon = "🕺",
		title = "Ещё танец",
		r15 = 507776043,
		r6 = 182436842,
		looped = true,
	},
	{
		id = "dance3",
		icon = "🎶",
		title = "Под музыку",
		r15 = 507777268,
		r6 = 182436935,
		looped = true,
	},
	{ id = "cheer", icon = "🎉", title = "Ура!", r15 = 507770677, r6 = 129423030, looped = false },
	{ id = "laugh", icon = "😄", title = "Смешно", r15 = 507770818, r6 = 129423131, looped = false },
	{ id = "point", icon = "👉", title = "Смотри!", r15 = 507770453, r6 = 128853357, looped = false },
}
Emotes.list = LIST

local byId: { [string]: Emote } = {}
for _, emote in LIST do
	assert(byId[emote.id] == nil, `Emotes: дубликат "{emote.id}"`)
	byId[emote.id] = emote
end

function Emotes.get(id: string): Emote?
	return byId[id]
end

-- Буквята радуются вместе с хозяином, если тот танцует или кричит «ура».
Emotes.PETS_JOIN = { dance = true, dance2 = true, dance3 = true, cheer = true }

return Emotes
