--!strict
--[[
	Витрина магазина: начиналась с 20 предметов первой играбельной версии
	(docs/17-CONTENT-PLAN.md § 6) и растёт к каталогу § 4. Цены разбросаны по тирам:
	после первого же испытания по карману кепка, венок или усы, ракета — это неделя,
	скины буквят — месяц.

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

--[[
	Эффект редкой вещи: частицы за ребёнком и, если задана, светящаяся лента.
	Редкое должно быть видно издалека — кепку не разглядишь с другого конца
	площади, а шлейф из звёзд видно сразу.

	particles — встроенная текстура Roblox (Config/Shop.PARTICLE_TEXTURES):
	чужие ассеты из каталога могут пропасть, встроенные — нет.
]]
export type ItemEffect = {
	particles: string, -- "sparkle" | "fire" | "smoke"
	color: ColorSequence,
	rate: number, -- частиц в секунду: для планшета держим до 20
	size: number,
	lightEmission: number?,
	trail: TrailVisual?, -- лента сзади, как у предметов-следов
}

--[[
	Скин буквёнка: во что одето его тело. Буква над головой остаётся цвета буквы —
	скин не должен мешать узнавать, чей это буквёнок (docs/04-ECONOMY.md § 4).
	rainbow — цвет тела плавно идёт по радуге: его крутит клиент, PetController.
]]
export type PetSkin = {
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	rainbow: boolean?,
}

export type ShopItem = {
	id: string,
	category: string, -- "hat" | "back" | "face" | "trail" | "petskin"
	title: string,
	price: number?,
	robuxProduct: number?,
	grantedBy: string?, -- например "letter_mastered:m"
	tier: number,
	unlockStage: number,
	visual: Visual?,
	trail: TrailVisual?,
	skin: PetSkin?,
	effect: ItemEffect?, -- шлейф редкой вещи, надевается вместе с ней
	-- Аксессуар каталога Roblox: надевается через HumanoidDescription (CosmeticsService).
	accessory: number?,
	-- Снят с продажи: в витрине только у того, кто уже купил, — купленное не отнимаем.
	retired: boolean?,
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

-- Предмет-аксессуар каталога: вместо рецепта из деталей — номер вещи Roblox.
local function worn(
	id: string,
	category: string,
	title: string,
	price: number,
	tier: number,
	icon: string,
	accessory: number
): ShopItem
	return {
		id = id,
		category = category,
		title = title,
		price = price,
		tier = tier,
		unlockStage = 1,
		icon = icon,
		accessory = accessory,
	}
end

-- Вещь каталога за задание недели номер week: не продаётся, выдаёт QuestService.
local function weekly(
	id: string,
	category: string,
	title: string,
	week: number,
	icon: string,
	accessory: number
): ShopItem
	return {
		id = id,
		category = category,
		title = title,
		grantedBy = `weekly:{week}`,
		tier = 2,
		unlockStage = 1,
		icon = icon,
		accessory = accessory,
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

	-- Цилиндр = поля + высокая тулья + красная лента
	hat_tophat = hat("hat_tophat", "Цилиндр", 40, 0, "🪄", {
		piece(
			"Cylinder",
			Color3.fromRGB(40, 40, 50),
			Vector3.new(0.2, 2.9, 2.9),
			CFrame.new(0, 0.65, 0) * CFrame.Angles(0, 0, math.rad(90))
		),
		piece(
			"Cylinder",
			Color3.fromRGB(45, 45, 58),
			Vector3.new(1.8, 1.9, 1.9),
			CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90))
		),
		piece(
			"Cylinder",
			Color3.fromRGB(210, 60, 70),
			Vector3.new(0.3, 1.95, 1.95),
			CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.rad(90))
		),
	}),
	-- Шапка с помпоном = купол + белый отворот + помпон
	hat_beanie = hat("hat_beanie", "Шапка с помпоном", 30, 0, "🧶", {
		piece("Ball", Color3.fromRGB(90, 140, 220), Vector3.new(2.3, 1.5, 2.3), CFrame.new(0, 0.8, 0)),
		piece(
			"Cylinder",
			Color3.fromRGB(245, 245, 250),
			Vector3.new(0.5, 2.35, 2.35),
			CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.rad(90))
		),
		piece("Ball", Color3.fromRGB(250, 250, 255), Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 1.65, 0)),
	}),
	-- Звёздная корона = фиолетовый обруч + пять золотых звёздочек-ромбиков + камень спереди
	hat_starcrown = hat("hat_starcrown", "Звёздная корона", 450, 2, "🌟", {
		piece(
			"Cylinder",
			Color3.fromRGB(130, 90, 200),
			Vector3.new(0.6, 2.3, 2.3),
			CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.rad(90))
		),
		piece(
			"Block",
			GOLD,
			Vector3.new(0.55, 0.55, 0.15),
			CFrame.new(0, 1.65, -1.05) * CFrame.Angles(0, 0, math.rad(45)),
			Enum.Material.Neon
		),
		piece(
			"Block",
			GOLD,
			Vector3.new(0.5, 0.5, 0.15),
			CFrame.new(-1, 1.6, -0.35) * CFrame.Angles(0, math.rad(70), math.rad(45)),
			Enum.Material.Neon
		),
		piece(
			"Block",
			GOLD,
			Vector3.new(0.5, 0.5, 0.15),
			CFrame.new(1, 1.6, -0.35) * CFrame.Angles(0, math.rad(-70), math.rad(45)),
			Enum.Material.Neon
		),
		piece(
			"Block",
			GOLD,
			Vector3.new(0.45, 0.45, 0.15),
			CFrame.new(-0.65, 1.55, 0.85) * CFrame.Angles(0, math.rad(140), math.rad(45)),
			Enum.Material.Neon
		),
		piece(
			"Block",
			GOLD,
			Vector3.new(0.45, 0.45, 0.15),
			CFrame.new(0.65, 1.55, 0.85) * CFrame.Angles(0, math.rad(-140), math.rad(45)),
			Enum.Material.Neon
		),
		piece(
			"Ball",
			Color3.fromRGB(120, 220, 255),
			Vector3.new(0.4, 0.4, 0.4),
			CFrame.new(0, 0.95, -1.18),
			Enum.Material.Neon
		),
	}),

	--[[
		Награды серии буквы дня (docs/03-CHALLENGES.md § 7). Не продаются: витрина
		показывает их целью «🔥 7 дней», а выдаёт DailyLetterService, когда рекорд
		серии дорос. Золото и лучи — тот же солнечный знак, что на камне буквы дня.
	]]
	-- Солнечная шляпа = широкие поля + тулья + солнце на макушке с лучами
	hat_sun = {
		id = "hat_sun",
		category = "hat",
		title = "Солнечная шляпа",
		grantedBy = "daily_streak:7",
		tier = 2,
		unlockStage = 1,
		icon = "🌞",
		visual = {
			piece(
				"Cylinder",
				Color3.fromRGB(245, 215, 130),
				Vector3.new(0.25, 3.4, 3.4),
				CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90))
			),
			piece(
				"Cylinder",
				Color3.fromRGB(235, 195, 100),
				Vector3.new(1, 2.1, 2.1),
				CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90))
			),
			piece("Ball", GOLD, Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, 2.05, 0), Enum.Material.Neon),
			piece("Block", GOLD, Vector3.new(1.7, 0.15, 0.15), CFrame.new(0, 2.05, 0), Enum.Material.Neon),
			piece(
				"Block",
				GOLD,
				Vector3.new(1.7, 0.15, 0.15),
				CFrame.new(0, 2.05, 0) * CFrame.Angles(0, math.rad(90), 0),
				Enum.Material.Neon
			),
		},
	},

	--[[
		Вещи из сундуков в парке (Config/Chests). Не продаются: в витрине видно,
		что они есть и где искать, — «🗝 в парке». Внутри сундука всегда одна
		и та же вещь, случайности нет.
	]]
	-- Шляпка-мухомор = красная шляпка с белыми крапинками + ножка-обод
	hat_mushroom = {
		id = "hat_mushroom",
		category = "hat",
		title = "Шляпка-мухомор",
		grantedBy = "chest:chest_pines",
		tier = 1,
		unlockStage = 1,
		icon = "🍄",
		visual = {
			piece(
				"Cylinder",
				Color3.fromRGB(245, 235, 215),
				Vector3.new(0.5, 2, 2),
				CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
			),
			piece("Ball", Color3.fromRGB(215, 55, 50), Vector3.new(3, 1.6, 3), CFrame.new(0, 1.35, 0)),
			piece(
				"Ball",
				Color3.fromRGB(255, 255, 255),
				Vector3.new(0.4, 0.4, 0.4),
				CFrame.new(0.6, 2.05, -0.4)
			),
			piece(
				"Ball",
				Color3.fromRGB(255, 255, 255),
				Vector3.new(0.35, 0.35, 0.35),
				CFrame.new(-0.7, 1.9, 0.3)
			),
			piece(
				"Ball",
				Color3.fromRGB(255, 255, 255),
				Vector3.new(0.3, 0.3, 0.3),
				CFrame.new(0.1, 2.1, 0.7)
			),
		},
	},

	-- Облачко из сундука на облачном острове: пушистая тучка над головой, с глазками и щёчками.
	hat_cloud = {
		id = "hat_cloud",
		category = "hat",
		title = "Облачко",
		grantedBy = "chest:chest_sky",
		tier = 2,
		unlockStage = 1,
		icon = "☁️",
		visual = {
			piece("Ball", Color3.fromRGB(255, 255, 255), Vector3.new(2.3, 2.3, 2.3), CFrame.new(0, 2.5, 0)),
			piece(
				"Ball",
				Color3.fromRGB(250, 252, 255),
				Vector3.new(1.6, 1.6, 1.6),
				CFrame.new(-1.2, 2.2, 0.1)
			),
			piece(
				"Ball",
				Color3.fromRGB(250, 252, 255),
				Vector3.new(1.6, 1.6, 1.6),
				CFrame.new(1.2, 2.2, 0.1)
			),
			piece(
				"Ball",
				Color3.fromRGB(240, 245, 255),
				Vector3.new(1.5, 1.5, 1.5),
				CFrame.new(0.5, 3.3, 0.3)
			),
			piece(
				"Ball",
				Color3.fromRGB(240, 245, 255),
				Vector3.new(1.3, 1.3, 1.3),
				CFrame.new(-0.6, 3.2, 0.3)
			),
			piece(
				"Ball",
				Color3.fromRGB(45, 45, 70),
				Vector3.new(0.25, 0.25, 0.25),
				CFrame.new(-0.4, 2.65, -1.1)
			),
			piece(
				"Ball",
				Color3.fromRGB(45, 45, 70),
				Vector3.new(0.25, 0.25, 0.25),
				CFrame.new(0.4, 2.65, -1.1)
			),
			piece(
				"Ball",
				Color3.fromRGB(255, 160, 185),
				Vector3.new(0.35, 0.35, 0.35),
				CFrame.new(-0.75, 2.35, -0.95)
			),
			piece(
				"Ball",
				Color3.fromRGB(255, 160, 185),
				Vector3.new(0.35, 0.35, 0.35),
				CFrame.new(0.75, 2.35, -0.95)
			),
			piece(
				"Block",
				Color3.fromRGB(45, 45, 70),
				Vector3.new(0.4, 0.08, 0.06),
				CFrame.new(0, 2.3, -1.12)
			),
		},
	},

	-- Кристальная корона из грота: золотой обруч и светящиеся кристаллы разных цветов.
	hat_crystal = {
		id = "hat_crystal",
		category = "hat",
		title = "Кристальная корона",
		grantedBy = "chest:chest_grotto",
		tier = 2,
		unlockStage = 1,
		icon = "💎",
		visual = {
			piece(
				"Cylinder",
				GOLD,
				Vector3.new(0.5, 2.3, 2.3),
				CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Enum.Material.Metal
			),
			glass(
				piece(
					"Block",
					Color3.fromRGB(190, 140, 255),
					Vector3.new(0.5, 1.5, 0.5),
					CFrame.new(0, 1.9, -1.05) * CFrame.Angles(0, math.rad(45), 0),
					Enum.Material.Neon
				),
				0.15
			),
			glass(
				piece(
					"Block",
					Color3.fromRGB(120, 220, 255),
					Vector3.new(0.42, 1.15, 0.42),
					CFrame.new(-0.85, 1.7, -0.6) * CFrame.Angles(0, math.rad(45), math.rad(12)),
					Enum.Material.Neon
				),
				0.15
			),
			glass(
				piece(
					"Block",
					Color3.fromRGB(255, 150, 200),
					Vector3.new(0.42, 1.15, 0.42),
					CFrame.new(0.85, 1.7, -0.6) * CFrame.Angles(0, math.rad(45), math.rad(-12)),
					Enum.Material.Neon
				),
				0.15
			),
			glass(
				piece(
					"Block",
					Color3.fromRGB(140, 240, 170),
					Vector3.new(0.38, 0.95, 0.38),
					CFrame.new(-0.8, 1.6, 0.65) * CFrame.Angles(0, math.rad(45), math.rad(10)),
					Enum.Material.Neon
				),
				0.15
			),
			glass(
				piece(
					"Block",
					Color3.fromRGB(255, 225, 120),
					Vector3.new(0.38, 0.95, 0.38),
					CFrame.new(0.8, 1.6, 0.65) * CFrame.Angles(0, math.rad(45), math.rad(-10)),
					Enum.Material.Neon
				),
				0.15
			),
		},
	},

	-- === Спина ===
	-- Рюкзак-ёжик = коричневое тельце + иголки веером + носик
	back_hedgehog = {
		id = "back_hedgehog",
		category = "back",
		title = "Рюкзак-ёжик",
		grantedBy = "chest:chest_pond",
		tier = 1,
		unlockStage = 1,
		icon = "🦔",
		visual = {
			piece("Ball", Color3.fromRGB(160, 120, 85), Vector3.new(1.9, 1.9, 1.3), CFrame.new(0, 0, 0.9)),
			piece(
				"Block",
				Color3.fromRGB(95, 70, 50),
				Vector3.new(0.3, 0.9, 0.3),
				CFrame.new(-0.55, 0.75, 1.2) * CFrame.Angles(math.rad(-30), 0, math.rad(25))
			),
			piece(
				"Block",
				Color3.fromRGB(95, 70, 50),
				Vector3.new(0.3, 1, 0.3),
				CFrame.new(0, 0.85, 1.25) * CFrame.Angles(math.rad(-30), 0, 0)
			),
			piece(
				"Block",
				Color3.fromRGB(95, 70, 50),
				Vector3.new(0.3, 0.9, 0.3),
				CFrame.new(0.55, 0.75, 1.2) * CFrame.Angles(math.rad(-30), 0, math.rad(-25))
			),
			piece("Ball", Color3.fromRGB(40, 30, 30), Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, -0.3, 1.6)),
		},
	},
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

	-- Фонарик светлячков = палочка через плечо + банка со светящимися светлячками + крышка
	back_firefly_jar = {
		id = "back_firefly_jar",
		category = "back",
		title = "Фонарик светлячков",
		grantedBy = "chest:chest_secret",
		tier = 2,
		unlockStage = 1,
		icon = "🏮",
		visual = {
			piece(
				"Cylinder",
				Color3.fromRGB(150, 105, 70),
				Vector3.new(3.4, 0.22, 0.22),
				CFrame.new(0.9, 1.2, 0.75) * CFrame.Angles(0, 0, math.rad(55)),
				Enum.Material.Wood
			),
			glass(
				piece(
					"Cylinder",
					Color3.fromRGB(200, 240, 220),
					Vector3.new(1.3, 1.1, 1.1),
					CFrame.new(1.95, 1.75, 0.95) * CFrame.Angles(0, 0, math.rad(90)),
					Enum.Material.Glass
				),
				0.45
			),
			piece(
				"Cylinder",
				Color3.fromRGB(240, 190, 80),
				Vector3.new(0.25, 1.2, 1.2),
				CFrame.new(1.95, 2.45, 0.95) * CFrame.Angles(0, 0, math.rad(90)),
				Enum.Material.Metal
			),
			piece(
				"Ball",
				Color3.fromRGB(230, 255, 120),
				Vector3.new(0.35, 0.35, 0.35),
				CFrame.new(1.8, 1.55, 0.95),
				Enum.Material.Neon
			),
			piece(
				"Ball",
				Color3.fromRGB(255, 240, 140),
				Vector3.new(0.3, 0.3, 0.3),
				CFrame.new(2.15, 1.85, 0.8),
				Enum.Material.Neon
			),
			piece(
				"Ball",
				Color3.fromRGB(200, 255, 150),
				Vector3.new(0.28, 0.28, 0.28),
				CFrame.new(1.9, 2.05, 1.1),
				Enum.Material.Neon
			),
		},
	},

	-- Воздушный шарик = ниточка от плеча + красный шар + узелок
	back_balloon = {
		id = "back_balloon",
		category = "back",
		title = "Воздушный шарик",
		price = 140,
		tier = 1,
		unlockStage = 1,
		icon = "🎈",
		visual = {
			piece(
				"Block",
				Color3.fromRGB(245, 245, 245),
				Vector3.new(0.08, 4, 0.08),
				CFrame.new(0.9, 2.4, 0.9)
			),
			piece(
				"Ball",
				Color3.fromRGB(235, 70, 80),
				Vector3.new(0.3, 0.3, 0.3),
				CFrame.new(0.9, 4.45, 0.9)
			),
			piece(
				"Ball",
				Color3.fromRGB(240, 80, 90),
				Vector3.new(1.8, 2.1, 1.8),
				CFrame.new(0.9, 5.55, 0.9)
			),
		},
	},
	-- Ранец = короб + клапан + золотая застёжка
	back_satchel = {
		id = "back_satchel",
		category = "back",
		title = "Ранец",
		price = 55,
		tier = 1,
		unlockStage = 1,
		icon = "🎒",
		visual = {
			piece("Block", Color3.fromRGB(80, 160, 110), Vector3.new(1.8, 2, 0.8), CFrame.new(0, -0.1, 0.85)),
			piece(
				"Block",
				Color3.fromRGB(60, 130, 90),
				Vector3.new(1.85, 0.8, 0.85),
				CFrame.new(0, 0.65, 0.9)
			),
			piece("Block", GOLD, Vector3.new(0.4, 0.3, 0.1), CFrame.new(0, 0.4, 1.33), Enum.Material.Neon),
		},
	},

	-- === Лицо ===
	-- Звёздные очки = две жёлтые звёздочки-ромба + перемычка
	face_stars = {
		id = "face_stars",
		category = "face",
		title = "Звёздные очки",
		price = 75,
		tier = 1,
		unlockStage = 1,
		icon = "🤩",
		visual = {
			piece(
				"Block",
				Color3.fromRGB(255, 215, 80),
				Vector3.new(0.65, 0.65, 0.12),
				CFrame.new(-0.45, 0.15, -0.62) * CFrame.Angles(0, 0, math.rad(45)),
				Enum.Material.Neon
			),
			piece(
				"Block",
				Color3.fromRGB(255, 215, 80),
				Vector3.new(0.65, 0.65, 0.12),
				CFrame.new(0.45, 0.15, -0.62) * CFrame.Angles(0, 0, math.rad(45)),
				Enum.Material.Neon
			),
			piece(
				"Block",
				Color3.fromRGB(230, 90, 150),
				Vector3.new(0.3, 0.1, 0.1),
				CFrame.new(0, 0.15, -0.63)
			),
		},
	},
	-- Бандана = платок на шее спереди + узелок сзади
	face_bandana = {
		id = "face_bandana",
		category = "face",
		title = "Бандана",
		price = 45,
		tier = 0,
		unlockStage = 1,
		icon = "🧣",
		visual = {
			piece(
				"Block",
				Color3.fromRGB(215, 60, 60),
				Vector3.new(1.4, 0.7, 0.15),
				CFrame.new(0, -0.55, -0.62) * CFrame.Angles(math.rad(-10), 0, 0)
			),
			piece(
				"Ball",
				Color3.fromRGB(190, 45, 45),
				Vector3.new(0.35, 0.35, 0.35),
				CFrame.new(0, -0.45, 0.62)
			),
		},
	},
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
	--[[
		Скины буквят — тир T3, «редкие» (docs/04-ECONOMY.md § 3, § 4). Сами буквята
		не продаются никогда: скин меняет только наряд тех, кого ребёнок уже заработал
		учёбой. Один скин на всех буквят сразу — выбирать скин для каждой из 33 букв
		пятилетке не нужно.
	]]
	skin_ice = {
		id = "skin_ice",
		category = "petskin",
		title = "Ледяные буквята",
		price = 500,
		tier = 3,
		unlockStage = 1,
		icon = "🧊",
		skin = { color = Color3.fromRGB(170, 225, 255), material = Enum.Material.Glass, transparency = 0.15 },
	},
	skin_gold = {
		id = "skin_gold",
		category = "petskin",
		title = "Золотые буквята",
		price = 650,
		tier = 3,
		unlockStage = 1,
		icon = "🥇",
		skin = { color = Color3.fromRGB(255, 200, 70), material = Enum.Material.Foil },
	},
	skin_fire = {
		id = "skin_fire",
		category = "petskin",
		title = "Огненные буквята",
		price = 850,
		tier = 3,
		unlockStage = 1,
		icon = "🔥",
		skin = { color = Color3.fromRGB(255, 130, 50), material = Enum.Material.Neon },
	},
	-- Награда за 30 дней серии буквы дня (docs/03-CHALLENGES.md § 7): не продаётся.
	skin_rainbow = {
		id = "skin_rainbow",
		category = "petskin",
		title = "Радужные буквята",
		grantedBy = "daily_streak:30",
		tier = 3,
		unlockStage = 1,
		icon = "🌈",
		skin = { color = Color3.fromRGB(255, 120, 120), material = Enum.Material.Neon, rainbow = true },
	},
	trail_petals = {
		id = "trail_petals",
		category = "trail",
		title = "Лепестки",
		price = 160,
		tier = 1,
		unlockStage = 1,
		icon = "🌸",
		trail = {
			color = ColorSequence.new(Color3.fromRGB(255, 200, 225), Color3.fromRGB(240, 120, 170)),
			lifetime = 1.3,
			width = 2,
		},
	},
	trail_bubbles = {
		id = "trail_bubbles",
		category = "trail",
		title = "Пузырьки",
		price = 120,
		tier = 1,
		unlockStage = 1,
		icon = "🫧",
		trail = {
			color = ColorSequence.new(Color3.fromRGB(200, 240, 255), Color3.fromRGB(120, 200, 240)),
			lifetime = 1.1,
			width = 1.8,
		},
	},
	trail_notes = {
		id = "trail_notes",
		category = "trail",
		title = "Ноты",
		price = 220,
		tier = 2,
		unlockStage = 1,
		icon = "🎵",
		trail = {
			color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 120, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 200, 220)),
			}),
			lifetime = 1.4,
			width = 2.2,
		},
	},
	-- Из сундука на лугу, см. hat_mushroom.
	trail_leaves = {
		id = "trail_leaves",
		category = "trail",
		title = "Листопад",
		grantedBy = "chest:chest_meadow",
		tier = 1,
		unlockStage = 1,
		icon = "🍂",
		trail = {
			color = ColorSequence.new(Color3.fromRGB(240, 180, 60), Color3.fromRGB(200, 90, 40)),
			lifetime = 1.4,
			width = 2.2,
		},
	},
	-- Награда за 14 дней серии буквы дня, см. hat_sun.
	trail_sun = {
		id = "trail_sun",
		category = "trail",
		title = "Солнечные зайчики",
		grantedBy = "daily_streak:14",
		tier = 2,
		unlockStage = 1,
		icon = "🔆",
		trail = {
			color = ColorSequence.new(Color3.fromRGB(255, 250, 200), Color3.fromRGB(255, 190, 40)),
			lifetime = 1.6,
			width = 2.6,
		},
	},

	--[[
		=== Настоящие аксессуары из каталога Roblox ===

		Кубики на голове на первой проверке назвали прямо: «кепка — ужас».
		Эти вещи — бесплатные аксессуары каталога Roblox. Они не покупаются
		и не дарятся ребёнку в каталоге: игра только надевает их внутри себя
		через HumanoidDescription, как примерочные в других играх, и снимает
		при выходе. Детские, без брендов и без оружия — отобраны руками.

		Если Roblox вещь не выдал (сняли с продажи, сбой сети), CosmeticsService
		ничего не ломает, но и на голове ничего не появится. Поэтому в наборе
		только бесплатные аксессуары с сотнями и тысячами добавлений в избранное:
		такие не пропадают. Раз в релиз набор проверяется по сценарию
		docs/HOW-TO-CHECK.md § 3.3.
	]]
	hat_birthday = worn(
		"hat_birthday",
		"hat",
		"Праздничный колпак",
		15,
		0,
		"🥳",
		17104079938
	),
	hat_bunny_ears = worn("hat_bunny_ears", "hat", "Заячьи уши", 20, 0, "🐰", 15178958628),
	hat_strawberry = worn(
		"hat_strawberry",
		"hat",
		"Шляпа-клубничка",
		35,
		0,
		"🍓",
		140455402501289
	),
	hat_cat_headphones = worn(
		"hat_cat_headphones",
		"hat",
		"Кошачьи наушники",
		40,
		0,
		"🐱",
		15109037058
	),
	hat_cowboy = worn("hat_cowboy", "hat", "Ковбойская шляпа", 45, 0, "🤠", 16154545741),
	hat_whale = worn("hat_whale", "hat", "Шапка-кит", 60, 1, "🐳", 15109046743),
	hat_halo = worn("hat_halo", "hat", "Нимб", 80, 1, "😇", 13947756131),
	hat_helicopter = worn("hat_helicopter", "hat", "Шапка-вертолёт", 90, 1, "🚁", 14972111489),
	hat_axolotl = worn("hat_axolotl", "hat", "Маска аксолотля", 120, 1, "🦎", 14751926555),
	hat_penguin = worn("hat_penguin", "hat", "Пингвин на голове", 140, 1, "🐧", 15685894569),
	hat_lion = worn("hat_lion", "hat", "Грива льва", 160, 1, "🦁", 15109042495),
	hat_sloth = worn("hat_sloth", "hat", "Ленивец на голове", 190, 1, "🦥", 18617727385),
	hat_robot = worn("hat_robot", "hat", "Голова робота", 250, 2, "🤖", 15050144871),
	hat_ice_crown = worn("hat_ice_crown", "hat", "Ледяная корона", 350, 2, "❄", 14738277949),
	back_leaf_umbrella = worn(
		"back_leaf_umbrella",
		"back",
		"Зонтик-листик",
		30,
		0,
		"🍃",
		14624345249
	),
	back_dog = worn("back_dog", "back", "Рюкзак-собачка", 40, 0, "🐶", 98752422639730),
	back_bunny = worn("back_bunny", "back", "Рюкзак-зайчик", 55, 1, "🐇", 14716529763),
	back_shark = worn("back_shark", "back", "Рюкзак-акула", 75, 1, "🦈", 15109044342),
	back_panda = worn("back_panda", "back", "Рюкзак-панда", 95, 1, "🐼", 18617852255),
	back_butterfly = worn(
		"back_butterfly",
		"back",
		"Крылья бабочки",
		180,
		1,
		"🦋",
		15109033959
	),
	back_angel = worn("back_angel", "back", "Крылья ангела", 300, 2, "🪽", 95651415246994),
	face_daisy = worn("face_daisy", "face", "Очки-ромашки", 20, 0, "🌼", 14896027020),
	face_aviators = worn("face_aviators", "face", "Очки лётчика", 30, 0, "🕶", 376526673),

	--[[
		Награды задания недели (Logic/Quests.WEEK_REWARDS): по одной за каждую
		выполненную неделю, по порядку. Не продаются — в витрине видно, что они
		есть и как их получить: «🏆 за неделю». Примерены на аватаре (сценарий tryon).
	]]
	hat_dino = weekly("hat_dino", "hat", "Капюшон-динозавр", 1, "🦖", 134363188636903),
	back_bear = weekly("back_bear", "back", "Мишка за спиной", 2, "🧸", 113819362696768),
	hat_dragon = weekly("hat_dragon", "hat", "Рожки дракончика", 3, "💗", 108272738153285),
	hat_whaleshark = weekly("hat_whaleshark", "hat", "Капюшон-акула", 4, "🦈", 18318294168),
	hat_goldshark = weekly("hat_goldshark", "hat", "Золотая акула", 5, "🏆", 17701414079),
}

