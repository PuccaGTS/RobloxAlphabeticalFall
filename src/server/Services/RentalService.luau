--!nonstrict
--[[
	Прокат в парке (Config/Rental): встал на круг у ларька — поехал.

	Вещь крепится к персонажу здесь, на сервере, — так её видят все дети
	вокруг. Персонаж принадлежит своему игроку, и приваренная к нему вещь
	движется вместе с ним у каждого без задержки. Скорость и прыжок меняются
	тут же; поза, колёса и подскоки лошадки — у клиента (RentalController).

	Слезть — кнопка ✖ (событие RentalOff). Уехал из парка — на поляну занятия,
	в забег, домой через портал — вещь остаётся в прокате сама: там своя
	скорость, и самокат только мешал бы.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rental = require(Shared.Config.Rental)
local Evening = require(Shared.Config.Evening)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local RentalVehicles = require(script.Parent.Parent.World.RentalVehicles)
local RateLimiter = require(script.Parent.RateLimiter)

local RentalService = {}

RentalService.PAD_TAG = "RentalPad"
RentalService.VEHICLE_TAG = "RentalVehicle"

type Ride = {
	id: string,
	model: Model,
	humanoid: Humanoid,
	walk: number,
	jump: number,
	hip: number,
	speed: number, -- что поставили мы: WalkSpeed и прыжок на время катания
	jumpSet: number,
}

local rides: { [Player]: Ride } = {}
-- На каком круге ребёнок стоял в прошлую проверку: садимся, только когда на круг ВОШЁЛ.
local standing: { [Player]: Instance? } = {}

function RentalService.riding(player: Player): string?
	local ride = rides[player]
	return ride and ride.id
end

function RentalService.dismount(player: Player)
	local ride = rides[player]
	if not ride then
		return
	end
	rides[player] = nil
	if ride.model.Parent then
		ride.model:Destroy()
	end
	local humanoid = ride.humanoid
	if humanoid.Parent then
		--[[
			Скорость и прыжок возвращаем, только если их никто не менял после нас:
			забег ставит свою скорость при старте, и сторож, заметивший, что
			ребёнок уже в забеге, не должен вернуть ему пешую.
		]]
		if humanoid.WalkSpeed == ride.speed then
			humanoid.WalkSpeed = ride.walk
		end
		if humanoid.UseJumpPower and humanoid.JumpPower == ride.jumpSet then
			humanoid.JumpPower = ride.jump
		elseif not humanoid.UseJumpPower and humanoid.JumpHeight == ride.jumpSet then
			humanoid.JumpHeight = ride.jump
		end
		humanoid.HipHeight = ride.hip
	end
	player:SetAttribute("Riding", nil)
end

function RentalService.mount(player: Player, id: string): boolean
	local vehicle = Rental.get(id)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not vehicle or not humanoid or not root or humanoid.Health <= 0 then
		return false
	end
	RentalService.dismount(player)

	local ride: Ride = {
		id = id,
		model = nil :: any,
		humanoid = humanoid,
		walk = humanoid.WalkSpeed,
		jump = if humanoid.UseJumpPower then humanoid.JumpPower else humanoid.JumpHeight,
		hip = humanoid.HipHeight,
		speed = vehicle.speed,
		jumpSet = 0,
	}
	humanoid.HipHeight = ride.hip + RentalVehicles.lift(id)
	humanoid.WalkSpeed = vehicle.speed
	if vehicle.jump > 0 then
		-- Лошадка скачет выше: прыжок на vehicle.jump студов выше обычного.
		if humanoid.UseJumpPower then
			local rise = ride.jump * ride.jump / (2 * workspace.Gravity) + vehicle.jump
			humanoid.JumpPower = math.sqrt(2 * workspace.Gravity * rise)
		else
			humanoid.JumpHeight = ride.jump + vehicle.jump
		end
	end
	ride.jumpSet = if humanoid.UseJumpPower then humanoid.JumpPower else humanoid.JumpHeight

	-- Земля под ребёнком: вещь строится от неё, Mount садится на корень.
	local floor = humanoid.HipHeight + root.Size.Y / 2
	local ground = root.CFrame * CFrame.new(0, -floor, 0)
	local model = RentalVehicles.build(id, CFrame.new(ground.Position) * root.CFrame.Rotation, vehicle.color)
	local mount = model.PrimaryPart
	local joint = Instance.new("Motor6D")
	joint.Name = "RentalJoint"
	joint.Part0 = root
	joint.Part1 = mount
	joint.C0 = root.CFrame:ToObjectSpace(mount.CFrame)
	joint:SetAttribute("Base", joint.C0)
	joint.Parent = mount
	model.Parent = character
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end
	CollectionService:AddTag(model, RentalService.VEHICLE_TAG)
	ride.model = model
	rides[player] = ride
	player:SetAttribute("Riding", id)
	return true
end

--[[
	Круги проверяются по положению, а не касанием: Touched срабатывает снова,
	пока стоишь, и нажавший ✖ прямо на круге садился бы обратно. Здесь круг
	сажает, только когда ребёнок на него шагнул, — постоял, слез, сошёл, вернулся.
]]
local function checkPads()
	local pads = CollectionService:GetTagged(RentalService.PAD_TAG)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local on: Instance? = nil
		if root then
			for _, pad in pads do
				if pad:IsA("BasePart") then
					local offset = root.Position - pad.Position
					local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
					if flat < Rental.PAD_RADIUS + 0.5 and offset.Y > -1 and offset.Y < 6 then
						on = pad
						break
					end
				end
			end
		end
		if on and on ~= standing[player] then
			local id = on:GetAttribute("Vehicle")
			if RentalService.riding(player) ~= id then
				RentalService.mount(player, id)
			end
		end
		standing[player] = on
	end
end

function RentalService.start()
	task.spawn(function()
		while true do
			task.wait(0.2)
			checkPads()
		end
	end)

	RemoteDefs.event("RentalOff").OnServerEvent:Connect(function(player: Player)
		if not RateLimiter.allow(player, "RentalOff", RemoteDefs.RATE_LIMITS.RentalOff) then
			return
		end
		RentalService.dismount(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		rides[player] = nil
		standing[player] = nil
	end)

	-- Сторож: уехал из парка, персонаж пропал или сел — вещь возвращается в прокат.
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, ride in rides do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if
					not root
					or not ride.model.Parent
					or ride.model.Parent ~= character
					or ride.humanoid.Health <= 0
					or ride.humanoid.Sit
					or not Evening.inHub(root.Position)
				then
					RentalService.dismount(player)
				end
			end
		end
	end)
end

return RentalService
