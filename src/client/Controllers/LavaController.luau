--!nonstrict
--[[
	Клиентская часть «Пол — это лава!». Правила — Challenges/LavaFloor на сервере.

	Арена — плиты с буквами на поляне. Раунды идут по серверным часам
	от `params.startAt`: клиент сам знает, когда плиты перемешать, когда чужие
	начинают теплеть и когда пол загорается. Сервер в тот же миг смотрит,
	где стоит ребёнок, — ответ решает он, клиент только показывает.

	Не успел — лава подбрасывает вверх: это не наказание, а смешно, и видно
	сразу, без ожидания ответа сервера.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)

local AudioController = require(script.Parent.AudioController)
local SfxController = require(script.Parent.SfxController)
local HUD = require(script.Parent.Parent.UI.HUD)

local LavaController = {}

local FOLDER_NAME = "AlphabetFall_Lava"
local TILE_HEIGHT = 1
local CALM = Color3.fromRGB(250, 244, 230)
local WARM = Color3.fromRGB(255, 170, 90)
local LAVA = Color3.fromRGB(255, 90, 30)
local SAFE = Color3.fromRGB(255, 220, 110)
local BOUNCE = 75

local player = Players.LocalPlayer

local spec: any = nil
local folder: Folder? = nil
local origin = CFrame.new()
local tiles: { [number]: BasePart } = {}
local labels: { [number]: TextLabel } = {}
local shownRound = 0
local phase = ""
local bounced: { [number]: boolean } = {}
local heartbeat: RBXScriptConnection? = nil

local function timing(round: number): (number, number)
	local params = spec.params
	local cycle = params.seconds + params.lavaSeconds + params.restSeconds
	local start = params.intro + (round - 1) * cycle
	return start, start + params.seconds
end

local function tileCenter(index: number): Vector3
	local params = spec.params
	local half = params.grid * params.pitch / 2
	local column = (index - 1) % params.grid + 1
	local row = (index - 1) // params.grid + 1
	return Vector3.new(-half + (column - 0.5) * params.pitch, 0, -half + (row - 0.5) * params.pitch)
end

local function tileAt(localPosition: Vector3): number?
	local params = spec.params
	local half = params.grid * params.pitch / 2
	local x, z = localPosition.X + half, localPosition.Z + half
	if x < 0 or z < 0 or x >= half * 2 or z >= half * 2 then
		return nil
	end
	return math.floor(z / params.pitch) * params.grid + math.floor(x / params.pitch) + 1
end

local function makeTile(index: number): BasePart
	local params = spec.params
	local part = Instance.new("Part")
	part.Name = `LavaTile_{index}`
	part.Size = Vector3.new(params.tile, TILE_HEIGHT, params.tile)
	-- Поворот на четверть круга: верх надписи на верхней грани смотрит вперёд, от ребёнка.
	part.CFrame = origin
		* CFrame.new(tileCenter(index) + Vector3.new(0, TILE_HEIGHT / 2, 0))
		* CFrame.Angles(0, -math.pi / 2, 0)
	part.Color = CALM
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.Parent = folder

	-- Буква лежит на плите: её видно сверху и под углом, а стоящего на ней не закрывает.
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	surface.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(40, 30, 40)
	label.Text = ""
	label.Parent = surface
	labels[index] = label
	return part
end

-- Бортик арены: тёмный камень, по нему видно, где кончается пол, который загорится.
local function buildRim()
	local params = spec.params
	local size = params.grid * params.pitch + 3
	for _, side in { -1, 1 } do
		for _, axis in { "x", "z" } do
			local rim = Instance.new("Part")
			rim.Name = "LavaRim"
			rim.Anchored = true
			rim.CanCollide = false
			rim.Material = Enum.Material.Basalt
			rim.Color = Color3.fromRGB(80, 70, 75)
			if axis == "x" then
				rim.Size = Vector3.new(1.5, 1.4, size)
				rim.CFrame = origin * CFrame.new(side * (size / 2 - 0.75), 0.7, 0)
			else
				rim.Size = Vector3.new(size, 1.4, 1.5)
				rim.CFrame = origin * CFrame.new(0, 0.7, side * (size / 2 - 0.75))
			end
			rim.Parent = folder
		end
	end
end

local function showRound(round: number)
	local data = spec.params.rounds[round]
	if not data then
		return
	end
	shownRound = round
	for index, label in labels do
		local letter = Letters.get(data.tiles[index])
		label.Text = if letter then letter.glyph else ""
		label.TextColor3 = if letter then letter.color else Color3.new(1, 1, 1)
	end
end

local function isTarget(index: number): boolean
	local data = spec.params.rounds[shownRound]
	return data ~= nil and data.tiles[index] == spec.params.targetLetter
end

local function paint(kind: string, pulse: number)
	for index, part in tiles do
		local target = isTarget(index)
		if kind == "lava" then
			part.Color = if target then SAFE else LAVA
			part.Material = if target then Enum.Material.Neon else Enum.Material.CrackedLava
		elseif kind == "warn" then
			part.Material = Enum.Material.SmoothPlastic
			part.Color = if target then CALM else CALM:Lerp(WARM, pulse)
		elseif kind == "rest" then
			part.Material = Enum.Material.SmoothPlastic
			part.Color = Color3.fromRGB(215, 205, 195)
		else
			part.Material = Enum.Material.SmoothPlastic
			part.Color = CALM
		end
	end
	local hideLetters = kind == "rest"
	for _, label in labels do
		label.TextTransparency = if hideLetters then 1 else 0
		label.TextStrokeTransparency = if hideLetters then 1 else 0
	end
end

local function bounce()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	root.AssemblyLinearVelocity =
		Vector3.new(root.AssemblyLinearVelocity.X, BOUNCE, root.AssemblyLinearVelocity.Z)
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(LAVA, Color3.fromRGB(255, 200, 80))
	fire.Rate = 0
	fire.Speed = NumberRange.new(4, 8)
	fire.Lifetime = NumberRange.new(0.4, 0.7)
	fire.SpreadAngle = Vector2.new(60, 60)
	fire.Parent = root
	fire:Emit(25)
	task.delay(1, function()
		fire:Destroy()
	end)
	HUD.toast("Горячо! 🔥", 2)
end

local function step()
	if not spec then
		return
	end
	local params = spec.params
	local t = workspace:GetServerTimeNow() - (params.startAt or 0)
	local rounds = #params.rounds

	local round = 1
	for r = rounds, 1, -1 do
		if t >= timing(r) then
			round = r
			break
		end
	end
	local start, lavaAt = timing(round)

	if round ~= shownRound and t >= start - params.restSeconds then
		showRound(round)
	end

	local kind
	if t < start then
		kind = if round == 1 then "intro" else "rest"
	elseif t < lavaAt - params.warnSeconds then
		kind = "calm"
	elseif t < lavaAt then
		kind = "warn"
	elseif t < lavaAt + params.lavaSeconds then
		kind = "lava"
	else
		kind = "rest"
	end

	if kind ~= phase then
		phase = kind
		if kind == "calm" and t >= start then
			-- Новый раунд: голос снова называет букву.
			AudioController.speak(params.targetVO)
		elseif kind == "warn" then
			HUD.toast(`Скорее на букву {params.targetGlyph}!`, 2)
		end
	end
	local pulse = 0.5 + 0.5 * math.sin((t - (lavaAt - params.warnSeconds)) * math.pi * 3)
	paint(kind, pulse)

	-- Лава под ногами: подбросить сразу, не дожидаясь сервера.
	if kind == "lava" and not bounced[round] then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local position = origin:PointToObjectSpace(root.Position)
			local index = tileAt(position)
			if index and position.Y < 5 and not isTarget(index) then
				bounced[round] = true
				bounce()
			end
		end
	end
end

function LavaController.start(newSpec: any)
	LavaController.stop()
	spec = newSpec
	local stage = newSpec.params.stage
	origin = if typeof(stage) == "CFrame" then stage else CFrame.new(0, 0, 0)

	local container = Instance.new("Folder")
	container.Name = FOLDER_NAME
	container.Parent = workspace
	folder = container

	for index = 1, spec.params.grid * spec.params.grid do
		tiles[index] = makeTile(index)
	end
	buildRim()
	showRound(1)
	paint("calm", 0)

	HUD.showTarget(spec.params.targetGlyph, 0, spec.targetCount)
	HUD.toast(
		`Пол — это лава! Когда загорится, стой на букве {spec.params.targetGlyph}`,
		4
	)
	heartbeat = RunService.Heartbeat:Connect(step)
end

function LavaController.feedback(fb: any)
	if not spec then
		return
	end
	HUD.showTarget(spec.params.targetGlyph, fb.caught, fb.targetCount)
	if fb.correct then
		SfxController.play("reward")
		return
	end
	-- «Это буква П. А нам нужна М» — ошибка становится подсказкой.
	local tapped = fb.tappedLetterId and Letters.get(fb.tappedLetterId)
	if tapped then
		task.delay(0.6, function()
			AudioController.speak(tapped.vo.name)
		end)
	end
end

function LavaController.stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	tiles = {}
	labels = {}
	shownRound = 0
	phase = ""
	bounced = {}
	spec = nil
end

return LavaController
