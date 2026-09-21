--!strict
--[[
	Строит горизонт по Config/Horizon: земля до края видимости, два пояса холмов
	с деревьями и горный хребет вдали. Всё закреплено, без столкновений и теней:
	дойти туда нельзя, а тень от горы на полкилометра ляжет на соседние холмы
	грязным пятном.
]]

local CollectionService = game:GetService("CollectionService")
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

--[[
	Водопад (Config/Horizon.WATERFALL): скала с травяной шапкой и плечами,
	вода с неё двумя уступами в пенную чашу, из чаши ручей к изгороди.
	Вода — полупрозрачные голубые пласты; течёт она глазу благодаря белым
	струйкам, которые клиент гонит сверху вниз (Controllers/AmbientController,
	метка AF_FallStripe), и брызгам.
]]
local ROCK = Color3.fromRGB(176, 158, 138)
local ROCK_DARK = Color3.fromRGB(138, 124, 110)
local GRASS = Color3.fromRGB(110, 175, 90)
local WATER = Color3.fromRGB(110, 190, 245)
local FOAM = Color3.fromRGB(240, 250, 255)

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	scenery(p)
	p.Parent = parent
	return p
end

local function mist(
	parent: BasePart,
	direction: Enum.NormalId,
	rate: number,
	speed: number,
	size: number,
	life: number
)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(FOAM)
	emitter.LightEmission = 0.3
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.6), NumberSequenceKeypoint.new(1, size) })
	emitter.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(life * 0.7, life)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(speed * 0.7, speed)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.EmissionDirection = direction
	emitter.Parent = parent
end

local function waterfall(parent: Instance)
	local spec = Horizon.WATERFALL
	local foot = Horizon.waterfallFrame()
	local model = Instance.new("Model")
	model.Name = "Waterfall"
	model.Parent = parent
	local h = spec.height
	local w = spec.width

	--[[
		Скала — тот же горный хребет из Creator Store, что стоит вдали, только
		поменьше и тёплого цвета: вода падает из расщелины настоящей скалы, а не
		из ящика. Лицо скалы — у z = 0, к площади.
	]]
	local look = foot.LookVector
	place(
		model,
		Horizon.MOUNTAIN,
		(foot * CFrame.new(0, 0, 24)).Position,
		math.atan2(-look.X, -look.Z),
		spec.rockScale,
		ROCK
	)
	for _, side in { -1, 1 } do
		for boulder = 1, 3 do
			local size = 5 + boulder * 2
			block(
				model,
				"Boulder",
				Vector3.new(size, size * 0.8, size),
				foot
					* CFrame.new(side * (w / 2 + 6 + boulder * 5), size * 0.35, -2 - boulder * 3)
					* CFrame.Angles(0.3 * boulder, boulder, 0.2),
				ROCK_DARK
			)
		end
	end
	-- Задник за водой: без него сквозь полупрозрачный поток видно небо между пиками.
	block(model, "FallBack", Vector3.new(w + 3, h + 1, 4), foot * CFrame.new(0, (h + 1) / 2, 3), ROCK_DARK)
	-- Уступ на середине высоты: вода падает двумя каскадами — так она читается водопадом.
	local ledgeY = h * 0.45
	block(model, "Ledge", Vector3.new(w + 10, 3, 8), foot * CFrame.new(0, ledgeY - 1.5, -3), ROCK_DARK)
	block(model, "LedgePool", Vector3.new(w + 6, 0.6, 6), foot * CFrame.new(0, ledgeY + 0.2, -3), WATER).Transparency =
		0.1

	-- Река на макушке скалы и два пласта воды.
	local upper = block(
		model,
		"FallUpper",
		Vector3.new(w, h - ledgeY + 3, 1.2),
		foot * CFrame.new(0, (h + ledgeY) / 2 + 1.5, -0.8),
		WATER
	)
	upper.Transparency = 0.15
	local lower = block(
		model,
		"FallLower",
		Vector3.new(w + 2, ledgeY, 1.2),
		foot * CFrame.new(0, ledgeY / 2, -6.8),
		WATER
	)
	lower.Transparency = 0.15

	-- Белые струйки бегут по пласту сверху вниз: их двигает клиент.
	for _, sheet in { upper, lower } do
		local top = sheet.Position.Y + sheet.Size.Y / 2
		local bottom = sheet.Position.Y - sheet.Size.Y / 2
		for stripe = 1, 5 do
			local x = (stripe - 3) * (sheet.Size.X / 5.5)
			local strip = block(
				model,
				"FallStripe",
				Vector3.new(0.8, 6, 0.3),
				sheet.CFrame * CFrame.new(x, 0, -0.7),
				FOAM
			)
			strip.Transparency = 0.25
			strip:SetAttribute("Top", top - 3)
			strip:SetAttribute("Bottom", bottom + 3)
			strip:SetAttribute("Phase", stripe * 0.37)
			CollectionService:AddTag(strip, "AF_FallStripe")
		end
	end

	-- Пенная чаша, камни по кругу и брызги.
	local pool = block(
		model,
		"Pool",
		Vector3.new(1, 34, 34),
		foot * CFrame.new(0, 0.4, -14) * CFrame.Angles(0, 0, math.pi / 2),
		WATER
	)
	pool.Shape = Enum.PartType.Cylinder
	pool.Transparency = 0.1
	for index = 1, 10 do
		local angle = index / 10 * math.pi * 2
		local size = 3 + (index % 3)
		local rock = block(
			model,
			"PoolRock",
			Vector3.new(size, size, size),
			foot * CFrame.new(math.cos(angle) * 17, size * 0.2, -14 + math.sin(angle) * 17),
			ROCK_DARK
		)
		rock.Shape = Enum.PartType.Ball
	end
	local foam = block(model, "Foam", Vector3.new(w + 4, 1, 6), foot * CFrame.new(0, 0.9, -9), FOAM)
	foam.Transparency = 0.2
	mist(foam, Enum.NormalId.Top, 8, 5, 9, 2.4)
	local crest = block(model, "Crest", Vector3.new(w, 0.4, 1), foot * CFrame.new(0, h + 3, -1), FOAM)
	crest.Transparency = 0.3
	mist(crest, Enum.NormalId.Bottom, 14, 18, 5, 2.6)

	-- Ручей от чаши к изгороди, чуть петляя.
	local from = (foot * CFrame.new(0, 0.55, -30)).Position
	local target = (foot * CFrame.new(0, 0.55, -(spec.distance - Horizon.EDGE) + 2)).Position
	local points = { from }
	for bend = 1, 4 do
		local along = from:Lerp(target, bend / 5)
		table.insert(points, along + foot.RightVector * (if bend % 2 == 0 then 4 else -4))
	end
	table.insert(points, target)
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		block(
			model,
			"Stream",
			Vector3.new(6, 0.4, (b - a).Magnitude + 3),
			CFrame.lookAt((a + b) / 2, b),
			WATER
		).Transparency =
			0.1
	end
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

	waterfall(folder)

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
