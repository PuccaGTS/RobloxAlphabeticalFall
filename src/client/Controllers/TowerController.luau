--!nonstrict
--[[
	Азбучная Башня — «зачем она нужна».

	Три ответа, и все три должны читаться ребёнком без объяснений взрослого:

	1. Это ВИТРИНА. Видно, сколько букв уже твои: серые — незнакомые, светящиеся —
	   освоенные. Ребёнок 5 лет не понимает процентов и прогресс-баров,
	   но прекрасно понимает «вот эти уже мои, а эти ещё нет».
	2. Это ЦЕЛЬ. Башню видно с любой точки площади, и она достраивается сама
	   по мере обучения — ради этого возвращаются.
	3. Это ПОВТОРЕНИЕ. Тап по букве произносит её. Бесплатно, без испытания
	   и без награды — просто подошёл и послушал. Ровно то повторение, ради которого
	   существует планировщик (docs/02-LEARNING.md § 6).

	Башня строится на клиенте: она у каждого своя, один общий объект в мире так не умеет.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)

local AudioController = require(script.Parent.AudioController)
local Glyph = require(script.Parent.Parent.UI.Glyph)

local TowerController = {}

local BASE_POSITION = Vector3.new(0, 4, 0)
local SEGMENT_HEIGHT = 2.4
local SEGMENT_SIZE = Vector3.new(5, 2.2, 5)
local FOLDER_NAME = "AlphabetTower"

local COLOR_LOCKED = Color3.fromRGB(105, 108, 122)

local segments: { [string]: BasePart } = {}
local folder: Folder? = nil
local counter: TextLabel? = nil

local function buildSegment(letterId: string, index: number): BasePart
	local letter = Letters.expect(letterId)

	local part = Instance.new("Part")
	part.Name = `Segment_{letterId}`
	part.Size = SEGMENT_SIZE
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = COLOR_LOCKED
	part.Transparency = 0.4
	part.CFrame = CFrame.new(BASE_POSITION + Vector3.new(0, index * SEGMENT_HEIGHT, 0))
		* CFrame.Angles(0, index * 0.22, 0)

	Glyph.attach(part, letter.glyph, SEGMENT_SIZE.Y * 1.3)

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 80
	click.Parent = part

	click.MouseClick:Connect(function()
		AudioController.speak(letter.vo.sound)
		-- Отклик обязателен: без него тап по букве ощущается как «ничего не произошло»,
		-- особенно пока озвучки нет.
		local original = part.Size
		TweenService:Create(part, TweenInfo.new(0.12), { Size = original * 1.18 }):Play()
		task.delay(0.14, function()
			if part.Parent then
				TweenService:Create(part, TweenInfo.new(0.2), { Size = original }):Play()
			end
		end)
	end)

	return part
end

local function buildSign(parent: Instance)
	local sign = Instance.new("Part")
	sign.Name = "TowerSign"
	sign.Size = Vector3.new(10, 3, 0.6)
	sign.CFrame = CFrame.new(BASE_POSITION + Vector3.new(0, -0.5, 6))
	sign.Color = Color3.fromRGB(255, 240, 200)
	sign.Anchored = true
	sign.CanCollide = false
	sign.Material = Enum.Material.SmoothPlastic
	sign.Parent = parent

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(320, 120)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 200
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
	if folder then
		return
	end

	local container = Instance.new("Folder")
	container.Name = FOLDER_NAME
	container.Parent = workspace
	folder = container

	for index, letterId in Letters.ordered() do
		local segment = buildSegment(letterId, index)
		segment.Parent = container
		segments[letterId] = segment
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

	local known = 0

	for letterId, segment in segments do
		local mastery = snapshot.mastery[letterId] or 0
		local letter = Letters.expect(letterId)

		if mastery >= 2 then
			known += 1
		end

		if mastery <= 0 then
			segment.Color = COLOR_LOCKED
			segment.Transparency = 0.4
			segment.Material = Enum.Material.SmoothPlastic
		elseif mastery == 1 then
			segment.Color = letter.color:Lerp(Color3.new(1, 1, 1), 0.45)
			segment.Transparency = 0.1
			segment.Material = Enum.Material.SmoothPlastic
		elseif mastery == 2 then
			segment.Color = letter.color
			segment.Transparency = 0
			segment.Material = Enum.Material.SmoothPlastic
		else
			segment.Color = letter.color
			segment.Transparency = 0
			segment.Material = Enum.Material.Neon
		end
	end

	if counter then
		counter.Text = `{known} / {Letters.count()}`
	end
end

function TowerController.init()
	TowerController.build()
end

return TowerController