--[[
	Редкие вещи со шлейфом. Каждой — свой: корона сыплет звёздами, ракета
	дымит огнём, ледяная корона метёт снегом, крылья ангела оставляют
	радужную ленту. У «Радуги» из следов теперь все семь цветов и искры.
]]
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 160, 60)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 220, 110)),
	ColorSequenceKeypoint.new(0.67, Color3.fromRGB(80, 190, 255)),
	ColorSequenceKeypoint.new(0.83, Color3.fromRGB(90, 110, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 100, 255)),
})

local EFFECTS: { [string]: ItemEffect } = {
	hat_starcrown = {
		particles = "sparkle",
		color = ColorSequence.new(GOLD, Color3.fromRGB(255, 170, 60)),
		rate = 14,
		size = 0.7,
		lightEmission = 1,
		trail = {
			color = ColorSequence.new(Color3.fromRGB(255, 230, 140), Color3.fromRGB(180, 120, 255)),
			lifetime = 0.8,
			width = 1.2,
		},
	},
	hat_ice_crown = {
		particles = "sparkle",
		color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 210, 255)),
		rate = 16,
		size = 0.5,
		lightEmission = 0.6,
	},
	hat_sun = {
		particles = "sparkle",
		color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 190, 70)),
		rate = 10,
		size = 0.6,
		lightEmission = 1,
	},
	back_rocket = {
		particles = "fire",
		color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 110, 50)),
		rate = 18,
		size = 0.8,
		lightEmission = 0.8,
		trail = {
			color = ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(200, 200, 210)),
			lifetime = 0.9,
			width = 1.4,
		},
	},
	back_angel = {
		particles = "sparkle",
		color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 235, 180)),
		rate = 10,
		size = 0.6,
		lightEmission = 1,
		trail = { color = RAINBOW, lifetime = 1.6, width = 2.4 },
	},
	-- Из облачка сыплются голубые искорки, как капельки.
	hat_cloud = {
		particles = "sparkle",
		color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 200, 255)),
		rate = 8,
		size = 0.45,
		lightEmission = 0.8,
	},
	-- Кристальная корона переливается искрами всех цветов грота.
	hat_crystal = {
		particles = "sparkle",
		color = ColorSequence.new(Color3.fromRGB(190, 140, 255), Color3.fromRGB(120, 220, 255)),
		rate = 10,
		size = 0.5,
		lightEmission = 1,
	},
	back_firefly_jar = {
		particles = "sparkle",
		color = ColorSequence.new(Color3.fromRGB(230, 255, 130), Color3.fromRGB(255, 220, 110)),
		rate = 8,
		size = 0.45,
		lightEmission = 1,
	},
	trail_rainbow = {
		particles = "sparkle",
		color = RAINBOW,
		rate = 12,
		size = 0.6,
		lightEmission = 1,
	},
}

