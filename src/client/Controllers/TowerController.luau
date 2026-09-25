--!nonstrict
--[[
	Азбучная Башня — «зачем она нужна».

	Три ответа, и все три должны читаться ребёнком без объяснений взрослого:

	1. Это ВИТРИНА. Видно, сколько букв уже твои: серые — незнакомые, светящиеся —
	   освоенные. Ребёнок 5 лет не понимает процентов и прогресс-баров,
	   но прекрасно понимает «вот эти уже мои, а эти ещё нет».
	2. Это ЦЕЛЬ. Башню видно с любой точки площади, и она достраивается сама
	   по мере обучения — ради этого возвращаются.
	3. Это ПОВТОРЕНИЕ. Тап по букве называет её: «Буква М». Бесплатно, без испытания
	   и без награды — просто подошёл и послушал. Ровно то повторение, ради которого
	   существует планировщик (docs/02-LEARNING.md § 5).

	Башня строится на клиенте: она у каждого своя, один общий объект в мире так не умеет.

	Стоит она НЕ в центре карты, а во дворе ребёнка: сервер выдаёт участок и присылает
	место под Башню (docs/15-HOME-BASE.md § 4). Витрина обучения — часть «моего двора»,
	а не памятник на площади, и соседям её тоже видно.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Base = require(Shared.Config.Base)
local Pets = require(Shared.Logic.Pets)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local AudioController = require(script.Parent.AudioController)

local TowerController = {}

-- Пока участок не выдан, Башне стоять негде: место приходит с сервера.
local basePosition: Vector3? = nil
--[[
	Башня — спираль: буквы-монетки вьются вокруг колонны по шесть на виток,
	как ступени винтовой лестницы. Раньше это были 33 серых бруска друг на друге
	высотой в 80 студов — издалека тонкая макаронина, вблизи буквы наезжали друг
	на друга. Спираль вдвое ниже, буквы расходятся по кругу, а те, что с обратной
	стороны, закрывает сама колонна.
]]
local COIN_RADIUS = 3 -- от оси колонны до монетки
local COIN_SIZE = Vector3.new(0.5, 2.4, 2.4) -- цилиндр лежит вдоль X: X — толщина
local LETTERS_PER_TURN = 6
local RISE = 1 -- на сколько выше каждая следующая буква
local FIRST_HEIGHT = 2.6 -- первая буква над землёй
local FOLDER_NAME = "AlphabetTower"

local COLOR_LOCKED = Color3.fromRGB(170, 172, 185)
local GOLD = Color3.fromRGB(255, 205, 90)
local CREAM = Color3.fromRGB(250, 240, 220)

local segments: { [string]: BasePart } = {}
local rings: { [string]: BasePart } = {}
local labels: { [string]: TextLabel } = {}
local star: BasePart? = nil
local folder: Folder? = nil
local counter: TextLabel? = nil
local lastSnapshot: any = nil

--[[
	Картинка к букве всплывает над сегментом и тает: коснулся А — вылетел арбуз.
	Башня сама по себе только называет букву; картинка даёт ей предмет, за который
	память цепляется лучше голой буквы. Одна на сегмент: частые тапы не копят стопку.
]]
local function showPicture(part: BasePart, letter: any)
	if letter.picture == "" or part:FindFirstChild("Picture") then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Picture"
	-- Студы, не пиксели: картинка размером с сегмент на любом расстоянии.
	billboard.Size = UDim2.fromScale(4, 4)
	billboard.StudsOffset = Vector3.new(0, 1, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = letter.picture
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard

	local info = TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, info, { StudsOffset = Vector3.new(3.5, 5, 0) }):Play()
	local fade = TweenService:Create(
		label,
		TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 1.1),
		{
			TextTransparency = 1,
		}
	)
	fade.Completed:Connect(function()
		billboard:Destroy()
	end)
	fade:Play()
end

-- Земля под Башней: сервер присылает точку на 2.6 студа выше пола участка.
local function groundOf(position: Vector3): Vector3
	return position - Vector3.new(0, 2.6, 0)
end

local function towerPart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Стоячий цилиндр: у детали ось цилиндра — X, ставим её вертикально.
local function column(
	name: string,
	height: number,
	diameter: number,
	center: Vector3,
	color: Color3,
	parent: Instance
)
	local part = towerPart(
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		parent
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Кадр монетки: ось цилиндра (локальная X) смотрит от колонны наружу.
local function coinFrame(index: number, lift: number): CFrame
	local ground = groundOf(basePosition or Vector3.zero)
	local angle = (index - 1) / LETTERS_PER_TURN * math.pi * 2
	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local position = ground
		+ Vector3.new(0, FIRST_HEIGHT + (index - 1) * RISE, 0)
		+ outward * (COIN_RADIUS + lift)
	return CFrame.lookAt(position, position + outward) * CFrame.Angles(0, math.pi / 2, 0)
end

local function buildSegment(letterId: string, index: number, parent: Instance): BasePart
	local letter = Letters.expect(letterId)

	-- Ободок за монеткой: у освоенной буквы он светится её цветом.
	local ring = towerPart(
		`Ring_{letterId}`,
		Vector3.new(0.3, COIN_SIZE.Y + 0.5, COIN_SIZE.Z + 0.5),
		coinFrame(index, -0.2),
		CREAM,
		parent
	)
	ring.Shape = Enum.PartType.Cylinder
	rings[letterId] = ring

	local part = towerPart(`Segment_{letterId}`, COIN_SIZE, coinFrame(index, 0), COLOR_LOCKED, parent)
	part.Shape = Enum.PartType.Cylinder

	-- Буква на внешнем торце. SurfaceGui, а не билборд: буквы с обратной
	-- стороны спирали закрывает колонна, и они не лезут сквозь неё кашей.
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 45
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = letter.glyph
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(35, 30, 50)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = gui
	labels[letterId] = label

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 80
	click.Parent = part

	click.MouseClick:Connect(function()
		AudioController.speak(letter.vo.name)
		showPicture(part, letter)

		--[[
			Освоенная буква — это ещё и буквёнок. Коснулся её на Башне — её буквёнок
			полетел с тобой. Выбор без меню и без чтения: ребёнок показывает букву,
			а не ищет её в списке. Сервер проверит, что буква и правда освоена.
		]]
		local mastery = if lastSnapshot then lastSnapshot.mastery[letterId] or 0 else 0
		if mastery >= Pets.OWNED_AT then
			RemoteDefs.event("EquipPet"):FireServer(letterId)
		end
		--[[
			Отклик обязателен: без него тап по букве ощущается как «ничего
			не произошло». Монетка выезжает из спирали и возвращается; исходный
			кадр берётся из расчёта, а не из текущего положения — частые тапы
			не уводят её всё дальше.
		]]
		if not part:GetAttribute("Pressing") then
			part:SetAttribute("Pressing", true)
			TweenService:Create(part, TweenInfo.new(0.12), { CFrame = coinFrame(index, 0.9) }):Play()
			task.delay(0.14, function()
				if part.Parent then
					TweenService:Create(part, TweenInfo.new(0.2), { CFrame = coinFrame(index, 0) }):Play()
				end
				task.wait(0.2)
				if part.Parent then
					part:SetAttribute("Pressing", false)
				end
			end)
		end
	end)

	part.Parent = parent
	return part
end

-- Колонна, пояски между ступенями алфавита и корона со звездой наверху.
local function buildColumn(parent: Instance)
	local ground = groundOf(basePosition or Vector3.zero)
	local count = Letters.count()
	local top = FIRST_HEIGHT + (count - 1) * RISE + 1.6

	local plinth =
		column("Plinth", 1, 8.8, ground + Vector3.new(0, 0.5, 0), Color3.fromRGB(190, 185, 200), parent)
	plinth.Material = Enum.Material.Slate
	plinth.CanCollide = true
	column("Column", top, 3.2, ground + Vector3.new(0, top / 2, 0), CREAM, parent)

	-- Поясок после каждой ступени: три буквы — один виток половины, видно, где ступень.
	for stage = 1, math.floor(count / 3) do
		local y = FIRST_HEIGHT + (stage * 3 - 1) * RISE + RISE / 2
		column(`StageBand_{stage}`, 0.35, 4.2, ground + Vector3.new(0, y, 0), GOLD, parent)
	end

	for level, spec in { { 0.6, 5 }, { 0.6, 3.6 }, { 0.6, 2.2 } } do
		column(
			`Crown_{level}`,
			spec[1],
			spec[2],
			ground + Vector3.new(0, top + (level - 0.5) * 0.6, 0),
			GOLD,
			parent
		)
	end
	local topStar = towerPart(
		"Star",
		Vector3.one * 2.2,
		CFrame.new(ground + Vector3.new(0, top + 3, 0)),
		COLOR_LOCKED,
		parent
	)
	topStar.Shape = Enum.PartType.Ball
	star = topStar
end

local function buildSign(parent: Instance)
	local sign = Instance.new("Part")
	sign.Name = "TowerSign"
	sign.Size = Vector3.new(10, 3, 0.6)
	--[[
		Табличка перед Башней, со стороны комнаты букв, в осях участка. Раньше
		смещение было мировым: на участках, повёрнутых к площади под другим углом,
		табличка оказывалась то сбоку, то за забором. Участок находим по ближайшему
		центру из конфига: сервер присылает только точку Башни.
	]]
	local position = basePosition or Vector3.zero
	local nearest, best = 1, math.huge
	for index = 1, Base.PLOT_COUNT do
		local distance = (Base.plotPosition(index) - position).Magnitude
		if distance < best then
			nearest, best = index, distance
		end
	end
	local plotFrame = CFrame.lookAt(Base.plotPosition(nearest), Vector3.zero)
	sign.CFrame = CFrame.new(position) * plotFrame.Rotation * CFrame.new(4.5, -0.5, 5.3)
	sign.Color = Color3.fromRGB(255, 240, 200)
	sign.Anchored = true
	sign.CanCollide = false
	sign.Material = Enum.Material.SmoothPlastic
	sign.Parent = parent

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(320, 120)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 55
	billboard.Parent = sign

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.45)
	title.BackgroundTransparency = 1
	title.Text = "ТВОИ БУКВЫ"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeTransparency = 0
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.Parent = billboard

	local value = Instance.new("TextLabel")
	value.Name = "Counter"
	value.Size = UDim2.fromScale(1, 0.55)
	value.Position = UDim2.fromScale(0, 0.45)
	value.BackgroundTransparency = 1
	value.Text = "0 / " .. Letters.count()
	value.TextColor3 = Color3.fromRGB(255, 214, 102)
	value.TextStrokeTransparency = 0
	value.TextScaled = true
	value.Font = Enum.Font.FredokaOne
	value.Parent = billboard

	counter = value
end

function TowerController.build()
	if folder or not basePosition then
		return
	end

	local container = Instance.new("Folder")
	container.Name = FOLDER_NAME
	container.Parent = workspace
	folder = container

	buildColumn(container)
	for index, letterId in Letters.ordered() do
		segments[letterId] = buildSegment(letterId, index, container)
	end

	buildSign(container)
end

--[[
	Состояния сегмента повторяют статусы буквы из docs/01-GDD.md § 4:
	серый силуэт → тусклый → яркий → сияющий.
]]
function TowerController.update(snapshot)
	if not snapshot or typeof(snapshot.mastery) ~= "table" then
		return
	end

	-- Срез запоминаем всегда: Башня может появиться позже среза, когда сервер
	-- выдаст участок, и тогда её нужно сразу покрасить по текущему прогрессу.
	lastSnapshot = snapshot

	local known = 0

	local mastered = 0
	for letterId, segment in segments do
		local mastery = snapshot.mastery[letterId] or 0
		local letter = Letters.expect(letterId)
		local ring = rings[letterId]
		local label = labels[letterId]

		if mastery >= 2 then
			known += 1
		end
		if mastery >= 3 then
			mastered += 1
		end

		if mastery <= 0 then
			segment.Color = COLOR_LOCKED
		elseif mastery == 1 then
			segment.Color = letter.color:Lerp(Color3.new(1, 1, 1), 0.45)
		else
			segment.Color = letter.color
		end
		if label then
			label.TextColor3 = if mastery <= 0
				then Color3.fromRGB(235, 235, 240)
				else Color3.fromRGB(255, 255, 255)
		end
		-- Освоенная буква — светящийся ободок её цвета, остальные — кремовый.
		if ring then
			ring.Color = if mastery >= 3 then letter.color else CREAM
			ring.Material = if mastery >= 3 then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end

	-- Все 33 освоены — звезда на короне загорается.
	if star then
		local complete = mastered >= Letters.count()
		star.Color = if complete then GOLD else COLOR_LOCKED
		star.Material = if complete then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end

	if counter then
		counter.Text = `{known} / {Letters.count()}`
	end
end

--[[
	Сервер выдал участок: ставим Башню во дворе.

	Место может прийти второй раз (например, участок переназначили) — тогда Башня
	собирается заново на новом месте. Пересборка дешевле, чем перенос: сегментов
	тридцать три, и они анкерные.
]]
function TowerController.placeAt(position: Vector3)
	if typeof(position) ~= "Vector3" then
		return
	end
	if basePosition and (basePosition - position).Magnitude < 0.5 then
		return
	end

	basePosition = position

	if folder then
		folder:Destroy()
		folder = nil
		table.clear(segments)
		table.clear(rings)
		table.clear(labels)
		star = nil
		counter = nil
	end

	TowerController.build()

	if lastSnapshot then
		TowerController.update(lastSnapshot)
	end
end

function TowerController.init()
	-- Строить пока нечего: ждём участок от сервера (см. placeAt).
end

return TowerController
