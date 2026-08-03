--!nonstrict
--[[
	Минимальный HUD вертикального среза.

	Из docs/08-UX-UI.md: на экране одновременно не больше трёх интерактивных элементов,
	кнопка «динамик» всегда на месте, текста ребёнку читать не нужно.

	Это серый ящик: пропорции и логика верные, арта нет.
	Кнопка «Играть» — временная, до появления хаба с порталами островов.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local HUD = {}

local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local starsLabel: TextLabel? = nil
local targetLabel: TextLabel? = nil
local progressLabel: TextLabel? = nil
local toastLabel: TextLabel? = nil

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

	-- Магазин: петля «поучился — получил вещь» должна замыкаться в один тап
	local shopButton = makeButton("Shop", "🛍", UDim2.fromScale(0.12, 0.12), UDim2.fromScale(0.84, 0.72))
	shopButton.Parent = screen
	shopButton.Activated:Connect(callbacks.onShop)

	-- Дубли падов из хаба: ребёнок может не дойти до пада, а взрослому нужен быстрый
	-- способ проверить обе механики. Уберём, когда хаб обрастёт навигацией.
	local startButton = makeButton("Start", "Буквы", UDim2.fromScale(0.2, 0.1), UDim2.fromScale(0.28, 0.85))
	startButton.Parent = screen
	startButton.Activated:Connect(callbacks.onStart)

	local bridgeButton = makeButton("Bridge", "Слоги", UDim2.fromScale(0.2, 0.1), UDim2.fromScale(0.52, 0.85))
	bridgeButton.Parent = screen
	bridgeButton.Activated:Connect(callbacks.onBridge)

	-- Сообщение поверх всего: без него любой отказ выглядит как «игра сломалась»
	local toast = Instance.new("TextLabel")
	toast.Name = "Toast"
	toast.Size = UDim2.fromScale(0.5, 0.09)
	toast.Position = UDim2.fromScale(0.25, 0.33)
	toast.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
	toast.BackgroundTransparency = 0.15
	toast.TextColor3 = Color3.fromRGB(255, 255, 255)
	toast.Text = ""
	toast.TextScaled = true
	toast.Font = Enum.Font.FredokaOne
	toast.Visible = false
	toast.Parent = screen
	toastLabel = toast

	local toastCorner = Instance.new("UICorner")
	toastCorner.CornerRadius = UDim.new(0, 16)
	toastCorner.Parent = toast
end

local toastToken = 0

function HUD.toast(text: string, seconds: number?)
	if not toastLabel then
		return
	end

	toastToken += 1
	local token = toastToken

	toastLabel.Text = text
	toastLabel.Visible = true

	task.delay(seconds or 2.5, function()
		if toastLabel and toastToken == token then
			toastLabel.Visible = false
		end
	end)
end

function HUD.setStars(value: number)
	if starsLabel then
		starsLabel.Text = `⭐ {value}`
	end
end

--[[
	Пауза после промаха. Ребёнку нельзя показать «ты ошибся» — показываем,
	что сейчас происходит подсказка: буква-цель увеличивается и подсвечивается,
	то есть внимание уводится на правильный ответ, а не на ошибку.
]]
function HUD.setBlocked(blocked: boolean)
	if not targetLabel then
		return
	end

	local goalSize = if blocked then UDim2.fromScale(0.2, 0.23) else UDim2.fromScale(0.14, 0.16)
	local goalPosition = if blocked then UDim2.fromScale(0.40, 0.02) else UDim2.fromScale(0.43, 0.03)

	targetLabel.TextColor3 = if blocked then Color3.fromRGB(255, 214, 102) else Color3.fromRGB(255, 255, 255)

	TweenService:Create(
		targetLabel,
		TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = goalSize, Position = goalPosition }
	):Play()
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
