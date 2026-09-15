--!strict
--[[
	Миграции профиля. Чистая логика, покрыта тестами.

	Правила (docs/09-DATA-SCHEMA.md § 9):
	  · STEPS[v] переводит профиль версии v в версию v+1;
	  · шаги применяются последовательно, пропусков быть не может;
	  · поле не удаляется в той же версии, в которой перестало использоваться:
	    сначала перестаём писать, через релиз — удаляем.

	Миграция обязана быть терпимой к мусору: профиль мог быть сохранён старым билдом,
	повреждён или недописан. Падать нельзя — ребёнок останется без своих букв и шапок.
]]

local Types = require(script.Parent.Parent.Types)
local Base = require(script.Parent.Parent.Config.Base)
local Levels = require(script.Parent.Parent.Config.Levels)
local ProfileTemplate = require(script.Parent.Parent.Config.ProfileTemplate)
local PlayLog = require(script.Parent.PlayLog)
local Tutorial = require(script.Parent.Tutorial)
local PlayLimit = require(script.Parent.PlayLimit)
local DailyLetter = require(script.Parent.DailyLetter)
local MathLevels = require(script.Parent.Parent.Config.MathLevels)

export type Step = (profile: any) -> ()

local Migrations = {}

--[[
	Шаги миграции.

	[1] Переход на обучение алфавиту: игра перестала учить звукам и слогам.
	    Слоги и слова из профиля уходят целиком, острова становятся ступенями,
	    режим эха уезжает вместе с испытанием, которому он служил.

	    Прогресс по буквам НЕ трогаем: буква остаётся буквой, и всё, что ребёнок
	    про неё уже знает, переносится как есть. Ступень у буквы теперь другая,
	    но статусы освоения от ступени не зависят.

	[2] Сохранка забега переехала в профиль: появилось поле `runs`,
	    а `stages[i].checkpoint` убрано. Поле описывало точку на «пути ступени»
	    и ни разу не было записано, так что терять при удалении нечего.

	[3] У игрока появился участок на спавне: поле `base` с уровнем каждой
	    категории построек. Пустой участок — это все нули, а не отсутствие поля.

	[4] Открылся мир математики: поле `math` с прогрессом по ступеням счёта.
	    У старого профиля его быть не может — математике до этой версии негде
	    было храниться, — так что шаг только заводит пустую таблицу и чинит
	    испорченную. Прогресс по буквам он не трогает вовсе: две ветки обучения
	    независимы (docs/16-MATH.md § 6).

	[5] Появилась посуточная история занятий: поле `playLog`. Прошлое восстановить
	    не из чего — время по дням раньше не писалось, — поэтому история
	    начинается пустой. Серию dailyStreak шаг не трогает: её тоже никто
	    не писал, и там ноль.

	[6] Мир букв стал путём из уровней: поле `levels`, пройденных уровней ноль.
	    Засчитать что-то задним числом не из чего — финиши раньше никуда
	    не писались, — и ребёнок начинает путь с первого уровня. Буквы, которые
	    он уже знает, при этом никуда не деваются: статусы живут отдельно.

	    Незаконченный туннель без уровня выбрасывается. Его рецепт старого вида:
	    по нему собрался бы уже другой туннель, и ребёнок оказался бы посреди
	    чужого пути. Потеряна в худшем случае одна сохранка.

	[7] Появилось обучение первых минут: поле `tutorial`. Кто уже играл —
	    есть звёздочки, буквы или вещи, — получает его пройденным: вести
	    за руку к паду, на котором ребёнок был сто раз, значит мешать.

	[8] У родителя появилось напоминание об отдыхе: `parent.restReminder`,
	    включено. Заодно лимит времени приводится к разрешённым значениям:
	    до этой версии его никто не писал, но в испорченном профиле там
	    могло оказаться что угодно.

	[9] Появилась буква дня: поле `daily`. Серию начинаем с нуля — dailyStreak
	    считает просто дни игры, а не пройденные буквы дня, и переносить его
	    сюда значило бы выдать награды за то, чего не было.
]]
local STEPS: { [number]: Step } = {
	[1] = function(profile)
		profile.syllables = nil
		profile.words = nil

		if typeof(profile.islands) == "table" then
			local stages: { [number]: any } = {}
			for index, state in profile.islands do
				if typeof(index) == "number" and typeof(state) == "table" then
					stages[index] = {
						unlocked = state.unlocked == true,
						checkpoint = 0,
						chests = if typeof(state.chests) == "table" then state.chests else {},
					}
				end
			end
			-- Первая ступень открыта всегда, чем бы ни был испорчен профиль.
			stages[1] = stages[1] or { unlocked = true, checkpoint = 0, chests = {} }
			stages[1].unlocked = true
			profile.stages = stages
			profile.islands = nil
		end

		if typeof(profile.settings) == "table" then
			profile.settings.echoMode = nil
		end
		if typeof(profile.parent) == "table" then
			profile.parent.echoConsent = nil
		end
	end,

	[2] = function(profile)
		if typeof(profile.stages) == "table" then
			for _, state in profile.stages do
				if typeof(state) == "table" then
					state.checkpoint = nil
				end
			end
		end

		-- Незаконченных забегов у старого профиля быть не может: до этой версии
		-- их негде было хранить. Заводим пустую таблицу, дальше её наполняет игра.
		if typeof(profile.runs) ~= "table" then
			profile.runs = {}
		end
	end,

	[3] = function(profile)
		-- Sanitize и заводит пустой участок, и чинит испорченный: у старого профиля
		-- построек нет вовсе, а у битого могут оказаться чужие ключи и дробные уровни.
		profile.base = Base.sanitize(profile.base)
	end,

	[4] = function(profile)
		if typeof(profile.math) ~= "table" then
			profile.math = {}
		end
	end,

	[5] = function(profile)
		profile.playLog = PlayLog.sanitize(profile.playLog)
	end,

	[6] = function(profile)
		profile.levels = Levels.sanitize(profile.levels)

		if typeof(profile.runs) == "table" then
			local tunnel = profile.runs.tunnel_run
			if typeof(tunnel) == "table" and tunnel.level == nil then
				profile.runs.tunnel_run = nil
			end
		end
	end,

	[7] = function(profile)
		profile.tutorial = if Tutorial.hasPlayed(profile)
			then Tutorial.finished()
			else Tutorial.sanitize(profile.tutorial)
	end,

	[8] = function(profile)
		profile.parent = PlayLimit.sanitizeParent(profile.parent)
	end,

	[9] = function(profile)
		profile.daily = DailyLetter.sanitize(profile.daily)
	end,

	--[[
		[10] Мир математики стал путём из уровней (Config/MathLevels): рядом с
		     `levels.letters` появился `levels.math`. Кто уже играл, получает
		     пройденными столько уровней, сколько ступеней у него было открыто
		     сверх первой, — портал продолжит с той же ступени, а не с полянки.
		     Сохранка забега с числами остаётся: её ступень и есть уровень.
	]]
	[10] = function(profile)
		local levels = Levels.sanitize(profile.levels)
		local math_ = if typeof(profile.math) == "table" then profile.math else {}
		levels[MathLevels.WORLD] = MathLevels.clearedFromMastery(function(stageId: string): number
			local progress = math_[stageId]
			return if typeof(progress) == "table" and typeof(progress.mastery) == "number"
				then progress.mastery
				else 0
		end)
		profile.levels = levels
	end,
}

