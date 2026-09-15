--!nonstrict
--[[
	Табличка прогресса над каждым порталом: «Уровень 3 из 11 · Ёжики»,
	«Уровень 2 из 11 · Тропа цифр». См. docs/14-TUNNEL-MODE.md § 3.2.

	Это единственное место в мире, где показаны цифры прогресса, и адресованы они
	скорее родителю: ребёнок цифр не читает, а взрослый рядом с одного взгляда видит,
	куда ведёт портал.

	Табличка у каждого своя — у одного ребёнка третий уровень, у другого первый, —
	поэтому её ставит клиент, как и Башню. Созданное клиентом в workspace видит
	только он сам, соседям достаётся своя табличка.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Levels = require(Shared.Config.Levels)
local MathLevels = require(Shared.Config.MathLevels)

local PortalSignController = {}

local SIGN_NAME = "ProgressSign"

-- Портал ищем по имени арки, которое ставит WorldService: `PortalArch_{id}`.
local function archOf(portalId: string): BasePart?
	local hub = workspace:FindFirstChild("Hub")
	local arch = hub and hub:FindFirstChild(`PortalArch_{portalId}`)
	if arch and arch:IsA("BasePart") then
		return arch
	end
	return nil
end

local function signOn(arch: BasePart): TextLabel
	local existing = arch:FindFirstChild(SIGN_NAME)
	if existing then
		return existing:FindFirstChildOfClass("TextLabel")
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = SIGN_NAME
	-- Размер в пикселях по той же причине, что у подписей падов: Scale у билборда
	-- считается от детали, и на широкой арке табличка раздулась бы.
	billboard.Size = UDim2.fromOffset(300, 56)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 70
	billboard.Parent = arch

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(255, 240, 200)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label

	return label
end

-- Тексты табличек по срезу профиля. Отдельно от мира — чтобы понять, что писать,
-- не нужен ни workspace, ни порталы.
function PortalSignController.texts(snapshot: any): { [string]: string }
	local cleared = Levels.sanitize(snapshot.levels)[Levels.WORLD]
	local level = Levels.current(cleared)
	local stage = Levels.stage(level)

	local mathIndex = MathLevels.current(Levels.sanitize(snapshot.levels)[MathLevels.WORLD])

	return {
		letters = `Уровень {level} из {Levels.count()} · {stage.title}`,
		math = `Уровень {mathIndex} из {MathLevels.count()} · {MathLevels.expect(mathIndex).title}`,
	}
end

local latest: { [string]: string } = {}
local waiting: { [string]: boolean } = {}

--[[
	Срез профиля может прийти раньше, чем площадь доедет до клиента. Тогда
	табличку ставим, как только появится арка, — с последним известным текстом,
	а не с тем, что был на момент ожидания.
]]
local function placeWhenReady(portalId: string)
	if waiting[portalId] then
		return
	end
	waiting[portalId] = true
	task.spawn(function()
		local hub = workspace:WaitForChild("Hub", 60)
		local arch = hub and hub:WaitForChild(`PortalArch_{portalId}`, 60)
		waiting[portalId] = nil
		if arch and arch:IsA("BasePart") then
			signOn(arch).Text = latest[portalId]
		end
	end)
end

function PortalSignController.update(snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end
	for portalId, text in PortalSignController.texts(snapshot) do
		latest[portalId] = text
		local arch = archOf(portalId)
		if arch then
			signOn(arch).Text = text
		else
			placeWhenReady(portalId)
		end
	end
end

return PortalSignController
