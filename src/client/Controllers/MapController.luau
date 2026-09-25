--!nonstrict
--[[
	Карта «Куда пойти?» (UI/MapUI): окно по кнопке 🗺 и с доски у точки появления,
	картинка той же карты на самой доске. Тап по месту — стрелка до него
	(QuestController.guide), та же, что у заданий дня.

	Доска строится сервером (WorldService, метка AF_MapBoard): здесь на неё
	кладётся нарисованная карта. Деталь может уйти из стриминга и вернуться —
	тогда карта рисуется заново.
]]

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Quests = require(Shared.Logic.Quests)

local MapUI = require(script.Parent.Parent.UI.MapUI)
local HUD = require(script.Parent.Parent.UI.HUD)
local QuestController = require(script.Parent.QuestController)

local MapController = {}

local BOARD_TAG = "AF_MapBoard"
local INK = Color3.fromRGB(70, 50, 35)

local function dress(board: Instance)
	if not board:IsA("BasePart") or board:FindFirstChild("MapSurface") then
		return
	end
	local surface = Instance.new("SurfaceGui")
	surface.Name = "MapSurface"
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 50
	surface.LightInfluence = 0.3
	surface.Parent = board

	local paper = Instance.new("Frame")
	paper.Size = UDim2.fromScale(1, 1)
	paper.BackgroundColor3 = Color3.fromRGB(252, 240, 210)
	paper.BorderSizePixel = 0
	paper.Parent = surface
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = paper

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.12)
	title.BackgroundTransparency = 1
	title.Text = "🗺 Куда пойти?"
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = INK
	title.Parent = paper

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.fromScale(0.5, 0.14)
	holder.Size = UDim2.fromScale(0.86, 0.86)
	holder.BackgroundTransparency = 1
	holder.Parent = paper
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = holder
	MapUI.draw(holder, false, nil)
end

-- Стрелка до выбранного места: как у задания дня, только без счётчика.
local function goTo(place: MapUI.Place)
	QuestController.guide({ id = `place:{place.id}`, icon = place.icon, target = place.position })
	HUD.toast(`{place.icon} Идём! Беги по стрелке`, 3)
end

function MapController.toggle()
	MapUI.toggle()
end

function MapController.init()
	MapUI.build({ onPick = goTo })

	CollectionService:GetInstanceAddedSignal(BOARD_TAG):Connect(dress)
	for _, board in CollectionService:GetTagged(BOARD_TAG) do
		dress(board)
	end

	-- Уголки парка из заданий дня горят на карте золотом, пока не выполнены.
	QuestController.onUpdate(function(payload)
		local spots = {}
		for _, item in payload.items or {} do
			local quest = Quests.get(item.id)
			local spot = quest and quest.park and string.match(quest.event, "^park:(.+)$")
			if spot and not item.done then
				spots[spot] = true
			end
		end
		MapUI.setQuestSpots(spots)
	end)
end

MapController.setHome = MapUI.setHome
MapController.open = MapUI.open

return MapController
