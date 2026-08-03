--!nonstrict
--[[
	Азбучная Башня — витрина прогресса и бесплатное повторение.

	Башня строится НА КЛИЕНТЕ, потому что она у каждого своя: у одного ребёнка буква
	освоена, у другого нет, а один общий объект в мире так не умеет.

	Тап по сегменту произносит букву. Это важнее, чем кажется: ребёнок сам,
	без испытания и без награды, тыкает в буквы и слушает их — ровно то повторение,
	которое мы пытаемся организовать планировщиком (docs/02-LEARNING.md § 6).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)

local AudioController = require(script.Parent.AudioController)

local TowerController = {}

local BASE_POSITION = Vector3.new(0, 4, 0)
local SEGMENT_HEIGHT = 1.8
local SEGMENT_SIZE = Vector3.new(4, 1.6, 4)
local FOLDER_NAME = "AlphabetTower"

local COLOR_LOCKED = Color3.fromRGB(120, 120, 130)

local segments: { [string]: BasePart } = {}
local folder: Folder? = nil

local function buildSegment(letterId: string, index: number): BasePart
	local letter = Letters.expect(letterId)

	local part = Instance.new("Part")
	part.Name = `Segment_{letterId}`
	part.Size = SEGMENT_SIZE
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = COLOR_LOCKED
	part.Transparency = 0.35
	-- лёгкая спираль, чтобы башня читалась как башня, а не как столб
	part.CFrame = CFrame.new(BASE_POSITION + Vector3.new(0, index * SEGMENT_HEIGHT, 0))
		* CFrame.Angles(0, index * 0.18, 0)

	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local surface = Instance.new("SurfaceGui")
		surface.Face = face
		surface.CanvasSize = Vector2.new(200, 100)
		surface.MaxDistance = 150
		surface.Parent = part

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = letter.glyph
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.Parent = surface
	end

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 60
	click.Parent = part
	click.MouseClick:Connect(function()
		AudioController.speak(letter.vo.sound)
	end)

	return part
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
end

--[[
	Состояния сегмента повторяют статусы буквы из docs/01-GDD.md § 4:
	серый силуэт → тусклый → яркий → с сиянием.
]]
function TowerController.update(snapshot)
	if not snapshot or typeof(snapshot.mastery) ~= "table" then
		return
	end

	for letterId, segment in segments do
		local mastery = snapshot.mastery[letterId] or 0
		local letter = Letters.expect(letterId)

		if mastery <= 0 then
			segment.Color = COLOR_LOCKED
			segment.Transparency = 0.35
			segment.Material = Enum.Material.SmoothPlastic
		elseif mastery == 1 then
			segment.Color = letter.color:Lerp(Color3.new(1, 1, 1), 0.5)
			segment.Transparency = 0.15
		elseif mastery == 2 then
			segment.Color = letter.color
			segment.Transparency = 0
		else
			segment.Color = letter.color
			segment.Transparency = 0
			segment.Material = Enum.Material.Neon
		end
	end
end

function TowerController.init()
	TowerController.build()
end

return TowerController
