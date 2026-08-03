--!nonstrict
--[[
	Хаб «Площадь Башни» — серый ящик.

	Строится кодом, а не руками в Studio: пока нет арта, геометрию проще держать
	в репозитории, чем в .rbxl, который не читается в диффе и конфликтует при слиянии.
	Когда появятся модели, этот сервис заменится на загрузку готовой сцены.

	Башня прогресса здесь НЕ строится: она у каждого игрока своя (у одного буква
	освоена, у другого нет), а один общий объект в мире так не умеет.
	Её собирает клиент — src/client/Controllers/TowerController.luau.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Islands = require(Shared.Config.Islands)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local ProgressService = require(script.Parent.ProgressService)
local ChallengeService = require(script.Parent.ChallengeService)

local WorldService = {}

local HUB_RADIUS = 46
local PAD_DISTANCE = 30

local ISLAND_CHALLENGE = {
	[1] = "letter_rain",
	[2] = "syllable_bridge",
	[3] = "letter_rain",
}

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

local function label(parent: BasePart, text: string, height: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(8, 3)
	billboard.StudsOffset = Vector3.new(0, height, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 120
	billboard.Parent = parent

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = text
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextStrokeTransparency = 0.3
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.Parent = billboard
end

local function prompt(parent: BasePart, actionText: string, objectText: string): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = actionText
	p.ObjectText = objectText
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

local function buildIslandPad(hub: Folder, island, index: number, total: number)
	local angle = (index - 1) / total * math.pi * 2
	local position = Vector3.new(math.cos(angle) * PAD_DISTANCE, 1.5, math.sin(angle) * PAD_DISTANCE)

	local pad = part(
		`Portal_{island.index}`,
		Vector3.new(12, 1, 12),
		CFrame.new(position),
		Color3.fromRGB(120, 170, 230),
		hub
	)
	label(pad, `{island.index}. {island.title}`, 4)

	local challengeId = ISLAND_CHALLENGE[island.index] or "letter_rain"
	local activate = prompt(pad, "Играть", island.title)

	activate.Triggered:Connect(function(player: Player)
		local profile = ProfileService.get(player)
		if not profile then
			return
		end

		local state = profile.islands[island.index]
		if not state or not state.unlocked then
			-- Закрытый остров не наказываем отказом молча: говорим, что нужно ещё поучиться.
			RemoteDefs.event("PlayVO"):FireClient(player, "hint_01", true)
			return
		end

		ChallengeService.startFor(player, challengeId)
	end)
end

function WorldService.build()
	local existing = workspace:FindFirstChild("Hub")
	if existing then
		existing:Destroy()
	end

	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = workspace

	-- Площадь
	part(
		"Ground",
		Vector3.new(HUB_RADIUS * 2, 2, HUB_RADIUS * 2),
		CFrame.new(0, 0, 0),
		Color3.fromRGB(150, 200, 150),
		hub
	)

	-- Подиум Башни: сама Башня достраивается на клиенте
	part("TowerBase", Vector3.new(14, 2, 14), CFrame.new(0, 2, 0), Color3.fromRGB(230, 220, 200), hub)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 1.5, 20)
	spawn.Anchored = true
	spawn.Color = Color3.fromRGB(255, 214, 102)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Parent = hub

	-- Магазин
	local shopPad = part(
		"ShopPad",
		Vector3.new(10, 1, 10),
		CFrame.new(-PAD_DISTANCE, 1.5, 0),
		Color3.fromRGB(255, 190, 120),
		hub
	)
	label(shopPad, "🛍 Магазин", 4)
	prompt(shopPad, "Открыть", "Магазин").Triggered:Connect(function(player: Player)
		RemoteDefs.event("OpenUI"):FireClient(player, "shop")
	end)

	for index, island in Islands.all do
		buildIslandPad(hub, island, index, Islands.count() + 1)
	end

	print(`[World] хаб построен: островов {Islands.count()}`)
end

function WorldService.start()
	WorldService.build()

	-- Пересчитываем открытые острова при входе: буквы могли быть освоены в прошлой сессии.
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			local profile = ProfileService.waitFor(player, 20)
			if profile then
				ProfileService.update(player, function(p)
					ProgressService.refreshIslands(p)
				end)
			end
		end)
	end)
end

return WorldService
