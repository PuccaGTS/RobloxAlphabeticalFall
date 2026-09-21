--!nonstrict
--[[
	Выбор постройки на своём участке (docs/15-HOME-BASE.md § 3.1).

	Открывается с пада улучшения. Внизу экрана — полоса: формы карточками,
	краски кружками и большая кнопка «Построить». Форма и краска меняются сразу
	и бесплатно: сервер перестраивает участок, и ребёнок видит новый забор
	прямо за полосой, а не в картинке. Покупка — только отдельной кнопкой.

	Читать ребёнок не умеет, поэтому всё главное — картинкой: форма значком,
	краска цветом, цена звёздочками.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Base = require(Shared.Config.Base)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local BuildPickerUI = {}

local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local panel: Frame? = nil
local categoryId: string? = nil
local snapshot: any = nil
-- Что выбрано сейчас: ждать ответа сервера на каждый тап — видно задержку.
local chosen = { shape = 1, paint = 1 }

local GOLD = Color3.fromRGB(255, 214, 102)
local CARD = Color3.fromRGB(48, 52, 68)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or Color3.fromRGB(240, 240, 250)
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.Parent = parent
	return l
end

--[[
	Столбик забора с верхушкой: ровной, острой или круглой. Подходящих эмодзи
	нет, а ребёнку нужна картинка, а не слово.
]]
local function postPicture(parent: Instance, picture: string)
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromScale(1, 0.62)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	for index = 0, 2 do
		local x = 0.22 + index * 0.28
		local post = Instance.new("Frame")
		post.AnchorPoint = Vector2.new(0.5, 1)
		post.Size = UDim2.fromScale(0.14, 0.55)
		post.Position = UDim2.fromScale(x, 0.95)
		post.BackgroundColor3 = Color3.fromRGB(245, 240, 230)
		post.BorderSizePixel = 0
		post.Parent = holder
		if picture == "pointed" then
			local tip = Instance.new("Frame")
			tip.AnchorPoint = Vector2.new(0.5, 0.5)
			tip.Size = UDim2.fromScale(0.1, 0.1)
			tip.Position = UDim2.fromScale(x, 0.4)
			tip.BackgroundColor3 = post.BackgroundColor3
			tip.BorderSizePixel = 0
			tip.Rotation = 45
			tip.Parent = holder
			local aspect = Instance.new("UIAspectRatioConstraint")
			aspect.Parent = tip
			tip.Size = UDim2.fromScale(0.1, 1)
		elseif picture == "round" then
			local knob = Instance.new("Frame")
			knob.AnchorPoint = Vector2.new(0.5, 0.5)
			knob.Size = UDim2.fromScale(0.2, 1)
			knob.Position = UDim2.fromScale(x, 0.36)
			knob.BackgroundColor3 = post.BackgroundColor3
			knob.BorderSizePixel = 0
			knob.Parent = holder
			local aspect = Instance.new("UIAspectRatioConstraint")
			aspect.Parent = knob
			corner(knob, 100)
		end
	end
	-- Перекладина: столбики читаются забором, а не тремя палочками.
	local rail = Instance.new("Frame")
	rail.Size = UDim2.fromScale(0.8, 0.07)
	rail.Position = UDim2.fromScale(0.1, 0.7)
	rail.BackgroundColor3 = Color3.fromRGB(245, 240, 230)
	rail.BorderSizePixel = 0
	rail.Parent = holder
end

--[[
	Окно дома: рама с крестовиной — квадратная, круглая или с полукруглым верхом.
	Форма дома — это его окна, и на карточке ребёнок видит именно окно.
]]
local function windowPicture(parent: Instance, picture: string)
	local frameColor = Color3.fromRGB(245, 240, 230)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromScale(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.33)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = if picture == "window_arch" then 0.75 else 1
	aspect.Parent = holder

	local function pane(size: UDim2, position: UDim2, round: boolean, z: number)
		local glass = Instance.new("Frame")
		glass.Size = size
		glass.Position = position
		glass.BackgroundColor3 = Color3.fromRGB(150, 205, 240)
		glass.BorderSizePixel = 0
		glass.ZIndex = z
		glass.Parent = holder
		local stroke = Instance.new("UIStroke")
		stroke.Color = frameColor
		stroke.Thickness = 4
		stroke.Parent = glass
		if round then
			corner(glass, 100)
		end
	end

	-- Перекладина крестовины; у арки — там, где начинается полукруг.
	local barY = 0.5
	if picture == "window_arch" then
		-- Круг сверху, прямоугольник поверх его нижней половины: вместе — арка.
		pane(UDim2.fromScale(1, 0.75), UDim2.fromScale(0, 0), true, 1)
		pane(UDim2.fromScale(1, 0.625), UDim2.fromScale(0, 0.375), false, 2)
		barY = 0.375
	else
		pane(UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), picture == "window_round", 1)
	end
	for _, vertical in { true, false } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Size = if vertical then UDim2.new(0, 4, 1, 0) else UDim2.new(1, 0, 0, 4)
		bar.Position = UDim2.fromScale(0.5, if vertical then 0.5 else barY)
		bar.BackgroundColor3 = frameColor
		bar.BorderSizePixel = 0
		bar.ZIndex = 3
		bar.Parent = holder
	end
end

local function pips(price: number): string
	return `{price} ` .. string.rep("⭐", math.clamp(math.ceil(price / 50), 1, 5))
end

local function send()
	if categoryId then
		RemoteDefs.event("SetBuildStyle"):FireServer(categoryId, chosen.shape, chosen.paint)
	end
end

local function render()
	if not panel or not categoryId then
		return
	end
	for _, child in panel:GetChildren() do
		if not child:IsA("UICorner") then
			child:Destroy()
		end
	end

	local category = Base.expect(categoryId)
	local level = snapshot and snapshot.base and snapshot.base[categoryId] or 0
	local stars = snapshot and snapshot.stars or 0
	local price = Base.priceFor(categoryId, level)
	local nextTitle = Base.nextTitle(categoryId, level, chosen.shape)
	-- Какую вещь показывать на карточках форм: ту, что покупают, или последнюю построенную.
	local shownLevel = math.clamp(level + 1, 1, Base.maxLevel(categoryId))

	label(
		panel,
		if nextTitle
			then `{category.emoji} {category.title}: {nextTitle}`
			else `{category.emoji} {category.title} ✅`,
		UDim2.fromScale(0.7, 0.18),
		UDim2.fromScale(0.03, 0.03)
	).TextXAlignment =
		Enum.TextXAlignment.Left

	local close = Instance.new("TextButton")
	close.Size = UDim2.fromScale(0.07, 0.2)
	close.Position = UDim2.fromScale(0.91, 0.03)
	close.BackgroundColor3 = Color3.fromRGB(220, 90, 80)
	close.TextColor3 = Color3.new(1, 1, 1)
	-- «✕» в этом шрифте не рисуется: на кнопке оставался пустой красный квадрат.
	close.Text = "X"
	close.TextScaled = true
	close.Font = Enum.Font.FredokaOne
	close.Parent = panel
	corner(close, 14)
	close.Activated:Connect(function()
		BuildPickerUI.close()
	end)

	local row = 0.26
	-- Формы: карточки со значком. Выбранная — в золотой рамке.
	if category.shapes then
		for index, shape in category.shapes do
			local card = Instance.new("TextButton")
			card.Name = `Shape_{index}`
			card.Size = UDim2.fromScale(0.14, 0.34)
			card.Position = UDim2.fromScale(0.03 + (index - 1) * 0.155, row)
			card.BackgroundColor3 = CARD
			card.Text = ""
			card.Parent = panel
			corner(card, 14)
			if shape.picture and string.sub(shape.picture, 1, 7) == "window_" then
				windowPicture(card, shape.picture)
			elseif shape.picture then
				postPicture(card, shape.picture)
			else
				label(
					card,
					Base.shapeIcon(shape, shownLevel),
					UDim2.fromScale(1, 0.62),
					UDim2.fromScale(0, 0.02)
				)
			end
			local title = if shape.titles then shape.titles[shownLevel] else shape.title
			label(card, title, UDim2.fromScale(0.92, 0.3), UDim2.fromScale(0.04, 0.66))
			if chosen.shape == index then
				local stroke = Instance.new("UIStroke")
				stroke.Color = GOLD
				stroke.Thickness = 4
				-- У кнопки рамка по умолчанию обводит текст, а его на карточке нет.
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = card
			end
			card.Activated:Connect(function()
				chosen.shape = index
				send()
				render()
			end)
		end
	end

	-- Краски: кружки. Первый — «как задумано», с радугой внутри.
	if category.paintable then
		local left = if category.shapes then 0.5 else 0.03
		for index, paint in Base.PAINTS do
			local dot = Instance.new("TextButton")
			dot.Name = `Paint_{index}`
			dot.Size = UDim2.fromScale(0.055, 0.2)
			dot.Position = UDim2.fromScale(left + ((index - 1) % 4) * 0.062, row + ((index - 1) // 4) * 0.22)
			dot.BackgroundColor3 = paint.color or Color3.fromRGB(250, 250, 250)
			dot.Text = if paint.color then "" else "🌈"
			dot.TextScaled = true
			dot.Parent = panel
			local aspect = Instance.new("UIAspectRatioConstraint")
			aspect.Parent = dot
			corner(dot, 100)
			if chosen.paint == index then
				local stroke = Instance.new("UIStroke")
				stroke.Color = GOLD
				stroke.Thickness = 4
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = dot
			end
			dot.Activated:Connect(function()
				chosen.paint = index
				send()
				render()
			end)
		end
	end

	-- Покупка: отдельная большая кнопка. Не хватает — видно, сколько ещё копить.
	if price then
		local enough = stars >= price
		local buy = Instance.new("TextButton")
		buy.Name = "Buy"
		buy.Size = UDim2.fromScale(0.94, 0.26)
		buy.Position = UDim2.fromScale(0.03, 0.71)
		buy.BackgroundColor3 = if enough then Color3.fromRGB(120, 200, 130) else Color3.fromRGB(95, 100, 115)
		buy.TextColor3 = Color3.fromRGB(30, 30, 40)
		buy.Text = if enough
			then `Построить  {pips(price)}`
			else `Копим: {stars} из {price} ⭐`
		buy.TextScaled = true
		buy.Font = Enum.Font.FredokaOne
		buy.Parent = panel
		corner(buy, 16)
		buy.Activated:Connect(function()
			if categoryId then
				RemoteDefs.event("BuildUpgrade"):FireServer(categoryId)
			end
		end)
	end
end

function BuildPickerUI.build()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "AlphabetFallBuildPicker"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.DisplayOrder = 20
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	-- Уже экрана: слева кнопка «повторить», справа магазин — их не закрываем.
	frame.Size = UDim2.fromScale(0.72, 0.34)
	frame.Position = UDim2.fromScale(0.14, 0.62)
	frame.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
	frame.BackgroundTransparency = 0.08
	frame.Parent = screen
	corner(frame, 22)
	panel = frame
end

function BuildPickerUI.open(id: string)
	if not Base.get(id) then
		return
	end
	BuildPickerUI.build()
	categoryId = id
	local style = snapshot and snapshot.baseStyle and snapshot.baseStyle[id]
	chosen = { shape = style and style.shape or 1, paint = style and style.paint or 1 }
	render()
	if gui then
		gui.Enabled = true
	end
end

function BuildPickerUI.close()
	categoryId = nil
	if gui then
		gui.Enabled = false
	end
end

function BuildPickerUI.isOpen(): boolean
	return categoryId ~= nil
end

-- Новый срез профиля: построили — цена и название следующего уровня сменились.
function BuildPickerUI.setSnapshot(newSnapshot: any)
	snapshot = newSnapshot
	if categoryId then
		render()
	end
end

return BuildPickerUI
