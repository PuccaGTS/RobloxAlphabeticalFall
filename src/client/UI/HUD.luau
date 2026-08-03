--!nonstrict
--[[
	Минимальный HUD вертикального среза.

	Из docs/08-UX-UI.md: на экране одновременно не больше трёх интерактивных элементов,
	кнопка «динамик» всегда на месте, текста ребёнку читать не нужно.

	Это серый ящик: пропорции и логика верные, арта нет.
	Кнопка «Играть» — временная, до появления хаба с порталами островов.
]]

local Players = game:GetService("Players")

local HUD = {}

local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local starsLabel: TextLabel? = nil
local targetLabel: TextLabel? = nil
local progressLabel: TextLabel? = nil

local function makeButton(name: string, text: string, size: UDim2, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = Color3.fromRGB(255, 214, 102)
	button.TextColor3 = Color3.fromRGB(40, 40, 50)
	button.Text = text
	button.TextScaled = true
	button.Font = Enum.Font.FredokaOne
	button.AutoButtonColor = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = button

	return button
end

function HUD.build(callbacks: { onRepeat: () -> (), onStart: () -> () })
	if gui then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "AlphabetFallHUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	-- Счётчик звёздочек: главный дофамин, всегда на виду
	local stars = Instance.new("TextLabel")
	stars.Name = "Stars"
	stars.Size = UDim2.fromScale(0.2, 0.08)
	stars.Position = UDim2.fromScale(0.78, 0.03)
	stars.BackgroundTransparency = 0.2
	stars.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	stars.TextColor3 = Color3.fromRGB(255, 214, 102)
	stars.Text = "⭐ 0"
	stars.TextScaled = true
	stars.Font = Enum.Font.FredokaOne
	stars.Parent = screen
	starsLabel = stars

	local starsCorner = Instance.new("UICorner")
	starsCorner.CornerRadius = UDim.new(0, 16)
	starsCorner.Parent = stars

	-- Буква-цель: ребёнок должен видеть её всё время, а не вспоминать
	local target = Instance.new("TextLabel")
	target.Name = "Target"
	target.Size = UDim2.fromScale(0.14, 0.16)
	target.Position = UDim2.fromScale(0.43, 0.03)
	target.BackgroundTransparency = 1
	target.TextColor3 = Color3.fromRGB(255, 255, 255)
	target.TextStrokeTransparency = 0.4
	target.Text = ""
	target.TextScaled = true
	target.Font = Enum.Font.FredokaOne
	target.Visible = false
	target.Parent = screen
	targetLabel = target

	local progress = Instance.new("TextLabel")
	progress.Name = "Progress"
	progress.Size = UDim2.fromScale(0.2, 0.06)
	progress.Position = UDim2.fromScale(0.40, 0.20)
	progress.BackgroundTransparency = 1
	progress.TextColor3 = Color3.fromRGB(255, 255, 255)
	progress.TextStrokeTransparency = 0.5
	progress.Text = ""
	progress.TextScaled = true
	progress.Font = Enum.Font.FredokaOne
	progress.Visible = false
	progress.Parent = screen
	progressLabel = progress

	-- Кнопка «динамик» — самая важная в игре, всегда в одном месте
	local repeatButton = makeButton("Repeat", "🔊", UDim2.fromScale(0.12, 0.12), UDim2.fromScale(0.04, 0.72))
	repeatButton.Parent = screen
	repeatButton.Activated:Connect(callbacks.onRepeat)

	-- ВРЕМЕННО: запуск испытания до появления хаба
	local startButton = makeButton("Start", "Играть", UDim2.fromScale(0.22, 0.1), UDim2.fromScale(0.39, 0.85))
	startButton.Parent = screen
	startButton.Activated:Connect(callbacks.onStart)
end

function HUD.setStars(value: number)
	if starsLabel then
		starsLabel.Text = `⭐ {value}`
	end
end

function HUD.showTarget(glyph: string?, caught: number?, total: number?)
	if targetLabel then
		targetLabel.Text = glyph or ""
		targetLabel.Visible = glyph ~= nil
	end
	if progressLabel then
		if caught and total then
			progressLabel.Text = `{caught} / {total}`
			progressLabel.Visible = true
		else
			progressLabel.Visible = false
		end
	end
end

return HUD
