--!nonstrict
--[[
	Вещи проката из деталей (Config/Rental): самокат, велосипед с корзинкой,
	лошадка-единорог на палочке.

	Строятся от точки на земле под ребёнком (base, вперёд — −Z). Деталь Mount
	стоит там, где у ребёнка корень: к нему её и крепит RentalService. Колёса
	и педали сидят на Motor6D «Axle»/«Crank» — их крутит клиент
	(RentalController), остальное приварено к Mount или к ступице колеса.

	На витрине проката стоят те же модели, только закреплённые.
]]

local RentalVehicles = {}

RentalVehicles.FLOOR = 3 -- от земли до корня обычного персонажа: здесь стоит Mount

local WHITE = Color3.fromRGB(250, 250, 250)
local TIRE = Color3.fromRGB(45, 45, 55)
local SILVER = Color3.fromRGB(200, 205, 215)
local GOLD = Color3.fromRGB(255, 205, 70)
local RAINBOW = {
	Color3.fromRGB(240, 90, 90),
	Color3.fromRGB(245, 150, 70),
	Color3.fromRGB(250, 210, 80),
	Color3.fromRGB(120, 205, 110),
	Color3.fromRGB(80, 190, 220),
	Color3.fromRGB(160, 110, 220),
}

local function piece(model: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = model
	return p
end

local function ball(model, name, diameter, cframe, color)
	local p = piece(model, name, Vector3.one * diameter, cframe, color)
	p.Shape = Enum.PartType.Ball
	return p
end

-- Цилиндр между двумя точками: у Roblox ось цилиндра — X.
local function rod(model, name, a: Vector3, b: Vector3, diameter: number, color: Color3): BasePart
	local length = (b - a).Magnitude
	local p = piece(
		model,
		name,
		Vector3.new(length, diameter, diameter),
		CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0),
		color
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function weld(a: BasePart, b: BasePart)
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = a
	joint.Part1 = b
	joint.Parent = b
end

-- Вращающийся узел: ступица на моторе от Mount. Клиент крутит C0 от атрибута Base.
local function spinner(mount: BasePart, hub: BasePart, name: string, ratio: number, radius: number)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = mount
	motor.Part1 = hub
	motor.C0 = mount.CFrame:ToObjectSpace(hub.CFrame)
	motor.C1 = CFrame.identity
	motor:SetAttribute("Base", motor.C0)
	motor:SetAttribute("Ratio", ratio)
	motor:SetAttribute("Radius", radius)
	motor.Parent = hub
end

--[[
	Колесо: шина, светлый обод и три спицы крест-накрест — по спицам видно,
	что колесо крутится. Лежит в плоскости YZ, ось — X.
]]
local function wheel(model, mount, name: string, at: CFrame, radius: number, width: number, hubColor: Color3)
	local hub = piece(model, name, Vector3.new(width + 0.1, 0.45, 0.45), at, hubColor)
	hub.Shape = Enum.PartType.Cylinder
	local tire = piece(model, `{name}Tire`, Vector3.new(width, radius * 2, radius * 2), at, TIRE)
	tire.Shape = Enum.PartType.Cylinder
	local rim =
		piece(model, `{name}Rim`, Vector3.new(width + 0.02, radius * 2 - 0.35, radius * 2 - 0.35), at, WHITE)
	rim.Shape = Enum.PartType.Cylinder
	weld(hub, tire)
	weld(hub, rim)
	for index = 0, 2 do
		local spoke = piece(
			model,
			`{name}Spoke{index}`,
			Vector3.new(width + 0.06, radius * 2 - 0.45, 0.12),
			at * CFrame.Angles(index * math.pi / 3, 0, 0),
			hubColor
		)
		weld(hub, spoke)
	end
	spinner(mount, hub, "Axle", 1, radius)
	return hub
end

local BUILDERS = {}

--[[
	Самокат: дека под ногами, два маленьких колеса, руль с ручками и звоночком.
	Ребёнок на нём стоит чуть выше земли (lift в RentalService): дека под ступнями.
]]
function BUILDERS.scooter(model: Model, mount: BasePart, base: CFrame, color: Color3)
	local lift = 0.6
	local deck =
		piece(model, "Deck", Vector3.new(1.3, 0.25, 3.8), base * CFrame.new(0, lift - 0.13, 0.25), color)
	weld(mount, deck)
	local grip =
		piece(model, "Grip", Vector3.new(1, 0.05, 2.6), base * CFrame.new(0, lift + 0.01, 0.35), TIRE)
	weld(mount, grip)
	local fender =
		piece(model, "Fender", Vector3.new(0.9, 0.15, 1.1), base * CFrame.new(0, 0.95, 2.15), color)
	weld(mount, fender)
	wheel(model, mount, "WheelFront", base * CFrame.new(0, 0.45, -1.6), 0.45, 0.4, color)
	wheel(model, mount, "WheelBack", base * CFrame.new(0, 0.45, 1.95), 0.45, 0.4, color)
	local stem = rod(
		model,
		"Stem",
		(base * CFrame.new(0, 0.45, -1.6)).Position,
		(base * CFrame.new(0, 3.35, -1.85)).Position,
		0.3,
		SILVER
	)
	weld(mount, stem)
	local bar = rod(
		model,
		"Handlebar",
		(base * CFrame.new(-1.1, 3.35, -1.85)).Position,
		(base * CFrame.new(1.1, 3.35, -1.85)).Position,
		0.22,
		SILVER
	)
	weld(mount, bar)
	for _, side in { -1, 1 } do
		local handle = rod(
			model,
			`Handle{side}`,
			(base * CFrame.new(side * 0.8, 3.35, -1.85)).Position,
			(base * CFrame.new(side * 1.25, 3.35, -1.85)).Position,
			0.32,
			color
		)
		weld(mount, handle)
	end
	local bell = ball(model, "Bell", 0.4, base * CFrame.new(0.45, 3.55, -1.85), GOLD)
	weld(mount, bell)
end

--[[
	Велосипед: рама цвета проката, колёса со спицами, седло, педали, руль
	и плетёная корзинка с цветами впереди. Ребёнок на нём сидит (поза sit).
]]
function BUILDERS.bike(model: Model, mount: BasePart, base: CFrame, color: Color3)
	local function at(x, y, z)
		return (base * CFrame.new(x, y, z)).Position
	end
	local radius = 1.1
	wheel(model, mount, "WheelFront", base * CFrame.new(0, radius, -2.3), radius, 0.25, SILVER)
	wheel(model, mount, "WheelBack", base * CFrame.new(0, radius, 1.5), radius, 0.25, SILVER)
	local crank = at(0, 0.95, -0.25)
	local saddle = at(0, 1.85, 0.45)
	local head = at(0, 2.15, -1.9)
	local tubes = {
		{ "SeatTube", crank, saddle },
		{ "TopTube", at(0, 1.75, 0.35), head },
		{ "DownTube", crank, at(0, 1.75, -1.95) },
		{ "ChainStay", crank, at(0, radius, 1.5) },
		{ "SeatStay", at(0, 1.7, 0.4), at(0, radius, 1.5) },
		{ "Fork", head, at(0, radius, -2.3) },
		{ "HeadStem", head, at(0, 2.75, -1.95) },
	}
	for _, spec in tubes do
		weld(mount, rod(model, spec[1], spec[2], spec[3], 0.28, color))
	end
	local seat = piece(model, "Saddle", Vector3.new(0.7, 0.28, 1.1), base * CFrame.new(0, 1.98, 0.5), TIRE)
	weld(mount, seat)
	weld(mount, rod(model, "Handlebar", at(-1, 2.75, -1.95), at(1, 2.75, -1.95), 0.2, SILVER))
	for _, side in { -1, 1 } do
		weld(
			mount,
			rod(model, `Handle{side}`, at(side * 0.75, 2.75, -1.95), at(side * 1.15, 2.75, -1.95), 0.3, WHITE)
		)
	end
	-- Педали на шатуне: крутятся вдвое медленнее колеса.
	local hub = piece(model, "Crank", Vector3.new(0.5, 0.5, 0.5), CFrame.new(crank) * base.Rotation, SILVER)
	hub.Shape = Enum.PartType.Cylinder
	for _, side in { -1, 1 } do
		local arm = piece(
			model,
			`CrankArm{side}`,
			Vector3.new(0.15, 1, 0.2),
			CFrame.new(crank) * base.Rotation * CFrame.new(side * 0.35, side * 0.4, 0),
			SILVER
		)
		weld(hub, arm)
		local pedal = piece(
			model,
			`Pedal{side}`,
			Vector3.new(0.5, 0.15, 0.35),
			CFrame.new(crank) * base.Rotation * CFrame.new(side * 0.6, side * 0.85, 0),
			TIRE
		)
		weld(hub, pedal)
	end
	spinner(mount, hub, "Crank", 0.5, radius)

	-- Корзинка с цветами.
	local basket = piece(
		model,
		"Basket",
		Vector3.new(1.3, 0.8, 0.9),
		base * CFrame.new(0, 2.45, -2.55),
		Color3.fromRGB(190, 140, 80)
	)
	basket.Material = Enum.Material.Fabric
	weld(mount, basket)
	for index, offset in
		{ Vector3.new(-0.35, 0.5, 0.1), Vector3.new(0.3, 0.55, -0.15), Vector3.new(0.05, 0.6, 0.2) }
	do
		local flower = ball(
			model,
			`Flower{index}`,
			0.45,
			base * CFrame.new(0, 2.45, -2.55) * CFrame.new(offset),
			RAINBOW[(index * 2) % #RAINBOW + 1]
		)
		weld(mount, flower)
		weld(mount, ball(model, `FlowerHeart{index}`, 0.2, flower.CFrame * CFrame.new(0, 0.12, -0.12), GOLD))
	end
end

--[[
	Лошадка на палочке: белая голова с радужной гривой, золотым рогом,
	ушками и уздечкой, палочка между ног, внизу колёсико. Ребёнок бежит
	сам, лошадка скачет (подкидывает клиент).
]]
function BUILDERS.unicorn(model: Model, mount: BasePart, base: CFrame, color: Color3)
	local function at(x, y, z)
		return base * CFrame.new(x, y, z)
	end
	weld(mount, rod(model, "Stick", at(0, 0.4, 1.05).Position, at(0, 3.05, -1.45).Position, 0.3, color))
	for index = 1, 3 do
		local k = index / 4
		local point = at(0, 0.4, 1.05).Position:Lerp(at(0, 3.05, -1.45).Position, k)
		weld(
			mount,
			rod(
				model,
				`StickBand{index}`,
				point,
				point + (at(0, 3.05, -1.45).Position - at(0, 0.4, 1.05).Position).Unit * 0.2,
				0.34,
				GOLD
			)
		)
	end
	wheel(model, mount, "WheelBack", at(0, 0.4, 1.1), 0.4, 0.3, color)

	weld(mount, rod(model, "Neck", at(0, 2.9, -1.4).Position, at(0, 3.75, -1.95).Position, 1, WHITE))
	weld(mount, ball(model, "Head", 1.35, at(0, 3.95, -2.05), WHITE))
	weld(mount, ball(model, "Snout", 1, at(0, 3.65, -2.6), Color3.fromRGB(255, 235, 240)))
	for _, side in { -1, 1 } do
		weld(mount, ball(model, `Eye{side}`, 0.26, at(side * 0.5, 4.1, -2.35), TIRE))
		weld(mount, ball(model, `Shine{side}`, 0.1, at(side * 0.55, 4.18, -2.46), WHITE))
		weld(
			mount,
			ball(model, `Cheek{side}`, 0.3, at(side * 0.5, 3.7, -2.45), Color3.fromRGB(255, 160, 185))
		)
		weld(
			mount,
			ball(model, `Nostril{side}`, 0.12, at(side * 0.2, 3.7, -3.08), Color3.fromRGB(230, 150, 170))
		)
		local ear = piece(
			model,
			`Ear{side}`,
			Vector3.new(0.22, 0.55, 0.3),
			at(side * 0.35, 4.6, -1.9) * CFrame.Angles(0, 0, -side * 0.3),
			WHITE
		)
		weld(mount, ear)
	end
	-- Рог: три золотых шарика всё меньше, чуть вперёд.
	for index, spec in { { 0.36, 4.62, -2.2 }, { 0.26, 4.9, -2.3 }, { 0.16, 5.12, -2.38 } } do
		local horn = ball(model, `Horn{index}`, spec[1], at(0, spec[2], spec[3]), GOLD)
		horn.Material = Enum.Material.Neon
		weld(mount, horn)
	end
	-- Радужная грива по затылку и шее.
	for index = 1, 6 do
		local k = (index - 1) / 5
		local point = at(0, 4.55 - k * 1.5, -1.75 + k * 0.45)
		weld(mount, ball(model, `Mane{index}`, 0.5, point, RAINBOW[index]))
	end
	-- Уздечка: красный ремешок вокруг морды.
	local strap =
		piece(model, "Bridle", Vector3.new(1.05, 0.14, 0.14), at(0, 3.7, -2.55), Color3.fromRGB(230, 70, 80))
	weld(mount, strap)
end

--[[
	Собрать вещь id у точки base на земле. Возвращает модель с Mount
	(PrimaryPart) на высоте корня обычного персонажа; всё закреплено.
]]
function RentalVehicles.build(id: string, base: CFrame, color: Color3): Model
	local builder = BUILDERS[id]
	assert(builder, `RentalVehicles: не умею строить "{id}"`)
	local model = Instance.new("Model")
	model.Name = `Rental_{id}`
	local mount = piece(
		model,
		"Mount",
		Vector3.new(0.3, 0.3, 0.3),
		base * CFrame.new(0, RentalVehicles.FLOOR, 0),
		WHITE
	)
	mount.Transparency = 1
	model.PrimaryPart = mount
	builder(model, mount, base, color)
	model.WorldPivot = base
	model:SetAttribute("Vehicle", id)
	return model
end

-- На сколько поднять ребёнка над землёй: на самокате он стоит на деке.
function RentalVehicles.lift(id: string): number
	return if id == "scooter" then 0.6 else 0
end

return RentalVehicles
