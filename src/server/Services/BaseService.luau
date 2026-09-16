--!nonstrict
--[[
	Участки игроков вокруг площади: у каждого ребёнка свой дом, который он строит
	за Звёздочки и который видят все на сервере. См. docs/15-HOME-BASE.md.

	Почему дом вообще: косметика отвечает на «что я получил», дом — на «что я построил».
	Шапку надел и забыл, а дом ребёнок видит каждый вход, помнит, что там было вчера,
	и хочет достроить. Это самый спокойный повод вернуться завтра: без реклам,
	ежедневных наград и давления.

	Три правила, которые сервис соблюдает:
	  · участок гарантирован каждому — двадцать площадок на двадцать мест сервера;
	  · менять можно только СВОЙ участок, соседний — только смотреть;
	  · улучшение заменяет предыдущее, а не ставится рядом.

	Строится кодом, а не руками в Studio: пока нет арта, геометрию проще держать
	в репозитории, чем в .rbxl, который не читается в диффе.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Base = require(Shared.Config.Base)
local Letters = require(Shared.Config.Letters)
local Stages = require(Shared.Config.Stages)
local MathLevels = require(Shared.Config.MathLevels)
local MathConfig = require(Shared.Config.Math)
local Awards = require(Shared.Logic.Awards)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local EconomyService = require(script.Parent.EconomyService)
local ChallengeService = require(script.Parent.ChallengeService)
local ProgressService = require(script.Parent.ProgressService)
local RateLimiter = require(script.Parent.RateLimiter)
local DecorShapes = require(script.Parent.Parent.World.DecorShapes)

local BaseService = {}

local FOLDER_NAME = "Plots"

type Plot = {
	index: number,
	model: Model,
	cframe: CFrame,
	owner: Player?,
}

local plots: { [number]: Plot } = {}
local byPlayer: { [Player]: number } = {}
local container: Folder? = nil

local GRASS = Color3.fromRGB(150, 205, 140)
local SOIL = Color3.fromRGB(178, 160, 130)

-- Верх земли участка: всё, что на нём стоит, отсчитывается отсюда, иначе постройки
-- уходят на студ под газон и дом выглядит просевшим.
--[[
	Верх пола участка. Земля площади кончается на Y = 1, и пока пол участка
	кончался там же, две поверхности дрались за один пиксель: издали весь двор
	мерцал. Теперь пол лежит заметно выше земли, и мерцать нечему.
]]
local FLOOR = 1.4

-- Где на участке стоит Азбучная Башня: за домом, у дальнего угла двора.
local TOWER_SPOT = CFrame.new(-13, 4, 13)

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function caption(parent: BasePart, text: string, height: number, size: number?)
	local existing = parent:FindFirstChild("Caption")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Caption"
	billboard.Size = UDim2.fromOffset(size or 260, 80)
	billboard.StudsOffset = Vector3.new(0, height, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 70
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(35, 30, 50)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard
end

--[[
	Где стоит участок с номером index.

	Участки идут по кругу с равным шагом и повёрнуты лицом к площади: ребёнок
	выходит из портала и видит фасады домов, а не их задние стены.
]]
function BaseService.plotCFrame(index: number): CFrame
	return CFrame.lookAt(Base.plotPosition(index), Vector3.zero)
end

-- ===== Постройки =================================================================

--[[
	Дом: четыре уровня, каждый ЗАМЕНЯЕТ предыдущий.

	Уровень 0 — пустая площадка с колышками: ребёнок видит место под дом,
	а не пустоту, и понимает, что здесь что-то будет.
]]
local function buildHouse(plot: Model, at: CFrame, level: number)
	if level <= 0 then
		for corner = 1, 4 do
			local angle = (corner - 1) / 4 * math.pi * 2
			local peg = part(
				`Peg_{corner}`,
				Vector3.new(0.8, 2, 0.8),
				at * CFrame.new(math.cos(angle) * 6, FLOOR + 1, math.sin(angle) * 6),
				SOIL,
				plot
			)
			peg.Material = Enum.Material.Wood
		end
		return
	end

	local sizes = {
		Vector3.new(10, 6, 10), -- шалаш
		Vector3.new(14, 8, 14), -- домик
		Vector3.new(16, 14, 16), -- двухэтажный
		Vector3.new(14, 20, 14), -- башенка
	}
	local colors = {
		Color3.fromRGB(205, 175, 140),
		Color3.fromRGB(235, 205, 165),
		Color3.fromRGB(240, 225, 200),
		Color3.fromRGB(225, 215, 240),
	}

	local size = sizes[level]
	local walls = part("House", size, at * CFrame.new(0, FLOOR + size.Y / 2, 0), colors[level], plot)
	walls.Material = Enum.Material.WoodPlanks

	-- Дверь и окно: дом обязан читаться домом, а не ящиком.
	local door = part(
		"Door",
		Vector3.new(3, 5, 0.4),
		at * CFrame.new(0, FLOOR + 2.5, -size.Z / 2 - 0.2),
		Color3.fromRGB(150, 110, 80),
		plot
	)
	door.Material = Enum.Material.Wood

	local window = part(
		"Window",
		Vector3.new(3, 3, 0.4),
		at * CFrame.new(-size.X / 3, FLOOR + size.Y * 0.6, -size.Z / 2 - 0.2),
		Color3.fromRGB(170, 220, 245),
		plot
	)
	window.Material = Enum.Material.Glass

	if level >= 3 then
		part(
			"SecondFloorBand",
			Vector3.new(size.X + 1, 0.8, size.Z + 1),
			at * CFrame.new(0, FLOOR + size.Y * 0.55, 0),
			Color3.fromRGB(190, 150, 120),
			plot
		)
	end
end

--[[
	Крыша живёт только над домом: без дома её ставить некуда.

	Это единственная зависимость между категориями, и она односторонняя —
	купленный уровень крыши не пропадает, он просто ждёт дом.
]]
local function buildRoof(plot: Model, at: CFrame, level: number, houseLevel: number)
	if level <= 0 or houseLevel <= 0 then
		return
	end

	local heights = { 6, 8, 14, 20 }
	local widths = { 11, 15, 17, 15 }
	local colors = {
		Color3.fromRGB(215, 185, 110), -- солома
		Color3.fromRGB(190, 105, 90), -- черепица
		Color3.fromRGB(150, 190, 230), -- цветная
		Color3.fromRGB(255, 235, 160), -- светящаяся
	}

	local top = heights[houseLevel]
	local width = widths[houseLevel]

	local roof = part(
		"Roof",
		Vector3.new(width + 2, 3, width + 2),
		at * CFrame.new(0, FLOOR + top + 1.5, 0),
		colors[level],
		plot
	)
	if level >= 4 then
		roof.Material = Enum.Material.Neon
	end

	local cap = part(
		"RoofCap",
		Vector3.new(width * 0.6, 2.5, width * 0.6),
		at * CFrame.new(0, FLOOR + top + 4, 0),
		colors[level],
		plot
	)
	if level >= 4 then
		cap.Material = Enum.Material.Neon
	end
end

-- Двор: от голой земли до фонтана. Растёт вокруг дома, а не вместо него.
local function buildYard(plot: Model, at: CFrame, level: number)
	local ground = part(
		"Ground",
		Vector3.new(Base.PLOT_SIZE, FLOOR, Base.PLOT_SIZE),
		at * CFrame.new(0, FLOOR / 2, 0),
		if level >= 1 then GRASS else SOIL,
		plot
	)
	ground.Material = if level >= 1 then Enum.Material.Grass else Enum.Material.Ground

	if level >= 2 then
		part(
			"Path",
			Vector3.new(4, 0.2, Base.PLOT_SIZE / 2),
			at * CFrame.new(0, FLOOR + 0.1, -Base.PLOT_SIZE / 4),
			Color3.fromRGB(230, 215, 185),
			plot
		)
	end

	if level >= 3 then
		for i = 1, 6 do
			local angle = (i - 1) / 6 * math.pi * 2
			local bush = part(
				`Bush_{i}`,
				Vector3.new(3, 2.4, 3),
				at * CFrame.new(math.cos(angle) * 14, FLOOR + 1.2, math.sin(angle) * 14),
				Color3.fromRGB(120, 185, 130),
				plot
			)
			bush.Material = Enum.Material.Grass
		end
	end

	if level >= 4 then
		part(
			"FountainBowl",
			Vector3.new(8, 1.6, 8),
			at * CFrame.new(0, FLOOR + 0.8, 13),
			Color3.fromRGB(215, 220, 230),
			plot
		)
		local water = part(
			"FountainWater",
			Vector3.new(6, 2.6, 6),
			at * CFrame.new(0, FLOOR + 2, 13),
			Color3.fromRGB(140, 200, 240),
			plot
		)
		water.Transparency = 0.35
		water.Material = Enum.Material.Neon
	end
end

--[[
	Мебель справа от дома, на виду с дорожки. Уровни набираются: стол остаётся,
	когда куплена кровать, — это набор вещей, а не лестница качества.

	Без дома мебель не ставится совсем: купленное не пропадает, а ждёт дом,
	как и крыша.
]]
local function buildFurniture(plot: Model, at: CFrame, level: number, houseLevel: number)
	if level <= 0 or houseLevel <= 0 then
		return
	end

	local x = 12

	if level >= 1 then
		local top = part(
			"TableTop",
			Vector3.new(4, 0.4, 3),
			at * CFrame.new(x, FLOOR + 2.2, -4),
			Color3.fromRGB(205, 165, 120),
			plot
		)
		top.Material = Enum.Material.WoodPlanks
		part("TableLeg", Vector3.new(0.6, 2, 0.6), at * CFrame.new(x, FLOOR + 1, -4), SOIL, plot)
	end

	if level >= 2 then
		part(
			"BedFrame",
			Vector3.new(3.4, 1, 6),
			at * CFrame.new(x, FLOOR + 0.5, 3),
			Color3.fromRGB(190, 150, 110),
			plot
		)
		local blanket = part(
			"BedBlanket",
			Vector3.new(3.6, 0.5, 4),
			at * CFrame.new(x, FLOOR + 1.2, 4),
			Color3.fromRGB(240, 170, 190),
			plot
		)
		blanket.Material = Enum.Material.Fabric
	end

	if level >= 3 then
		local rug = part(
			"Rug",
			Vector3.new(6, 0.2, 6),
			at * CFrame.new(x - 1, FLOOR + 0.1, -10),
			Color3.fromRGB(150, 190, 230),
			plot
		)
		rug.Material = Enum.Material.Fabric
		rug.CanCollide = false
	end

	if level >= 4 then
		local shelf = part(
			"Shelf",
			Vector3.new(0.6, 5, 4),
			at * CFrame.new(x + 3, FLOOR + 2.5, -1),
			Color3.fromRGB(215, 185, 145),
			plot
		)
		shelf.Material = Enum.Material.WoodPlanks
		for board = 1, 2 do
			part(
				`ShelfBoard_{board}`,
				Vector3.new(2, 0.3, 4),
				at * CFrame.new(x + 2, FLOOR + 1.6 + board * 1.6, -1),
				Color3.fromRGB(230, 205, 170),
				plot
			)
		end
	end
end

--[[
	Декор двора. Стоит на своих местах и ни от чего не зависит: флажки можно
	повесить над калиткой и на пустом участке — это первая покупка в игре
	и первое «здесь живу я».
]]
local function buildDecor(plot: Model, at: CFrame, level: number)
	if level <= 0 then
		return
	end

	local colors = {
		Color3.fromRGB(255, 130, 130),
		Color3.fromRGB(255, 205, 120),
		Color3.fromRGB(150, 220, 160),
		Color3.fromRGB(150, 190, 245),
	}

	if level >= 1 then
		-- Гирлянда над калиткой: её видно с дорожки раньше самого дома.
		for index = 1, 7 do
			local flag = part(
				`YardFlag_{index}`,
				Vector3.new(1.2, 1.2, 0.15),
				at
					* CFrame.new(
						(index - 4) * 2.2,
						FLOOR + 6 - math.abs(index - 4) * 0.25,
						-Base.PLOT_SIZE / 2 + 2
					),
				colors[(index - 1) % #colors + 1],
				plot
			)
			flag.CanCollide = false
		end
	end

	if level >= 2 then
		for index = 1, 3 do
			local balloon = part(
				`Balloon_{index}`,
				Vector3.new(2, 2.4, 2),
				at * CFrame.new(-13 + index * 1.6, FLOOR + 7 + index * 0.6, -12),
				colors[index],
				plot
			)
			balloon.Shape = Enum.PartType.Ball
			balloon.CanCollide = false
			part(
				`BalloonString_{index}`,
				Vector3.new(0.1, 5, 0.1),
				at * CFrame.new(-13 + index * 1.6, FLOOR + 3.5 + index * 0.6, -12),
				Color3.fromRGB(240, 240, 240),
				plot
			).CanCollide =
				false
		end
	end

	if level >= 3 then
		for index = 1, 4 do
			local post = part(
				`LanternPost_{index}`,
				Vector3.new(0.4, 4, 0.4),
				at * CFrame.new(-5, FLOOR + 2, -14 + index * 3),
				Color3.fromRGB(120, 110, 100),
				plot
			)
			post.CanCollide = false
			local lamp = part(
				`Lantern_{index}`,
				Vector3.new(1.4, 1.4, 1.4),
				at * CFrame.new(-5, FLOOR + 4.6, -14 + index * 3),
				Color3.fromRGB(255, 230, 160),
				plot
			)
			lamp.Material = Enum.Material.Neon
			lamp.CanCollide = false
		end
	end

	if level >= 4 then
		local x = -13
		for _, side in { -1, 1 } do
			part(
				`SwingPost_{side}`,
				Vector3.new(0.6, 7, 0.6),
				at * CFrame.new(x + side * 2.5, FLOOR + 3.5, 6),
				Color3.fromRGB(180, 140, 100),
				plot
			)
		end
		part(
			"SwingBar",
			Vector3.new(6, 0.5, 0.5),
			at * CFrame.new(x, FLOOR + 7, 6),
			Color3.fromRGB(180, 140, 100),
			plot
		)
		for _, side in { -1, 1 } do
			part(
				`SwingRope_{side}`,
				Vector3.new(0.15, 4, 0.15),
				at * CFrame.new(x + side * 1.2, FLOOR + 5, 6),
				Color3.fromRGB(235, 225, 200),
				plot
			).CanCollide =
				false
		end
		local seat = part(
			"SwingSeat",
			Vector3.new(3, 0.3, 1.4),
			at * CFrame.new(x, FLOOR + 3, 6),
			Color3.fromRGB(255, 180, 120),
			plot
		)
		seat.Material = Enum.Material.WoodPlanks
	end
end

--[[
	Забор по краю участка. На верхнем уровне столбики — буквы: это витрина
	обучения, вынесенная на границу двора, и её видно соседям.
]]
local function buildFence(plot: Model, at: CFrame, level: number)
	if level <= 0 then
		return
	end

	local heights = { 1.6, 3, 4, 4 }
	local colors = {
		Color3.fromRGB(180, 150, 110),
		Color3.fromRGB(225, 215, 195),
		Color3.fromRGB(170, 170, 175),
		Color3.fromRGB(255, 214, 102),
	}

	local half = Base.PLOT_SIZE / 2 - 1
	local step = 4
	local height = heights[level]

	for offset = -half, half, step do
		for _, side in { -1, 1 } do
			-- Проём в переднем заборе: калитка ровно там, где дорожка.
			local isFrontGate = side == -1 and math.abs(offset) <= 3
			if not isFrontGate then
				local post = part(
					`Post_{side}_{math.floor(offset)}`,
					Vector3.new(0.8, height, 0.8),
					at * CFrame.new(offset, FLOOR + height / 2, side * half),
					colors[level],
					plot
				)
				if level >= 4 then
					post.Material = Enum.Material.Neon
				end
			end

			local post = part(
				`PostSide_{side}_{math.floor(offset)}`,
				Vector3.new(0.8, height, 0.8),
				at * CFrame.new(side * half, FLOOR + height / 2, offset),
				colors[level],
				plot
			)
			if level >= 4 then
				post.Material = Enum.Material.Neon
			end
		end
	end
end

-- ===== Заработанное учёбой =======================================================

--[[
	Постройки, которые не купить (Logic/Awards, docs/17-CONTENT-PLAN.md § 5).
	Стоят там, где двор свободен при любых уровнях дома: флаги — вдоль правого
	забора, арка — над калиткой, шпиль — в правом заднем углу, напротив Башни.
]]
local FLAG_X = Base.PLOT_SIZE / 2 - 2.5
local FLAG_STEP = 2.1
local POLE_HEIGHT = 5

local function buildFlags(plot: Model, at: CFrame, count: number)
	for index = 1, count do
		local stage = Stages.get(index)
		if stage then
			local z = (index - (Stages.count() + 1) / 2) * FLAG_STEP
			local pole = part(
				`FlagPole_{index}`,
				Vector3.new(0.3, POLE_HEIGHT, 0.3),
				at * CFrame.new(FLAG_X, FLOOR + POLE_HEIGHT / 2, z),
				Color3.fromRGB(235, 235, 240),
				plot
			)
			pole.CanCollide = false

			-- Цвет флага — цвет первой буквы ступени: флаги разные, как и уровни.
			local first = Letters.expect(stage.letters[1])
			local cloth = part(
				`Flag_{index}`,
				Vector3.new(0.15, 1.2, 1.7),
				at * CFrame.new(FLAG_X, FLOOR + POLE_HEIGHT - 0.7, z + 0.9),
				first.color,
				plot
			)
			cloth.CanCollide = false
			caption(cloth, first.glyph, 1.4, 60)
		end
	end
end

local function buildArch(plot: Model, at: CFrame)
	local gold = Color3.fromRGB(255, 214, 102)
	-- Сразу за линией забора: у калитки внутри стоят табличка и пады улучшений.
	local z = -Base.PLOT_SIZE / 2 - 1.5
	for _, side in { -1, 1 } do
		local leg = part(
			`AlphabetArchLeg_{side}`,
			Vector3.new(1, 7, 1),
			at * CFrame.new(side * 4.6, FLOOR + 3.5, z),
			gold,
			plot
		)
		leg.Material = Enum.Material.Neon
	end
	local beam =
		part("AlphabetArch", Vector3.new(10.2, 1.2, 1), at * CFrame.new(0, FLOOR + 7.6, z), gold, plot)
	beam.Material = Enum.Material.Neon
	caption(beam, "А Б В Г Д Е Ё Ж З И", 2.2, 320)
end

local function buildSpire(plot: Model, at: CFrame)
	local gold = Color3.fromRGB(255, 214, 102)
	local spot = at * CFrame.new(Base.PLOT_SIZE / 2 - 7, 0, Base.PLOT_SIZE / 2 - 7)
	local spire = part("AlphabetSpire", Vector3.new(2, 16, 2), spot * CFrame.new(0, FLOOR + 8, 0), gold, plot)
	spire.Material = Enum.Material.Neon
	local star =
		part("AlphabetSpireStar", Vector3.new(3, 3, 3), spot * CFrame.new(0, FLOOR + 17.5, 0), gold, plot)
	star.Shape = Enum.PartType.Ball
	star.Material = Enum.Material.Neon
	caption(star, "33 из 33", 3, 280)
end

--[[
	Путь мира математики — вдоль левого забора, зеркально буквенным флагам.
	На флаге цифра уровня: цвет у чисел смысла не несёт, поэтому флаги
	чередуют тёплые оттенки, чтобы ряд не сливался в одну полосу.
]]
local MATH_FLAG_COLORS = {
	Color3.fromRGB(240, 150, 120),
	Color3.fromRGB(235, 195, 110),
	Color3.fromRGB(160, 210, 140),
	Color3.fromRGB(130, 195, 235),
}

local function buildMathFlags(plot: Model, at: CFrame, count: number)
	for index = 1, math.min(count, MathLevels.count()) do
		local z = (index - (MathLevels.count() + 1) / 2) * FLAG_STEP
		local pole = part(
			`MathFlagPole_{index}`,
			Vector3.new(0.3, POLE_HEIGHT, 0.3),
			at * CFrame.new(-FLAG_X, FLOOR + POLE_HEIGHT / 2, z),
			Color3.fromRGB(235, 235, 240),
			plot
		)
		pole.CanCollide = false
		local cloth = part(
			`MathFlag_{index}`,
			Vector3.new(0.15, 1.2, 1.7),
			at * CFrame.new(-FLAG_X, FLOOR + POLE_HEIGHT - 0.7, z + 0.9),
			MATH_FLAG_COLORS[(index - 1) % #MATH_FLAG_COLORS + 1],
			plot
		)
		cloth.CanCollide = false
		caption(cloth, tostring(index), 1.4, 60)
	end
end

--[[
	Шпиль Счёта — у задней стены, между Башней и Шпилем Азбуки: две вершины
	обучения стоят рядом, и с улицы видно обе. Голубой, чтобы не спутать с золотым.
]]
local function buildCountSpire(plot: Model, at: CFrame)
	local blue = Color3.fromRGB(120, 200, 255)
	local spot = at * CFrame.new(6, 0, Base.PLOT_SIZE / 2 - 4)
	local spire = part("CountSpire", Vector3.new(2, 13, 2), spot * CFrame.new(0, FLOOR + 6.5, 0), blue, plot)
	spire.Material = Enum.Material.Neon
	local top =
		part("CountSpireTop", Vector3.new(2.6, 2.6, 2.6), spot * CFrame.new(0, FLOOR + 14.3, 0), blue, plot)
	top.Material = Enum.Material.Neon
	caption(top, "1 2 3 … 9", 3, 280)
end

--[[
	Комнаты дома (docs/15-HOME-BASE.md § 5). Их нельзя купить: комната появляется
	за освоенную букву и за освоенную ступень счёта, и полка в ней растёт сама.

	Пристроены сзади дома — открытые, без крыши и четвёртой стены: заходить внутрь
	ребёнку незачем, а видеть свою полку он должен с дорожки, не влезая никуда.
	Без дома комнат не бывает: пристраивать их не к чему.
]]
local ROOM_DEPTH = 6
local ROOM_Z = 12
local TILE_STEP = 1.4
local TILES_IN_ROW = 6

local function buildRoom(
	plot: Model,
	at: CFrame,
	name: string,
	centerX: number,
	width: number,
	title: string,
	tiles: { { glyph: string, color: Color3 } }
)
	if #tiles == 0 then
		return
	end

	local rows = math.ceil(#tiles / TILES_IN_ROW)
	local wallHeight = math.max(4, 1.6 + rows * TILE_STEP + 1)

	local floorSlab = part(
		`{name}Floor`,
		Vector3.new(width, 0.4, ROOM_DEPTH),
		at * CFrame.new(centerX, FLOOR + 0.2, ROOM_Z),
		Color3.fromRGB(225, 210, 190),
		plot
	)
	floorSlab.Material = Enum.Material.WoodPlanks

	local back = part(
		`{name}Wall`,
		Vector3.new(width, wallHeight, 0.5),
		at * CFrame.new(centerX, FLOOR + wallHeight / 2, ROOM_Z + ROOM_DEPTH / 2),
		Color3.fromRGB(240, 230, 215),
		plot
	)
	back.Material = Enum.Material.SmoothPlastic
	caption(back, title, 2, 200)

	for _, side in { -1, 1 } do
		part(
			`{name}Side_{side}`,
			Vector3.new(0.5, wallHeight, ROOM_DEPTH),
			at * CFrame.new(centerX + side * (width / 2), FLOOR + wallHeight / 2, ROOM_Z),
			Color3.fromRGB(235, 222, 205),
			plot
		)
	end

	--[[
		Полки с буквами: ряд заполняется слева направо, новый ряд ложится выше.
		Плитка — та самая буква, которую ребёнок освоил, её же цвета
		(Config/Letters): полка читается как список выученного, а не как узор.
	]]
	for index, tile in tiles do
		local row = math.floor((index - 1) / TILES_IN_ROW)
		local column = (index - 1) % TILES_IN_ROW
		local inRow = math.min(TILES_IN_ROW, #tiles - row * TILES_IN_ROW)
		local x = centerX + (column - (inRow - 1) / 2) * TILE_STEP

		if column == 0 then
			local shelf = part(
				`{name}Shelf_{row}`,
				Vector3.new(inRow * TILE_STEP, 0.2, 1),
				at * CFrame.new(centerX, FLOOR + 1.2 + row * TILE_STEP, ROOM_Z + ROOM_DEPTH / 2 - 0.8),
				Color3.fromRGB(205, 180, 150),
				plot
			)
			shelf.Material = Enum.Material.WoodPlanks
			shelf.CanCollide = false
		end

		local tilePart = part(
			`{name}Tile_{index}`,
			Vector3.new(TILE_STEP - 0.25, TILE_STEP - 0.25, 0.3),
			at * CFrame.new(x, FLOOR + 1.9 + row * TILE_STEP, ROOM_Z + ROOM_DEPTH / 2 - 0.8),
			tile.color,
			plot
		)
		tilePart.CanCollide = false
		caption(tilePart, tile.glyph, 1.2, 90)
	end
end

local function buildRooms(plot: Model, at: CFrame, earned: Awards.Earned, houseLevel: number)
	if houseLevel <= 0 then
		return
	end

	local letterTiles = {}
	-- preview из консоли Studio зовут руками и неполной таблицей: комнат может не быть вовсе.
	for _, letterId in earned.letterRooms or {} do
		local letter = Letters.expect(letterId)
		table.insert(letterTiles, { glyph = letter.glyph, color = letter.color })
	end
	buildRoom(plot, at, "LetterRoom", -7, 10, "Комнаты букв", letterTiles)

	--[[
		На плитке — номер ступени счёта, а не её порядок в списке освоенных:
		ступени осваиваются вразнобой, и «третья комната» должна означать
		третью ступень, а не третью по счёту победу.
	]]
	local mathTiles = {}
	for stage = 1, MathConfig.count() do
		local spec = MathConfig.get(stage)
		if spec and table.find(earned.mathRooms or {}, spec.id) then
			table.insert(mathTiles, {
				glyph = tostring(stage),
				color = MATH_FLAG_COLORS[(stage - 1) % #MATH_FLAG_COLORS + 1],
			})
		end
	end
	buildRoom(plot, at, "MathRoom", 7, 10, "Комнаты цифр", mathTiles)
end

local function renderAwards(plot: Plot, earned: Awards.Earned)
	buildFlags(plot.model, plot.cframe, earned.flags)
	buildMathFlags(plot.model, plot.cframe, earned.mathFlags)
	if earned.arch then
		buildArch(plot.model, plot.cframe)
	end
	if earned.spire then
		buildSpire(plot.model, plot.cframe)
	end
	if earned.countSpire then
		buildCountSpire(plot.model, plot.cframe)
	end
end

-- ===== Пады улучшений ============================================================

--[[
	Пад улучшения — по одному на категорию, вдоль фасада участка.

	Здесь, в отличие от падов занятий, срабатывает НЕ касание, а подсказка с
	удержанием: занятие бесплатно и обратимо, а трата звёздочек — нет.
	Ребёнок не должен потратить накопленное, просто пробежав мимо.
]]
local function buildUpgradePad(
	plot: Model,
	at: CFrame,
	index: number,
	categoryId: string,
	player: Player,
	level: number
)
	local category = Base.expect(categoryId)
	local offset = (index - (#Base.CATEGORIES + 1) / 2) * Base.PAD_STEP

	local pad = part(
		`Upgrade_{categoryId}`,
		Vector3.new(Base.PAD_WIDTH, 1, Base.PAD_WIDTH),
		at * CFrame.new(offset, FLOOR + 0.5, -Base.PLOT_SIZE / 2 + 5),
		Color3.fromRGB(255, 235, 190),
		plot
	)

	local price = Base.priceFor(categoryId, level)
	local nextTitle = Base.nextTitle(categoryId, level)

	if not price or not nextTitle then
		caption(pad, `{category.emoji} {category.title}\nготово`, 4)
		pad.Color = Color3.fromRGB(200, 230, 200)
		return
	end

	caption(pad, `{category.emoji} {nextTitle}\n{price} ⭐`, 4)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Построить"
	prompt.ObjectText = `{category.title}: {nextTitle} — {price} ⭐`
	prompt.HoldDuration = 0.8
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	prompt.Triggered:Connect(function(who: Player)
		if who == player then
			BaseService.upgrade(who, categoryId)
		end
	end)
end

-- ===== Сборка участка ============================================================

local function clearPlot(plot: Plot)
	plot.model:ClearAllChildren()
end

--[[
	Собирает участок целиком по уровням из профиля.

	Перестраиваем участок ЦЕЛИКОМ на каждое улучшение, а не правим один слот:
	двадцать деталей строятся мгновенно, а «улучшили крышу, а дом остался старый»
	— это класс ошибок, которого при полной пересборке не существует.
]]
local function renderBuildings(plot: Plot, base: { [string]: number })
	local at = plot.cframe
	buildYard(plot.model, at, base.yard)
	buildHouse(plot.model, at, base.house)
	buildRoof(plot.model, at, base.roof, base.house)
	buildFence(plot.model, at, base.fence)
	buildFurniture(plot.model, at, base.furniture, base.house)
	buildDecor(plot.model, at, base.decor)
end

local function renderSign(plot: Plot, text: string)
	local sign = part(
		"Sign",
		Vector3.new(8, 0.6, 0.6),
		plot.cframe * CFrame.new(0, FLOOR + 3, -Base.PLOT_SIZE / 2 + 1),
		Color3.fromRGB(255, 240, 200),
		plot.model
	)
	caption(sign, text, 2)
end

local function renderPlot(plot: Plot, player: Player?, profile: any?)
	clearPlot(plot)

	if not player then
		-- Свободный участок: голая земля и табличка. Пустое место должно читаться
		-- как «сюда кто-то въедет», а не как дырка в мире.
		renderBuildings(plot, Base.newProgress())
		renderSign(plot, "Свободный участок")
		return
	end

	local base = Base.sanitize(profile and profile.base)
	local earned = Awards.of(profile)
	renderBuildings(plot, base)
	renderAwards(plot, earned)
	buildRooms(plot.model, plot.cframe, earned, base.house)
	renderSign(plot, `Дом: {player.DisplayName}`)

	for index, categoryId in Base.ids() do
		buildUpgradePad(plot.model, plot.cframe, index, categoryId, player, base[categoryId])
	end
end

--[[
	Показать участок с заданными уровнями, ничего не покупая.

	Нужно на проверке руками: накопить шесть тысяч звёздочек, чтобы посмотреть
	на башенку с фонтаном, — не проверка, а рабочий день. Из игры не вызывается:
	это команда для консоли Studio, см. docs/HOW-TO-CHECK.md.
]]
function BaseService.preview(index: number, levels: { [string]: number }, earned: Awards.Earned?)
	local plot = plots[index]
	if not plot then
		warn(`[Base] участка {index} нет`)
		return
	end

	clearPlot(plot)
	local clean = Base.sanitize(levels)
	renderBuildings(plot, clean)
	if earned then
		renderAwards(plot, earned)
		buildRooms(plot.model, plot.cframe, earned, clean.house)
	end
	renderSign(plot, "Показ")
end

local function ensureContainer(): Folder
	if container and container.Parent then
		return container
	end

	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	container = folder
	return folder
end

--[[
	Сады между участками. Дома раздвинуты (Config/Base.PLOT_GAP), и промежуток
	не должен быть пустырём: в каждом — куст у дорожки, дерево посередине
	и ещё дерево у дальнего края. С дорожки соседние дворы читаются отдельно,
	как дома на улице, а не как ряд одинаковых площадок.
]]
local GARDEN = { "bush_round", "tree_round", "tree_pine" }

local function buildGardens(folder: Instance)
	local gardens = Instance.new("Folder")
	gardens.Name = "Gardens"
	gardens.Parent = folder

	for index = 1, Base.PLOT_COUNT do
		local angle = (index - 0.5) / Base.PLOT_COUNT * math.pi * 2
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		for slot, id in GARDEN do
			local model = DecorShapes.build({ id = id })
			if model then
				local distance = Base.RING_RADIUS + (slot - 2) * (Base.PLOT_SIZE / 2.5)
				local spot = outward * distance
				model.Name = `Garden_{index}_{slot}`
				model.Parent = gardens
				if id ~= "bush_round" then
					model:ScaleTo(1.3)
				end
				model:PivotTo(CFrame.new(spot) * CFrame.Angles(0, angle + slot, 0))
				local box, size = model:GetBoundingBox()
				model:PivotTo(model:GetPivot() + Vector3.new(0, 1 - (box.Position.Y - size.Y / 2), 0))
				for _, descendant in model:GetDescendants() do
					if descendant:IsA("BasePart") then
						descendant.Anchored = true
					end
				end
			end
		end
	end
end

function BaseService.build()
	local folder = ensureContainer()
	table.clear(plots)
	buildGardens(folder)

	for index = 1, Base.PLOT_COUNT do
		local model = Instance.new("Model")
		model.Name = `Plot_{index}`
		model.Parent = folder

		local plot: Plot = {
			index = index,
			model = model,
			cframe = BaseService.plotCFrame(index),
			owner = nil,
		}
		plots[index] = plot
		renderPlot(plot, nil, nil)
	end

	print(
		`[Base] участков построено: {Base.PLOT_COUNT}, радиус кольца {Base.RING_RADIUS}`
	)
end

-- ===== Игроки ====================================================================

local function freePlotIndex(): number?
	for index = 1, Base.PLOT_COUNT do
		local plot = plots[index]
		if plot and not plot.owner then
			return index
		end
	end
	return nil
end

function BaseService.plotOf(player: Player): Plot?
	local index = byPlayer[player]
	return if index then plots[index] else nil
end

--[[
	Перерисовывает участок игрока по текущему профилю.
	Единственный путь, которым дом меняется на глазах у ребёнка.
]]
function BaseService.refresh(player: Player)
	local plot = BaseService.plotOf(player)
	local profile = ProfileService.get(player)
	if not plot or not profile then
		return
	end
	renderPlot(plot, player, profile)
end

function BaseService.assign(player: Player)
	if byPlayer[player] then
		return
	end

	local index = freePlotIndex()
	if not index then
		-- Участков ровно столько, сколько мест на сервере: сюда мы попасть не должны.
		warn(`[Base] свободных участков нет для {player.Name}`)
		return
	end

	local plot = plots[index]
	plot.owner = player
	byPlayer[player] = index

	BaseService.refresh(player)

	--[[
		Клиенту сообщаем, где на его участке стоит Азбучная Башня.

		Витрина обучения переезжает из центра карты во двор ребёнка
		(docs/15-HOME-BASE.md § 4): в центре теперь порталы, а Башня — «моя»,
		и стоит она у меня за домом, где её видно и мне, и соседям.
	]]
	RemoteDefs.event("BaseAssigned"):FireClient(player, (plot.cframe * TOWER_SPOT).Position)
end

--[[
	Точка перед своим домом: у края участка со стороны площади, лицом к фасаду.
	Не на самом участке — там пады улучшений, и ребёнка не должно ставить
	прямо на пад покупки.
]]
function BaseService.homeCFrame(player: Player): CFrame?
	local plot = BaseService.plotOf(player)
	if not plot then
		return nil
	end
	local at = (plot.cframe * CFrame.new(0, FLOOR + 3, -Base.PLOT_SIZE / 2 - 5)).Position
	local center = plot.cframe.Position
	return CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
end

--[[
	Кнопка 🏠. Два шага, и оба нужны: идёт испытание — оно заканчивается как
	«вышел домой» (сохранка остаётся, docs/14-TUNNEL-MODE.md § 7), а сам ребёнок
	оказывается у своего дома, а не на входе в портал. «Домик» обязан работать
	всегда и из любого места: застрять в игре нельзя (docs/08-UX-UI.md § 2).
]]
function BaseService.sendHome(player: Player)
	if not RateLimiter.allow(player, "GoHome", RemoteDefs.RATE_LIMITS.GoHome) then
		return
	end

	if ChallengeService.isBusy(player) then
		ChallengeService.abort(player)
	end

	local home = BaseService.homeCFrame(player)
	local character = player.Character
	if home and character then
		character:PivotTo(home)
	end
end

function BaseService.release(player: Player)
	local index = byPlayer[player]
	byPlayer[player] = nil
	if not index then
		return
	end

	local plot = plots[index]
	if plot then
		plot.owner = nil
		renderPlot(plot, nil, nil)
	end
end

--[[
	Улучшение постройки. Цена берётся ИЗ КОНФИГА, из запроса — только название
	категории. Проверки те же, что в магазине: свой участок, есть следующий
	уровень, хватает звёздочек.
]]
function BaseService.upgrade(player: Player, categoryId: any): boolean
	if typeof(categoryId) ~= "string" then
		return false
	end

	if not RateLimiter.allow(player, "BuildUpgrade", RemoteDefs.RATE_LIMITS.BuildUpgrade) then
		return false
	end

	local category = Base.get(categoryId)
	if not category then
		warn(`[Base] неизвестная категория построек: {categoryId}`)
		return false
	end

	local plot = BaseService.plotOf(player)
	local profile = ProfileService.get(player)
	if not plot or not profile then
		return false
	end

	local level = Base.sanitize(profile.base)[categoryId]
	local price = Base.priceFor(categoryId, level)
	if not price then
		return false -- достроено до конца
	end

	if not EconomyService.spend(player, price, `base:{categoryId}`) then
		-- Не хватает звёздочек — это не ошибка, а «ещё не накопил».
		RemoteDefs.event("OpenUI"):FireClient(player, "need_stars")
		return false
	end

	ProfileService.update(player, function(p)
		p.base = Base.sanitize(p.base)
		p.base[categoryId] = level + 1
	end)

	BaseService.refresh(player)
	print(`[Base] {player.Name}: {categoryId} → уровень {level + 1}`)
	return true
end

function BaseService.start()
	BaseService.build()

	RemoteDefs.event("BuildUpgrade").OnServerEvent:Connect(function(player: Player, categoryId: any)
		BaseService.upgrade(player, categoryId)
	end)

	RemoteDefs.event("GoHome").OnServerEvent:Connect(BaseService.sendHome)

	--[[
		Заработанное учёбой появляется во дворе сразу. Пройден уровень — встал флаг;
		освоена буква — могли появиться арка или шпиль. Перестройка отложена на кадр:
		хук финиша срабатывает раньше, чем уровень записан в профиль.
	]]
	ChallengeService.onFinished(function(player: Player, spec: any, reason: string)
		-- Любое математическое занятие могло освоить ступень — а с ней встать Шпилю Счёта.
		if
			(reason == "completed" or reason == "timeout")
			and (spec.level or spec.params.mathLevel or spec.params.mathStageId)
		then
			task.defer(BaseService.refresh, player)
		end
	end)
	ProgressService.onTransition(function(player: Player)
		task.defer(BaseService.refresh, player)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			if ProfileService.waitFor(player, 20) then
				BaseService.assign(player)
			end
		end)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			if ProfileService.waitFor(player, 20) then
				BaseService.assign(player)
			end
		end)
	end

	Players.PlayerRemoving:Connect(BaseService.release)
end

return BaseService
