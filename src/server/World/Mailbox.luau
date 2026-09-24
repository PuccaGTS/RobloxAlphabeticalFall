--!nonstrict
--[[
	Почтовый ящик у калитки (Logic/Mail): столбик, синий ящик с полукруглой
	крышкой, дверца с сердечком и красный флажок сбоку. Флажок поднимает и 💌
	над ящиком зажигает клиент (MailController) — по атрибуту хозяина MailUnread,
	его ставит MailService. Касание и подсказку ловит MailService по метке Mailbox.
]]

local CollectionService = game:GetService("CollectionService")

local Mailbox = {}

Mailbox.TAG = "Mailbox"
-- Снаружи у калитки, справа от неё, если смотреть с дорожки: к ящику подходят по пути домой.
Mailbox.OFFSET = CFrame.new(-7.8, 0, -35.5)

local BOX = Color3.fromRGB(90, 150, 235)
local WOOD = Color3.fromRGB(170, 120, 80)

local function part(model: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.Parent = model
	return p
end

local function ghost(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

--[[
	Ящик участка plotFrame (−Z смотрит на площадь) для хозяина owner.
	Возвращает модель; слушать касания — дело MailService.
]]
function Mailbox.build(parent: Instance, plotFrame: CFrame, owner: Player): Model
	local model = Instance.new("Model")
	model.Name = "Mailbox"
	model:SetAttribute("Owner", owner.UserId)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = parent
	local at = plotFrame * Mailbox.OFFSET

	part(model, "Post", Vector3.new(0.5, 3.6, 0.5), at * CFrame.new(0, 1.8, 0), WOOD).Material =
		Enum.Material.Wood
	ghost(part(model, "Foot", Vector3.new(1.4, 0.3, 1.4), at * CFrame.new(0, 0.15, 0), WOOD))

	local body = part(model, "Box", Vector3.new(1.7, 1.3, 2.6), at * CFrame.new(0, 4.2, 0), BOX)
	local lid = ghost(
		part(
			model,
			"Lid",
			Vector3.new(2.6, 1.7, 1.7),
			at * CFrame.new(0, 4.85, 0) * CFrame.Angles(0, math.pi / 2, 0),
			BOX
		)
	)
	lid.Shape = Enum.PartType.Cylinder
	-- Дверца спереди, к дорожке, с розовым сердечком.
	ghost(
		part(
			model,
			"Door",
			Vector3.new(1.5, 1.9, 0.12),
			at * CFrame.new(0, 4.5, -1.33),
			Color3.fromRGB(70, 125, 215)
		)
	)
	local heart = ghost(
		part(
			model,
			"Heart",
			Vector3.new(0.8, 0.8, 0.12),
			at * CFrame.new(0, 4.55, -1.42),
			Color3.fromRGB(255, 120, 160)
		)
	)
	heart.Shape = Enum.PartType.Ball
	-- Белый конвертик на боку: что это ящик, видно и без двери.
	ghost(
		part(
			model,
			"Envelope",
			Vector3.new(0.08, 0.7, 1.1),
			at * CFrame.new(-0.88, 4.2, 0.1),
			Color3.fromRGB(255, 255, 255)
		)
	)

	--[[
		Флажок на оси сбоку: лежит назад, пока писем нет, и встаёт торчком,
		когда пришли. Base — ось; клиент крутит флажок вокруг X.
	]]
	local pivot = at * CFrame.new(0.95, 4.2, 0.6)
	local arm = ghost(
		part(
			model,
			"FlagArm",
			Vector3.new(0.14, 1.5, 0.22),
			pivot * CFrame.new(0, 0.75, 0),
			Color3.fromRGB(235, 60, 70)
		)
	)
	local paddle = ghost(
		part(
			model,
			"FlagPaddle",
			Vector3.new(0.14, 0.55, 0.7),
			pivot * CFrame.new(0, 1.3, 0.3),
			Color3.fromRGB(235, 60, 70)
		)
	)
	for _, piece in { arm, paddle } do
		piece:SetAttribute("Pivot", pivot)
		piece:SetAttribute("Offset", pivot:ToObjectSpace(piece.CFrame))
	end

	-- 💌 над ящиком: горит, пока есть непрочитанные открытки (клиент).
	local anchor = ghost(part(model, "Bubble", Vector3.new(0.4, 0.4, 0.4), at * CFrame.new(0, 6.8, 0), BOX))
	anchor.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Mail"
	billboard.Size = UDim2.fromScale(2.6, 2.6)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 150
	billboard.Enabled = false
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "💌"
	label.TextScaled = true
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Открыть"
	prompt.ObjectText = "Почта"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	model.PrimaryPart = body
	CollectionService:AddTag(model, Mailbox.TAG)
	return model
end

return Mailbox
