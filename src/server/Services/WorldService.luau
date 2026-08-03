--!nonstrict
--[[
	Хаб «Площадь Башни».

	Строится кодом, а не руками в Studio: пока нет арта, геометрию проще держать
	в репозитории, чем в .rbxl, который не читается в диффе и конфликтует при слиянии.
	Когда появятся модели, этот сервис заменится на загрузку готовой сцены.

	Башня прогресса здесь НЕ строится: она у каждого игрока своя (у одного буква
	освоена, у другого нет), а один общий объект в мире так не умеет.
	Её собирает клиент — src/client/Controllers/TowerController.luau.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Islands = require(Shared.Config.Islands)
local Letters = require(Shared.Config.Letters)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local ProgressService = require(script.Parent.ProgressService)
local ChallengeService = require(script.Parent.ChallengeService)

local WorldService = {}

local HUB_RADIUS = 52
local PAD_DISTANCE = 34
local TOUCH_DEBOUNCE = 2

--[[
	Все острова ведут в «Буквопад», а «Мост слогов» стоит отдельным падом и открыт
	с самого начала. Причина не косметическая: для статуса «изученная» буква обязана
	быть успешно пройдена в ДВУХ разных типах испытаний (docs/02-LEARNING.md § 9).
	Если бы мост открывался только на втором острове, а второй остров требовал
	изученных букв первого, прогресс упирался бы в тупик на четвёртой минуте.
]]
local ISLAND_CHALLENGE = {
	[1] = "letter_rain",
	[2] = "letter_rain",
	[3] = "letter_rain",
}

local lastTouch: { [Player]: number } = {}

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

--[[
	Подпись над объектом. Размер в ПИКСЕЛЯХ: у BillboardGui доля Scale считается
	от размера детали, и на платформе 12 студов подпись раздувается до нечитаемой.
]]
local function caption(parent: BasePart, text: string, height: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Caption"
	billboard.Size = UDim2.fromOffset(280, 90)
	billboard.StudsOffset = Vector3.new(0, height, 0)
	billboard.LightInfluence = 0
	-- Близко — чтобы подписи всех падов и Башни не наслаивались друг на друга
	-- в одну кашу, как только отойдёшь на середину площади.
	billboard.MaxDistance = 55
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
	Запуск и по подсказке, и по касанию.

	Дошкольник не будет искать клавишу E и не всегда попадёт по кнопке подсказки —
	он просто придёт и встанет на пад. Касание обязано работать как основной способ.
]]
local function makeActivator(pad: BasePart, actionText: string, objectText: string, action: (Player) -> ())
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad
	prompt.Triggered:Connect(action)

	--[[
		Касание срабатывает много раз в секунду, пока ребёнок стоит на паде.
		Поэтому реагируем только на ВХОД на пад: пока он с него не сойдёт,
		повторные касания игнорируются.
	]]
	local standing: { [Player]: boolean } = {}

	pad.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or standing[player] then
			return
		end

		local now = os.clock()
		if lastTouch[player] and now - lastTouch[player] < TOUCH_DEBOUNCE then
			return
		end

		standing[player] = true
		lastTouch[player] = now
		action(player)
	end)

	pad.TouchEnded:Connect(function(hit: BasePart)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			standing[player] = nil
		end
	end)
end

local function buildIslandPad(hub: Folder, island, slot: number, slots: number)
	-- Пады расставлены по кругу с равным шагом. Мост и магазин занимают свои слоты,
	-- иначе два пада встают в одну точку и подсказки накладываются друг на друга.
	local angle = (slot - 1) / slots * math.pi * 2
	local position = Vector3.new(math.cos(angle) * PAD_DISTANCE, 1.5, math.sin(angle) * PAD_DISTANCE)

	local pad = part(
		`Portal_{island.index}`,
		Vector3.new(14, 1, 14),
		CFrame.new(position),
		Color3.fromRGB(120, 170, 230),
		hub
	)
	caption(pad, `{island.index}. {island.title}`, 5)

	-- Арка над падом, чтобы портал читался как вход, а не как плитка на полу
	part(
		`PortalArch_{island.index}`,
		Vector3.new(14, 1.2, 1.2),
		CFrame.new(position + Vector3.new(0, 9, 0)),
		Color3.fromRGB(90, 140, 210),
		hub
	)
	part(
		`PortalLeft_{island.index}`,
		Vector3.new(1.2, 9, 1.2),
		CFrame.new(position + Vector3.new(-6.4, 4.5, 0)),
		Color3.fromRGB(90, 140, 210),
		hub
	)
	part(
		`PortalRight_{island.index}`,
		Vector3.new(1.2, 9, 1.2),
		CFrame.new(position + Vector3.new(6.4, 4.5, 0)),
		Color3.fromRGB(90, 140, 210),
		hub
	)

	local challengeId = ISLAND_CHALLENGE[island.index] or "letter_rain"

	makeActivator(pad, "Играть", island.title, function(player: Player)
		local profile = ProfileService.get(player)
		if not profile then
			return
		end

		local state = profile.islands[island.index]
		if not state or not state.unlocked then
			-- Закрытый остров не отказывает молча: говорим, что нужно ещё поучиться.
			RemoteDefs.event("OpenUI"):FireClient(player, "locked_island")
			return
		end

		ChallengeService.startFor(player, challengeId)
	end)
end

