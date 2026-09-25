--!nonstrict
--[[
	Панель «Задания дня» в левом верхнем углу: три строки — значок, дело, счётчик.
	Тап по строке — стрелка и светлая дорожка к месту задания (Controllers/QuestController).

	Для нечитающего ребёнка главное — значок: 🌧 — Буквопад, 🗝 — сундук, 📖 — портал
	букв. Надпись рядом — для взрослого. Кнопка 📋 сворачивает панель, чтобы
	она не мешала бегать; выполненная строка гаснет и получает ✅.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Economy = require(ReplicatedStorage:WaitForChild("Shared").Config.Economy)

local QuestsUI = {}

local player = Players.LocalPlayer

local ROW_HEIGHT = 50
local WEEK_HEIGHT = 30 + ROW_HEIGHT
local WIDTH = 290
local GOLD = Color3.fromRGB(255, 214, 102)

local gui: ScreenGui? = nil
local panel: Frame? = nil
local list: Frame? = nil
local header: TextLabel? = nil
local weekHeader: TextLabel? = nil
local weekRow: Frame? = nil
local onPick: ((item: any) -> ())? = nil
local open = true

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(240, 240, 250)
	l.Font = Enum.Font.FredokaOne
	l.Parent = parent
	return l
end

function QuestsUI.build(callbacks: { onPick: (item: any) -> () })
	if gui then
		return
	end
	onPick = callbacks.onPick

	local screen = Instance.new("ScreenGui")
	screen.Name = "AlphabetFallQuests"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 1 -- над HUD, под итогами занятия и магазином
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	-- Под кнопкой ⚙ родителя: левый верхний угол занимает меню самого Roblox.
	local toggle = Instance.new("TextButton")
	toggle.Name = "QuestsToggle"
	toggle.Size = UDim2.fromOffset(48, 48)
	toggle.Position = UDim2.new(0, 12, 0, 128)
	toggle.BackgroundColor3 = GOLD
	toggle.Text = "📋"
	toggle.TextScaled = true
	toggle.Parent = screen
	corner(toggle, 12)

	local frame = Instance.new("Frame")
	frame.Name = "QuestsPanel"
	frame.Size = UDim2.fromOffset(WIDTH, 34 + ROW_HEIGHT * 3 + 8 + WEEK_HEIGHT)
	frame.Position = UDim2.new(0, 68, 0, 72)
	frame.BackgroundColor3 = Color3.fromRGB(28, 30, 44)
	frame.BackgroundTransparency = 0.15
	frame.Parent = screen
	corner(frame, 16)
	panel = frame

	header = label(frame, "Задания дня", UDim2.new(1, -16, 0, 26), UDim2.fromOffset(10, 5))
	header.TextColor3 = GOLD
	header.TextXAlignment = Enum.TextXAlignment.Left

	local rows = Instance.new("Frame")
	rows.Size = UDim2.new(1, -12, 0, ROW_HEIGHT * 3)
	rows.Position = UDim2.fromOffset(6, 34)
	rows.BackgroundTransparency = 1
	rows.Parent = frame
	list = rows
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rows

	--[[
		Задание недели — под заданиями дня: значок, дело, полоска и вещь,
		которая ждёт в конце. Полоска видна ребёнку, который не читает цифр.
	]]
	local wHeader = label(
		frame,
		"Задание недели",
		UDim2.new(1, -16, 0, 22),
		UDim2.fromOffset(10, 34 + ROW_HEIGHT * 3 + 6)
	)
	wHeader.TextColor3 = Color3.fromRGB(180, 220, 255)
	wHeader.TextXAlignment = Enum.TextXAlignment.Left
	weekHeader = wHeader

	local wRow = Instance.new("Frame")
	wRow.Name = "Week"
	wRow.Size = UDim2.new(1, -12, 0, ROW_HEIGHT - 4)
	wRow.Position = UDim2.fromOffset(6, 34 + ROW_HEIGHT * 3 + 30)
	wRow.BackgroundColor3 = Color3.fromRGB(44, 60, 92)
	wRow.Parent = frame
	corner(wRow, 10)
	weekRow = wRow

	toggle.Activated:Connect(function()
		open = not open
		frame.Visible = open
	end)
	frame.Visible = false -- пока сервер не прислал список
end

local function row(item, order: number)
	local button = Instance.new("TextButton")
	button.Name = `Quest_{item.id}`
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, ROW_HEIGHT - 4)
	button.BackgroundColor3 = if item.done then Color3.fromRGB(70, 110, 80) else Color3.fromRGB(52, 56, 80)
	button.Text = ""
	button.AutoButtonColor = not item.done
	corner(button, 10)

	label(button, item.icon, UDim2.fromOffset(38, 38), UDim2.fromOffset(4, 4))
	local title = label(button, item.title, UDim2.new(1, -118, 1, -10), UDim2.fromOffset(46, 5))
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextWrapped = true
	if item.done then
		title.TextTransparency = 0.35
	end

	local status = label(
		button,
		if item.done then "✅" elseif item.need > 1 then `{item.have}/{item.need}` else "",
		UDim2.fromOffset(36, 30),
		UDim2.new(1, -70, 0, 8)
	)
	status.TextColor3 = GOLD

	-- Есть куда идти — стрелка: тап по строке показывает дорогу.
	if item.target and not item.done then
		local go = label(button, "➜", UDim2.fromOffset(28, 30), UDim2.new(1, -32, 0, 8))
		go.TextColor3 = GOLD
		button.Activated:Connect(function()
			if onPick then
				onPick(item)
			end
		end)
	end
	return button
end

function QuestsUI.update(payload)
	if not list or not panel or not header then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local done = 0
	for order, item in payload.items or {} do
		row(item, order).Parent = list
		if item.done then
			done += 1
		end
	end
	local total = #(payload.items or {})
	header.Text = if total > 0 and done == total
		then "Задания дня: все сделаны! 🎉"
		else `Задания дня · +{Economy.REWARDS.dailyQuest} ⭐ за каждое`
	panel.Visible = open and total > 0

	local week = payload.week
	if weekRow and weekHeader and typeof(week) == "table" then
		weekRow:ClearAllChildren()
		corner(weekRow, 10)
		weekHeader.Text = if week.done
			then "Задание недели выполнено! 🏆"
			else `Задание недели · награда {week.prizeIcon} {week.prizeTitle}`
		label(weekRow, week.icon, UDim2.fromOffset(38, 38), UDim2.fromOffset(4, 4))
		local title = label(weekRow, week.title, UDim2.new(1, -118, 0, 22), UDim2.fromOffset(46, 3))
		title.TextXAlignment = Enum.TextXAlignment.Left
		-- Полоска: сколько уже сделано из нужного.
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, -118, 0, 10)
		bar.Position = UDim2.fromOffset(46, 30)
		bar.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
		bar.Parent = weekRow
		corner(bar, 5)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(math.clamp((week.have or 0) / math.max(1, week.need or 1), 0, 1), 1)
		fill.BackgroundColor3 = if week.done
			then Color3.fromRGB(120, 220, 130)
			else Color3.fromRGB(120, 200, 255)
		fill.Parent = bar
		corner(fill, 5)
		local status = label(
			weekRow,
			if week.done then "✅" else `{week.have}/{week.need}`,
			UDim2.fromOffset(44, 30),
			UDim2.new(1, -64, 0, 8)
		)
		status.TextColor3 = GOLD
		weekRow.BackgroundColor3 = if week.done
			then Color3.fromRGB(70, 110, 80)
			else Color3.fromRGB(44, 60, 92)
	end
end

-- Выполненное задание: панель подпрыгивает, даже если свёрнута — раскрывается.
function QuestsUI.celebrate()
	if not panel then
		return
	end
	open = true
	panel.Visible = true
	local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = panel
	scale.Scale = 1.12
	TweenService
		:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

return QuestsUI
