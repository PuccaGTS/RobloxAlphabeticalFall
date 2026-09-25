--!nonstrict
--[[
	Азбучная грядка у калитки своего участка (Logic/LetterGarden).

	Деревянный ящик с землёй справа от калитки — почтовый ящик слева, — три
	лунки. Хозяин наступил на пустую лунку — посадил букву: голос называет её,
	над лункой табличка. Потом росток, потом цветок цвета буквы с картинкой
	в серединке. Наступил на цветок — урожай: голос, звёзды, лунка пустеет.

	Грядка живёт отдельно от модели участка (BaseService перестраивает её
	целиком при каждой стройке), в workspace.LetterGardens, и перерисовывается
	только когда что-то выросло, посажено или собрано. Трогать чужую грядку
	нельзя: сажает и собирает только хозяин.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Letters = require(Shared.Config.Letters)
local LetterGarden = require(Shared.Logic.LetterGarden)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local EconomyService = require(script.Parent.EconomyService)
local BaseService = require(script.Parent.BaseService)

local GardenService = {}

-- Справа от калитки, за забором со стороны площади (−Z участка).
local OFFSET = CFrame.new(11.5, 1, -36.5)
local SLOT_STEP = 2.8
local STEP_RADIUS = 1.4

local WOOD = Color3.fromRGB(165, 118, 72)
local SOIL = Color3.fromRGB(105, 72, 50)
local STEM = Color3.fromRGB(95, 165, 75)
local LEAF = Color3.fromRGB(120, 195, 90)

type Garden = { model: Model, plot: number, signature: string }

local gardens: { [Player]: Garden } = {}
local standing: { [Player]: number? } = {}
local hooks: { (Player, string) -> () } = {}
local folder: Folder? = nil

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): BasePart
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

local function ghost(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Сплюснутый шар: лист и лепесток. Форма Ball берёт размер по меньшей стороне, а сетка-сфера — нет.
local function oval(p: BasePart)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
end

local function billboard(parent: BasePart, text: string, size: number, offset: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(size, size)
	gui.StudsOffset = Vector3.new(0, offset, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.fromRGB(50, 40, 30)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	return label
end

-- Выученные буквы по алфавиту: из них сажается следующая.
local function learned(profile): { string }
	local list = {}
	for _, id in Letters.ordered() do
		local progress = profile.letters and profile.letters[id]
		if typeof(progress) == "table" and (tonumber(progress.mastery) or 0) >= 1 then
			table.insert(list, id)
		end
	end
	return list
end

local function slotFrame(plotFrame: CFrame, index: number): CFrame
	return plotFrame * OFFSET * CFrame.new((index - (LetterGarden.BEDS + 1) / 2) * SLOT_STEP, 0, 0)
end

-- Табличка-буква на палочке: у семечка и ростка видно, что посажено.
local function tag(parent: Instance, at: CFrame, letterId: string)
	local letter = Letters.expect(letterId)
	ghost(part(parent, "TagStick", Vector3.new(0.12, 1.4, 0.12), at * CFrame.new(0.7, 0.7, 0.5), WOOD))
	local plate = ghost(
		part(
			parent,
			"TagPlate",
			Vector3.new(0.9, 0.7, 0.1),
			at * CFrame.new(0.7, 1.45, 0.5),
			Color3.fromRGB(250, 245, 230)
		)
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.Parent = plate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = letter.glyph
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = letter.color
	label.Parent = gui
end

local function renderSlot(parent: Instance, at: CFrame, bed: LetterGarden.Bed, now: number, index: number)
	local stage = LetterGarden.stage(bed, now)
	local slot = Instance.new("Model")
	slot.Name = `Slot_{index}`
	slot:SetAttribute("Stage", stage)
	slot.Parent = parent
	-- Лунка: тёмный кружок в земле.
	local hole = ghost(
		part(
			slot,
			"Hole",
			Vector3.new(0.1, 1.6, 1.6),
			at * CFrame.new(0, 0.02, 0) * CFrame.Angles(0, 0, math.pi / 2),
			SOIL:Lerp(Color3.new(0, 0, 0), 0.3)
		)
	)
	hole.Shape = Enum.PartType.Cylinder

	if stage == "empty" then
		-- Подсказка «посади!»: росточек над пустой лункой.
		local hint = ghost(part(slot, "Hint", Vector3.new(0.3, 0.3, 0.3), at * CFrame.new(0, 1.2, 0), STEM))
		hint.Transparency = 1
		billboard(hint, "🌱", 1.6, 0)
		return
	end
	local letterId = bed.letterId :: string
	local letter = Letters.expect(letterId)
	if stage == "seed" then
		local mound = ghost(part(slot, "Mound", Vector3.new(1.3, 0.6, 1.3), at * CFrame.new(0, 0.1, 0), SOIL))
		mound.Shape = Enum.PartType.Ball
		tag(slot, at, letterId)
		return
	end
	if stage == "sprout" then
		ghost(part(slot, "Stem", Vector3.new(0.18, 1.3, 0.18), at * CFrame.new(0, 0.65, 0), STEM))
		for _, side in { -1, 1 } do
			local leaf = ghost(
				part(
					slot,
					`Leaf_{side}`,
					Vector3.new(0.8, 0.12, 0.45),
					at * CFrame.new(side * 0.4, 1.1, 0) * CFrame.Angles(0, 0, math.rad(side * 25)),
					LEAF
				)
			)
			oval(leaf)
		end
		tag(slot, at, letterId)
		return
	end

	-- Цветок: стебель, листья, лепестки цвета буквы, серединка — картинка к букве.
	ghost(part(slot, "Stem", Vector3.new(0.22, 2.6, 0.22), at * CFrame.new(0, 1.3, 0), STEM))
	for _, side in { -1, 1 } do
		local leaf = ghost(
			part(
				slot,
				`Leaf_{side}`,
				Vector3.new(1.1, 0.14, 0.55),
				at * CFrame.new(side * 0.55, 1, 0) * CFrame.Angles(0, 0, math.rad(side * 25)),
				LEAF
			)
		)
		oval(leaf)
	end
	-- Цветок смотрит к калитке и на дорожку (−Z участка): его видно, подходя к дому.
	local head = at * CFrame.new(0, 2.9, 0)
	for petal = 1, 6 do
		local angle = petal / 6 * math.pi * 2
		local p = ghost(
			part(
				slot,
				`Petal_{petal}`,
				Vector3.new(1.1, 0.7, 0.2),
				head
					* CFrame.new(math.cos(angle) * 0.8, math.sin(angle) * 0.8, -0.05)
					* CFrame.Angles(0, 0, angle),
				letter.color:Lerp(Color3.new(1, 1, 1), 0.25)
			)
		)
		oval(p)
	end
	local middle = ghost(
		part(
			slot,
			"Middle",
			Vector3.new(0.3, 1.2, 1.2),
			head * CFrame.new(0, 0, -0.15) * CFrame.Angles(0, math.pi / 2, 0),
			Color3.fromRGB(255, 225, 110)
		)
	)
	middle.Shape = Enum.PartType.Cylinder
	billboard(middle, letter.picture or letter.glyph, 1.8, 1.9)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 235, 140))
	sparkle.Size = NumberSequence.new(0.4, 0)
	sparkle.Lifetime = NumberRange.new(0.7, 1.2)
	sparkle.Rate = 4
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Parent = middle
	tag(slot, at, letterId)
end

local function signatureOf(state: LetterGarden.State, now: number): string
	local parts = {}
	for index, bed in state.beds do
		parts[index] = `{bed.letterId or "-"}:{LetterGarden.stage(bed, now)}`
	end
	return table.concat(parts, ",")
end

local function render(player: Player, force: boolean?)
	local plot = BaseService.plotOf(player)
	local profile = ProfileService.get(player)
	local existing = gardens[player]
	if not plot or not profile or not folder then
		if existing then
			existing.model:Destroy()
			gardens[player] = nil
		end
		return
	end
	local state = LetterGarden.sanitize(profile.garden)
	local now = os.time()
	local signature = signatureOf(state, now)
	if existing and existing.plot == plot.index and existing.signature == signature and not force then
		return
	end
	if existing then
		existing.model:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = `LetterGarden_{plot.index}`
	model:SetAttribute("Owner", player.UserId)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local at = plot.cframe * OFFSET
	local box = part(
		model,
		"Box",
		Vector3.new(LetterGarden.BEDS * SLOT_STEP + 1, 0.8, 3),
		at * CFrame.new(0, 0.4, 0),
		WOOD
	)
	box.Material = Enum.Material.WoodPlanks
	local soil = part(
		model,
		"Soil",
		Vector3.new(LetterGarden.BEDS * SLOT_STEP + 0.4, 0.1, 2.4),
		at * CFrame.new(0, 0.82, 0),
		SOIL
	)
	soil.Material = Enum.Material.Ground
	local post = ghost(
		part(
			model,
			"SignPost",
			Vector3.new(0.3, 3, 0.3),
			at * CFrame.new(LetterGarden.BEDS * SLOT_STEP / 2 + 1.2, 1.5, -0.6),
			WOOD
		)
	)
	local board = ghost(
		part(
			model,
			"SignBoard",
			Vector3.new(3.4, 1.2, 0.2),
			post.CFrame * CFrame.new(0, 1.3, 0),
			Color3.fromRGB(250, 240, 215)
		)
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "🌱 Грядка букв"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(80, 60, 40)
	label.Parent = gui

	for index, bed in state.beds do
		renderSlot(model, slotFrame(plot.cframe, index) * CFrame.new(0, 0.87, 0), bed, now, index)
	end
	CollectionService:AddTag(model, "AF_LetterGarden")
	model.Parent = folder
	gardens[player] = { model = model, plot = plot.index, signature = signature }
end

local function notify(player: Player, payload)
	RemoteDefs.event("OpenUI"):FireClient(player, "garden", payload)
end

-- Хозяин наступил на лунку index: посадить, собрать или сказать, сколько ждать.
local function stepOn(player: Player, index: number)
	local profile = ProfileService.get(player)
	if not profile then
		return
	end
	local now = os.time()
	local state = LetterGarden.sanitize(profile.garden)
	local bed = state.beds[index]
	local stage = LetterGarden.stage(bed, now)
	if stage == "empty" then
		local planted: string? = nil
		ProfileService.update(player, function(p)
			p.garden, planted = LetterGarden.plant(p.garden, index, learned(p), now)
		end)
		if planted then
			local letter = Letters.expect(planted)
			RemoteDefs.event("PlayVO"):FireClient(player, letter.vo.name)
			RemoteDefs.event("PlaySfx"):FireClient(player, "tap")
			notify(
				player,
				{ state = "planted", letterId = planted, minutes = math.ceil(LetterGarden.BLOOM / 60) }
			)
			for _, hook in hooks do
				task.spawn(hook, player, "plant")
			end
		end
	elseif stage == "bloom" then
		local harvested: string? = nil
		ProfileService.update(player, function(p)
			p.garden, harvested = LetterGarden.harvest(p.garden, index, now)
		end)
		if harvested then
			local letter = Letters.expect(harvested)
			local awarded =
				EconomyService.award(player, "garden_harvest", Economy.REWARDS.gardenHarvest, harvested)
			RemoteDefs.event("PlayVO"):FireClient(player, letter.vo.name)
			RemoteDefs.event("PlaySfx"):FireClient(player, "reward")
			notify(player, { state = "harvest", letterId = harvested, awarded = awarded })
			for _, hook in hooks do
				task.spawn(hook, player, "harvest")
			end
		end
	else
		notify(
			player,
			{ state = "wait", letterId = bed.letterId, minutes = math.ceil(LetterGarden.left(bed, now) / 60) }
		)
	end
	render(player)
end

-- На какой лунке своей грядки стоит ребёнок (nil — ни на какой).
local function slotUnder(player: Player): number?
	local plot = BaseService.plotOf(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not plot or not root then
		return nil
	end
	for index = 1, LetterGarden.BEDS do
		local at = slotFrame(plot.cframe, index)
		local offset = at:PointToObjectSpace(root.Position)
		if Vector2.new(offset.X, offset.Z).Magnitude < STEP_RADIUS and offset.Y > 0 and offset.Y < 6 then
			return index
		end
	end
	return nil
end

-- Грядка на участке игрока: куда ведёт стрелка задания «посади букву».
function GardenService.position(player: Player): Vector3?
	local plot = BaseService.plotOf(player)
	return if plot then (plot.cframe * OFFSET).Position else nil
end

-- Посадил или собрал (для заданий дня): hook(player, "plant" | "harvest").
function GardenService.onAction(hook: (Player, string) -> ())
	table.insert(hooks, hook)
end

GardenService.render = render
GardenService.stepOn = stepOn

function GardenService.start()
	local created = Instance.new("Folder")
	created.Name = "LetterGardens"
	created.Parent = workspace
	folder = created

	Players.PlayerRemoving:Connect(function(player: Player)
		local garden = gardens[player]
		if garden then
			garden.model:Destroy()
		end
		gardens[player] = nil
		standing[player] = nil
	end)

	-- Шаги: садимся, только когда на лунку ВОШЛИ, — стоящий не сажает без конца.
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in Players:GetPlayers() do
				local index = slotUnder(player)
				if index and index ~= standing[player] then
					task.spawn(stepOn, player, index)
				end
				standing[player] = index
			end
		end
	end)
	-- Раз в пять секунд: участок выдан или сменился, что-то проросло. Без перемен — не перестраиваем.
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				pcall(render, player)
			end
			task.wait(5)
		end
	end)
end

return GardenService
