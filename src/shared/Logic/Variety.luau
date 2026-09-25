--!strict
--[[
	Бонус за разнообразие: первое за сутки прохождение каждого занятия приносит
	сверху Economy.REWARDS.varietyBonus.

	Зачем. На проверке 24.09.2026 посчитали: семь занятий по 5 ⭐ — это одна шапка,
	«а дальше как заработать? идти всё сначала?». Награда за повтор одного и того же
	подталкивала бы гонять одно занятие по кругу. Бонус платит за новое: сегодня
	сыграл в Пузыри, Лаву и Весы — за каждое сверху, а завтра всё снова свежее.
	Это по-прежнему плата только за обучающие действия (docs/04-ECONOMY.md § 2):
	бонус даётся за законченное занятие с ответами, не за вход и не за время.

	В профиле — день и список занятий, уже взятых в этот день. Чистая логика.
]]

local Variety = {}

export type State = { day: number, done: { string } }

-- Больше занятий в игре нет; запас от мусора в профиле.
Variety.MAX_DONE = 32

function Variety.new(): State
	return { day = 0, done = {} }
end

function Variety.sanitize(raw: any): State
	if typeof(raw) ~= "table" or typeof(raw.day) ~= "number" or raw.day ~= raw.day then
		return Variety.new()
	end
	local done: { string } = {}
	if typeof(raw.done) == "table" then
		for _, id in raw.done do
			if typeof(id) == "string" and not table.find(done, id) and #done < Variety.MAX_DONE then
				table.insert(done, id)
			end
		end
	end
	return { day = math.floor(raw.day), done = done }
end

--[[
	Отметить законченное занятие. true — сегодня оно первое такое, и бонус положен.
	Новые сутки начинают список заново.
]]
function Variety.claim(state: State, day: number, challengeId: string): (State, boolean)
	local clean = Variety.sanitize(state)
	if clean.day ~= day then
		clean = { day = day, done = {} }
	end
	if table.find(clean.done, challengeId) or #clean.done >= Variety.MAX_DONE then
		return clean, false
	end
	table.insert(clean.done, challengeId)
	return clean, true
end

return Variety
