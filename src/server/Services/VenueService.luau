--!nonstrict
--[[
	Локации занятий: строит поляны и переносит на них ребёнка.

	Правило простое и общее: **одно задание — одна локация** (Config/Venues).
	Пад на площади — дверь, а не сцена. Занятие разворачивается на своей поляне,
	где нет ни порталов, ни домов, ни чужих падов, и потому ничто не закрывает
	ни весы, ни лестницу, ни падающие буквы.

	Сервис ничего не знает про сами испытания: он подписан на те же хуки, что
	и туннель (ChallengeService.onStarted / onFinished), и работает только
	с теми id, для которых в конфиге заведена поляна.

	Сцену строит клиент — контроллер испытания. Точку сцены он получает
	в самом задании (`spec.params.stage`), а не вычисляет от своего персонажа:
	иначе сцена успевала собраться на площади раньше, чем ребёнка перенесло.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Venues = require(Shared.Config.Venues)

local ChallengeService = require(script.Parent.ChallengeService)
local DecorService = require(script.Parent.DecorService)
local VenueThemes = require(script.Parent.Parent.World.VenueThemes)
local Teleport = require(script.Parent.Parent.World.Teleport)

local VenueService = {}

local container: Folder? = nil
-- Откуда ребёнка увели: куда вернуть, если занятие оборвалось.
local returnOf: { [Player]: CFrame } = {}

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
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

local function sign(parent: Instance, at: CFrame, text: string, color: Color3)
	local board = part("VenueSign", Vector3.new(16, 3, 0.8), at, color, parent)
	board.CanCollide = false

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Title"
	--[[
		В студах и не поверх всего. Пиксельная надпись держала размер на экране:
		вблизи, когда ребёнок стоит в задании, она разрасталась и ложилась поверх
		падающих букв и пузырей («Берег Пузырей» прямо по «Б» и «В»).
	]]
	billboard.Size = UDim2.fromScale(34, 8)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 220
	billboard.Parent = board

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(40, 32, 60)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard
end

--[[
	Растительность по краю поляны. Стоит не как попало: восемь мест по кругу,
	набор эскизов повторяется по очереди. Поляна должна читаться как место,
	а не как платформа в пустоте, но и заслонять задание ей нельзя —
	поэтому весь декор жмётся к бордюру.
]]
local function buildDecor(parent: Instance, center: Vector3, venue)
	local radius = Venues.SIZE / 2 - 5
	for slot = 1, 8 do
		local id = venue.decor[(slot - 1) % #venue.decor + 1]
		local model = DecorService.modelFor(id)
		if model then
			local angle = (slot - 1) / 8 * math.pi * 2 + math.pi / 8
			local spot = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			model.Name = `{id}_{slot}`
			model.Parent = parent
			model:PivotTo(CFrame.new(spot) * CFrame.Angles(0, angle, 0))

			--[[
				Эскиз строится от нуля по Y, поэтому его надо посадить на пол
				поляны: она висит на своей высоте, а не на нулевой земле.
			]]
			local box, size = model:GetBoundingBox()
			local bottom = box.Position.Y - size.Y / 2
			model:PivotTo(model:GetPivot() + Vector3.new(0, spot.Y - bottom, 0))

			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
				end
			end
		end
	end
end

local function buildVenue(parent: Instance, venue)
	local center = Venues.center(venue.id)
	local model = Instance.new("Model")
	model.Name = `Venue_{venue.id}`
	model.Parent = parent

	local half = Venues.SIZE / 2

	local floor = part(
		"Floor",
		Vector3.new(Venues.SIZE, Venues.FLOOR_THICKNESS, Venues.SIZE),
		CFrame.new(center - Vector3.new(0, Venues.FLOOR_THICKNESS / 2, 0)),
		venue.ground,
		model
	)
	floor.Material = Enum.Material.Grass

	--[[
		Вместо цветных стен — оформление по теме поляны и невидимая ограда
		по краю (World/VenueThemes): упасть с поляны нельзя ни с одной стороны,
		падений и смертей в этой игре нет нигде.
	]]
	VenueThemes.build(model, center, venue, Venues.order(venue.id) * 7919)

	-- Табличка сбоку от задника: посередине она закрывала вершину Горы Алфавита.
	sign(model, CFrame.new(center + Vector3.new(-(half - 14), 16, -(half - 4))), venue.title, venue.accent)
	buildDecor(model, center, venue)

	return model
end

function VenueService.build()
	local folder = Instance.new("Folder")
	folder.Name = "Venues"
	folder.Parent = workspace
	container = folder

	for _, venue in Venues.all do
		buildVenue(folder, venue)
	end

	print(`[Venues] построено локаций: {Venues.count()}`)
end

--[[
	Куда вернуть ребёнка, если занятие оборвалось (вышло время, нажал 🏠).

	Обычный конец занятия обслуживает WorldService: он ставит ребёнка к тому
	паду, с которого тот ушёл. Здесь только страховка — чтобы никто не остался
	стоять на пустой поляне.
]]
local function returnHome(player: Player)
	local back = returnOf[player]
	returnOf[player] = nil
	local character = player.Character
	if back and character then
		Teleport.to(player, back)
	end
end

function VenueService.start()
	VenueService.build()

	ChallengeService.onStarted(function(player: Player, spec: any)
		local venue = Venues.get(spec.challengeId)
		if not venue then
			return
		end

		local character = player.Character
		if not character then
			return
		end

		--[[
			Точка сцены уходит в самом задании: хук вызывается ДО отправки
			задания клиенту, поэтому дописать её сюда можно и нужно.
		]]
		spec.params.stage = Venues.stage(venue.id)

		returnOf[player] = character:GetPivot()
		Teleport.to(player, Venues.entry(venue.id))
	end)

	ChallengeService.onFinished(function(player: Player, spec: any)
		if Venues.get(spec.challengeId) then
			returnHome(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		returnOf[player] = nil
	end)
end

function VenueService.container(): Folder?
	return container
end

return VenueService
