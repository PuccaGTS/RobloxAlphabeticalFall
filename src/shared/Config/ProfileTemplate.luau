--!strict
--[[
	Шаблон профиля игрока и его версия.

	ВАЖНО: при ЛЮБОМ изменении структуры профиля увеличиваем VERSION и добавляем шаг
	в Logic/Migrations. Профили детей терять нельзя — это их шапки, питомцы и выученные буквы.

	См. docs/09-DATA-SCHEMA.md § 9.
]]

local Types = require(script.Parent.Parent.Types)
local Base = require(script.Parent.Base)
local Levels = require(script.Parent.Levels)
local Tutorial = require(script.Parent.Parent.Logic.Tutorial)
local DailyLetter = require(script.Parent.Parent.Logic.DailyLetter)
local Mail = require(script.Parent.Parent.Logic.Mail)
local Variety = require(script.Parent.Parent.Logic.Variety)
local Quests = require(script.Parent.Parent.Logic.Quests)
local LetterGarden = require(script.Parent.Parent.Logic.LetterGarden)
local Secrets = require(script.Parent.Parent.Logic.Secrets)

local ProfileTemplate = {}

--[[
	Версия 2: игра перешла с обучения звукам на обучение алфавиту.
	Из профиля ушли `syllables` и `words` (слоги и слова больше не изучаются),
	`islands` стали `stages`, из настроек ушёл режим эха.

	Версия 4: у игрока появился участок на спавне — поле `base` с уровнем
	каждой категории построек (docs/15-HOME-BASE.md § 8).

	Версия 3: сохранка забега переехала в профиль. Появилось поле `runs`,
	а `stages[i].checkpoint` ушло: оно описывало точку на «пути ступени», которого
	в игре так и не завелось, и ни разу не было записано. Настоящая сохранка
	принадлежит забегу, а не ступени алфавита, — см. Types.SavedRun.

	Обычно поле не удаляется в той же версии, в которой перестало использоваться,
	но здесь мы вправе резать сразу: игра не опубликована, живых профилей нет,
	и тащить пустые таблицы в DataStore не за чем.

	Версия 5: открылся мир математики — поле `math` с прогрессом по ступеням счёта.
	Оно отдельное от `letters`, потому что математика и буквы не блокируют друг друга
	(docs/16-MATH.md § 6), а устроено точно так же: ступень осваивается по тем же
	правилам, что и буква.

	Версия 6: посуточная история занятий — поле `playLog`. Без неё отчёт родителя
	не может сказать «занимался 6 дней из последних 7» (docs/13-PARENT-MODE.md § 2).

	Версия 7: мир букв стал путём из уровней — поле `levels` со счётом пройденных
	уровней каждого мира (Config/Levels). Портал ведёт на следующий за пройденными.

	Версия 8: обучение первых минут — поле `tutorial` со сделанными шагами
	(Logic/Tutorial). Кто уже играл, получает его пройденным.

	Версия 9: у родителя появилось напоминание об отдыхе — `parent.restReminder`,
	по умолчанию включено (docs/13-PARENT-MODE.md § 3).

	Версия 10: буква дня и её серия — поле `daily` (Logic/DailyLetter).

	Версия 11: мир математики стал путём из уровней — `levels.math` (Config/MathLevels).

	Версия 12: почта от буквят — поле `mail` с открытыми открытками (Logic/Mail).
	Кто уже осваивал буквы, найдёт в ящике открытки от всех своих буквят сразу.

	Версия 13: бонус за разнообразие — поле `variety`, какие занятия уже закончены
	сегодня (Logic/Variety). Первое за сутки каждое занятие приносит звёзды сверху.
	И задания дня — поле `quests` (Logic/Quests): три дела на сутки со стрелкой к месту.

	Версия 14: азбучная грядка у калитки — поле `garden` (Logic/LetterGarden):
	три лунки, что в них посажено и когда, сколько собрано.
]]
ProfileTemplate.VERSION = 14