for id, effect in EFFECTS do
	local item = Items[id]
	assert(item, `Shop: эффект у неизвестного предмета "{id}"`)
	item.effect = effect
end

--[[
	Настоящие вещи вместо рецептов из деталей. На проверке 24.09.2026 венок назвали
	«диск и шары», бантик — «два кубика и шар», колпак — «кубики друг на друге»,
	а кепку не было видно из-за волос. Каждая вещь здесь примерена на аватаре
	с пышной причёской (сценарий стенда tryon) и видна поверх волос.

	Номер предмета и деньги ребёнка не меняются: купленное остаётся купленным,
	только выглядит теперь как вещь. Где смысл вещи другой, другое и название:
	котёнок с бантиком, шляпа-лягушка, шлем-пчёлка. Рецепт из деталей остаётся
	запасным — если Roblox вещь не выдал, ребёнок всё равно не с пустой головой.
]]
local CATALOG_LOOKS: { [string]: { accessory: number, title: string?, icon: string? } } = {
	hat_cap = { accessory = 17895835574 }, -- светлая кепка-тракер, козырёк поверх чёлки
	hat_bow = { accessory = 86732225534172, title = "Котёнок с бантиком", icon = "🐱" },
	hat_flower = { accessory = 111804776065213, icon = "🌹" }, -- венок из красных роз
	hat_stargazer = { accessory = 18997207632, icon = "🧙" }, -- розовый колпак со звездой и искрами
	hat_beanie = { accessory = 113370715265938, title = "Вязаная шапка" },
	hat_ears = { accessory = 136388222545618, title = "Кошачьи ушки", icon = "🐱" },
	hat_helmet = { accessory = 120932533807756, title = "Шлем-пчёлка", icon = "🐝" },
	hat_crown = { accessory = 14943768260 }, -- золотая корона с зубцами
	hat_chef = { accessory = 90744205836468, title = "Шляпа-лягушка", icon = "🐸" },
	hat_starcrown = { accessory = 139398905874156 },
	hat_sun = { accessory = 137899557081532 }, -- белая панама путешественника
	hat_cloud = { accessory = 101884624083489 }, -- тучка с месяцем и звёздочками
	hat_crystal = { accessory = 98309642235565 },
	back_cape = { accessory = 15495472290 }, -- тёмно-синий плащ до пят
	back_turtle = { accessory = 118223758771060 },
	back_book = { accessory = 14614524189, title = "Школьный рюкзак", icon = "🎒" },
	back_wings = { accessory = 80631944181023, title = "Крылья феи", icon = "🧚" },
	back_balloon = { accessory = 15251317166, title = "Воздушные шарики", icon = "🎈" },
	back_satchel = { accessory = 101934260265989 }, -- зелёный ранец с бантом
	-- 🥸 и 🎩 в витрине рисовались пустым квадратом и тёмным пятном: значки поновее шрифта.
	face_mustache = { accessory = 73502059591702, icon = "🧔" },
	face_glasses = { accessory = 100708494276937 }, -- круглые очки в тонкой оправе
	face_stars = { accessory = 139675453532820 },
	face_bandana = { accessory = 14895882271 },
	face_mask = { accessory = 15736791518, title = "Тёмные очки", icon = "🕶" },
	--[[
		Последние вещи из деталей. На проверке 25.09.2026 рюкзак-ёжик назвали
		«нелепо, непонятно что это ёжик»: ёжика в каталоге нет, поэтому в
		сундуке у пруда теперь плюшевый котёнок. Фонарик светлячков стал
		крыльями светлячка — искры-светлячки остались, — ракета стала
		реактивным ранцем с тем же огнём, мухомор — цветком-ростком.
	]]
	hat_tophat = { accessory = 18987826111 }, -- чёрный цилиндр с красной лентой
	hat_mushroom = { accessory = 15529427786, title = "Цветок-росток", icon = "🌼" },
	back_hedgehog = { accessory = 117304949593457, title = "Рюкзак-котёнок", icon = "🐱" },
	back_rocket = { accessory = 14751932277, title = "Реактивный ранец" },
	back_firefly_jar = { accessory = 98927447898825, title = "Крылья светлячка", icon = "✨" },
}

