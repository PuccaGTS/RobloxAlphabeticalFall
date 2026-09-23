--!strict
--[[
	Коньки на катке зимней полянки (Config/Playground winter, метка AF_Ice).

	Лёд с низким трением персонажа Roblox не заносит: он держит скорость сам,
	как на асфальте. Поэтому скольжение — здесь: пока ребёнок на льду, его
	скорость по земле не слушается сразу, а догоняет желаемую за SKATE_GRIP
	секунды. Разогнался и отпустил — едет дальше; повернул — заносит.

	Скорость держит LinearVelocity в плоскости земли: вверх-вниз персонаж
	свободен, прыгать на льду можно как обычно. Сошёл со льда — всё снимается.
	Ничего не даёт и никуда не пишется: просто весело.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Playground = require(Shared.Config.Playground)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local AudioController = require(script.Parent.AudioController)

local SkateController = {}

local ICE_TAG = "AF_Ice"

local player = Players.LocalPlayer
local rays = RaycastParams.new()
rays.FilterType = Enum.RaycastFilterType.Include
local iceParts: { BasePart } = {}

local momentum = Vector3.zero
local glide: LinearVelocity? = nil
local skateSound: Sound? = nil

local function refreshIce()
	rays.FilterDescendantsInstances = iceParts
end

-- Лёд под ногами: луч вниз только по деталям катка.
local function onIce(root: BasePart): boolean
	if #iceParts == 0 then
		return false
	end
	return workspace:Raycast(root.Position, Vector3.new(0, -6, 0), rays) ~= nil
end

local function stop()
	if glide then
		local attachment = glide.Attachment0
		glide:Destroy()
		if attachment then
			attachment:Destroy()
		end
		glide = nil
	end
	if skateSound then
		skateSound:Destroy()
		skateSound = nil
	end
end

local function start(root: BasePart)
	-- С той скоростью, с какой въехал: разбежался по снегу — и покатился.
	momentum = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	local attachment = Instance.new("Attachment")
	attachment.Name = "SkateAttachment"
	attachment.Parent = root
	local constraint = Instance.new("LinearVelocity")
	constraint.Name = "Skate"
	constraint.Attachment0 = attachment
	constraint.RelativeTo = Enum.ActuatorRelativeTo.World
	constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	constraint.PrimaryTangentAxis = Vector3.xAxis
	constraint.SecondaryTangentAxis = Vector3.zAxis
	constraint.MaxForce = 40000
	constraint.PlaneVelocity = Vector2.new(momentum.X, momentum.Z)
	constraint.Parent = root
	glide = constraint

	local id = AudioRegistry.ids.sfx_skate
	if id and id ~= "" then
		local sound = Instance.new("Sound")
		sound.Name = "SkateSound"
		sound.SoundId = id
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = AudioController.group("SFX")
		sound.Parent = root
		sound:Play()
		skateSound = sound
	end
end

local function step(dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or humanoid.Sit then
		stop()
		return
	end
	if not onIce(root) then
		stop()
		return
	end
	if not glide or glide.Parent ~= root then
		stop()
		start(root)
	end
	-- От настоящей скорости, а не от задуманной: упёрся в бортик — встал, толкнули — поехал.
	momentum = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	local target = humanoid.MoveDirection * Vector3.new(1, 0, 1) * Playground.SKATE_SPEED
	local share = 1 - math.exp(-dt / Playground.SKATE_GRIP)
	momentum += (target - momentum) * share
	if glide then
		glide.PlaneVelocity = Vector2.new(momentum.X, momentum.Z)
	end
	if skateSound then
		skateSound.Volume = 0.5 * math.clamp(momentum.Magnitude / Playground.SKATE_SPEED, 0, 1)
	end
end

function SkateController.init()
	local function add(instance: Instance)
		if instance:IsA("BasePart") and not table.find(iceParts, instance) then
			table.insert(iceParts, instance)
			refreshIce()
		end
	end
	for _, instance in CollectionService:GetTagged(ICE_TAG) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(ICE_TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(ICE_TAG):Connect(function(instance: Instance)
		local index = table.find(iceParts, instance :: BasePart)
		if index then
			table.remove(iceParts, index)
			refreshIce()
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return SkateController
