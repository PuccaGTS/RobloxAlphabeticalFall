--!nonstrict
--[[
	Буква дня над камнем на площади (docs/03-CHALLENGES.md § 7).

	Буква у каждого ребёнка своя, поэтому её ставит клиент, как Башню и таблички
	над порталами: созданное клиентом в workspace видит только он сам.

	Под буквой три кружка — сколько заданий сделано. Кружки ребёнок считает
	без чтения; цифру серии «🔥 4» читает родитель. Пройдено — буква золотая.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)

local DailyLetterController = {}

local SIGN_NAME = "DailyLetterSign"
local GOLD = Color3.fromRGB(255, 205, 90)
local DIM = Color3.fromRGB(90, 85, 110)

local latest: any = nil
local waiting = false

type Sign = { glyph: TextLabel, dots: { Frame }, streak: TextLabel }

local function build(stone: BasePart): Sign
	local billboard = Instance.new("BillboardGui")
	billboard.Name = SIGN_NAME
	--[[
		Размер в студах (у BillboardGui доля Scale — студы): камень стоит
		между порталами, и пиксельная табличка вдали расползалась на таблички
		уровней над ними. В студах она держит место, как вывеска. Всё внутри —
		в долях таблички, иначе оно не росло бы вместе с ней.
	]]
	billboard.Size = UDim2.fromScale(8, 10.8)
	billboard.StudsOffset = Vector3.new(0, 8, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 90
	billboard.Parent = stone

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.13)
	title.BackgroundTransparency = 1
	title.Text = "☀ Буква дня"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeTransparency = 0
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.Parent = billboard

	local glyph = Instance.new("TextLabel")
	glyph.Position = UDim2.fromScale(0, 0.13)
	glyph.Size = UDim2.fromScale(1, 0.61)
	glyph.BackgroundTransparency = 1
	glyph.TextColor3 = Color3.fromRGB(255, 255, 255)
	glyph.TextStrokeColor3 = Color3.fromRGB(35, 30, 50)
	glyph.TextStrokeTransparency = 0
	glyph.TextScaled = true
	glyph.Font = Enum.Font.FredokaOne
	glyph.Parent = billboard

	local row = Instance.new("Frame")
	row.Position = UDim2.fromScale(0, 0.765)
	row.Size = UDim2.fromScale(1, 0.113)
	row.BackgroundTransparency = 1
	row.Parent = billboard

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0.06, 0)
	layout.Parent = row

	local dots: { Frame } = {}
	for index = 1, 3 do
		local dot = Instance.new("Frame")
		dot.Name = `Dot{index}`
		dot.Size = UDim2.fromScale(1, 1)
		dot.BackgroundColor3 = DIM
		dot.LayoutOrder = index
		dot.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
		local round = Instance.new("UIAspectRatioConstraint")
		round.AspectRatio = 1
		round.DominantAxis = Enum.DominantAxis.Height
		round.Parent = dot
		table.insert(dots, dot)
	end

	local streak = Instance.new("TextLabel")
	streak.Position = UDim2.fromScale(0, 0.896)
	streak.Size = UDim2.fromScale(1, 0.104)
	streak.BackgroundTransparency = 1
	streak.TextColor3 = Color3.fromRGB(255, 240, 200)
	streak.TextStrokeTransparency = 0
	streak.TextScaled = true
	streak.Font = Enum.Font.FredokaOne
	streak.Parent = billboard

	return { glyph = glyph, dots = dots, streak = streak }
end

local sign: Sign? = nil

local function render(daily: any)
	if not sign or typeof(daily) ~= "table" then
		return
	end
	local letter = typeof(daily.letterId) == "string" and Letters.get(daily.letterId)
	local done = typeof(daily.done) == "number" and daily.done or 0
	local total = typeof(daily.total) == "number" and daily.total or 3
	local finished = done >= total

	sign.glyph.Text = if letter then letter.glyph else "?"
	sign.glyph.TextColor3 = if finished then GOLD elseif letter then letter.color else Color3.new(1, 1, 1)
	for index, dot in sign.dots do
		dot.BackgroundColor3 = if index <= done then GOLD else DIM
		dot.Visible = index <= total
	end
	local streak = typeof(daily.streak) == "number" and daily.streak or 0
	sign.streak.Text = if streak > 0 then `🔥 {streak}` else ""
end

-- Срез может прийти раньше, чем площадь доедет до клиента: ждём камень один раз.
local function placeWhenReady()
	if waiting then
		return
	end
	waiting = true
	task.spawn(function()
		local hub = workspace:WaitForChild("Hub", 60)
		local stone = hub and hub:WaitForChild("DailyLetterStone", 60)
		waiting = false
		if stone and stone:IsA("BasePart") then
			sign = build(stone)
			render(latest)
		end
	end)
end

function DailyLetterController.update(snapshot: any)
	if typeof(snapshot) ~= "table" or typeof(snapshot.daily) ~= "table" then
		return
	end
	latest = snapshot.daily
	if sign and sign.glyph.Parent then
		render(latest)
	else
		sign = nil
		placeWhenReady()
	end
end

return DailyLetterController
