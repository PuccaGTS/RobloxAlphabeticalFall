--!strict
--[[
	Строит горизонт по Config/Horizon: земля до края видимости, два пояса холмов
	с деревьями и горный хребет вдали. Всё закреплено, без столкновений и теней:
	дойти туда нельзя, а тень от горы на полкилометра ляжет на соседние холмы
	грязным пятном.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Horizon = require(ReplicatedStorage:WaitForChild("Shared").Config.Horizon)
local DecorService = require(script.Parent.Parent.Services.DecorService)

local HorizonBuilder = {}

local function scenery(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

local function hill(parent: Instance, spec: Horizon.Hill, index: number)
	local part = Instance.new("Part")
	part.Name = `Hill_{spec.belt}_{index}`
	part.Size = spec.size
	part.CFrame = CFrame.new(spec.position) * CFrame.Angles(0, spec.yaw, 0)
	part.Color = spec.color
	part.Material = Enum.Material.SmoothPlastic
	scenery(part)
	-- Эллипсоид из сферы: мягкий мультяшный холм без граней и швов.
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
end

local function place(parent: Instance, id: string, at: Vector3, yaw: number, scale: number, color: Color3?)
	local model = DecorService.modelFor(id, scale)
	if not model then
		return
	end
	model:PivotTo(CFrame.new(at) * CFrame.Angles(0, yaw, 0))
	local box, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, at.Y - (box.Position.Y - size.Y / 2), 0))
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			scenery(descendant)
			if color then
				descendant.Color = color
			end
		end
	end
	model.Parent = parent
end

function HorizonBuilder.build(parent: Instance)
	--[[
		Модель, а не папка: у места включён стриминг с радиусом 512 студов, и без
		Persistent клиент получил бы только ближние холмы — гор за полкилометра
		у него бы просто не было.
	]]
	local folder = Instance.new("Model")
	folder.Name = "Horizon"
	folder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	folder.Parent = parent

	local ground = Instance.new("Part")
	ground.Name = "FarGround"
	ground.Size = Vector3.new(Horizon.FAR_GROUND_SIZE, 2, Horizon.FAR_GROUND_SIZE)
	ground.CFrame = CFrame.new(0, Horizon.FAR_GROUND_TOP - 1, 0)
	ground.Color = Color3.fromRGB(100, 160, 85)
	ground.Material = Enum.Material.Grass
	scenery(ground)
	ground.Parent = folder

	local random = Random.new(Horizon.SEED + 2)
	local trees = 0
	for index, spec in Horizon.hills() do
		hill(folder, spec, index)
		for _, at in spec.trees do
			local id = Horizon.TREES[random:NextInteger(1, #Horizon.TREES)]
			local scale = Horizon.TREE_SCALE[1]
				+ random:NextNumber() * (Horizon.TREE_SCALE[2] - Horizon.TREE_SCALE[1])
			place(folder, id, at, random:NextNumber() * math.pi * 2, scale)
			trees += 1
		end
	end

	for _, mountain in Horizon.mountains() do
		place(
			folder,
			Horizon.MOUNTAIN,
			mountain.position,
			mountain.yaw,
			mountain.scale,
			Horizon.MOUNTAIN_COLOR
		)
	end

	print(
		`[Horizon] холмов {#Horizon.hills()}, деревьев на них {trees}, гор {Horizon.MOUNTAIN_COUNT}`
	)
end

return HorizonBuilder