-- Декор: цветные клумбы и парящие буквы. Мир должен выглядеть местом, а не полигоном.
local function buildDecor(hub: Folder)
	local palette = {
		Color3.fromRGB(240, 130, 130),
		Color3.fromRGB(250, 200, 110),
		Color3.fromRGB(140, 210, 150),
		Color3.fromRGB(140, 180, 240),
		Color3.fromRGB(200, 150, 230),
	}

	for i = 1, 12 do
		local angle = (i - 1) / 12 * math.pi * 2
		local radius = HUB_RADIUS - 6
		local position = Vector3.new(math.cos(angle) * radius, 1.6, math.sin(angle) * radius)

		part(
			`Bush_{i}`,
			Vector3.new(5, 2.2, 5),
			CFrame.new(position) * CFrame.Angles(0, angle, 0),
			palette[(i - 1) % #palette + 1],
			hub
		)
	end

	-- Парящие буквы вокруг Башни: тема мира читается с первого взгляда
	local ordered = Letters.ordered()
	for i, letterId in ordered do
		local letter = Letters.expect(letterId)
		local angle = (i - 1) / #ordered * math.pi * 2
		local radius = 20
		local position = Vector3.new(math.cos(angle) * radius, 14 + (i % 3) * 3, math.sin(angle) * radius)

		local floater = part(
			`Floater_{letterId}`,
			Vector3.new(2.6, 2.6, 2.6),
			CFrame.new(position) * CFrame.Angles(0, -angle, 0),
			letter.color,
			hub
		)
		floater.CanCollide = false
		floater.Material = Enum.Material.Neon
		floater.Transparency = 0.25
	end
end

local function styleLighting()
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(120, 120, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 170)
	Lighting.ClockTime = 14

	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.Parent = Lighting
	end

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.28
		atmosphere.Haze = 1.2
		atmosphere.Color = Color3.fromRGB(210, 225, 245)
		atmosphere.Parent = Lighting
	end
end

function WorldService.build()
	local existing = workspace:FindFirstChild("Hub")
	if existing then
		existing:Destroy()
	end

	styleLighting()

	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = workspace

	part(
		"Ground",
		Vector3.new(HUB_RADIUS * 2, 2, HUB_RADIUS * 2),
		CFrame.new(0, 0, 0),
		Color3.fromRGB(150, 205, 140),
		hub
	)
	part("Plaza", Vector3.new(46, 2, 46), CFrame.new(0, 0.6, 0), Color3.fromRGB(235, 225, 200), hub)
	part("TowerBase", Vector3.new(16, 2, 16), CFrame.new(0, 2, 0), Color3.fromRGB(250, 240, 215), hub)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 2.2, 22)
	spawn.Anchored = true
	spawn.Color = Color3.fromRGB(255, 214, 102)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Parent = hub

	local slots = Islands.count() + 2 -- острова + магазин + мост
	local slotIndex = 0

	for _, island in Islands.all do
		slotIndex += 1
		buildIslandPad(hub, island, slotIndex, slots)
	end

	slotIndex += 1
	local shopAngle = (slotIndex - 1) / slots * math.pi * 2
	local shopPad = part(
		"ShopPad",
		Vector3.new(12, 1, 12),
		CFrame.new(math.cos(shopAngle) * PAD_DISTANCE, 1.5, math.sin(shopAngle) * PAD_DISTANCE),
		Color3.fromRGB(255, 190, 120),
		hub
	)
	caption(shopPad, "🛍 Магазин", 5)
	makeActivator(shopPad, "Открыть", "Магазин", function(player: Player)
		RemoteDefs.event("OpenUI"):FireClient(player, "shop")
	end)

	slotIndex += 1
	local bridgeAngle = (slotIndex - 1) / slots * math.pi * 2
	local bridgePad = part(
		"BridgePad",
		Vector3.new(12, 1, 12),
		CFrame.new(math.cos(bridgeAngle) * PAD_DISTANCE, 1.5, math.sin(bridgeAngle) * PAD_DISTANCE),
		Color3.fromRGB(190, 150, 230),
		hub
	)
	caption(bridgePad, "🌉 Мост слогов", 5)
	makeActivator(bridgePad, "Строить", "Мост слогов", function(player: Player)
		ChallengeService.startFor(player, "syllable_bridge")
	end)

	-- Вход в туннель. Временно стоит здесь: настоящий вход — два портала миров
	-- на новом спавне (docs/14-TUNNEL-MODE.md § 3.1), они ещё не построены.
	local tunnelPad = part(
		"TunnelPad",
		Vector3.new(12, 1, 12),
		CFrame.new(0, 1.5, -PAD_DISTANCE),
		Color3.fromRGB(140, 220, 200),
		hub
	)
	caption(tunnelPad, "🌀 Азбучный туннель", 5)
	makeActivator(tunnelPad, "Бежать", "Азбучный туннель", function(player: Player)
		ChallengeService.startFor(player, "tunnel_run")
	end)

	buildDecor(hub)

	--[[
		Чужие точки появления (например, из шаблона Baseplate) выключаем: иначе
		ребёнка выбрасывает мимо площади, а то и внутрь подиума Башни.
	]]
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") and instance ~= spawn then
			instance.Enabled = false
		end
	end

	print(`[World] хаб построен: островов {Islands.count()}, падов {slots}`)
end

function WorldService.start()
	WorldService.build()

	Players.PlayerRemoving:Connect(function(player: Player)
		lastTouch[player] = nil
	end)

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
