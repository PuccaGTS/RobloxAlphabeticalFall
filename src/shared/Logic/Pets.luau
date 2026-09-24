--!strict
--[[
	Питомцы-буквята: кто у ребёнка есть и кто летает за ним сейчас.
	См. docs/01-GDD.md § 5 и docs/04-ECONOMY.md § «Питомцы-буквята».

	Буквёнок даётся за букву в статусе «освоенная» — бесплатно, и купить его нельзя.
	Это главная связка «учился → получил живого спутника»: питомец летает за
	ребёнком и называет свою букву, если на него нажать, — постоянное фоновое
	повторение, встроенное в косметику. Продавай мы его за Звёздочки, связка
	перестала бы работать (docs/17-CONTENT-PLAN.md § 4).

	Отсюда главное устройство: владение НЕ хранится. Буквёнок есть, пока буква
	освоена, а понижения статуса не бывает никогда (Logic/MasteryRules), так что
	и питомец не пропадёт. Две записи об одном — статус и «куплен питомец» —
	рано или поздно разошлись бы. В профиле лежит только, кто летает сейчас:
	equipped.pets — список id букв.

	Чистая логика без Roblox API — покрыта тестами.
]]

local Letters = require(script.Parent.Parent.Config.Letters)
local MasteryRules = require(script.Parent.MasteryRules)

local Pets = {}

--[[
	Сколько буквят летает за ребёнком одновременно: один с самого начала, второй —
	за десять освоенных букв. В docs/04-ECONOMY.md § 4 второй слот стоял «на 10 уровне
	Хранителя», но уровня Хранителя в игре нет, а слот за учёбу понятнее и честнее:
	тот же порог, что у Азбучной арки. Третий слот за Game Pass — вместе с покупками.
]]
Pets.MAX_SLOTS = 2
Pets.SECOND_SLOT_AT = 10

local function masteryOf(letters: any, letterId: string): number
	if typeof(letters) ~= "table" then
		return 0
	end
	local progress = letters[letterId]
	if typeof(progress) ~= "table" or typeof(progress.mastery) ~= "number" then
		return 0
	end
	return progress.mastery
end

--[[
	Какой зверёк у буквы: по порядку в алфавите, чтобы у соседних букв зверьки
	были разные, — котик, зайчик, мишка, птенчик, лягушонок. Его рисует
	PetController, а открытка буквёнка (Logic/Mail) показывает его эмодзи.
]]
Pets.SPECIES = { "cat", "bunny", "bear", "bird", "frog" }
Pets.SPECIES_ICONS = { cat = "🐱", bunny = "🐰", bear = "🐻", bird = "🐥", frog = "🐸" }

function Pets.speciesOf(letterId: string): string
	local letter = Letters.expect(letterId)
	return Pets.SPECIES[(letter.order - 1) % #Pets.SPECIES + 1]
end

function Pets.isOwned(letters: any, letterId: any): boolean
	if typeof(letterId) ~= "string" or Letters.get(letterId) == nil then
		return false
	end
	return masteryOf(letters, letterId) >= MasteryRules.MASTERED
end

-- Все буквята ребёнка в порядке алфавита.
function Pets.owned(letters: any): { string }
	local list: { string } = {}
	for _, id in Letters.ordered() do
		if Pets.isOwned(letters, id) then
			table.insert(list, id)
		end
	end
	return list
end

function Pets.slotsFor(letters: any): number
	return if #Pets.owned(letters) >= Pets.SECOND_SLOT_AT then Pets.MAX_SLOTS else 1
end

--[[
	Все 33 буквы освоены: ребёнок — Хранитель Азбуки (docs/01-GDD.md, docs/04-ECONOMY.md § 4).
	Титул не хранится, как и сами буквята: он есть, пока освоены все буквы.
]]
function Pets.isKeeper(letters: any): boolean
	return #Pets.owned(letters) == Letters.count()
end

--[[
	Кто летает, приведённый в порядок: только свои буквята, без повторов,
	не больше слотов. Из DataStore может прийти что угодно, а подделанный
	питомец за неосвоенную букву сломал бы ту самую связку «учился → получил».
]]
function Pets.sanitizeEquipped(equipped: any, letters: any): { string }
	local clean: { string } = {}
	if typeof(equipped) ~= "table" then
		return clean
	end
	local slots = Pets.slotsFor(letters)
	for _, id in equipped do
		if #clean >= slots then
			break
		end
		if Pets.isOwned(letters, id) and not table.find(clean, id) then
			table.insert(clean, id)
		end
	end
	return clean
end

--[[
	Буква только что освоена. Если есть свободный слот, новый буквёнок сразу
	вылетает к ребёнку: награду надо видеть сейчас, а не искать в меню.
	Занятый слот не трогаем — любимца на новичка молча не меняем.
]]
function Pets.afterMastered(equipped: any, letters: any, letterId: string): { string }
	local clean = Pets.sanitizeEquipped(equipped, letters)
	if
		#clean < Pets.slotsFor(letters)
		and Pets.isOwned(letters, letterId)
		and not table.find(clean, letterId)
	then
		table.insert(clean, letterId)
	end
	return clean
end

--[[
	Ребёнок выбрал буквёнка (коснулся освоенной буквы на Башне). Выбранный
	встаёт первым — на место за правым плечом, — а прежний первый сдвигается
	во второй слот, если он есть; самый давний улетает. Уже летающего выбор
	не выгоняет: коснулся своего буквёнка на Башне — он просто остался.
	nil — выбрать нельзя: буква не освоена или такой буквы нет.
]]
function Pets.choose(letters: any, letterId: any, equipped: any): { string }?
	if not Pets.isOwned(letters, letterId) then
		return nil
	end
	local clean = Pets.sanitizeEquipped(equipped, letters)
	if table.find(clean, letterId) then
		return clean
	end
	table.insert(clean, 1, letterId)
	while #clean > Pets.slotsFor(letters) do
		table.remove(clean)
	end
	return clean
end

return Pets
