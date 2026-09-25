--!nonstrict
--[[
	Задания дня на клиенте: панель (UI/QuestsUI), тост за выполненное и дорога
	к месту задания. Решает всё сервер (Services/QuestService), здесь только
	рисуется список и стрелка.

	Дорога — как у обучения первых минут (TutorialController): над целью прыгает
	крупная стрелка, от ног тянется светлая полоса. Дошёл до места или задание
	выполнено — стрелка гаснет сама.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefs = require(Shared.Net.RemoteDefs)

local QuestsUI = require(script.Parent.Parent.UI.QuestsUI)
local HUD = require(script.Parent.Parent.UI.HUD)

local QuestController = {}

local player = Players.LocalPlayer

local COLOR = Color3.fromRGB(120, 230, 255)
local ARRIVED = 14 -- ближе этого к цели — дошёл, стрелка не нужна

local way: { anchor: BasePart, beam: Beam?, from: Attachment?, questId: string }? = nil
local watch: RBXScriptConnection? = nil

local function clearWay()
	if watch then
		watch:Disconnect()
		watch = nil
	end
	if way then
		way.anchor:Destroy()
		if way.beam then
			way.beam:Destroy()
		end
		if way.from then
			way.from:Destroy()
		end
		way = nil
	end
end

local function showWay(item)
	local same = way and way.questId == item.id
	clearWay()
	-- Второй тап по той же строке прячет дорогу.
	if same or typeof(item.target) ~= "Vector3" then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "QuestTarget"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = item.target + Vector3.new(0, 2, 0)
	anchor.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(110, 110)
	billboard.StudsOffset = Vector3.new(0, 9, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = anchor
	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.fromScale(1, 0.62)
	arrow.BackgroundTransparency = 1
	arrow.Text = "⬇"
	arrow.TextScaled = true
	arrow.TextColor3 = COLOR
	arrow.TextStrokeTransparency = 0
	arrow.Font = Enum.Font.FredokaOne
	arrow.Parent = billboard
	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.fromScale(1, 0.38)
	icon.Position = UDim2.fromScale(0, 0.62)
	icon.BackgroundTransparency = 1
	icon.Text = item.icon
	icon.TextScaled = true
	icon.Parent = billboard
	TweenService:Create(
		billboard,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffset = Vector3.new(0, 11.5, 0) }
	):Play()

	local to = Instance.new("Attachment")
	to.Parent = anchor
	local entry = { anchor = anchor, questId = item.id, beam = nil, from = nil }
	way = entry

	local function attach()
		if entry.beam then
			entry.beam:Destroy()
			entry.from:Destroy()
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local from = Instance.new("Attachment")
		from.Position = Vector3.new(0, -2, 0)
		from.Parent = root
		local band = Instance.new("Beam")
		band.Attachment0 = from
		band.Attachment1 = to
		band.Color = ColorSequence.new(COLOR)
		band.Transparency = NumberSequence.new(0.4)
		band.LightEmission = 1
		band.Width0 = 1.2
		band.Width1 = 2.5
		band.FaceCamera = true
		band.Segments = 16
		band.Parent = root
		entry.beam, entry.from = band, from
	end
	attach()

	watch = RunService.Heartbeat:Connect(function()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		if not entry.from or entry.from.Parent ~= root then
			attach() -- персонаж появился заново
		end
		local flat = (root.Position - anchor.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude < ARRIVED then
			clearWay()
		elseif flat.Magnitude > 700 then
			-- Ребёнок в забеге или на поляне занятия: полоса через весь мир только мешает.
			if entry.beam then
				entry.beam.Enabled = false
			end
		elseif entry.beam then
			entry.beam.Enabled = true
		end
	end)
end

local function onQuests(payload)
	if typeof(payload) ~= "table" then
		return
	end
	QuestsUI.update(payload)

	-- Задание выполнено: дорога к нему больше не нужна, а награду надо увидеть.
	if #(payload.justDone or {}) > 0 then
		if way and table.find(payload.justDone, way.questId) then
			clearWay()
		end
		local icons = {}
		for _, item in payload.items or {} do
			if table.find(payload.justDone, item.id) then
				table.insert(icons, item.icon)
			end
		end
		HUD.toast(`✅ Задание дня {table.concat(icons, " ")}  +{payload.awarded} ⭐`, 4)
		QuestsUI.celebrate()
	end
	-- Цель могла переехать (следующий сундук): стрелка ведёт туда, куда теперь нужно.
	if way then
		for _, item in payload.items or {} do
			if item.id == way.questId and typeof(item.target) == "Vector3" then
				way.anchor.Position = item.target + Vector3.new(0, 2, 0)
			end
		end
	end
end

function QuestController.init()
	QuestsUI.build({ onPick = showWay })
	RemoteDefs.event("Quests").OnClientEvent:Connect(onQuests)
end

return QuestController
