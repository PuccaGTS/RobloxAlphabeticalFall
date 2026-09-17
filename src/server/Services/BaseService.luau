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

local CollectionService = game:GetService("CollectionService")
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
local DecorService = require(script.Parent.DecorService)
local Teleport = require(script.Parent.Parent.World.Teleport)

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

-- Шар диаметром size: у Roblox шар берёт наименьшую сторону, поэтому стороны равны.
local function ball(name: string, size: number, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local p = part(name, Vector3.new(size, size, size), cframe, color, parent)
	p.Shape = Enum.PartType.Ball
	return p
end

-- Стоячий цилиндр: у детали цилиндр лежит вдоль X, его ставят на торец.
local function cylinder(
	name: string,
	height: number,
	diameter: number,
	cframe: CFrame,
	color: Color3,
	parent: Instance
): BasePart
	local p = part(
		name,
		Vector3.new(height, diameter, diameter),
		cframe * CFrame.Angles(0, 0, math.pi / 2),
		color,
		parent
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

--[[
	Группа деталей, которую двигает клиент (PlaygroundController): карусель
	крутится, шар покачивается, утки плавают по кругу. Сервер ставит только
	метку и числа — анимация у каждого ребёнка своя и в сеть не идёт.
]]
local function moving(parent: Instance, name: string): Model
	local group = Instance.new("Model")
	group.Name = name
	-- Приезжает к клиенту целиком: иначе часть деталей встала бы на место позже и не в такт.
	group.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	group.Parent = parent
	return group
end

-- Мелкая отделка, о которую ребёнок не должен спотыкаться.
local function trim(p: BasePart): BasePart
	p.CanCollide = false
	return p
end

--[[
	Подпись над деталью. size — ширина в пикселях, а со studs = true — сторона
	квадрата в студах: так подписываются буквы на флажках и плитках. Флажки
	стоят через студ-два, и пиксельные буквы издалека слипались в «АГЁИ».
]]
local function caption(parent: BasePart, text: string, height: number, size: number?, studs: boolean?)
	local existing = parent:FindFirstChild("Caption")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Caption"
	billboard.Size = if studs
		then UDim2.fromScale(size or 1, size or 1)
		else UDim2.fromOffset(size or 260, 80)
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
	Размеры дома по уровням: ширина (x), высота стен, глубина (z). Крыша, флаги
	на коньке и печная труба считаются от них же. Пятна под домом не меняются
	с прошлых версий: мебель, комнаты букв и пады стоят вокруг этих габаритов.
]]
local HOUSE_SIZES = {
	Vector3.new(10, 6, 10), -- шалаш
	Vector3.new(14, 8, 14), -- домик
	Vector3.new(16, 14, 16), -- двухэтажный
	Vector3.new(14, 20, 14), -- башенка
}
local ROOF_OVERHANG = 0.8

-- Высота двускатной крыши над стенами: одинаковый уклон у всех домов.
local function roofRise(houseLevel: number): number
	return HOUSE_SIZES[houseLevel].X * 0.42
end

local HOUSE_WHITE = Color3.fromRGB(250, 248, 240)
local HOUSE_DARK_WOOD = Color3.fromRGB(120, 85, 60)
local HOUSE_DOOR = Color3.fromRGB(160, 100, 70)
local HOUSE_STONE = Color3.fromRGB(185, 180, 190)
local HOUSE_GLASS = Color3.fromRGB(150, 205, 240)
local FLOWERS = { Color3.fromRGB(245, 120, 150), Color3.fromRGB(255, 215, 90), Color3.fromRGB(170, 130, 230) }

local function wedge(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local p = Instance.new("WedgePart")
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

-- Бревно, конёк, перекладина: цилиндр лежит вдоль локальной оси X детали.
local function log(
	name: string,
	length: number,
	diameter: number,
	cframe: CFrame,
	color: Color3,
	parent: Instance
)
	local p = part(name, Vector3.new(length, diameter, diameter), cframe, color, parent)
	p.Shape = Enum.PartType.Cylinder
	return p
end

--[[
	Окно на стене. face — точка в центре окна на поверхности стены, её −Z смотрит
	наружу. Рама, стекло с крестовиной, по желанию ставни и ящик с цветами:
	из этих мелочей коробка и становится домом.
]]
local function houseWindow(
	plot: Model,
	face: CFrame,
	name: string,
	width: number,
	height: number,
	shutters: Color3?,
	flowers: boolean?
)
	trim(
		part(
			`{name}Frame`,
			Vector3.new(width + 0.6, height + 0.6, 0.3),
			face * CFrame.new(0, 0, -0.15),
			HOUSE_WHITE,
			plot
		)
	)
	local glass = trim(
		part(`{name}Glass`, Vector3.new(width, height, 0.3), face * CFrame.new(0, 0, -0.3), HOUSE_GLASS, plot)
	)
	glass.Material = Enum.Material.Glass
	glass.Reflectance = 0.15
	trim(
		part(`{name}Cross`, Vector3.new(0.25, height, 0.2), face * CFrame.new(0, 0, -0.5), HOUSE_WHITE, plot)
	)
	trim(
		part(
			`{name}CrossBar`,
			Vector3.new(width, 0.25, 0.2),
			face * CFrame.new(0, 0, -0.5),
			HOUSE_WHITE,
			plot
		)
	)
	if shutters then
		for _, side in { -1, 1 } do
			trim(
				part(
					`{name}Shutter_{side}`,
					Vector3.new(width * 0.5, height + 0.5, 0.25),
					face * CFrame.new(side * (width * 0.75 + 0.35), 0, -0.2),
					shutters,
					plot
				)
			)
		end
	end
	if flowers then
		trim(
			part(
				`{name}FlowerBox`,
				Vector3.new(width + 0.8, 0.7, 0.9),
				face * CFrame.new(0, -height / 2 - 0.65, -0.55),
				HOUSE_DARK_WOOD,
				plot
			)
		)
		for index = 1, 3 do
			trim(
				ball(
					`{name}Flower_{index}`,
					0.75,
					face * CFrame.new((index - 2) * width * 0.34, -height / 2 - 0.1, -0.55),
					FLOWERS[index],
					plot
				)
			)
		end
	end
end

-- Дверь: полотно, рама, ручка; arched — полукруглый верх, как у башенки.
local function houseDoor(plot: Model, face: CFrame, width: number, height: number, arched: boolean?)
	local frame = part(
		"DoorFrame",
		Vector3.new(width + 0.7, height + 0.35, 0.3),
		face * CFrame.new(0, (height + 0.35) / 2, -0.15),
		HOUSE_WHITE,
		plot
	)
	trim(frame)
	local door = part(
		"Door",
		Vector3.new(width, height, 0.4),
		face * CFrame.new(0, height / 2, -0.3),
		HOUSE_DOOR,
		plot
	)
	door.Material = Enum.Material.WoodPlanks
	trim(door)
	if arched then
		for index, spec in { { width + 0.7, 0.3, HOUSE_WHITE }, { width, 0.4, HOUSE_DOOR } } do
			local top = log(
				`DoorArch_{index}`,
				spec[2],
				spec[1],
				face * CFrame.new(0, height, -0.15 - (index - 1) * 0.15) * CFrame.Angles(0, math.pi / 2, 0),
				spec[3],
				plot
			)
			trim(top)
		end
	end
	trim(
		ball(
			"DoorKnob",
			0.45,
			face * CFrame.new(width * 0.32, height * 0.45, -0.6),
			Color3.fromRGB(240, 200, 90),
			plot
		)
	)
end

-- Печная труба сквозь крышу, с дымком: дом, в котором живут.
local function chimney(plot: Model, at: CFrame, x: number, z: number, houseLevel: number)
	local size = HOUSE_SIZES[houseLevel]
	local halfWidth = size.X / 2 + ROOF_OVERHANG
	-- Над скатом в этой точке на полтора студа, даже если крыши ещё нет.
	local top = FLOOR + size.Y + roofRise(houseLevel) * (1 - math.abs(x) / halfWidth) + 1.6
	local bottom = FLOOR + size.Y - 1
	local stack = part(
		"Chimney",
		Vector3.new(1.6, top - bottom, 1.6),
		at * CFrame.new(x, (top + bottom) / 2, z),
		Color3.fromRGB(175, 95, 80),
		plot
	)
	stack.Material = Enum.Material.Brick
	local cap = part(
		"ChimneyCap",
		Vector3.new(2.1, 0.4, 2.1),
		at * CFrame.new(x, top + 0.2, z),
		HOUSE_DARK_WOOD,
		plot
	)

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Rate = 1.2
	smoke.Lifetime = NumberRange.new(3, 4.5)
	smoke.Speed = NumberRange.new(1.5, 2.5)
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 2.6) })
	smoke.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	smoke.Color = ColorSequence.new(Color3.fromRGB(235, 235, 240))
	smoke.Parent = cap
end

