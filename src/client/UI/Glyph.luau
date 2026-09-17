--!nonstrict
--[[
	Буква, которую видно всегда.

	Раньше глифы рисовались через SurfaceGui на грани детали — и стоило ребёнку
	обойти букву сбоку или сзади, как надпись пропадала. Для игры про узнавание букв
	это провал: узнавать нечего.

	BillboardGui всегда развёрнут к камере, поэтому буква читается с любой стороны
	и с любого расстояния.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrokeGlyphs = require(ReplicatedStorage:WaitForChild("Shared").Logic.StrokeGlyphs)

local Glyph = {}

--[[
	Вешает букву на деталь.

	scale — доля от размера САМОЙ детали (от её большей стороны), а не размер
	в студах. Единица = ровно по размеру детали.

	Сама BillboardGui считает долю Scale в СТУДАХ, а не от детали. Долгое время
	здесь стояло обратное убеждение, и буква 0.9 на щите 12×12 была точкой
	в один студ: в Буквопаде, Пузырях, Лестнице и Зеркале ребёнок видел шарики
	и таблички почти без букв. Поэтому доля переводится в студы здесь, явно.
]]
local function studsOf(part: BasePart, scale: number?): number
	local size = part.Size
	return (scale or 1) * math.max(size.X, size.Y, size.Z)
end

function Glyph.attach(part: BasePart, text: string, scale: number?, color: Color3?): BillboardGui
	local existing = part:FindFirstChild("GlyphBillboard")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GlyphBillboard"
	local studs = studsOf(part, scale)
	billboard.Size = UDim2.fromScale(studs, studs)
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

--[[
	Квадратный холст с буквой из штрихов: полоски в долях холста. Вставляется
	куда угодно — в билборд над табличкой или в карточку на экране.
	Квадрат обязателен: доли X и Y у полосок должны значить одно и то же.
	Размер штрихов ничем не ограничен, в отличие от TextScaled (не крупнее
	100 пикселей), поэтому такая буква годится и на весь экран.
]]
function Glyph.strokeCanvas(strokes: { { { number } } }, color: Color3?): Frame
	local canvas = Instance.new("Frame")
	canvas.Name = "Strokes"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.BackgroundTransparency = 1
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = canvas

	local layers = {
		{ width = StrokeGlyphs.WIDTH + StrokeGlyphs.OUTLINE, color = Color3.fromRGB(35, 30, 50), z = 1 },
		{ width = StrokeGlyphs.WIDTH, color = color or Color3.fromRGB(255, 255, 255), z = 2 },
	}
	for _, layer in layers do
		for _, stroke in strokes do
			for index = 1, math.max(1, #stroke - 1) do
				local a = stroke[index]
				local b = stroke[index + 1] or a
				local dx, dy = b[1] - a[1], b[2] - a[2]

				local bar = Instance.new("Frame")
				bar.Name = "Stroke"
				bar.AnchorPoint = Vector2.new(0.5, 0.5)
				bar.Position = UDim2.fromScale((a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
				bar.Size = UDim2.fromScale(math.sqrt(dx * dx + dy * dy) + layer.width, layer.width)
				bar.Rotation = math.deg(math.atan2(dy, dx))
				bar.BackgroundColor3 = layer.color
				bar.BorderSizePixel = 0
				bar.ZIndex = layer.z
				bar.Parent = canvas

				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(1, 0)
				corner.Parent = bar
			end
		end
	end

	return canvas
end

--[[
	Буква, нарисованная штрихами (Logic/StrokeGlyphs), — там, где её надо
	отразить: TextLabel умеет только поворачиваться.

	Каждый отрезок ломаной — полоска со скруглёнными концами, повёрнутая вдоль
	отрезка. Соседние полоски перекрываются кругляшами концов, и ломаная выходит
	гладкой, как от фломастера. Под цветными полосками такие же тёмные, чуть
	толще, — это обводка, как TextStroke у обычной буквы.

	Размеры в долях квадрата, поэтому толщина штриха растёт и падает вместе
	с билбордом на любом расстоянии.
]]
function Glyph.attachStrokes(
	part: BasePart,
	strokes: { { { number } } },
	scale: number?,
	color: Color3?
): BillboardGui
	local existing = part:FindFirstChild("GlyphBillboard")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GlyphBillboard"
	local studs = studsOf(part, scale)
	billboard.Size = UDim2.fromScale(studs, studs)
	-- Поверх всего — по той же причине, что у обычной буквы.
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 250
	billboard.Parent = part

	Glyph.strokeCanvas(strokes, color).Parent = billboard

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
	local canvas = billboard:FindFirstChild("Strokes")
	if canvas then
		for _, bar in canvas:GetChildren() do
			if bar:IsA("Frame") then
				bar.BackgroundTransparency = transparency
			end
		end
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
