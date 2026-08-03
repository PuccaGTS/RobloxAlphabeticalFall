--!nonstrict
--[[
	Буква, которую видно всегда.

	Раньше глифы рисовались через SurfaceGui на грани детали — и стоило ребёнку
	обойти букву сбоку или сзади, как надпись пропадала. Для игры про узнавание букв
	это провал: узнавать нечего.

	BillboardGui всегда развёрнут к камере, поэтому буква читается с любой стороны
	и с любого расстояния.
]]

local Glyph = {}

--[[
	Вешает букву на деталь.

	scale — доля от размера САМОЙ детали, а не размер в студах. У BillboardGui
	доля Scale считается от адорни: значение 6 на пятистудовом кубике давало
	надпись в тридцать студов, буквы перекрывали друг друга и «менялись» при
	движении камеры. Единица = ровно по размеру детали.
]]
function Glyph.attach(part: BasePart, text: string, scale: number?, color: Color3?): BillboardGui
	local existing = part:FindFirstChild("GlyphBillboard")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GlyphBillboard"
	billboard.Size = UDim2.fromScale(scale or 1, scale or 1)
	billboard.SizeOffset = Vector2.new(0, 0)
	--[[
		Обязательно поверх всего.

		Билборд висит в ЦЕНТРЕ детали, и без этого флага его загораживает сама деталь:
		на экране остаётся просто цветной кубик без буквы. Подписи падов было видно
		только потому, что они подняты над платформой через StudsOffset.
	]]
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 250
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Glyph"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(35, 30, 50)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard

	return billboard
end

function Glyph.setTransparency(part: BasePart, transparency: number)
	local billboard = part:FindFirstChild("GlyphBillboard")
	if not billboard then
		return
	end
	local label = billboard:FindFirstChild("Glyph")
	if label and label:IsA("TextLabel") then
		label.TextTransparency = transparency
		label.TextStrokeTransparency = transparency
	end
end

--[[
	Подпись над объектом (название пада, счётчик). Размер в ПИКСЕЛЯХ:
	у BillboardGui доля Scale считается от размера детали, и подпись на большой
	платформе раздувается до нечитаемой. Offset ведёт себя предсказуемо.
]]
function Glyph.caption(part: BasePart, text: string, heightStuds: number): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Caption"
	billboard.Size = UDim2.fromOffset(260, 80)
	billboard.StudsOffset = Vector3.new(0, heightStuds, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 200
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(35, 30, 50)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard

	return billboard
end

return Glyph
