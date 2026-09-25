--!strict
--[[
	Значки Roblox (docs/17-CONTENT-PLAN.md § 7.5): статус в профиле ребёнка,
	который видят друзья, — «прошёл все уровни», «собрал всех буквят».

	Значок заводится руками в Creator Dashboard (Associated Items → Badges),
	его номер вписывается сюда в badgeId. Пока номера нет, значок не выдаётся
	и ничего не ломается — сервис молча пропускает его.

	Что заработано, считается из профиля (Badges.earned) — чистая функция,
	её держит тест. Ничего отдельно не хранится: пройденный уровень и
	открытый сундук не отнимаются, значит и значок не «потеряется».
]]

local Chests = require(script.Parent.Chests)
local Levels = require(script.Parent.Levels)
local Letters = require(script.Parent.Letters)
local Pets = require(script.Parent.Parent.Logic.Pets)

export type Badge = { key: string, title: string, badgeId: number? }

local Badges = {}

Badges.LIST = {
	{ key = "first_level", title = "Первый уровень мира букв", badgeId = nil },
	{ key = "all_levels", title = "Все уровни мира букв", badgeId = nil },
	{ key = "first_pet", title = "Первый буквёнок", badgeId = nil },
	{
		key = "all_pets",
		title = "Хранитель Азбуки: все 33 буквёнка",
		badgeId = nil,
	},
	{ key = "all_chests", title = "Все сундуки парка", badgeId = nil },
} :: { Badge }

-- Какие значки ребёнок заработал: множество ключей.
function Badges.earned(profile: any): { [string]: boolean }
	local earned: { [string]: boolean } = {}
	if typeof(profile) ~= "table" then
		return earned
	end
	local levels = if typeof(profile.levels) == "table" then profile.levels else {}
	local cleared = tonumber(levels[Levels.WORLD]) or 0
	if cleared >= 1 then
		earned.first_level = true
	end
	if cleared >= Levels.count() then
		earned.all_levels = true
	end
	local owned = #Pets.owned(profile.letters)
	if owned >= 1 then
		earned.first_pet = true
	end
	if owned >= Letters.count() then
		earned.all_pets = true
	end
	local all = #Chests.all > 0
	for _, chest in Chests.all do
		if not Chests.isOpened(chest, profile.inventory) then
			all = false
			break
		end
	end
	if all then
		earned.all_chests = true
	end
	return earned
end

return Badges