function ProfileTemplate.defaultSettings(): Types.Settings
	return {
		-- Ступени Logic/SoundSettings: родитель выбирает громкость кнопками по 25 %.
		music = 0.5,
		sfx = 0.75,
		voice = 1, -- голос всегда громче остального, см. docs/13-PARENT-MODE.md
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
		math = {},
		stages = {
			[1] = { unlocked = true, chests = {} },
		},
		runs = {},
		levels = Levels.sanitize(nil),
		tutorial = {},
		base = Base.newProgress(),
		-- Форма и краска построек: { [категория] = { shape, paint } }, Base.sanitizeStyle.
		baseStyle = {},
		inventory = {},
		equipped = { hat = nil, back = nil, face = nil, trail = nil, pets = {} },
		difficulty = {},
		dailyStreak = 0,
		lastLoginDay = 0,
		playLog = {},
		daily = DailyLetter.new(),
		mail = Mail.new(),
		variety = Variety.new(),
		quests = Quests.new(),
		garden = LetterGarden.new(),
		settings = ProfileTemplate.defaultSettings(),
		parent = { pinHash = nil, dailyLimitMin = nil, restReminder = true },
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
	-- Статусы ступеней математики: тот же вид, что у букв, ключ — id ступени.
	math: { [string]: number },
	stages: { [number]: boolean },
	-- Пройденные уровни каждого мира: по ним клиент подписывает портал.
	levels: { [string]: number },
	-- Найдено секретов на каждом уровне мира букв, по порядку (Logic/Secrets).
	secrets: { number },
	-- Текущий шаг обучения ("catch", "shop", "run") или nil, если пройдено.
	tutorial: string?,
	base: { [string]: number },
	baseStyle: { [string]: Base.Style },
	inventory: { string },
	equipped: Types.Equipped,
	dailyStreak: number,
	-- Буква дня: какая и сколько заданий из трёх сделано. Сегодняшняя ли она, решает сервер.
	daily: { letterId: string?, done: number, total: number, streak: number },
	settings: Types.Settings,
}

-- Клиенту нужен только текущий шаг обучения — куда показывать стрелкой.
local function tutorialStep(profile: Types.Profile): string?
	local step = Tutorial.current(Tutorial.sanitize(profile.tutorial))
	return if step then step.id else nil
end

local function dailySnapshot(profile: Types.Profile)
	local state = DailyLetter.sanitize(profile.daily)
	return {
		letterId = state.letterId,
		done = state.done,
		total = #DailyLetter.TASKS,
		streak = state.streak,
	}
end

function ProfileTemplate.toSnapshot(profile: Types.Profile): Snapshot
	local mastery: { [string]: number } = {}
	local nextReview: { [string]: number } = {}
	for letterId, progress in profile.letters do
		mastery[letterId] = progress.mastery
		nextReview[letterId] = progress.nextReview
	end

	local math_: { [string]: number } = {}
	for stageId, progress in profile.math do
		math_[stageId] = progress.mastery
	end

	local stages: { [number]: boolean } = {}
	for index, state in profile.stages do
		stages[index] = state.unlocked
	end

	return {
		stars = profile.stars,
		level = profile.level,
		xp = profile.xp,
		mastery = mastery,
		nextReview = nextReview,
		math = math_,
		stages = stages,
		levels = Levels.sanitize(profile.levels),
		-- Сколько секретов найдено на каждом уровне: табличка портала и пад охоты за ними.
		secrets = Secrets.counts(profile.stages),
		tutorial = tutorialStep(profile),
		base = table.clone(profile.base),
		baseStyle = Base.sanitizeStyle(profile.baseStyle),
		inventory = table.clone(profile.inventory),
		equipped = {
			hat = profile.equipped.hat,
			back = profile.equipped.back,
			face = profile.equipped.face,
			trail = profile.equipped.trail,
			petskin = profile.equipped.petskin,
			pets = table.clone(profile.equipped.pets),
		},
		dailyStreak = profile.dailyStreak,
		daily = dailySnapshot(profile),
		settings = table.clone(profile.settings),
	}
end

return ProfileTemplate
