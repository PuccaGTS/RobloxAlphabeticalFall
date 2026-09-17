--!nonstrict
--[[
	Мелкие строители для сцен испытаний на клиенте.

	Щит Буквопада и таблички Зеркала были голыми брусками: на поляне под небом
	кремовая плита выходила серой коробкой, и сцена читалась как заготовка.
	Панель в раме — то же самое место под букву, но похожее на вещь: вывеску,
	зеркало, табло.
]]

local Props = {}

local function piece(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--[[
	Панель в раме. Возвращает саму панель (face): на неё вешают букву, она ловит
	касания. Рама и ножки — её дети, поэтому исчезают вместе с ней, а
	Props.setTransparency гасит всё разом.

	size — размер панели без рамы; frame — ширина рамы; legs — высота ножек до земли
	(0 — без ножек, панель висит, как табло).
]]
function Props.framedPanel(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	faceColor: Color3,
	frameColor: Color3,
	frame: number,
	legs: number?
): BasePart
	local face = piece(name, size, cframe, faceColor, parent)
	local depth = size.Z + 0.3
	local halfX, halfY = size.X / 2, size.Y / 2
	for _, spec in
		{
			{
				"FrameTop",
				Vector3.new(size.X + frame * 2, frame, depth),
				Vector3.new(0, halfY + frame / 2, 0),
			},
			{
				"FrameBottom",
				Vector3.new(size.X + frame * 2, frame, depth),
				Vector3.new(0, -halfY - frame / 2, 0),
			},
			{ "FrameLeft", Vector3.new(frame, size.Y, depth), Vector3.new(-halfX - frame / 2, 0, 0) },
			{ "FrameRight", Vector3.new(frame, size.Y, depth), Vector3.new(halfX + frame / 2, 0, 0) },
		}
	do
		local bar = piece(spec[1], spec[2], cframe * CFrame.new(spec[3]), frameColor, face)
		bar.Material = Enum.Material.Wood
	end
	-- Уголки-шарики: рама перестаёт быть четырьмя палками.
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			local knob = piece(
				"FrameKnob",
				Vector3.one * frame * 1.5,
				cframe * CFrame.new(sx * (halfX + frame / 2), sy * (halfY + frame / 2), 0),
				frameColor:Lerp(Color3.new(1, 1, 1), 0.25),
				face
			)
			knob.Shape = Enum.PartType.Ball
		end
	end
	if legs and legs > 0 then
		for _, sx in { -1, 1 } do
			local leg = piece(
				"Leg",
				Vector3.new(frame * 0.8, legs, frame * 0.8),
				cframe * CFrame.new(sx * (halfX - frame), -halfY - frame - legs / 2, 0),
				frameColor,
				face
			)
			leg.Material = Enum.Material.Wood
		end
	end
	return face
end

-- Прозрачность панели вместе с рамой и ножками.
function Props.setTransparency(face: BasePart, transparency: number)
	face.Transparency = transparency
	for _, child in face:GetChildren() do
		if child:IsA("BasePart") then
			child.Transparency = transparency
		end
	end
end

return Props
