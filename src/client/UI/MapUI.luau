--!nonstrict
--[[
	Карта «Куда пойти?»: парк сверху, каждое место — кружок со своей картинкой.

	Зачем. На проверке 24.09.2026 тестер прошёл площадь и сказал «больше ничего
	не вижу», хотя за изгородью площади стоит парк на двадцать с лишним мест.
	Задания дня ведут в одно место в день; карта — вторая дверь: всё сразу,
	на своих местах, и тап по любому — стрелка до него (docs/17-CONTENT-PLAN.md § 7.3).

	Для нечитающего ребёнка главное — картинки: 🎡, 🦢, 🌱. Название места
	появляется внизу для взрослого. Место из задания дня пульсирует золотом,
	красная стрелка — «ты здесь», и смотрит туда же, куда ребёнок.

	Одна и та же карта рисуется в окне (кнопка 🗺 в HUD) и на доске у точки
	появления (Controllers/MapController) — чтобы ребёнок узнал её в окне.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Base = require(Shared.Config.Base)
local Decor = require(Shared.Config.Decor)
local Playground = require(Shared.Config.Playground)

local CloseButton = require(script.Parent.CloseButton)

local MapUI = {}

export type Place = {
	id: string,
	icon: string,
	title: string,
	position: Vector3,
}

local player = Players.LocalPlayer

-- Сколько студов от центра площади помещается в радиус карты: парк и кольцо домов.
local WORLD_RADIUS = Base.RING_RADIUS + 18
local GRASS = Color3.fromRGB(128, 196, 104)
local GRASS_DARK = Color3.fromRGB(98, 168, 86)
local PLAZA = Color3.fromRGB(240, 222, 186)
local PATH = Color3.fromRGB(226, 204, 164)
local WOOD = Color3.fromRGB(150, 104, 66)
local GOLD = Color3.fromRGB(255, 205, 80)
local INK = Color3.fromRGB(60, 50, 40)

local gui: ScreenGui? = nil
local caption: TextLabel? = nil
local follow: RBXScriptConnection? = nil
local onPick: ((Place) -> ())? = nil
local home: Vector3? = nil
local questSpots: { [string]: boolean } = {}

local function corner(object: GuiObject, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = object
end

local function stroke(object: GuiObject, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = object
	return s
end

--[[
	Площадь на карте крупнее, чем в жизни: порталы, магазин и пады стоят на ней
	тесно, и в честном масштабе их кружки слипались бы в один. Первые INNER студов
	от центра занимают INNER_SHARE радиуса карты, остальное — парк и дома.
]]
local INNER = 60
local INNER_SHARE = 0.3

-- Расстояние от центра площади → доля радиуса карты.
local function radial(distance: number): number
	if distance <= INNER then
		return distance / INNER * INNER_SHARE
	end
	return INNER_SHARE + (distance - INNER) / (WORLD_RADIUS - INNER) * (1 - INNER_SHARE)
end

-- Мир → доля карты: +X вправо, −Z вверх (так ребёнок стоит при появлении — лицом к порталам).
local function toMap(position: Vector3): UDim2
	local flat = Vector2.new(position.X, position.Z)
	local distance = flat.Magnitude
	local at = if distance > 0.001 then flat.Unit * radial(distance) * 0.5 else Vector2.zero
	return UDim2.fromScale(0.5 + at.X, 0.5 + at.Y)
end

local function disc(parent: Instance, name: string, center: Vector3, radius: number, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = toMap(center)
	-- Размер — по масштабу того места, где стоит круг: у площади крупнее, в парке мельче.
	local distance = Vector2.new(center.X, center.Z).Magnitude
	local scale = if distance <= INNER
		then INNER_SHARE / INNER
		else (1 - INNER_SHARE) / (WORLD_RADIUS - INNER)
	f.Size = UDim2.fromScale(radius * scale, radius * scale)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	corner(f, 0.5)
	return f
end

-- «🎈 Шарики» → «🎈», «Шарики»: картинка — всё до первого пробела.
local function splitTitle(title: string): (string, string)
	local icon, rest = string.match(title, "^(%S+)%s+(.+)$")
	return icon or "📍", rest or title
end

-- Все места карты: уголки парка, порталы, магазин и свой дом, если он уже выдан.
function MapUI.places(): { Place }
	local list: { Place } = {}
	for _, spot in Playground.spots do
		local icon, title = splitTitle(spot.title)
		local position = Playground.position(spot)
		table.insert(list, {
			id = `spot:{spot.id}`,
			icon = icon,
			title = title,
			position = Vector3.new(position.X, Decor.groundY(position.X, position.Z), position.Z),
		})
	end
	table.insert(list, {
		id = "portal:letters",
		icon = "📖",
		title = "Мир букв",
		position = Vector3.new(-16, 1.6, -6),
	})
	table.insert(list, {
		id = "portal:math",
		icon = "🔢",
		title = "Мир чисел",
		position = Vector3.new(16, 1.6, -6),
	})
	table.insert(list, {
		id = "shop",
		icon = "🛍",
		title = "Магазин",
		position = Base.padPosition(Base.PAD_SLOTS) + Vector3.new(0, 1.6, 0),
	})
	if home then
		table.insert(list, { id = "home", icon = "🏠", title = "Мой дом", position = home })
	end
	return list
end

--[[
	Рисует карту в квадратный frame: трава, площадь, дорожки к домам, озеро,
	дома по кругу и кружки мест. interactive — кружки нажимаются (окно);
	на доске в мире — только картинка. Возвращает кружки по id места.
]]
function MapUI.draw(frame: GuiObject, interactive: boolean, pick: ((Place) -> ())?): { [string]: GuiObject }
	local map = Instance.new("Frame")
	map.Name = "Map"
	map.Size = UDim2.fromScale(1, 1)
	map.BackgroundColor3 = GRASS
	map.BorderSizePixel = 0
	map.ClipsDescendants = false
	map.Parent = frame
	corner(map, 0.5)
	stroke(map, WOOD, 6)
	local shade = Instance.new("UIGradient")
	shade.Color = ColorSequence.new(GRASS, GRASS_DARK)
	shade.Rotation = 90
	shade.Parent = map

	-- Дорожки от площади к домам — крест из светлых полос.
	for index = 0, 1 do
		local strip = Instance.new("Frame")
		strip.Name = "Path"
		strip.AnchorPoint = Vector2.new(0.5, 0.5)
		strip.Position = UDim2.fromScale(0.5, 0.5)
		strip.Size = if index == 0 then UDim2.fromScale(0.96, 0.03) else UDim2.fromScale(0.03, 0.96)
		strip.BackgroundColor3 = PATH
		strip.BorderSizePixel = 0
		strip.Parent = map
	end
	disc(map, "Plaza", Vector3.zero, Base.PLAZA_RADIUS, PLAZA)
	disc(map, "Fountain", Vector3.new(0, 0, -34), 5, Color3.fromRGB(120, 190, 235))
	local lake = Playground.expect("lake")
	disc(map, "Lake", Playground.position(lake), lake.radius * 0.9, Color3.fromRGB(110, 185, 235))

	-- Дома по кругу: маленькие крыши. Свой — крупнее, с флажком.
	for index = 1, Base.PLOT_COUNT do
		local at = Base.plotPosition(index)
		local roof = Instance.new("TextLabel")
		roof.Name = "Plot"
		roof.AnchorPoint = Vector2.new(0.5, 0.5)
		roof.Position = toMap(at)
		roof.Size = UDim2.fromScale(0.035, 0.035)
		roof.BackgroundTransparency = 1
		roof.Text = "🏡"
		roof.TextScaled = true
		roof.TextTransparency = 0.35
		roof.Parent = map
	end

	local pins: { [string]: GuiObject } = {}
	for _, place in MapUI.places() do
		local pin = Instance.new(if interactive then "TextButton" else "TextLabel")
		pin.Name = place.id
		pin.AnchorPoint = Vector2.new(0.5, 0.5)
		pin.Position = toMap(place.position)
		local big = place.id == "home" or string.sub(place.id, 1, 7) == "portal:"
		local size = if big then 0.085 else 0.072
		pin.Size = UDim2.fromScale(size, size)
		pin.BackgroundColor3 = Color3.fromRGB(255, 252, 240)
		pin.Text = place.icon
		pin.TextScaled = true
		pin.Font = Enum.Font.FredokaOne
		pin.ZIndex = 3
		pin.Parent = map
		corner(pin, 0.5)
		stroke(pin, if place.id == "home" then Color3.fromRGB(230, 90, 80) else WOOD, 2)
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0.14, 0)
		padding.PaddingBottom = UDim.new(0.14, 0)
		padding.PaddingLeft = UDim.new(0.14, 0)
		padding.PaddingRight = UDim.new(0.14, 0)
		padding.Parent = pin
		if interactive and pick then
			local button = pin :: TextButton
			button.Activated:Connect(function()
				pick(place)
			end)
			button.MouseEnter:Connect(function()
				if caption then
					caption.Text = `{place.icon} {place.title}`
				end
			end)
		end
		pins[place.id] = pin
	end
	return pins
end

-- Место из задания дня: золотое кольцо, которое дышит.
local function markQuest(pin: GuiObject)
	local ring = Instance.new("Frame")
	ring.Name = "QuestRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = pin.Position
	ring.Size = UDim2.fromScale(pin.Size.X.Scale * 1.5, pin.Size.Y.Scale * 1.5)
	ring.BackgroundColor3 = GOLD
	ring.BackgroundTransparency = 0.35
	ring.ZIndex = 2
	ring.Parent = pin.Parent
	corner(ring, 0.5)
	TweenService
		:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Size = UDim2.fromScale(pin.Size.X.Scale * 1.9, pin.Size.Y.Scale * 1.9),
			BackgroundTransparency = 0.7,
		})
		:Play()
	local star = Instance.new("TextLabel")
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.Position = UDim2.new(
		pin.Position.X.Scale + pin.Size.X.Scale * 0.45,
		0,
		pin.Position.Y.Scale - pin.Size.Y.Scale * 0.45,
		0
	)
	star.Size = UDim2.fromScale(pin.Size.X.Scale * 0.55, pin.Size.Y.Scale * 0.55)
	star.BackgroundTransparency = 1
	star.Text = "⭐"
	star.TextScaled = true
	star.ZIndex = 4
	star.Parent = pin.Parent
end

function MapUI.isOpen(): boolean
	return gui ~= nil
end

function MapUI.close()
	if follow then
		follow:Disconnect()
		follow = nil
	end
	if gui then
		gui:Destroy()
		gui = nil
	end
	caption = nil
end

function MapUI.open()
	MapUI.close()
	local screen = Instance.new("ScreenGui")
	screen.Name = "AlphabetFallMap"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	-- Подложка ловит нажатия мимо карты: ничего не нажимается сквозь неё.
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Parent = screen
	dim.Activated:Connect(MapUI.close)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.52)
	panel.Size = UDim2.fromScale(0.62, 0.9)
	panel.BackgroundColor3 = Color3.fromRGB(252, 240, 210)
	panel.Parent = screen
	corner(panel, 0.06)
	stroke(panel, WOOD, 5)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 0.86
	ratio.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.8, 0.08)
	title.Position = UDim2.fromScale(0.1, 0.015)
	title.BackgroundTransparency = 1
	title.Text = "🗺 Куда пойти?"
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = INK
	title.Parent = panel

	local holder = Instance.new("Frame")
	holder.Name = "MapHolder"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.fromScale(0.5, 0.105)
	holder.Size = UDim2.fromScale(0.94, 0.94 * 0.86)
	holder.BackgroundTransparency = 1
	holder.Parent = panel

	local label = Instance.new("TextLabel")
	label.Name = "Caption"
	label.Size = UDim2.fromScale(0.9, 0.065)
	label.Position = UDim2.fromScale(0.05, 0.92)
	label.BackgroundTransparency = 1
	label.Text = "Нажми на картинку — покажу дорогу"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(120, 95, 70)
	label.Parent = panel
	caption = label

	local pins = MapUI.draw(holder, true, function(place)
		MapUI.close()
		if onPick then
			onPick(place)
		end
	end)
	for spotId in questSpots do
		local pin = pins[`spot:{spotId}`]
		if pin then
			markQuest(pin)
		end
	end

	-- «Ты здесь»: красная стрелка смотрит туда же, куда ребёнок.
	local map = holder:FindFirstChild("Map")
	local you = Instance.new("TextLabel")
	you.Name = "You"
	you.AnchorPoint = Vector2.new(0.5, 0.5)
	you.Size = UDim2.fromScale(0.085, 0.085)
	you.BackgroundTransparency = 1
	you.Text = "▲"
	you.TextScaled = true
	you.Font = Enum.Font.GothamBlack
	you.TextColor3 = Color3.fromRGB(235, 60, 60)
	you.TextStrokeColor3 = Color3.new(1, 1, 1)
	you.TextStrokeTransparency = 0
	you.ZIndex = 6
	you.Parent = map
	local function place()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			you.Visible = true
			you.Position = toMap(root.Position)
			local look = root.CFrame.LookVector
			you.Rotation = math.deg(math.atan2(look.X, -look.Z))
		else
			you.Visible = false
		end
	end
	place()
	follow = RunService.Heartbeat:Connect(place)

	CloseButton.make(panel, 44, UDim2.new(1, -52, 0, 8)).Activated:Connect(MapUI.close)

	panel.Size = UDim2.fromScale(0.5, 0.72)
	TweenService
		:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromScale(0.62, 0.9) })
		:Play()
end

function MapUI.toggle()
	if gui then
		MapUI.close()
	else
		MapUI.open()
	end
end

function MapUI.build(callbacks: { onPick: (Place) -> () })
	onPick = callbacks.onPick
end

-- Свой участок: сервер выдаёт его после входа (событие BaseAssigned).
function MapUI.setHome(position: Vector3)
	home = position
end

-- Уголки парка из сегодняшних невыполненных заданий: их кружки горят золотом.
function MapUI.setQuestSpots(spots: { [string]: boolean })
	questSpots = spots
end

return MapUI
