--!nonstrict
--[[
	Объёмная буква из тех же штрихов, что буквы Зеркала (Logic/StrokeGlyphs).

	Каждый отрезок ломаной — трубка-цилиндр, на каждой вершине — шарик: стыки
	скруглены, концы тоже. Получается буква, словно согнутая из толстой проволоки
	или вылепленная из теста. Буква стоит в плоскости XY своего CFrame и смотрит
	туда же, куда он: LookVector направлен на зрителя, как лицо на собеседника.

	Раньше буквы в мире были только надписями на билбордах: секретная золотая
	буква уровня — плиткой с надписью в один студ, Азбучная арка — строкой текста.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrokeGlyphs = require(ReplicatedStorage:WaitForChild("Shared").Logic.StrokeGlyphs)

local Letter3D = {}

-- Толщина трубки в долях высоты буквы: толще, чем у плоской буквы, — объёму нужен вес.
Letter3D.THICKNESS = 0.15

export type Options = {
	material: Enum.Material?,
	reflectance: number?,
	-- Тег мелких деталей: у далёких участков клиент их не рисует (DetailLodController).
	detailTag: string?,
}

local function piece(
	model: Model,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	options: Options
)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = options.material or Enum.Material.SmoothPlastic
	part.Reflectance = options.reflectance or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	if options.detailTag then
		CollectionService:AddTag(part, options.detailTag)
	end
	return part
end

--[[
	Строит букву высотой height (сторона квадрата штрихов) с центром в cframe.
	Возвращает модель; её точка привязки — центр буквы.
]]
function Letter3D.build(
	letterId: string,
	height: number,
	cframe: CFrame,
	color: Color3,
	options: Options?
): Model
	local opts = options or {}
	local model = Instance.new("Model")
	model.Name = `Letter3D_{letterId}`

	local diameter = Letter3D.THICKNESS * height
	--[[
		Точка квадрата штрихов (x вправо, y вниз) → место в модели. Зритель стоит
		перед буквой и смотрит ей навстречу, поэтому его «вправо» — это −X кадра.
	]]
	local function at(point: { number }): Vector3
		return (cframe * CFrame.new((0.5 - point[1]) * height, (0.5 - point[2]) * height, 0)).Position
	end

	local balls = 0
	local tubes = 0
	for _, stroke in StrokeGlyphs.strokes(letterId) do
		for index, point in stroke do
			balls += 1
			piece(
				model,
				`Joint_{balls}`,
				Enum.PartType.Ball,
				Vector3.one * diameter,
				CFrame.new(at(point)),
				color,
				opts
			)
			local following = stroke[index + 1]
			if following then
				local a, b = at(point), at(following)
				local length = (b - a).Magnitude
				if length > 0.01 then
					tubes += 1
					-- Ось цилиндра — локальная X; поворачиваем её вдоль отрезка.
					-- «Верх» для lookAt не должен совпадать с отрезком: у вертикальных берём взгляд буквы.
					local direction = (b - a).Unit
					local up = if math.abs(direction:Dot(cframe.UpVector)) > 0.95
						then cframe.LookVector
						else cframe.UpVector
					local frame = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0)
					piece(
						model,
						`Tube_{tubes}`,
						Enum.PartType.Cylinder,
						Vector3.new(length, diameter, diameter),
						frame,
						color,
						opts
					)
				end
			end
		end
	end

	model.WorldPivot = cframe
	return model
end

return Letter3D
