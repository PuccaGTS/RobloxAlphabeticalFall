--!strict
--[[
	Кнопка 💃 и ряд жестов (Config/Emotes). Кнопка — над 🔊, слева внизу:
	большим пальцем достать легко, а на задания она не налезает.
	Тап по жесту — персонаж его делает, ряд закрывается.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Emotes = require(Shared.Config.Emotes)

local DanceUI = {}

local gui: ScreenGui? = nil
local row: Frame? = nil

local function round(button: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = button
end

local function setOpen(open: boolean)
	local panel = row
	if not panel then
		return
	end
	panel.Visible = open
	if open then
		panel.Size = UDim2.fromScale(0.05, 0.11)
		TweenService
			:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Size = UDim2.fromScale(0.62, 0.11) })
			:Play()
	end
end

function DanceUI.build(onEmote: (id: string) -> (), onTap: () -> ())
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "AlphabetFallDance"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen

	local toggle = Instance.new("TextButton")
	toggle.Name = "Dance"
	toggle.Size = UDim2.fromScale(0.09, 0.11)
	toggle.Position = UDim2.fromScale(0.055, 0.58)
	toggle.BackgroundColor3 = Color3.fromRGB(245, 150, 200)
	toggle.Text = "💃"
	toggle.TextScaled = true
	toggle.Font = Enum.Font.FredokaOne
	toggle.Parent = screen
	round(toggle, 0.5)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = toggle

	local panel = Instance.new("Frame")
	panel.Name = "Emotes"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.fromScale(0.16, 0.635)
	panel.Size = UDim2.fromScale(0.62, 0.11)
	panel.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
	panel.BackgroundTransparency = 0.25
	panel.ClipsDescendants = true
	panel.Visible = false
	panel.Parent = screen
	round(panel, 0.3)
	row = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.01, 0)
	layout.Parent = panel

	for order, emote in Emotes.list do
		local button = Instance.new("TextButton")
		button.Name = emote.id
		button.LayoutOrder = order
		button.Size = UDim2.fromScale(0.13, 0.84)
		button.BackgroundColor3 = Color3.fromRGB(255, 244, 220)
		button.Text = emote.icon
		button.TextScaled = true
		button.Font = Enum.Font.FredokaOne
		button.Parent = panel
		round(button, 0.3)
		button.Activated:Connect(function()
			onTap()
			onEmote(emote.id)
			setOpen(false)
		end)
	end

	toggle.Activated:Connect(function()
		onTap()
		setOpen(not panel.Visible)
	end)
end

function DanceUI.isOpen(): boolean
	return row ~= nil and (row :: Frame).Visible
end

return DanceUI
