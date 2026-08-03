--!strict
--[[
	Витрина магазина. 12 предметов вертикального среза.

	Правила (docs/04-ECONOMY.md):
	  · косметика НИЧЕГО не даёт в геймплее — только вид;
	  · у предмета ровно одно из: цена в ⭐ / покупка за Robux / выдача за прогресс;
	  · первая покупка должна быть по карману после первого же испытания (10 ⭐).

	Арта пока нет, поэтому каждый предмет описан рецептом примитивов (visual):
	CosmeticsService собирает из него деталь и приваривает к персонажу.
	Когда появятся модели, поле visual заменится на assetModel — остальное не изменится.
]]

export type Visual = {
	shape: string, -- "Block" | "Ball" | "Cylinder"
	color: Color3,
	size: Vector3,
	offset: CFrame, -- относительно точки крепления
	material: Enum.Material?,
}

export type TrailVisual = {
	color: ColorSequence,
	lifetime: number,
	width: number,
}

export type ShopItem = {
	id: string,
	category: string, -- "hat" | "back" | "face" | "trail"
	title: string,
	price: number?,
	robuxProduct: number?,
	grantedBy: string?, -- например "letter_mastered:m"
	tier: number,
	unlockIsland: number,
	visual: Visual?,
	trail: TrailVisual?,
	icon: string, -- пока эмодзи, потом rbxassetid
}

local function hat(
	id: string,
	title: string,
	price: number,
	tier: number,
	icon: string,
	shape: string,
	color: Color3,
	size: Vector3,
	height: number
): ShopItem
	return {
		id = id,
		category = "hat",
		title = title,
		price = price,
		tier = tier,
		unlockIsland = 1,
		icon = icon,
		visual = {
			shape = shape,
			color = color,
			size = size,
			offset = CFrame.new(0, height, 0),
		},
	}
end

local Items: { [string]: ShopItem } = {
	-- === Головные уборы ===
	hat_cap = hat(
		"hat_cap",
		"Кепка",
		10,
		0,
		"🧢",
		"Block",
		Color3.fromRGB(220, 90, 80),
		Vector3.new(2.2, 0.5, 2.2),
		0.75
	),
	hat_bow = hat(
		"hat_bow",
		"Бантик",
		15,
		0,
		"🎀",
		"Block",
		Color3.fromRGB(240, 130, 190),
		Vector3.new(1.6, 0.6, 0.6),
		0.9
	),
	hat_stargazer = hat(
		"hat_stargazer",
		"Колпак звездочёта",
		25,
		0,
		"🎩",
		"Cylinder",
		Color3.fromRGB(90, 80, 200),
		Vector3.new(2.4, 1.6, 1.6),
		1.2
	),
	hat_ears = hat(
		"hat_ears",
		"Ушки",
		50,
		1,
		"🐰",
		"Block",
		Color3.fromRGB(250, 240, 230),
		Vector3.new(0.4, 1.8, 0.9),
		1.4
	),
	hat_helmet = hat(
		"hat_helmet",
		"Каска",
		80,
		1,
		"⛑️",
		"Ball",
		Color3.fromRGB(250, 200, 60),
		Vector3.new(2.4, 2.4, 2.4),
		0.5
	),
	hat_crown = hat(
		"hat_crown",
		"Корона",
		120,
		1,
		"👑",
		"Cylinder",
		Color3.fromRGB(255, 214, 102),
		Vector3.new(1.2, 2.2, 2.2),
		1.0
	),

	-- === Спина ===
	back_book = {
		id = "back_book",
		category = "back",
		title = "Рюкзак-азбука",
		price = 60,
		tier = 1,
		unlockIsland = 1,
		icon = "🎒",
		visual = {
			shape = "Block",
			color = Color3.fromRGB(200, 80, 60),
			size = Vector3.new(1.8, 2, 0.6),
			offset = CFrame.new(0, 0, 0.8),
		},
	},
	back_wings = {
		id = "back_wings",
		category = "back",
		title = "Крылья из букв",
		price = 200,
		tier = 2,
		unlockIsland = 1,
		icon = "🪽",
		visual = {
			shape = "Block",
			color = Color3.fromRGB(150, 220, 255),
			size = Vector3.new(5.5, 2.4, 0.3),
			offset = CFrame.new(0, 0.3, 0.7),
		},
	},

	-- === Лицо ===
	face_glasses = {
		id = "face_glasses",
		category = "face",
		title = "Очки",
		price = 35,
		tier = 0,
		unlockIsland = 1,
		icon = "🤓",
		visual = {
			shape = "Block",
			color = Color3.fromRGB(40, 40, 50),
			size = Vector3.new(2, 0.5, 0.2),
			offset = CFrame.new(0, 0.15, -0.6),
		},
	},
	face_mask = {
		id = "face_mask",
		category = "face",
		title = "Маска буквёнка",
		price = 90,
		tier = 1,
		unlockIsland = 1,
		icon = "🎭",
		visual = {
			shape = "Block",
			color = Color3.fromRGB(120, 200, 140),
			size = Vector3.new(2.1, 1.2, 0.25),
			offset = CFrame.new(0, 0, -0.62),
		},
	},

	-- === Следы ===
	trail_stardust = {
		id = "trail_stardust",
		category = "trail",
		title = "Звёздная пыль",
		price = 150,
		tier = 2,
		unlockIsland = 1,
		icon = "✨",
		trail = {
			color = ColorSequence.new(Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 180, 60)),
			lifetime = 1.2,
			width = 2,
		},
	},
	trail_rainbow = {
		id = "trail_rainbow",
		category = "trail",
		title = "Радуга",
		price = 300,
		tier = 2,
		unlockIsland = 1,
		icon = "🌈",
		trail = {
			color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 120)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 140, 255)),
			}),
			lifetime = 1.5,
			width = 2.4,
		},
	},
}

local Module = {}

Module.all = Items
Module.CATEGORIES = { "hat", "back", "face", "trail" }

function Module.get(id: string): ShopItem?
	return Items[id]
end

function Module.expect(id: string): ShopItem
	local item = Items[id]
	assert(item, `Shop: неизвестный предмет "{id}"`)
	return item
end

-- Витрина в стабильном порядке: сначала дешёвое, чтобы первое, что видит ребёнок,
-- он мог купить прямо сейчас.
function Module.ids(): { string }
	local ids: { string } = {}
	for id in Items do
		table.insert(ids, id)
	end
	table.sort(ids, function(a: string, b: string): boolean
		local ia, ib = Items[a], Items[b]
		local pa = ia.price or math.huge
		local pb = ib.price or math.huge
		if pa ~= pb then
			return pa < pb
		end
		return a < b
	end)
	return ids
end

function Module.count(): number
	local n = 0
	for _ in Items do
		n += 1
	end
	return n
end

return Module
