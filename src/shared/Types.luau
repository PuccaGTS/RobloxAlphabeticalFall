--!strict
--[[
	Общие типы проекта. Единственное место, где живут структуры данных.
	См. docs/09-DATA-SCHEMA.md
]]

local Types = {}

-- ===== Буквы =====================================================================

export type LetterKind = "vowel" | "consonant" | "hissing" | "iotated" | "sign"

export type LetterVO = {
	sound: string, -- изолированный звук: "snd_m"
	long: string?, -- растянутый звук для эха: "snd_long_m" (только для тянущихся)
	name: string, -- название буквы, даётся поздно: "name_m"
}

export type Letter = {
	id: string, -- ключ во всех системах: "m"
	glyph: string, -- "М"
	glyphLower: string, -- "м"
	kind: LetterKind,
	voiced: boolean?, -- звонкая/глухая, только для согласных
	sustainable: boolean, -- можно ли тянуть звук
	island: number,
	order: number, -- порядок внутри острова
	color: Color3,
	vo: LetterVO,
	examples: { string }, -- id слов из Config/Words
	confusableWith: { string }, -- пары-путаницы, см. docs/02-LEARNING.md
}

-- ===== Слоги и слова =============================================================

export type SyllableKind = "open" | "closed" | "vv" | "cluster"

export type Syllable = {
	id: string, -- "ma"
	text: string, -- "МА"
	consonant: string?, -- id согласной
	vowel: string, -- id гласной
	kind: SyllableKind,
	vo: string, -- "blend_ma" — ОДИН слитный файл, не склейка
	minIsland: number,
}

export type Word = {
	id: string, -- "mama"
	text: string, -- "МАМА"
	letters: { string }, -- {"m","a","m","a"}
	-- Разбиение НАПИСАНИЯ на слоги для подсветки и слоговой озвучки: {"МА","МА"}.
	-- Это не id из Config/Syllables: в словах встречаются куски вроде "НАН",
	-- которых нет и не должно быть в наборе учебных слогов.
	syllables: { string },
	vo: string,
	voSyllabic: string,
	image: string, -- ключ ассета картинки
	minIsland: number,
	tags: { string },
}

-- ===== Острова ===================================================================

export type Island = {
	index: number,
	id: string,
	title: string,
	letters: { string },
	challenges: { string },
	unlockPrevMasteryRatio: number, -- 0.8 = 80% букв предыдущего острова
	bossId: string?,
	music: string,
	voIntro: string,
}

-- ===== Прогресс игрока ===========================================================

-- 0 незнакомая · 1 знакомая · 2 изученная · 3 освоенная
export type Mastery = number

export type LetterProgress = {
	mastery: Mastery,
	correct: number,
	wrong: number,
	streak: number,
	types: { string }, -- в каких типах испытаний был успех
	lastSeen: number, -- os.time()
	learnedAt: number?, -- когда достигнут статус 2 (нужно для правила «через 2 дня»)
	masteredAt: number?, -- когда достигнут статус 3
	reviewStep: number, -- индекс интервала повторения, см. Logic/ReviewScheduler
	nextReview: number, -- os.time()
	avgReactionMs: number,
	answers: number, -- сколько всего ответов учтено в avgReactionMs
}

export type Answer = {
	letterId: string,
	challengeId: string,
	correct: boolean,
	reactionMs: number,
	hintsUsed: number,
}

-- ===== Профиль ===================================================================

export type Equipped = {
	hat: string?,
	back: string?,
	face: string?,
	trail: string?,
	pets: { string },
}

export type Settings = {
	music: number,
	sfx: number,
	voice: number,
	echoMode: string, -- "A" | "B" | "C"
	subtitles: boolean,
	slowSpeech: boolean,
	hideRobux: boolean,
}

export type ParentData = {
	pinHash: string?,
	dailyLimitMin: number?,
	echoConsent: boolean,
}

export type IslandProgress = {
	unlocked: boolean,
	bossDone: boolean,
	chests: { string },
}

export type Profile = {
	version: number,
	stars: number,
	level: number,
	xp: number,
	letters: { [string]: LetterProgress },
	syllables: { [string]: boolean },
	words: { [string]: boolean },
	islands: { [number]: IslandProgress },
	inventory: { string },
	equipped: Equipped,
	difficulty: { [string]: number }, -- уровень сложности на каждое испытание
	dailyStreak: number,
	lastLoginDay: number,
	settings: Settings,
	parent: ParentData,
	stats: {
		totalPlayMin: number,
		sessionsCount: number,
		firstJoin: number,
	},
}

-- ===== Испытания =================================================================

export type ChallengeSpec = {
	challengeId: string,
	seed: number,
	letters: { string },
	difficulty: number,
	targetCount: number,
	params: { [string]: any },
}

export type ChallengeResult = {
	challengeId: string,
	stars: number, -- 1..3
	answers: { Answer },
	rewardStars: number,
}

return Types
