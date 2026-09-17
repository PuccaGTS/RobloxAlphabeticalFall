--!nonstrict
--[[
	Хаб: большая площадь с двумя порталами в центре, занятиями вокруг них
	и кольцом участков по краю (docs/14-TUNNEL-MODE.md § 3.1, docs/15-HOME-BASE.md § 2).

	Устройство мира читается телом, а не текстом:
	  · в центре два портала — «Мир букв» и «Мир математики». Два входа ребёнок
	    различает по цвету и месту, а список уровней требует чтения и выбора,
	    которых он не умеет. Больше двух порталов — это уже меню;
	  · вокруг порталов — площадка занятий и магазин: то, что делают между забегами;
	  · по краю — двадцать участков с домами детей. Сервер вмещает двадцать игроков,
	    и каждому гарантирован свой участок.

	Сами участки строит BaseService: у них своя жизнь, они появляются и гаснут
	вместе с игроками, а площадь стоит всегда.

	Строится кодом, а не руками в Studio: пока нет арта, геометрию проще держать
	в репозитории, чем в .rbxl, который не читается в диффе и конфликтует при слиянии.
	Когда появятся модели, этот сервис заменится на загрузку готовой сцены.

	Башня прогресса здесь НЕ строится: она у каждого игрока своя (у одного буква
	освоена, у другого нет), а один общий объект в мире так не умеет. Её собирает
	клиент на участке хозяина — src/client/Controllers/TowerController.luau.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Challenges = require(Shared.Config.Challenges)
local Letters = require(Shared.Config.Letters)
local Base = require(Shared.Config.Base)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local ProgressService = require(script.Parent.ProgressService)
local ChallengeService = require(script.Parent.ChallengeService)
local DecorService = require(script.Parent.DecorService)
local PlaygroundService = require(script.Parent.PlaygroundService)
local Teleport = require(script.Parent.Parent.World.Teleport)
local DailyLetterService = require(script.Parent.DailyLetterService)

local WorldService = {}

local PLAZA_RADIUS = Base.PLAZA_RADIUS
local TOUCH_DEBOUNCE = 2

--[[
	Два портала — два мира, и у каждого свой путь и свои сохранки.

	Портал не спрашивает, куда идти: он продолжает путь своего мира. В мире букв
	это забег — начатый с начала или продолженный с последней арки, если ребёнок
	вышел из игры посреди туннеля (docs/14-TUNNEL-MODE.md § 3.2).

	Оба мира открыты. Математический ждал ворот с числами и дождался: за порталом
	тот же коридор с проёмами, только над ними числа, а задача меняется у каждых
	ворот (docs/16-MATH.md § 3.1).

	Ни один мир не запирает другой: ребёнок вправе любить счёт и не любить буквы,
	и наоборот (docs/16-MATH.md § 6).
]]
local PORTALS = {
	{
		id = "letters",
		challengeId = "tunnel_run",
		caption = "📖 МИР БУКВ",
		action = "Войти",
		color = Color3.fromRGB(110, 165, 235),
		offset = -16,
	},
	{
		id = "math",
		challengeId = "math_gates",
		caption = "🔢 МИР МАТЕМАТИКИ",
		action = "Войти",
		color = Color3.fromRGB(235, 165, 95),
		offset = 16,
	},
}

--[[
	Пады площади: четыре занятия и магазин.

	Падов по одному на испытание, а не по одному на ступень алфавита. Ступеней
	одиннадцать, и одиннадцать порталов по кругу — это меню, которое нечитающий
	ребёнок не осилит. Ступень выбирает не он, а прогресс: любое занятие берёт
	буквы из очереди повторений (docs/14-TUNNEL-MODE.md § 3.2).

	Все открыты с самого начала. Причина не косметическая: для статуса
	«изученная» буква обязана быть успешно пройдена в ДВУХ разных типах испытаний
	(docs/02-LEARNING.md § 8). Запри половину — и прогресс упрётся в тупик
	на четвёртой минуте.
]]
local PADS = {
	{
		challengeId = "obstacle_course",
		caption = "🏃 Полоса препятствий",
		action = "Прыгать",
		color = Color3.fromRGB(250, 200, 120),
	},
	{
		challengeId = "letter_rain",
		caption = "🌧 Буквопад",
		action = "Ловить",
		color = Color3.fromRGB(120, 170, 230),
	},
	{
		challengeId = "alphabet_ladder",
		caption = "🪜 Алфавитная лестница",
		action = "Подниматься",
		color = Color3.fromRGB(190, 150, 230),
	},
	-- Спокойное занятие: пузыри плывут медленно, успеть можно всё.
	{
		challengeId = "bubbles",
		caption = "🫧 Пузыри",
		action = "Лопать",
		color = Color3.fromRGB(140, 215, 230),
	},
	-- Единственное занятие на начертание: какая буква написана правильно.
	{
		challengeId = "mirror",
		caption = "🪞 Зеркало",
		action = "Смотреть",
		color = Color3.fromRGB(215, 195, 240),
	},
	-- Счёт без ворот: уравнять весы кучкой камней (docs/16-MATH.md § 3.3).
	{
		challengeId = "scales",
		caption = "⚖️ Весы",
		action = "Взвешивать",
		color = Color3.fromRGB(235, 185, 120),
	},
	-- Счёт действием: собрать столько ягод, сколько сказал голос (docs/16-MATH.md § 3.2).
	{
		challengeId = "berries",
		caption = "🍓 Ягоды",
		action = "Собирать",
		color = Color3.fromRGB(230, 120, 140),
	},
}

local lastTouch: { [Player]: number } = {}

--[[
	Откуда ребёнок ушёл в испытание: точка рядом с падом или порталом, куда его
	поставить, когда испытание кончится. Не на сам пад — иначе касание срабатывало
	снова, и испытание начиналось по кругу: «постоянно куда-то телепортирует».
]]
local exitOf: { [Player]: CFrame } = {}

-- Пауза после конца испытания, прежде чем пад или портал снова сработает на касание.
local AFTER_FINISH_COOLDOWN = 3

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--[[
	Подпись над объектом. Размер в ПИКСЕЛЯХ: у BillboardGui доля Scale считается
	от размера детали, и на платформе 12 студов подпись раздувается до нечитаемой.
]]
local function caption(parent: BasePart, text: string, height: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Caption"
	billboard.Size = UDim2.fromOffset(280, 90)
	billboard.StudsOffset = Vector3.new(0, height, 0)
	billboard.LightInfluence = 0
	-- Близко — чтобы подписи всех падов и Башни не наслаивались друг на друга
	-- в одну кашу, как только отойдёшь на середину площади.
	billboard.MaxDistance = 55
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(35, 30, 50)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard
end

--[[
	Сколько секунд надо простоять на паде, прежде чем занятие начнётся.

	Мгновенного старта здесь больше нет, и это главное правило пада: ребёнок
	бегает по площади, задевает всё подряд, и занятие, начавшееся от случайного
	касания, выбрасывало его из игры в чужой экран. Теперь пад отсчитывает
	вслух — «3 · 2 · 1» — и отпускает, если ребёнок просто пробежал мимо.

	У магазина отсчёт короче: открыть витрину — не то же самое, что улететь
	в испытание, и передумать там можно одной кнопкой.
]]
local ACTIVATE_SECONDS = 3
local SHOP_ACTIVATE_SECONDS = 1

--[[
	Запуск и по подсказке, и по касанию.

	Дошкольник не будет искать клавишу E и не всегда попадёт по кнопке подсказки —
	он просто придёт и встанет на пад. Касание обязано работать как основной способ,
	но не мгновенно: и касание, и подсказка ждут, пока ребёнок задержится.
]]
local function makeActivator(
	pad: BasePart,
	actionText: string,
	objectText: string,
	action: (Player) -> (),
	exit: CFrame?,
	seconds: number?
)
	local hold = seconds or ACTIVATE_SECONDS

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	-- Удержание, а не нажатие: случайное E больше ничего не запускает.
	prompt.HoldDuration = math.min(hold, 1.5)
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	local function activate(player: Player)
		if exit then
			exitOf[player] = exit
		end
		lastTouch[player] = os.clock()
		action(player)
	end
	prompt.Triggered:Connect(activate)

	--[[
		Отсчёт над падом. Живёт на самом паде и виден всем: ребёнок понимает,
		что стоять надо здесь, а родитель — что сейчас что-то начнётся.
	]]
	local counter = Instance.new("BillboardGui")
	counter.Name = "Countdown"
	counter.Size = UDim2.fromOffset(200, 200)
	counter.StudsOffset = Vector3.new(0, 7, 0)
	counter.AlwaysOnTop = true
	counter.LightInfluence = 0
	counter.MaxDistance = 90
	counter.Enabled = false
	counter.Parent = pad

	local counterLabel = Instance.new("TextLabel")
	counterLabel.Size = UDim2.fromScale(1, 1)
	counterLabel.BackgroundTransparency = 1
	counterLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	counterLabel.TextStrokeColor3 = Color3.fromRGB(40, 30, 60)
	counterLabel.TextStrokeTransparency = 0
	counterLabel.TextScaled = true
	counterLabel.Font = Enum.Font.FredokaOne
	counterLabel.Text = ""
	counterLabel.Parent = counter

	--[[
		Касание срабатывает много раз в секунду, пока ребёнок стоит на паде.
		Поэтому реагируем только на ВХОД на пад: пока он с него не сойдёт,
		повторные касания игнорируются.
	]]
	local standing: { [Player]: boolean } = {}
	local counting: Player? = nil

	local function stopCounting()
		counting = nil
		counter.Enabled = false
	end

	pad.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or standing[player] or counting then
			return
		end

		local now = os.clock()
		if lastTouch[player] and now - lastTouch[player] < TOUCH_DEBOUNCE then
			return
		end

		standing[player] = true
		counting = player
		counter.Enabled = true

		task.spawn(function()
			for left = math.ceil(hold), 1, -1 do
				if counting ~= player or not standing[player] then
					stopCounting()
					return
				end
				counterLabel.Text = tostring(left)
				task.wait(1)
			end

			if counting ~= player or not standing[player] then
				stopCounting()
				return
			end

			counterLabel.Text = "Поехали!"
			stopCounting()
			activate(player)
		end)
	end)

	pad.TouchEnded:Connect(function(hit: BasePart)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			standing[player] = nil
			-- Сошёл с пада — отсчёт отменён без единого слова: передумать можно молча.
			if counting == player then
				stopCounting()
			end
		end
	end)
end

--[[
	Портал мира: круглые каменные врата с живым вихрем внутри.

	Первая версия была рамкой из трёх брусков и цветной плитой — на проверке
	её назвали сырой и примитивной. Портал — первое, что ребёнок видит, появившись
	на площади, и он обязан звать внутрь сам: камень по кругу, светящиеся руны,
	закрученный вихрь, искры и буквы или цифры, которые медленно облетают врата.

	Имена двух деталей держатся ради других систем: `Portal_{id}` — цель шага
	обучения, `PortalArch_{id}` — к ней клиент крепит табличку «Уровень 3 из 11».
]]
local PORTAL_RADIUS = 8
local PORTAL_STONES = 20
local PORTAL_GLYPHS = {
	letters = { "А", "Б", "В", "Г", "Д", "Е" },
	math = { "1", "2", "3", "4", "5", "+" },
}

local function weldTo(anchor: BasePart, piece: BasePart)
	piece.Anchored = false
	piece.Massless = true
	piece.CanCollide = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = piece
	weld.Parent = piece
end

local function spin(hub: BasePart, seconds: number, axis: Vector3)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1)
	local turn = CFrame.fromAxisAngle(axis, math.pi)
	TweenService:Create(hub, info, { CFrame = hub.CFrame * turn }):Play()
end

local function buildPortal(hub: Folder, portal: any)
	local position = Vector3.new(portal.offset, 1.5, -6)
	local color = portal.color
	local stone = Color3.fromRGB(205, 200, 215)
	local center = position + Vector3.new(0, PORTAL_RADIUS + 2.5, 0)

	-- Круглый постамент в две ступени: к порталу поднимаются, а не натыкаются на него.
	local platform = part(
		`Portal_{portal.id}`,
		Vector3.new(1.4, 20, 20),
		CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		stone,
		hub
	)
	platform.Shape = Enum.PartType.Cylinder
	platform.Material = Enum.Material.Slate
	caption(platform, portal.caption, PORTAL_RADIUS * 2 + 7)

	local step = part(
		`PortalStep_{portal.id}`,
		Vector3.new(1, 15, 15),
		CFrame.new(position + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		hub
	)
	step.Shape = Enum.PartType.Cylinder
	step.Material = Enum.Material.SmoothPlastic

	-- Каменное кольцо. Каждый четвёртый камень — светящаяся руна цвета мира.
	for index = 1, PORTAL_STONES do
		local angle = (index - 1) / PORTAL_STONES * math.pi * 2
		local rune = index % 4 == 1
		local block = part(
			if index == 1 then `PortalArch_{portal.id}` else `PortalStone_{portal.id}_{index}`,
			Vector3.new(3, 2.8, 2.4),
			CFrame.new(center) * CFrame.Angles(0, 0, angle) * CFrame.new(0, PORTAL_RADIUS, 0),
			if rune then color else stone,
			hub
		)
		block.Material = if rune then Enum.Material.Neon else Enum.Material.Slate
	end

	-- Полотно: светящийся диск. Сквозь него и входят — активатор висит на нём.
	local veil = part(
		`PortalVeil_{portal.id}`,
		Vector3.new(0.4, PORTAL_RADIUS * 2 - 1.5, PORTAL_RADIUS * 2 - 1.5),
		CFrame.new(center) * CFrame.Angles(0, math.rad(90), 0),
		color,
		hub
	)
	veil.Shape = Enum.PartType.Cylinder
	veil.CanCollide = false
	veil.Material = Enum.Material.Neon
	veil.Transparency = 0.45

	--[[
		Вихрь: шесть лопастей на невидимой втулке. Крутится одна втулка, лопасти
		приварены к ней: так они не расходятся по фазе и не дёргаются.
	]]
	local swirl = part(`PortalSwirl_{portal.id}`, Vector3.new(0.5, 0.5, 0.5), CFrame.new(center), color, hub)
	swirl.Transparency = 1
	swirl.CanCollide = false
	for blade = 1, 6 do
		local angle = (blade - 1) / 6 * math.pi * 2
		local arm = part(
			`PortalSwirlBlade_{portal.id}_{blade}`,
			Vector3.new(1.1, PORTAL_RADIUS - 2, 0.3),
			CFrame.new(center)
				* CFrame.Angles(0, 0, angle)
				* CFrame.new(0.9, (PORTAL_RADIUS - 2) / 2, 0.35)
				* CFrame.Angles(0, 0, math.rad(-25)),
			Color3.fromRGB(255, 255, 255),
			hub
		)
		arm.Material = Enum.Material.Neon
		arm.Transparency = 0.55
		weldTo(swirl, arm)
	end
	spin(swirl, 5, Vector3.new(0, 0, 1))

	-- Буквы или цифры мира облетают врата: видно издалека, куда ведёт портал.
	local orbit = part(`PortalOrbit_{portal.id}`, Vector3.new(0.5, 0.5, 0.5), CFrame.new(center), color, hub)
	orbit.Transparency = 1
	orbit.CanCollide = false
	local glyphs = PORTAL_GLYPHS[portal.id] or {}
	for index, glyph in glyphs do
		local angle = (index - 1) / #glyphs * math.pi * 2
		local bubble = part(
			`PortalGlyph_{portal.id}_{index}`,
			Vector3.new(2.6, 2.6, 2.6),
			CFrame.new(center) * CFrame.Angles(0, 0, angle) * CFrame.new(0, PORTAL_RADIUS + 3.5, 0),
			Color3.fromRGB(255, 255, 255),
			hub
		)
		bubble.Shape = Enum.PartType.Ball
		bubble.Transparency = 0.2
		weldTo(orbit, bubble)

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(70, 70)
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.MaxDistance = 160
		billboard.Parent = bubble

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = glyph
		label.TextColor3 = color
		label.TextStrokeColor3 = Color3.fromRGB(40, 30, 60)
		label.TextStrokeTransparency = 0
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.Parent = billboard
	end
	spin(orbit, 18, Vector3.new(0, 0, 1))

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = 12
	sparkles.Lifetime = NumberRange.new(1.2, 2)
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Color = ColorSequence.new(color)
	sparkles.Parent = veil

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 22
	light.Brightness = 2
	light.Parent = veil

	--[[
		Вход в мир. Испытание само решит, начать забег заново или продолжить
		с последней арки: незаконченный забег лежит в профиле (Types.SavedRun).
		Сохранки у миров свои — ключ забега это его испытание.

		Срабатывает светящееся полотно, а не постамент под ним: в портал входят,
		пройдя сквозь врата. Постамент лежал посреди площади, на него наступали
		по пути куда угодно — и улетали в туннель, не собираясь.
	]]
	local front = position + Vector3.new(0, 3, 13)
	makeActivator(veil, portal.action, Challenges.expect(portal.challengeId).title, function(player: Player)
		if not ProfileService.get(player) then
			return
		end
		ChallengeService.startFor(player, portal.challengeId)
	end, CFrame.lookAt(front, Vector3.new(position.X, front.Y, position.Z)))
end

local function buildChallengePad(hub: Folder, pad: any, slot: number)
	-- Пады расставлены по кругу с равным шагом: магазин занимает свой слот,
	-- иначе два пада встают в одну точку и подсказки накладываются друг на друга.
	--[[
		Занятия стоят полукругом ПЕРЕД порталами, а не вокруг них: порталы должны
		быть видны от точки появления, и загораживать их падами нельзя.
	]]
	local position = Base.padPosition(slot) + Vector3.new(0, 1.5, 0)

	local meta = Challenges.expect(pad.challengeId)

	local platform =
		part(`Pad_{pad.challengeId}`, Vector3.new(14, 1, 14), CFrame.new(position), pad.color, hub)
	caption(platform, pad.caption, 5)

	-- Арка над падом, чтобы портал читался как вход, а не как плитка на полу
	local frameColor = Color3.fromRGB(90, 140, 210)
	part(
		`PadArch_{pad.challengeId}`,
		Vector3.new(14, 1.2, 1.2),
		CFrame.new(position + Vector3.new(0, 9, 0)),
		frameColor,
		hub
	)
	part(
		`PadLeft_{pad.challengeId}`,
		Vector3.new(1.2, 9, 1.2),
		CFrame.new(position + Vector3.new(-6.4, 4.5, 0)),
		frameColor,
		hub
	)
	part(
		`PadRight_{pad.challengeId}`,
		Vector3.new(1.2, 9, 1.2),
		CFrame.new(position + Vector3.new(6.4, 4.5, 0)),
		frameColor,
		hub
	)

	-- Выход — на шаг ближе к центру площади, лицом к паду: рядом, но не на нём.
	local flat = Vector3.new(position.X, 0, position.Z)
	local exitAt = position + Vector3.new(0, 3, 0) - flat.Unit * 12
	makeActivator(platform, pad.action, meta.title, function(player: Player)
		if not ProfileService.get(player) then
			return
		end
		ChallengeService.startFor(player, pad.challengeId)
	end, CFrame.lookAt(exitAt, Vector3.new(position.X, exitAt.Y, position.Z)))
end

--[[
	Камень буквы дня (docs/03-CHALLENGES.md § 7): постамент со светящимся
	кристаллом над ним. Саму букву сервер не пишет — она у каждого ребёнка своя,
	её ставит клиент над деталью `DailyLetterStone` (DailyLetterController).

	Срабатывает касание кристалла на постаменте, как и у падов: ребёнок
	подходит и встаёт. Камень стоит не на пути к порталам (Base), так что
	случайно на него не наступают.
]]
local function buildDailyStone(hub: Folder)
	local base = Base.DAILY_LETTER_POSITION
	local gold = Color3.fromRGB(255, 205, 90)

	local plinth = part(
		"DailyLetterPlinth",
		Vector3.new(8, 1, 8),
		CFrame.new(base + Vector3.new(0, 2.1, 0)),
		Color3.fromRGB(200, 190, 215),
		hub
	)
	plinth.Material = Enum.Material.Slate

	local stone =
		part("DailyLetterStone", Vector3.new(6, 1, 6), CFrame.new(base + Vector3.new(0, 3.1, 0)), gold, hub)
	stone.Material = Enum.Material.Neon
	stone.Transparency = 0.2

	local glow = Instance.new("PointLight")
	glow.Color = gold
	glow.Range = 16
	glow.Brightness = 1.5
	glow.Parent = stone

	-- Выход — перед камнем, со стороны порталов, лицом к нему.
	local exitAt = base + Vector3.new(0, 3, 9)
	makeActivator(stone, "Играть", "Буква дня", function(player: Player)
		if not ProfileService.get(player) then
			return
		end
		DailyLetterService.begin(player)
	end, CFrame.lookAt(exitAt, Vector3.new(base.X, exitAt.Y, base.Z)))
end

--[[
	Декор: деревья, фонари, клумбы. Мир должен выглядеть местом, а не полигоном.

	Предметы на земле расставляет DecorService по каталогу Config/Decor: там же лежит
	и запрет ставить что-либо перед порталами и падами. Пока моделей нет, он ставит
	заглушки того же размера — расстановка проверяется до прихода арта, а не после.
]]
local function buildDecor(hub: Folder)
	--[[
		Парящих букв над площадью больше нет. Они висели вокруг Башни, когда та
		стояла в центре; Башня переехала во двор, а над порталами остались
		33 неоновых куба без букв — цветной мусор в небе, по которому ничего
		не понять. Буквы в мире теперь там, где с ними что-то делают.
	]]
	DecorService.build(hub)
	-- Игровые места парка: батуты, музыкальная дорожка, классики и остальное (Config/Playground).
	PlaygroundService.build(hub)
end

--[[
	Свет, воздух и облака. Погоды как механики в игре нет и не будет: смена погоды
	или времени суток означала бы, что ребёнок пришёл — а мир другой, темнее
	и хуже видно. Здесь всегда светлый день, и это решение, а не заглушка.

	Ни один эффект не добавлен «для красоты вообще» — каждый отвечает за то,
	чтобы объект в мире было ВИДНО:
	  · день в два часа пополудни: тени короткие и ничего не прячут;
	  · воздух чуть плотнее обычного — дальние дома видно, но они не спорят
	    по контрасту с буквами на воротах;
	  · облака над головой: небо перестаёт быть плоской заливкой, и мир
	    читается как место, куда пришли, а не как полигон.

	Дешёвые эффекты выбраны намеренно: цель — 30 FPS на дешёвом планшете
	(CHECKLIST, «перед публикацией»). Поэтому мягкое солнце и лёгкое свечение,
	а не глубина резкости и объёмный туман.
]]
local function effect(className: string, apply: (Instance) -> ())
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		return
	end
	local instance = Instance.new(className)
	apply(instance)
	instance.Parent = Lighting
end

local function styleLighting()
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(120, 120, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 170)
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 12 -- солнце повыше: длинные тени поперёк площади не нужны
	Lighting.ExposureCompensation = 0.15
	-- Мягкий край тени: жёсткая ступенька от дерева на плитке выглядит грязью.
	Lighting.ShadowSoftness = 0.35

	effect("Sky", function() end)

	effect("Atmosphere", function(instance)
		local atmosphere = instance :: Atmosphere
		atmosphere.Density = 0.32
		atmosphere.Offset = 0.1
		atmosphere.Haze = 1.4
		atmosphere.Glare = 0.2
		atmosphere.Color = Color3.fromRGB(215, 228, 245)
		atmosphere.Decay = Color3.fromRGB(150, 175, 210)
	end)

	-- Свечение только на самом ярком: неоновые буквы, вода фонтана, плафоны.
	effect("BloomEffect", function(instance)
		local bloom = instance :: BloomEffect
		bloom.Intensity = 0.5
		bloom.Size = 20
		bloom.Threshold = 1.6
	end)

	-- Тёплые лучи в кроны деревьев: одна из немногих вещей, которые дёшево
	-- превращают «расставленные объекты» в место.
	effect("SunRaysEffect", function(instance)
		local rays = instance :: SunRaysEffect
		rays.Intensity = 0.08
		rays.Spread = 0.6
	end)

	--[[
		Цвет: чуть теплее и сочнее. Насыщенность поднята слабо — на дешёвых
		экранах сильный перекос по цвету бьёт как раз по различению букв,
		а они у нас разноцветные не для красоты (docs/08-UX-UI.md).
	]]
	effect("ColorCorrectionEffect", function(instance)
		local color = instance :: ColorCorrectionEffect
		color.Brightness = 0.02
		color.Contrast = 0.06
		color.Saturation = 0.08
		color.TintColor = Color3.fromRGB(255, 251, 245)
	end)

	--[[
		Облака. Живут в Terrain, а не в Lighting, и террейна для них не нужно —
		достаточно самого объекта.
	]]
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain and not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55 -- половина неба: не пасмурно и не голо
		clouds.Density = 0.55
		clouds.Color = Color3.fromRGB(255, 255, 255)
		clouds.Parent = terrain
	end
end

--[[
	Мир целиком строится кодом, и ничего чужого в нём быть не должно.

	Если место открыто из шаблона Studio (с рельефом, горами и витриной
	материалов), шаблон остаётся лежать поверх площади: рельеф с травой
	оказывается над головой, ребёнок проваливается под него, выпрыгивает
	наверх и уже не может дойти ни до портала, ни до дома. Поэтому перед
	постройкой всё, что не наше, убирается: рельеф стирается, чужие объекты
	удаляются. Это делается во время игры и файл места не меняет.

	Не трогаем только камеру, сам объект Terrain (в нём живут облака)
	и персонажей игроков, если они уже появились.
]]
local function clearForeignWorld()
	workspace.Terrain:Clear()

	local removed = 0
	for _, child in workspace:GetChildren() do
		local keep = child:IsA("Terrain")
			or child:IsA("Camera")
			or (child:IsA("Model") and Players:GetPlayerFromCharacter(child) ~= nil)
		if not keep then
			child:Destroy()
			removed += 1
		end
	end
	if removed > 0 then
		print(
			`[World] убрано чужое из Workspace: {removed} объектов и рельеф шаблона`
		)
	end
end

function WorldService.build()
	clearForeignWorld()

	styleLighting()

	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = workspace

	--[[
		Земля накрывает всю площадку с участками: край мира должен быть далеко
		за домами, а не сразу за спиной у крайнего дома.
	]]
	part(
		"Ground",
		Vector3.new(Base.GROUND_SIZE, 2, Base.GROUND_SIZE),
		CFrame.new(0, 0, 0),
		Color3.fromRGB(150, 205, 140),
		hub
	)
	part(
		"Plaza",
		Vector3.new(PLAZA_RADIUS * 2, 2, PLAZA_RADIUS * 2),
		CFrame.new(0, 0.6, 0),
		Color3.fromRGB(235, 225, 200),
		hub
	)

	--[[
		Край мира. За домами земля кончалась обрывом: ребёнок, обежавший свой
		участок сзади, падал в пустоту и «умирал», появляясь в центре площади.
		Смерти в этой игре нет нигде, и здесь её быть тоже не должно.

		Поэтому по периметру идёт живая изгородь: её видно, она читается как
		«дальше не надо», и поверх неё — невысокая невидимая стена, чтобы
		перепрыгнуть тоже не вышло.
	]]
	local edge = Base.GROUND_SIZE / 2
	for _, side in { -1, 1 } do
		for _, axis in { "x", "z" } do
			local along = Vector3.new(
				if axis == "x" then 3 else Base.GROUND_SIZE,
				5,
				if axis == "x" then Base.GROUND_SIZE else 3
			)
			local at = CFrame.new(
				if axis == "x" then side * edge else 0,
				3.5,
				if axis == "x" then 0 else side * edge
			)
			local hedge = part(`WorldHedge_{axis}_{side}`, along, at, Color3.fromRGB(110, 170, 120), hub)
			hedge.Material = Enum.Material.Grass

			local wall = part(
				`WorldWall_{axis}_{side}`,
				Vector3.new(along.X, 30, along.Z),
				at * CFrame.new(0, 16, 0),
				Color3.fromRGB(255, 255, 255),
				hub
			)
			wall.Transparency = 1
		end
	end

	--[[
		Дорожки от площади к кольцу участков: ребёнок видит, куда идти к домам.
		Длина лежит вдоль X: на первой проверке сверху дорожки оказались поперёк
		направления — квадратом вокруг площади, а фонари стояли вдоль настоящего пути.
		Кончается дорожка у калитки участка, а не посреди двора.
	]]
	for i = 1, 4 do
		local angle = (i - 1) / 4 * math.pi * 2
		local length = Base.RING_RADIUS - Base.PLOT_SIZE / 2 - PLAZA_RADIUS
		local at = (PLAZA_RADIUS + length / 2)
		part(
			`Path_{i}`,
			Vector3.new(length, 0.4, 10),
			CFrame.new(math.cos(angle) * at, 1.1, math.sin(angle) * at) * CFrame.Angles(0, -angle, 0),
			Color3.fromRGB(230, 215, 185),
			hub
		)
	end

	for _, portal in PORTALS do
		buildPortal(hub, portal)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	-- Появляемся лицом к порталам: первое, что видит ребёнок, — два входа в миры.
	spawn.CFrame = CFrame.new(0, 2.2, 26)
	spawn.Anchored = true
	spawn.Color = Color3.fromRGB(255, 214, 102)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Parent = hub

	local slots = #PADS + 1 -- занятия + магазин
	assert(
		slots == Base.PAD_SLOTS,
		`WorldService: падов {slots}, а мест в полукруге {Base.PAD_SLOTS}`
	)

	for slot, pad in PADS do
		buildChallengePad(hub, pad, slot)
	end

	-- Магазин занимает последний слот полукруга: потратить перед выходом в мир.
	local shopPad = part(
		"ShopPad",
		Vector3.new(12, 1, 12),
		CFrame.new(Base.padPosition(slots) + Vector3.new(0, 1.5, 0)),
		Color3.fromRGB(255, 190, 120),
		hub
	)
	caption(shopPad, "🛍 Магазин", 5)
	makeActivator(shopPad, "Открыть", "Магазин", function(player: Player)
		RemoteDefs.event("OpenUI"):FireClient(player, "shop")
	end, nil, SHOP_ACTIVATE_SECONDS)

	buildDailyStone(hub)
	buildDecor(hub)

	--[[
		Чужие точки появления (например, из шаблона Baseplate) выключаем: иначе
		ребёнка выбрасывает мимо площади, а то и внутрь подиума Башни.
	]]
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") and instance ~= spawn then
			instance.Enabled = false
		end
	end

	print(
		`[World] площадь построена: порталов {#PORTALS}, падов {slots}, букв {Letters.count()}`
	)
end

function WorldService.start()
	WorldService.build()

	Players.PlayerRemoving:Connect(function(player: Player)
		lastTouch[player] = nil
		exitOf[player] = nil
	end)

	--[[
		Испытание кончилось — ребёнок встаёт рядом с тем падом или порталом,
		откуда ушёл, лицом к нему. Не на него: иначе касание запускало испытание
		снова. И пару секунд пад на него не реагирует вовсе.

		Нажал 🏠 — его уже увели домой, и сюда возвращать не нужно.
	]]
	ChallengeService.onFinished(function(player: Player, _spec: any, reason: string)
		local exit = exitOf[player]
		exitOf[player] = nil
		lastTouch[player] = os.clock() + AFTER_FINISH_COOLDOWN - TOUCH_DEBOUNCE
		if not exit or reason == "aborted" then
			return
		end
		-- После хука туннеля: он сначала возвращает ребёнка туда, откуда тот стартовал.
		task.defer(function()
			local character = player.Character
			if character then
				Teleport.to(player, exit)
			end
		end)
	end)

	-- Пересчитываем открытые ступени при входе: буквы могли быть освоены в прошлой сессии.
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			local profile = ProfileService.waitFor(player, 20)
			if profile then
				ProfileService.update(player, function(p)
					ProgressService.refreshStages(p)
				end)
			end
		end)
	end)
end

return WorldService
