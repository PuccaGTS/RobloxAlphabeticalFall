--!nonstrict
--[[
	Клиентская часть «Моста слогов».

	Показываем ровно одну секцию за раз: слева согласная, справа гласные на выбор.
	Никакой пропасти-угрозы и падения вниз — ребёнок ничем не рискует, он просто
	достраивает мост. Каждый верный выбор кладёт доску и звучит слитным слогом.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local BridgeController = {}

local FOLDER_NAME = "AlphabetFall_Bridge"
local PLANK_STEP = 7
local BLOCK_SIZE = Vector3.new(4, 4, 0.8)

local player = Players.LocalPlayer

local spec: any = nil
local folder: Folder? = nil
local origin = CFrame.new()
local currentSection = 1
local blockedUntil = 0
local sectionParts: { BasePart } = {}

local function resolveOrigin(): CFrame
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.CFrame * CFrame.new(0, 0, -12)
	end
	return CFrame.new(0, 4, 0)
end

local function makeBlock(name: string, glyph: string, color: Color3, cframe: CFrame): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = BLOCK_SIZE
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = folder

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(200, 200)
	surface.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = glyph
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = surface

	return part
end

local function clearSection()
	for _, part in sectionParts do
		part:Destroy()
	end
	sectionParts = {}
end

local function showSection(index: number)
	clearSection()
	if not spec then
		return
	end

	local section = spec.params.sections[index]
	if not section then
		return
	end

	local base = origin * CFrame.new(0, 0, -(index - 1) * PLANK_STEP)

	-- Согласная: она никуда не девается, ребёнок «приставляет» к ней гласную
	local consonant = makeBlock(
		"Consonant",
		section.consonantGlyph,
		Letters.expect(section.consonantId).color,
		base * CFrame.new(-4.5, 0, 0)
	)
	table.insert(sectionParts, consonant)

	for order, choice in section.choices do
		local offset = 2 + (order - 1) * 5
		local block = makeBlock(
			`Choice_{choice.letterId}`,
			choice.glyph,
			Letters.expect(choice.letterId).color,
			base * CFrame.new(offset, 0, 0)
		)
		table.insert(sectionParts, block)

		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 200
		click.Parent = block

		click.MouseClick:Connect(function()
			if not spec or os.clock() < blockedUntil then
				return
			end
			RemoteDefs.event("ChallengeAction"):FireServer({
				sectionIndex = index,
				letterId = choice.letterId,
			})
		end)
	end
end

-- Доска моста: видимый след того, что ребёнок уже прочитал.
local function layPlank(index: number, text: string)
	if not folder then
		return
	end

	local base = origin * CFrame.new(0, -2.5, -(index - 1) * PLANK_STEP)
	local plank = Instance.new("Part")
	plank.Name = `Plank_{index}`
	plank.Size = Vector3.new(10, 0.6, 6)
	plank.CFrame = base
	plank.Color = Color3.fromRGB(200, 170, 120)
	plank.Anchored = true
	plank.Material = Enum.Material.WoodPlanks
	plank.Transparency = 1
	plank.Parent = folder

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.CanvasSize = Vector2.new(400, 200)
	surface.Parent = plank

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(60, 45, 30)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = surface

	TweenService:Create(plank, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Transparency = 0 }):Play()
end

function BridgeController.start(newSpec: any)
	BridgeController.stop()

	spec = newSpec
	currentSection = 1
	blockedUntil = 0
	origin = resolveOrigin()

	local container = Instance.new("Folder")
	container.Name = FOLDER_NAME
	container.Parent = workspace
	folder = container

	showSection(1)
end

function BridgeController.feedback(fb: any)
	if not spec then
		return
	end

	if fb.correct then
		layPlank(fb.sectionIndex or currentSection, fb.syllableText or "")
		currentSection = (fb.sectionIndex or currentSection) + 1
		task.delay(0.9, function()
			if spec then
				showSection(currentSection)
			end
		end)
	else
		blockedUntil = os.clock() + (fb.cooldown or 0)
		-- Промах не убирает выбор: буквы остаются на месте, чтобы ребёнок
		-- мог попробовать снова, дослушав подсказку.
		for _, part in sectionParts do
			part.Transparency = 0.6
		end
		task.delay(fb.cooldown or 0, function()
			for _, part in sectionParts do
				if part.Parent then
					part.Transparency = 0
				end
			end
		end)
	end
end

function BridgeController.stop()
	clearSection()
	if folder then
		folder:Destroy()
		folder = nil
	end
	spec = nil
	blockedUntil = 0
	currentSection = 1
end

return BridgeController
