--!nonstrict
--[[
	Минимальный HUD вертикального среза.

	Из docs/08-UX-UI.md: на экране одновременно не больше трёх интерактивных элементов,
	кнопка «динамик» всегда на месте, текста ребёнку читать не нужно.

	Это серый ящик: пропорции и логика верные, арта нет.
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
local subtitleLabel: TextLabel? = nil

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

function HUD.build(callbacks: { [string]: () -> () })
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
	local repeatButton =
		makeButton("Repeat", "🔊", UDim2.fromScale(0.12, 0.12), UDim2.fromScale(0.04, 0.72))
	repeatButton.Parent = screen
	repeatButton.Activated:Connect(callbacks.onRepeat)

	-- Магазин: петля «поучился — получил вещь» должна замыкаться в один тап
	local shopButton = makeButton("Shop", "🛍", UDim2.fromScale(0.12, 0.12), UDim2.fromScale(0.84, 0.72))
	shopButton.Parent = screen
	shopButton.Activated:Connect(callbacks.onShop)

	--[[
		Кнопок «Буквы», «Лестница», «Числа» здесь больше нет. Это были отладочные
		дубли падов, и они путали: «Буквы» запускала Буквопад, а не мир букв.
		Дорогу к занятиям теперь показывают пады, порталы и стрелка обучения.
	]]

	--[[
		Субтитры: текст того, что говорит голос. Пока озвучка не записана, это
		единственный способ узнать задание; потом — для тех, кто их включит.
		Внизу по центру, где их ищут по привычке, над кнопками 🔊 и 🛍.
	]]
	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.AnchorPoint = Vector2.new(0.5, 1)
	sub.Size = UDim2.fromScale(0.6, 0.08)
	sub.Position = UDim2.fromScale(0.5, 0.95)
	sub.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	sub.BackgroundTransparency = 0.35
	sub.TextColor3 = Color3.fromRGB(255, 255, 255)
	sub.TextScaled = true
	sub.Font = Enum.Font.GothamBold
	sub.Text = ""
	sub.Visible = false
	sub.Parent = screen
	subtitleLabel = sub

	local subPadding = Instance.new("UIPadding")
	subPadding.PaddingLeft = UDim.new(0, 12)
	subPadding.PaddingRight = UDim.new(0, 12)
	subPadding.PaddingTop = UDim.new(0, 4)
	subPadding.PaddingBottom = UDim.new(0, 4)
	subPadding.Parent = sub

	local subCorner = Instance.new("UICorner")
	subCorner.CornerRadius = UDim.new(0, 12)
	subCorner.Parent = sub

	--[[
		«Домик»: одинаковый на всех экранах и всегда на месте (docs/08-UX-UI.md § 2).
		Из испытания выводит без потерь — сохранка остаётся, — и из любого места
		приводит к своему дому. Застрять в игре ребёнок не должен никогда.
	]]
	local homeButton = makeButton("Home", "🏠", UDim2.fromScale(0.09, 0.11), UDim2.fromScale(0.89, 0.13))
	homeButton.Parent = screen
	homeButton.Activated:Connect(callbacks.onHome)

	local homeRatio = Instance.new("UIAspectRatioConstraint")
	homeRatio.AspectRatio = 1
	homeRatio.Parent = homeButton

	--[[
		Вход для родителей: маленький и в углу, чтобы ребёнок не тыкал в него
		первым делом. Ребёнку он всё равно ничего не откроет — дальше взрослый
		вопрос и PIN (docs/13-PARENT-MODE.md § 1).
	]]
	-- Отступ сверху в пикселях: левый верхний угол занимает меню самого Roblox.
	local parentButton = makeButton("Parent", "⚙", UDim2.fromOffset(48, 48), UDim2.new(0, 12, 0, 72))
	parentButton.BackgroundColor3 = Color3.fromRGB(60, 64, 82)
	parentButton.TextColor3 = Color3.fromRGB(200, 205, 220)
	parentButton.Parent = screen
	parentButton.Activated:Connect(callbacks.onParent)

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

--[[
	Знакомство с буквой: она выезжает крупно на весь экран, держится, пока звучит
	реплика, и уходит. Никаких кнопок — ребёнку ничего не нужно делать,
	это момент «посмотри и послушай», а не задание.
]]
function HUD.showIntro(glyph: string)
	if not gui then
		return
	end

	local existing = gui:FindFirstChild("Intro")
	if existing then
		existing:Destroy()
	end

	local card = Instance.new("TextLabel")
	card.Name = "Intro"
	card.Size = UDim2.fromScale(0.36, 0.42)
	card.Position = UDim2.fromScale(0.32, 0.24)
	card.BackgroundColor3 = Color3.fromRGB(255, 250, 240)
	card.BackgroundTransparency = 0.05
	card.TextColor3 = Color3.fromRGB(40, 40, 55)
	card.Text = glyph
	card.TextScaled = true
	card.Font = Enum.Font.FredokaOne
	card.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 28)
	corner.Parent = card

	card.Size = UDim2.fromScale(0.05, 0.06)
	TweenService:Create(
		card,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(0.36, 0.42) }
	):Play()

	task.delay(3.2, function()
		if card.Parent then
			local out = TweenService:Create(
				card,
				TweenInfo.new(0.35),
				{ TextTransparency = 1, BackgroundTransparency = 1 }
			)
			out.Completed:Connect(function()
				card:Destroy()
			end)
			out:Play()
		end
	end)
end

local toastToken = 0

--[[
	Очередь субтитров: строки идут одна за другой, как голос, а не затирают
	друг друга. «Познакомься! Это…», «Буква А», «Беги в ворота…» приходят разом,
	и покажи мы только последнюю, первые две пропали бы.
]]
local subtitleQueue: { string } = {}
local subtitleRunning = false
local SUBTITLE_MAX_PENDING = 3

local function subtitleSeconds(text: string): number
	-- Столько, сколько взрослый читает вслух: около 15 символов в секунду, не меньше полутора секунд.
	return math.clamp(0.8 + utf8.len(text) / 15, 1.5, 6)
end

function HUD.subtitle(text: string)
	if not subtitleLabel or text == "" then
		return
	end
	-- Одна и та же строка подряд (тап по той же букве) — не копим повторы.
	if subtitleQueue[#subtitleQueue] == text then
		return
	end
	table.insert(subtitleQueue, text)
	while #subtitleQueue > SUBTITLE_MAX_PENDING do
		table.remove(subtitleQueue, 1)
	end

	if subtitleRunning then
		return
	end
	subtitleRunning = true
	task.spawn(function()
		while #subtitleQueue > 0 do
			local line = table.remove(subtitleQueue, 1) :: string
			if subtitleLabel then
				subtitleLabel.Text = line
				subtitleLabel.Visible = true
			end
			task.wait(subtitleSeconds(line))
		end
		if subtitleLabel then
			subtitleLabel.Visible = false
		end
		subtitleRunning = false
	end)
end

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
