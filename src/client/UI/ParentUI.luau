--!nonstrict
--[[
	Экран «Для родителей»: взрослый вопрос → PIN → отчёт. См. docs/13-PARENT-MODE.md.

	Это единственный экран игры с полноценным текстом, и читает его взрослый.
	Поэтому здесь другой шрифт и мелкий кегль, в отличие от детского интерфейса.

	Цифры вводятся своей клавиатурой на экране, а не системной: на планшете
	системная закрывает полэкрана, а у поля ввода Roblox нет режима пароля —
	PIN было бы видно целиком. На своей клавиатуре вместо цифр PIN рисуются точки.

	Клиент ничего не решает: подошёл ли PIN, сколько ждать и что в отчёте,
	говорит сервер (Services/ParentService). Взрослый вопрос проверяется здесь —
	это барьер от пятилетнего, а не от взломщика.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ParentGate = require(Shared.Logic.ParentGate)
local PlayLimit = require(Shared.Logic.PlayLimit)
local ParentReportText = require(Shared.Logic.ParentReportText)
local SoundSettings = require(Shared.Logic.SoundSettings)
local Letters = require(Shared.Config.Letters)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local CloseButton = require(script.Parent.CloseButton)

local ParentUI = {}

local player = Players.LocalPlayer

local FONT = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold
local TEXT = Color3.fromRGB(235, 235, 245)
local MUTED = Color3.fromRGB(160, 165, 185)
local ACCENT = Color3.fromRGB(255, 214, 102)
local PANEL = Color3.fromRGB(28, 30, 40)
local KEY = Color3.fromRGB(52, 56, 74)
local WARN = Color3.fromRGB(255, 150, 130)

local gui: ScreenGui? = nil
local body: ScrollingFrame? = nil
local random = Random.new()

--[[
	Порядок в списках задаётся счётчиком: при равном LayoutOrder Roblox
	не обещает порядок создания, и строки отчёта могли бы перемешаться.
]]
local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: number, color: Color3?, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Text = text
	l.TextSize = size
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = color or TEXT
	l.Font = if bold then FONT_BOLD else FONT
	l.LayoutOrder = nextOrder()
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, color: Color3?, width: number?): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width or 180, 44)
	b.BackgroundColor3 = color or ACCENT
	b.TextColor3 = Color3.fromRGB(30, 30, 40)
	b.Text = text
	b.TextSize = 20
	b.Font = FONT_BOLD
	b.AutoButtonColor = true
	b.LayoutOrder = nextOrder()
	b.Parent = parent
	corner(b, 12)
	return b
end

