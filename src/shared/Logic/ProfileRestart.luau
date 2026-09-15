--!strict
--[[
	«Начать заново» из родительского режима: обучение с нуля. См. docs/13-PARENT-MODE.md § 3.

	Граница проходит между знанием и заработанным.

	Стирается всё, что говорит, что ребёнок уже знает: буквы, математика, открытые
	ступени, пройденные уровни, незаконченные забеги, сложность испытаний и буквята —
	буквёнок прилетает за освоенную букву, и без неё его быть не может (Logic/Pets).
	Флаги, арка и шпиль во дворе считаются из букв и уровней, они уйдут сами.

	Остаётся заработанное и родительское: звёздочки, вещи, дом, серия буквы дня,
	история занятий, звук, PIN и лимит. Отнимать шапку у ребёнка за решение
	взрослого нельзя, а лимит времени считается по истории занятий: сотри её —
	и «начать заново» снимало бы лимит на сегодня.

	Обучение первых минут тоже не повторяется: оно учит управлению, а не буквам.

	Чистая логика без Roblox API — покрыта тестами.
]]

local Types = require(script.Parent.Parent.Types)
local Levels = require(script.Parent.Parent.Config.Levels)
local DailyLetter = require(script.Parent.DailyLetter)

local ProfileRestart = {}

--[[
	Меняет профиль на месте. today — сутки по PlayLog.dayOf.

	Буква дня: если сегодня ни одного задания не сделано, букву выбираем заново —
	старая могла быть с поздней ступени, которой после сброса нет. Начатую
	не трогаем: ребёнок уже видел её на камне, и счётчик не должен обнулиться,
	иначе те же три задания принесли бы награду второй раз за день.
]]
function ProfileRestart.apply(profile: Types.Profile, today: number)
	profile.letters = {}
	profile.math = {}
	profile.stages = { [1] = { unlocked = true, chests = {} } }
	profile.runs = {}
	profile.levels = Levels.sanitize(nil)
	profile.difficulty = {}
	profile.equipped.pets = {}

	local daily = DailyLetter.sanitize(profile.daily)
	if daily.day ~= today or daily.done == 0 then
		daily.day = 0
		daily.letterId = nil
		daily.done = 0
	end
	profile.daily = daily
end

return ProfileRestart