--[[
	Дом: четыре уровня, каждый ЗАМЕНЯЕТ предыдущий.

	Уровень 0 — пустая площадка с колышками: ребёнок видит место под дом,
	а не пустоту, и понимает, что здесь что-то будет.

	Раньше каждый уровень был окрашенным ящиком с дверью и одним окном, и
	«башенка» за тысячу звёздочек выглядела серым кубом. Теперь у каждого уровня
	свой характер: сруб из брёвен, беленький домик со ставнями и трубой,
	двухэтажный с крыльцом, каменная башенка с круглой башней и флажком.
	Габариты прежние — вокруг них стоят мебель, комнаты букв и пады.
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

	local size = HOUSE_SIZES[level]
	local halfX, halfZ = size.X / 2, size.Z / 2

	-- Точка на стене: front — фасад к площади, side(±1) — боковые стены.
	local function front(x: number, y: number): CFrame
		return at * CFrame.new(x, FLOOR + y, -halfZ)
	end
	local function side(sign: number, z: number, y: number): CFrame
		return at * CFrame.new(sign * halfX, FLOOR + y, z) * CFrame.Angles(0, -sign * math.pi / 2, 0)
	end

	local plinth = part(
		"HousePlinth",
		Vector3.new(size.X + 1.2, 0.6, size.Z + 1.2),
		at * CFrame.new(0, FLOOR + 0.3, 0),
		HOUSE_STONE,
		plot
	)
	plinth.Material = Enum.Material.Slate

	if level == 1 then
		-- Сруб: брёвна двух оттенков внахлёст, в фасаде проём под дверь.
		local core = part(
			"House",
			Vector3.new(size.X - 0.8, size.Y, size.Z - 0.8),
			at * CFrame.new(0, FLOOR + size.Y / 2, 0),
			Color3.fromRGB(150, 110, 75),
			plot
		)
		core.Material = Enum.Material.Wood
		local rows = 6
		for row = 1, rows do
			local y = FLOOR + 0.6 + (row - 0.5) * (size.Y - 0.6) / rows
			local color = if row % 2 == 0 then Color3.fromRGB(200, 150, 100) else Color3.fromRGB(180, 130, 85)
			log(`LogBack_{row}`, size.X + 0.8, 1.05, at * CFrame.new(0, y, halfZ - 0.4), color, plot).Material =
				Enum.Material.Wood
			for _, sign in { -1, 1 } do
				log(
					`LogSide_{sign}_{row}`,
					size.Z + 0.8,
					1.05,
					at * CFrame.new(sign * (halfX - 0.4), y, 0) * CFrame.Angles(0, math.pi / 2, 0),
					color,
					plot
				).Material =
					Enum.Material.Wood
			end
			if y - FLOOR < 4.8 then
				local length = (size.X + 0.8) / 2 - 1.9
				for _, sign in { -1, 1 } do
					log(
						`LogFront_{sign}_{row}`,
						length,
						1.05,
						at * CFrame.new(sign * (1.9 + length / 2), y, -halfZ + 0.4),
						color,
						plot
					).Material =
						Enum.Material.Wood
				end
			else
				log(`LogFront_{row}`, size.X + 0.8, 1.05, at * CFrame.new(0, y, -halfZ + 0.4), color, plot).Material =
					Enum.Material.Wood
			end
		end
		houseDoor(plot, at * CFrame.new(0, FLOOR + 0.6, -halfZ + 0.4), 2.8, 4)
		houseWindow(plot, side(1, 0, 3.4) * CFrame.new(0, 0, -0.55), "WindowSide", 1.8, 1.6)
		return
	end

	local wallColors = {
		nil,
		Color3.fromRGB(250, 242, 225), -- белёный домик
		Color3.fromRGB(255, 225, 165), -- тёплый жёлтый
		Color3.fromRGB(215, 205, 235), -- сиреневый камень
	}
	local walls = part("House", size, at * CFrame.new(0, FLOOR + size.Y / 2, 0), wallColors[level], plot)
	walls.Material = if level == 4 then Enum.Material.Slate else Enum.Material.Plaster

	if level == 2 then
		-- Фахверк: тёмные балки по углам и под крышей.
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				part(
					`CornerBeam_{sx}_{sz}`,
					Vector3.new(0.9, size.Y, 0.9),
					at * CFrame.new(sx * halfX, FLOOR + size.Y / 2, sz * halfZ),
					HOUSE_DARK_WOOD,
					plot
				).Material =
					Enum.Material.Wood
			end
		end
		part(
			"TopBeam",
			Vector3.new(size.X + 0.5, 0.7, size.Z + 0.5),
			at * CFrame.new(0, FLOOR + size.Y - 0.35, 0),
			HOUSE_DARK_WOOD,
			plot
		).Material =
			Enum.Material.Wood

		houseDoor(plot, front(0, 0), 3, 5)
		trim(
			part(
				"Doorstep",
				Vector3.new(4, 0.4, 1.4),
				front(0, 0.2) * CFrame.new(0, 0, -0.7),
				HOUSE_STONE,
				plot
			)
		)
		local awning = part(
			"DoorAwning",
			Vector3.new(4.4, 0.3, 1.8),
			front(0, 5.9) * CFrame.new(0, 0, -0.8) * CFrame.Angles(math.rad(-18), 0, 0),
			Color3.fromRGB(200, 90, 80),
			plot
		)
		trim(awning)
		local green = Color3.fromRGB(110, 170, 120)
		for _, x in { -4.3, 4.3 } do
			houseWindow(plot, front(x, 4.4), `Window_{x}`, 2.4, 2.4, green, true)
		end
		for _, sign in { -1, 1 } do
			houseWindow(plot, side(sign, 0, 4.4), `WindowSide_{sign}`, 2.2, 2.2, green)
		end
		chimney(plot, at, 3.2, 3.2, level)
	elseif level == 3 then
		part(
			"FloorBand",
			Vector3.new(size.X + 0.6, 0.6, size.Z + 0.6),
			at * CFrame.new(0, FLOOR + 7, 0),
			HOUSE_WHITE,
			plot
		)
		part(
			"Cornice",
			Vector3.new(size.X + 0.6, 0.6, size.Z + 0.6),
			at * CFrame.new(0, FLOOR + size.Y - 0.3, 0),
			HOUSE_WHITE,
			plot
		)

		-- Крыльцо с навесом на двух столбиках.
		local porch = part(
			"Porch",
			Vector3.new(7, 0.6, 3),
			front(0, 0.3) * CFrame.new(0, 0, -1.5),
			Color3.fromRGB(200, 160, 120),
			plot
		)
		porch.Material = Enum.Material.WoodPlanks
		for _, x in { -3, 3 } do
			trim(
				part(
					`PorchPost_{x}`,
					Vector3.new(0.5, 5, 0.5),
					front(x, 3) * CFrame.new(0, 0, -2.6),
					HOUSE_WHITE,
					plot
				)
			)
		end
		trim(
			part(
				"PorchRoof",
				Vector3.new(8, 0.4, 3.8),
				front(0, 5.6) * CFrame.new(0, 0, -1.7) * CFrame.Angles(math.rad(-12), 0, 0),
				Color3.fromRGB(200, 90, 80),
				plot
			)
		)
		houseDoor(plot, front(0, 0.6), 3, 4.8)

		local blue = Color3.fromRGB(90, 140, 205)
		for _, x in { -5, 5 } do
			houseWindow(plot, front(x, 3.4), `Window1_{x}`, 2.4, 2.4, blue)
		end
		for _, x in { -5, 0, 5 } do
			houseWindow(plot, front(x, 10.4), `Window2_{x}`, 2.4, 2.4, blue, x == 0)
		end
		for _, sign in { -1, 1 } do
			houseWindow(plot, side(sign, 0, 3.4), `WindowSide1_{sign}`, 2.2, 2.2)
			houseWindow(plot, side(sign, 0, 10.4), `WindowSide2_{sign}`, 2.2, 2.2)
		end
		chimney(plot, at, 4.5, 4, level)
	else
		-- Башенка: каменный дом, круглая башня на переднем углу, зубцы и флажок.
		local stone = Color3.fromRGB(195, 185, 220)
		for _, y in { 6.8, 13.6 } do
			part(
				`StoneBand_{y}`,
				Vector3.new(size.X + 0.5, 0.6, size.Z + 0.5),
				at * CFrame.new(0, FLOOR + y, 0),
				HOUSE_WHITE,
				plot
			).Material =
				Enum.Material.Slate
		end
		for _, corner in { { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			cylinder(
				`CornerColumn_{corner[1]}_{corner[2]}`,
				size.Y,
				1.8,
				at * CFrame.new(corner[1] * halfX, FLOOR + size.Y / 2, corner[2] * halfZ),
				stone,
				plot
			).Material =
				Enum.Material.Slate
		end

		local turretAt = at * CFrame.new(-halfX, 0, -halfZ)
		local turretHeight = size.Y + 6
		cylinder(
			"Turret",
			turretHeight,
			6,
			turretAt * CFrame.new(0, FLOOR + turretHeight / 2, 0),
			stone,
			plot
		).Material =
			Enum.Material.Slate
		cylinder(
			"TurretRing",
			1,
			6.8,
			turretAt * CFrame.new(0, FLOOR + turretHeight - 0.5, 0),
			HOUSE_WHITE,
			plot
		).Material =
			Enum.Material.Slate
		for tooth = 1, 8 do
			local angle = (tooth - 1) / 8 * math.pi * 2
			part(
				`TurretTooth_{tooth}`,
				Vector3.new(1.1, 1.3, 1.1),
				turretAt * CFrame.Angles(0, angle, 0) * CFrame.new(0, FLOOR + turretHeight + 0.65, -2.9),
				HOUSE_WHITE,
				plot
			).Material =
				Enum.Material.Slate
		end
		trim(
			part(
				"TurretFlagPole",
				Vector3.new(0.25, 5, 0.25),
				turretAt * CFrame.new(0, FLOOR + turretHeight + 2.5, 0),
				HOUSE_WHITE,
				plot
			)
		)
		local flag = trim(
			part(
				"TurretFlag",
				Vector3.new(2.4, 1.4, 0.12),
				turretAt * CFrame.new(1.3, FLOOR + turretHeight + 4.2, 0),
				Color3.fromRGB(230, 80, 80),
				plot
			)
		)
		flag.Material = Enum.Material.Fabric
		for _, y in { 9, 17 } do
			-- Узкие окна башни смотрят по диагонали, наружу от угла.
			houseWindow(
				plot,
				turretAt
					* CFrame.new(0, FLOOR + y, 0)
					* CFrame.Angles(0, math.rad(45), 0)
					* CFrame.new(0, 0, -2.95),
				`TurretWindow_{y}`,
				1.2,
				2.2
			)
		end

		houseDoor(plot, front(1.5, 0), 3.2, 5, true)
		houseWindow(plot, front(5, 3.6), "Window1", 2, 2.4)
		for _, x in { -1.5, 4.5 } do
			houseWindow(plot, front(x, 10.2), `Window2_{x}`, 2, 2.6, nil, true)
			houseWindow(plot, front(x, 17), `Window3_{x}`, 2, 2.6)
		end
		for _, y in { 10.2, 17 } do
			houseWindow(plot, side(1, 0, y), `WindowSide_{y}`, 2, 2.6)
		end
		houseWindow(plot, side(-1, 2, 10.2), "WindowLeft", 2, 2.6)
	end
end

--[[
	Крыша живёт только над домом: без дома её ставить некуда.

	Это единственная зависимость между категориями, и она односторонняя —
	купленный уровень крыши не пропадает, он просто ждёт дом.

	Двускатная, конёк вдоль участка: к площади смотрит треугольник фронтона —
	тот самый дом, который дети рисуют. Раньше крыша была плитой и кубиком
	на ней. Материал и цвет — от уровня крыши, размер — от уровня дома.
]]
local ROOF_STYLES = {
	{ -- солома
		colors = { Color3.fromRGB(225, 190, 110) },
		material = Enum.Material.Grass,
		ridge = Color3.fromRGB(175, 135, 75),
	},
	{ -- черепица
		colors = { Color3.fromRGB(195, 95, 75) },
		material = Enum.Material.ClayRoofTiles,
		ridge = Color3.fromRGB(150, 70, 55),
	},
	{ -- цветная: полосы поперёк ската
		colors = {
			Color3.fromRGB(235, 100, 100),
			Color3.fromRGB(250, 190, 80),
			Color3.fromRGB(120, 200, 130),
			Color3.fromRGB(100, 165, 235),
			Color3.fromRGB(175, 120, 220),
		},
		material = Enum.Material.SmoothPlastic,
		ridge = HOUSE_WHITE,
	},
	{ -- светящаяся: золото, гирлянда по карнизу и звезда
		colors = { Color3.fromRGB(255, 200, 80) },
		material = Enum.Material.Foil,
		ridge = Color3.fromRGB(255, 240, 170),
	},
}

local function buildRoof(plot: Model, at: CFrame, level: number, houseLevel: number)
	if level <= 0 or houseLevel <= 0 then
		return
	end

	local size = HOUSE_SIZES[houseLevel]
	local width = size.X + ROOF_OVERHANG * 2
	local depth = size.Z + ROOF_OVERHANG * 2
	local rise = roofRise(houseLevel)
	local base = FLOOR + size.Y
	local style = ROOF_STYLES[level]
	local stripes = #style.colors

	for _, sign in { -1, 1 } do
		for stripe = 1, stripes do
			local stripeDepth = depth / stripes
			-- Клин высокой гранью к коньку: локальная +Z клина развёрнута к центру дома.
			local slope = wedge(
				`Roof_{sign}_{stripe}`,
				Vector3.new(stripeDepth, rise, width / 2),
				at
					* CFrame.new(sign * width / 4, base + rise / 2, -depth / 2 + (stripe - 0.5) * stripeDepth)
					* CFrame.Angles(0, -sign * math.pi / 2, 0),
				style.colors[stripe],
				plot
			)
			slope.Material = style.material
		end
	end

	local ridge = log(
		"RoofRidge",
		depth + 0.4,
		0.9,
		at * CFrame.new(0, base + rise, 0) * CFrame.Angles(0, math.pi / 2, 0),
		style.ridge,
		plot
	)
	trim(ridge)

	-- Круглое чердачное окошко во фронтоне.
	if level >= 2 then
		local diameter = rise * 0.42
		for index, spec in { { diameter, HOUSE_WHITE }, { diameter * 0.7, HOUSE_GLASS } } do
			local disc = log(
				`AtticWindow_{index}`,
				0.3,
				spec[1],
				at
					* CFrame.new(0, base + rise * 0.33, -depth / 2 - 0.1 - index * 0.08)
					* CFrame.Angles(0, math.pi / 2, 0),
				spec[2],
				plot
			)
			trim(disc)
		end
	end

	if level >= 4 then
		ridge.Material = Enum.Material.Neon
		local bulbs =
			{ Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 150, 190), Color3.fromRGB(140, 220, 255) }
		local count = math.floor(depth / 1.8)
		for _, sign in { -1, 1 } do
			for index = 1, count do
				local bulb = ball(
					`RoofBulb_{sign}_{index}`,
					0.8,
					at
						* CFrame.new(
							sign * (width / 2 - 0.15),
							base - 0.05,
							-depth / 2 + (index - 0.5) * depth / count
						),
					bulbs[(index - 1) % #bulbs + 1],
					plot
				)
				bulb.Material = Enum.Material.Neon
				trim(bulb)
			end
		end
		local star = ball(
			"RoofStar",
			1.6,
			at * CFrame.new(0, base + rise + 1.2, -depth / 2 + 0.6),
			Color3.fromRGB(255, 225, 90),
			plot
		)
		star.Material = Enum.Material.Neon
		trim(star)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 220, 140)
		light.Range = 16
		light.Brightness = 1.2
		light.Parent = star
	end
end

-- Двор: от голой земли до фонтана. Растёт вокруг дома, а не вместо него.
local function buildYard(plot: Model, at: CFrame, level: number)
	--[[
		Двор без травы — не голая земля, а выгоревшая светлая трава и вскопанная
		площадка под дом. Участок вырос до 64 студов, и двадцать голых коричневых
		квадратов вокруг парка читались как стройка на весь посёлок. Купленная
		«Трава» по-прежнему видна сразу: двор становится сочно-зелёным.
	]]
	local ground = part(
		"Ground",
		Vector3.new(Base.PLOT_SIZE, FLOOR, Base.PLOT_SIZE),
		at * CFrame.new(0, FLOOR / 2, 0),
		if level >= 1 then GRASS else Color3.fromRGB(196, 205, 150),
		plot
	)
	ground.Material = Enum.Material.Grass
	if level <= 0 then
		local site =
			part("BuildingSite", Vector3.new(18, 0.1, 18), at * CFrame.new(0, FLOOR + 0.05, 0), SOIL, plot)
		site.Material = Enum.Material.Ground
		site.CanCollide = false
	end

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
		--[[
			Кусты вдоль переднего забора по обе стороны от калитки. Раньше они
			стояли кольцом вокруг дома и влезали в мебель и комнаты; у забора
			им ничего не мешает, и сад виден с дорожки.
		]]
		local index = 0
		for _, side in { -1, 1 } do
			for _, x in { 21, 25, 29 } do
				index += 1
				local bush = ball(
					`Bush_{index}`,
					3,
					at * CFrame.new(side * x, FLOOR + 1.2, -Base.PLOT_SIZE / 2 + 2.5),
					Color3.fromRGB(120, 185, 130),
					plot
				)
				bush.Material = Enum.Material.Grass
			end
		end
	end

	if level >= 4 then
		-- Фонтан на дорожке перед домом: сзади его закрывали комнаты букв и цифр.
		local spot = at * CFrame.new(0, 0, -18)
		cylinder(
			"FountainBowl",
			1.6,
			8,
			spot * CFrame.new(0, FLOOR + 0.8, 0),
			Color3.fromRGB(215, 220, 230),
			plot
		)
		cylinder(
			"FountainPillar",
			2.6,
			1.2,
			spot * CFrame.new(0, FLOOR + 2.6, 0),
			Color3.fromRGB(225, 228, 235),
			plot
		)
		trim(
			cylinder(
				"FountainTop",
				0.5,
				3,
				spot * CFrame.new(0, FLOOR + 3.9, 0),
				Color3.fromRGB(215, 220, 230),
				plot
			)
		)
		local water = cylinder(
			"FountainWater",
			0.3,
			7,
			spot * CFrame.new(0, FLOOR + 1.5, 0),
			Color3.fromRGB(140, 200, 240),
			plot
		)
		trim(
			ball(
				"FountainSpray",
				1.4,
				spot * CFrame.new(0, FLOOR + 4.6, 0),
				Color3.fromRGB(190, 230, 255),
				plot
			)
		).Transparency =
			0.3
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
		--[[
			Гирлянда над калиткой: её видно с дорожки раньше самого дома.
			Треугольные флажки на верёвке между двумя столбиками — раньше это были
			семь плоских квадратов, висевших в воздухе перед фасадом.
		]]
		local gateZ = -Base.PLOT_SIZE / 2 + 2
		for _, side in { -1, 1 } do
			part(
				`BuntingPole_{side}`,
				Vector3.new(0.4, 7, 0.4),
				at * CFrame.new(side * 9, FLOOR + 3.5, gateZ),
				Color3.fromRGB(180, 140, 100),
				plot
			).Material =
				Enum.Material.Wood
		end
		trim(
			part(
				"BuntingRope",
				Vector3.new(18, 0.12, 0.12),
				at * CFrame.new(0, FLOOR + 6.6, gateZ),
				Color3.fromRGB(240, 235, 220),
				plot
			)
		)
		for index = 1, 7 do
			local top = at * CFrame.new((index - 4) * 2.3, FLOOR + 6.55, gateZ)
			-- Флажок из двух клиньев: вертикальные рёбра сходятся в середине, остриё вниз.
			for _, half in { -1, 1 } do
				local flag = wedge(
					`YardFlag_{index}_{half}`,
					Vector3.new(0.12, 1.5, 0.7),
					top
						* CFrame.new(half * 0.35, -0.75, 0)
						* CFrame.Angles(0, half * math.pi / 2, 0)
						* CFrame.Angles(math.pi, 0, 0),
					colors[(index - 1) % #colors + 1],
					plot
				)
				flag.CanCollide = false
			end
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
		--[[
			Фонарики по обе стороны дорожки. Раньше они стояли столбиком при x = −5
			у самого фасада — внутри стен любого дома от «Домика» и выше.
		]]
		local spots =
			{ Vector2.new(-5.5, -12), Vector2.new(5.5, -12), Vector2.new(-5.5, -22), Vector2.new(5.5, -22) }
		for index, spot in spots do
			local post = part(
				`LanternPost_{index}`,
				Vector3.new(0.4, 4, 0.4),
				at * CFrame.new(spot.X, FLOOR + 2, spot.Y),
				Color3.fromRGB(120, 110, 100),
				plot
			)
			post.CanCollide = false
			local lamp = part(
				`Lantern_{index}`,
				Vector3.new(1.4, 1.4, 1.4),
				at * CFrame.new(spot.X, FLOOR + 4.6, spot.Y),
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
	Забор по краю участка. Четыре уровня: колышки с верёвкой, белый штакетник,
	каменная стена со столбами и буквенный забор.

	Буквенный забор — это алфавит: 33 кубика с буквами по порядку. Первая, А,
	стоит справа от калитки, если смотреть на дом с дорожки, и дальше буквы идут
	по кругу, как читают, слева направо, — последняя, Я, встаёт слева от калитки.
	Витрина обучения на границе двора, и её видно соседям.

	Раньше все уровни были одними и теми же столбиками разной высоты, а верхний
	светился жёлтым неоном.
]]
local function fenceRuns(): { { Vector2 } }
	local half = Base.PLOT_SIZE / 2 - 1
	local gate = 3.5
	-- Отрезки по порядку обхода: от калитки вправо (для зрителя с дорожки) и по кругу.
	return {
		{ Vector2.new(-gate, -half), Vector2.new(-half, -half) },
		{ Vector2.new(-half, -half), Vector2.new(-half, half) },
		{ Vector2.new(-half, half), Vector2.new(half, half) },
		{ Vector2.new(half, half), Vector2.new(half, -half) },
		{ Vector2.new(half, -half), Vector2.new(gate, -half) },
	}
end

-- Кадр в точке отрезка: локальная −Z смотрит наружу участка, +X — вдоль обхода.
local function fenceFrame(at: CFrame, a: Vector2, b: Vector2, t: number, y: number): CFrame
	local point = a:Lerp(b, t)
	local direction = (b - a).Unit
	local outward = Vector2.new(direction.Y, -direction.X)
	if outward:Dot(point) < 0 then
		outward = -outward
	end
	local position = Vector3.new(point.X, FLOOR + y, point.Y)
	return at * CFrame.lookAt(position, position + Vector3.new(outward.X, 0, outward.Y))
end

-- Длинная деталь вдоль всего отрезка: верёвка, перекладина, стена.
local function fenceRail(
	plot: Model,
	at: CFrame,
	name: string,
	a: Vector2,
	b: Vector2,
	y: number,
	thickness: Vector2,
	color: Color3
): BasePart
	local length = (b - a).Magnitude
	return part(
		name,
		Vector3.new(length, thickness.Y, thickness.X),
		fenceFrame(at, a, b, 0.5, y),
		color,
		plot
	)
end

local function buildFence(plot: Model, at: CFrame, level: number)
	if level <= 0 then
		return
	end

	local runs = fenceRuns()

	if level == 1 then
		for index, run in runs do
			local length = (run[2] - run[1]).Magnitude
			local count = math.max(1, math.round(length / 4))
			for step = 0, count do
				-- Угловой колышек ставит следующий отрезок: не дублируем.
				if step < count or index == #runs then
					local peg = part(
						`Peg_{index}_{step}`,
						Vector3.new(0.6, 1.8, 0.6),
						fenceFrame(at, run[1], run[2], step / count, 0.9),
						Color3.fromRGB(175, 135, 90),
						plot
					)
					peg.Material = Enum.Material.Wood
				end
			end
			trim(
				fenceRail(
					plot,
					at,
					`Rope_{index}`,
					run[1],
					run[2],
					1.3,
					Vector2.new(0.15, 0.15),
					Color3.fromRGB(235, 215, 165)
				)
			)
		end
	elseif level == 2 then
		for index, run in runs do
			local length = (run[2] - run[1]).Magnitude
			local count = math.max(1, math.round(length / 2.2))
			for step = 0, count - 1 do
				part(
					`Picket_{index}_{step}`,
					Vector3.new(0.9, 3, 0.25),
					fenceFrame(at, run[1], run[2], (step + 0.5) / count, 1.5),
					HOUSE_WHITE,
					plot
				)
			end
			for rail, y in { 1, 2.3 } do
				fenceRail(
					plot,
					at,
					`Rail_{index}_{rail}`,
					run[1],
					run[2],
					y,
					Vector2.new(0.3, 0.35),
					HOUSE_WHITE
				)
			end
		end
	elseif level == 3 then
		for index, run in runs do
			local wall = fenceRail(
				plot,
				at,
				`StoneWall_{index}`,
				run[1],
				run[2],
				1.1,
				Vector2.new(1, 2.2),
				Color3.fromRGB(170, 165, 160)
			)
			wall.Material = Enum.Material.Cobblestone
			local cap = fenceRail(
				plot,
				at,
				`StoneWallCap_{index}`,
				run[1],
				run[2],
				2.35,
				Vector2.new(1.3, 0.35),
				Color3.fromRGB(205, 200, 195)
			)
			cap.Material = Enum.Material.Slate
			local length = (run[2] - run[1]).Magnitude
			local count = math.max(1, math.round(length / 8))
			for step = 0, count do
				if step < count or index == #runs then
					local frame = fenceFrame(at, run[1], run[2], step / count, 0)
					part(
						`StonePillar_{index}_{step}`,
						Vector3.new(1.8, 3.2, 1.8),
						frame * CFrame.new(0, 1.6, 0),
						HOUSE_STONE,
						plot
					).Material =
						Enum.Material.Slate
					part(
						`StonePillarCap_{index}_{step}`,
						Vector3.new(2.2, 0.4, 2.2),
						frame * CFrame.new(0, 3.4, 0),
						Color3.fromRGB(215, 210, 205),
						plot
					).Material =
						Enum.Material.Slate
				end
			end
		end
	else
		for index, run in runs do
			for rail, y in { 0.7, 1.5 } do
				trim(
					fenceRail(
						plot,
						at,
						`LetterRail_{index}_{rail}`,
						run[1],
						run[2],
						y,
						Vector2.new(0.25, 0.3),
						HOUSE_WHITE
					)
				)
			end
		end

		-- Кубики с буквами на равных расстояниях по всему обходу.
		local total = 0
		for _, run in runs do
			total += (run[2] - run[1]).Magnitude
		end
		local letters = Letters.ordered()
		local spacing = total / #letters
		for order, letterId in letters do
			local letter = Letters.expect(letterId)
			local distance = (order - 0.5) * spacing
			for _, run in runs do
				local length = (run[2] - run[1]).Magnitude
				if distance <= length then
					local cube = part(
						`LetterBlock_{letterId}`,
						Vector3.new(2.2, 2.2, 2.2),
						fenceFrame(at, run[1], run[2], distance / length, 1.1),
						letter.color:Lerp(Color3.new(1, 1, 1), 0.15),
						plot
					)
					for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
						local gui = Instance.new("SurfaceGui")
						gui.Face = face
						gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
						gui.PixelsPerStud = 40
						gui.LightInfluence = 0
						gui.MaxDistance = 80
						gui.Parent = cube
						local label = Instance.new("TextLabel")
						label.Size = UDim2.fromScale(1, 1)
						label.BackgroundTransparency = 1
						label.Text = letter.glyph
						label.TextColor3 = Color3.fromRGB(255, 255, 255)
						label.TextStrokeColor3 = Color3.fromRGB(35, 30, 50)
						label.TextStrokeTransparency = 0
						label.TextScaled = true
						label.Font = Enum.Font.FredokaOne
						label.Parent = gui
					end
					cube.Material = Enum.Material.SmoothPlastic
					break
				end
				distance -= length
			end
		end
	end
end

-- ===== Наборы вокруг дома ========================================================
--[[
	Огород, площадка, живность и транспорт (Config/Base, docs/15-HOME-BASE.md § 3).
	Набираются, как мебель: у вещи каждого уровня своё место, и купленная тыква
	не выкидывает подсолнухи. Строитель получает точку на земле в центре места,
	ось −Z смотрит на площадь.

	Всё из деталей, пока нет моделей, но каждая вещь обязана узнаваться
	издалека: морковка — оранжевая с хвостиком, пони — с гривой и хвостом.
]]
local WOOD = Color3.fromRGB(190, 145, 100)
local DARK_WOOD = Color3.fromRGB(140, 100, 70)
local LEAF = Color3.fromRGB(110, 180, 90)
local WHITE = Color3.fromRGB(250, 250, 245)
local BLACK = Color3.fromRGB(45, 45, 55)
local ORANGE = Color3.fromRGB(245, 145, 50)

local function tilted(cframe: CFrame, x: number, y: number, z: number): CFrame
	return cframe * CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- Глазки-бусинки: два чёрных шарика на морде, смотрят туда, куда смотрит голова.
local function eyes(plot: Model, head: CFrame, name: string, spread: number, size: number)
	for _, side in { -1, 1 } do
		trim(ball(`{name}Eye_{side}`, size, head * CFrame.new(side * spread, 0, 0), BLACK, plot))
	end
end

local GARDEN = {
	-- Грядка: тёмная земля в досках и два ряда морковок с зелёными хвостиками.
	function(plot: Model, at: CFrame)
		local soil = part(
			"GardenBed",
			Vector3.new(5, 0.6, 6),
			at * CFrame.new(0, 0.3, 0),
			Color3.fromRGB(115, 80, 55),
			plot
		)
		soil.Material = Enum.Material.Ground
		for _, side in { -1, 1 } do
			local board = part(
				`GardenBoard_{side}`,
				Vector3.new(0.4, 0.9, 6.4),
				at * CFrame.new(side * 2.7, 0.45, 0),
				WOOD,
				plot
			)
			board.Material = Enum.Material.WoodPlanks
			part(
				`GardenBoardEnd_{side}`,
				Vector3.new(5.8, 0.9, 0.4),
				at * CFrame.new(0, 0.45, side * 3),
				WOOD,
				plot
			).Material =
				Enum.Material.WoodPlanks
		end
		for row = -1, 1, 2 do
			for step = 1, 4 do
				local spot = at * CFrame.new(row * 1.2, 0.75, -2.7 + step * 1.1)
				trim(cylinder(`Carrot_{row}_{step}`, 0.5, 0.55, spot, ORANGE, plot))
				for leaf = -1, 1, 2 do
					trim(
						part(
							`CarrotLeaf_{row}_{step}_{leaf}`,
							Vector3.new(0.15, 1, 0.35),
							tilted(spot * CFrame.new(leaf * 0.12, 0.7, 0), 0, 0, leaf * 18),
							LEAF,
							plot
						)
					)
				end
			end
		end
	end,

	-- Подсолнухи: четыре разной высоты, головы смотрят на калитку.
	function(plot: Model, at: CFrame)
		for index = 1, 4 do
			local height = 4 + (index % 3) * 0.8
			local base = at * CFrame.new(-2.7 + index * 1.1, 0, (index % 2) * 0.8 - 0.4)
			trim(
				cylinder(
					`SunflowerStem_{index}`,
					height,
					0.3,
					base * CFrame.new(0, height / 2, 0),
					Color3.fromRGB(95, 160, 80),
					plot
				)
			)
			for _, side in { -1, 1 } do
				trim(
					part(
						`SunflowerLeaf_{index}_{side}`,
						Vector3.new(1, 0.15, 0.6),
						tilted(base * CFrame.new(side * 0.55, height * 0.45, 0), 0, 0, side * 25),
						LEAF,
						plot
					)
				)
			end
			local head = tilted(base * CFrame.new(0, height, -0.2), -15, 0, 0)
			local petals = trim(
				part(
					`SunflowerPetals_{index}`,
					Vector3.new(0.2, 2.3, 2.3),
					head * CFrame.Angles(0, math.pi / 2, 0),
					Color3.fromRGB(255, 205, 50),
					plot
				)
			)
			petals.Shape = Enum.PartType.Cylinder
			local middle = trim(
				part(
					`SunflowerMiddle_{index}`,
					Vector3.new(0.3, 1.2, 1.2),
					head * CFrame.new(0, 0, -0.08) * CFrame.Angles(0, math.pi / 2, 0),
					Color3.fromRGB(120, 80, 45),
					plot
				)
			)
			middle.Shape = Enum.PartType.Cylinder
		end
	end,

	-- Тыквы: каждая из трёх шаров бок о бок — так она пузатая и с долями.
	function(plot: Model, at: CFrame)
		local layout = { { -1.1, -0.6, 2 }, { 1.2, 0.2, 1.5 }, { -0.2, 1.4, 1.1 } }
		for index, spec in layout do
			local size = spec[3]
			local spot = at * CFrame.new(spec[1], size * 0.42, spec[2]) * CFrame.Angles(0, index, 0)
			ball(`Pumpkin_{index}`, size, spot, ORANGE, plot)
			for _, side in { -1, 1 } do
				trim(
					ball(
						`PumpkinSide_{index}_{side}`,
						size * 0.85,
						spot * CFrame.new(side * size * 0.28, -size * 0.04, 0),
						Color3.fromRGB(235, 130, 40),
						plot
					)
				)
			end
			trim(
				cylinder(
					`PumpkinStem_{index}`,
					0.5,
					0.25,
					spot * CFrame.new(0, size * 0.5, 0),
					Color3.fromRGB(110, 130, 60),
					plot
				)
			)
			trim(
				part(
					`PumpkinLeaf_{index}`,
					Vector3.new(0.9, 0.1, 0.6),
					tilted(spot * CFrame.new(0.4, size * 0.45, 0), 0, 0, -20),
					LEAF,
					plot
				)
			)
		end
	end,

	-- Яблоня: крона из трёх шаров, румяные яблоки на ней и два в траве.
	function(plot: Model, at: CFrame)
		cylinder("AppleTrunk", 5, 1.1, at * CFrame.new(0, 2.5, 0), Color3.fromRGB(135, 95, 65), plot).Material =
			Enum.Material.Wood
		local crown = at * CFrame.new(0, 6.5, 0)
		for index, spec in { { 0, 0.6, 0, 5 }, { -1.6, -0.4, 0.4, 3.6 }, { 1.6, -0.3, -0.3, 3.8 } } do
			local leaves = trim(
				ball(
					`AppleCrown_{index}`,
					spec[4],
					crown * CFrame.new(spec[1], spec[2], spec[3]),
					Color3.fromRGB(95, 170, 85),
					plot
				)
			)
			leaves.Material = Enum.Material.Grass
		end
		for index = 1, 8 do
			local angle = index / 8 * math.pi * 2
			local lift = (index % 3) * 0.7 - 0.9
			trim(
				ball(
					`Apple_{index}`,
					0.7,
					crown * CFrame.new(math.cos(angle) * 2.3, lift, math.sin(angle) * 2.3),
					Color3.fromRGB(225, 50, 55),
					plot
				)
			)
		end
		trim(ball("AppleFallen_1", 0.7, at * CFrame.new(1.4, 0.35, -1.2), Color3.fromRGB(225, 50, 55), plot))
		trim(ball("AppleFallen_2", 0.7, at * CFrame.new(-1, 0.35, -1.6), Color3.fromRGB(240, 200, 60), plot))
	end,
}

local PLAYGROUND = {
	-- Песочница: песок в ярких досках, ведёрко, совок и башенка из песка.
	function(plot: Model, at: CFrame)
		local sand = part(
			"Sand",
			Vector3.new(5.4, 0.5, 5.4),
			at * CFrame.new(0, 0.25, 0),
			Color3.fromRGB(240, 215, 150),
			plot
		)
		sand.Material = Enum.Material.Sand
		local colors = {
			Color3.fromRGB(240, 110, 110),
			Color3.fromRGB(110, 170, 240),
			Color3.fromRGB(250, 205, 80),
			Color3.fromRGB(120, 200, 120),
		}
		for index = 1, 4 do
			local angle = index / 4 * math.pi * 2
			part(
				`SandboxBoard_{index}`,
				Vector3.new(6.2, 0.9, 0.5),
				at * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.45, 2.95),
				colors[index],
				plot
			)
		end
		trim(
			cylinder(
				"SandBucket",
				0.9,
				0.9,
				at * CFrame.new(1.4, 0.95, -1.2),
				Color3.fromRGB(230, 60, 70),
				plot
			)
		)
		trim(
			part(
				"SandSpadeHandle",
				Vector3.new(0.15, 1.4, 0.15),
				tilted(at * CFrame.new(-1.5, 1.1, -1.2), 0, 0, 30),
				Color3.fromRGB(70, 130, 220),
				plot
			)
		)
		trim(
			part(
				"SandSpadeBlade",
				Vector3.new(0.6, 0.5, 0.1),
				tilted(at * CFrame.new(-1.9, 0.6, -1.2), 0, 0, 30),
				Color3.fromRGB(70, 130, 220),
				plot
			)
		)
		local castle = at * CFrame.new(0, 0.5, 1)
		trim(
			cylinder(
				"SandCastle",
				1,
				1.8,
				castle * CFrame.new(0, 0.5, 0),
				Color3.fromRGB(225, 195, 130),
				plot
			)
		)
		trim(
			cylinder(
				"SandCastleTop",
				0.8,
				1,
				castle * CFrame.new(0, 1.4, 0),
				Color3.fromRGB(225, 195, 130),
				plot
			)
		)
		trim(
			part(
				"SandCastleFlag",
				Vector3.new(0.6, 0.4, 0.05),
				castle * CFrame.new(0.3, 2.2, 0),
				Color3.fromRGB(240, 90, 90),
				plot
			)
		)
	end,

	--[[
		Горка: ступеньки слева, площадка с перилами, скат направо. Всё
		проходимо: по ступенькам забираются, по скату съезжают бегом.
	]]
	function(plot: Model, at: CFrame)
		for step = 1, 5 do
			local x = -6.3 + step * 0.8
			part(
				`SlideStep_{step}`,
				Vector3.new(0.8, step, 3),
				at * CFrame.new(x, step / 2, 0),
				Color3.fromRGB(250, 205, 80),
				plot
			)
		end
		local deck = part(
			"SlideDeck",
			Vector3.new(3, 0.5, 3),
			at * CFrame.new(-0.9, 4.75, 0),
			Color3.fromRGB(110, 170, 240),
			plot
		)
		deck.Material = Enum.Material.WoodPlanks
		-- Столбы по углам и перила по бокам, без крыши: ребёнку на площадке нужна голова.
		for _, x in { -2.2, 0.4 } do
			for _, z in { -1.45, 1.45 } do
				part(
					`SlidePost_{x}_{z}`,
					Vector3.new(0.4, 6.4, 0.4),
					at * CFrame.new(x, 3.2, z),
					Color3.fromRGB(240, 110, 110),
					plot
				)
				trim(
					ball(
						`SlidePostTop_{x}_{z}`,
						0.7,
						at * CFrame.new(x, 6.5, z),
						Color3.fromRGB(120, 200, 120),
						plot
					)
				)
			end
		end
		for _, z in { -1.45, 1.45 } do
			trim(
				part(
					`SlideRail_{z}`,
					Vector3.new(2.6, 0.3, 0.3),
					at * CFrame.new(-0.9, 6.1, z),
					Color3.fromRGB(240, 110, 110),
					plot
				)
			)
		end
		local from = Vector3.new(0.6, 5, 0)
		local to = Vector3.new(6.3, 0.4, 0)
		local length = (to - from).Magnitude
		local angle = math.atan2(from.Y - to.Y, to.X - from.X)
		local mid = (from + to) / 2
		local slide = part(
			"Slide",
			Vector3.new(length, 0.3, 2.4),
			at * CFrame.new(mid) * CFrame.Angles(0, 0, -angle),
			Color3.fromRGB(110, 170, 240),
			plot
		)
		slide.Material = Enum.Material.SmoothPlastic
		for _, z in { -1.3, 1.3 } do
			trim(
				part(
					`SlideSide_{z}`,
					Vector3.new(length, 0.6, 0.2),
					at * CFrame.new(mid + Vector3.new(0, 0.35, z)) * CFrame.Angles(0, 0, -angle),
					Color3.fromRGB(250, 205, 80),
					plot
				)
			)
		end
	end,

	-- Батут: пружинит так же, как батуты в парке (метка AF_Trampoline).
	function(plot: Model, at: CFrame)
		cylinder(
			"HomeTrampolineFrame",
			1.4,
			5.4,
			at * CFrame.new(0, 0.7, 0),
			Color3.fromRGB(70, 150, 220),
			plot
		)
		for leg = 1, 4 do
			local angle = leg / 4 * math.pi * 2 + math.pi / 4
			trim(
				part(
					`HomeTrampolineLeg_{leg}`,
					Vector3.new(0.4, 0.8, 0.4),
					at * CFrame.new(math.cos(angle) * 2.4, 0.2, math.sin(angle) * 2.4),
					BLACK,
					plot
				)
			)
		end
		local top = cylinder(
			"HomeTrampoline",
			0.3,
			4.4,
			at * CFrame.new(0, 1.55, 0),
			Color3.fromRGB(255, 120, 170),
			plot
		)
		top.Material = Enum.Material.Fabric
		top:SetAttribute("Power", 70)
		CollectionService:AddTag(top, "AF_Trampoline")
	end,

	-- Карусель: круглый пол, столб, полосатый купол и четыре лошадки на шестах.
	function(plot: Model, at: CFrame)
		cylinder("CarouselFloor", 0.6, 7, at * CFrame.new(0, 0.3, 0), Color3.fromRGB(250, 235, 200), plot)
		-- Всё выше пола крутится: пол стоит, чтобы на него можно было встать.
		plot = moving(plot, "CarouselSpin")
		local pole =
			cylinder("CarouselPole", 6, 0.7, at * CFrame.new(0, 3.5, 0), Color3.fromRGB(250, 205, 80), plot)
		pole:SetAttribute("Speed", 0.6)
		CollectionService:AddTag(pole, "AF_Spin")
		trim(
			cylinder(
				"CarouselRoof",
				0.6,
				7.4,
				at * CFrame.new(0, 6.6, 0),
				Color3.fromRGB(240, 110, 110),
				plot
			)
		)
		trim(cylinder("CarouselRoofStripe", 0.7, 5, at * CFrame.new(0, 7, 0), WHITE, plot))
		trim(
			cylinder(
				"CarouselRoofTop",
				0.7,
				2.6,
				at * CFrame.new(0, 7.5, 0),
				Color3.fromRGB(240, 110, 110),
				plot
			)
		)
		trim(ball("CarouselBall", 1, at * CFrame.new(0, 8.2, 0), Color3.fromRGB(250, 205, 80), plot)).Material =
			Enum.Material.Neon
		local colors = {
			WHITE,
			Color3.fromRGB(255, 190, 215),
			Color3.fromRGB(190, 220, 255),
			Color3.fromRGB(255, 230, 150),
		}
		for index = 1, 4 do
			local angle = index / 4 * math.pi * 2
			local spot = at * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, 2.6)
			trim(
				cylinder(
					`CarouselHorsePole_{index}`,
					6,
					0.2,
					spot * CFrame.new(0, 3.6, 0),
					Color3.fromRGB(250, 205, 80),
					plot
				)
			)
			local lift = 1.9 + (index % 2) * 0.6
			local color = colors[index]
			trim(
				part(
					`CarouselHorse_{index}`,
					Vector3.new(1.8, 0.8, 0.7),
					spot * CFrame.new(0, lift, 0),
					color,
					plot
				)
			)
			trim(
				part(
					`CarouselHorseHead_{index}`,
					Vector3.new(0.6, 0.9, 0.5),
					tilted(spot * CFrame.new(0.95, lift + 0.55, 0), 0, 0, -25),
					color,
					plot
				)
			)
			trim(
				part(
					`CarouselHorseMane_{index}`,
					Vector3.new(0.3, 0.8, 0.55),
					tilted(spot * CFrame.new(0.65, lift + 0.6, 0), 0, 0, -25),
					Color3.fromRGB(240, 110, 110),
					plot
				)
			)
			for _, legX in { -0.6, 0.6 } do
				trim(
					part(
						`CarouselHorseLeg_{index}_{legX}`,
						Vector3.new(0.2, 0.7, 0.5),
						tilted(spot * CFrame.new(legX, lift - 0.6, 0), 0, 0, legX * 40),
						color,
						plot
					)
				)
			end
		end
	end,
}

local PETS = {
	-- Будка со щенком: щенок лежит у входа и смотрит на калитку.
	function(plot: Model, at: CFrame)
		local house = part(
			"Doghouse",
			Vector3.new(3, 2.4, 3),
			at * CFrame.new(0, 1.2, 0.6),
			Color3.fromRGB(215, 110, 80),
			plot
		)
		house.Material = Enum.Material.WoodPlanks
		for _, side in { -1, 1 } do
			local roof = part(
				`DoghouseRoof_{side}`,
				Vector3.new(0.3, 2.3, 3.6),
				tilted(at * CFrame.new(side * 0.85, 3, 0.6), 0, 0, side * 45),
				Color3.fromRGB(120, 90, 160),
				plot
			)
			roof.Material = Enum.Material.WoodPlanks
		end
		trim(part("DoghouseDoor", Vector3.new(1.4, 1.6, 0.1), at * CFrame.new(0, 0.8, -0.92), BLACK, plot))
		trim(part("DoghouseSign", Vector3.new(1.2, 0.4, 0.1), at * CFrame.new(0, 2.05, -0.92), WHITE, plot))
		local dog = at * CFrame.new(0.2, 0, -1.8)
		local fur = Color3.fromRGB(225, 180, 120)
		trim(ball("PuppyBody", 1.1, dog * CFrame.new(0, 0.5, 0.3), fur, plot))
		trim(ball("PuppyBack", 1, dog * CFrame.new(0, 0.45, 0.9), fur, plot))
		local head = dog * CFrame.new(0, 1, -0.35)
		trim(ball("PuppyHead", 0.9, head, fur, plot))
		trim(ball("PuppyNose", 0.25, head * CFrame.new(0, -0.1, -0.45), BLACK, plot))
		eyes(plot, head * CFrame.new(0, 0.12, -0.38), "Puppy", 0.2, 0.14)
		for _, side in { -1, 1 } do
			trim(
				part(
					`PuppyEar_{side}`,
					Vector3.new(0.25, 0.6, 0.4),
					tilted(head * CFrame.new(side * 0.45, 0, 0), 0, 0, side * 15),
					Color3.fromRGB(150, 100, 60),
					plot
				)
			)
			trim(ball(`PuppyPaw_{side}`, 0.35, dog * CFrame.new(side * 0.3, 0.17, -0.4), fur, plot))
		end
		trim(
			part(
				"PuppyTail",
				Vector3.new(0.15, 0.7, 0.15),
				tilted(dog * CFrame.new(0, 0.8, 1.4), -40, 0, 0),
				fur,
				plot
			)
		)
		trim(
			cylinder(
				"PuppyBowl",
				0.3,
				0.8,
				at * CFrame.new(-1.3, 0.15, -1.5),
				Color3.fromRGB(230, 60, 70),
				plot
			)
		)
	end,

	-- Курятник на ножках с лесенкой, три курочки и цыплята.
	function(plot: Model, at: CFrame)
		local coop = part(
			"Coop",
			Vector3.new(4, 2.4, 3),
			at * CFrame.new(0, 2.4, 1),
			Color3.fromRGB(250, 230, 180),
			plot
		)
		coop.Material = Enum.Material.WoodPlanks
		for _, x in { -1.8, 1.8 } do
			for _, z in { -0.3, 2.3 } do
				part(
					`CoopLeg_{x}_{z}`,
					Vector3.new(0.3, 1.2, 0.3),
					at * CFrame.new(x, 0.6, z),
					DARK_WOOD,
					plot
				)
			end
		end
		for _, side in { -1, 1 } do
			part(
				`CoopRoof_{side}`,
				Vector3.new(0.3, 2.7, 3.6),
				tilted(at * CFrame.new(side * 1.05, 4.45, 1), 0, 0, side * 50),
				Color3.fromRGB(215, 90, 70),
				plot
			)
		end
		trim(part("CoopDoor", Vector3.new(1, 1.2, 0.1), at * CFrame.new(0.8, 2.1, -0.52), DARK_WOOD, plot))
		trim(
			part(
				"CoopRamp",
				Vector3.new(0.9, 0.15, 2),
				tilted(at * CFrame.new(0.8, 0.8, -1.2), -35, 0, 0),
				WOOD,
				plot
			)
		)
		local hens = { { -1.8, -1.6, 0 }, { -0.4, -2.4, 40 }, { 2.3, -2, -30 } }
		for index, spec in hens do
			local hen = at * CFrame.new(spec[1], 0, spec[2]) * CFrame.Angles(0, math.rad(spec[3]), 0)
			local color = if index == 2 then Color3.fromRGB(190, 120, 70) else WHITE
			trim(ball(`HenBody_{index}`, 1, hen * CFrame.new(0, 0.6, 0.15), color, plot))
			trim(
				part(
					`HenTail_{index}`,
					Vector3.new(0.5, 0.6, 0.25),
					tilted(hen * CFrame.new(0, 0.95, 0.6), 30, 0, 0),
					color,
					plot
				)
			)
			local head = hen * CFrame.new(0, 1.2, -0.35)
			trim(ball(`HenHead_{index}`, 0.55, head, color, plot))
			trim(
				part(
					`HenComb_{index}`,
					Vector3.new(0.12, 0.3, 0.35),
					head * CFrame.new(0, 0.3, 0),
					Color3.fromRGB(230, 50, 50),
					plot
				)
			)
			trim(
				part(
					`HenBeak_{index}`,
					Vector3.new(0.15, 0.12, 0.3),
					head * CFrame.new(0, -0.02, -0.33),
					ORANGE,
					plot
				)
			)
			eyes(plot, head * CFrame.new(0, 0.08, -0.22), `Hen_{index}`, 0.16, 0.1)
			for _, side in { -1, 1 } do
				trim(
					part(
						`HenLeg_{index}_{side}`,
						Vector3.new(0.08, 0.35, 0.08),
						hen * CFrame.new(side * 0.2, 0.15, 0.15),
						ORANGE,
						plot
					)
				)
			end
		end
		for index = 1, 3 do
			local chick = at * CFrame.new(-2.6 + index * 0.55, 0, -3 + (index % 2) * 0.3)
			trim(
				ball(
					`Chick_{index}`,
					0.45,
					chick * CFrame.new(0, 0.22, 0),
					Color3.fromRGB(255, 225, 90),
					plot
				)
			)
			trim(
				ball(
					`ChickHead_{index}`,
					0.3,
					chick * CFrame.new(0, 0.52, -0.1),
					Color3.fromRGB(255, 225, 90),
					plot
				)
			)
		end
	end,

	-- Пруд: камни по кругу, кувшинки, камыши и уточка с утёнком на воде.
	function(plot: Model, at: CFrame)
		local water = trim(
			cylinder("PondWater", 0.2, 5.4, at * CFrame.new(0, 0.12, 0), Color3.fromRGB(100, 175, 230), plot)
		)
		water.Material = Enum.Material.Glass
		water.Transparency = 0.15
		for index = 1, 12 do
			local angle = index / 12 * math.pi * 2
			local size = 0.7 + (index % 3) * 0.2
			ball(
				`PondStone_{index}`,
				size,
				at * CFrame.new(math.cos(angle) * 2.9, size * 0.25, math.sin(angle) * 2.9),
				Color3.fromRGB(165, 160, 155),
				plot
			)
		end
		for index, spec in { { 1.3, 0.9 }, { -1.5, 1.1 }, { 0.4, -1.6 } } do
			local pad = trim(
				cylinder(`LilyPad_{index}`, 0.08, 0.9, at * CFrame.new(spec[1], 0.26, spec[2]), LEAF, plot)
			)
			pad.Material = Enum.Material.Grass
		end
		trim(ball("LilyFlower", 0.35, at * CFrame.new(1.3, 0.4, 0.9), Color3.fromRGB(255, 170, 210), plot))
		for index = 1, 4 do
			local spot = at * CFrame.new(2 + index * 0.25, 0, 1.6 + (index % 2) * 0.4)
			trim(
				cylinder(
					`Reed_{index}`,
					2.2,
					0.12,
					spot * CFrame.new(0, 1.1, 0),
					Color3.fromRGB(110, 150, 70),
					plot
				)
			)
			trim(
				cylinder(
					`ReedTop_{index}`,
					0.5,
					0.25,
					spot * CFrame.new(0, 2.1, 0),
					Color3.fromRGB(120, 85, 55),
					plot
				)
			)
		end
		-- Уточка с утёнком плывут по кругу за невидимым центром пруда.
		local swimming = moving(plot, "PondDucks")
		local center = trim(
			part("PondDucksCenter", Vector3.new(0.2, 0.2, 0.2), at * CFrame.new(0, 0.3, 0), WHITE, swimming)
		)
		center.Transparency = 1
		center:SetAttribute("Speed", -0.35)
		CollectionService:AddTag(center, "AF_Spin")
		plot = swimming
		for index, spec in { { -1.4, 0, 1, 0 }, { 1.4, 0, 0.65, 180 } } do
			local duck = at * CFrame.new(spec[1], 0.25, spec[2]) * CFrame.Angles(0, math.rad(spec[4]), 0)
			local size = spec[3]
			local color = if index == 1 then WHITE else Color3.fromRGB(255, 225, 90)
			trim(ball(`PondDuck_{index}`, size, duck * CFrame.new(0, size * 0.3, 0), color, plot))
			local head = duck * CFrame.new(0, size * 0.85, -size * 0.35)
			trim(ball(`PondDuckHead_{index}`, size * 0.6, head, color, plot))
			trim(
				part(
					`PondDuckBeak_{index}`,
					Vector3.new(size * 0.25, size * 0.1, size * 0.35),
					head * CFrame.new(0, -0.05, -size * 0.35),
					ORANGE,
					plot
				)
			)
			eyes(plot, head * CFrame.new(0, size * 0.08, -size * 0.25), `PondDuck_{index}`, size * 0.15, 0.09)
		end
	end,

	-- Пони: сиреневый, с розовой гривой, хвостом и стожком сена рядом.
	function(plot: Model, at: CFrame)
		local coat = Color3.fromRGB(215, 190, 240)
		local mane = Color3.fromRGB(255, 140, 190)
		local pony = at * CFrame.Angles(0, math.rad(-20), 0)
		part("PonyBody", Vector3.new(2.8, 1.3, 1.3), pony * CFrame.new(0, 1.9, 0), coat, plot)
		for _, x in { -1, 1 } do
			for _, z in { -0.4, 0.4 } do
				part(
					`PonyLeg_{x}_{z}`,
					Vector3.new(0.35, 1.3, 0.35),
					pony * CFrame.new(x, 0.65, z),
					coat,
					plot
				)
				trim(
					part(
						`PonyHoof_{x}_{z}`,
						Vector3.new(0.4, 0.25, 0.4),
						pony * CFrame.new(x, 0.12, z),
						Color3.fromRGB(120, 90, 110),
						plot
					)
				)
			end
		end
		trim(
			part(
				"PonyNeck",
				Vector3.new(0.7, 1.4, 0.8),
				tilted(pony * CFrame.new(-1.35, 2.7, 0), 0, 0, -30),
				coat,
				plot
			)
		)
		local head = pony * CFrame.new(-1.9, 3.3, 0)
		trim(part("PonyHead", Vector3.new(1.3, 0.8, 0.8), head, coat, plot))
		trim(ball("PonyMuzzle", 0.7, head * CFrame.new(-0.6, -0.1, 0), Color3.fromRGB(245, 225, 250), plot))
		for _, side in { -1, 1 } do
			trim(ball(`PonyEye_{side}`, 0.18, head * CFrame.new(-0.15, 0.15, side * 0.4), BLACK, plot))
			trim(
				part(
					`PonyEar_{side}`,
					Vector3.new(0.2, 0.4, 0.2),
					head * CFrame.new(0.3, 0.55, side * 0.25),
					coat,
					plot
				)
			)
		end
		trim(
			part(
				"PonyMane",
				Vector3.new(1.3, 0.5, 0.3),
				tilted(pony * CFrame.new(-1.2, 3.2, 0), 0, 0, -30),
				mane,
				plot
			)
		)
		trim(
			part(
				"PonyTail",
				Vector3.new(0.35, 1.5, 0.35),
				tilted(pony * CFrame.new(1.6, 1.7, 0), 0, 0, 25),
				mane,
				plot
			)
		)
		local hay = part(
			"HayBale",
			Vector3.new(1.6, 1, 1.1),
			at * CFrame.new(0.5, 0.5, -1.7),
			Color3.fromRGB(235, 205, 110),
			plot
		)
		hay.Material = Enum.Material.Grass
	end,
}

local TRANSPORT = {
	-- Велосипед с корзинкой цветов на подножке, едет в сторону калитки.
	function(plot: Model, at: CFrame)
		local frame = Color3.fromRGB(80, 190, 170)
		for _, z in { -1.2, 1.2 } do
			local wheel = trim(
				part(`BikeWheel_{z}`, Vector3.new(0.25, 1.8, 1.8), at * CFrame.new(0, 0.9, z), BLACK, plot)
			)
			wheel.Shape = Enum.PartType.Cylinder
			local hub =
				trim(part(`BikeHub_{z}`, Vector3.new(0.3, 1.1, 1.1), at * CFrame.new(0, 0.9, z), WHITE, plot))
			hub.Shape = Enum.PartType.Cylinder
		end
		trim(
			part(
				"BikeFrame",
				Vector3.new(0.2, 0.2, 2.1),
				tilted(at * CFrame.new(0, 1.5, 0), -15, 0, 0),
				frame,
				plot
			)
		)
		trim(
			part(
				"BikeFork",
				Vector3.new(0.2, 1.3, 0.2),
				tilted(at * CFrame.new(0, 1.5, -1), 20, 0, 0),
				frame,
				plot
			)
		)
		trim(part("BikeSeatPost", Vector3.new(0.2, 1, 0.2), at * CFrame.new(0, 1.6, 0.7), frame, plot))
		trim(part("BikeSeat", Vector3.new(0.4, 0.15, 0.7), at * CFrame.new(0, 2.15, 0.7), BLACK, plot))
		trim(
			part("BikeHandlebar", Vector3.new(1.2, 0.15, 0.15), at * CFrame.new(0, 2.15, -1.25), frame, plot)
		)
		trim(part("BikeBasket", Vector3.new(0.9, 0.6, 0.7), at * CFrame.new(0, 1.9, -1.75), WOOD, plot))
		for index, color in { Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 220, 90), WHITE } do
			trim(
				ball(
					`BikeFlower_{index}`,
					0.35,
					at * CFrame.new(-0.4 + index * 0.25, 2.3, -1.75),
					color,
					plot
				)
			)
		end
	end,

	--[[
		Машинка по размеру ребёнка. В неё можно сесть — это единственная вещь
		во дворе, с которой можно что-то сделать, кроме как смотреть и лазать.
		Встать с сиденья — прыжок, как везде в Roblox.
	]]
	function(plot: Model, at: CFrame)
		local paint = Color3.fromRGB(235, 70, 80)
		part("CarBody", Vector3.new(3.4, 1.4, 6), at * CFrame.new(0, 1.4, 0), paint, plot)
		part("CarCabin", Vector3.new(3, 1.3, 2.8), at * CFrame.new(0, 2.75, 0.6), paint, plot)
		local glass = trim(
			part(
				"CarWindshield",
				Vector3.new(2.6, 1, 0.1),
				at * CFrame.new(0, 2.75, -0.82),
				Color3.fromRGB(180, 225, 250),
				plot
			)
		)
		glass.Material = Enum.Material.Glass
		for _, side in { -1, 1 } do
			local window = trim(
				part(
					`CarWindow_{side}`,
					Vector3.new(0.1, 0.9, 2.2),
					at * CFrame.new(side * 1.52, 2.75, 0.6),
					Color3.fromRGB(180, 225, 250),
					plot
				)
			)
			window.Material = Enum.Material.Glass
			for _, z in { -1.9, 1.9 } do
				local wheel = part(
					`CarWheel_{side}_{z}`,
					Vector3.new(0.7, 1.6, 1.6),
					at * CFrame.new(side * 1.55, 0.8, z),
					BLACK,
					plot
				)
				wheel.Shape = Enum.PartType.Cylinder
				local cap = trim(
					part(
						`CarHubcap_{side}_{z}`,
						Vector3.new(0.75, 0.7, 0.7),
						at * CFrame.new(side * 1.56, 0.8, z),
						Color3.fromRGB(220, 220, 225),
						plot
					)
				)
				cap.Shape = Enum.PartType.Cylinder
			end
			local light = trim(
				ball(
					`CarHeadlight_{side}`,
					0.6,
					at * CFrame.new(side * 1.1, 1.6, -3),
					Color3.fromRGB(255, 240, 170),
					plot
				)
			)
			light.Material = Enum.Material.Neon
		end
		trim(
			part(
				"CarBumper",
				Vector3.new(3.6, 0.35, 0.3),
				at * CFrame.new(0, 0.85, -3.05),
				Color3.fromRGB(220, 220, 225),
				plot
			)
		)
		local seat = Instance.new("Seat")
		seat.Name = "CarSeat"
		seat.Size = Vector3.new(2, 0.4, 1.4)
		seat.CFrame = at * CFrame.new(0, 2.3, 1.2)
		seat.Color = Color3.fromRGB(60, 60, 70)
		seat.Anchored = true
		seat.TopSurface = Enum.SurfaceType.Smooth
		seat.BottomSurface = Enum.SurfaceType.Smooth
		seat.Parent = plot
	end,

	-- Воздушный шар на привязи: корзина на земле, полосатый купол высоко над двором.
	function(plot: Model, at: CFrame)
		local basket = part(
			"BalloonBasket",
			Vector3.new(2.4, 1.8, 2.4),
			at * CFrame.new(0, 0.9, 0),
			Color3.fromRGB(175, 125, 75),
			plot
		)
		basket.Material = Enum.Material.WoodPlanks
		local lift = at * CFrame.new(0, 10, 0)
		local basketPlot = plot
		-- Купол чуть покачивается на привязи; корзина и верёвки стоят.
		plot = moving(plot, "BalloonLift")
		local envelope = trim(ball("BalloonEnvelope", 7, lift, Color3.fromRGB(250, 205, 80), plot))
		envelope.Material = Enum.Material.SmoothPlastic
		envelope:SetAttribute("Amplitude", 0.6)
		envelope:SetAttribute("Period", 4)
		CollectionService:AddTag(envelope, "AF_Float")
		-- Полосы — тонкие диски чуть шире шара, поставленные на ребро.
		for index, color in { Color3.fromRGB(240, 100, 110), Color3.fromRGB(100, 170, 240) } do
			local band = trim(
				part(
					`BalloonBand_{index}`,
					Vector3.new(0.9, 7.1, 7.1),
					lift * CFrame.Angles(0, index * math.pi / 2, 0),
					color,
					plot
				)
			)
			band.Shape = Enum.PartType.Cylinder
		end
		trim(
			cylinder(
				"BalloonNeck",
				1.4,
				2.4,
				lift * CFrame.new(0, -3.6, 0),
				Color3.fromRGB(240, 100, 110),
				plot
			)
		)
		plot = basketPlot
		local flame =
			trim(ball("BalloonFlame", 0.8, at * CFrame.new(0, 3.2, 0), Color3.fromRGB(255, 160, 60), plot))
		flame.Material = Enum.Material.Neon
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				local top = lift.Position
					+ (at.RightVector * x + at.LookVector * -z) * 1.2
					+ Vector3.new(0, -4.3, 0)
				local bottom = (at * CFrame.new(x * 1.1, 1.8, z * 1.1)).Position
				local rope = trim(
					part(
						`BalloonRope_{x}_{z}`,
						Vector3.new(0.1, 0.1, (top - bottom).Magnitude),
						CFrame.lookAt((top + bottom) / 2, top),
						Color3.fromRGB(120, 90, 60),
						plot
					)
				)
				rope.Material = Enum.Material.Fabric
			end
		end
	end,

	-- Ракета на стартовом столе: белая, с красным носом, окошком и тремя крыльями.
	function(plot: Model, at: CFrame)
		local red = Color3.fromRGB(230, 60, 70)
		cylinder("RocketPad", 0.5, 5, at * CFrame.new(0, 0.25, 0), Color3.fromRGB(150, 155, 165), plot)
		cylinder("RocketBody", 6, 2.4, at * CFrame.new(0, 4, 0), WHITE, plot)
		trim(cylinder("RocketBand", 0.5, 2.5, at * CFrame.new(0, 5.6, 0), red, plot))
		for index, spec in { { 1.4, 2 }, { 1, 1.4 }, { 0.8, 0.8 } } do
			trim(
				cylinder(
					`RocketNose_{index}`,
					spec[1],
					spec[2],
					at * CFrame.new(0, 7 + (index - 1) * 1.1 + spec[1] / 2 - 0.2, 0),
					red,
					plot
				)
			)
		end
		trim(ball("RocketTip", 0.6, at * CFrame.new(0, 10.2, 0), red, plot))
		local window = trim(
			part(
				"RocketWindow",
				Vector3.new(0.2, 1.1, 1.1),
				at * CFrame.new(0, 5, -1.15) * CFrame.Angles(0, math.pi / 2, 0),
				Color3.fromRGB(120, 200, 250),
				plot
			)
		)
		window.Shape = Enum.PartType.Cylinder
		window.Material = Enum.Material.Neon
		for index = 1, 3 do
			local angle = index / 3 * math.pi * 2
			part(
				`RocketFin_{index}`,
				Vector3.new(0.3, 2.2, 1.4),
				at * CFrame.Angles(0, angle, 0) * CFrame.new(0, 1.9, 1.5),
				red,
				plot
			)
		end
		local flame =
			trim(ball("RocketFlame", 1.2, at * CFrame.new(0, 0.9, 0), Color3.fromRGB(255, 170, 60), plot))
		flame.Material = Enum.Material.Neon
	end,
}

