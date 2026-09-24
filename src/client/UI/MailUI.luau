--!strict
--[[
	Почта от буквят (Logic/Mail): открытки и альбом.

	Открыл ящик — если пришли новые открытки, они идут по одной: конверт
	подпрыгивает и раскрывается, на открытке зверёк-буквёнок в кружке цвета
	своей буквы, марка, крупная буква штрихами и картинка к ней. Буква главная:
	она крупнее всего. После новых — альбом: все 33 места, пришедшие открытки
	цветные, остальные ждут с «?». Тап по открытке в альбоме — снова её показать.

	Читать ребёнку ничего не надо: кнопки — стрелка и крестик, открытка —
	картинки. Слово под картинкой для взрослого рядом (как на карточке знакомства).
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local Pets = require(Shared.Logic.Pets)
local StrokeGlyphs = require(Shared.Logic.StrokeGlyphs)

local Glyph = require(script.Parent.Glyph)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)

local MailUI = {}

local PAPER = Color3.fromRGB(255, 250, 238)
local INK = Color3.fromRGB(90, 80, 70)
local DESIGN = Vector2.new(360, 470)

local gui: ScreenGui? = nil

local function corner(object: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radius, 0)
	c.Parent = object
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = color or INK
	l.Parent = parent
	return l
end

local function sound(key: string, volume: number)
	local id = AudioRegistry.ids[key]
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.SoundGroup = AudioController.group("SFX")
	s.Parent = SoundService
	s.Ended:Connect(function()
		s:Destroy()
	end)
	s:Play()
end

local function roundButton(
	parent: Instance,
	name: string,
	text: string,
	color: Color3,
	position: UDim2,
	size: number
): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = position
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = color
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextScaled = true
	b.Font = Enum.Font.FredokaOne
	b.Parent = parent
	corner(b, 0.5)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(1, 1, 1)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	return b
end

function MailUI.close()
	if gui then
		gui:Destroy()
		gui = nil
	end
end

function MailUI.isOpen(): boolean
	return gui ~= nil
end

-- Открытка буквы id: во всю панель. Возвращает саму открытку.
local function buildCard(parent: Instance, id: string): Frame
	local letter = Letters.expect(id)
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromOffset(DESIGN.X / 2, 205)
	card.Size = UDim2.fromOffset(320, 380)
	card.BackgroundColor3 = PAPER
	card.Parent = parent
	corner(card, 0.06)
	local border = Instance.new("UIStroke")
	border.Thickness = 5
	border.Color = letter.color
	border.Parent = card

	-- Буквёнок-отправитель: зверёк в кружке цвета буквы, с буквой на значке.
	local sender = Instance.new("Frame")
	sender.Size = UDim2.fromOffset(84, 84)
	sender.Position = UDim2.fromOffset(14, 14)
	sender.BackgroundColor3 = letter.color:Lerp(Color3.new(1, 1, 1), 0.35)
	sender.Parent = card
	corner(sender, 0.5)
	label(
		sender,
		Pets.SPECIES_ICONS[Pets.speciesOf(id)] or "🐾",
		UDim2.fromScale(0.8, 0.8),
		UDim2.fromScale(0.1, 0.08)
	)
	local badge = Instance.new("Frame")
	badge.Size = UDim2.fromOffset(34, 34)
	badge.Position = UDim2.fromOffset(58, 56)
	badge.BackgroundColor3 = Color3.new(1, 1, 1)
	badge.Parent = sender
	corner(badge, 0.5)
	label(badge, letter.glyph, UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.1, 0.1), letter.color)
	label(card, "💌", UDim2.fromOffset(48, 48), UDim2.fromOffset(112, 30))

	-- Марка в углу: зубчатый край из белой рамки, внутри звёздочка.
	local stamp = Instance.new("Frame")
	stamp.Size = UDim2.fromOffset(66, 78)
	stamp.Position = UDim2.fromOffset(236, 16)
	stamp.Rotation = 8
	stamp.BackgroundColor3 = letter.color:Lerp(Color3.new(1, 1, 1), 0.55)
	stamp.Parent = card
	local stampEdge = Instance.new("UIStroke")
	stampEdge.Thickness = 4
	stampEdge.Color = Color3.new(1, 1, 1)
	stampEdge.Parent = stamp
	label(stamp, "⭐", UDim2.fromScale(0.8, 0.6), UDim2.fromScale(0.1, 0.2))

	-- Буква — главное на открытке: штрихами, крупно.
	local holder = Instance.new("Frame")
	holder.Name = "Glyph"
	holder.Size = UDim2.fromOffset(200, 170)
	holder.Position = UDim2.fromOffset(60, 104)
	holder.BackgroundTransparency = 1
	holder.Parent = card
	if StrokeGlyphs.has(id) then
		Glyph.strokeCanvas(StrokeGlyphs.strokes(id), letter.color).Parent = holder
	else
		label(holder, letter.glyph, UDim2.fromScale(1, 1), UDim2.new(), letter.color)
	end

	-- Картинка к букве и слово — для взрослого рядом.
	local strip = Instance.new("Frame")
	strip.Size = UDim2.fromOffset(280, 80)
	strip.Position = UDim2.fromOffset(20, 286)
	strip.BackgroundColor3 = Color3.fromRGB(245, 236, 215)
	strip.Parent = card
	corner(strip, 0.25)
	if letter.picture ~= "" then
		label(strip, letter.picture, UDim2.fromOffset(70, 70), UDim2.fromOffset(12, 5))
	end
	local word = label(strip, letter.example, UDim2.fromOffset(180, 40), UDim2.fromOffset(90, 20))
	word.TextXAlignment = Enum.TextXAlignment.Left
	return card
