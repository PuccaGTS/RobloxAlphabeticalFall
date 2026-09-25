--!nonstrict
--[[
	Итог испытания: 1–3 звезды, прилетающие ⭐ и две кнопки — «Ещё раз» и «Домой».
	См. docs/08-UX-UI.md § 6, пункт 5.

	Экран обязан быть понятен без текста (docs/08 § 1): звёзды считаются глазами,
	кнопки узнаются по значкам 🔁 и 🏠 («↻» в шрифте не рисуется), подписи под ними — для взрослого рядом.
	Пустых звёзд нет: худший итог — одна звезда, и она горит так же ярко.
	Проиграть в игре нельзя, и экран итогов этого не должен подсказывать.

	Экран не держит ребёнка: не нажал ничего — через несколько секунд уходит сам,
	побежал — уходит сразу, а в углу есть крестик. На проверке 24.09.2026 окно
	с двумя кнопками посреди экрана назвали «не даёт свободно пойти побегать».
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CloseButton = require(script.Parent.CloseButton)

local ResultScreen = {}

local player = Players.LocalPlayer

local AUTO_HIDE_SECONDS = 6
local STAR_DELAY = 0.35
-- Столько экран не замечает бега: звёзды успевают вылететь, а случайный шаг не гасит итог.
local MOVE_GRACE_SECONDS = 1.2

local gui: ScreenGui? = nil
local stars: { TextLabel } = {}
local rewardLabel: TextLabel? = nil
local captionLabel: TextLabel? = nil
local handlers: { onAgain: () -> (), onHome: () -> (), onStar: () -> () }? = nil
local token = 0
local watchMove: RBXScriptConnection? = nil

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function bigButton(parent: Instance, icon: string, text: string, x: number, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromScale(0.4, 0.26)
	b.Position = UDim2.fromScale(x, 0.68)
	b.BackgroundColor3 = color
	b.Text = ""
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 18)

	local glyph = Instance.new("TextLabel")
	glyph.Size = UDim2.fromScale(1, 0.62)
	glyph.BackgroundTransparency = 1
	glyph.Text = icon
	glyph.TextScaled = true
	glyph.TextColor3 = Color3.fromRGB(40, 40, 50)
	glyph.Font = Enum.Font.FredokaOne
	glyph.Parent = b

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.fromScale(1, 0.3)
	caption.Position = UDim2.fromScale(0, 0.64)
	caption.BackgroundTransparency = 1
	caption.Text = text
	caption.TextScaled = true
	caption.TextColor3 = Color3.fromRGB(60, 60, 70)
	caption.Font = Enum.Font.FredokaOne
	caption.Parent = b

	return b
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "AlphabetFallResult"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	screen.DisplayOrder = 3 -- над HUD, под экраном «На сегодня всё» и родительским
	screen.Parent = player:WaitForChild("PlayerGui")

	local card = Instance.new("Frame")
	card.Size = UDim2.fromScale(0.5, 0.56)
	card.Position = UDim2.fromScale(0.25, 0.2)
	card.BackgroundColor3 = Color3.fromRGB(40, 44, 66)
	card.BackgroundTransparency = 0.05
	card.Parent = screen
	corner(card, 28)

	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1.35
	ratio.Parent = card

	for index = 1, 3 do
		local star = Instance.new("TextLabel")
		star.Name = `Star_{index}`
		star.Size = UDim2.fromScale(0.26, 0.34)
		star.Position = UDim2.fromScale(0.07 + (index - 1) * 0.3, 0.06)
		star.BackgroundTransparency = 1
		star.Text = "⭐"
		star.TextScaled = true
		star.Visible = false
		star.Parent = card
		stars[index] = star
	end

	local reward = Instance.new("TextLabel")
	reward.Size = UDim2.fromScale(0.8, 0.14)
	reward.Position = UDim2.fromScale(0.1, 0.42)
	reward.BackgroundTransparency = 1
	reward.TextColor3 = Color3.fromRGB(255, 214, 102)
	reward.TextScaled = true
	reward.Font = Enum.Font.FredokaOne
	reward.Parent = card
	rewardLabel = reward

	-- Строка для взрослого: «Уровень «Первые три» пройден!». Ребёнку хватит звёзд.
	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.fromScale(0.9, 0.08)
	caption.Position = UDim2.fromScale(0.05, 0.57)
	caption.BackgroundTransparency = 1
	caption.TextColor3 = Color3.fromRGB(210, 215, 235)
	caption.TextScaled = true
	caption.Font = Enum.Font.FredokaOne
	caption.Parent = card
	captionLabel = caption

	bigButton(card, "🔁", "Ещё раз", 0.06, Color3.fromRGB(150, 215, 150)).Activated:Connect(function()
		ResultScreen.hide()
		if handlers then
			handlers.onAgain()
		end
	end)
	bigButton(card, "🏠", "Домой", 0.54, Color3.fromRGB(255, 214, 102)).Activated:Connect(function()
		ResultScreen.hide()
		if handlers then
			handlers.onHome()
		end
	end)

	CloseButton.make(card, 44, UDim2.new(1, -30, 0, -14)).Activated:Connect(ResultScreen.hide)

	gui = screen
end

function ResultScreen.init(callbacks: { onAgain: () -> (), onHome: () -> (), onStar: () -> () })
	handlers = callbacks
	if not gui then
		build()
	end
end

--[[
	count — сколько звёзд (1–3), awarded — сколько ⭐ начислено,
	caption — строка для взрослого или nil.
]]
function ResultScreen.show(count: number, awarded: number, caption: string?)
	if not gui then
		build()
	end
	ResultScreen.hide()
	local mine = token

	local shown = math.clamp(math.floor(count), 1, 3)
	for index, star in stars do
		star.Visible = false
		star.Size = UDim2.fromScale(0.26, 0.34)
		-- Одна звезда — посередине, а не с краю: итог не должен выглядеть недобором.
		local slot = if shown == 1 then 2 elseif shown == 2 then index + 0.5 else index
		star.Position = UDim2.fromScale(0.07 + (slot - 1) * 0.3, 0.06)
	end
	if rewardLabel then
		rewardLabel.Text = if awarded > 0 then `+{awarded} ⭐` else ""
	end
	if captionLabel then
		captionLabel.Text = caption or ""
	end
	gui.Enabled = true

	-- Звёзды вылетают по одной, каждая со своим звоном: так их считают, не читая.
	task.spawn(function()
		for index = 1, shown do
			task.wait(STAR_DELAY)
			if mine ~= token then
				return
			end
			local star = stars[index]
			star.Size = UDim2.fromScale(0.05, 0.06)
			star.Visible = true
			TweenService:Create(
				star,
				TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.fromScale(0.26, 0.34) }
			):Play()
			if handlers then
				handlers.onStar()
			end
		end
	end)

	task.delay(AUTO_HIDE_SECONDS, function()
		if mine == token then
			ResultScreen.hide()
		end
	end)

	-- Побежал — значит, итог увидел и хочет играть: окно уходит с дороги.
	local shownAt = os.clock()
	watchMove = RunService.Heartbeat:Connect(function()
		if os.clock() - shownAt < MOVE_GRACE_SECONDS then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
			ResultScreen.hide()
		end
	end)
end

function ResultScreen.hide()
	token += 1
	if watchMove then
		watchMove:Disconnect()
		watchMove = nil
	end
	if gui then
		gui.Enabled = false
	end
end

return ResultScreen
