--!nonstrict
--[[
	Геометрия туннеля: строит забег по плану от Challenges/TunnelRun,
	телепортирует игрока внутрь и обратно, ловит касания ворот и финиша.

	Туннель у каждого игрока СВОЙ и стоит в отдельном месте карты: иначе двое детей
	бегали бы по одному коридору с разными заданиями и мешали друг другу.

	Сервер здесь — источник истины целиком: ворота это физические триггеры на сервере,
	клиент о выборе даже не сообщает, он просто бежит.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Tunnel = require(Shared.Config.Tunnel)

local ChallengeService = require(script.Parent.ChallengeService)

local TunnelService = {}

local FOLDER_NAME = "Tunnels"

type Run = {
	model: Model,
	origin: CFrame,
	returnCFrame: CFrame?,
	spec: any,
	slowUntil: number,
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
	Буква над проёмом. Билборд создаётся на сервере и реплицируется всем —
	для статичной надписи это дешевле, чем гонять данные на клиент и рисовать там.
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

local function buildCorridor(model: Model, origin: CFrame, length: number)
	local half = Tunnel.WIDTH / 2

	build(
		"Floor",
		Vector3.new(Tunnel.WIDTH, 2, length),
		origin * CFrame.new(0, -1, -length / 2),
		Color3.fromRGB(205, 195, 175),
		model
	)

	for _, side in { -1, 1 } do
		build(
			`Wall_{side}`,
			Vector3.new(Tunnel.WALL_THICKNESS, Tunnel.HEIGHT, length),
			origin * CFrame.new(side * (half + Tunnel.WALL_THICKNESS / 2), Tunnel.HEIGHT / 2, -length / 2),
			Color3.fromRGB(120, 165, 220),
			model
		)
	end

	-- Разметка дорожек: ребёнку нужно видеть, что дорожек ровно три.
	for lane = 1, Tunnel.LANE_COUNT - 1 do
		local x = Tunnel.laneOffset(lane) + Tunnel.LANE_WIDTH / 2
		local stripe = build(
			`LaneStripe_{lane}`,
			Vector3.new(0.4, 0.1, length),
			origin * CFrame.new(x, 0.05, -length / 2),
			Color3.fromRGB(235, 230, 215),
			model
		)
		stripe.CanCollide = false
	end
end

local function buildGate(model: Model, origin: CFrame, gate: any, player: Player)
	local openLanes: { [number]: any } = {}
	for _, opening in gate.openings do
		openLanes[opening.lane] = opening
	end

	for lane = 1, Tunnel.LANE_COUNT do
		local x = Tunnel.laneOffset(lane)
		local opening = openLanes[lane]
		local at = origin * CFrame.new(x, 0, -gate.z)

		if opening then
			-- Проём: рамка по краям и невидимый триггер посередине
			local letter = Letters.expect(opening.letterId)

			local frame = build(
				`GateFrame_{gate.index}_{lane}`,
				Vector3.new(Tunnel.LANE_WIDTH, 1.2, 1.2),
				at * CFrame.new(0, Tunnel.HEIGHT * 0.55, 0),
				letter.color,
				model
			)
			frame.CanCollide = false
			attachGlyph(frame, letter.glyph, Color3.fromRGB(255, 255, 255))

			local trigger = build(
				`GateTrigger_{gate.index}_{lane}`,
				Vector3.new(Tunnel.LANE_WIDTH - 0.5, Tunnel.HEIGHT * 0.5, 1.5),
				at * CFrame.new(0, Tunnel.HEIGHT * 0.25, 0),
				letter.color,
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

local function buildBarriers(model: Model, origin: CFrame, barriers: { any })
	for index, barrier in barriers do
		local part = build(
			`Barrier_{index}`,
			Vector3.new(Tunnel.LANE_WIDTH - 1, 2.5, 1.2),
			origin * CFrame.new(Tunnel.laneOffset(barrier.lane), 1.25, -barrier.z),
			Color3.fromRGB(240, 170, 90),
			model
		)
		part.Material = Enum.Material.Wood
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
	local origin = CFrame.new(Tunnel.PLOT_ORIGIN + Vector3.new(index * Tunnel.PLOT_SPACING, 0, 0))
	local length = spec.params.length

	local model = Instance.new("Model")
	model.Name = `Tunnel_{player.UserId}`
	model.Parent = ensureContainer()

	buildCorridor(model, origin, length)
	for _, gate in spec.params.gates do
		buildGate(model, origin, gate, player)
	end
	buildBarriers(model, origin, spec.params.barriers)
	buildFinish(model, origin, length, player)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	runs[player] = {
		model = model,
		origin = origin,
		returnCFrame = if root then root.CFrame else nil,
		spec = spec,
		slowUntil = 0,
	}

	if character then
		character:PivotTo(origin * CFrame.new(0, 4, -4))
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

function TunnelService.start()
	ChallengeService.onStarted(function(player: Player, spec: any)
		if spec.challengeId == "tunnel_run" then
			TunnelService.spawn(player, spec)
		end
	end)

	ChallengeService.onFinished(function(player: Player, spec: any)
		if spec.challengeId == "tunnel_run" then
			TunnelService.despawn(player)
		end
	end)

	ChallengeService.onAnswer(function(player: Player, spec: any, result: any)
		if spec.challengeId == "tunnel_run" and not result.correct and (result.cooldown or 0) > 0 then
			TunnelService.slow(player, result.cooldown, result.slowFactor or 0.5)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		TunnelService.despawn(player)
		releasePlot(player)
	end)
end

return TunnelService
