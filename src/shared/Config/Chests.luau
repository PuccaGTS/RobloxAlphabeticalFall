--!strict
--[[
	Коллекционные сундуки в парке между площадью и домами — docs/18-CONTENT-BACKLOG.md § 8.

	Три правила, и все зашиты в данные:
	  · в каждом сундуке ОДНА заранее известная вещь. Случайных наград в игре нет
	    вовсе (docs/04-ECONOMY.md § 1), и сундук — не исключение: что в нём лежит,
	    видно в магазине ещё до того, как сундук найден;
	  · награда — косметика, никогда не прогресс обучения и не звёздочки:
	    звёздочки только за учёбу (CHECKLIST, «Правила»);
	  · открывается один раз. Открыт ли, не хранится отдельно: вещь в инвентаре —
	    значит, открыт. Две записи об одном рано или поздно разошлись бы.

	Сундуки стоят в парке — там, куда ребёнок и так ходит от площади к своему дому,
	но чуть в стороне от дорожек: найти можно, наткнуться случайно — нет.
]]

local Base = require(script.Parent.Base)
local Playground = require(script.Parent.Playground)

local Chests = {}

export type Chest = {
	id: string,
	itemId: string, -- что лежит внутри: предмет Config/Shop с grantedBy = "chest:<id>"
	angle: number, -- направление от центра площади, в градусах
	distance: number, -- расстояние от центра
	rotation: number, -- куда смотрит крышка, в градусах
	-- Сундук спрятан внутри игрового места (Config/Playground): его зона — свой дом, а не помеха.
	insideSpot: string?,
	-- На какой высоте над землёй стоит: сундук на облачном острове висит над парком.
	height: number?,
}

--[[
	Углы — между дорожками к домам (0°, 90°, 180°, 270°), а не на них. Расстояние —
	за кольцом деревьев вокруг площади и заметно раньше участков.
]]
local CHESTS: { Chest } = {
	{ id = "chest_pines", itemId = "hat_mushroom", angle = 35, distance = 92, rotation = 215 },
	{ id = "chest_pond", itemId = "back_hedgehog", angle = 150, distance = 104, rotation = 330 },
	{ id = "chest_meadow", itemId = "trail_leaves", angle = 250, distance = 98, rotation = 70 },
	--[[
		Четвёртый — в Тайном саду (Config/Playground, secret): за стеной кустов,
		вход с дальней от площади стороны, сквозь занавес из листвы. Находка
		для того, кто обойдёт круг кустов, а не для того, кто бежит мимо.
	]]
	{
		id = "chest_secret",
		itemId = "back_firefly_jar",
		angle = 276,
		distance = 211, -- у дальней от входа стены сада, замком ко входу
		rotation = 354,
		insideSpot = "secret",
	},
	--[[
		Пятый — на облачном острове над бобовым стеблем (Config/Playground,
		beanstalk): у замка великана, рядом с золотой гусыней. Добраться — значит
		долезть до облаков по листьям. Внутри «Облачко» — шапка-тучка с щёчками.
	]]
	{
		id = "chest_sky",
		itemId = "hat_cloud",
		angle = 145,
		distance = 204, -- на острове, ближе к площади, чем замок
		rotation = 325,
		insideSpot = "beanstalk",
		height = Playground.BEAN_TOP,
	},
}

Chests.all = CHESTS
Chests.PREFIX = "chest:"

function Chests.get(id: string): Chest?
	for _, chest in CHESTS do
		if chest.id == id then
			return chest
		end
	end
	return nil
end

function Chests.position(chest: Chest): Vector3
	local angle = math.rad(chest.angle)
	return Vector3.new(math.cos(angle) * chest.distance, 0, math.sin(angle) * chest.distance)
end

-- Сундук открыт, если его вещь уже у ребёнка.
function Chests.isOpened(chest: Chest, inventory: any): boolean
	return typeof(inventory) == "table" and table.find(inventory, chest.itemId) ~= nil
end

-- Из какого сундука предмет: id сундука из grantedBy или nil.
function Chests.chestIdOf(grantedBy: string?): string?
	if not grantedBy or string.sub(grantedBy, 1, #Chests.PREFIX) ~= Chests.PREFIX then
		return nil
	end
	local id = string.sub(grantedBy, #Chests.PREFIX + 1)
	return if Chests.get(id) then id else nil
end

-- Дальше этого стоят участки детей: сундук на чужом дворе — не находка, а путаница.
Chests.MAX_DISTANCE = Base.RING_RADIUS - Base.PLOT_SIZE

return Chests