local function column(parent: Instance, padding: number?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding or 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Parent = parent
	return layout
end

local function row(parent: Instance, height: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, height)
	f.LayoutOrder = nextOrder()
	f.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = f
	return f
end

local function clearBody(): ScrollingFrame
	assert(body, "ParentUI: экран не построен")
	for _, child in body:GetChildren() do
		child:Destroy()
	end
	body.CanvasPosition = Vector2.zero
	column(body)
	return body
end

local function auth(request: { [string]: any }): any
	local ok, answer = pcall(function()
		return RemoteDefs.func("ParentAuth"):InvokeServer(request)
	end)
	if not ok or typeof(answer) ~= "table" then
		return { ok = false, reason = "offline" }
	end
	return answer
end

--[[
	Цифровая клавиатура: 1–9, стереть, 0, готово. masked — вместо цифр точки.
	onDone получает набранную строку; проверка — забота того, кто спрашивает.
]]
local function keypad(parent: Instance, maxLength: number, masked: boolean, onDone: (typed: string) -> ())
	local typed = ""

	local display = label(parent, "", 34, ACCENT, true)
	display.TextXAlignment = Enum.TextXAlignment.Center
	display.Size = UDim2.new(0, 330, 0, 0)

	local function refresh()
		local shown = if masked then string.rep("●", #typed) else typed
		display.Text = shown .. string.rep(" _", maxLength - #typed)
	end
	refresh()

	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromOffset(330, 4 * 58)
	grid.LayoutOrder = nextOrder()
	grid.Parent = parent

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(100, 50)
	layout.CellPadding = UDim2.fromOffset(10, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "OK" }
	for _, key in keys do
		local b = button(grid, key, if key == "OK" then ACCENT else KEY)
		b.TextColor3 = if key == "OK" then Color3.fromRGB(30, 30, 40) else TEXT
		b.Activated:Connect(function()
			if key == "⌫" then
				typed = string.sub(typed, 1, -2)
			elseif key == "OK" then
				local value = typed
				typed = ""
				refresh()
				onDone(value)
				return
			elseif #typed < maxLength then
				typed ..= key
			end
			refresh()
		end)
	end
end

local showPin -- объявлены заранее: экраны ссылаются друг на друга
local showReport
local showSound
local showLetterReset
local showRestart

-- Ряд кнопок-вариантов: выбранный подсвечен. Для лимита и для напоминания.
local function choices(
	parent: Instance,
	options: { { text: string, value: any } },
	selected: any,
	onPick: (value: any) -> ()
)
	local line = row(parent, 44)
	for _, option in options do
		local chosen = option.value == selected
		local b = button(line, option.text, if chosen then ACCENT else KEY, 90)
		b.TextColor3 = if chosen then Color3.fromRGB(30, 30, 40) else TEXT
		b.Activated:Connect(function()
			if not chosen then
				onPick(option.value)
			end
		end)
	end
end

--[[
	Громкость и субтитры (docs/13-PARENT-MODE.md § 3). Правило «голос громче
	остального» решает сервер; здесь та же функция из Logic/SoundSettings
	повторяет его на копии, чтобы кнопки сразу показали, что музыка опустилась.
]]
local VOLUME_ROWS = {
	{ key = "voice", title = "Голос" },
	{ key = "music", title = "Музыка" },
	{ key = "sfx", title = "Эффекты" },
}

function showSound(root: Instance, data: any, settings: any)
	label(root, "Звук", 24, TEXT, true)
	label(
		root,
		"Музыка и эффекты не бывают громче голоса: задания ребёнок получает голосом. "
			.. "Выключить голос нельзя.",
		18,
		MUTED
	)

	for _, volumeRow in VOLUME_ROWS do
		label(root, volumeRow.title, 20, TEXT)
		local options = {}
		for _, step in SoundSettings.STEPS do
			if volumeRow.key ~= "voice" or step >= SoundSettings.MIN_VOICE then
				table.insert(
					options,
					{ text = if step == 0 then "Выкл" else `{step * 100}%`, value = step }
				)
			end
		end
		choices(root, options, settings[volumeRow.key], function(value)
			if auth({ action = "set_volume", key = volumeRow.key, value = value }).ok then
				SoundSettings.setVolume(settings, volumeRow.key, value)
				data.settings = settings
				showReport("Настройки", data)
			end
		end)
	end

	label(root, "Субтитры", 20, TEXT)
	label(
		root,
		"Текст всего, что говорит голос, внизу экрана. Пока озвучка не записана, "
			.. "субтитры видны всегда.",
		18,
		MUTED
	)
	choices(
		root,
		{ { text = "Вкл", value = true }, { text = "Выкл", value = false } },
		settings.subtitles == true,
		function(value)
			if auth({ action = "set_subtitles", on = value }).ok then
				settings.subtitles = value
				data.settings = settings
				showReport("Настройки", data)
			end
		end
	)

	--[[
		Покупки за Robux (docs/13-PARENT-MODE.md § 3). Ребёнок просит то, что видит,
		поэтому выключатель прячет сами карточки, а не кнопку покупки.
	]]
	label(root, "Покупки за Robux", 20, TEXT)
	label(
		root,
		"Скрыть из магазина всё, что продаётся за настоящие деньги. Купленное "
			.. "раньше останется у ребёнка. Звёздочки за занятия это не затрагивает.",
		18,
		MUTED
	)
	choices(
		root,
		{ { text = "Показывать", value = false }, { text = "Скрыть", value = true } },
		settings.hideRobux == true,
		function(value)
			if auth({ action = "set_hide_robux", on = value }).ok then
				settings.hideRobux = value
				data.settings = settings
				showReport("Настройки", data)
			end
		end
	)
end

--[[
	Сброс прогресса одной буквы: ребёнок «зазубрил» её без понимания
	(docs/13-PARENT-MODE.md § 3). Буква снова станет незнакомой и вернётся
	в занятия со знакомством. Кнопки только у букв, по которым есть прогресс.
]]
function showLetterReset(root: Instance, data: any, settings: any)
	label(root, "Сбросить прогресс буквы", 24, TEXT, true)
	local touched = settings.touched or {}
	if #touched == 0 then
		label(root, "Ребёнок ещё не занимался ни одной буквой.", 18, MUTED)
		return
	end
	label(
		root,
		"Если ребёнок угадывает букву, но не узнаёт её, — начните её заново. "
			.. "Звёздочки, буквёнок и открытые буквы останутся.",
		18,
		MUTED
	)

	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, -16, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = nextOrder()
	grid.Parent = root
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(52, 44)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for _, letterId in touched do
		local letter = Letters.get(letterId)
		if letter then
			local b = button(grid, letter.glyph, KEY, 52)
			b.TextColor3 = TEXT
			b.Activated:Connect(function()
				local confirm = clearBody()
				label(confirm, `Сбросить прогресс буквы {letter.glyph}?`, 26, TEXT, true)
				label(
					confirm,
					"Буква станет незнакомой: игра снова познакомит с ней и будет спрашивать чаще. "
						.. "Отменить сброс нельзя.",
					20,
					MUTED
				)
				local actions = row(confirm, 44)
				button(actions, "Сбросить", WARN).Activated:Connect(function()
					if auth({ action = "reset_letter", letterId = letterId }).ok then
						local at = table.find(touched, letterId)
						if at then
							table.remove(touched, at)
						end
						-- Отчёт после сброса устарел: берём новый с сервера.
						showReport("Настройки", nil)
					end
				end)
				button(actions, "Отмена", KEY).Activated:Connect(function()
					showReport("Настройки", data)
				end)
			end)
		end
	end
end

--[[
	«Начать заново» с двойным подтверждением (docs/13-PARENT-MODE.md § 3):
	экран «что сотрётся и что останется», затем PIN ещё раз. Второй шаг —
	именно PIN, а не вторая кнопка: две кнопки подряд ребёнок нажмёт, PIN — нет.
	Что стирать, решает сервер (Logic/ProfileRestart); текст здесь только пересказ.
]]
local function showRestartPin(data: any, message: string?)
	local root = clearBody()
	label(root, "Введите PIN, чтобы начать заново", 26, TEXT, true)
	label(
		root,
		message
			or "Это последний шаг. После него отменить сброс нельзя.",
		20,
		if message then WARN else MUTED
	)

	keypad(root, ParentGate.PIN_LENGTH, true, function(pin: string)
		if not ParentGate.isValidPin(pin) then
			showRestartPin(data, "Нужно ровно четыре цифры.")
			return
		end
		local answer = auth({ action = "restart", pin = pin })
		if answer.ok then
			local done = clearBody()
			label(done, "Обучение начато заново", 26, TEXT, true)
			label(
				done,
				"Игра снова начнёт с букв А, Б и В и заново познакомит ребёнка с каждой. "
					.. "Звёздочки, вещи и дом на месте.",
				20,
				MUTED
			)
			button(done, "К отчёту", ACCENT).Activated:Connect(function()
				showReport("Главное", nil)
			end)
		elseif answer.reason == "wrong_pin" and (answer.lockedFor or 0) == 0 then
			showRestartPin(
				data,
				`Неверный PIN. Осталось попыток: {answer.attemptsLeft}.`
			)
		elseif answer.reason == "wrong_pin" or answer.reason == "locked" then
			showPin()
		elseif answer.reason == "not_signed_in" then
			showPin("Вход истёк — введите PIN ещё раз.")
		else
			showRestartPin(data, "Не получилось. Попробуйте ещё раз.")
		end
	end)

	button(root, "Отмена", KEY).Activated:Connect(function()
		showReport("Настройки", data)
	end)
end

function showRestart(root: Instance, data: any)
	label(root, "Начать заново", 24, TEXT, true)
	label(
		root,
		"Для второго ребёнка на том же устройстве или если начали слишком рано. "
			.. "Стирает всё, что игра знает об успехах, — звёздочки и вещи остаются.",
		18,
		MUTED
	)
	local start = button(root, "Начать заново…", WARN, 220)
	start.Activated:Connect(function()
		local confirm = clearBody()
		label(confirm, "Начать обучение заново?", 26, TEXT, true)
		label(confirm, "Сотрётся:", 20, WARN, true)
		label(
			confirm,
			"• прогресс всех букв и математики\n"
				.. "• пройденные уровни и открытые ступени\n"
				.. "• незаконченный забег\n"
				.. "• буквята, флаги, арка и шпиль во дворе — ребёнок заработает их снова",
			20
		)
		label(confirm, "Останется:", 20, TEXT, true)
		label(
			confirm,
			"• звёздочки, купленные вещи и дом\n"
				.. "• серия буквы дня и история занятий\n"
				.. "• PIN, лимит времени и звук",
			20
		)
		label(confirm, "Отменить сброс будет нельзя.", 20, MUTED)
		local actions = row(confirm, 44)
		button(actions, "Дальше", WARN).Activated:Connect(function()
			showRestartPin(data)
		end)
		button(actions, "Отмена", KEY).Activated:Connect(function()
			showReport("Настройки", data)
		end)
	end)
end

--[[
	Вкладка «Настройки» — docs/13-PARENT-MODE.md § 3: лимит времени в день,
	напоминание об отдыхе, звук и сброс буквы. Меняет их сервер, и только после входа по PIN.
]]
local function showSettings(root: Instance, data: any)
	local settings = data.settings or {}
	local limit = settings.limitMin
	local played = settings.playedTodayMin or 0

	label(root, "Лимит времени в день", 24, TEXT, true)
	label(
		root,
		if limit
			then `Сегодня сыграно {played} мин из {limit}.`
			else `Сегодня сыграно {played} мин. Лимит выключен.`,
		20,
		MUTED
	)

	local options = { { text = "Выкл", value = 0 } }
	for _, minutes in PlayLimit.OPTIONS do
		table.insert(options, { text = `{minutes} мин`, value = minutes })
	end
	choices(root, options, limit or 0, function(value)
		if auth({ action = "set_limit", minutes = value }).ok then
			settings.limitMin = if value == 0 then nil else value
			data.settings = settings
			showReport("Настройки", data)
		end
	end)
	label(
		root,
		"Когда время выйдет, начатый забег доиграется до финиша, а новые занятия не начнутся. "
			.. "Из игры ребёнка не выкинет: дом, магазин и Башня останутся. "
			.. "Сброс PIN через «Забыли PIN?» лимит не снимает.",
		18,
		MUTED
	)

	label(root, "Напоминание об отдыхе", 24, TEXT, true)
	label(
		root,
		"Раз в 20 минут голос предложит передохнуть. Игру оно не останавливает.",
		18,
		MUTED
	)
	choices(
		root,
		{ { text = "Вкл", value = true }, { text = "Выкл", value = false } },
		settings.restReminder ~= false,
		function(value)
			if auth({ action = "set_rest", on = value }).ok then
				settings.restReminder = value
				data.settings = settings
				showReport("Настройки", data)
			end
		end
	)

	showSound(root, data, settings)
	showLetterReset(root, data, settings)
	showRestart(root, data)
end

-- ===== Отчёт =====================================================================

local TABS = { "Главное", "Советы", "Подробно", "Дома", "Настройки" }

local function linesFor(tab: string, data: any): { string }
	if tab == "Главное" then
		local lines = ParentReportText.summary(data.report)
		table.insert(lines, "")
		table.insert(lines, ParentReportText.MICROPHONE)
		return lines
	elseif tab == "Советы" then
		return ParentReportText.tips(data.report)
	elseif tab == "Подробно" then
		return ParentReportText.details(data.report, data.now)
	elseif tab == "Дома" then
		return ParentReportText.HOME
	end
	return {}
end

--[[
	cached — отчёт, уже полученный при входе. Вкладки его переиспользуют: на каждую
	вкладку ходить к серверу незачем, а лимит частоты на быстрых нажатиях выкинул бы
	родителя обратно на экран PIN.
]]
function showReport(tab: string?, cached: any?)
	local data = cached
	local ok = true
	if data == nil then
		ok = pcall(function()
			data = RemoteDefs.func("GetParentReport"):InvokeServer()
		end)
	end
	-- Вход истёк или сервер не ответил: обратно к PIN, а не пустой экран.
	if not ok or typeof(data) ~= "table" or typeof(data.report) ~= "table" then
		showPin("Вход истёк — введите PIN ещё раз.")
		return
	end

	local current = tab or TABS[1]
	local root = clearBody()

	local tabs = row(root, 44)
	for _, name in TABS do
		local b = button(tabs, name, if name == current then ACCENT else KEY, 112)
		b.TextColor3 = if name == current then Color3.fromRGB(30, 30, 40) else TEXT
		b.Activated:Connect(function()
			showReport(name, data)
		end)
	end

	for index, line in linesFor(current, data) do
		local l = label(root, line, 20, if line == ParentReportText.MICROPHONE then MUTED else TEXT)
		l.Size = UDim2.new(1, -16, 0, 0)
		if index == 1 and current == "Главное" then
			l.TextSize = 26
			l.Font = FONT_BOLD
		end
	end

	if current == "Настройки" then
		showSettings(root, data)
	end

	--[[
		Обучение первых минут можно пропустить — для второго ребёнка в семье,
		который уже видел, как играет первый (docs/13-PARENT-MODE.md § 3).
		Кнопка есть, только пока обучение не пройдено.
	]]
	if current == "Главное" and data.tutorialDone == false then
		local skip = button(root, "Пропустить обучение", KEY, 260)
		skip.TextColor3 = TEXT
		skip.Activated:Connect(function()
			if auth({ action = "skip_tutorial" }).ok then
				data.tutorialDone = true
				showReport(current, data)
			end
		end)
	end
end

-- ===== PIN =======================================================================

local function showReset()
	local root = clearBody()
	label(root, "Сбросить PIN?", 26, TEXT, true)
	label(
		root,
		"Сбросятся PIN и настройки родительского режима. Прогресс ребёнка, звёздочки "
			.. "и покупки не пострадают. После сброса можно будет задать новый PIN.",
		20,
		MUTED
	)
	local actions = row(root, 44)
	button(actions, "Сбросить", WARN).Activated:Connect(function()
		auth({ action = "reset" })
		showPin()
	end)
	button(actions, "Отмена", KEY).Activated:Connect(function()
		showPin()
	end)
end

local function showCreate(message: string?)
	local root = clearBody()
	label(root, "Придумайте PIN из 4 цифр", 26, TEXT, true)
	label(
		root,
		message
			or "Он понадобится каждый раз при входе в этот раздел.",
		20,
		MUTED
	)

	keypad(root, ParentGate.PIN_LENGTH, true, function(first: string)
		if not ParentGate.isValidPin(first) then
			showCreate("Нужно ровно четыре цифры.")
			return
		end
		local repeatRoot = clearBody()
		label(repeatRoot, "Повторите PIN", 26, TEXT, true)
		label(repeatRoot, "Чтобы не ошибиться при наборе.", 20, MUTED)
		keypad(repeatRoot, ParentGate.PIN_LENGTH, true, function(second: string)
			if second ~= first then
				showCreate("PIN не совпали. Давайте ещё раз.")
				return
			end
			local answer = auth({ action = "set", pin = first })
			if answer.ok then
				showReport()
			else
				showPin(
					"Не получилось сохранить PIN. Попробуйте ещё раз."
				)
			end
		end)
	end)
end

function showPin(message: string?)
	local status = auth({ action = "status" })
	if not status.ok then
		local root = clearBody()
		label(
			root,
			"Сервер не ответил. Закройте экран и попробуйте позже.",
			20,
			WARN
		)
		return
	end

	if not status.hasPin then
		showCreate()
		return
	end

	local root = clearBody()
	label(root, "Введите PIN", 26, TEXT, true)
	if status.lockedFor and status.lockedFor > 0 then
		label(
			root,
			`Слишком много попыток. Подождите {status.lockedFor} с и попробуйте снова.`,
			20,
			WARN
		)
	elseif message then
		label(root, message, 20, WARN)
	end

	keypad(root, ParentGate.PIN_LENGTH, true, function(pin: string)
		-- Недобранный PIN на сервер не уходит: там он сжёг бы одну из пяти попыток.
		if not ParentGate.isValidPin(pin) then
			showPin("Нужно ровно четыре цифры.")
			return
		end
		local answer = auth({ action = "enter", pin = pin })
		if answer.ok then
			showReport()
		elseif answer.reason == "locked" then
			showPin()
		elseif answer.reason == "wrong_pin" then
			if (answer.lockedFor or 0) > 0 then
				showPin()
			else
				showPin(`Неверный PIN. Осталось попыток: {answer.attemptsLeft}.`)
			end
		else
			showPin("Не получилось. Попробуйте ещё раз.")
		end
	end)

	button(root, "Забыли PIN?", KEY, 200).Activated:Connect(showReset)
end

-- ===== Взрослый вопрос ===========================================================

local function showGate(message: string?)
	local question = ParentGate.adultQuestion(random)
	local root = clearBody()
	label(root, "Этот раздел — для взрослых", 26, TEXT, true)
	label(root, message or question.text, 22, if message then WARN else TEXT)
	if message then
		label(root, question.text, 22)
	end
	keypad(root, 2, false, function(typed: string)
		if ParentGate.checkAnswer(question, typed) then
			showPin()
		else
			showGate("Не то. Вот другой вопрос:")
		end
	end)
end

-- ===== Каркас ====================================================================

function ParentUI.build()
	if gui then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "AlphabetFallParent"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	screen.DisplayOrder = 10 -- поверх детского интерфейса и магазина
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.86, 0.86)
	panel.Position = UDim2.fromScale(0.07, 0.07)
	panel.BackgroundColor3 = PANEL
	panel.Parent = screen
	corner(panel, 24)

	local header = label(panel, "Для родителей", 22, MUTED, true)
	header.Position = UDim2.fromOffset(24, 18)
	header.Size = UDim2.new(1, -120, 0, 0)

	local close = CloseButton.make(panel, 48, UDim2.new(1, -66, 0, 12))
	close.Activated:Connect(ParentUI.close)

	--[[
		Содержимое прокручивается целиком: на телефоне в альбомной ориентации
		клавиатура с заголовками выше панели, и без прокрутки кнопка «OK»
		уходила бы за край.
	]]
	local content = Instance.new("ScrollingFrame")
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(24, 70)
	content.Size = UDim2.new(1, -48, 1, -90)
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.Parent = panel
	body = content
end

function ParentUI.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function ParentUI.open()
	if not gui then
		ParentUI.build()
	end
	if gui.Enabled then
		return
	end
	gui.Enabled = true
	showGate()
end

--[[
	Закрыли экран — вход закрывается и на сервере. Иначе ребёнок, взявший
	планшет через минуту, открыл бы отчёт без PIN, пока не истекла сессия.
]]
function ParentUI.close()
	if not gui or not gui.Enabled then
		return
	end
	gui.Enabled = false
	clearBody()
	task.spawn(auth, { action = "leave" })
end

return ParentUI
