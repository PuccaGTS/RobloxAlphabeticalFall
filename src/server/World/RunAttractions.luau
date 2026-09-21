--!nonstrict
--[[
	Станции букв и аттракционы забега: строит геометрию по плану
	(Challenges/CourseLayout, Logic/AttractionPlan). Триггеры и возврат
	к флажку остаются в TunnelService — здесь только то, что видно.

	Всё, что движется, двигает КЛИЕНТ (RunHazardController): сервер ставит деталь
	в исходное положение, вешает тег RunMover и атрибуты движения. Движение
	считается от серверных часов, поэтому у клиента и у задумки оно одно и то же,
	а картинка плавная — сервер, двигающий детали сам, рассылал бы рывки.

	Деталь с тегом RunHurt «сбивает»: клиент видит касание и просит сервер
	вернуть ребёнка к флажку. Нечестно тут нечего выиграть — касание только
	отнимает секунды, поэтому проверка касания и живёт у того, кто его видит.

	Координаты планов: z — от начала аттракциона вперёд, x — вбок, y — от пола.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tunnel = require(Shared.Config.Tunnel)
local Attractions = require(Shared.Config.Attractions)

local Letter3D = require(script.Parent.Letter3D)

local RunAttractions = {}

RunAttractions.MOVER_TAG = "RunMover"
RunAttractions.HURT_TAG = "RunHurt"

local function part(model: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function ghost(p: BasePart): BasePart
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	return p
end

local function mover(p: BasePart, kind: string, attributes: { [string]: any })
	p:SetAttribute("Mover", kind)
	p:SetAttribute("Base", p.CFrame)
	for key, value in attributes do
		p:SetAttribute(key, value)
	end
	CollectionService:AddTag(p, RunAttractions.MOVER_TAG)
end

local function hurts(p: BasePart)
	CollectionService:AddTag(p, RunAttractions.HURT_TAG)
end

-- Табличка-эмодзи над входом: читать ребёнок не умеет, картинку узнаёт.
local function sign(model: Instance, name: string, at: CFrame, emoji: string)
	local anchor = ghost(part(model, name, Vector3.new(1, 1, 1), at, Color3.new(1, 1, 1)))
	anchor.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 120)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 160
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = emoji
	label.TextScaled = true
	label.Parent = billboard
end

-- Точка плана аттракциона в мире: path понимает запись origin * CFrame.new(x, y, -z).
local function at(path, ride, x: number, y: number, z: number): CFrame
	return path * CFrame.new(x, y, -(ride.z + z))
end

-- ===== Станция буквы ==============================================================

local STATION_STONE = Color3.fromRGB(250, 246, 236)
local STATION_GOLD = Color3.fromRGB(255, 205, 80)

--[[
	Станция: круг на полу, за ним ворота-беседка, в проёме парит огромная буква
	отрезка и держит невидимую преграду. Ребёнок встал в круг — голос называет
	букву, буква подпрыгивает и поднимается над беседкой, преграда исчезает.

	Возвращает функцию открытия: её зовёт TunnelService, когда ребёнок дошёл до круга.
	passed — станция пройдена в прошлый заход: строится сразу открытой.
]]
function RunAttractions.buildStation(model: Model, path, station, passed: boolean): () -> ()
	local base = station.z
	local color = station.color or STATION_GOLD
	local half = Tunnel.WIDTH / 2

	-- Круг, куда надо встать: светлый диск с кольцом цвета буквы.
	local circleAt = path * CFrame.new(0, 0.12, -(base + Tunnel.STATION_TRIGGER_Z))
	local ring = ghost(
		part(
			model,
			`StationRing_{station.index}`,
			Vector3.new(0.2, 13, 13),
			circleAt * CFrame.Angles(0, 0, math.pi / 2),
			color
		)
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	local disc = ghost(
		part(
			model,
			`StationDisc_{station.index}`,
			Vector3.new(0.24, 11, 11),
			circleAt * CFrame.Angles(0, 0, math.pi / 2),
			STATION_STONE
		)
	)
	disc.Shape = Enum.PartType.Cylinder

	-- Беседка: два столба, перекладина с лампочками цвета буквы.
	local doorZ = base + Tunnel.STATION_DOOR_Z
	local height = Tunnel.STATION_LETTER + 4
	for _, side in { -1, 1 } do
		local post = part(
			model,
			`StationPost_{station.index}_{side}`,
			Vector3.new(2, height, 2),
			path * CFrame.new(side * (half - 1), height / 2, -doorZ),
			STATION_STONE
		)
		post.Material = Enum.Material.Marble
		local cap = ghost(
			part(
				model,
				`StationCap_{station.index}_{side}`,
				Vector3.new(2.6, 2.6, 2.6),
				path * CFrame.new(side * (half - 1), height + 1.3, -doorZ),
				color
			)
		)
		cap.Shape = Enum.PartType.Ball
		cap.Material = Enum.Material.Neon
	end
	local lintel = part(
		model,
		`StationLintel_{station.index}`,
		Vector3.new(Tunnel.WIDTH, 1.6, 2.2),
		path * CFrame.new(0, height, -doorZ),
		STATION_STONE
	)
	lintel.Material = Enum.Material.Marble

	-- Преграда: прозрачная, с лёгким отливом. Буква «держит» проход.
	local barrier = part(
		model,
		`StationBarrier_{station.index}`,
		Vector3.new(Tunnel.WIDTH - 4, height, 1),
		path * CFrame.new(0, height / 2, -doorZ),
		color
	)
	barrier.Transparency = 0.8
	barrier.Material = Enum.Material.ForceField
	barrier.CanQuery = false

	-- Огромная буква: парит в проёме, лицом к бегущему.
	local letterHome = path
		* CFrame.new(0, 1 + Tunnel.STATION_LETTER / 2, -(doorZ - 1.5))
		* CFrame.Angles(0, math.pi, 0)
	local letterTop = path
		* CFrame.new(0, height + 1.5 + Tunnel.STATION_LETTER * 0.35, -doorZ)
		* CFrame.Angles(0, math.pi, 0)
	local letter = Letter3D.build(station.letterId, Tunnel.STATION_LETTER, letterHome, color, {
		material = Enum.Material.SmoothPlastic,
	})
	letter.Name = `StationLetter_{station.index}`
	letter.Parent = model

	local function moveLetter(target: CFrame, scale: number, seconds: number)
		local current = letter:GetPivot()
		local value = Instance.new("CFrameValue")
		value.Value = current
		local startScale = letter:GetScale()
		local connection = value.Changed:Connect(function(cframe: CFrame)
			letter:PivotTo(cframe)
		end)
		local tween =
			TweenService:Create(value, TweenInfo.new(seconds, Enum.EasingStyle.Back), { Value = target })
		tween.Completed:Connect(function()
			connection:Disconnect()
			value:Destroy()
		end)
		tween:Play()
		if scale ~= startScale then
			task.spawn(function()
				local steps = math.max(1, math.floor(seconds * 20))
				for step = 1, steps do
					if not letter.Parent then
						return
					end
					letter:ScaleTo(startScale + (scale - startScale) * step / steps)
					task.wait(seconds / steps)
				end
			end)
		end
	end

	-- Пивот модели — центр буквы: Letter3D строит её вокруг letterHome.
	letter.WorldPivot = letterHome

	local opened = false
	local function open(instant: boolean?)
		if opened then
			return
		end
		opened = true
		barrier.CanCollide = false
		if instant then
			barrier:Destroy()
			letter:ScaleTo(0.5)
			letter:PivotTo(letterTop)
			return
		end
		-- Буква подпрыгивает, пока звучит её имя, и поднимается над беседкой.
		moveLetter(letterHome * CFrame.new(0, 2.5, 0), 1, 0.35)
		task.delay(0.4, function()
			moveLetter(letterHome, 1, 0.3)
		end)
		local burst = Instance.new("ParticleEmitter")
		burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		burst.Rate = 0
		burst.Speed = NumberRange.new(8, 14)
		burst.Lifetime = NumberRange.new(0.8, 1.3)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Color = ColorSequence.new(color)
		burst.LightEmission = 1
		burst.Parent = lintel
		burst:Emit(45)
		task.delay(Tunnel.STATION_OPEN_DELAY, function()
			if not barrier.Parent then
				return
			end
			TweenService:Create(barrier, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			task.delay(0.4, function()
				barrier:Destroy()
			end)
			moveLetter(letterTop, 0.5, 0.8)
		end)
	end

	if passed then
		open(true)
	end

	return function()
		open(false)
	end
end

-- ===== Флажок перед аттракционом ======================================================

local FLAG_COLD = Color3.fromRGB(255, 200, 70)
local FLAG_LIT = Color3.fromRGB(120, 220, 140)

-- Флажок: столбик у бортика и треугольный вымпел. Возвращает вымпел: его зажигает TunnelService.
function RunAttractions.buildFlag(model: Model, path, ride): BasePart
	local x = Tunnel.WIDTH / 2 - 1.2
	local base = path * CFrame.new(x, 0, -ride.flagZ)
	ghost(
		part(
			model,
			`FlagPole_{ride.index}`,
			Vector3.new(0.35, 7, 0.35),
			base * CFrame.new(0, 3.5, 0),
			Color3.fromRGB(250, 250, 250)
		)
	)
	local pennant = ghost(
		part(
			model,
			`FlagPennant_{ride.index}`,
			Vector3.new(0.15, 1.8, 2.6),
			base * CFrame.new(-1.1, 6, 0) * CFrame.Angles(0, math.pi / 2, 0),
			FLAG_COLD
		)
	)
	pennant.Material = Enum.Material.SmoothPlastic
	return pennant
end

function RunAttractions.lightFlag(pennant: BasePart)
	pennant.Color = FLAG_LIT
	pennant.Material = Enum.Material.Neon
end

-- ===== Аттракционы ================================================================

local ISLAND_TOPS = {
	Color3.fromRGB(125, 205, 110),
	Color3.fromRGB(150, 215, 95),
	Color3.fromRGB(110, 195, 150),
	Color3.fromRGB(240, 190, 90),
	Color3.fromRGB(235, 150, 170),
}
local EARTH = Color3.fromRGB(150, 110, 80)

local BUILDERS = {}

--[[
	Островки: круглые кочки над пропастью. Сверху трава, снизу земляной конус —
	кочка читается «островом», а не плитой, и видно, что под ней пусто.
]]
function BUILDERS.islands(model: Model, path, ride)
	for _, island in ride.islands do
		local top = at(path, ride, island.x, island.y, island.z)
		local grass = part(
			model,
			`Island_{ride.index}_{island.index}`,
			Vector3.new(1.2, island.size, island.size),
			top * CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.pi / 2),
			ISLAND_TOPS[(island.index - 1) % #ISLAND_TOPS + 1]
		)
		grass.Shape = Enum.PartType.Cylinder
		grass.Material = Enum.Material.Grass
		local earth = ghost(
			part(
				model,
				`IslandEarth_{ride.index}_{island.index}`,
				Vector3.new(3, island.size * 0.8, island.size * 0.8),
				top * CFrame.new(0, -2.6, 0) * CFrame.Angles(0, 0, math.pi / 2),
				EARTH
			)
		)
		earth.Shape = Enum.PartType.Cylinder
		local root = ghost(
			part(
				model,
				`IslandRoot_{ride.index}_{island.index}`,
				Vector3.new(3, island.size * 0.45, island.size * 0.45),
				top * CFrame.new(0, -5, 0) * CFrame.Angles(0, 0, math.pi / 2),
				EARTH
			)
		)
		root.Shape = Enum.PartType.Cylinder
		-- Цветок на каждой второй кочке: живое, а не плита в воздухе.
		if island.index % 2 == 0 then
			local flower = ghost(
				part(
					model,
					`IslandFlower_{ride.index}_{island.index}`,
					Vector3.new(0.9, 0.9, 0.9),
					top * CFrame.new(island.size * 0.28, 0.9, 0),
					Color3.fromRGB(255, 240, 120)
				)
			)
			flower.Shape = Enum.PartType.Ball
		end
	end
	sign(model, `Sign_{ride.index}`, at(path, ride, 0, 12, 0), "🏝️")
end

--[[
	Вертушка: круглая площадка, в центре столб, по полу ходит перекладина.
	Перепрыгни её, когда она подходит, — или попадёшься и вернёшься к флажку.
]]
function BUILDERS.spinner(model: Model, path, ride)
	local diameter = Attractions.SPINNER_DIAMETER
	local center = at(path, ride, 0, 0, ride.length / 2)
	local plate = part(
		model,
		`SpinnerPlate_{ride.index}`,
		Vector3.new(0.4, diameter, diameter),
		center * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(245, 240, 255)
	)
	plate.Shape = Enum.PartType.Cylinder
	local rim = ghost(
		part(
			model,
			`SpinnerRim_{ride.index}`,
			Vector3.new(0.3, diameter + 1.2, diameter + 1.2),
			center * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(160, 120, 235)
		)
	)
	rim.Shape = Enum.PartType.Cylinder
	local hub = part(
		model,
		`SpinnerHub_{ride.index}`,
		Vector3.new(4.5, 2.6, 2.6),
		center * CFrame.new(0, 2.25, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(255, 205, 80)
	)
	hub.Shape = Enum.PartType.Cylinder

	local barHeight = Attractions.SPINNER_BAR_HEIGHT
	local pivot = center * CFrame.new(0, 0.4 + barHeight / 2 + 0.3, 0)
	for bar = 1, ride.bars do
		local turn = CFrame.Angles(0, (bar - 1) * math.pi / ride.bars, 0)
		local beam = part(
			model,
			`SpinnerBar_{ride.index}_{bar}`,
			Vector3.new(diameter - 1, barHeight, barHeight),
			pivot * turn,
			if bar % 2 == 1 then Color3.fromRGB(240, 85, 85) else Color3.fromRGB(80, 150, 240)
		)
		beam.CanCollide = false
		beam.CanQuery = false
		mover(beam, "spin", { Period = ride.period * ride.direction, Offset = turn })
		beam:SetAttribute("Base", pivot)
		hurts(beam)
	end
	sign(model, `Sign_{ride.index}`, at(path, ride, 0, 12, 0), "🌀")
end

--[[
	Валуны: коридор между каменными стенами, в стенах ниши. Из пещеры в дальнем
	конце выкатываются валуны во всю ширину прохода — мимо не проскочить,
	только спрятаться в нише и переждать.
]]
local ROCK = Color3.fromRGB(150, 135, 120)
local ROCK_DARK = Color3.fromRGB(110, 98, 88)

function BUILDERS.boulders(model: Model, path, ride)
	local inner = Attractions.BOULDER_CORRIDOR / 2
	local outer = Tunnel.WIDTH / 2
	local depth = Attractions.NICHE_DEPTH
	local wallHeight = Attractions.BOULDER_WALL_HEIGHT
	local length = ride.length

	for _, side in { -1, 1 } do
		-- Задняя стена во всю длину: за ней уже бортик трассы.
		local backThickness = outer - inner - depth
		local back = part(
			model,
			`BoulderBack_{ride.index}_{side}`,
			Vector3.new(backThickness, wallHeight, length),
			at(path, ride, side * (outer - backThickness / 2), wallHeight / 2, length / 2),
			ROCK_DARK
		)
		back.Material = Enum.Material.Slate

		-- Передняя стена кусками между нишами своей стороны.
		local cursor = 0
		local function wall(from: number, to: number)
			if to - from < 0.2 then
				return
			end
			local piece = part(
				model,
				`BoulderWall_{ride.index}_{side}_{math.floor(from)}`,
				Vector3.new(depth, wallHeight, to - from),
				at(path, ride, side * (inner + depth / 2), wallHeight / 2, (from + to) / 2),
				ROCK
			)
			piece.Material = Enum.Material.Slate
		end
		for _, niche in ride.niches do
			if niche.side == side then
				local from = niche.z - Attractions.NICHE_LENGTH / 2
				wall(cursor, from)
				cursor = niche.z + Attractions.NICHE_LENGTH / 2
				-- Зелёный фонарик в нише: здесь безопасно.
				local lamp = ghost(
					part(
						model,
						`NicheLamp_{ride.index}_{math.floor(niche.z)}`,
						Vector3.new(1.2, 1.2, 1.2),
						at(path, ride, side * (outer - backThickness - 0.8), 6, niche.z),
						Color3.fromRGB(120, 235, 140)
					)
				)
				lamp.Shape = Enum.PartType.Ball
				lamp.Material = Enum.Material.Neon
				local light = Instance.new("PointLight")
				light.Color = lamp.Color
				light.Range = 9
				light.Brightness = 1.5
				light.Parent = lamp
			end
		end
		wall(cursor, length)
	end

	-- Пещера в дальнем конце: тёмная арка, сквозь неё выход, из неё валуны.
	local caveZ = length - 3
	local cave = part(
		model,
		`BoulderCaveRoof_{ride.index}`,
		Vector3.new(Tunnel.WIDTH, 4, 6),
		at(path, ride, 0, wallHeight + 1, caveZ),
		ROCK_DARK
	)
	cave.Material = Enum.Material.Slate
	local shade = ghost(
		part(
			model,
			`BoulderCaveShade_{ride.index}`,
			Vector3.new(Attractions.BOULDER_CORRIDOR, wallHeight, 0.2),
			at(path, ride, 0, wallHeight / 2, caveZ + 2.5),
			Color3.fromRGB(35, 30, 30)
		)
	)
	shade.Transparency = 0.55

	local radius = Attractions.BOULDER_DIAMETER / 2
	local travel = (length - 6) / ride.speed
	local count = math.ceil(travel / ride.interval) + 1
	local start = at(path, ride, 0, radius, length - 3)
	for index = 1, count do
		local ball = part(
			model,
			`Boulder_{ride.index}_{index}`,
			Vector3.one * Attractions.BOULDER_DIAMETER,
			start,
			Color3.fromRGB(165, 150, 135)
		)
		ball.Shape = Enum.PartType.Ball
		ball.Material = Enum.Material.Slate
		ball.CanCollide = false
		ball.CanQuery = false
		mover(ball, "roll", {
			Period = count * ride.interval,
			Phase = (index - 1) * ride.interval,
			Travel = travel,
			Speed = ride.speed,
			Radius = radius,
		})
		hurts(ball)
	end
	sign(model, `Sign_{ride.index}`, at(path, ride, 0, wallHeight + 5, 0), "⛰️")
end

--[[
	Лавовые кочки: вместо пола — светящаяся лава, по ней две колонки камней.
	Камни уходят в лаву и возвращаются; перед тем как уйти, краснеют.
]]
local BASALT = Color3.fromRGB(90, 80, 85)
local BASALT_STEADY = Color3.fromRGB(70, 65, 75)
local LAVA = Color3.fromRGB(255, 95, 30)

function BUILDERS.lava(model: Model, path, ride)
	local pool = part(
		model,
		`LavaPool_{ride.index}`,
		Vector3.new(Tunnel.WIDTH, 1, ride.length),
		at(path, ride, 0, -2, ride.length / 2),
		LAVA
	)
	pool.Material = Enum.Material.CrackedLava
	hurts(pool)
	local glow = Instance.new("PointLight")
	glow.Color = LAVA
	glow.Range = 16
	glow.Brightness = 2
	glow.Parent = pool

	local size = Attractions.LAVA_STONE
	for _, stone in ride.stones do
		local block = part(
			model,
			`LavaStone_{ride.index}_{stone.row}_{stone.column}`,
			Vector3.new(size, 2, size),
			at(path, ride, stone.x, -1, stone.z),
			if stone.steady then BASALT_STEADY else BASALT
		)
		block.Material = Enum.Material.Basalt
		if not stone.steady then
			mover(block, "sink", {
				Period = ride.period,
				Phase = stone.phase,
				Solid = ride.solid,
				Warn = Attractions.LAVA_WARN,
				Depth = Attractions.LAVA_SINK,
				WarnColor = Color3.fromRGB(235, 70, 50),
			})
		end
	end
	sign(model, `Sign_{ride.index}`, at(path, ride, 0, 12, 0), "🌋")
end

--[[
	Облачка: пушистые облака над пропастью катаются поперёк трассы. Сверху
	ровная площадка — на неё приземляются, по краю клубы — чтобы облако
	читалось облаком, а не тарелкой. Клубы ни с чем не сталкиваются.
	Облако везёт стоящего на нём ребёнка: клиент задаёт ему скорость (Carry).
]]
local CLOUD = Color3.fromRGB(252, 252, 255)
local CLOUD_SHADE = Color3.fromRGB(225, 232, 250)

function BUILDERS.clouds(model: Model, path, ride)
	local size = ride.size
	for _, cloud in ride.clouds do
		local center = at(path, ride, 0, -0.8, cloud.z)
		local attributes = { Period = ride.period, Phase = cloud.phase, Travel = ride.travel }
		local body = part(
			model,
			`Cloud_{ride.index}_{cloud.row}`,
			Vector3.new(1.6, size, size),
			center * CFrame.Angles(0, 0, math.pi / 2),
			CLOUD
		)
		body.Shape = Enum.PartType.Cylinder
		attributes.Offset = CFrame.Angles(0, 0, math.pi / 2)
		mover(body, "slide", attributes)
		body:SetAttribute("Base", center)
		body:SetAttribute("Carry", true)

		local puffs = 6
		for puff = 1, puffs do
			local angle = (puff - 0.5) / puffs * math.pi * 2 + cloud.row
			local diameter = size * (if puff % 2 == 0 then 0.42 else 0.34)
			local offset = CFrame.new(math.cos(angle) * size * 0.46, -0.3, math.sin(angle) * size * 0.46)
			local ball = ghost(
				part(
					model,
					`CloudPuff_{ride.index}_{cloud.row}_{puff}`,
					Vector3.new(diameter, diameter, diameter),
					center * offset,
					if puff % 3 == 0 then CLOUD_SHADE else CLOUD
				)
			)
			ball.Shape = Enum.PartType.Ball
			mover(
				ball,
				"slide",
				{ Period = ride.period, Phase = cloud.phase, Travel = ride.travel, Offset = offset }
			)
			ball:SetAttribute("Base", center)
		end
	end
	sign(model, `Sign_{ride.index}`, at(path, ride, 0, 12, 0), "☁️")
end

--[[
	Молоты: узкий мостик над пропастью, над ним качаются три молота поперёк
	мостика. Молот сбивает вниз — и ребёнок возвращается к флажку.
]]
local WOOD = Color3.fromRGB(190, 140, 95)

function BUILDERS.hammers(model: Model, path, ride)
	local bridge = part(
		model,
		`HammerBridge_{ride.index}`,
		Vector3.new(ride.bridge, 1.5, ride.length),
		at(path, ride, 0, -0.75, ride.length / 2),
		WOOD
	)
	bridge.Material = Enum.Material.WoodPlanks

	local half = Tunnel.WIDTH / 2
	local pivotY = Attractions.HAMMER_PIVOT
	local arm = Attractions.HAMMER_ARM
	for _, hammer in ride.hammers do
		for _, side in { -1, 1 } do
			ghost(
				part(
					model,
					`HammerPost_{ride.index}_{hammer.index}_{side}`,
					Vector3.new(1.2, pivotY + 22, 1.2),
					at(path, ride, side * (half - 0.6), pivotY - (pivotY + 22) / 2 + 1, hammer.z),
					Color3.fromRGB(120, 90, 70)
				)
			)
		end
		ghost(
			part(
				model,
				`HammerBeam_{ride.index}_{hammer.index}`,
				Vector3.new(Tunnel.WIDTH, 1.2, 1.2),
				at(path, ride, 0, pivotY + 0.6, hammer.z),
				Color3.fromRGB(120, 90, 70)
			)
		)

		local pivot = at(path, ride, 0, pivotY, hammer.z)
		local attributes = {
			Period = ride.period,
			Phase = hammer.phase,
			Amplitude = Attractions.HAMMER_SWING,
		}
		local armOffset = CFrame.new(0, -arm / 2, 0)
		local rod = part(
			model,
			`HammerArm_{ride.index}_{hammer.index}`,
			Vector3.new(0.6, arm, 0.6),
			pivot * armOffset,
			Color3.fromRGB(90, 70, 60)
		)
		rod.CanCollide = false
		rod.CanQuery = false
		attributes.Offset = armOffset
		mover(rod, "swing", attributes)
		rod:SetAttribute("Base", pivot)

		local headOffset = CFrame.new(0, -arm, 0) * CFrame.Angles(0, math.pi / 2, 0)
		local size = Attractions.HAMMER_HEAD
		local head = part(
			model,
			`HammerHead_{ride.index}_{hammer.index}`,
			Vector3.new(size.X, size.Z, size.Y),
			pivot * headOffset,
			Color3.fromRGB(235, 90, 80)
		)
		head.Shape = Enum.PartType.Cylinder
		head.CanCollide = false
		head.CanQuery = false
		mover(head, "swing", {
			Period = ride.period,
			Phase = hammer.phase,
			Amplitude = Attractions.HAMMER_SWING,
			Offset = headOffset,
		})
		head:SetAttribute("Base", pivot)
		hurts(head)
	end
	sign(model, `Sign_{ride.index}`, at(path, ride, 0, pivotY + 6, 0), "🔨")
end

function RunAttractions.buildAttraction(model: Model, path, ride)
	local builder = BUILDERS[ride.id]
	if not builder then
		warn(`[RunAttractions] не умею строить аттракцион "{ride.id}"`)
		return
	end
	local folder = Instance.new("Model")
	folder.Name = `Attraction_{ride.index}_{ride.id}`
	folder.Parent = model
	builder(folder, path, ride)
end

--[[
	Где у аттракциона нет пола трассы: там его заменяют кочки, мостик или лава.
	Отдаёт отрезки [from, to] вдоль всего забега — по ним TunnelService режет пол.
]]
function RunAttractions.holes(attractions: { any }?): { { from: number, to: number } }
	local list = {}
	for _, ride in attractions or {} do
		local meta = Attractions.get(ride.id)
		if meta and not meta.floor then
			table.insert(list, { from = ride.z, to = ride.z + ride.length })
		end
	end
	return list
end

return RunAttractions
