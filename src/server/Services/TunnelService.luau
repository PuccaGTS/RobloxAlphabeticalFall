--!nonstrict
--[[
	Геометрия забега: строит туннель или полосу препятствий по плану
	от Challenges/RunCourse, телепортирует игрока внутрь и обратно,
	ловит касания ворот, сохранок и финиша.

	Туннель у каждого игрока СВОЙ и стоит в отдельном месте карты: иначе двое детей
	бегали бы по одному коридору с разными заданиями и мешали друг другу.

	Сервер здесь — источник истины целиком: ворота это физические триггеры на сервере,
	клиент о выборе даже не сообщает, он просто бежит.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tunnel = require(Shared.Config.Tunnel)
local RemoteDefs = require(Shared.Net.RemoteDefs)
local Challenges = require(Shared.Config.Challenges)
local TrackShape = require(Shared.Logic.TrackShape)

local ChallengeService = require(script.Parent.ChallengeService)
local ProgressService = require(script.Parent.ProgressService)
local DecorService = require(script.Parent.DecorService)
local Teleport = require(script.Parent.Parent.World.Teleport)
local Letter3D = require(script.Parent.Parent.World.Letter3D)
local RunAttractions = require(script.Parent.Parent.World.RunAttractions)
local RateLimiter = require(script.Parent.RateLimiter)

local TunnelService = {}

local FOLDER_NAME = "Tunnels"

type Run = {
	model: Model,
	origin: CFrame,
	returnCFrame: CFrame?,
	spec: any,
	slowUntil: number,
	-- Последняя пройденная сохранка: сюда возвращается упавший ребёнок.
	checkpointZ: number,
	fallingUntil: number,
}

local runs: { [Player]: Run } = {}
local plots: { [Player]: number } = {}
local usedPlots: { [number]: boolean } = {}
local container: Folder? = nil

local function ensureContainer(): Folder
	if container and container.Parent then
		return container
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	container = folder
	return folder
end

-- Каждому игроку свой участок карты, чтобы туннели не пересекались.
local function plotFor(player: Player): number
	if plots[player] then
		return plots[player]
	end
	local index = 1
	while usedPlots[index] do
		index += 1
	end
	usedPlots[index] = true
	plots[player] = index
	return index
end

local function releasePlot(player: Player)
	local index = plots[player]
	if index then
		usedPlots[index] = nil
		plots[player] = nil
	end
end

local function build(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--[[
	Знак над проёмом: буква или число. Билборд создаётся на сервере и реплицируется
	всем — для статичной надписи это дешевле, чем гонять данные на клиент
	и рисовать их там.
]]
local function attachGlyph(part: BasePart, glyph: string, color: Color3)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Glyph"
	billboard.Size = UDim2.fromOffset(220, 220)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 250
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = glyph
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(30, 26, 45)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard
end

--[[
	Где в полу дырки. Яма вырезает пол на своей дорожке, балка — на всех трёх,
	оставляя вместо пола узкую доску посередине.

	Пол строится кусками между дырками, а не тайлами по всей длине: тайлов
	на длинный забег набежали бы сотни, а кусков всегда на два-три больше,
	чем ям.
]]
local function laneHoles(obstacles: { any }, attractions: { any }?): { { { from: number, to: number } } }
	local holes = {}
	for lane = 1, Tunnel.LANE_COUNT do
		holes[lane] = {}
	end

	-- Под островками, лавой и молотами пола нет во всю ширину: падать есть куда.
	for _, hole in RunAttractions.holes(attractions) do
		for lane = 1, Tunnel.LANE_COUNT do
			table.insert(holes[lane], hole)
		end
	end

	for _, obstacle in obstacles or {} do
		if obstacle.kind == "gap" and obstacle.lane >= 1 then
			table.insert(holes[obstacle.lane], { from = obstacle.z, to = obstacle.z + Tunnel.GAP_LENGTH })
		elseif obstacle.kind == "platform" and obstacle.lane >= 1 then
			table.insert(holes[obstacle.lane], { from = obstacle.z, to = obstacle.z + Tunnel.PLATFORM_SPAN })
		elseif obstacle.kind == "fading" and obstacle.lane >= 1 then
			table.insert(holes[obstacle.lane], { from = obstacle.z, to = obstacle.z + Tunnel.FADE_SPAN })
		elseif obstacle.kind == "stones" and obstacle.lane >= 1 then
			table.insert(holes[obstacle.lane], { from = obstacle.z, to = obstacle.z + Tunnel.STONES_SPAN })
		elseif obstacle.kind == "bridge" and obstacle.lane >= 1 then
			table.insert(holes[obstacle.lane], { from = obstacle.z, to = obstacle.z + Tunnel.BRIDGE_SPAN })
		elseif obstacle.kind == "beam" then
			for lane = 1, Tunnel.LANE_COUNT do
				table.insert(holes[lane], { from = obstacle.z, to = obstacle.z + Tunnel.BEAM_LENGTH })
			end
		end
	end

	for _, list in holes do
		table.sort(list, function(a, b)
			return a.from < b.from
		end)
	end

	return holes
end

--[[
	Путь забега: трасса с формой (Logic/TrackShape) вместо прямой доски.

	Все строители написаны в духе «origin * CFrame.new(x, y, -z)»: z — сколько
	пройдено от старта, x — вбок, y — вверх. Путь подменяет origin и понимает
	ровно эту запись: z он переводит в точку на изогнутой трассе, а x и y
	откладывает уже от неё. Поэтому ворота, препятствия, ряды букв и сохранки
	встали на петляющую трассу без единой правки в своих строителях —
	и стоят вертикально: наклон есть только у пола на горках.
]]
local function makePath(origin: CFrame, spec: any)
	local sampler = TrackShape.sampler(spec.params.track or {}, spec.params.length)
	local path = { origin = origin, sampler = sampler }

	function path.frame(z: number): CFrame
		return origin * sampler.frame(z)
	end

	function path.flat(z: number): CFrame
		return origin * sampler.flat(z)
	end

	return setmetatable(path, {
		__mul = function(self, offset: CFrame): CFrame
			local position = offset.Position
			return self.flat(-position.Z) * CFrame.new(position.X, position.Y, 0) * offset.Rotation
		end,
	})
end

--[[
	Режет участок [from, to] на куски: прямые участки — одним куском, зоны формы —
	короткими, чтобы пол и бортики легли по горке и виражу без щелей.
	piece(mid, length, curved) вызывается на каждый кусок.
]]
-- Пять студов: на вираже в 20° щели не видно, а деталей на горку вчетверо меньше, чем по студу.
local CURVE_CHUNK = 5

local function pieces(path, from: number, to: number, chunk: number, piece: (number, number, boolean) -> ())
	local cuts = { from, to }
	-- Швы у ворот: пол и бортики меняют цвет ровно там, где начинается новый отрезок.
	for _, z in path.seams or {} do
		if z > from and z < to then
			table.insert(cuts, z)
		end
	end
	-- Края аттракционов: разметка обрывается ровно там, где кончается пол.
	for _, z in path.cuts or {} do
		if z > from and z < to then
			table.insert(cuts, z)
		end
	end
	for _, zone in path.sampler.zones do
		if zone.from > from and zone.from < to then
			table.insert(cuts, zone.from)
		end
		if zone.to > from and zone.to < to then
			table.insert(cuts, zone.to)
		end
	end
	table.sort(cuts)

	for i = 1, #cuts - 1 do
		local a, b = cuts[i], cuts[i + 1]
		if b - a >= 0.5 then
			if path.sampler.zoneAt((a + b) / 2) then
				local cursor = a
				while cursor < b - 0.01 do
					local next_ = math.min(cursor + chunk, b)
					piece((cursor + next_) / 2, next_ - cursor, true)
					cursor = next_
				end
			else
				piece((a + b) / 2, b - a, false)
			end
		end
	end
end

local FLOOR_ZONE_COLOR = Color3.fromRGB(235, 215, 160)

--[[
	У каждого отрезка забега свой цвет пола и бортиков: песок, мята, небо,
	сирень, персик, лимон. Раньше весь забег был одного бежевого цвета,
	и пройденные ворота ничем не отличались от будущих: бежишь, бежишь,
	а место то же. Теперь за воротами начинается другое место, и это видно
	раньше, чем ребёнок добежит до следующей буквы.

	Цвета светлые и неяркие: на полу стоят плитки с буквами и препятствия,
	и спорить с ними пол не должен.
]]
local SEGMENT_FLOORS = {
	Color3.fromRGB(214, 202, 178),
	Color3.fromRGB(190, 216, 194),
	Color3.fromRGB(190, 208, 228),
	Color3.fromRGB(214, 198, 226),
	Color3.fromRGB(232, 204, 184),
	Color3.fromRGB(226, 220, 172),
}
local SEGMENT_RAILS = {
	Color3.fromRGB(245, 175, 110),
	Color3.fromRGB(110, 195, 140),
	Color3.fromRGB(120, 170, 235),
	Color3.fromRGB(185, 140, 225),
	Color3.fromRGB(240, 130, 120),
	Color3.fromRGB(235, 200, 80),
}

-- Номер отрезка в точке z: сколько ворот уже позади, плюс один.
local function segmentAt(path, z: number): number
	local segment = 1
	for _, seam in path.seams or {} do
		if z > seam then
			segment += 1
		end
	end
	return segment
end

local function floorColor(path, z: number): Color3
	return SEGMENT_FLOORS[(segmentAt(path, z) - 1) % #SEGMENT_FLOORS + 1]
end

local function buildFloor(model: Model, path, length: number, obstacles: { any }, attractions: { any }?)
	local holes = laneHoles(obstacles, attractions)

	--[[
		В зонах формы ям не бывает никогда (там ничего не стоит), поэтому пол
		кладётся во всю ширину сразу: кусков втрое меньше, а горка — одним цветом.
	]]
	pieces(path, 0, length, CURVE_CHUNK, function(mid: number, size: number, curved: boolean)
		if not curved then
			return
		end
		local part = build(
			`FloorCurve_{math.floor(mid)}`,
			Vector3.new(Tunnel.WIDTH, 2, size + 0.5),
			path.frame(mid) * CFrame.new(0, -1, 0),
			FLOOR_ZONE_COLOR,
			model
		)
		part.Material = Enum.Material.SmoothPlastic
	end)

	for lane = 1, Tunnel.LANE_COUNT do
		local x = Tunnel.laneOffset(lane)

		local function span(from: number, to: number)
			pieces(path, from, to, CURVE_CHUNK, function(mid: number, size: number, curved: boolean)
				if curved then
					return
				end
				build(
					`Floor_{lane}_{math.floor(mid - size / 2)}`,
					Vector3.new(Tunnel.LANE_WIDTH, 2, size),
					path.frame(mid) * CFrame.new(x, -1, 0),
					floorColor(path, mid),
					model
				)
			end)
		end

		local cursor = 0
		for _, hole in holes[lane] do
			span(cursor, math.clamp(hole.from, cursor, length))
			cursor = math.max(cursor, math.min(hole.to, length))
		end
		span(cursor, length)
	end
end

--[[
	Бортики вместо глухих стен. Туннель с синими стенами высотой в шестнадцать
	студов был коридором, из которого не видно ничего, кроме следующей стены.
	Теперь по краю трассы идёт низкий цветной бортик, за ним видно долину
	с деревьями и небо, а выше бортика стоит невидимая стенка: спрыгнуть
	с трассы в сторону по-прежнему нельзя.
]]
local RAIL_HEIGHT = 2.5
local GUARD_MAX_SPAN = 80 -- длиннее кусок невидимой стенки не делаем
local GUARD_STRAIGHT = 0.99995 -- косинус угла: меньше полуградуса поворота — это прямая
local GUARD_SAMPLE = 5 -- шаг, с которым меряется размах высот под стенкой
local GUARD_MAX_TURN = 0.07 -- радиан поворота внутри одного куска стенки, около четырёх градусов
local GUARD_MIN_PIECE = 1.5

local function buildCorridor(model: Model, path, length: number, obstacles: { any }, attractions: { any }?)
	local half = Tunnel.WIDTH / 2

	buildFloor(model, path, length, obstacles, attractions)
	local voids = RunAttractions.holes(attractions)

	for _, side in { -1, 1 } do
		local x = side * (half + Tunnel.WALL_THICKNESS / 2)

		pieces(path, 0, length, CURVE_CHUNK * 2, function(mid: number, size: number, curved: boolean)
			local color = SEGMENT_RAILS[(segmentAt(path, mid) - 1) % #SEGMENT_RAILS + 1]
			local rail = build(
				`Rail_{side}_{math.floor(mid)}`,
				Vector3.new(Tunnel.WALL_THICKNESS, RAIL_HEIGHT, size + (if curved then 1.2 else 0)),
				path.frame(mid) * CFrame.new(x, RAIL_HEIGHT / 2, 0),
				color,
				model
			)
			rail.Material = Enum.Material.SmoothPlastic
		end)

		--[[
			Невидимые стенки кладутся длинными кусками везде, где трасса в плане
			не поворачивает: на горках, ямках и подъёмах стенке незачем повторять
			рельеф — она просто выше на размах высот. Раньше стенка шла кусками
			по десять студов, как бортик, и на забеге 11-го уровня это было
			почти полторы сотни деталей, которых никто не видит.
		]]
		local spanFrom: number? = nil
		local spanTo = 0
		local function flush()
			if not spanFrom then
				return
			end
			local from, to = spanFrom, spanTo
			spanFrom = nil
			local low, high = math.huge, -math.huge
			local z = from
			while true do
				local y = path.flat(math.min(z, to)).Position.Y
				low, high = math.min(low, y), math.max(high, y)
				if z >= to then
					break
				end
				z += GUARD_SAMPLE
			end
			local mid = (from + to) / 2
			local midY = path.flat(mid).Position.Y
			local tall = Tunnel.HEIGHT + (high - low)
			local guard = build(
				`Guard_{side}_{math.floor(mid)}`,
				-- Толще бортика и наружу: остаток изгиба на длинном куске не открывает щель.
				Vector3.new(Tunnel.WALL_THICKNESS + 2, tall, to - from + 1.5),
				path.flat(mid) * CFrame.new(x + side, low - midY + tall / 2, 0),
				Color3.fromRGB(255, 255, 255),
				model
			)
			guard.Transparency = 1
		end

		--[[
			Крутой поворот режется на куски помельче, пока поворот внутри куска
			не станет меньше GUARD_MAX_TURN. Иначе на углах зигзага прямой кусок
			открывал у внешнего края клин, в который проскакивал ребёнок, а удлинять
			кусок нельзя — на внутренней стороне поворота он вылезал бы на дорожку.
		]]
		local function turnOf(from: number, to: number): number
			return math.acos(math.clamp(path.flat(from).LookVector:Dot(path.flat(to).LookVector), -1, 1))
		end

		local function addPiece(from: number, to: number)
			if to - from > GUARD_MIN_PIECE and turnOf(from, to) > GUARD_MAX_TURN then
				local cut = (from + to) / 2
				addPiece(from, cut)
				addPiece(cut, to)
				return
			end
			if spanFrom then
				local straight = path.flat(spanFrom).LookVector:Dot(path.flat(to).LookVector) > GUARD_STRAIGHT
				-- Зигзаг может вернуться к прежнему курсу со сдвигом вбок: такое не прямая.
				local aside = math.abs(path.flat(spanFrom):PointToObjectSpace(path.flat(to).Position).X)
				if straight and aside < 0.3 and to - spanFrom <= GUARD_MAX_SPAN then
					spanTo = to
					return
				end
				flush()
			end
			spanFrom, spanTo = from, to
		end

		pieces(path, 0, length, CURVE_CHUNK * 2, function(mid: number, size: number)
			addPiece(mid - size / 2, mid + size / 2)
		end)
		flush()
	end

	-- Разметка дорожек на прямых: ребёнку нужно видеть, что дорожек ровно три.
	for lane = 1, Tunnel.LANE_COUNT - 1 do
		local x = Tunnel.laneOffset(lane) + Tunnel.LANE_WIDTH / 2
		pieces(path, 0, length, CURVE_CHUNK, function(mid: number, size: number, curved: boolean)
			if curved then
				return
			end
			-- Над пропастью аттракциона разметке лежать не на чем.
			for _, void in voids do
				if mid + size / 2 > void.from and mid - size / 2 < void.to then
					return
				end
			end
			local stripe = build(
				`LaneStripe_{lane}_{math.floor(mid)}`,
				Vector3.new(0.4, 0.1, size),
				path.frame(mid) * CFrame.new(x, 0.05, 0),
				Color3.fromRGB(235, 230, 215),
				model
			)
			stripe.CanCollide = false
		end)
	end
end

--[[
	Количество под числом: столько же шариков, сколько написано цифрой.

	Это первое правило математики в игре (docs/16-MATH.md § 1): сначала количество,
	потом значок. Ребёнок 4–5 лет должен увидеть три предмета и лишь затем узнать
	в «3» их обозначение, иначе он выучит картинку, за которой ничего не стоит.

	Больше пяти в ряд не ставим — считать длинную линию взглядом уже тяжело,
	и второй ряд читается быстрее.
]]
local PIP_ROW = 5
local PIP_SIZE = 0.9

local function buildPips(model: Model, at: CFrame, count: number, color: Color3, name: string)
	for index = 1, count do
		local row = math.floor((index - 1) / PIP_ROW)
		local column = (index - 1) % PIP_ROW
		local inRow = math.min(PIP_ROW, count - row * PIP_ROW)

		local pip = build(
			`{name}_{index}`,
			Vector3.new(PIP_SIZE, PIP_SIZE, PIP_SIZE),
			at * CFrame.new((column - (inRow - 1) / 2) * (PIP_SIZE + 0.35), -row * (PIP_SIZE + 0.3), 0),
			color,
			model
		)
		pip.Shape = Enum.PartType.Ball
		pip.CanCollide = false
		pip.Material = Enum.Material.Neon
	end
end

--[[
	Условие задачи над воротами: пример («2 + 2») и тарелки с предметами.

	Тарелки — это то, ради чего умножению вообще разрешили выйти за десяток:
	три тарелки по два ребёнок пересчитывает, а двузначное число не читает
	(docs/16-MATH.md § 1, правило 3). У букв ни того, ни другого нет, и функция
	просто ничего не строит.
]]
local function buildGateHeader(model: Model, origin: CFrame, gate: any)
	local at = origin * CFrame.new(0, Tunnel.HEIGHT * 0.78, -gate.z)

	if gate.prompt and gate.prompt ~= "" then
		local board = build(
			`GatePrompt_{gate.index}`,
			Vector3.new(Tunnel.WIDTH * 0.5, 3, 0.6),
			at,
			Color3.fromRGB(250, 245, 230),
			model
		)
		board.CanCollide = false
		attachGlyph(board, gate.prompt, Color3.fromRGB(60, 55, 80))
	end

	local groups = gate.groups
	local each = gate.each
	if not groups or not each then
		return
	end

	for group = 1, groups do
		local plateAt = at * CFrame.new((group - (groups + 1) / 2) * 5, -3.5, 0)
		local plate = build(
			`GatePlate_{gate.index}_{group}`,
			Vector3.new(4, 0.4, 0.6),
			plateAt,
			Color3.fromRGB(250, 245, 230),
			model
		)
		plate.CanCollide = false

		buildPips(
			model,
			plateAt * CFrame.new(0, 1.2, 0),
			each,
			Color3.fromRGB(235, 120, 110),
			`GateApple_{gate.index}_{group}`
		)
	end
end

--[[
	Ворота — арка из колонн, а не ряд цветных коробок. Колонна на каждой границе
	дорожек, сверху перемычка с лампочками, выше всего, что висит над воротами
	(пример и тарелки математики). Закрытая дорожка — деревянная дверь с
	перекладинами: она читается как «сюда нельзя», а не как ещё один цвет.
]]
local GATE_TOP = Tunnel.HEIGHT - 1
local GATE_STONE = Color3.fromRGB(245, 240, 230)
local GATE_DOOR = Color3.fromRGB(195, 145, 100)
local GATE_BOARD = Color3.fromRGB(150, 105, 70)
local GATE_BULBS = {
	Color3.fromRGB(255, 120, 120),
	Color3.fromRGB(255, 200, 90),
	Color3.fromRGB(130, 220, 140),
	Color3.fromRGB(120, 185, 255),
	Color3.fromRGB(200, 150, 240),
}

local function buildGateArch(model: Model, origin: CFrame, gate: any)
	local at = origin * CFrame.new(0, 0, -gate.z)
	local half = Tunnel.WIDTH / 2
	for boundary = 0, Tunnel.LANE_COUNT do
		local x = -half + boundary * Tunnel.LANE_WIDTH
		local plinth = build(
			`GatePlinth_{gate.index}_{boundary}`,
			Vector3.new(2.4, 1.4, 2.4),
			at * CFrame.new(x, 0.7, 0),
			GATE_STONE,
			model
		)
		plinth.Material = Enum.Material.Marble
		local pillar = build(
			`GatePillar_{gate.index}_{boundary}`,
			Vector3.new(GATE_TOP, 1.6, 1.6),
			at * CFrame.new(x, GATE_TOP / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			GATE_STONE,
			model
		)
		pillar.Shape = Enum.PartType.Cylinder
		pillar.Material = Enum.Material.Marble
		local cap = build(
			`GateCap_{gate.index}_{boundary}`,
			Vector3.new(2.2, 2.2, 2.2),
			at * CFrame.new(x, GATE_TOP + 2.6, 0),
			GATE_BULBS[boundary % #GATE_BULBS + 1],
			model
		)
		cap.Shape = Enum.PartType.Ball
		cap.CanCollide = false
	end

	local lintel = build(
		`GateLintel_{gate.index}`,
		Vector3.new(Tunnel.WIDTH + 2.4, 1.6, 2),
		at * CFrame.new(0, GATE_TOP + 0.8, 0),
		GATE_STONE,
		model
	)
	lintel.Material = Enum.Material.Marble
	-- Лампочки на перемычке со стороны бегущего: ворота видно издалека.
	for bulb = 1, 7 do
		local light = build(
			`GateBulb_{gate.index}_{bulb}`,
			Vector3.new(0.7, 0.7, 0.7),
			at * CFrame.new((bulb - 4) * 3.8, GATE_TOP + 0.8, 1.05),
			GATE_BULBS[bulb % #GATE_BULBS + 1],
			model
		)
		light.Shape = Enum.PartType.Ball
		light.Material = Enum.Material.Neon
		light.CanCollide = false
	end
end

local function dressDoor(model: Model, at: CFrame, name: string)
	for index, y in { 3, Tunnel.HEIGHT - 4 } do
		local board = build(
			`{name}_Board_{index}`,
			Vector3.new(Tunnel.LANE_WIDTH - 1.8, 1, 0.3),
			at * CFrame.new(0, y, 0.85),
			GATE_BOARD,
			model
		)
		board.Material = Enum.Material.WoodPlanks
		board.CanCollide = false
	end
	local rise = Tunnel.HEIGHT - 7
	local run = Tunnel.LANE_WIDTH - 2.4
	local brace = build(
		`{name}_Brace`,
		Vector3.new(math.sqrt(rise * rise + run * run), 0.9, 0.3),
		at * CFrame.new(0, Tunnel.HEIGHT / 2 - 0.5, 0.85) * CFrame.Angles(0, 0, math.atan2(rise, run)),
		GATE_BOARD,
		model
	)
	brace.Material = Enum.Material.WoodPlanks
	brace.CanCollide = false
end

local function buildGate(model: Model, origin: CFrame, gate: any, player: Player)
	local openLanes: { [number]: any } = {}
	for _, opening in gate.openings do
		openLanes[opening.lane] = opening
	end

	buildGateHeader(model, origin, gate)
	buildGateArch(model, origin, gate)

	for lane = 1, Tunnel.LANE_COUNT do
		local x = Tunnel.laneOffset(lane)
		local opening = openLanes[lane]
		local at = origin * CFrame.new(x, 0, -gate.z)

		if opening then
			--[[
				Проём: рамка по краям и невидимый триггер посередине.

				Что написано над проёмом, ворота не решают — знак и цвет приходят
				готовыми из плана забега. Поэтому один и тот же код строит и буквы,
				и числа: план знает предмет обучения, геометрия — нет.
			]]
			local color = opening.color or Color3.fromRGB(200, 200, 210)

			local frame = build(
				`GateFrame_{gate.index}_{lane}`,
				Vector3.new(Tunnel.LANE_WIDTH, 1.2, 1.2),
				at * CFrame.new(0, Tunnel.HEIGHT * 0.55, 0),
				color,
				model
			)
			frame.CanCollide = false
			attachGlyph(frame, opening.glyph, Color3.fromRGB(255, 255, 255))

			if (opening.pips or 0) > 0 then
				buildPips(
					model,
					at * CFrame.new(0, Tunnel.HEIGHT * 0.42, 0),
					opening.pips,
					color,
					`GatePip_{gate.index}_{lane}`
				)
			end

			local trigger = build(
				`GateTrigger_{gate.index}_{lane}`,
				Vector3.new(Tunnel.LANE_WIDTH - 0.5, Tunnel.HEIGHT * 0.5, 1.5),
				at * CFrame.new(0, Tunnel.HEIGHT * 0.25, 0),
				color,
				model
			)
			trigger.CanCollide = false
			trigger.Transparency = 0.75

			trigger.Touched:Connect(function(hit: BasePart)
				local character = hit.Parent
				if not character or Players:GetPlayerFromCharacter(character) ~= player then
					return
				end
				ChallengeService.submitAction(player, {
					kind = "gate",
					gateIndex = gate.index,
					lane = lane,
				})
			end)
		else
			-- Закрытая дорожка: сплошная дверь до перемычки, объехать выбор нельзя
			local door = build(
				`GateWall_{gate.index}_{lane}`,
				Vector3.new(Tunnel.LANE_WIDTH, Tunnel.HEIGHT, 1.5),
				at * CFrame.new(0, Tunnel.HEIGHT / 2, 0),
				GATE_DOOR,
				model
			)
			door.Material = Enum.Material.WoodPlanks
			dressDoor(model, at, `GateDoor_{gate.index}_{lane}`)
		end
	end
end

--[[
	Секрет уровня (docs/18-CONTENT-BACKLOG.md § 8): постамент в крайней дорожке
	и над ним золотая буква, вокруг которой искрится. Мимо можно пробежать,
	а можно запрыгнуть и коснуться — голос назовёт букву, и за первую
	находку упадут звёздочки. Найденный однажды секрет больше не строится.
]]
local SECRET_GOLD = Color3.fromRGB(255, 205, 80)

local function buildSecret(model: Model, origin: CFrame, secret: any, player: Player, resumeFrom: number)
	if not secret or secret.found or secret.segment <= resumeFrom then
		return
	end

	local x = Tunnel.laneOffset(secret.lane)
	local pedestal = build(
		"SecretPedestal",
		Tunnel.SECRET_PEDESTAL,
		origin * CFrame.new(x, Tunnel.SECRET_PEDESTAL.Y / 2, -secret.z),
		Color3.fromRGB(190, 170, 140),
		model
	)
	pedestal.Material = Enum.Material.Cobblestone

	--[[
		Касание ловит невидимая плитка; видна объёмная золотая буква (World/Letter3D).
		Раньше это была золотая плитка с надписью в один студ — издалека просто
		жёлтый квадрат. Буква покачивается и чуть поворачивается, но не крутится
		кругом: крутясь, она полпути была бы зеркальной — ровно то, от чего
		отучает Зеркало.
	]]
	local tile = build(
		"SecretTile",
		Vector3.new(Tunnel.SECRET_SIZE, Tunnel.SECRET_SIZE, 1.2),
		origin * CFrame.new(x, Tunnel.SECRET_PEDESTAL.Y + Tunnel.SECRET_LIFT, -secret.z),
		SECRET_GOLD,
		model
	)
	tile.CanCollide = false
	tile.Transparency = 1

	if secret.letterId then
		-- Буква смотрит на бегущего: он приближается с +Z пути.
		local facing = tile.CFrame * CFrame.Angles(0, math.pi, 0)
		local letter = Letter3D.build(secret.letterId, Tunnel.SECRET_SIZE * 1.2, facing, SECRET_GOLD, {
			material = Enum.Material.Foil,
			reflectance = 0.1,
		})
		letter.Parent = model
		-- Детали приварены к невидимой анкерной втулке: качается одна она.
		local hub = build("SecretLetterHub", Vector3.one * 0.2, facing, SECRET_GOLD, model)
		hub.Transparency = 1
		hub.CanCollide = false
		for _, letterPart in letter:GetChildren() do
			if letterPart:IsA("BasePart") then
				letterPart.Anchored = false
				letterPart.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = hub
				weld.Part1 = letterPart
				weld.Parent = hub
			end
		end
		hub.CFrame = facing * CFrame.Angles(0, math.rad(-22), 0)
		TweenService:Create(
			hub,
			TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ CFrame = facing * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, math.rad(22), 0) }
		):Play()
	end

	-- Искры: секрет должно быть видно издалека, иначе это не секрет, а пропажа.
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(1, 2)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Color = ColorSequence.new(SECRET_GOLD)
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(0.4, 0)
	sparkle.Parent = tile

	tile.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character or Players:GetPlayerFromCharacter(character) ~= player then
			return
		end
		ChallengeService.submitAction(player, { kind = "secret" })
	end)
end

--[[
	Приваривает деталь к анкерной: связка ездит вместе с ней, но толкает мягко.
	Нужно маятнику — верёвка и шар должны ходить за подвесом.
]]
local function weldTo(anchor: BasePart, part: BasePart)
	part.Anchored = false
	part.Massless = true

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = part
	weld.Parent = anchor
end

--[[
	Бесконечное «туда-обратно» по синусу: так ходят маятник и платформа.

	Твин, а не свой цикл на Heartbeat: он сам останавливается вместе с деталью,
	когда туннель убирают, и не оставляет за собой висящих потоков.
]]
local function swing(part: BasePart, to: CFrame, seconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(part, info, { CFrame = to }):Play()
end

--[[
	Весы особого участка мира математики (docs/16-MATH.md § 3.3, план — params.balance).

	Над трассой перед прозрачной преградой висят большие весы: на левой чаше камни,
	правая пустая, коромысло наклонено. На полу по дорожкам кучки камней разного цвета.
	Встал на кучку, где камней столько же, — они ложатся на правую чашу, весы
	выравниваются, преграда исчезает. Ошибка — весы качнулись и вернулись, короткое
	замедление, верная кучка светится. Цифр нигде нет.
]]
local BALANCE_COLORS = {
	Color3.fromRGB(240, 150, 150),
	Color3.fromRGB(150, 205, 140),
	Color3.fromRGB(245, 200, 110),
}
local BALANCE_STONE = 1.1
local BALANCE_ARM = 7
local BALANCE_HEIGHT = 11
local BALANCE_TILT = math.rad(14)

local function balanceStones(
	anchor: BasePart,
	count: number,
	color: Color3,
	name: string,
	top: number,
	parent: Instance
)
	local perRow = 3
	local rows = math.ceil(count / perRow)
	for index = 1, count do
		local row = math.floor((index - 1) / perRow)
		local inRow = math.min(perRow, count - row * perRow)
		local column = (index - 1) % perRow
		local stone = build(
			`{name}_{index}`,
			Vector3.one * BALANCE_STONE,
			anchor.CFrame
				* CFrame.new(
					(column - (inRow - 1) / 2) * BALANCE_STONE * 1.2,
					top + BALANCE_STONE / 2,
					(row - (rows - 1) / 2) * BALANCE_STONE * 1.2
				),
			color,
			parent
		)
		stone.Shape = Enum.PartType.Ball
		stone.Material = Enum.Material.Pebble
		stone.CanCollide = false
		weldTo(anchor, stone)
	end
end

local function balanceBarrierZ(balance, index: number): number
	return balance.z + Tunnel.BALANCE_LEAD + (index - 1) * Tunnel.BALANCE_PITCH
end

local function buildBalance(model: Model, origin: CFrame, balance: any, player: Player, resumeFrom: number)
	if not balance or #balance.rounds == 0 or balance.segment <= resumeFrom then
		return
	end

	for index, round in balance.rounds do
		local z = balanceBarrierZ(balance, index)

		local barrier = build(
			`BalanceBarrier_{index}`,
			Vector3.new(Tunnel.WIDTH, 12, 0.6),
			origin * CFrame.new(0, 6, -z),
			Color3.fromRGB(255, 235, 190),
			model
		)
		barrier.Material = Enum.Material.ForceField
		barrier.Transparency = 0.2

		-- Весы над преградой: столбы по краям, коромысло посередине.
		for _, side in { -1, 1 } do
			local post = build(
				`BalancePost_{index}_{side}`,
				Vector3.new(1, BALANCE_HEIGHT + 3, 1),
				origin * CFrame.new(side * (Tunnel.WIDTH / 2 - 0.5), (BALANCE_HEIGHT + 3) / 2, -z),
				Color3.fromRGB(170, 120, 75),
				model
			)
			post.Material = Enum.Material.WoodPlanks
		end
		local crossbar = build(
			`BalanceCrossbar_{index}`,
			Vector3.new(Tunnel.WIDTH, 1, 1),
			origin * CFrame.new(0, BALANCE_HEIGHT + 3, -z),
			Color3.fromRGB(170, 120, 75),
			model
		)
		crossbar.Material = Enum.Material.WoodPlanks

		local level = origin * CFrame.new(0, BALANCE_HEIGHT, -(z + 1.5))
		local beam = build(
			`BalanceBeam_{index}`,
			Vector3.new(BALANCE_ARM * 2 + 1, 0.5, 0.6),
			level * CFrame.Angles(0, 0, BALANCE_TILT),
			Color3.fromRGB(215, 175, 90),
			model
		)
		beam.Material = Enum.Material.Metal
		beam:SetAttribute("Level", level)

		for _, side in { -1, 1 } do
			local pan = build(
				`BalancePan_{index}_{side}`,
				Vector3.new(3.6, 0.4, 3.6),
				beam.CFrame * CFrame.new(side * BALANCE_ARM, -2.5, 0),
				Color3.fromRGB(215, 175, 90),
				model
			)
			pan.Material = Enum.Material.Metal
			weldTo(beam, pan)
			if side < 0 then
				balanceStones(
					pan,
					round.left,
					Color3.fromRGB(130, 170, 215),
					`BalanceGiven_{index}`,
					0.2,
					model
				)
			end
		end

		-- Кучки на полу перед преградой.
		local padZ = z - Tunnel.BALANCE_PITCH / 2 + 1.5
		for slot, choice in round.choices do
			local color = BALANCE_COLORS[(slot - 1) % #BALANCE_COLORS + 1]
			local pad = build(
				`BalancePad_{index}_{slot}`,
				Vector3.new(6, 0.5, 5),
				origin * CFrame.new(Tunnel.laneOffset(choice.lane), 0.25, -padZ),
				Color3.fromRGB(170, 120, 75),
				model
			)
			pad.Material = Enum.Material.WoodPlanks
			pad:SetAttribute("PileColor", color)
			balanceStones(pad, choice.count, color, `BalancePile_{index}_{slot}`, 0.25, model)

			local last = 0
			pad.Touched:Connect(function(hit: BasePart)
				local character = hit.Parent
				if not character or Players:GetPlayerFromCharacter(character) ~= player then
					return
				end
				local now = os.clock()
				if now - last < 1 then
					return
				end
				last = now
				ChallengeService.submitAction(player, { kind = "balance", round = index, slot = slot })
			end)
		end
	end
end

local function onBalanceAnswer(player: Player, result: any)
	local run = runs[player]
	if not run then
		return
	end
	local balance = run.spec.params.balance
	local round = balance and balance.rounds[result.round]
	local beam = run.model:FindFirstChild(`BalanceBeam_{result.round}`)
	if not round or not beam or not beam:IsA("BasePart") then
		return
	end
	local level = beam:GetAttribute("Level")
	if typeof(level) ~= "CFrame" then
		return
	end

	if result.correct then
		local pan = run.model:FindFirstChild(`BalancePan_{result.round}_1`)
		local pad = run.model:FindFirstChild(`BalancePad_{result.round}_{result.slot}`)
		local color = if pad then pad:GetAttribute("PileColor") else nil
		if pan and pan:IsA("BasePart") then
			balanceStones(
				pan,
				round.left,
				if typeof(color) == "Color3" then color else Color3.fromRGB(240, 150, 150),
				`BalanceChosen_{result.round}`,
				0.2,
				run.model
			)
		end
		TweenService:Create(beam, TweenInfo.new(0.6, Enum.EasingStyle.Back), { CFrame = level }):Play()
		local barrier = run.model:FindFirstChild(`BalanceBarrier_{result.round}`)
		if barrier then
			barrier:Destroy()
		end
		return
	end

	-- Весы качнулись к пустой чаше и вернулись: кучка оказалась не той.
	local tilted = beam.CFrame
	local swingInfo = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true)
	TweenService:Create(beam, swingInfo, { CFrame = level * CFrame.Angles(0, 0, -BALANCE_TILT) }):Play()
	task.delay(0.8, function()
		if beam.Parent then
			beam.CFrame = tilted
		end
	end)

	TunnelService.slow(player, result.cooldown or Tunnel.SPECIAL_MISS_SECONDS, 0.5)
	for slot, choice in round.choices do
		if choice.count == round.left then
			local pad = run.model:FindFirstChild(`BalancePad_{result.round}_{slot}`)
			if pad and pad:IsA("BasePart") then
				pad.Material = Enum.Material.Neon
				pad.Color = Color3.fromRGB(255, 225, 140)
			end
		end
	end
end

--[[
	Элементы полосы препятствий. Каталог — Config/Obstacles, раскладку по пути
	считает Challenges/RunCourse, здесь только геометрия.

	Общее для всех: ни один элемент не требует точного тайминга и ни один
	не перекрывает все три дорожки насмерть. Обойти или перепрыгнуть можно всегда,
	и пройти можно медленно. См. docs/19-OBSTACLES.md § 2.
]]
local OBSTACLE_BUILDERS: { [string]: (Model, CFrame, any, number) -> () } = {
	-- Барьер: перепрыгнуть или обойти по соседней дорожке.
	barrier = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local part = build(
			`Barrier_{index}`,
			Vector3.new(Tunnel.LANE_WIDTH - 1, Tunnel.BARRIER_HEIGHT, Tunnel.BARRIER_LENGTH),
			origin * CFrame.new(Tunnel.laneOffset(obstacle.lane), Tunnel.BARRIER_HEIGHT / 2, -obstacle.z),
			Color3.fromRGB(240, 170, 90),
			model
		)
		part.Material = Enum.Material.Wood
	end,

	-- Яма: пола на этом куске дорожки нет. Края помечены, чтобы дырка была видна.
	gap = function(model: Model, origin: CFrame, obstacle: any, index: number)
		for _, edge in { obstacle.z, obstacle.z + Tunnel.GAP_LENGTH } do
			local marker = build(
				`GapEdge_{index}_{math.floor(edge)}`,
				Vector3.new(Tunnel.LANE_WIDTH, 0.4, 0.8),
				origin * CFrame.new(Tunnel.laneOffset(obstacle.lane), 0.2, -edge),
				Color3.fromRGB(250, 210, 120),
				model
			)
			marker.CanCollide = false
		end
	end,

	-- Низкий свод: перепрыгнуть нельзя, только обойти. Учит смотреть вперёд.
	arch = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local height = Tunnel.HEIGHT - Tunnel.ARCH_CLEARANCE
		local part = build(
			`Arch_{index}`,
			Vector3.new(Tunnel.LANE_WIDTH, height, 1.5),
			origin
				* CFrame.new(
					Tunnel.laneOffset(obstacle.lane),
					Tunnel.ARCH_CLEARANCE + height / 2,
					-obstacle.z
				),
			Color3.fromRGB(150, 130, 200),
			model
		)
		part.Material = Enum.Material.Slate
	end,

	-- Балка: пола нет нигде, кроме узкой доски посередине.
	beam = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local part = build(
			`Beam_{index}`,
			Vector3.new(Tunnel.BEAM_WIDTH, 1, Tunnel.BEAM_LENGTH),
			origin * CFrame.new(0, -0.5, -(obstacle.z + Tunnel.BEAM_LENGTH / 2)),
			Color3.fromRGB(200, 170, 120),
			model
		)
		part.Material = Enum.Material.WoodPlanks
	end,

	-- Ступени во всю ширину: подъём прыжками и спуск. Падать здесь некуда.
	steps = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local total = Tunnel.STEP_COUNT * 2
		for step = 1, total do
			local level = if step <= Tunnel.STEP_COUNT then step else total - step + 1
			local height = level * Tunnel.STEP_HEIGHT
			build(
				`Step_{index}_{step}`,
				Vector3.new(Tunnel.WIDTH, height, Tunnel.STEP_RUN),
				origin * CFrame.new(0, height / 2, -(obstacle.z + (step - 0.5) * Tunnel.STEP_RUN)),
				Color3.fromRGB(180, 200, 170),
				model
			)
		end
	end,

	--[[
		Горка во всю ширину: клин вверх и клин вниз. Клин у Roblox высокий сзади,
		поэтому подъём развёрнут на пол-оборота, а спуск стоит как есть.
	]]
	hump = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local up = Instance.new("WedgePart")
		up.Name = `HumpUp_{index}`
		up.Size = Vector3.new(Tunnel.WIDTH, Tunnel.HUMP_HEIGHT, Tunnel.HUMP_RUN)
		up.CFrame = origin
			* CFrame.new(0, Tunnel.HUMP_HEIGHT / 2, -(obstacle.z + Tunnel.HUMP_RUN / 2))
			* CFrame.Angles(0, math.pi, 0)
		up.Color = Color3.fromRGB(150, 205, 140)
		up.Material = Enum.Material.Grass
		up.Anchored = true
		up.Parent = model

		local down = Instance.new("WedgePart")
		down.Name = `HumpDown_{index}`
		down.Size = Vector3.new(Tunnel.WIDTH, Tunnel.HUMP_HEIGHT, Tunnel.HUMP_RUN)
		down.CFrame = origin * CFrame.new(0, Tunnel.HUMP_HEIGHT / 2, -(obstacle.z + Tunnel.HUMP_RUN * 1.5))
		down.Color = Color3.fromRGB(150, 205, 140)
		down.Material = Enum.Material.Grass
		down.Anchored = true
		down.Parent = model

		-- Флажок на макушке: горку видно издалека, и на неё хочется забежать.
		local pole = build(
			`HumpPole_{index}`,
			Vector3.new(0.25, 3, 0.25),
			origin
				* CFrame.new(
					-Tunnel.WIDTH / 2 + 1.5,
					Tunnel.HUMP_HEIGHT + 1.5,
					-(obstacle.z + Tunnel.HUMP_RUN)
				),
			Color3.fromRGB(245, 245, 250),
			model
		)
		pole.CanCollide = false
		local flag = build(
			`HumpFlag_{index}`,
			Vector3.new(1.6, 1, 0.15),
			origin
				* CFrame.new(
					-Tunnel.WIDTH / 2 + 2.35,
					Tunnel.HUMP_HEIGHT + 2.5,
					-(obstacle.z + Tunnel.HUMP_RUN)
				),
			Color3.fromRGB(245, 120, 90),
			model
		)
		flag.CanCollide = false
	end,

	-- Слалом: конусы змейкой, мягкие — сталкиваются, но не сбивают.
	cones = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local x = Tunnel.laneOffset(obstacle.lane)
		for cone = 1, Tunnel.CONE_COUNT do
			local side = if cone % 2 == 0 then 1 else -1
			local at = origin * CFrame.new(x + side * 2, 0, -(obstacle.z + (cone - 0.5) * Tunnel.CONE_STEP))
			local base = build(
				`ConeBase_{index}_{cone}`,
				Vector3.new(Tunnel.CONE_SIZE + 0.6, 0.3, Tunnel.CONE_SIZE + 0.6),
				at * CFrame.new(0, 0.15, 0),
				Color3.fromRGB(245, 120, 60),
				model
			)
			base.CanCollide = false
			local body = build(
				`Cone_{index}_{cone}`,
				Vector3.new(Tunnel.CONE_SIZE, 2.2, Tunnel.CONE_SIZE),
				at * CFrame.new(0, 1.1, 0),
				Color3.fromRGB(250, 140, 70),
				model
			)
			body.Shape = Enum.PartType.Cylinder
			body.Size = Vector3.new(2.2, Tunnel.CONE_SIZE, Tunnel.CONE_SIZE)
			body.CFrame = at * CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90))
			local stripe = build(
				`ConeStripe_{index}_{cone}`,
				Vector3.new(0.4, Tunnel.CONE_SIZE + 0.05, Tunnel.CONE_SIZE + 0.05),
				at * CFrame.new(0, 1.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(250, 250, 245),
				model
			)
			stripe.Shape = Enum.PartType.Cylinder
			stripe.CanCollide = false
		end
	end,

	--[[
		Средний ряд (docs/19-OBSTACLES.md § 3.2). Общее для всех пяти:
		соседняя дорожка свободна, ждать можно сколько угодно, и ни один
		не движется быстрее ребёнка.
	]]

	--[[
		Маятник: мягкий шар на подвесе ходит поперёк своей дорожки за четыре секунды.
		Подвес анкерный, шар и верёвка приварены к нему — так вся связка ездит
		вместе с подвесом и при этом толкает мягко, а не сбивает.
	]]
	pendulum = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local x = Tunnel.laneOffset(obstacle.lane)
		local top = origin * CFrame.new(x, Tunnel.HEIGHT - 0.5, -obstacle.z)
		local from = top * CFrame.Angles(0, 0, Tunnel.PENDULUM_SWING)

		local pivot = build(
			`PendulumPivot_{index}`,
			Vector3.new(1.5, 0.5, 1.5),
			from,
			Color3.fromRGB(120, 165, 220),
			model
		)
		pivot.CanCollide = false

		local rope = build(
			`PendulumRope_{index}`,
			Vector3.new(0.4, Tunnel.PENDULUM_ROPE, 0.4),
			from * CFrame.new(0, -Tunnel.PENDULUM_ROPE / 2, 0),
			Color3.fromRGB(150, 130, 110),
			model
		)
		rope.CanCollide = false
		weldTo(pivot, rope)

		local ball = build(
			`PendulumBall_{index}`,
			Vector3.new(Tunnel.PENDULUM_BALL, Tunnel.PENDULUM_BALL, Tunnel.PENDULUM_BALL),
			from * CFrame.new(0, -(Tunnel.PENDULUM_ROPE + Tunnel.PENDULUM_BALL / 2), 0),
			Color3.fromRGB(235, 130, 150),
			model
		)
		ball.Shape = Enum.PartType.Ball
		weldTo(pivot, ball)

		swing(pivot, top * CFrame.Angles(0, 0, -Tunnel.PENDULUM_SWING), Tunnel.PENDULUM_SECONDS)
	end,

	--[[
		Движущаяся платформа над ямой. Яма не длиннее обычной: её перепрыгивают
		и без платформы, так что промахнуться мимо неё ничем не грозит,
		а дождаться и проехать — приятно.
	]]
	platform = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local x = Tunnel.laneOffset(obstacle.lane)

		for _, edge in { obstacle.z, obstacle.z + Tunnel.PLATFORM_SPAN } do
			local marker = build(
				`PlatformEdge_{index}_{math.floor(edge)}`,
				Vector3.new(Tunnel.LANE_WIDTH, 0.4, 0.8),
				origin * CFrame.new(x, 0.2, -edge),
				Color3.fromRGB(250, 210, 120),
				model
			)
			marker.CanCollide = false
		end

		local startZ = obstacle.z - Tunnel.PLATFORM_LEAD
		local from = origin * CFrame.new(x, 0.5, -(startZ + Tunnel.PLATFORM_LENGTH / 2))
		local plate = build(
			`Platform_{index}`,
			Vector3.new(Tunnel.LANE_WIDTH - 1, 1, Tunnel.PLATFORM_LENGTH),
			from,
			Color3.fromRGB(150, 200, 230),
			model
		)

		swing(plate, from * CFrame.new(0, 0, -Tunnel.PLATFORM_TRAVEL), Tunnel.PLATFORM_SECONDS)
	end,

	--[[
		Исчезающие плиты над ямой в одну дорожку.

		Плиты гаснут по очереди со сдвигом в треть цикла, поэтому две подряд
		не пропадают никогда и дорожка не превращается в сплошную яму.
		Каждая держит три с половиной секунды — это не проверка реакции.
	]]
	fading = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local x = Tunnel.laneOffset(obstacle.lane)
		local cycle = Tunnel.FADE_SOLID_SECONDS + Tunnel.FADE_GONE_SECONDS

		for tile = 1, Tunnel.FADE_TILE_COUNT do
			local at = obstacle.z + (tile - 0.5) * Tunnel.FADE_TILE_RUN
			local plate = build(
				`FadingTile_{index}_{tile}`,
				Vector3.new(Tunnel.LANE_WIDTH - 1, 1, Tunnel.FADE_TILE_RUN - 0.5),
				origin * CFrame.new(x, -0.5, -at),
				Color3.fromRGB(225, 195, 240),
				model
			)

			local offset = (tile - 1) * cycle / Tunnel.FADE_TILE_COUNT

			-- Цикл живёт, пока жива плита: туннель убирается вместе с забегом.
			task.spawn(function()
				task.wait(offset)
				while plate.Parent do
					plate.CanCollide = true
					plate.Transparency = 0
					task.wait(Tunnel.FADE_SOLID_SECONDS)
					if not plate.Parent then
						break
					end
					plate.CanCollide = false
					plate.Transparency = 0.75
					task.wait(Tunnel.FADE_GONE_SECONDS)
				end
			end)
		end
	end,

	--[[
		Батут: подбрасывает вверх. Ничего не отнимает, ничем не грозит и никуда
		не обязывает — просто весело, и это тоже причина остаться в игре.
	]]
	trampoline = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local pad = build(
			`Trampoline_{index}`,
			Vector3.new(Tunnel.LANE_WIDTH - 1, 1, Tunnel.TRAMPOLINE_LENGTH),
			origin
				* CFrame.new(
					Tunnel.laneOffset(obstacle.lane),
					0.5,
					-(obstacle.z + Tunnel.TRAMPOLINE_LENGTH / 2)
				),
			Color3.fromRGB(120, 220, 180),
			model
		)
		pad.Material = Enum.Material.Neon

		pad.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not humanoid or not root then
				return
			end
			-- Уже летит вверх — второй раз не толкаем: иначе батут отправляет в потолок.
			if root.AssemblyLinearVelocity.Y > 5 then
				return
			end
			root.AssemblyLinearVelocity = Vector3.new(
				root.AssemblyLinearVelocity.X,
				Tunnel.TRAMPOLINE_POWER,
				root.AssemblyLinearVelocity.Z
			)
		end)
	end,

	--[[
		Скользкий лёд во всю ширину: разгоняет и заносит, но падать с него некуда —
		под ним обычный пол. Самый безобидный из среднего ряда.
	]]
	ice = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local slab = build(
			`Ice_{index}`,
			Vector3.new(Tunnel.WIDTH, 0.5, Tunnel.ICE_LENGTH),
			origin * CFrame.new(0, 0.25, -(obstacle.z + Tunnel.ICE_LENGTH / 2)),
			Color3.fromRGB(190, 225, 245),
			model
		)
		slab.Material = Enum.Material.Ice
		slab.Transparency = 0.15
		slab.CustomPhysicalProperties = PhysicalProperties.new(0.7, Tunnel.ICE_FRICTION, 0.2, 1, 1)
	end,

	--[[
		Кочки: яма в одну дорожку и три камня через неё. Камни чуть выше пола,
		чтобы по ним хотелось прыгать, а не просто идти; щели между ними
		перешагиваются. Промахнулся — мягкое дно и сохранка.
	]]
	stones = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local x = Tunnel.laneOffset(obstacle.lane)
		for _, edge in { obstacle.z, obstacle.z + Tunnel.STONES_SPAN } do
			local marker = build(
				`StonesEdge_{index}_{math.floor(edge)}`,
				Vector3.new(Tunnel.LANE_WIDTH, 0.4, 0.8),
				origin * CFrame.new(x, 0.2, -edge),
				Color3.fromRGB(250, 210, 120),
				model
			)
			marker.CanCollide = false
		end

		local step = Tunnel.STONES_SPAN / Tunnel.STONE_COUNT
		for stone = 1, Tunnel.STONE_COUNT do
			local part = build(
				`Stone_{index}_{stone}`,
				Vector3.new(Tunnel.STONE_SIZE, 1.4, Tunnel.STONE_SIZE),
				origin * CFrame.new(x, 0.1, -(obstacle.z + (stone - 0.5) * step)),
				Color3.fromRGB(165, 160, 150),
				model
			)
			part.Material = Enum.Material.Slate
		end
	end,

	--[[
		Подвесной мост. Доски лежат по провисающей дуге и покачиваются волной
		на пол-студа — мост живой, но идти по нему спокойно. Перила — верёвки
		от столбов к середине, по пояс ребёнку, и они сталкиваются: оступиться
		в яму с моста нельзя, только спрыгнуть нарочно.
	]]
	bridge = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local x = Tunnel.laneOffset(obstacle.lane)
		local span = Tunnel.BRIDGE_SPAN
		local half = Tunnel.BRIDGE_WIDTH / 2
		local wood = Color3.fromRGB(175, 125, 80)
		local rope = Color3.fromRGB(225, 200, 150)

		local function sagAt(t: number): number
			return Tunnel.BRIDGE_SAG * (1 - (2 * t - 1) ^ 2)
		end

		local step = span / Tunnel.BRIDGE_PLANKS
		for plank = 1, Tunnel.BRIDGE_PLANKS do
			local t = (plank - 0.5) / Tunnel.BRIDGE_PLANKS
			local board = build(
				`BridgePlank_{index}_{plank}`,
				Vector3.new(Tunnel.BRIDGE_WIDTH, 0.4, step - 0.2),
				origin * CFrame.new(x, -0.2 - sagAt(t), -(obstacle.z + (plank - 0.5) * step)),
				if plank % 2 == 0 then wood else Color3.fromRGB(195, 145, 95),
				model
			)
			board.Material = Enum.Material.WoodPlanks
			-- Волна по доскам: у каждой своя задержка, поэтому качается весь мост, а не одна доска.
			task.delay((plank - 1) * 0.15, function()
				if board.Parent then
					TweenService:Create(
						board,
						TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
						{ CFrame = board.CFrame * CFrame.new(0, -0.25, 0) }
					):Play()
				end
			end)
		end

		for _, side in { -1, 1 } do
			for _, edge in { obstacle.z, obstacle.z + span } do
				local post = build(
					`BridgePost_{index}_{side}_{math.floor(edge)}`,
					Vector3.new(0.6, Tunnel.BRIDGE_RAIL_HEIGHT + 1.4, 0.6),
					origin
						* CFrame.new(
							x + side * (half + 0.3),
							(Tunnel.BRIDGE_RAIL_HEIGHT + 1.4) / 2 - 0.6,
							-edge
						),
					Color3.fromRGB(140, 100, 65),
					model
				)
				post.Material = Enum.Material.Wood
			end
			-- Верёвка провисает к середине вместе с досками, двумя кусками.
			for _, from in { 0, 0.5 } do
				local a = Vector3.new(
					x + side * (half + 0.3),
					Tunnel.BRIDGE_RAIL_HEIGHT - sagAt(from),
					-(obstacle.z + from * span)
				)
				local b = Vector3.new(
					x + side * (half + 0.3),
					Tunnel.BRIDGE_RAIL_HEIGHT - sagAt(from + 0.5),
					-(obstacle.z + (from + 0.5) * span)
				)
				local middle = (a + b) / 2
				local length = (b - a).Magnitude
				local tilt = math.atan2(b.Y - a.Y, -(b.Z - a.Z))
				local rail = build(
					`BridgeRope_{index}_{side}_{from}`,
					Vector3.new(0.3, 0.3, length + 0.3),
					origin * CFrame.new(middle) * CFrame.Angles(tilt, 0, 0),
					rope,
					model
				)
				rail.Material = Enum.Material.Fabric
			end
		end
	end,

	--[[
		Сложный ряд (docs/19-OBSTACLES.md § 3.2.1): бревно, поршень, гребёнка.
		Встречаются на поздних уровнях и у уверенных; правила всё те же.
	]]

	--[[
		Бревно поперёк дорожки: крутится на месте, высотой с барьер. Бревно
		круглое, так что вращение только на вид — толкать оно не толкает,
		а прыгать через крутящееся веселее, чем через стоящее.
	]]
	roller = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local at = origin
			* CFrame.new(Tunnel.laneOffset(obstacle.lane), Tunnel.ROLLER_DIAMETER / 2, -obstacle.z)
		local log = build(
			`Roller_{index}`,
			Vector3.new(Tunnel.LANE_WIDTH - 1, Tunnel.ROLLER_DIAMETER, Tunnel.ROLLER_DIAMETER),
			at,
			Color3.fromRGB(160, 110, 70),
			model
		)
		log.Shape = Enum.PartType.Cylinder -- ось цилиндра — X, то есть поперёк дорожки
		log.Material = Enum.Material.Wood

		local info =
			TweenInfo.new(Tunnel.ROLLER_SECONDS, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1)
		TweenService:Create(log, info, { CFrame = at * CFrame.Angles(math.pi, 0, 0) }):Play()
	end,

	--[[
		Поршень: мягкий блок медленно выезжает из стены в крайнюю дорожку
		и уезжает обратно. Выезжает за четыре секунды — это не ловушка,
		а «подожди или обойди». Средней дорожки поршень не касается никогда.
	]]
	pistons = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local side = if obstacle.lane == 1 then -1 else 1
		local width = Tunnel.LANE_WIDTH - 1
		local y = Tunnel.PISTON_HEIGHT / 2

		local hidden = origin * CFrame.new(side * (Tunnel.WIDTH / 2 + width / 2), y, -obstacle.z)
		local shown = origin * CFrame.new(Tunnel.laneOffset(obstacle.lane), y, -obstacle.z)

		local block = build(
			`Piston_{index}`,
			Vector3.new(width, Tunnel.PISTON_HEIGHT, Tunnel.PISTON_DEPTH),
			hidden,
			Color3.fromRGB(240, 150, 170),
			model
		)

		-- Заметный край на полу: здесь что-то выезжает.
		local marker = build(
			`PistonMark_{index}`,
			Vector3.new(Tunnel.LANE_WIDTH, 0.1, Tunnel.PISTON_DEPTH + 1),
			origin * CFrame.new(Tunnel.laneOffset(obstacle.lane), 0.05, -obstacle.z),
			Color3.fromRGB(250, 210, 120),
			model
		)
		marker.CanCollide = false

		swing(block, shown, Tunnel.PISTON_SECONDS)
	end,

	--[[
		Карусель: низкий диск с четырьмя перекладинами крутится в одной дорожке.
		Оборот занимает двенадцать секунд, перекладины по колено: их перешагивают
		или пропускают. Диск не поднимает и не уносит — он просто мешает пройти
		напрямую, и обойти его можно всегда.
	]]
	carousel = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local x = Tunnel.laneOffset(obstacle.lane)
		local at = origin * CFrame.new(x, 0.2, -(obstacle.z + Tunnel.CAROUSEL_SPAN / 2))

		local disc = build(
			`Carousel_{index}`,
			Vector3.new(Tunnel.CAROUSEL_SPAN, 0.4, Tunnel.CAROUSEL_SPAN),
			at,
			Color3.fromRGB(250, 200, 120),
			model
		)
		disc.CanCollide = false

		--[[
			Перекладины — дети диска: крутится один твин, а не четыре, иначе
			они разошлись бы по фазе и карусель перестала бы быть каруселью.
		]]
		local hub = build(
			`CarouselHub_{index}`,
			Vector3.new(1, Tunnel.CAROUSEL_BAR_HEIGHT, 1),
			at * CFrame.new(0, Tunnel.CAROUSEL_BAR_HEIGHT / 2, 0),
			Color3.fromRGB(200, 150, 90),
			model
		)
		hub.CanCollide = false

		for bar = 1, Tunnel.CAROUSEL_BARS do
			local angle = (bar - 1) / Tunnel.CAROUSEL_BARS * math.pi * 2
			local arm = build(
				`CarouselBar_{index}_{bar}`,
				Vector3.new(0.6, Tunnel.CAROUSEL_BAR_HEIGHT, Tunnel.CAROUSEL_SPAN / 2),
				hub.CFrame * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -Tunnel.CAROUSEL_SPAN / 4),
				Color3.fromRGB(235, 175, 105),
				model
			)
			--[[
				Перекладина приварена к втулке и НЕ закреплена сама: твин крутит
				одну втулку, сварка тянет за собой перекладины. Закрепи их —
				и они остались бы висеть на месте, пока втулка крутится под ними.
			]]
			arm.Anchored = false
			arm.Massless = true

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hub
			weld.Part1 = arm
			weld.Parent = hub
		end

		local info =
			TweenInfo.new(Tunnel.CAROUSEL_SECONDS, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1)
		TweenService:Create(hub, info, { CFrame = hub.CFrame * CFrame.Angles(0, math.pi, 0) }):Play()
	end,

	--[[
		Подъёмник: площадка ходит от пола до мостика, мостик идёт над той же
		дорожкой и кончается спуском. Наверху ничего не подстерегает — это просто
		другой путь через отрезок, с высоты которого видно ворота впереди.

		Ждать площадку не обязательно: соседние дорожки свободны, а падать
		с мостика некуда — под ним обычный пол.
	]]
	lift = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local x = Tunnel.laneOffset(obstacle.lane)
		local low = origin * CFrame.new(x, 0.25, -(obstacle.z + Tunnel.LIFT_PAD / 2))
		local high = origin * CFrame.new(x, Tunnel.LIFT_HEIGHT, -(obstacle.z + Tunnel.LIFT_PAD / 2))

		local pad = build(
			`Lift_{index}`,
			Vector3.new(Tunnel.LIFT_PAD, 0.5, Tunnel.LIFT_PAD),
			low,
			Color3.fromRGB(150, 205, 235),
			model
		)
		pad.Material = Enum.Material.SmoothPlastic
		pad.Anchored = true

		-- Мостик наверху: по нему бегут дальше и спрыгивают с дальнего края.
		local bridge = build(
			`LiftBridge_{index}`,
			Vector3.new(Tunnel.LIFT_PAD, 0.5, Tunnel.LIFT_SPAN - Tunnel.LIFT_PAD),
			origin
				* CFrame.new(
					x,
					Tunnel.LIFT_HEIGHT,
					-(obstacle.z + Tunnel.LIFT_PAD + (Tunnel.LIFT_SPAN - Tunnel.LIFT_PAD) / 2)
				),
			Color3.fromRGB(190, 220, 240),
			model
		)
		bridge.Material = Enum.Material.SmoothPlastic

		-- Столбик под мостиком: видно, что мостик на чём-то стоит, а не висит.
		local post = build(
			`LiftPost_{index}`,
			Vector3.new(0.8, Tunnel.LIFT_HEIGHT, 0.8),
			origin * CFrame.new(x, Tunnel.LIFT_HEIGHT / 2, -(obstacle.z + Tunnel.LIFT_SPAN - 0.5)),
			Color3.fromRGB(170, 175, 185),
			model
		)
		post.CanCollide = false

		swing(pad, high, Tunnel.LIFT_SECONDS)
	end,

	--[[
		Спираль: ступени по кругу вокруг столба — половина витка вверх, половина
		вниз. Стоит неподвижно, ждёт сколько угодно; шаг между ступенями обычный,
		как у ступеней базового ряда.
	]]
	spiral = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local x = Tunnel.laneOffset(obstacle.lane)
		local radius = Tunnel.SPIRAL_SPAN / 4
		local centerZ = obstacle.z + Tunnel.SPIRAL_SPAN / 2

		local pole = build(
			`SpiralPole_{index}`,
			Vector3.new(1, Tunnel.SPIRAL_HEIGHT + 2, 1),
			origin * CFrame.new(x, (Tunnel.SPIRAL_HEIGHT + 2) / 2, -centerZ),
			Color3.fromRGB(170, 175, 185),
			model
		)
		pole.CanCollide = false

		for step = 1, Tunnel.SPIRAL_STEPS do
			-- Подъём до середины витка и спуск обратно: спираль возвращает на пол.
			local half = Tunnel.SPIRAL_STEPS / 2
			local climb = if step <= half then step else Tunnel.SPIRAL_STEPS - step + 1
			local height = climb / half * Tunnel.SPIRAL_HEIGHT

			local angle = (step - 1) / Tunnel.SPIRAL_STEPS * math.pi * 2 - math.pi / 2
			local plate = build(
				`SpiralStep_{index}_{step}`,
				Vector3.new(3, 0.4, 3),
				origin
					* CFrame.new(x + math.cos(angle) * radius, height, -(centerZ + math.sin(angle) * radius)),
				Color3.fromRGB(215, 195, 235),
				model
			)
			plate.Material = Enum.Material.SmoothPlastic
		end
	end,

	--[[
		Гребёнка: стена поперёк коридора с узкой щелью в каждой дорожке.
		Путь не перекрыт — щель есть везде, — но в неё надо прицелиться.
	]]
	comb = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local tooth = (Tunnel.LANE_WIDTH - Tunnel.COMB_SLOT) / 2
		for lane = 1, Tunnel.LANE_COUNT do
			for _, side in { -1, 1 } do
				local x = Tunnel.laneOffset(lane) + side * (Tunnel.COMB_SLOT / 2 + tooth / 2)
				build(
					`Comb_{index}_{lane}_{side}`,
					Vector3.new(tooth, Tunnel.HEIGHT, Tunnel.COMB_THICKNESS),
					origin * CFrame.new(x, Tunnel.HEIGHT / 2, -obstacle.z),
					Color3.fromRGB(130, 180, 150),
					model
				)
			end
		end
	end,
}

--[[
	Отделка препятствий. Строители выше отвечают за то, что мешает бежать,
	а здесь — за то, чтобы это читалось вещью, а не цветным брусом: у барьера
	стойки и полосы, у свода колонны и замковый камень, у ступеней кромки,
	у балки фонарики на концах.

	Все детали отделки ни с чем не сталкиваются и ничего не ловят: форма
	препятствия, по которой бегут и прыгают, остаётся ровно той, что проверена
	тестами и детьми. Отделка только показывает её.
]]
local WHITE = Color3.fromRGB(250, 250, 245)
local WARNING = Color3.fromRGB(245, 120, 90)

local function trim(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3): BasePart
	local piece = build(name, size, cframe, color, model)
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.CastShadow = false
	return piece
end

local OBSTACLE_DRESSING: { [string]: (Model, CFrame, any, number) -> () } = {
	-- Барьер как спортивный: белые стойки по краям и полосы на планке.
	barrier = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local x = Tunnel.laneOffset(obstacle.lane)
		local half = (Tunnel.LANE_WIDTH - 1) / 2
		for _, side in { -1, 1 } do
			trim(
				model,
				`BarrierPost_{index}_{side}`,
				Vector3.new(0.5, Tunnel.BARRIER_HEIGHT + 0.8, 0.5),
				origin * CFrame.new(x + side * (half + 0.3), (Tunnel.BARRIER_HEIGHT + 0.8) / 2, -obstacle.z),
				WHITE
			)
		end
		for stripe = -1, 1 do
			trim(
				model,
				`BarrierStripe_{index}_{stripe}`,
				Vector3.new(0.9, Tunnel.BARRIER_HEIGHT * 0.5, Tunnel.BARRIER_LENGTH + 0.1),
				origin * CFrame.new(x + stripe * half * 0.6, Tunnel.BARRIER_HEIGHT * 0.65, -obstacle.z),
				WHITE
			)
		end
	end,

	-- Яма: полосатые кромки и по конусу с каждой стороны — дырку видно издалека.
	gap = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local x = Tunnel.laneOffset(obstacle.lane)
		for _, edge in { obstacle.z, obstacle.z + Tunnel.GAP_LENGTH } do
			for stripe = -2, 2 do
				trim(
					model,
					`GapStripe_{index}_{math.floor(edge)}_{stripe}`,
					Vector3.new(0.9, 0.45, 0.85),
					origin * CFrame.new(x + stripe * 1.8, 0.23, -edge),
					if stripe % 2 == 0 then WARNING else WHITE
				)
			end
		end
		for _, side in { -1, 1 } do
			local cone = trim(
				model,
				`GapCone_{index}_{side}`,
				Vector3.new(1.2, 1.6, 1.2),
				origin * CFrame.new(x + side * (Tunnel.LANE_WIDTH / 2 - 0.8), 0.8, -obstacle.z + 0.8),
				WARNING
			)
			cone.Shape = Enum.PartType.Ball
		end
	end,

	-- Свод: колонны до пола по краям дорожки, светящаяся кромка снизу и замковый камень.
	arch = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local x = Tunnel.laneOffset(obstacle.lane)
		for _, side in { -1, 1 } do
			local column = trim(
				model,
				`ArchColumn_{index}_{side}`,
				Vector3.new(0.8, Tunnel.ARCH_CLEARANCE, 1.7),
				origin
					* CFrame.new(
						x + side * (Tunnel.LANE_WIDTH / 2 - 0.4),
						Tunnel.ARCH_CLEARANCE / 2,
						-obstacle.z
					),
				Color3.fromRGB(120, 105, 170)
			)
			column.Material = Enum.Material.Slate
		end
		local edge = trim(
			model,
			`ArchEdge_{index}`,
			Vector3.new(Tunnel.LANE_WIDTH, 0.4, 1.7),
			origin * CFrame.new(x, Tunnel.ARCH_CLEARANCE + 0.2, -obstacle.z),
			Color3.fromRGB(255, 200, 110)
		)
		edge.Material = Enum.Material.Neon
		local key = trim(
			model,
			`ArchKey_{index}`,
			Vector3.new(2, 2.4, 1.9),
			origin * CFrame.new(x, Tunnel.HEIGHT - 1.4, -obstacle.z),
			Color3.fromRGB(255, 214, 102)
		)
		key.Material = Enum.Material.Slate
	end,

	-- Балка: торцевые доски и фонарики на концах — видно, где она начинается.
	beam = function(model: Model, origin: CFrame, obstacle: any, index: number)
		for _, edge in { obstacle.z, obstacle.z + Tunnel.BEAM_LENGTH } do
			trim(
				model,
				`BeamCap_{index}_{math.floor(edge)}`,
				Vector3.new(Tunnel.BEAM_WIDTH + 0.6, 0.3, 0.6),
				origin * CFrame.new(0, 0.1, -edge),
				Color3.fromRGB(150, 110, 70)
			)
			for _, side in { -1, 1 } do
				trim(
					model,
					`BeamLampPost_{index}_{math.floor(edge)}_{side}`,
					Vector3.new(0.25, 2.4, 0.25),
					origin * CFrame.new(side * (Tunnel.BEAM_WIDTH / 2 + 0.5), 1.2, -edge),
					Color3.fromRGB(120, 100, 80)
				)
				local lamp = trim(
					model,
					`BeamLamp_{index}_{math.floor(edge)}_{side}`,
					Vector3.new(0.7, 0.7, 0.7),
					origin * CFrame.new(side * (Tunnel.BEAM_WIDTH / 2 + 0.5), 2.6, -edge),
					Color3.fromRGB(255, 225, 150)
				)
				lamp.Shape = Enum.PartType.Ball
				lamp.Material = Enum.Material.Neon
			end
		end
	end,

	-- Ступени: белая кромка на каждой, чтобы край был виден до прыжка.
	steps = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local total = Tunnel.STEP_COUNT * 2
		for step = 1, total do
			local level = if step <= Tunnel.STEP_COUNT then step else total - step + 1
			local height = level * Tunnel.STEP_HEIGHT
			local z = obstacle.z + (step - 1) * Tunnel.STEP_RUN
			trim(
				model,
				`StepNosing_{index}_{step}`,
				Vector3.new(Tunnel.WIDTH, 0.25, 0.6),
				origin * CFrame.new(0, height + 0.1, -(z + 0.3)),
				WHITE
			)
			local tread = model:FindFirstChild(`Step_{index}_{step}`)
			if tread and tread:IsA("BasePart") then
				tread.Color = if step % 2 == 0
					then Color3.fromRGB(165, 205, 160)
					else Color3.fromRGB(195, 225, 180)
				tread.Material = Enum.Material.Slate
			end
		end
	end,

	-- Гребёнка: у зубьев круглые шапки и два цвета — щели видно сразу.
	comb = function(model: Model, origin: CFrame, obstacle: any, index: number)
		local tooth = (Tunnel.LANE_WIDTH - Tunnel.COMB_SLOT) / 2
		for lane = 1, Tunnel.LANE_COUNT do
			for _, side in { -1, 1 } do
				local x = Tunnel.laneOffset(lane) + side * (Tunnel.COMB_SLOT / 2 + tooth / 2)
				local part = model:FindFirstChild(`Comb_{index}_{lane}_{side}`)
				if part and part:IsA("BasePart") then
					part.Color = if lane % 2 == 0
						then Color3.fromRGB(130, 180, 150)
						else Color3.fromRGB(110, 160, 200)
					part.Material = Enum.Material.SmoothPlastic
				end
				local cap = trim(
					model,
					`CombCap_{index}_{lane}_{side}`,
					Vector3.new(tooth + 0.4, tooth + 0.4, tooth + 0.4),
					origin * CFrame.new(x, Tunnel.HEIGHT, -obstacle.z),
					Color3.fromRGB(255, 214, 102)
				)
				cap.Shape = Enum.PartType.Ball
			end
		end
	end,
}

local function buildObstacles(model: Model, origin: CFrame, obstacles: { any })
	for index, obstacle in obstacles or {} do
		local builder = OBSTACLE_BUILDERS[obstacle.kind]
		if builder then
			builder(model, origin, obstacle, index)
			local dressing = OBSTACLE_DRESSING[obstacle.kind]
			if dressing then
				dressing(model, origin, obstacle, index)
			end
		else
			warn(`[TunnelService] не умею строить препятствие "{obstacle.kind}"`)
		end
	end
end

local CHECKPOINT_COLD = Color3.fromRGB(160, 170, 180)
local CHECKPOINT_LIT = Color3.fromRGB(120, 220, 140)

--[[
	Сохранка: арка с флагом сразу за воротами. Пробежал — точка записана,
	и падение отбрасывает не дальше неё.

	Флаг меняет цвет на месте, без единого сетевого сообщения: ребёнку нужно
	видеть, что «здесь я уже был», а не читать уведомление.

	passed — арка уже пройдена в прошлый заход: флаг горит с самого начала,
	и в профиль ничего не пишется, там эта точка и так записана.
]]
local function buildCheckpoint(model: Model, origin: CFrame, checkpoint: any, player: Player, passed: boolean)
	local at = origin * CFrame.new(0, 0, -checkpoint.z)

	--[[
		Арка: два столба по краям трассы, перекладина и высокий флагшток справа.
		Раньше сохранка была светящейся планкой поперёк коридора — её было не отличить
		от ворот и не понять, что здесь «записалось». Флаг поднят и горит, когда
		арка пройдена.
	]]
	local archHeight = Tunnel.HEIGHT * 0.62
	local stone = Color3.fromRGB(235, 230, 220)
	for _, side in { -1, 1 } do
		local post = build(
			`CheckpointPost_{checkpoint.index}_{side}`,
			Vector3.new(1.4, archHeight, 1.4),
			at * CFrame.new(side * (Tunnel.WIDTH / 2 - 0.7), archHeight / 2, 0),
			stone,
			model
		)
		post.Material = Enum.Material.Marble
		post.CanCollide = false
		local cap = build(
			`CheckpointCap_{checkpoint.index}_{side}`,
			Vector3.new(2, 2, 2),
			at * CFrame.new(side * (Tunnel.WIDTH / 2 - 0.7), archHeight + 1, 0),
			CHECKPOINT_LIT,
			model
		)
		cap.Shape = Enum.PartType.Ball
		cap.CanCollide = false
	end
	local top = build(
		`CheckpointTop_{checkpoint.index}`,
		Vector3.new(Tunnel.WIDTH, 1.2, 1.4),
		at * CFrame.new(0, archHeight, 0),
		stone,
		model
	)
	top.Material = Enum.Material.Marble
	top.CanCollide = false

	local poleX = Tunnel.WIDTH / 2 - 0.7
	local pole = build(
		`CheckpointPole_{checkpoint.index}`,
		Vector3.new(0.35, 7, 0.35),
		at * CFrame.new(poleX, archHeight + 4.5, 0),
		Color3.fromRGB(245, 245, 250),
		model
	)
	pole.CanCollide = false

	local flag = build(
		`CheckpointFlag_{checkpoint.index}`,
		Vector3.new(3.4, 2.2, 0.2),
		at * CFrame.new(poleX - 1.9, archHeight + (if passed then 6.8 else 2.8), 0),
		if passed then CHECKPOINT_LIT else CHECKPOINT_COLD,
		model
	)
	flag.CanCollide = false
	if passed then
		flag.Material = Enum.Material.Neon
	end
	local flagTop = at * CFrame.new(poleX - 1.9, archHeight + 6.8, 0)

	local trigger = build(
		`CheckpointTrigger_{checkpoint.index}`,
		Vector3.new(Tunnel.WIDTH, Tunnel.HEIGHT * 0.5, 2),
		at * CFrame.new(0, Tunnel.HEIGHT * 0.25, 0),
		Color3.fromRGB(160, 220, 170),
		model
	)
	trigger.CanCollide = false
	trigger.Transparency = 0.85

	trigger.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character or Players:GetPlayerFromCharacter(character) ~= player then
			return
		end
		local run = runs[player]
		if not run or run.checkpointZ >= checkpoint.z then
			return
		end
		run.checkpointZ = checkpoint.z
		Teleport.setSafe(player, run.origin * CFrame.new(0, 4, -checkpoint.z))
		flag.Color = CHECKPOINT_LIT
		flag.Material = Enum.Material.Neon
		-- Флаг взлетает на верх флагштока: точка записана.
		TweenService:Create(flag, TweenInfo.new(0.6, Enum.EasingStyle.Back), { CFrame = flagTop }):Play()
		local burst = Instance.new("ParticleEmitter")
		burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		burst.Rate = 0
		burst.Speed = NumberRange.new(6, 10)
		burst.Lifetime = NumberRange.new(0.6, 1)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Color = ColorSequence.new(CHECKPOINT_LIT)
		burst.Parent = top
		burst:Emit(30)
		RemoteDefs.event("PlaySfx"):FireClient(player, "checkpoint")

		--[[
			Точка уходит в профиль сразу, а не в конце забега: ребёнок закрывает
			планшет не на финише, а посреди туннеля, и именно этот случай сохранка
			и обслуживает. См. docs/14-TUNNEL-MODE.md § 3.3.
		]]
		ProgressService.saveRunCheckpoint(player, run.spec, checkpoint.index)
	end)
end

--[[
	Мягкое дно. Упал — приземлился на облако и вернулся к последней сохранке.

	Ни жизней, ни счётчика падений, ни потери звёздочек: падение стоит нескольких
	секунд пути и ничего больше. См. docs/17-CONTENT-PLAN.md § 3.1.
]]
--[[
	Возврат к последней отметке: арке за воротами или флажку перед аттракционом.
	Зовут его мягкое дно (упал) и клиент (сбил валун, молот, обжёгся лавой).

	Ни жизней, ни счётчика падений, ни потери звёздочек: падение стоит нескольких
	секунд пути и ничего больше. См. docs/19-OBSTACLES.md § 2.
]]
function TunnelService.returnToCheckpoint(player: Player)
	local run = runs[player]
	if not run or os.clock() < run.fallingUntil then
		return
	end
	-- Пока идёт возврат, повторные касания игнорируем: иначе ребёнка
	-- телепортирует несколько раз подряд от одного падения.
	run.fallingUntil = os.clock() + 1

	-- Звук мягкий: внизу трава, а не смерть, и звук обязан это подтверждать.
	RemoteDefs.event("PlaySfx"):FireClient(player, "fall")

	Teleport.to(player, run.origin * CFrame.new(0, 4, -run.checkpointZ))
end

local VALLEY_DROP = Tunnel.FALL_DEPTH + 10 -- ниже самой глубокой ямки трассы
local VALLEY_WIDTH = Tunnel.WIDTH + 140
local VALLEY_CHUNK = 40

local function buildSoftBottom(model: Model, path, length: number, player: Player)
	local function onTouch(hit: BasePart)
		local character = hit.Parent
		if not character or Players:GetPlayerFromCharacter(character) ~= player then
			return
		end

		TunnelService.returnToCheckpoint(player)
	end

	--[[
		Внизу не облако-подложка, а зелёная долина вдоль всей трассы: она и ловит
		упавшего, и делает мир вокруг трассы местом. Долина ровная, трасса над ней
		петляет и ходит горками, и сверху видно, как высоко бежишь.
	]]
	local baseY = path.origin.Position.Y - VALLEY_DROP
	local z = 0
	while z < length + VALLEY_CHUNK do
		local flat = path.flat(math.clamp(z, 0, length))
		local at = CFrame.new(flat.Position.X, baseY, flat.Position.Z) * flat.Rotation
		local ground = build(
			`Valley_{math.floor(z)}`,
			Vector3.new(VALLEY_WIDTH, 2, VALLEY_CHUNK + 8),
			at,
			Color3.fromRGB(135, 195, 120),
			model
		)
		ground.Material = Enum.Material.Grass
		ground.Touched:Connect(onTouch)
		z += VALLEY_CHUNK
	end
end

--[[
	Деревья и кусты в долине по обе стороны трассы. Верхушки поднимаются почти
	до уровня бега: ребёнок видит, что мчится над лесом, а не по полосе в пустоте.
	Расстановка детерминирована сидом забега — как и всё остальное в нём.
]]
--[[
	Деревья чаще всего, но не только они: великанские мухоморы, домик-гриб,
	мельница и стожки. Долина одних ёлок на забеге в полторы минуты надоедала
	быстрее, чем кончалась трасса.
]]
local SCENERY = {
	"tree_round",
	"tree_pine",
	"bush_round",
	"tree_round",
	"rock_small",
	"tree_pine",
	"mushroom",
	"tree_round",
	"tree_pine",
	"mushroom_house",
	"hay_bales",
	"windmill",
}
-- Во сколько раз крупнее каталожного: мелочь в долине под трассой не разглядеть.
local SCENERY_SCALE = { mushroom = 2.2, hay_bales = 1.6, mushroom_house = 1.1, windmill = 1.2 }
-- Шаг деревьев в долине. Было 44: на длинном забеге лес давал четыре сотни деталей.
local SCENERY_STEP = 62

local function buildScenery(model: Model, path, length: number, seed: number)
	local random = Random.new(seed + 3571)
	local baseY = path.origin.Position.Y - VALLEY_DROP + 1
	local z = 10
	local slot = 0
	while z < length do
		for _, side in { -1, 1 } do
			slot += 1
			local id = SCENERY[random:NextInteger(1, #SCENERY)]
			local tree = DecorService.modelFor(id)
			if tree then
				local lateral = side * (Tunnel.WIDTH / 2 + 12 + random:NextNumber() * 30)
				local spot = path.flat(math.min(z + random:NextNumber() * 10, length))
					* CFrame.new(lateral, 0, 0)
				tree.Name = `Scenery_{slot}`
				tree.Parent = model
				if SCENERY_SCALE[id] then
					tree:ScaleTo(tree:GetScale() * SCENERY_SCALE[id])
				elseif id ~= "rock_small" and id ~= "bush_round" then
					tree:ScaleTo(tree:GetScale() * (1.6 + random:NextNumber() * 0.6))
				end
				-- Домики и мельницы смотрят дверью на трассу, остальное как попало.
				local facing = if id == "windmill" or id == "mushroom_house"
					then CFrame.lookAt(spot.Position, path.flat(z).Position).Rotation
					else CFrame.Angles(0, random:NextNumber() * 6.28, 0)
				tree:PivotTo(CFrame.new(spot.Position.X, baseY, spot.Position.Z) * facing)
				local box, size = tree:GetBoundingBox()
				tree:PivotTo(tree:GetPivot() + Vector3.new(0, baseY - (box.Position.Y - size.Y / 2), 0))
				for _, descendant in tree:GetDescendants() do
					if descendant:IsA("BasePart") then
						descendant.Anchored = true
						descendant.CanCollide = false
					end
				end
			end
		end
		z += SCENERY_STEP
	end
end

--[[
	Что стоит на зонах формы. Горка без ничего — просто горка; с аркой наверху
	и стрелками ускорения у подножия это уже аттракцион, ради которого ребёнок
	бежит пробежку, а не пережидает её.

	  · горка, волна, подъём — радужная арка над вершиной и стрелки-ускорители;
	  · вираж и змейка — большая вертушка снаружи поворота;
	  · ямка и спуск — звезда, качающаяся над трассой.

	Ничто из этого не мешает бежать: декор не сталкивается, ускоритель только
	подталкивает вперёд на полторы секунды.
]]
local ARCH_COLORS = {
	Color3.fromRGB(240, 110, 110),
	Color3.fromRGB(250, 180, 90),
	Color3.fromRGB(250, 225, 100),
	Color3.fromRGB(130, 210, 130),
	Color3.fromRGB(110, 170, 240),
	Color3.fromRGB(180, 130, 230),
}
local BOOST_SECONDS = 1.5
local BOOST_FACTOR = 1.5

local function buildArch(model: Model, path, z: number, name: string)
	local at = path.flat(z)
	local half = Tunnel.WIDTH / 2 + 1.5
	local top = 13
	for index, color in ARCH_COLORS do
		local angle = math.pi * (index - 0.5) / #ARCH_COLORS
		local x = -math.cos(angle) * half
		local y = math.sin(angle) * top
		local piece = build(
			`{name}_{index}`,
			Vector3.new(3.2, 3.2, 1.4),
			at * CFrame.new(x, y + 1, 0) * CFrame.Angles(0, 0, angle - math.pi / 2),
			color,
			model
		)
		piece.Material = Enum.Material.Neon
		piece.CanCollide = false
	end
end

local function buildSpinner(model: Model, at: CFrame, name: string, radius: number)
	local hub = build(`{name}_Hub`, Vector3.new(1.4, 1.4, 1.4), at, Color3.fromRGB(250, 250, 250), model)
	hub.CanCollide = false
	for blade = 1, 4 do
		local color = ARCH_COLORS[(blade * 2 - 1) % #ARCH_COLORS + 1]
		local angle = (blade - 1) * math.pi / 2
		local part = build(
			`{name}_Blade_{blade}`,
			Vector3.new(radius, 2.4, 0.4),
			hub.CFrame * CFrame.Angles(0, 0, angle) * CFrame.new(radius / 2, 0, 0),
			color,
			model
		)
		part.CanCollide = false
		-- Лопасть приварена к втулке и не закреплена сама: твин крутит одну втулку.
		part.Anchored = false
		part.Massless = true
		weldTo(hub, part)
	end
	local info = TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1)
	TweenService:Create(hub, info, { CFrame = hub.CFrame * CFrame.Angles(0, 0, math.pi) }):Play()
end

local function buildBoost(model: Model, path, z: number, name: string, player: Player)
	for chevron = 0, 2 do
		local arrow = build(
			`{name}_Arrow_{chevron}`,
			Vector3.new(Tunnel.WIDTH - 4, 0.15, 1.2),
			path.frame(z + chevron * 2.2) * CFrame.new(0, 0.08, 0),
			Color3.fromRGB(120, 235, 255),
			model
		)
		arrow.Material = Enum.Material.Neon
		arrow.CanCollide = false
	end

	local trigger = build(
		`{name}_Trigger`,
		Vector3.new(Tunnel.WIDTH, 4, 7),
		path.flat(z + 2.2) * CFrame.new(0, 2, 0),
		Color3.fromRGB(120, 235, 255),
		model
	)
	trigger.CanCollide = false
	trigger.Transparency = 1

	local last = 0
	trigger.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character or Players:GetPlayerFromCharacter(character) ~= player then
			return
		end
		local run = runs[player]
		local now = os.clock()
		-- После неверных ворот ускоритель не отменяет замедление: ошибка стоит времени.
		if not run or now - last < 2 or now < run.slowUntil then
			return
		end
		last = now
		TunnelService.boost(player, BOOST_SECONDS, BOOST_FACTOR)
	end)
end

local function buildZoneDecor(model: Model, path, player: Player)
	for index, zone in path.sampler.zones do
		local mid = (zone.from + zone.to) / 2
		local name = `Zone_{index}`
		if zone.kind == "hill" or zone.kind == "wave" or zone.kind == "climb" then
			buildArch(model, path, mid, `{name}_Arch`)
			buildBoost(model, path, zone.from + 1, name, player)
		elseif zone.kind == "zigzag" or zone.kind == "turn_left" or zone.kind == "turn_right" then
			-- Снаружи поворота: там, куда ребёнок и так смотрит на вираже.
			local outside = if zone.kind == "turn_left" then 1 else -1
			local at = path.flat(mid) * CFrame.new(outside * (Tunnel.WIDTH / 2 + 9), 8, 0)
			local post = build(
				`{name}_Post`,
				Vector3.new(0.8, 16, 0.8),
				at * CFrame.new(0, -8, 0),
				Color3.fromRGB(240, 240, 245),
				model
			)
			post.CanCollide = false
			buildSpinner(model, at * CFrame.Angles(0, math.pi / 2, 0), `{name}_Spinner`, 7)
		elseif zone.kind == "dip" or zone.kind == "descent" then
			local star = build(
				`{name}_Star`,
				Vector3.new(3, 3, 3),
				path.flat(mid) * CFrame.new(0, 11, 0),
				Color3.fromRGB(255, 214, 102),
				model
			)
			star.Shape = Enum.PartType.Ball
			star.Material = Enum.Material.Neon
			star.CanCollide = false
			local info = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
			TweenService:Create(star, info, { CFrame = star.CFrame * CFrame.new(0, 2, 0) }):Play()
		end
	end
end

--[[
	Гирлянды флажков поперёк трассы — там, где над дорожкой ничего нет:
	не у ворот и сохранок, не над препятствиями, горками, лестницей и весами.
	На прямом отрезке между воротами иначе смотреть не на что, кроме пола.
	Висят высоко и ни с чем не сталкиваются.
]]
local GARLAND_HEIGHT = 11
local GARLAND_STEP = 55 -- реже нельзя: пусто; чаще — сотни деталей на длинном забеге
local GARLAND_FLAGS = 7
-- Препятствия, которые поднимаются к гирлянде. Низкие ей не мешают: она висит над ними.
local TALL_OBSTACLES =
	{ arch = true, pendulum = true, lift = true, spiral = true, carousel = true, pistons = true }

local function buildGarland(model: Model, path, z: number, name: string)
	local at = path.flat(z)
	local half = Tunnel.WIDTH / 2 + Tunnel.WALL_THICKNESS + 0.4
	for _, side in { -1, 1 } do
		local post = build(
			`{name}_Post_{side}`,
			Vector3.new(0.5, GARLAND_HEIGHT + 0.6, 0.5),
			at * CFrame.new(side * half, (GARLAND_HEIGHT + 0.6) / 2, 0),
			Color3.fromRGB(250, 250, 245),
			model
		)
		post.CanCollide = false
	end
	local sag = 1.8
	for _, side in { -1, 1 } do
		local from = Vector3.new(side * half, GARLAND_HEIGHT, 0)
		local to = Vector3.new(0, GARLAND_HEIGHT - sag, 0)
		local rope = build(
			`{name}_Rope_{side}`,
			Vector3.new((to - from).Magnitude, 0.12, 0.12),
			at * CFrame.new((from + to) / 2) * CFrame.Angles(0, 0, math.atan2(to.Y - from.Y, to.X - from.X)),
			Color3.fromRGB(250, 250, 245),
			model
		)
		rope.CanCollide = false
	end
	for index = 1, GARLAND_FLAGS do
		local t = (index - 0.5) / GARLAND_FLAGS
		local x = -half + t * 2 * half
		local y = GARLAND_HEIGHT - sag * (1 - math.abs(2 * t - 1)) - 0.75
		local flag = build(
			`{name}_Flag_{index}`,
			Vector3.new(1.1, 1.1, 0.12),
			at * CFrame.new(x, y, 0) * CFrame.Angles(0, 0, math.pi / 4),
			ARCH_COLORS[(index - 1) % #ARCH_COLORS + 1],
			model
		)
		flag.CanCollide = false
	end
end

local function buildGarlands(model: Model, path, spec: any)
	local params = spec.params
	local length = params.length
	local busy: { { number } } = {}
	local function block(from: number, to: number)
		table.insert(busy, { from, to })
	end
	for _, gate in params.gates or {} do
		block(gate.z - 9, gate.z + 9)
	end
	for _, checkpoint in params.checkpoints or {} do
		block(checkpoint.z - 6, checkpoint.z + 6)
	end
	for _, obstacle in params.obstacles or {} do
		if TALL_OBSTACLES[obstacle.kind] then
			block(obstacle.z - 6, obstacle.z + Tunnel.OBSTACLE_PITCH + 6)
		end
	end
	for _, zone in path.sampler.zones do
		block(zone.from - 4, zone.to + 4)
	end
	for _, station in params.stations or {} do
		block(station.z - 4, station.z + Tunnel.STATION_PITCH + 4)
	end
	for _, ride in params.attractions or {} do
		block(ride.flagZ - 4, ride.z + ride.length + 4)
	end
	local balance = params.balance
	if balance and #balance.rounds > 0 then
		block(balance.z - 6, balanceBarrierZ(balance, #balance.rounds) + 6)
	end
	block(length - 24, length + 1)

	local count = 0
	local z = 12
	while z < length do
		local free = true
		for _, span in busy do
			if z >= span[1] and z <= span[2] then
				free = false
				break
			end
		end
		if free then
			count += 1
			buildGarland(model, path, z, `Garland_{count}`)
			z += GARLAND_STEP
		else
			z += 4
		end
	end
end

local function buildFinish(model: Model, origin: CFrame, length: number, player: Player)
	local at = origin * CFrame.new(0, 0, -(length - 6))
	local half = Tunnel.WIDTH / 2

	--[[
		Финиш — клетчатые столбы, клетчатое полотно поперёк трассы, шарики
		на столбах и золотая звезда, которая покачивается над серединой.
		Раньше это была жёлтая планка, похожая на сохранку.
	]]
	local checkWhite = Color3.fromRGB(250, 250, 250)
	local checkBlack = Color3.fromRGB(45, 45, 55)
	local cube = 2.2
	for _, side in { -1, 1 } do
		for level = 0, 6 do
			local block = build(
				`FinishPost_{side}_{level}`,
				Vector3.new(cube, cube, cube),
				at * CFrame.new(side * (half - cube / 2), cube / 2 + level * cube, 0),
				if (level + (side + 1) / 2) % 2 == 0 then checkWhite else checkBlack,
				model
			)
			block.CanCollide = level == 0
		end
		for index, color in { GATE_BULBS[1], GATE_BULBS[2], GATE_BULBS[4] } do
			local offset = Vector3.new(side * (half - 1.1) + (index - 2) * 1.3, 7 * cube + 3 + (index % 2), 0)
			local balloon = build(
				`FinishBalloon_{side}_{index}`,
				Vector3.new(2, 2, 2),
				at * CFrame.new(offset),
				color,
				model
			)
			balloon.Shape = Enum.PartType.Ball
			balloon.CanCollide = false
			local thread = build(
				`FinishBalloonString_{side}_{index}`,
				Vector3.new(0.1, 3, 0.1),
				at * CFrame.new(offset - Vector3.new(0, 2.4, 0)),
				checkWhite,
				model
			)
			thread.CanCollide = false
		end
	end
	local columns = 9
	local square = (Tunnel.WIDTH - 2 * cube) / columns
	for row = 0, 1 do
		for column = 0, columns - 1 do
			local cell = build(
				`FinishBanner_{row}_{column}`,
				Vector3.new(square, square, 0.4),
				at * CFrame.new(-half + cube + square * (column + 0.5), 7 * cube - square * (row + 0.5), 0),
				if (row + column) % 2 == 0 then checkWhite else checkBlack,
				model
			)
			cell.CanCollide = false
		end
	end
	local star = build(
		"FinishStar",
		Vector3.new(3.4, 3.4, 3.4),
		at * CFrame.new(0, 7 * cube + 2.4, 0),
		Color3.fromRGB(255, 214, 102),
		model
	)
	star.Shape = Enum.PartType.Ball
	star.Material = Enum.Material.Neon
	star.CanCollide = false
	TweenService:Create(
		star,
		TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ CFrame = star.CFrame * CFrame.new(0, 1.5, 0) }
	):Play()

	local trigger = build(
		"FinishTrigger",
		Vector3.new(Tunnel.WIDTH, Tunnel.HEIGHT * 0.6, 2),
		at * CFrame.new(0, Tunnel.HEIGHT * 0.3, 0),
		Color3.fromRGB(255, 214, 102),
		model
	)
	trigger.CanCollide = false
	trigger.Transparency = 0.8

	trigger.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character or Players:GetPlayerFromCharacter(character) ~= player then
			return
		end
		ChallengeService.submitAction(player, { kind = "finish" })
	end)

	-- Стена за финишем: чтобы не убежать в пустоту за краем туннеля. Радужная, а не синяя глухая.
	build(
		"EndWall",
		Vector3.new(Tunnel.WIDTH, Tunnel.HEIGHT, 2),
		origin * CFrame.new(0, Tunnel.HEIGHT / 2, -length),
		Color3.fromRGB(250, 245, 235),
		model
	)
	for index, color in ARCH_COLORS do
		local stripe = build(
			`EndWallStripe_{index}`,
			Vector3.new(Tunnel.WIDTH, 1.4, 0.3),
			origin * CFrame.new(0, 2 + (index - 1) * 2, -length + 1.1),
			color,
			model
		)
		stripe.CanCollide = false
	end
end

--[[
	Станции и аттракционы с флажками (World/RunAttractions). Станция открывается,
	когда ребёнок встал в круг: голос называет букву отрезка. Пройденные в прошлый
	заход станции стоят открытыми, флажки — горят.
]]
local function touchedBy(player: Player, hit: BasePart): boolean
	local character = hit.Parent
	return character ~= nil and Players:GetPlayerFromCharacter(character) == player
end

--[[
	Отметка пройдена: сюда вернёт следующее падение. Отметки идут только вперёд —
	вернуться к прошлому флажку и «сбросить» дальнюю арку нельзя.
]]
local function markReached(player: Player, z: number): boolean
	local run = runs[player]
	if not run or run.checkpointZ >= z then
		return false
	end
	run.checkpointZ = z
	Teleport.setSafe(player, run.origin * CFrame.new(0, 4, -z))
	return true
end

local function buildStations(model: Model, path, spec: any, player: Player)
	local resumeFrom = spec.params.resumeFrom or 0
	for _, station in spec.params.stations or {} do
		local passed = station.segment <= resumeFrom
		local open = RunAttractions.buildStation(model, path, station, passed)
		if passed then
			continue
		end
		local trigger = build(
			`StationTrigger_{station.index}`,
			Vector3.new(Tunnel.WIDTH, Tunnel.HEIGHT * 0.6, 3),
			path * CFrame.new(0, Tunnel.HEIGHT * 0.3, -(station.z + Tunnel.STATION_TRIGGER_Z)),
			station.color,
			model
		)
		trigger.CanCollide = false
		trigger.Transparency = 1
		local done = false
		trigger.Touched:Connect(function(hit: BasePart)
			if done or not touchedBy(player, hit) or not runs[player] then
				return
			end
			done = true
			markReached(player, station.z + Tunnel.STATION_TRIGGER_Z - 2)
			RemoteDefs.event("PlayVO"):FireClient(player, station.vo, true)
			RemoteDefs.event("PlaySfx"):FireClient(player, "checkpoint")
			open()
		end)
	end
end

local function buildAttractions(model: Model, path, spec: any, player: Player)
	local resumeFrom = spec.params.resumeFrom or 0
	for _, ride in spec.params.attractions or {} do
		RunAttractions.buildAttraction(model, path, ride)
		local pennant = RunAttractions.buildFlag(model, path, ride)
		if ride.segment <= resumeFrom then
			RunAttractions.lightFlag(pennant)
			continue
		end
		local trigger = build(
			`FlagTrigger_{ride.index}`,
			Vector3.new(Tunnel.WIDTH, Tunnel.HEIGHT * 0.6, 2),
			path * CFrame.new(0, Tunnel.HEIGHT * 0.3, -ride.flagZ),
			Color3.fromRGB(255, 200, 70),
			model
		)
		trigger.CanCollide = false
		trigger.Transparency = 1
		trigger.Touched:Connect(function(hit: BasePart)
			if not touchedBy(player, hit) then
				return
			end
			if markReached(player, ride.flagZ) then
				RunAttractions.lightFlag(pennant)
				RemoteDefs.event("PlaySfx"):FireClient(player, "checkpoint")
			end
		end)
	end
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

function TunnelService.spawn(player: Player, spec: any)
	TunnelService.despawn(player)

	local index = plotFor(player)
	local origin =
		makePath(CFrame.new(Tunnel.PLOT_ORIGIN + Vector3.new(index * Tunnel.PLOT_SPACING, 0, 0)), spec)
	local length = spec.params.length
	origin.seams = {}
	for _, gate in spec.params.gates do
		table.insert(origin.seams, gate.z)
	end
	origin.cuts = {}
	for _, void in RunAttractions.holes(spec.params.attractions) do
		table.insert(origin.cuts, void.from)
		table.insert(origin.cuts, void.to)
	end

	local model = Instance.new("Model")
	model.Name = `Tunnel_{player.UserId}`
	-- Какой это забег: по метке клиент выбирает музыку (Controllers/MusicController).
	model:SetAttribute("Challenge", spec.challengeId)
	model.Parent = ensureContainer()

	buildCorridor(model, origin, length, spec.params.obstacles, spec.params.attractions)
	for _, gate in spec.params.gates do
		buildGate(model, origin, gate, player)
	end
	buildObstacles(model, origin, spec.params.obstacles)
	buildSecret(model, origin, spec.params.secret, player, spec.params.resumeFrom or 0)
	buildBalance(model, origin, spec.params.balance, player, spec.params.resumeFrom or 0)
	buildFinish(model, origin, length, player)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	--[[
		Продолженный забег начинается не у входа, а у последней пройденной арки:
		переигрывать уже пройденное ребёнка не заставляем.
	]]
	local resumeFrom = spec.params.resumeFrom or 0
	local resumed = (spec.params.checkpoints or {})[resumeFrom]
	local startZ = if resumed then resumed.z else 0

	runs[player] = {
		model = model,
		origin = origin,
		returnCFrame = if root then root.CFrame else nil,
		spec = spec,
		slowUntil = 0,
		checkpointZ = startZ,
		fallingUntil = 0,
	}

	-- Сохранки и дно строятся после записи забега: их триггеры читают runs[player].
	for _, checkpoint in spec.params.checkpoints or {} do
		buildCheckpoint(model, origin, checkpoint, player, checkpoint.index <= resumeFrom)
	end
	buildStations(model, origin, spec, player)
	buildAttractions(model, origin, spec, player)
	buildSoftBottom(model, origin, length, player)
	buildScenery(model, origin, length, spec.seed or 0)
	buildZoneDecor(model, origin, player)
	buildGarlands(model, origin, spec)

	if character then
		Teleport.to(player, origin * CFrame.new(0, 4, -math.max(startZ, 4)))
	end

	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = Tunnel.WALK_SPEED
		humanoid.JumpPower = Tunnel.JUMP_POWER
		humanoid.UseJumpPower = true
	end
end

--[[
	Замедление после неверных ворот: единственная плата за ошибку — время.
	Прогресс, звёздочки и пройденные ворота не трогаются.
]]
function TunnelService.slow(player: Player, seconds: number, factor: number)
	local run = runs[player]
	local humanoid = humanoidOf(player)
	if not run or not humanoid then
		return
	end

	run.slowUntil = os.clock() + seconds
	humanoid.WalkSpeed = Tunnel.WALK_SPEED * factor

	task.delay(seconds, function()
		local current = runs[player]
		local currentHumanoid = humanoidOf(player)
		if current and currentHumanoid and os.clock() >= current.slowUntil - 0.05 then
			currentHumanoid.WalkSpeed = Tunnel.WALK_SPEED
		end
	end)
end

--[[
	Ускоритель на горке: короткий рывок вперёд. Не награда и не условие —
	просто весело, и на подъёме ребёнок не вязнет.
]]
function TunnelService.boost(player: Player, seconds: number, factor: number)
	local run = runs[player]
	local humanoid = humanoidOf(player)
	if not run or not humanoid then
		return
	end

	run.boostUntil = os.clock() + seconds
	humanoid.WalkSpeed = Tunnel.WALK_SPEED * factor

	task.delay(seconds, function()
		local current = runs[player]
		local currentHumanoid = humanoidOf(player)
		if
			current
			and currentHumanoid
			and os.clock() >= (current.boostUntil or 0) - 0.05
			and os.clock() >= current.slowUntil
		then
			currentHumanoid.WalkSpeed = Tunnel.WALK_SPEED
		end
	end)
end

function TunnelService.despawn(player: Player)
	local run = runs[player]
	if not run then
		return
	end
	runs[player] = nil

	if run.model.Parent then
		run.model:Destroy()
	end

	local character = player.Character
	if character and run.returnCFrame then
		Teleport.to(player, run.returnCFrame)
	end

	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
	end
end

--[[
	Забегов два: туннель мира букв и ворота с числами. Геометрия
	у них общая, отличаются только пропорции плана и то, что написано над проёмами,
	поэтому сервис обслуживает все три одинаково.
]]
local RUN_CHALLENGES: { [string]: boolean } = {
	tunnel_run = true,
	-- Ворота с числами: тот же коридор, только над проёмами числа (docs/16-MATH.md § 3.1)
	math_gates = true,
}

function TunnelService.isRun(challengeId: string): boolean
	return RUN_CHALLENGES[challengeId] == true
end

function TunnelService.start()
	for id in RUN_CHALLENGES do
		assert(
			Challenges.get(id),
			`TunnelService: испытание "{id}" не заведено в Config/Challenges`
		)
	end

	ChallengeService.onStarted(function(player: Player, spec: any)
		if TunnelService.isRun(spec.challengeId) then
			TunnelService.spawn(player, spec)
		end
	end)

	ChallengeService.onFinished(function(player: Player, spec: any)
		if TunnelService.isRun(spec.challengeId) then
			TunnelService.despawn(player)
		end
	end)

	ChallengeService.onAnswer(function(player: Player, spec: any, result: any)
		if not TunnelService.isRun(spec.challengeId) then
			return
		end

		-- Найденный секрет исчезает вместе с искрами: постамент остаётся — место находки.
		if result.secret then
			local run = runs[player]
			local tile = run and run.model:FindFirstChild("SecretTile")
			if tile then
				tile:Destroy()
			end
			return
		end

		if result.balance then
			onBalanceAnswer(player, result)
			return
		end

		if not result.correct and (result.cooldown or 0) > 0 then
			TunnelService.slow(player, result.cooldown, result.slowFactor or 0.5)
		end
	end)

	-- Клиент видит, что валун, молот или лава задели ребёнка (World/RunAttractions).
	RemoteDefs.event("RunHazard").OnServerEvent:Connect(function(player: Player)
		if not RateLimiter.allow(player, "RunHazard", RemoteDefs.RATE_LIMITS.RunHazard) then
			return
		end
		TunnelService.returnToCheckpoint(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		TunnelService.despawn(player)
		releasePlot(player)
	end)
end

return TunnelService