for id, look in CATALOG_LOOKS do
	local item = Items[id]
	assert(item, `Shop: вещь каталога у неизвестного предмета "{id}"`)
	item.accessory = look.accessory
	item.title = look.title or item.title
	item.icon = look.icon or item.icon
end
Items.trail_rainbow.trail = { color = RAINBOW, lifetime = 1.6, width = 2.6 }

--[[
	Шлем космонавта из деталей был кубиком со стеклом, а настоящего детского
	шлема в бесплатном каталоге нет: вещь снята с продажи.
]]
Items.hat_astronaut.retired = true

local Module = {}

local STREAK_PREFIX = "daily_streak:"

-- Текстуры частиц встроены в клиент Roblox: грузить и одобрять их не нужно.
Module.PARTICLE_TEXTURES = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

Module.all = Items
Module.CATEGORIES = { "hat", "back", "face", "trail", "petskin" }

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

--[[
	Витрина, какой её видит ребёнок. hideRobux — переключатель родительского
	режима (docs/13-PARENT-MODE.md § 3): семьям, где за настоящие деньги
	не покупают ничего, незачем и показывать такие карточки — ребёнок
	просит то, что видит.

	Прячется только показ. Купленное за Robux раньше остаётся в гардеробе
	и надетым: отнимать оплаченное настройка не имеет права.
]]
function Module.visibleIds(hideRobux: boolean?): { string }
	local ids: { string } = {}
	for _, id in Module.ids() do
		if not (hideRobux and Items[id].robuxProduct) then
			table.insert(ids, id)
		end
	end
	return ids
