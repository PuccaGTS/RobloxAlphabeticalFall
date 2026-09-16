--!nonstrict
--[[
	Строит игровые места парка (Config/Playground): батуты, музыкальную дорожку,
	классики, песочницу с мячами и горкой, шарики и лабиринт.

	Сервер только ставит детали и вешает метки CollectionService. Что происходит
	при касании — подпрыгнуть, звякнуть, лопнуть, — решает клиент
	(Controllers/PlaygroundController): награды здесь нет, проверять нечего.

	Единственное, что живёт на сервере, — мячи: они физические и общие для всех,
	и если мяч укатился за бортик, вернуть его должен кто-то один.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Playground = require(Shared.Config.Playground)
local Decor = require(Shared.Config.Decor)

local PlaygroundService = {}

local RAINBOW = {
	Color3.fromRGB(240, 90, 90),
	Color3.fromRGB(245, 150, 70),
	Color3.fromRGB(250, 210, 80),
	Color3.fromRGB(120, 205, 110),
	Color3.fromRGB(80, 190, 220),
	Color3.fromRGB(90, 130, 230),
	Color3.fromRGB(160, 110, 220),
	Color3.fromRGB(230, 120, 190),
}

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.Parent = parent
	return p
end

local function cylinder(
	parent: Instance,
	name: string,
	height: number,
	diameter: number,
	at: CFrame,
	color: Color3
)
	local p = part(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		at * CFrame.Angles(0, 0, math.rad(90)),
		color
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function sign(parent: Instance, at: CFrame, text: string)
	local post = part(
		parent,
		"SignPost",
		Vector3.new(0.4, 5, 0.4),
		at * CFrame.new(0, 2.5, 0),
		Color3.fromRGB(150, 110, 70)
	)
	post.CanCollide = false
	local board = part(
		parent,
		"SignBoard",
		Vector3.new(6, 2, 0.4),
		at * CFrame.new(0, 5.5, 0),
		Color3.fromRGB(250, 240, 215)
	)
	board.CanCollide = false

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(70, 60, 50)
	label.Parent = gui
end

-- Точка места на земле, «лицом» к центру площади: так табличку видно с площади.
local function frameOf(spot): CFrame
	local position = Playground.position(spot)
	local ground = Decor.groundY(position.X, position.Z)
	local at = Vector3.new(position.X, ground, position.Z)
	return CFrame.lookAt(at, Vector3.new(0, ground, 0))
end

local BUILDERS = {}

-- Три батута разного размера: чем больше, тем выше подбрасывает.
function BUILDERS.trampolines(model: Model, origin: CFrame)
	local layout = { { -8, 4, 6 }, { 1, -5, 8 }, { 9, 5, 10 } }
	for index, spec in layout do
		local at = origin * CFrame.new(spec[1], 0, spec[2])
		local diameter = spec[3]
		cylinder(
			model,
			`TrampolineFrame_{index}`,
			1.6,
			diameter + 1.2,
			at * CFrame.new(0, 0.8, 0),
			Color3.fromRGB(70, 90, 140)
		)
		for leg = 1, 4 do
			local angle = leg / 4 * math.pi * 2
			part(
				model,
				`TrampolineLeg_{index}_{leg}`,
				Vector3.new(0.4, 1, 0.4),
				at * CFrame.new(math.cos(angle) * diameter / 2, 0.3, math.sin(angle) * diameter / 2),
				Color3.fromRGB(60, 60, 70)
			).CanCollide =
				false
		end
		local top = cylinder(
			model,
			`Trampoline_{index}`,
			0.3,
			diameter,
			at * CFrame.new(0, 1.75, 0),
			RAINBOW[index * 2]
		)
		top.Material = Enum.Material.Fabric
		top:SetAttribute("Power", Playground.TRAMPOLINE_POWER[index])
		CollectionService:AddTag(top, "AF_Trampoline")
	end
	sign(model, origin * CFrame.new(-12, 0, -8), "🤸")
end

-- Восемь клавиш дугой: наступил — нота. Слева низкие, справа высокие.
function BUILDERS.xylophone(model: Model, origin: CFrame)
	for index = 1, #Playground.NOTE_SPEEDS do
		local t = (index - 4.5) / 8
		local at = origin * CFrame.new(t * 22, 0, math.cos(t * 2) * -4) * CFrame.Angles(0, -t * 0.8, 0)
		local length = 7 - index * 0.35
		local key = part(
			model,
			`Note_{index}`,
			Vector3.new(2.3, 0.5, length),
			at * CFrame.new(0, 0.25, 0),
			RAINBOW[index]
		)
		key.Material = Enum.Material.Neon
		key:SetAttribute("Note", index)
		CollectionService:AddTag(key, "AF_Note")
		part(
			model,
			`NoteBase_{index}`,
			Vector3.new(2.7, 0.3, length + 0.4),
			at * CFrame.new(0, 0.1, 0),
			Color3.fromRGB(240, 240, 235)
		).CanCollide =
			false
	end
	sign(model, origin * CFrame.new(0, 0, 8), "🎵")
end

-- Классики: одна клетка, две рядом, одна, две... Каждая клетка называет своё число.
function BUILDERS.hopscotch(model: Model, origin: CFrame)
	local rows = { { 1 }, { 2, 3 }, { 4 }, { 5, 6 }, { 7 }, { 8, 9 }, { 10 } }
	for row, numbers in rows do
		for column, number in numbers do
			local x = if #numbers == 1 then 0 else (column - 1.5) * 4.4
			local at = origin * CFrame.new(x, 0.15, (row - 4) * 4.2)
			local tile =
				part(model, `Hop_{number}`, Vector3.new(4, 0.3, 4), at, RAINBOW[(number - 1) % #RAINBOW + 1])
			tile:SetAttribute("Number", number)
			CollectionService:AddTag(tile, "AF_Number")

			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Top
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 30
			gui.Parent = tile
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = tostring(number)
			label.TextScaled = true
			label.Font = Enum.Font.FredokaOne
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.3
			label.Parent = gui
		end
	end
	sign(model, origin * CFrame.new(-6, 0, 14), "🔢")
end

-- Песочница с бортиком, мячами и горкой в углу.
function BUILDERS.sandbox(model: Model, origin: CFrame)
	local size = 26
	local sand = part(
		model,
		"Sand",
		Vector3.new(size, 0.4, size),
		origin * CFrame.new(0, 0.2, 0),
		Color3.fromRGB(235, 215, 160)
	)
	sand.Material = Enum.Material.Sand
	for _, side in { -1, 1 } do
		for _, axis in { "x", "z" } do
			local along = if axis == "x" then Vector3.new(1, 1.6, size + 1) else Vector3.new(size + 1, 1.6, 1)
			local offset = if axis == "x"
				then Vector3.new(side * size / 2, 0.8, 0)
				else Vector3.new(0, 0.8, side * size / 2)
			local rim = part(
				model,
				`SandRim_{axis}_{side}`,
				along,
				origin * CFrame.new(offset),
				Color3.fromRGB(190, 140, 90)
			)
			rim.Material = Enum.Material.WoodPlanks
		end
	end

	-- Горка: лесенка сзади, площадка и скат вперёд.
	local slide = origin * CFrame.new(7, 0, -6)
	for step = 1, 5 do
		part(
			model,
			`SlideStep_{step}`,
			Vector3.new(3, 0.5, 1.2),
			slide * CFrame.new(0, step * 1.2, 4 + (5 - step) * 1.2),
			Color3.fromRGB(250, 200, 80)
		)
	end
	part(
		model,
		"SlideTop",
		Vector3.new(3.4, 0.6, 3),
		slide * CFrame.new(0, 6.3, 2),
		Color3.fromRGB(90, 150, 230)
	)
	local ramp = Instance.new("WedgePart")
	ramp.Name = "SlideRamp"
	ramp.Size = Vector3.new(3, 6, 9)
	-- Клин у Roblox высокий сзади (+Z): там и площадка, поворачивать не нужно.
	ramp.CFrame = slide * CFrame.new(0, 3.3, -4)
	ramp.Color = Color3.fromRGB(240, 100, 100)
	ramp.Material = Enum.Material.SmoothPlastic
	ramp.Anchored = true
	ramp.Parent = model

	for index = 1, Playground.BALL_COUNT do
		local ball = part(
			model,
			`Ball_{index}`,
			Vector3.one * 3.2,
			origin * CFrame.new(-6 + (index % 2) * 5, 3, -4 + index * 3),
			RAINBOW[index * 2 - 1]
		)
		ball.Shape = Enum.PartType.Ball
		ball.Anchored = false
		ball.CustomPhysicalProperties = PhysicalProperties.new(0.25, 0.4, 0.6, 1, 1)
		ball:SetAttribute("Home", ball.CFrame)
		CollectionService:AddTag(ball, "AF_Ball")
	end
	sign(model, origin * CFrame.new(-14, 0, 12), "⚽")
end

-- Шарики на ниточках: коснулся — лопнул (у каждого ребёнка свой), потом вырос снова.
function BUILDERS.balloons(model: Model, origin: CFrame)
	local stake = part(
		model,
		"BalloonStake",
		Vector3.new(0.6, 1.2, 0.6),
		origin * CFrame.new(0, 0.6, 0),
		Color3.fromRGB(150, 110, 70)
	)
	stake.CanCollide = false
	for index = 1, Playground.BALLOON_COUNT do
		local angle = index / Playground.BALLOON_COUNT * math.pi * 2
		local height = 5 + (index % 3) * 1.4
		local at = origin * CFrame.new(math.cos(angle) * 3.5, height, math.sin(angle) * 3.5)
		local balloon = part(model, `Balloon_{index}`, Vector3.new(2.4, 2.9, 2.4), at, RAINBOW[index])
		balloon.Shape = Enum.PartType.Ball
		balloon.Material = Enum.Material.Glass
		balloon.Transparency = 0.1
		balloon.CanCollide = false
		CollectionService:AddTag(balloon, "AF_Balloon")

		-- Ниточка от колышка к низу шарика: деталь вытянута по Y, поэтому поворот на четверть.
		local bottom = origin.Position + Vector3.new(0, 1.2, 0)
		local top = at.Position - Vector3.new(0, 1.4, 0)
		local rope = part(
			model,
			`BalloonString_{index}`,
			Vector3.new(0.08, (top - bottom).Magnitude, 0.08),
			CFrame.lookAt((bottom + top) / 2, top) * CFrame.Angles(math.rad(90), 0, 0),
			Color3.fromRGB(240, 240, 240)
		)
		rope.CanCollide = false
		rope.CanTouch = false
		rope.Parent = balloon
	end
	sign(model, origin * CFrame.new(0, 0, 7), "🎈")
end

-- Лабиринт из кустов с флажком в середине.
function BUILDERS.maze(model: Model, origin: CFrame)
	local rows = Playground.MAZE
	local cell = Playground.MAZE_CELL
	local half = (#rows + 1) / 2
	for row, line in rows do
		for column = 1, #line do
			local char = string.sub(line, column, column)
			local at = origin * CFrame.new((column - half) * cell, 0, (row - half) * cell)
			if char == "#" then
				local hedge = part(
					model,
					`Hedge_{row}_{column}`,
					Vector3.new(cell, 5, cell),
					at * CFrame.new(0, 2.5, 0),
					Color3.fromRGB(95, 160, 95)
				)
				hedge.Material = Enum.Material.Grass
			elseif char == "*" then
				part(
					model,
					"MazePole",
					Vector3.new(0.4, 7, 0.4),
					at * CFrame.new(0, 3.5, 0),
					Color3.fromRGB(245, 245, 250)
				).CanCollide =
					false
				local flag = part(
					model,
					"MazeFlag",
					Vector3.new(2.4, 1.5, 0.2),
					at * CFrame.new(1.3, 6.2, 0),
					Color3.fromRGB(245, 120, 90)
				)
				flag.CanCollide = false
				CollectionService:AddTag(flag, "AF_MazeFlag")
			end
		end
	end
	sign(model, origin * CFrame.new(0, 0, (half + 1) * cell), "🌿")
end

-- Мячи, укатившиеся за бортик или упавшие, возвращаются в песочницу.
local function watchBalls(model: Model, origin: CFrame)
	task.spawn(function()
		while model.Parent do
			task.wait(3)
			for _, ball in model:GetChildren() do
				if CollectionService:HasTag(ball, "AF_Ball") and ball:IsA("BasePart") then
					local offset = ball.Position - origin.Position
					if Vector3.new(offset.X, 0, offset.Z).Magnitude > 30 or offset.Y < -20 then
						ball.AssemblyLinearVelocity = Vector3.zero
						ball.CFrame = ball:GetAttribute("Home")
					end
				end
			end
		end
	end)
end

function PlaygroundService.build(parent: Instance): number
	local folder = Instance.new("Folder")
	folder.Name = "Playground"
	folder.Parent = parent

	local built = 0
	for _, spot in Playground.spots do
		local builder = BUILDERS[spot.id]
		assert(builder, `PlaygroundService: нет строителя для "{spot.id}"`)
		local model = Instance.new("Model")
		model.Name = `Play_{spot.id}`
		model.Parent = folder
		local origin = frameOf(spot)
		builder(model, origin)
		if spot.id == "sandbox" then
			watchBalls(model, origin)
		end
		built += 1
	end
	return built
end

PlaygroundService.BUILDERS = BUILDERS

return PlaygroundService