end

--[[
	Конверт подпрыгивает, потом раскрывается открыткой. Голос называет
	букву (пока реплик нет — молчит, в субтитрах виден текст).
]]
local function reveal(panel: Frame, id: string): Frame
	local envelope =
		label(panel, "✉️", UDim2.fromOffset(150, 150), UDim2.fromOffset(DESIGN.X / 2 - 75, 130))
	envelope.Name = "Envelope"
	sound("sfx_mail_open", 0.7)
	local up = TweenService:Create(
		envelope,
		TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true),
		{
			Position = UDim2.fromOffset(DESIGN.X / 2 - 75, 90),
		}
	)
	up:Play()
	local card = buildCard(panel, id)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.05
	scale.Parent = card
	card.Visible = false
	task.delay(0.5, function()
		if not card.Parent then
			return
		end
		envelope:Destroy()
		card.Visible = true
		TweenService
			:Create(
				scale,
				TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }
			)
			:Play()
		sound("sfx_magic", 0.6)
		AudioController.speak(Letters.expect(id).vo.name)
	end)
	return card
end

local showAlbum: (panel: Frame, all: { string }) -> ()

-- Новые открытки по одной; последняя стрелка ведёт в альбом.
local function showFresh(panel: Frame, fresh: { string }, all: { string }, index: number)
	for _, child in panel:GetChildren() do
		if child.Name ~= "Close" and child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	reveal(panel, fresh[index])
	-- Точки внизу: сколько открыток пришло и какая сейчас.
	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.BackgroundTransparency = 1
	dots.Size = UDim2.fromOffset(200, 16)
	dots.Position = UDim2.fromOffset(DESIGN.X / 2 - 100, 402)
	dots.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = dots
	for dot = 1, math.min(#fresh, 12) do
		local d = Instance.new("Frame")
		d.Size = UDim2.fromOffset(12, 12)
		d.BackgroundColor3 = if dot == index
			then Color3.fromRGB(255, 200, 70)
			else Color3.fromRGB(255, 255, 255)
		d.Parent = dots
		corner(d, 0.5)
	end
	local forward = roundButton(
		panel,
		"Next",
		"▶",
		Color3.fromRGB(90, 200, 120),
		UDim2.fromOffset(DESIGN.X / 2, 440),
		58
	)
	forward.Activated:Connect(function()
		if index < #fresh then
			showFresh(panel, fresh, all, index + 1)
		else
			showAlbum(panel, all)
		end
	end)
end

-- Одна открытка из альбома: стрелка назад возвращает в альбом.
local function showOne(panel: Frame, id: string, all: { string })
	for _, child in panel:GetChildren() do
		if child.Name ~= "Close" and child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	reveal(panel, id)
	local back = roundButton(
		panel,
		"Back",
		"◀",
		Color3.fromRGB(120, 160, 240),
		UDim2.fromOffset(DESIGN.X / 2, 440),
		58
	)
	back.Activated:Connect(function()
		showAlbum(panel, all)
	end)
end

function showAlbum(panel: Frame, all: { string })
	for _, child in panel:GetChildren() do
		if child.Name ~= "Close" and child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local received: { [string]: boolean } = {}
	for _, id in all do
		received[id] = true
	end
	local sheet = Instance.new("Frame")
	sheet.Name = "Album"
	sheet.Size = UDim2.fromOffset(DESIGN.X, 450)
	sheet.BackgroundColor3 = PAPER
	sheet.Parent = panel
	corner(sheet, 0.05)
	label(sheet, `📬  {#all} / {#Letters.ordered()}`, UDim2.fromOffset(220, 40), UDim2.fromOffset(20, 12))

	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromOffset(DESIGN.X - 24, 380)
	grid.Position = UDim2.fromOffset(12, 60)
	grid.Parent = sheet
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(52, 58)
	layout.CellPadding = UDim2.fromOffset(4, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for order, id in Letters.ordered() do
		local letter = Letters.expect(id)
		local cell = Instance.new("TextButton")
		cell.Name = `Slot_{id}`
		cell.LayoutOrder = order
		cell.Text = ""
		cell.AutoButtonColor = received[id] == true
		cell.BackgroundColor3 = if received[id]
			then letter.color:Lerp(Color3.new(1, 1, 1), 0.7)
			else Color3.fromRGB(228, 224, 216)
		cell.Parent = grid
		corner(cell, 0.2)
		if received[id] then
			label(cell, letter.glyph, UDim2.fromScale(0.8, 0.62), UDim2.fromScale(0.1, 0.04), letter.color)
			if letter.picture ~= "" then
				label(cell, letter.picture, UDim2.fromScale(0.4, 0.34), UDim2.fromScale(0.56, 0.62))
			end
			cell.Activated:Connect(function()
				showOne(panel, id, all)
			end)
		else
			label(
				cell,
				"?",
				UDim2.fromScale(0.5, 0.5),
				UDim2.fromScale(0.25, 0.25),
				Color3.fromRGB(200, 195, 185)
			)
		end
	end
end

--[[
	Открыть почту: fresh — новые открытки (показываются по одной), all — все
	пришедшие, для альбома. Новых нет — сразу альбом.
]]
function MailUI.show(fresh: { string }, all: { string })
	MailUI.close()
	local screen = Instance.new("ScreenGui")
	screen.Name = "AlphabetFallMail"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 20
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
	dim.BackgroundTransparency = 0.45
	dim.Active = true
	dim.Parent = screen

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
	panel.BackgroundTransparency = 1
	panel.Parent = screen
	local fit = Instance.new("UIScale")
	local size = screen.AbsoluteSize
	fit.Scale = if size.Y > 0 then math.min(size.Y * 0.88 / DESIGN.Y, size.X * 0.92 / DESIGN.X) else 1
	fit.Parent = panel

	local close = roundButton(
		panel,
		"Close",
		"✖",
		Color3.fromRGB(240, 90, 100),
		UDim2.fromOffset(DESIGN.X - 6, 6),
		46
	)
	close.ZIndex = 5
	close.Activated:Connect(MailUI.close)

	if #fresh > 0 then
		showFresh(panel, fresh, all, 1)
	else
		showAlbum(panel, all)
	end
end

return MailUI
