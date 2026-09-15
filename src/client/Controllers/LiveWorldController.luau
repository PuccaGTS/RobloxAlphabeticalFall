--!nonstrict
--[[
	Бабочки у клумб и листья с деревьев. Места, количество и бюджет — Config/LiveWorld.

	Всё движется твинами (TweenService) по закреплённым деталям, без физики —
	docs/18-CONTENT-BACKLOG.md § 7 и docs/07-TECH-ARCH.md § 8. Ни одна бабочка
	и ни один лист ничего не задевают: у всех CanCollide, CanTouch и CanQuery
	выключены, сквозь них проходят, и по ним нельзя случайно «нажать».

	Бабочка — три детали: тельце и два крыла. Их положение хранит CFrameValue,
	а взмах крыльев — NumberValue; оба твинятся, и детали расставляются по их
	значениям. Так одна бабочка стоит два твина, а не твин на каждую деталь.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LiveWorld = require(Shared.Config.LiveWorld)

local LiveWorldController = {}

local FOLDER_NAME = "AlphabetFallLiveWorld"
local WING_SIZE = Vector3.new(0.55, 0.05, 0.45)
local FLAP_ANGLE = math.rad(55)

local random = Random.new()
local folder: Folder? = nil
local activeLeaves = 0

local function container(): Folder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = workspace
	folder = created
	return created
end

local function ghostPart(name: string, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

local function nearCamera(position: Vector3): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude < LiveWorld.VISIBLE_DISTANCE
end

-- ===== Бабочки ===================================================================

local function spawnButterfly(home: Vector3, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Butterfly"
	local body = ghostPart("Body", Vector3.new(0.12, 0.12, 0.45), Color3.fromRGB(60, 45, 40))
	body.Parent = model
	local wings = {}
	for _, side in { -1, 1 } do
		local wing = ghostPart(`Wing_{side}`, WING_SIZE, color)
		wing.Parent = model
		wings[side] = wing
	end
	model.Parent = container()

	local where = Instance.new("CFrameValue")
	local flap = Instance.new("NumberValue")
	where.Parent = model
	flap.Parent = model

	local function layout()
		local at = where.Value
		body.CFrame = at
		local angle = flap.Value * FLAP_ANGLE
		for side, wing in wings do
			wing.CFrame = at
				* CFrame.new(side * 0.06, 0, 0)
				* CFrame.Angles(0, 0, side * angle)
				* CFrame.new(side * WING_SIZE.X / 2, 0, 0)
		end
	end
	where.Changed:Connect(layout)
	flap.Changed:Connect(layout)

	local function pointNearHome(): Vector3
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(1, LiveWorld.BUTTERFLY_RADIUS)
		local low, high = LiveWorld.BUTTERFLY_HEIGHT[1], LiveWorld.BUTTERFLY_HEIGHT[2]
		return home
			+ Vector3.new(math.cos(angle) * radius, random:NextNumber(low, high), math.sin(angle) * radius)
	end

	local start = pointNearHome()
	where.Value = CFrame.new(start)

	-- Крылья машут всегда: бесконечный твин туда-обратно.
	TweenService:Create(
		flap,
		TweenInfo.new(
			random:NextNumber(0.12, 0.18),
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,
			true
		),
		{ Value = 1 }
	):Play()

	task.spawn(function()
		while model.Parent do
			local from = where.Value.Position
			local target = pointNearHome()
			local seconds = random:NextNumber(1.8, 3.5)
			-- Смотрит туда, куда летит; тихо висит на месте, если камера далеко.
			if nearCamera(from) and (target - from).Magnitude > 0.1 then
				local goal = CFrame.lookAt(target, target + (target - from).Unit)
				TweenService:Create(where, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Value = goal })
					:Play()
			end
			task.wait(seconds + random:NextNumber(0.2, 1.2))
		end
	end)
end

-- ===== Листья ====================================================================

local function dropLeaf(sources: { LiveWorld.LeafSource })
	if activeLeaves >= LiveWorld.LEAVES_AT_ONCE or #sources == 0 then
		return
	end
	local source = sources[random:NextInteger(1, #sources)]
	if not nearCamera(source.position) then
		return
	end

	local angle = random:NextNumber(0, math.pi * 2)
	local radius = random:NextNumber(0, source.spread)
	local top = source.position
		+ Vector3.new(math.cos(angle) * radius, source.height, math.sin(angle) * radius)
	local drift = Vector3.new(random:NextNumber(-3, 3), 0, random:NextNumber(-3, 3))
	local ground = Vector3.new(top.X, source.position.Y + 0.1, top.Z) + drift

	local colors = LiveWorld.LEAF_COLORS
	local leaf = ghostPart("Leaf", Vector3.new(0.5, 0.05, 0.35), colors[random:NextInteger(1, #colors)])
	leaf.CFrame = CFrame.new(top) * CFrame.Angles(random:NextNumber(0, 3), random:NextNumber(0, 3), 0)
	leaf.Parent = container()
	activeLeaves += 1

	local low, high = LiveWorld.LEAF_FALL_SECONDS[1], LiveWorld.LEAF_FALL_SECONDS[2]
	local seconds = random:NextNumber(low, high)
	-- Лист ложится плашмя и поворачивается по пути вниз, а не падает камнем.
	local landed = CFrame.new(ground) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	local fall = TweenService:Create(leaf, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { CFrame = landed })
	fall:Play()
	fall.Completed:Once(function()
		local fade = TweenService:Create(leaf, TweenInfo.new(1.5), { Transparency = 1 })
		fade:Play()
		fade.Completed:Once(function()
			leaf:Destroy()
			activeLeaves -= 1
		end)
	end)
end

function LiveWorldController.init()
	--[[
		Ждём декор: расстановка общая, но деревья и клумбы приедут не сразу.
		Координаты при этом из конфига, так что ждать нужно только саму площадь.
	]]
	task.spawn(function()
		workspace:WaitForChild("Hub", 60)

		local colors = LiveWorld.BUTTERFLY_COLORS
		local index = 0
		for _, home in LiveWorld.butterflyHomes() do
			for _ = 1, LiveWorld.BUTTERFLIES_PER_BED do
				index += 1
				spawnButterfly(home, colors[(index - 1) % #colors + 1])
			end
		end

		local sources = LiveWorld.leafSources()
		while true do
			task.wait(LiveWorld.LEAF_INTERVAL)
			dropLeaf(sources)
		end
	end)
end

return LiveWorldController
