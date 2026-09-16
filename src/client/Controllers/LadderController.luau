--!nonstrict
--[[
	Клиентская часть «Алфавитной лестницы».

	Это подъём на гору, а не клик по кубикам. Раньше перед ребёнком висели
	в воздухе цветные блоки, по которым надо было щёлкать издалека, а «ступени»
	появлялись сами где-то сбоку — и на первой же проверке было непонятно,
	что здесь вообще происходит.

	Теперь гора видна целиком с первой секунды: ступени уходят вверх, на первой
	написана буква, с которой начинаем, на остальных — «?», а на вершине стоит
	звезда. На ступени, где стоит ребёнок, лежат плиты с буквами. Какая буква
	идёт следующей — на ту плиту и надо встать. Верно — вопрос на следующей
	ступени превращается в букву, прозрачная преграда исчезает, и можно
	подниматься. На вершине звезда загорается, а вдоль всей горы написан кусок
	алфавита, который ребёнок выложил сам.

	Упасть некуда, проиграть нельзя: промах только ненадолго опускает плиту.
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

--[[
	Ступень невысокая: персонаж заходит на неё шагом, прыгать не нужно.
	Пятилетний ребёнок на планшете прыжок нажимает не всегда, а подъём
	не должен превращаться в проверку ловкости.
]]
local STEP_WIDTH = 18
--[[
	Глубина ступени и вершины посчитаны под поляну: восемь ступеней с вершиной
	занимают около шестидесяти студов и не упираются в задник (Config/Venues.SIZE).
]]
local STEP_DEPTH = 5.5
local STEP_RISE = 1.6
local SUMMIT_DEPTH = 10

local PAD_SIZE = 4.2
local PAD_GAP = 5.5

local STONE = Color3.fromRGB(205, 190, 235)
local STONE_DARK = Color3.fromRGB(165, 145, 210)
local GOLD = Color3.fromRGB(255, 214, 102)

local player = Players.LocalPlayer

local spec: any = nil
local folder: Folder? = nil
local origin = CFrame.new()
local currentSection = 1
local blockedUntil = 0
local sectionParts: { BasePart } = {}
local signs: { BasePart } = {}
local barriers: { BasePart } = {}
local summitStar: BasePart? = nil
local hintThread: thread? = nil

--[[
	Где разворачивается сцена. Сервер присылает точку своей поляны в самом задании
	(Config/Venues): одно задание — одна локация.
]]
local function stageOf(from: any): CFrame?
	local stage = from and from.params and from.params.stage
	return if typeof(stage) == "CFrame" then stage else nil
end

local function resolveOrigin(from: any): CFrame
	local stage = stageOf(from)
	if stage then
		-- Подножие горы в шести студах перед ребёнком; гора уходит от него вперёд.
		return stage * CFrame.new(0, 0, 20)
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.05 then
			flat = Vector3.new(0, 0, -1)
		end
		local base = root.Position + flat.Unit * 10 - Vector3.new(0, 3, 0)
		return CFrame.lookAt(base, base + flat.Unit)
	end
	return CFrame.new(0, 0, 0)
end

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = folder
	return part
end

-- Верх ступени k: первая стоит почти на полу, каждая следующая на STEP_RISE выше.
local function stepTop(k: number): number
	return (k - 1) * STEP_RISE + 1
end

local function stepCenterZ(k: number): number
	return -(k - 1) * STEP_DEPTH - STEP_DEPTH / 2
end

--[[
	Гора целиком: ступени, указатели с буквами слева, боковые стенки и вершина.
	Строится один раз на всё испытание — ребёнок с первой секунды видит,
	куда поднимается и сколько осталось.
]]
local function buildMountain(sections: { any })
	local count = #sections + 1

	for k = 1, count do
		local top = stepTop(k)
		local step = block(
			`Step_{k}`,
			Vector3.new(STEP_WIDTH, top, STEP_DEPTH),
			origin * CFrame.new(0, top / 2, stepCenterZ(k)),
			if k % 2 == 0 then STONE else STONE_DARK
		)
		step.Material = Enum.Material.Slate

		-- Указатель у левого края: на первой ступени буква старта, дальше вопросы.
		local post = block(
			`SignPost_{k}`,
			Vector3.new(0.5, 4, 0.5),
			origin * CFrame.new(-STEP_WIDTH / 2 - 1.2, top + 2, stepCenterZ(k)),
			Color3.fromRGB(150, 120, 90)
		)
		post.CanCollide = false

		local sign = block(
			`Sign_{k}`,
			Vector3.new(3, 3, 0.4),
			origin * CFrame.new(-STEP_WIDTH / 2 - 1.2, top + 4.8, stepCenterZ(k)),
			if k == 1 then Letters.expect(sections[1].fromId).color else Color3.fromRGB(240, 235, 250)
		)
		sign.CanCollide = false
		Glyph.attach(
			sign,
			if k == 1 then sections[1].fromGlyph else "?",
			1.3,
			if k == 1 then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(150, 130, 190)
		)
		signs[k] = sign

		--[[
			Прозрачная преграда перед следующей ступенью. Пока буква не угадана,
			выше не пройти, — но и сзади ничто не держит: вернуться вниз можно всегда.
		]]
		if k < count then
			local barrier = block(
				`Barrier_{k}`,
				Vector3.new(STEP_WIDTH, 14, 0.6),
				origin * CFrame.new(0, top + 7, -k * STEP_DEPTH),
				Color3.fromRGB(255, 255, 255)
			)
			barrier.Transparency = 0.85
			barrier.Material = Enum.Material.ForceField
			barriers[k] = barrier
		end
	end

	-- Боковые стенки: на верхние ступени не заберёшься в обход, сбоку по кочкам.
	local length = count * STEP_DEPTH + SUMMIT_DEPTH
	for _, side in { -1, 1 } do
		local wall = block(
			`SideWall_{side}`,
			Vector3.new(0.6, 30, length),
			origin * CFrame.new(side * (STEP_WIDTH / 2 + 0.3), 15, -length / 2),
			Color3.fromRGB(255, 255, 255)
		)
		wall.Transparency = 1
	end

	-- Вершина: площадка, флаг и звезда. Звезда тусклая, пока до неё не дошли.
	local summitTop = stepTop(count)
	local summitZ = -count * STEP_DEPTH - SUMMIT_DEPTH / 2
	local summit = block(
		"Summit",
		Vector3.new(STEP_WIDTH, summitTop, SUMMIT_DEPTH),
		origin * CFrame.new(0, summitTop / 2, summitZ),
		Color3.fromRGB(235, 225, 250)
	)
	summit.Material = Enum.Material.Marble

	local pole = block(
		"FlagPole",
		Vector3.new(0.5, 12, 0.5),
		origin * CFrame.new(5, summitTop + 6, summitZ),
		Color3.fromRGB(240, 240, 245)
	)
	pole.CanCollide = false
	local flag = block(
		"Flag",
		Vector3.new(4, 2.6, 0.2),
		origin * CFrame.new(7.2, summitTop + 10.5, summitZ),
		Color3.fromRGB(240, 110, 130)
	)
	flag.CanCollide = false

	local star = block(
		"SummitStar",
		Vector3.new(4, 4, 4),
		origin * CFrame.new(0, summitTop + 4, summitZ),
		Color3.fromRGB(190, 180, 150)
	)
	star.Shape = Enum.PartType.Ball
	star.CanCollide = false
	summitStar = star
end

local function stopHint()
	if hintThread then
		task.cancel(hintThread)
		hintThread = nil
	end
end

local function clearSection()
	stopHint()
	for _, part in sectionParts do
		part:Destroy()
	end
	sectionParts = {}
end

-- Подсказка: плита верного ответа мягко пульсирует светом.
local function glow(part: BasePart)
	part.Material = Enum.Material.Neon
	local info = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(part, info, { Transparency = 0.35 }):Play()
end

local function showSection(index: number)
	clearSection()
	if not spec or not folder then
		return
	end

	local section = spec.params.sections[index]
	if not section then
		return
	end

	--[[
		Задание сказано голосом, но озвучки пока нет — дублируем на экране.
		Показываем букву, на которой стоим, а не ту, которую ищем.
	]]
	HUD.showTarget(section.fromGlyph, index - 1, #spec.params.sections)
	HUD.toast(`Какая буква идёт после {section.fromGlyph}? Встань на неё!`, 4)

	local top = stepTop(index)
	local z = stepCenterZ(index) - 0.5
	local targetPad: BasePart? = nil

	for order, choice in section.choices do
		local x = (order - (#section.choices + 1) / 2) * PAD_GAP
		local color = Letters.expect(choice.letterId).color

		local pad = block(
			`Pad_{choice.letterId}`,
			Vector3.new(PAD_SIZE, 0.5, PAD_SIZE),
			origin * CFrame.new(x, top + 0.25, z),
			color
		)
		table.insert(sectionParts, pad)

		local tile = block(
			`Tile_{choice.letterId}`,
			Vector3.new(3.2, 3.2, 0.4),
			origin * CFrame.new(x, top + 3.4, z),
			Color3.fromRGB(252, 250, 245)
		)
		tile.CanCollide = false
		Glyph.attach(tile, choice.glyph, 1.1, color)
		table.insert(sectionParts, tile)

		if choice.letterId == section.targetId then
			targetPad = pad
		end

		local lastSent = 0
		pad.Touched:Connect(function(hit: BasePart)
			local character = player.Character
			if not character or not hit:IsDescendantOf(character) then
				return
			end
			local now = os.clock()
			if not spec or now < blockedUntil or now - lastSent < 1 or currentSection ~= index then
				return
			end
			lastSent = now
			RemoteDefs.event("ChallengeAction"):FireServer({
				sectionIndex = index,
				letterId = choice.letterId,
			})
		end)
	end

	--[[
		Незнакомая буква подсвечена сразу: угадать её ребёнок не может, и лестница
		здесь не спрашивает, а знакомит. Знакомая — только если он долго думает.
	]]
	if targetPad then
		if section.hint then
			glow(targetPad)
		else
			local waitSeconds = spec.params.hintAfterSec or 10
			hintThread = task.delay(waitSeconds, function()
				hintThread = nil
				if targetPad.Parent and currentSection == index then
					glow(targetPad)
				end
			end)
		end
	end
end

local function celebrate()
	local star = summitStar
	if star and star.Parent then
		star.Color = GOLD
		star.Material = Enum.Material.Neon
		TweenService:Create(
			star,
			TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Size = Vector3.new(5.5, 5.5, 5.5) }
		):Play()

		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Rate = 40
		sparkles.Lifetime = NumberRange.new(1, 2)
		sparkles.Speed = NumberRange.new(4, 8)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Color = ColorSequence.new(GOLD)
		sparkles.Parent = star
	end

	-- Вдоль всей горы — кусок алфавита, выложенный ребёнком.
	local glyphs: { string } = {}
	if spec then
		table.insert(glyphs, spec.params.sections[1].fromGlyph)
		for _, section in spec.params.sections do
			table.insert(glyphs, section.targetGlyph)
		end
	end
	HUD.toast(`Ты на вершине! {table.concat(glyphs, " ")}`, 5)
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

	buildMountain(newSpec.params.sections)
	showSection(1)
end

function LadderController.feedback(fb: any)
	if not spec then
		return
	end

	local index = fb.sectionIndex or currentSection

	if fb.correct then
		stopHint()

		-- Вопрос на следующей ступени становится буквой: это и есть взятая ступень.
		local sign = signs[index + 1]
		local section = spec.params.sections[index]
		if sign and section then
			sign.Color = Letters.expect(section.targetId).color
			Glyph.attach(sign, fb.stepGlyph or section.targetGlyph, 1.3, Color3.fromRGB(255, 255, 255))
			local size = sign.Size
			sign.Size = size * 0.4
			TweenService:Create(sign, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Size = size }):Play()
		end

		local barrier = barriers[index]
		if barrier then
			TweenService:Create(barrier, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			barrier.CanCollide = false
			barriers[index] = nil
		end

		for _, part in sectionParts do
			if part.Name:sub(1, 4) == "Tile" then
				TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
		end

		currentSection = index + 1
		local finished = index >= #spec.params.sections
		task.delay(0.8, function()
			if not spec then
				return
			end
			if finished then
				clearSection()
				celebrate()
			else
				showSection(currentSection)
			end
		end)
	else
		blockedUntil = os.clock() + (fb.cooldown or 0)

		-- Неверная плита мягко проседает и возвращается: ошибка стоит пары секунд.
		for _, part in sectionParts do
			if part.Name == `Pad_{fb.tappedLetterId}` then
				local home = part.CFrame
				TweenService:Create(part, TweenInfo.new(0.2), { CFrame = home * CFrame.new(0, -0.4, 0) })
					:Play()
				task.delay(math.max(0.3, fb.cooldown or 0), function()
					if part.Parent then
						TweenService:Create(part, TweenInfo.new(0.25), { CFrame = home }):Play()
					end
				end)
			end
		end
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
	signs = {}
	barriers = {}
	summitStar = nil
end

return LadderController
