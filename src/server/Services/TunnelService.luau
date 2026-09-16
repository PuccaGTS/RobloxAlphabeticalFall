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
local DecorShapes = require(script.Parent.Parent.World.DecorShapes)

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
local function laneHoles(obstacles: { any }): { { { from: number, to: number } } }
	local holes = {}
	for lane = 1, Tunnel.LANE_COUNT do
		holes[lane] = {}
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
local CURVE_CHUNK = 4

local function pieces(path, from: number, to: number, chunk: number, piece: (number, number, boolean) -> ())
	local cuts = { from, to }
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

local FLOOR_COLOR = Color3.fromRGB(205, 195, 175)
local FLOOR_ZONE_COLOR = Color3.fromRGB(235, 215, 160)

local function buildFloor(model: Model, path, length: number, obstacles: { any })
	local holes = laneHoles(obstacles)

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
					FLOOR_COLOR,
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
local RAIL_COLORS = {
	Color3.fromRGB(120, 180, 235),
	Color3.fromRGB(245, 175, 110),
	Color3.fromRGB(150, 210, 140),
	Color3.fromRGB(215, 160, 225),
}

local function buildCorridor(model: Model, path, length: number, obstacles: { any })
	local half = Tunnel.WIDTH / 2

	buildFloor(model, path, length, obstacles)

	for _, side in { -1, 1 } do
		local x = side * (half + Tunnel.WALL_THICKNESS / 2)

		pieces(path, 0, length, CURVE_CHUNK + 1, function(mid: number, size: number, curved: boolean)
			local color = RAIL_COLORS[math.floor(mid / 60) % #RAIL_COLORS + 1]
			local rail = build(
				`Rail_{side}_{math.floor(mid)}`,
				Vector3.new(Tunnel.WALL_THICKNESS, RAIL_HEIGHT, size + (if curved then 0.6 else 0)),
				path.frame(mid) * CFrame.new(x, RAIL_HEIGHT / 2, 0),
				color,
				model
			)
			rail.Material = Enum.Material.SmoothPlastic
		end)

		pieces(path, 0, length, CURVE_CHUNK * 2, function(mid: number, size: number, curved: boolean)
			local guard = build(
				`Guard_{side}_{math.floor(mid)}`,
				Vector3.new(Tunnel.WALL_THICKNESS, Tunnel.HEIGHT, size + (if curved then 1.5 else 0)),
				path.flat(mid) * CFrame.new(x, Tunnel.HEIGHT / 2, 0),
				Color3.fromRGB(255, 255, 255),
				model
			)
			guard.Transparency = 1
		end)
	end

	-- Разметка дорожек на прямых: ребёнку нужно видеть, что дорожек ровно три.
	for lane = 1, Tunnel.LANE_COUNT - 1 do
		local x = Tunnel.laneOffset(lane) + Tunnel.LANE_WIDTH / 2
		pieces(path, 0, length, CURVE_CHUNK, function(mid: number, size: number, curved: boolean)
			if curved then
				return
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

local function buildGate(model: Model, origin: CFrame, gate: any, player: Player)
	local openLanes: { [number]: any } = {}
	for _, opening in gate.openings do
		openLanes[opening.lane] = opening
	end

	buildGateHeader(model, origin, gate)

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
			-- Закрытая дорожка: сплошная стена, объехать выбор нельзя
			build(
				`GateWall_{gate.index}_{lane}`,
				Vector3.new(Tunnel.LANE_WIDTH, Tunnel.HEIGHT, 1.5),
				at * CFrame.new(0, Tunnel.HEIGHT / 2, 0),
				Color3.fromRGB(95, 130, 180),
				model
			)
		end
	end
end

--[[
	Ряды букв на дорожке (docs/14-TUNNEL-MODE.md § 4.2): плитки с буквами
	по пояс ребёнку. Касание засчитывается только у буквы своего отрезка —
	у отвлекающей триггера нет, пробежать сквозь неё ничего не стоит.

	Буква на плитке своего размера и не поверх всего, в отличие от букв ворот:
	рядов на забеге много, и висящие сквозь стены буквы превратили бы туннель
	в кашу из значков.
]]
local function buildRows(model: Model, origin: CFrame, rows: { any }, player: Player, resumeFrom: number)
	for _, row in rows do
		-- Ряды пройденных до выхода отрезков не строим: их «монетки» уже взяты или упущены.
		if row.segment > resumeFrom then
			for slot, item in row.items do
				--[[
					Плитка светлая, а цвет буквы живёт в рамке и в самой букве.
					Раньше плитка была целиком цвета буквы, а надпись висела
					билбордом в один студ: на бегу это читалось как «синий
					и красный квадратики», без единой буквы. Буква обязана
					быть видна раньше, чем ребёнок до плитки добежал.
				]]
				local frame = build(
					`CollectFrame_{row.index}_{slot}`,
					Vector3.new(Tunnel.COLLECT_SIZE + 0.5, Tunnel.COLLECT_SIZE + 0.5, 0.3),
					origin * CFrame.new(Tunnel.laneOffset(item.lane), Tunnel.COLLECT_HEIGHT, -row.z),
					item.color,
					model
				)
				frame.CanCollide = false
				frame.Material = Enum.Material.Neon

				local tile = build(
					`Collect_{row.index}_{slot}`,
					Vector3.new(Tunnel.COLLECT_SIZE, Tunnel.COLLECT_SIZE, 0.5),
					origin * CFrame.new(Tunnel.laneOffset(item.lane), Tunnel.COLLECT_HEIGHT, -row.z),
					Color3.fromRGB(252, 250, 245),
					model
				)
				tile.CanCollide = false

				local billboard = Instance.new("BillboardGui")
				billboard.Name = "Glyph"
				-- Размер в пикселях, как у букв над воротами: в студах билборд
				-- получался с ноготь и на бегу не читался вовсе.
				billboard.Size = UDim2.fromOffset(150, 150)
				billboard.AlwaysOnTop = true
				billboard.LightInfluence = 0
				billboard.MaxDistance = 220
				billboard.Parent = tile

				local label = Instance.new("TextLabel")
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundTransparency = 1
				label.Text = item.glyph
				label.TextColor3 = item.color
				label.TextStrokeColor3 = Color3.fromRGB(30, 26, 45)
				label.TextStrokeTransparency = 0
				label.TextScaled = true
				label.Font = Enum.Font.FredokaOne
				label.Parent = billboard

				if item.isTarget then
					tile.Touched:Connect(function(hit: BasePart)
						local character = hit.Parent
						if not character or Players:GetPlayerFromCharacter(character) ~= player then
							return
						end
						ChallengeService.submitAction(
							player,
							{ kind = "collect", row = row.index, slot = slot }
						)
					end)
				end
			end
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

	local tile = build(
		"SecretTile",
		Vector3.new(Tunnel.SECRET_SIZE, Tunnel.SECRET_SIZE, 0.6),
		origin * CFrame.new(x, Tunnel.SECRET_PEDESTAL.Y + Tunnel.SECRET_LIFT, -secret.z),
		SECRET_GOLD,
		model
	)
	tile.CanCollide = false
	tile.Material = Enum.Material.Neon

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Glyph"
	billboard.Size = UDim2.fromScale(1, 1)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 140
	billboard.Parent = tile

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = secret.glyph
	label.TextColor3 = Color3.fromRGB(120, 70, 10)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard

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

local function buildObstacles(model: Model, origin: CFrame, obstacles: { any })
	for index, obstacle in obstacles or {} do
		local builder = OBSTACLE_BUILDERS[obstacle.kind]
		if builder then
			builder(model, origin, obstacle, index)
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

	local flag = build(
		`CheckpointFlag_{checkpoint.index}`,
		Vector3.new(Tunnel.WIDTH, 1, 1),
		at * CFrame.new(0, Tunnel.HEIGHT * 0.5, 0),
		if passed then CHECKPOINT_LIT else CHECKPOINT_COLD,
		model
	)
	flag.CanCollide = false
	if passed then
		flag.Material = Enum.Material.Neon
	end

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
		flag.Color = CHECKPOINT_LIT
		flag.Material = Enum.Material.Neon
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
local VALLEY_DROP = Tunnel.FALL_DEPTH + 10 -- ниже самой глубокой ямки трассы
local VALLEY_WIDTH = Tunnel.WIDTH + 140
local VALLEY_CHUNK = 40

local function buildSoftBottom(model: Model, path, length: number, player: Player)
	local function onTouch(hit: BasePart)
		local character = hit.Parent
		if not character or Players:GetPlayerFromCharacter(character) ~= player then
			return
		end

		local run = runs[player]
		if not run or os.clock() < run.fallingUntil then
			return
		end
		-- Пока идёт возврат, повторные касания дна игнорируем: иначе ребёнка
		-- телепортирует несколько раз подряд от одного падения.
		run.fallingUntil = os.clock() + 1

		--[[
			Звук падения мягкий и водяной: внизу трава, а не смерть, и звук
			обязан подтверждать это, а не пугать.
		]]
		RemoteDefs.event("PlaySfx"):FireClient(player, "fall")

		character:PivotTo(run.origin * CFrame.new(0, 4, -run.checkpointZ))
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
local SCENERY = { "tree_round", "tree_pine", "bush_round", "tree_round", "rock_small", "tree_pine" }
local SCENERY_STEP = 34

local function buildScenery(model: Model, path, length: number, seed: number)
	local random = Random.new(seed + 3571)
	local baseY = path.origin.Position.Y - VALLEY_DROP + 1
	local z = 10
	local slot = 0
	while z < length do
		for _, side in { -1, 1 } do
			slot += 1
			local id = SCENERY[random:NextInteger(1, #SCENERY)]
			local tree = DecorShapes.build({ id = id })
			if tree then
				local lateral = side * (Tunnel.WIDTH / 2 + 12 + random:NextNumber() * 30)
				local spot = path.flat(math.min(z + random:NextNumber() * 10, length))
					* CFrame.new(lateral, 0, 0)
				tree.Name = `Scenery_{slot}`
				tree.Parent = model
				if id ~= "rock_small" and id ~= "bush_round" then
					tree:ScaleTo(1.6 + random:NextNumber() * 0.6)
				end
				tree:PivotTo(
					CFrame.new(spot.Position.X, baseY, spot.Position.Z)
						* CFrame.Angles(0, random:NextNumber() * 6.28, 0)
				)
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

local function buildFinish(model: Model, origin: CFrame, length: number, player: Player)
	local at = origin * CFrame.new(0, 0, -(length - 6))

	build(
		"FinishArch",
		Vector3.new(Tunnel.WIDTH, 1.5, 1.5),
		at * CFrame.new(0, Tunnel.HEIGHT * 0.6, 0),
		Color3.fromRGB(255, 214, 102),
		model
	)

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

	-- Стена за финишем: чтобы не убежать в пустоту за краем туннеля
	build(
		"EndWall",
		Vector3.new(Tunnel.WIDTH, Tunnel.HEIGHT, 2),
		origin * CFrame.new(0, Tunnel.HEIGHT / 2, -length),
		Color3.fromRGB(120, 165, 220),
		model
	)
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

	local model = Instance.new("Model")
	model.Name = `Tunnel_{player.UserId}`
	model.Parent = ensureContainer()

	buildCorridor(model, origin, length, spec.params.obstacles)
	for _, gate in spec.params.gates do
		buildGate(model, origin, gate, player)
	end
	buildObstacles(model, origin, spec.params.obstacles)
	buildRows(model, origin, spec.params.rows or {}, player, spec.params.resumeFrom or 0)
	buildSecret(model, origin, spec.params.secret, player, spec.params.resumeFrom or 0)
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
	buildSoftBottom(model, origin, length, player)
	buildScenery(model, origin, length, spec.seed or 0)
	buildZoneDecor(model, origin, player)

	if character then
		character:PivotTo(origin * CFrame.new(0, 4, -math.max(startZ, 4)))
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
		character:PivotTo(run.returnCFrame)
	end

	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
	end
end

--[[
	Забегов три: учебный туннель, полоса препятствий и ворота с числами. Геометрия
	у них общая, отличаются только пропорции плана и то, что написано над проёмами,
	поэтому сервис обслуживает все три одинаково.
]]
local RUN_CHALLENGES: { [string]: boolean } = {
	tunnel_run = true,
	obstacle_course = true,
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

		-- Подобранная буква исчезает: второй раз её не взять, и ребёнок видит, что взял.
		if result.collect then
			local run = runs[player]
			local tile = run and run.model:FindFirstChild(`Collect_{result.row}_{result.slot}`)
			if tile then
				tile:Destroy()
			end
			return
		end

		if not result.correct and (result.cooldown or 0) > 0 then
			TunnelService.slow(player, result.cooldown, result.slowFactor or 0.5)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		TunnelService.despawn(player)
		releasePlot(player)
	end)
end

return TunnelService