Migrations.STEPS = STEPS

--[[
	Приводит профиль к целевой версии.
	Возвращает профиль и число применённых шагов.

	steps можно подменить — это нужно тестам и ничему больше.
]]
function Migrations.apply(profile: any, targetVersion: number, steps: { [number]: Step }?): (any, number)
	local table_ = steps or STEPS
	local applied = 0

	if typeof(profile) ~= "table" then
		return profile, 0
	end

	if typeof(profile.version) ~= "number" then
		-- профиль без версии считаем самым первым
		profile.version = 1
	end

	while profile.version < targetVersion do
		local step = table_[profile.version]
		if step then
			local ok, err = pcall(step, profile)
			if not ok then
				warn(`[Migrations] шаг {profile.version} упал: {err}`)
			end
			applied += 1
		end
		profile.version += 1
	end

	return profile, applied
end

--[[
	Достраивает недостающие поля по шаблону. Страховка от профилей, сохранённых
	билдом, который поле ещё не писал, и от частично повреждённых данных.
	Существующие значения не трогает.
]]
function Migrations.fillDefaults(profile: any, now: number): Types.Profile
	local template = ProfileTemplate.new(now)

	if typeof(profile) ~= "table" then
		return template
	end

	for key, value in template :: any do
		if profile[key] == nil then
			profile[key] = value
		elseif typeof(value) == "table" and typeof(profile[key]) == "table" then
			-- один уровень вложенности: settings, parent, stats, equipped
			for subKey, subValue in value do
				if profile[key][subKey] == nil then
					profile[key][subKey] = subValue
				end
			end
		elseif typeof(profile[key]) ~= typeof(value) then
			-- тип не совпал: данные повреждены, берём значение по умолчанию
			warn(
				`[Migrations] поле "{key}" имело неверный тип, сброшено к значению по умолчанию`
			)
			profile[key] = value
		end
	end

	return profile :: Types.Profile
end

-- Полный проход: миграции + достройка полей. Именно это вызывает ProfileService.
function Migrations.normalize(profile: any, now: number): Types.Profile
	local migrated = Migrations.apply(profile, ProfileTemplate.VERSION)
	local normalized = Migrations.fillDefaults(migrated, now)
	--[[
		Историю занятий чистим на каждом входе, а не только в шаге миграции:
		в неё пишут перед каждым сохранением, и одна битая запись у профиля
		уже текущей версии уронила бы учёт времени — а вместе с ним и сохранение.
		Записей не больше четырёх недель, так что это дёшево.
	]]
	normalized.playLog = PlayLog.sanitize(normalized.playLog)
	return normalized
end

return Migrations
