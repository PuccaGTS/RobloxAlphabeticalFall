--!strict
--[[
	Витрина магазина: 20 предметов — столько, сколько план первой играбельной
	версии (docs/17-CONTENT-PLAN.md § 6). Цены разбросаны по трём тирам: после
	первого же испытания по карману кепка, венок или усы, а ракета — это неделя.

	Правила (docs/04-ECONOMY.md):
	  · косметика НИЧЕГО не даёт в геймплее — только вид;
	  · у предмета ровно одно из: цена в ⭐ / покупка за Robux / выдача за прогресс;
	  · первая покупка должна быть по карману после первого же испытания (10 ⭐).

	Арта пока нет, поэтому каждый предмет описан рецептом примитивов (visual):
	CosmeticsService собирает из него деталь и приваривает к персонажу.
	Когда появятся модели, поле visual заменится на assetModel — остальное не изменится.
]]

--[[
	Одна деталь предмета. Предмет собирается из НЕСКОЛЬКИХ деталей: из одного куба
	не получается ни кепка, ни корона — получается куб на голове, что мы и увидели
	на первой примерке.
]]
export type Piece = {
	shape: string, -- "Block" | "Ball" | "Cylinder"
	color: Color3,
	size: Vector3,
	offset: CFrame, -- относительно точки крепления
	material: Enum.Material?,
	transparency: number?, -- стекло шлема и подобное; по умолчанию непрозрачно
}

export type Visual = { Piece }

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
	unlockStage: number,
	visual: Visual?,
	trail: TrailVisual?,
	icon: string, -- пока эмодзи, потом rbxassetid
}

local function piece(
	shape: string,
	color: Color3,
	size: Vector3,
	offset: CFrame,
	material: Enum.Material?
): Piece
	return { shape = shape, color = color, size = size, offset = offset, material = material }
end

-- Прозрачная деталь: стекло шлема видно, а лицо под ним — тоже.
local function glass(part: Piece, transparency: number): Piece
	part.transparency = transparency
	return part
end

local function hat(
	id: string,
	title: string,
	price: number,
	tier: number,
	icon: string,
	visual: Visual
): ShopItem
	return {
		id = id,
		category = "hat",
		title = title,
		price = price,
		tier = tier,
		unlockStage = 1,
		icon = icon,
		visual = visual,
	}
end

local GOLD = Color3.fromRGB(255, 214, 102)

