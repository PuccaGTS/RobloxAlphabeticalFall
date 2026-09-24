--!strict
--[[
	Вечер в парке (Config/Evening): свет, облака и звёзды по кругу серверных
	часов, а когда стемнело — фонари, окна домов и светлячки.

	Всё на клиенте. Сервер ставит дневной свет один раз и больше его не трогает,
	поэтому то, что клиент меняет в Lighting, остаётся у него. Вне парка — на
	поляне занятия, в забеге — свет возвращается к дневному за секунду: буквы
	должны быть видны одинаково в любое время.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Evening = require(Shared.Config.Evening)
local Decor = require(Shared.Config.Decor)
local Playground = require(Shared.Config.Playground)

local EveningController = {}

local DAY = Evening.LOOKS.day
local UPDATE_SECONDS = 0.1 -- свет меняется медленно: десяти раз в секунду хватает с запасом
local EXTRAS_SECONDS = 1 -- фонари, окна и светлячки

local shift = 0 -- сдвиг круга из панели разработчика: вечер приходит сразу
local blend = 0 -- 0 — дневной свет (не в парке), 1 — свет круга
local current: Evening.Look = DAY
local night = false

local lampLights: { [Instance]: PointLight } = {}
local windows: { [BasePart]: { material: Enum.Material, color: Color3 } } = {}
local fireflies: { ParticleEmitter } = {}

-- Секунда круга: общая для всех, со сдвигом разработчика. Метка EveningAt — для стенда.
function EveningController.now(): number
	local forced = workspace:GetAttribute("EveningAt")
	if typeof(forced) == "number" then
		return forced
	end
	return (workspace:GetServerTimeNow() + shift) % Evening.CYCLE
end

-- Перейти в секунду круга at: так кнопка в панели разработчика зовёт закат.
function EveningController.skipTo(at: number)
	shift = (at - workspace:GetServerTimeNow()) % Evening.CYCLE
end

function EveningController.glow(): number
	return current.glow
end

-- Стемнело: горят фонари и окна, поют сверчки, играет колыбельная.
function EveningController.isNight(): boolean
	return night
end

local function apply(look: Evening.Look)
	Lighting.ClockTime = look.clock
	Lighting.Brightness = look.brightness
	Lighting.Ambient = look.ambient
	Lighting.OutdoorAmbient = look.outdoor
	Lighting.ExposureCompensation = look.exposure
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Color = look.air
		atmosphere.Decay = look.decay
		atmosphere.Haze = look.haze
		atmosphere.Glare = look.glare
	end
	local tint = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if tint then
		tint.TintColor = look.tint
	end
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds.Color = look.clouds
	end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.CelestialBodiesShown = look.sun > 0.5
		sky.StarCount = if look.glow >= Evening.NIGHT_FROM then 3000 else 0
	end
end

local function same(a: Evening.Look, b: Evening.Look): boolean
	return math.abs(a.clock - b.clock) < 0.001
		and math.abs(a.glow - b.glow) < 0.001
		and math.abs(a.brightness - b.brightness) < 0.001
		and a.air == b.air
end

-- ===== Фонари ==========================================================================

-- Плафон фонаря: у модели из Store — «Lamp Glass», у эскиза — «Bulb».
local function lampHead(lamp: Instance): BasePart?
	local head = lamp:FindFirstChild("Lamp Glass", true) or lamp:FindFirstChild("Bulb", true)
	return if head and head:IsA("BasePart") then head else nil
end

--[[
	Настоящий свет — только у нескольких ближайших фонарей: световые пятна на
	дорожке и есть вечер, но два десятка источников дешёвый планшет не тянет.
]]
local function updateLamps(root: Vector3?)
	local wanted: { [Instance]: boolean } = {}
	if night and root then
		local near = {}
		for _, lamp in CollectionService:GetTagged("Lamp") do
			if lamp:IsA("Model") then
				local distance = (lamp:GetPivot().Position - root).Magnitude
				if distance < 160 then
					table.insert(near, { lamp = lamp, distance = distance })
				end
			end
		end
		table.sort(near, function(a, b)
			return a.distance < b.distance
		end)
		for index = 1, math.min(Evening.LAMP_LIGHTS, #near) do
			wanted[near[index].lamp] = true
		end
	end
	for lamp, light in lampLights do
		if not wanted[lamp] or not light.Parent then
			light:Destroy()
			lampLights[lamp] = nil
		end
	end
	for lamp in wanted do
		if not lampLights[lamp] then
			local head = lampHead(lamp)
			if head then
				local light = Instance.new("PointLight")
				light.Name = "EveningLight"
				light.Color = Color3.fromRGB(255, 214, 150)
				light.Brightness = 1.6
				light.Range = Evening.LAMP_RANGE
				light.Shadows = false
				light.Parent = head
				lampLights[lamp] = light
			end
		end
	end
end

-- ===== Окна домов ======================================================================

local function lightWindow(glass: BasePart, on: boolean)
	if on and not windows[glass] then
		windows[glass] = { material = glass.Material, color = glass.Color }
		glass.Material = Enum.Material.Neon
		glass.Color = Evening.WINDOW_COLOR
	elseif not on and windows[glass] then
		local saved = windows[glass]
		windows[glass] = nil
		glass.Material = saved.material
		glass.Color = saved.color
	end
end

local function updateWindows()
	for _, glass in CollectionService:GetTagged("HouseWindow") do
		if glass:IsA("BasePart") then
			lightWindow(glass, night)
		end
	end
	for glass in windows do
		if not glass.Parent then
			windows[glass] = nil
		end
	end
end

-- ===== Светлячки =======================================================================

--[[
	Где светлячки: клумбы и кусты парка, разбросанные по кругу не ближе
	сорока студов друг к другу, плюс озеро и подсолнухи. Это частицы, а не
	детали: бюджет живого мира (40 движущихся в кадре) они не трогают.
]]
local function fireflySpots(): { Vector3 }
	local spots: { Vector3 } = {}
	local function far(x: number, z: number): boolean
		for _, spot in spots do
			if (Vector2.new(spot.X, spot.Z) - Vector2.new(x, z)).Magnitude < 40 then
				return false
			end
		end
		return true
	end
	for _, id in { "lake", "sunflowers" } do
		local at = Playground.position(Playground.expect(id))
		table.insert(spots, Vector3.new(at.X, Decor.groundY(at.X, at.Z), at.Z))
	end
	for _, placement in Decor.placements do
		if #spots >= Evening.FIREFLY_SPOTS then
			break
		end
		local id = placement.id
		if
			(id == "flower_bed" or id == "bush_round" or id == "bush_round2")
			and far(placement.x, placement.z)
		then
			table.insert(
				spots,
				Vector3.new(placement.x, Decor.groundY(placement.x, placement.z), placement.z)
			)
		end
	end
	return spots
end

local function buildFireflies()
	local folder = Instance.new("Folder")
	folder.Name = "EveningFireflies"
	folder.Parent = workspace
	for index, spot in fireflySpots() do
		local air = Instance.new("Part")
		air.Name = `Fireflies{index}`
		air.Anchored = true
		air.CanCollide = false
		air.CanQuery = false
		air.CanTouch = false
		air.Transparency = 1
		air.Size = Vector3.new(22, 4, 22)
		air.CFrame = CFrame.new(spot + Vector3.new(0, 3, 0))
		air.Parent = folder
		local glow = Instance.new("ParticleEmitter")
		glow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		glow.Color = ColorSequence.new(Color3.fromRGB(215, 255, 110), Color3.fromRGB(255, 225, 110))
		glow.LightEmission = 1
		glow.LightInfluence = 0
		-- Мигают: разгораются, притухают и вспыхивают снова.
		glow.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.2, 0.9),
			NumberSequenceKeypoint.new(0.45, 0.25),
			NumberSequenceKeypoint.new(0.7, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		glow.Lifetime = NumberRange.new(4, 6.5)
		glow.Rate = 5
		glow.Speed = NumberRange.new(0.4, 1.2)
		glow.SpreadAngle = Vector2.new(180, 180)
		glow.Acceleration = Vector3.new(0, 0.15, 0)
		glow.Drag = 0.3
		glow.RotSpeed = NumberRange.new(-40, 40)
		glow.Enabled = false
		glow.Parent = air
		table.insert(fireflies, glow)
	end
end

local function updateExtras()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	updateLamps(root and root.Position)
	updateWindows()
	for _, glow in fireflies do
		glow.Enabled = night
	end
end

function EveningController.init()
	buildFireflies()
	-- Окно новой постройки загорается сразу, если купили её вечером.
	CollectionService:GetInstanceAddedSignal("HouseWindow"):Connect(function(glass: Instance)
		if night and glass:IsA("BasePart") then
			lightWindow(glass, true)
		end
	end)

	local sinceUpdate = UPDATE_SECONDS
	local sinceExtras = EXTRAS_SECONDS
	RunService.Heartbeat:Connect(function(dt: number)
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		-- Вне парка — день. Переход за секунду, чтобы телепорт не щёлкал светом.
		local target = if root and not Evening.inHub(root.Position) then 0 else 1
		if blend ~= target then
			blend = if target > blend then math.min(target, blend + dt) else math.max(target, blend - dt)
		end

		sinceUpdate += dt
		if sinceUpdate >= UPDATE_SECONDS then
			sinceUpdate = 0
			local look = Evening.blend(DAY, Evening.sample(EveningController.now()), blend)
			if not same(look, current) then
				current = look
				apply(look)
			end
			local wasNight = night
			night = current.glow >= Evening.NIGHT_FROM
			if night ~= wasNight then
				sinceExtras = EXTRAS_SECONDS
			end
		end

		sinceExtras += dt
		if sinceExtras >= EXTRAS_SECONDS then
			sinceExtras = 0
			updateExtras()
		end
	end)
end

return EveningController
