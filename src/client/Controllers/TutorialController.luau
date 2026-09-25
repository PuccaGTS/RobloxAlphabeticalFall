--!nonstrict
--[[
	Стрелка обучения первых минут: куда идти сейчас. См. docs/08-UX-UI.md § 7 —
	никаких текстов, только голос, стрелка и пульсация.

	Над целью (падом Буквопада, магазином, порталом) прыгает крупная стрелка,
	от персонажа к цели тянется светлая полоса. Стрелку видно сквозь стены,
	полосу — только на площади: в туннеле она протянулась бы через весь мир
	и мешала бы бежать.

	Какой шаг сейчас, решает сервер (Services/TutorialService) и присылает
	в срезе профиля. Клиент только рисует.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tutorial = require(Shared.Logic.Tutorial)
local Playground = require(Shared.Config.Playground)
local Decor = require(Shared.Config.Decor)

local TutorialController = {}

local player = Players.LocalPlayer

local COLOR = Color3.fromRGB(255, 214, 102)
-- Дальше этого от цели полоса гаснет: значит, ребёнок в забеге, а не на площади.
local BEAM_MAX_DISTANCE = 300

local currentStep: string? = nil
local target: BasePart? = nil
local marker: BillboardGui? = nil
local targetAttachment: Attachment? = nil
local rootAttachment: Attachment? = nil
local beam: Beam? = nil
local token = 0
local spotAnchor: BasePart? = nil

local function clear()
	for _, instance in { marker, targetAttachment, rootAttachment, beam } do
		if instance then
			instance:Destroy()
		end
	end
	marker, targetAttachment, rootAttachment, beam, target = nil, nil, nil, nil, nil
	if spotAnchor then
		spotAnchor:Destroy()
		spotAnchor = nil
	end
end

-- Цель прогулки — место парка: невидимая точка над его серединой.
local function anchorAt(spotId: string): BasePart
	local position = Playground.position(Playground.expect(spotId))
	local anchor = Instance.new("Part")
	anchor.Name = "TutorialSpot"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = Vector3.new(position.X, Decor.groundY(position.X, position.Z) + 4, position.Z)
	anchor.Parent = workspace
	spotAnchor = anchor
	return anchor
end

local function buildMarker(part: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TutorialArrow"
	billboard.Size = UDim2.fromOffset(96, 96)
	billboard.StudsOffset = Vector3.new(0, 8, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = part

	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.BackgroundTransparency = 1
	arrow.Text = "⬇"
	arrow.TextScaled = true
	arrow.TextColor3 = COLOR
	arrow.TextStrokeColor3 = Color3.fromRGB(60, 40, 10)
	arrow.TextStrokeTransparency = 0
	arrow.Font = Enum.Font.FredokaOne
	arrow.Parent = billboard

	-- Пульсация: стрелка подпрыгивает над целью, пока шаг не сделан.
	TweenService:Create(
		billboard,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffset = Vector3.new(0, 10.5, 0) }
	):Play()

	marker = billboard
end

local function attachBeam()
	if not target or not targetAttachment then
		return
	end
	if beam then
		beam:Destroy()
		beam = nil
	end
	if rootAttachment then
		rootAttachment:Destroy()
		rootAttachment = nil
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local from = Instance.new("Attachment")
	from.Name = "TutorialFrom"
	from.Position = Vector3.new(0, -2, 0) -- у ног: полоса читается как дорожка, а не как луч
	from.Parent = root
	rootAttachment = from

	local band = Instance.new("Beam")
	band.Name = "TutorialPath"
	band.Attachment0 = from
	band.Attachment1 = targetAttachment
	band.Color = ColorSequence.new(COLOR)
	band.Transparency = NumberSequence.new(0.35)
	band.LightEmission = 1
	band.Width0 = 1.2
	band.Width1 = 2.5
	band.FaceCamera = true
	band.Segments = 16
	band.Parent = root
	beam = band
end

local function show(step: Tutorial.Step)
	token += 1
	local mine = token

	task.spawn(function()
		local spotId = string.match(step.target, "^spot:(.+)$")
		local hub = if spotId then nil else workspace:WaitForChild("Hub", 60)
		local part = if spotId then anchorAt(spotId) else hub and hub:WaitForChild(step.target, 60)
		-- Пока ждали, шаг мог смениться: рисовать устаревшую стрелку нельзя.
		if mine ~= token or not part or not part:IsA("BasePart") then
			return
		end

		target = part
		buildMarker(part)

		local to = Instance.new("Attachment")
		to.Name = "TutorialTo"
		to.Position = Vector3.new(0, 1, 0)
		to.Parent = part
		targetAttachment = to

		attachBeam()
	end)
end

function TutorialController.update(snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end
	local stepId = if typeof(snapshot.tutorial) == "string" then snapshot.tutorial else nil
	if stepId == currentStep then
		return
	end

	currentStep = stepId
	token += 1
	clear()

	local step = if stepId then Tutorial.get(stepId) else nil
	if step then
		show(step)
	end
end

function TutorialController.init()
	-- Новый персонаж (упал, переродился) — полоса перецепляется к нему.
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		attachBeam()
	end)

	RunService.Heartbeat:Connect(function()
		if not beam or not target then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		beam.Enabled = root ~= nil and (root.Position - target.Position).Magnitude < BEAM_MAX_DISTANCE
	end)
end

return TutorialController