local Items: { [string]: ShopItem } = {
	-- === Головные уборы ===
	-- Кепка = тулья + козырёк
	hat_cap = hat("hat_cap", "Кепка", 10, 0, "🧢", {
		piece("Block", Color3.fromRGB(220, 90, 80), Vector3.new(2.1, 0.7, 2.1), CFrame.new(0, 0.85, 0)),
		piece("Block", Color3.fromRGB(190, 70, 62), Vector3.new(2.1, 0.2, 1.2), CFrame.new(0, 0.55, -1.4)),
	}),
	-- Бантик = две петли + узелок
	hat_bow = hat("hat_bow", "Бантик", 15, 0, "🎀", {
		piece(
			"Block",
			Color3.fromRGB(240, 130, 190),
			Vector3.new(1.1, 0.9, 0.5),
			CFrame.new(-0.75, 1.05, 0) * CFrame.Angles(0, 0, math.rad(20))
		),
		piece(
			"Block",
			Color3.fromRGB(240, 130, 190),
			Vector3.new(1.1, 0.9, 0.5),
			CFrame.new(0.75, 1.05, 0) * CFrame.Angles(0, 0, math.rad(-20))
		),
		piece("Ball", Color3.fromRGB(250, 175, 215), Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 1.05, 0)),
	}),
	-- Колпак = поля + конус из сужающихся ярусов + звезда на макушке
	hat_stargazer = hat("hat_stargazer", "Колпак звездочёта", 25, 0, "🎩", {
		piece(
			"Cylinder",
			Color3.fromRGB(70, 62, 170),
			Vector3.new(0.3, 3, 3),
			CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90))
		),
		piece("Block", Color3.fromRGB(90, 80, 200), Vector3.new(1.7, 0.9, 1.7), CFrame.new(0, 1.25, 0)),
		piece("Block", Color3.fromRGB(105, 95, 215), Vector3.new(1.2, 0.9, 1.2), CFrame.new(0, 2.05, 0)),
		piece("Block", Color3.fromRGB(120, 110, 230), Vector3.new(0.7, 0.9, 0.7), CFrame.new(0, 2.8, 0)),
		piece("Ball", GOLD, Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, 3.4, 0), Enum.Material.Neon),
	}),
	-- Ушки = ободок + два уха
	hat_ears = hat("hat_ears", "Ушки", 50, 1, "🐰", {
		piece(
			"Cylinder",
			Color3.fromRGB(240, 230, 225),
			Vector3.new(0.35, 2.3, 2.3),
			CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(90))
		),
		piece(
			"Block",
			Color3.fromRGB(250, 240, 230),
			Vector3.new(0.45, 2, 0.9),
			CFrame.new(-0.7, 2, 0) * CFrame.Angles(0, 0, math.rad(12))
		),
		piece(
			"Block",
			Color3.fromRGB(250, 240, 230),
			Vector3.new(0.45, 2, 0.9),
			CFrame.new(0.7, 2, 0) * CFrame.Angles(0, 0, math.rad(-12))
		),
	}),
	-- Каска = купол + гребень + козырёк
	hat_helmet = hat("hat_helmet", "Каска", 80, 1, "⛑️", {
		piece("Ball", Color3.fromRGB(250, 200, 60), Vector3.new(2.4, 2, 2.4), CFrame.new(0, 0.75, 0)),
		piece("Block", Color3.fromRGB(230, 175, 45), Vector3.new(0.4, 0.5, 2.4), CFrame.new(0, 1.5, 0)),
		piece("Block", Color3.fromRGB(230, 175, 45), Vector3.new(2.4, 0.25, 1), CFrame.new(0, 0.45, -1.3)),
	}),
	-- Корона = обруч + пять зубцов
	hat_crown = hat("hat_crown", "Корона", 120, 1, "👑", {
		piece(
			"Cylinder",
			GOLD,
			Vector3.new(0.8, 2.3, 2.3),
			CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Enum.Material.Neon
		),
		piece("Block", GOLD, Vector3.new(0.4, 1, 0.4), CFrame.new(0, 1.8, -1), Enum.Material.Neon),
		piece("Block", GOLD, Vector3.new(0.4, 1.1, 0.4), CFrame.new(-0.95, 1.85, -0.3), Enum.Material.Neon),
		piece("Block", GOLD, Vector3.new(0.4, 1.1, 0.4), CFrame.new(0.95, 1.85, -0.3), Enum.Material.Neon),
		piece("Block", GOLD, Vector3.new(0.4, 1, 0.4), CFrame.new(-0.7, 1.8, 0.85), Enum.Material.Neon),
		piece("Block", GOLD, Vector3.new(0.4, 1, 0.4), CFrame.new(0.7, 1.8, 0.85), Enum.Material.Neon),
	}),

	-- Венок = зелёный обруч + пять цветков по кругу
	hat_flower = hat("hat_flower", "Венок", 20, 0, "🌼", {
		piece(
			"Cylinder",
			Color3.fromRGB(110, 180, 90),
			Vector3.new(0.3, 2.3, 2.3),
			CFrame.new(0, 0.85, 0) * CFrame.Angles(0, 0, math.rad(90))
		),
		piece("Ball", Color3.fromRGB(255, 220, 90), Vector3.new(0.55, 0.55, 0.55), CFrame.new(0, 1, -1.1)),
		piece(
			"Ball",
			Color3.fromRGB(250, 140, 190),
			Vector3.new(0.55, 0.55, 0.55),
			CFrame.new(-1.05, 1, -0.35)
		),
		piece(
			"Ball",
			Color3.fromRGB(255, 255, 255),
			Vector3.new(0.55, 0.55, 0.55),
			CFrame.new(1.05, 1, -0.35)
		),
		piece(
			"Ball",
			Color3.fromRGB(170, 140, 240),
			Vector3.new(0.55, 0.55, 0.55),
			CFrame.new(-0.65, 1, 0.9)
		),
		piece("Ball", Color3.fromRGB(255, 170, 90), Vector3.new(0.55, 0.55, 0.55), CFrame.new(0.65, 1, 0.9)),
	}),
	-- Поварской колпак = белый обод + пышная шапка
	hat_chef = hat("hat_chef", "Поварской колпак", 70, 1, "👨‍🍳", {
		piece("Block", Color3.fromRGB(245, 245, 245), Vector3.new(2.1, 0.7, 2.1), CFrame.new(0, 0.85, 0)),
		piece("Ball", Color3.fromRGB(255, 255, 255), Vector3.new(2.5, 1.9, 2.5), CFrame.new(0, 1.9, 0)),
	}),
	-- Шлем космонавта = прозрачный шар вокруг головы + белое кольцо у шеи
	hat_astronaut = hat("hat_astronaut", "Шлем космонавта", 250, 2, "🧑‍🚀", {
		glass(
			piece(
				"Ball",
				Color3.fromRGB(190, 225, 255),
				Vector3.new(2.9, 2.9, 2.9),
				CFrame.new(0, 0.15, 0),
				Enum.Material.Glass
			),
			0.6
		),
		piece(
			"Cylinder",
			Color3.fromRGB(240, 240, 245),
			Vector3.new(0.5, 2.6, 2.6),
			CFrame.new(0, -1.15, 0) * CFrame.Angles(0, 0, math.rad(90))
		),
		piece(
			"Ball",
			Color3.fromRGB(255, 90, 80),
			Vector3.new(0.35, 0.35, 0.35),
			CFrame.new(0, 1.55, 0),
			Enum.Material.Neon
		),
	}),

	-- === Спина ===
	-- Плащ = полотно за спиной, чуть отведённое назад, + застёжка
	back_cape = {
		id = "back_cape",
		category = "back",
		title = "Плащ",
		price = 45,
		tier = 0,
		unlockStage = 1,
		icon = "🦸",
		visual = {
			piece(
				"Block",
				Color3.fromRGB(210, 60, 70),
				Vector3.new(2.2, 3, 0.15),
				CFrame.new(0, -0.6, 0.75) * CFrame.Angles(math.rad(-10), 0, 0)
			),
			piece("Ball", GOLD, Vector3.new(0.45, 0.45, 0.45), CFrame.new(0, 0.9, 0.55), Enum.Material.Neon),
		},
	},
	-- Панцирь = зелёный купол + светлые пятна
	back_turtle = {
		id = "back_turtle",
		category = "back",
		title = "Черепаший панцирь",
		price = 110,
		tier = 1,
		unlockStage = 1,
		icon = "🐢",
		visual = {
			piece("Ball", Color3.fromRGB(90, 150, 80), Vector3.new(2.3, 2.4, 1.4), CFrame.new(0, 0, 0.85)),
			piece(
				"Block",
				Color3.fromRGB(160, 200, 110),
				Vector3.new(0.7, 0.7, 0.2),
				CFrame.new(0, 0.3, 1.52)
			),
			piece(
				"Block",
				Color3.fromRGB(160, 200, 110),
				Vector3.new(0.55, 0.55, 0.2),
				CFrame.new(-0.6, -0.4, 1.42)
			),
			piece(
				"Block",
				Color3.fromRGB(160, 200, 110),
				Vector3.new(0.55, 0.55, 0.2),
				CFrame.new(0.6, -0.4, 1.42)
			),
		},
	},
	-- Ракета = корпус + нос + крылышки + огонёк снизу
	back_rocket = {
		id = "back_rocket",
		category = "back",
		title = "Ракета",
		price = 350,
		tier = 2,
		unlockStage = 1,
		icon = "🚀",
		visual = {
			piece(
				"Cylinder",
				Color3.fromRGB(235, 235, 240),
				Vector3.new(2.4, 1.1, 1.1),
				CFrame.new(0, 0.2, 0.95) * CFrame.Angles(0, 0, math.rad(90))
			),
			piece("Ball", Color3.fromRGB(230, 80, 80), Vector3.new(1.1, 1.2, 1.1), CFrame.new(0, 1.5, 0.95)),
			piece(
				"Block",
				Color3.fromRGB(230, 80, 80),
				Vector3.new(1.8, 0.6, 0.2),
				CFrame.new(0, -0.8, 0.95)
			),
			piece(
				"Ball",
				Color3.fromRGB(255, 170, 60),
				Vector3.new(0.8, 0.9, 0.8),
				CFrame.new(0, -1.35, 0.95),
				Enum.Material.Neon
			),
		},
	},
	back_book = {
		id = "back_book",
		category = "back",
		title = "Рюкзак-азбука",
		price = 60,
		tier = 1,
		unlockStage = 1,
		icon = "🎒",
		visual = {
			piece("Block", Color3.fromRGB(200, 80, 60), Vector3.new(1.9, 2.1, 0.9), CFrame.new(0, 0, 0.9)),
			piece(
				"Block",
				Color3.fromRGB(240, 230, 210),
				Vector3.new(1.3, 1.4, 0.15),
				CFrame.new(0, 0.1, 1.4)
			),
			piece(
				"Block",
				Color3.fromRGB(160, 60, 45),
				Vector3.new(0.35, 1.8, 0.3),
				CFrame.new(-0.7, 0.1, 0.35)
			),
			piece(
				"Block",
				Color3.fromRGB(160, 60, 45),
				Vector3.new(0.35, 1.8, 0.3),
				CFrame.new(0.7, 0.1, 0.35)
			),
		},
	},
	back_wings = {
		id = "back_wings",
		category = "back",
		title = "Крылья из букв",
		price = 200,
		tier = 2,
		unlockStage = 1,
		icon = "🪽",
		visual = {
			piece(
				"Block",
				Color3.fromRGB(150, 220, 255),
				Vector3.new(2.6, 1.6, 0.25),
				CFrame.new(-1.6, 0.5, 0.7) * CFrame.Angles(0, math.rad(-18), math.rad(18)),
				Enum.Material.Neon
			),
			piece(
				"Block",
				Color3.fromRGB(150, 220, 255),
				Vector3.new(2.6, 1.6, 0.25),
				CFrame.new(1.6, 0.5, 0.7) * CFrame.Angles(0, math.rad(18), math.rad(-18)),
				Enum.Material.Neon
			),
			piece(
				"Block",
				Color3.fromRGB(200, 240, 255),
				Vector3.new(1.8, 1.1, 0.25),
				CFrame.new(-1.3, -0.6, 0.7) * CFrame.Angles(0, math.rad(-18), math.rad(32)),
				Enum.Material.Neon
			),
			piece(
				"Block",
				Color3.fromRGB(200, 240, 255),
				Vector3.new(1.8, 1.1, 0.25),
				CFrame.new(1.3, -0.6, 0.7) * CFrame.Angles(0, math.rad(18), math.rad(-32)),
				Enum.Material.Neon
			),
		},
	},

	-- === Лицо ===
	face_glasses = {
		id = "face_glasses",
		category = "face",
		title = "Очки",
		price = 35,
		tier = 0,
		unlockStage = 1,
		icon = "🤓",
		visual = {
			piece(
				"Cylinder",
				Color3.fromRGB(35, 35, 45),
				Vector3.new(0.12, 0.8, 0.8),
				CFrame.new(-0.45, 0.15, -0.62) * CFrame.Angles(0, math.rad(90), 0)
			),
			piece(
				"Cylinder",
				Color3.fromRGB(35, 35, 45),
				Vector3.new(0.12, 0.8, 0.8),
				CFrame.new(0.45, 0.15, -0.62) * CFrame.Angles(0, math.rad(90), 0)
			),
			piece(
				"Block",
				Color3.fromRGB(35, 35, 45),
				Vector3.new(0.5, 0.12, 0.12),
				CFrame.new(0, 0.15, -0.62)
			),
			piece(
				"Block",
				Color3.fromRGB(35, 35, 45),
				Vector3.new(0.12, 0.12, 0.9),
				CFrame.new(-0.8, 0.15, -0.25)
			),
			piece(
				"Block",
				Color3.fromRGB(35, 35, 45),
				Vector3.new(0.12, 0.12, 0.9),
				CFrame.new(0.8, 0.15, -0.25)
			),
		},
	},
	face_mask = {
		id = "face_mask",
		category = "face",
		title = "Маска буквёнка",
		price = 90,
		tier = 1,
		unlockStage = 1,
		icon = "🎭",
		visual = {
			piece(
				"Block",
				Color3.fromRGB(120, 200, 140),
				Vector3.new(2.1, 1.3, 0.25),
				CFrame.new(0, 0.1, -0.65)
			),
			piece(
				"Ball",
				Color3.fromRGB(255, 255, 255),
				Vector3.new(0.55, 0.55, 0.3),
				CFrame.new(-0.45, 0.3, -0.78)
			),
			piece(
				"Ball",
				Color3.fromRGB(255, 255, 255),
				Vector3.new(0.55, 0.55, 0.3),
				CFrame.new(0.45, 0.3, -0.78)
			),
			piece(
				"Block",
				Color3.fromRGB(90, 165, 110),
				Vector3.new(2.1, 0.25, 0.28),
				CFrame.new(0, -0.45, -0.66)
			),
		},
	},

	-- Усы = две половинки под носом, чуть вразлёт
	face_mustache = {
		id = "face_mustache",
		category = "face",
		title = "Весёлые усы",
		price = 25,
		tier = 0,
		unlockStage = 1,
		icon = "🥸",
		visual = {
			piece(
				"Block",
				Color3.fromRGB(80, 55, 40),
				Vector3.new(0.6, 0.2, 0.15),
				CFrame.new(-0.3, -0.2, -0.64) * CFrame.Angles(0, 0, math.rad(12))
			),
			piece(
				"Block",
				Color3.fromRGB(80, 55, 40),
				Vector3.new(0.6, 0.2, 0.15),
				CFrame.new(0.3, -0.2, -0.64) * CFrame.Angles(0, 0, math.rad(-12))
			),
		},
	},

	-- === Следы ===
	trail_snow = {
		id = "trail_snow",
		category = "trail",
		title = "Снежинки",
		price = 180,
		tier = 1,
		unlockStage = 1,
		icon = "❄️",
		trail = {
			color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 210, 255)),
			lifetime = 1.3,
			width = 2,
		},
	},
	trail_stardust = {
		id = "trail_stardust",
		category = "trail",
		title = "Звёздная пыль",
		price = 150,
		tier = 1,
		unlockStage = 1,
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
		unlockStage = 1,
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