end

-- За какую по счёту неделю выдаётся предмет (задание недели), или nil.
function Module.weekNumber(item: ShopItem): number?
	local grantedBy = item.grantedBy
	if not grantedBy or string.sub(grantedBy, 1, 7) ~= "weekly:" then
		return nil
	end
	return tonumber(string.sub(grantedBy, 8))
end

-- За сколько дней серии буквы дня выдаётся предмет, или nil, если не за серию.
function Module.streakDays(item: ShopItem): number?
	local grantedBy = item.grantedBy
	if not grantedBy or string.sub(grantedBy, 1, #STREAK_PREFIX) ~= STREAK_PREFIX then
		return nil
	end
	return tonumber(string.sub(grantedBy, #STREAK_PREFIX + 1))
end

--[[
	Предметы, которые положены за рекорд серии best, от ближних к дальним.
	По рекорду, а не по текущей серии: серия откатывается на шаг при пропуске,
	а выданное назад не забирается и второй раз не выдаётся.
]]
function Module.streakItems(best: number): { string }
	local ids: { string } = {}
	for id, item in Items do
		local days = Module.streakDays(item)
		if days and days <= best then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a: string, b: string): boolean
		local da = Module.streakDays(Items[a]) :: number
		local db = Module.streakDays(Items[b]) :: number
		if da ~= db then
			return da < db
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
