--!strict
--[[
	Почта от буквят глазами клиента (Logic/Mail, Services/MailService).

	  · у каждого ящика на участках флажок встаёт, а над ящиком качается 💌,
	    пока у хозяина есть непрочитанные открытки (атрибут MailUnread);
	  · открыл свой ящик — сервер прислал открытки (MailOpened), их показывает MailUI.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local MailUI = require(script.Parent.Parent.UI.MailUI)

local MailController = {}

local TAG = "Mailbox"
local FLAG_DOWN = math.rad(90) -- флажок лежит назад, к дому
local NEAR = 160

local angles: { [Instance]: number } = {}
local bubbleHome: { [Instance]: CFrame } = {}

local function letterIds(list: any): { string }
	local clean: { string } = {}
	if typeof(list) == "table" then
		for _, id in list do
			if typeof(id) == "string" and Letters.get(id) then
				table.insert(clean, id)
			end
		end
	end
	return clean
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	local now = os.clock()
	for _, box in CollectionService:GetTagged(TAG) do
		local body = box:FindFirstChild("Box")
		if not body or not body:IsA("BasePart") or (eye and (body.Position - eye).Magnitude > NEAR) then
			continue
		end
		local owner = Players:GetPlayerByUserId(box:GetAttribute("Owner") or 0)
		local unread = owner and owner:GetAttribute("MailUnread") or 0
		local target = if unread > 0 then 0 else FLAG_DOWN
		local angle = angles[box] or FLAG_DOWN
		angle += (target - angle) * math.min(1, dt * 5)
		angles[box] = angle
		for _, name in { "FlagArm", "FlagPaddle" } do
			local piece = box:FindFirstChild(name)
			if piece and piece:IsA("BasePart") then
				local pivot = piece:GetAttribute("Pivot")
				local offset = piece:GetAttribute("Offset")
				if typeof(pivot) == "CFrame" and typeof(offset) == "CFrame" then
					piece.CFrame = pivot * CFrame.Angles(angle, 0, 0) * offset
				end
			end
		end
		local bubble = box:FindFirstChild("Bubble")
		if bubble and bubble:IsA("BasePart") then
			local billboard = bubble:FindFirstChildOfClass("BillboardGui")
			if billboard then
				billboard.Enabled = unread > 0
			end
			if unread > 0 then
				local home = bubbleHome[bubble] or bubble.CFrame
				bubbleHome[bubble] = home
				bubble.CFrame = home * CFrame.new(0, math.sin(now * 3) * 0.35, 0)
			end
		end
	end
	for box in angles do
		if not box.Parent then
			angles[box] = nil
		end
	end
	for bubble in bubbleHome do
		if not bubble.Parent then
			bubbleHome[bubble] = nil
		end
	end
end

function MailController.init()
	RemoteDefs.event("MailOpened").OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" then
			return
		end
		MailUI.show(letterIds(data.fresh), letterIds(data.all))
	end)
	RunService.Heartbeat:Connect(step)
end

return MailController
