--!strict
--[[
	Шаблон профиля игрока и его версия.

	ВАЖНО: при ЛЮБОМ изменении структуры профиля увеличиваем VERSION и добавляем шаг
	в Logic/Migrations. Профили детей терять нельзя — это их шапки, питомцы и выученные буквы.

	См. docs/09-DATA-SCHEMA.md § 9.
]]

local Types = require(script.Parent.Parent.Types)

local ProfileTemplate = {}

ProfileTemplate.VERSION = 1

function ProfileTemplate.defaultSettings(): Types.Settings
	return {
		music = 0.6,
		sfx = 0.7,
		voice = 1, -- голос всегда громче остального, см. docs/13-PARENT-MODE.md
		echoMode = "A", -- честное эхо; режим B включает только родитель
		subtitles = false,
		slowSpeech = false,
		hideRobux = false,
	}
end

function ProfileTemplate.new(now: number): Types.Profile
	return {
		version = ProfileTemplate.VERSION,
		stars = 0,
		level = 1,
		xp = 0,
		letters = {},
		syllables = {},
		words = {},
		islands = {
			[1] = { unlocked = true, bossDone = false, chests = {} },
		},
		inventory = {},
		equipped = { hat = nil, back = nil, face = nil, trail = nil, pets = {} },
		difficulty = {},
		dailyStreak = 0,
		lastLoginDay = 0,
		settings = ProfileTemplate.defaultSettings(),
		parent = { pinHash = nil, dailyLimitMin = nil, echoConsent = false },
		stats = { totalPlayMin = 0, sessionsCount = 0, firstJoin = now },
	}
end

--[[
	Срез профиля, который уходит клиенту. Целиком профиль клиенту не отдаём никогда:
	родительский PIN, настройки лимитов и служебные поля там не нужны.
	См. docs/07-TECH-ARCH.md § 4.
]]
export type Snapshot = {
	stars: number,
	level: number,
	xp: number,
	mastery: { [string]: number },
	nextReview: { [string]: number },
	syllables: { [string]: boolean },
	words: { [string]: boolean },
	islands: { [number]: boolean },
	inventory: { string },
	equipped: Types.Equipped,
	dailyStreak: number,
	settings: Types.Settings,
	echoConsent: boolean,
}

function ProfileTemplate.toSnapshot(profile: Types.Profile): Snapshot
	local mastery: { [string]: number } = {}
	local nextReview: { [string]: number } = {}
	for letterId, progress in profile.letters do
		mastery[letterId] = progress.mastery
		nextReview[letterId] = progress.nextReview
	end

	local islands: { [number]: boolean } = {}
	for index, state in profile.islands do
		islands[index] = state.unlocked
	end

	return {
		stars = profile.stars,
		level = profile.level,
		xp = profile.xp,
		mastery = mastery,
		nextReview = nextReview,
		syllables = table.clone(profile.syllables),
		words = table.clone(profile.words),
		islands = islands,
		inventory = table.clone(profile.inventory),
		equipped = {
			hat = profile.equipped.hat,
			back = profile.equipped.back,
			face = profile.equipped.face,
			trail = profile.equipped.trail,
			pets = table.clone(profile.equipped.pets),
		},
		dailyStreak = profile.dailyStreak,
		settings = table.clone(profile.settings),
		echoConsent = profile.parent.echoConsent,
	}
end

return ProfileTemplate