local SETS: { [string]: { (Model, CFrame) -> () } } = {
	garden = GARDEN,
	playground = PLAYGROUND,
	pets = PETS,
	transport = TRANSPORT,
}

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
			caption(cloth, first.glyph, 1.4, 1.5, true)
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
		caption(cloth, tostring(index), 1.4, 1.5, true)
	end
end

--[[
	Шпиль Счёта — перед Шпилем Азбуки, в правом углу: две вершины обучения
	стоят рядом, и с улицы видно обе. Голубой, чтобы не спутать с золотым.
	У задней стены, где он стоял раньше, теперь будка и курятник.
]]
local function buildCountSpire(plot: Model, at: CFrame)
	local blue = Color3.fromRGB(120, 200, 255)
	local spot = at * CFrame.new(Base.PLOT_SIZE / 2 - 7, 0, Base.PLOT_SIZE / 2 - 15)
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
	tiles: { { glyph: string, color: Color3, vo: string? } }
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
		caption(tilePart, tile.glyph, 1.2, 1.2, true)

		--[[
			Нажал на плитку — буква называет себя. Любому, кто нажал, а не только
			хозяину: зашёл к соседу, коснулся его буквы — услышал её. Бесплатное
			повторение, ради которого комнаты и стоят на виду.
		]]
		if tile.vo then
			local click = Instance.new("ClickDetector")
			click.MaxActivationDistance = 30
			click.Parent = tilePart
			local home = tilePart.CFrame
			click.MouseClick:Connect(function(who: Player)
				RemoteDefs.event("PlayVO"):FireClient(who, tile.vo)
				if tilePart.Parent then
					tilePart.CFrame = home * CFrame.new(0, 0, -0.4)
					task.delay(0.2, function()
						if tilePart.Parent then
							tilePart.CFrame = home
						end
					end)
				end
			end)
		end
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
		table.insert(letterTiles, { glyph = letter.glyph, color = letter.color, vo = letter.vo.name })
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
				-- Чисел в записи десять: у одиннадцатой ступени голоса нет, плитка молчит.
				vo = if stage <= MathConfig.MAX_NUMBER then `num_{stage}` else nil,
			})
		end
	end
	buildRoom(plot, at, "MathRoom", 7, 10, "Комнаты цифр", mathTiles)
