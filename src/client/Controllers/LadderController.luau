--!nonstrict
--[[
	Клиентская часть «Алфавитной лестницы».

	Показываем ровно одну ступень за раз: слева буква, на которой мы стоим,
	справа плиты на выбор. Никакой пропасти-угрозы и падения вниз — ребёнок ничем
	не рискует, он просто поднимается. Каждый верный выбор кладёт ступень
	и называет взятую букву.

	Раньше на этом месте был «Мост слогов» с тем же устройством. Изменилось
	не оформление, а вопрос: не «какой звук получится», а «какая буква следующая».
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local Glyph = require(script.Parent.Parent.UI.Glyph)
local HUD = require(script.Parent.Parent.UI.HUD)

local LadderController = {}

local FOLDER_NAME = "AlphabetFall_Ladder"
local RUNG_STEP = 7
local RUNG_RISE = 2.2 -- каждая ступень выше предыдущей: лестница должна расти вверх
local BLOCK_SIZE = Vector3.new(5, 5, 1)

local player = Players.LocalPlayer

local spec: any = nil
local folder: Folder? = nil
local origin = CFrame.new()
local currentSection = 1
local blockedUntil = 0
local sectionParts: { BasePart } = {}

--[[
	Где разворачивать сцену. Сервер присылает точку своей поляны в самом задании
	(Config/Venues): одно задание — одна локация, и сцена больше не растёт
	посреди площади, где её закрывали порталы и чужие пады.

	Если поляны нет (старое задание, забег), остаётся прежний путь — «перед
	ребёнком там, где он стоит».
]]
local function stageOf(from: any): CFrame?
	local stage = from and from.params and from.params.stage
	return if typeof(stage) == "CFrame" then stage else nil
end

local function resolveOrigin(from: any): CFrame
	local stage = stageOf(from)
	if stage then
		-- Лестница уходит вперёд от ребёнка: разворачивать сцену не надо.
		return stage * CFrame.new(0, 3, 0)
	end

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

	Glyph.attach(part, glyph, 0.95)

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

	--[[
		Задание сказано вслух голосом, но озвучки пока нет — дублируем его на экране,
		иначе ребёнок видит только цветные кубы и не знает, что от него хотят.

		Показываем букву, НА КОТОРОЙ стоим, а не ту, которую ищем: подсказать ответ
		значит отменить задание.
	]]
	HUD.showTarget(section.fromGlyph, index - 1, #spec.params.sections)
	HUD.toast(`Какая буква после {section.fromGlyph}?`, 3)

	local base = origin * CFrame.new(0, (index - 1) * RUNG_RISE, -(index - 1) * RUNG_STEP)

	-- Буква, с которой поднимаемся: она никуда не девается, ребёнок видит, откуда шагает
	local from = makeBlock(
		"From",
		section.fromGlyph,
		Letters.expect(section.fromId).color,
		base * CFrame.new(-4.5, 0, 0)
	)
	table.insert(sectionParts, from)

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

-- Ступень лестницы: видимый след того, сколько букв ребёнок уже прошёл по порядку.
local function layStep(index: number, text: string)
	if not folder then
		return
	end

	local base = origin * CFrame.new(0, (index - 1) * RUNG_RISE - 2.5, -(index - 1) * RUNG_STEP)
	local step = Instance.new("Part")
	step.Name = `Step_{index}`
	step.Size = Vector3.new(10, 0.6, 6)
	step.CFrame = base
	step.Color = Color3.fromRGB(200, 170, 120)
	step.Anchored = true
	step.Material = Enum.Material.WoodPlanks
	step.Transparency = 1
	step.Parent = folder

	-- Взятая буква остаётся написанной на ступени: ребёнок видит кусок алфавита,
	-- который он выложил сам, и это самая честная награда в игре.
	Glyph.attach(step, text, 0.55, Color3.fromRGB(255, 245, 220))

	TweenService:Create(step, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Transparency = 0 }):Play()
end

function LadderController.start(newSpec: any)
	LadderController.stop()

	spec = newSpec
	currentSection = 1
	blockedUntil = 0
	origin = resolveOrigin(newSpec)

	local container = Instance.new("Folder")
	container.Name = FOLDER_NAME
	container.Parent = workspace
	folder = container

	showSection(1)
end

function LadderController.feedback(fb: any)
	if not spec then
		return
	end

	if fb.correct then
		layStep(fb.sectionIndex or currentSection, fb.stepGlyph or "")
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

function LadderController.stop()
	clearSection()
	if folder then
		folder:Destroy()
		folder = nil
	end
	spec = nil
	blockedUntil = 0
	currentSection = 1
end

return LadderController
