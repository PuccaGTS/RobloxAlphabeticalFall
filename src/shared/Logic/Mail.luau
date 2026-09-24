--!strict
--[[
	Почта от буквят: освоил букву — её буквёнок присылает открытку в почтовый
	ящик у калитки. Открытка — сама буква крупно, картинка к ней и буквёнок.

	Какие открытки пришли, не хранится: это освоенные буквы (Logic/Pets —
	кто освоен, у того и буквёнок). Хранится только, какие ребёнок уже открыл, —
	по этому флажок на ящике и поднимается. Две записи «пришло» и «освоено»
	рано или поздно разошлись бы, а «прочитано» ничем другим не выводится.

	Звёздочек почта не даёт: открытка — это радость за букву, а не награда
	за то, что сходил к ящику.

	Чистая логика без Roblox API — покрыта тестами.
]]

local Letters = require(script.Parent.Parent.Config.Letters)
local Pets = require(script.Parent.Pets)

local Mail = {}

export type State = {
	seen: { string }, -- id букв, чьи открытки уже открыты, по алфавиту
}

function Mail.new(): State
	return { seen = {} }
end

-- Порядок, мусор и повторы: в seen только настоящие буквы, каждая один раз.
function Mail.sanitize(state: any): State
	local seen: { [string]: boolean } = {}
	if typeof(state) == "table" and typeof(state.seen) == "table" then
		for _, id in state.seen do
			if typeof(id) == "string" and Letters.get(id) then
				seen[id] = true
			end
		end
	end
	local list: { string } = {}
	for _, id in Letters.ordered() do
		if seen[id] then
			table.insert(list, id)
		end
	end
	return { seen = list }
end

-- Все открытки, что ребёнку пришли: по одной за освоенную букву, по алфавиту.
function Mail.received(letters: any): { string }
	return Pets.owned(letters)
end

-- Пришли и ещё не открыты: по ним флажок на ящике поднят.
function Mail.unread(letters: any, state: any): { string }
	local seen: { [string]: boolean } = {}
	for _, id in Mail.sanitize(state).seen do
		seen[id] = true
	end
	local list: { string } = {}
	for _, id in Mail.received(letters) do
		if not seen[id] then
			table.insert(list, id)
		end
	end
	return list
end

-- Отметить открытки прочитанными. Прочитать можно только пришедшую.
function Mail.markRead(state: any, letters: any, ids: { string }): State
	local clean = Mail.sanitize(state)
	local received: { [string]: boolean } = {}
	for _, id in Mail.received(letters) do
		received[id] = true
	end
	for _, id in ids do
		if received[id] and not table.find(clean.seen, id) then
			table.insert(clean.seen, id)
		end
	end
	return Mail.sanitize(clean)
end

return Mail