end

--[[
	Флаги ступеней на коньке крыши (docs/15-HOME-BASE.md § 5): флажок за каждую ступень
	алфавита, все буквы которой освоены. Цвет — первой буквы ступени, как у флагов
	пройденных уровней вдоль забора. Без дома и крыши их ставить некуда.
]]

local function buildRoofFlags(
	plot: Model,
	at: CFrame,
	earned: Awards.Earned,
	houseLevel: number,
	roofLevel: number
)
	local flags = earned.stageFlags or {}
	if houseLevel <= 0 or roofLevel <= 0 or #flags == 0 then
		return
	end
	-- По коньку крыши, от фасада назад: у каждой ступени своё место, флаги видно с дорожки.
	local size = HOUSE_SIZES[houseLevel]
	local depth = size.Z + ROOF_OVERHANG * 2
	local y = FLOOR + size.Y + roofRise(houseLevel) + 0.4
	for _, stageIndex in flags do
		local stage = Stages.get(stageIndex)
		if stage then
			local x = 0
			local z = -depth / 2 + 0.8 + (stageIndex - 0.5) / Stages.count() * (depth - 1.6)
			local first = Letters.expect(stage.letters[1])
			local pole = part(
				`RoofFlagPole_{stageIndex}`,
				Vector3.new(0.2, 2.6, 0.2),
				at * CFrame.new(x, y + 1.3, z),
				Color3.fromRGB(245, 245, 250),
				plot
			)
			pole.CanCollide = false
			local cloth = part(
				`RoofFlag_{stageIndex}`,
				-- Полотнище вдоль конька: флаги стоят через студ и поперёк закрыли бы друг друга.
				Vector3.new(0.1, 0.8, 0.9),
				at * CFrame.new(x, y + 2.2, z + 0.5),
				first.color,
				plot
			)
			cloth.CanCollide = false
			caption(cloth, first.glyph, 0.9, 0.9, true)
		end
	end
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
	Подпись пада — в студах, а не в пикселях. Пады стоят рядком через шесть
	студов, и пиксельные подписи издалека сливались в кашу «Мебель готово
	Транспорт готово». В студах подпись не шире своего пада, а достроенная
	категория показывает только эмодзи и ✅ — читать ребёнку всё равно нечего.
]]
local function padCaption(pad: BasePart, text: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Caption"
	billboard.Size = UDim2.fromScale(5.6, 2.4)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 60
	billboard.Parent = pad

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
	local spot = if category.pad
		then CFrame.new(category.pad.X, FLOOR + 0.5, category.pad.Y)
		else CFrame.new(
			(index - (#Base.rowIds() + 1) / 2) * Base.PAD_STEP,
			FLOOR + 0.5,
			-Base.PLOT_SIZE / 2 + 5
		)

	local pad = part(
		`Upgrade_{categoryId}`,
		Vector3.new(Base.PAD_WIDTH, 1, Base.PAD_WIDTH),
		at * spot,
		Color3.fromRGB(255, 235, 190),
		plot
	)

	local price = Base.priceFor(categoryId, level)
	local nextTitle = Base.nextTitle(categoryId, level)

	if not price or not nextTitle then
		padCaption(pad, `{category.emoji} ✅`)
		pad.Color = Color3.fromRGB(200, 230, 200)
		return
	end

	padCaption(pad, `{category.emoji} {nextTitle}\n{price} ⭐`)

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
	for id, builders in SETS do
		for level = 1, math.min(base[id], #builders) do
			local spot = Base.expect(id).spots[level]
			builders[level](plot.model, at * CFrame.new(spot.x, FLOOR, spot.z))
		end
	end
end

--[[
	Буквята дома (docs/15-HOME-BASE.md § 5). Освоенные буквы, которые не летают
	за ребёнком, живут у него во дворе и кружат над домом — соседи видят, сколько
	у него буквят, и любого можно нажать, чтобы услышать букву.

	Сервер пишет только список: атрибут YardPets_<номер участка> на папке участков
	в виде «userId:a,b,v». Папка не пространственная и приезжает к клиенту всегда,
	в отличие от модели участка при стриминге. Кого из списка сейчас водит хозяин,
	клиент отсеивает сам по атрибутам PetLetter — сервису питомцев не нужно
	перестраивать участок при каждой смене буквёнка.
]]
local YARD_PETS_SENT = 8

local function renderYardPets(plot: Plot, player: Player?, earned: Awards.Earned?)
	local folder = plot.model.Parent
	if not folder then
		return
	end
	local attribute = `YardPets_{plot.index}`
	local mastered = earned and earned.letterRooms or {}
	if not player or #mastered == 0 then
		folder:SetAttribute(attribute, nil)
		return
	end
	local list = {}
	for index = math.max(1, #mastered - YARD_PETS_SENT + 1), #mastered do
		table.insert(list, mastered[index])
	end
	folder:SetAttribute(attribute, `{player.UserId}:{table.concat(list, ",")}`)
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
		renderYardPets(plot, nil, nil)
		return
	end

	local base = Base.sanitize(profile and profile.base)
	local earned = Awards.of(profile)
	renderBuildings(plot, base)
	renderAwards(plot, earned)
	buildRooms(plot.model, plot.cframe, earned, base.house)
	buildRoofFlags(plot.model, plot.cframe, earned, base.house, base.roof)
	renderSign(plot, `Дом: {player.DisplayName}`)
	renderYardPets(plot, player, earned)

	for index, categoryId in Base.rowIds() do
		buildUpgradePad(plot.model, plot.cframe, index, categoryId, player, base[categoryId])
	end
	for _, categoryId in Base.ids() do
		if Base.expect(categoryId).pad then
			buildUpgradePad(plot.model, plot.cframe, 0, categoryId, player, base[categoryId])
		end
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
		buildRoofFlags(plot.model, plot.cframe, earned, clean.house, clean.roof)
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
local GARDEN_TREES = { "bush_round", "tree_round", "tree_pine" }

local function buildGardens(folder: Instance)
	local gardens = Instance.new("Folder")
	gardens.Name = "Gardens"
	gardens.Parent = folder

	for index = 1, Base.PLOT_COUNT do
		local angle = (index - 0.5) / Base.PLOT_COUNT * math.pi * 2
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		for slot, id in GARDEN_TREES do
			local model = DecorService.modelFor(id)
			if model then
				local distance = Base.RING_RADIUS + (slot - 2) * (Base.PLOT_SIZE / 2.5)
				local spot = outward * distance
				model.Name = `Garden_{index}_{slot}`
				model.Parent = gardens
				if id ~= "bush_round" then
					model:ScaleTo(model:GetScale() * 1.3)
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
		Teleport.to(player, home)
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
