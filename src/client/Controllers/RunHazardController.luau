--!nonstrict
--[[
	Движение аттракционов забега и их касания (World/RunAttractions на сервере).

	Сервер ставит детали на место и вешает теги: RunMover — «двигай меня»,
	RunHurt — «сбиваю». Здесь каждое движение считается от серверных часов
	(workspace:GetServerTimeNow), поэтому вертушка у всех в одной фазе, а у
	ребёнка на экране крутится плавно — без рывков сетевой репликации.

	Касание проверяется тут же, по той картинке, которую ребёнок видит: сбил
	молот — значит, сбил. Сервер только возвращает к флажку и больше ничего
	не делает, так что подделывать касание незачем.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefs = require(Shared.Net.RemoteDefs)

local RunHazardController = {}

local MOVER_TAG = "RunMover"
local HURT_TAG = "RunHurt"

-- Насколько персонаж «шире» точки корня: полстуда вбок, ноги на три студа вниз.
local SIDE_MARGIN = 1
local FEET = 3.3
local HEAD = 2.5
local NEAR = 60 -- дальше этого движущиеся детали не двигаем и не проверяем
local HIT_COOLDOWN = 1.6
local SINK_EASE = 0.25 -- за сколько секунд кочка уходит в лаву и поднимается

local player = Players.LocalPlayer
local movers: { [BasePart]: boolean } = {}
local hurting: { [BasePart]: boolean } = {}
local lastHit = 0
local originalColor: { [BasePart]: Color3 } = {}

local function positionFor(part: BasePart, now: number): CFrame?
	local kind = part:GetAttribute("Mover")
	local base = part:GetAttribute("Base")
	if typeof(base) ~= "CFrame" then
		return nil
	end
	local period = part:GetAttribute("Period") or 1
	local phase = part:GetAttribute("Phase") or 0
	local offset = part:GetAttribute("Offset")
	if typeof(offset) ~= "CFrame" then
		offset = CFrame.identity
	end

	if kind == "spin" then
		local angle = 2 * math.pi * ((now + phase) / period)
		return base * CFrame.Angles(0, angle, 0) * offset
	elseif kind == "swing" then
		local amplitude = part:GetAttribute("Amplitude") or 0.5
		local angle = amplitude * math.sin(2 * math.pi * (now + phase) / period)
		return base * CFrame.Angles(0, 0, angle) * offset
	elseif kind == "roll" then
		local s = (now + phase) % period
		local travel = part:GetAttribute("Travel") or 0
		if s >= travel then
			part.Transparency = 1
			return base * CFrame.new(0, -200, 0)
		end
		part.Transparency = 0
		local speed = part:GetAttribute("Speed") or 10
		local radius = part:GetAttribute("Radius") or 5
		local distance = s * speed
		-- Последние полсекунды валун уходит в землю: он не исчезает, а проваливается.
		local sink = math.max(0, s - (travel - 0.5)) / 0.5 * radius * 2
		return base * CFrame.new(0, -sink, distance) * CFrame.Angles(distance / radius, 0, 0)
	elseif kind == "sink" then
		local s = (now + phase) % period
		local solid = part:GetAttribute("Solid") or period
		local warn = part:GetAttribute("Warn") or 0.8
		local depth = part:GetAttribute("Depth") or 4
		local warnColor = part:GetAttribute("WarnColor")
		if not originalColor[part] then
			originalColor[part] = part.Color
		end
		local down
		if s < solid then
			down = if s < SINK_EASE then 1 - s / SINK_EASE else 0
			local warning = s >= solid - warn
			part.Color = if warning and typeof(warnColor) == "Color3" then warnColor else originalColor[part]
		else
			down = math.min(1, (s - solid) / SINK_EASE)
			part.Color = originalColor[part]
		end
		return base * CFrame.new(0, -depth * down, 0)
	end
	return nil
end

-- Задела ли деталь персонажа: корень в пространстве детали с запасом на тело.
local function touches(part: BasePart, root: Vector3): boolean
	if part.Transparency >= 1 then
		return false
	end
	local size = part.Size
	if part.Shape == Enum.PartType.Ball then
		return (part.Position - root).Magnitude < size.X / 2 + SIDE_MARGIN + 0.3
	end
	local p = part.CFrame:PointToObjectSpace(root)
	local half = size / 2
	-- Цилиндр лежит осью по X: поперёк оси он круглый, считаем его коробкой — запас и так есть.
	return math.abs(p.X) < half.X + SIDE_MARGIN
		and math.abs(p.Z) < half.Z + SIDE_MARGIN
		and p.Y < half.Y + FEET
		and p.Y > -half.Y - HEAD
end

local function onHit()
	local now = os.clock()
	if now - lastHit < HIT_COOLDOWN then
		return
	end
	lastHit = now
	RemoteDefs.event("RunHazard"):FireServer()
end

local function step()
	if next(movers) == nil and next(hurting) == nil then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rootPosition = root and root.Position
	local now = workspace:GetServerTimeNow()

	for part in movers do
		if not part.Parent then
			movers[part] = nil
			continue
		end
		local base = part:GetAttribute("Base")
		if rootPosition and typeof(base) == "CFrame" and (base.Position - rootPosition).Magnitude > NEAR then
			continue
		end
		local cframe = positionFor(part, now)
		if cframe then
			part.CFrame = cframe
		end
	end

	if not rootPosition then
		return
	end
	for part in hurting do
		if not part.Parent then
			hurting[part] = nil
			continue
		end
		if (part.Position - rootPosition).Magnitude < NEAR and touches(part, rootPosition) then
			onHit()
			return
		end
	end
end

local function watch(tag: string, set: { [BasePart]: boolean })
	local function add(instance: Instance)
		if instance:IsA("BasePart") then
			set[instance] = true
		end
	end
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		set[instance :: BasePart] = nil
		originalColor[instance :: BasePart] = nil
	end)
end

function RunHazardController.init()
	watch(MOVER_TAG, movers)
	watch(HURT_TAG, hurting)
	RunService.RenderStepped:Connect(step)
end

-- Для тестов: где деталь стоит в момент now.
RunHazardController.positionFor = positionFor
RunHazardController.touches = touches

return RunHazardController
