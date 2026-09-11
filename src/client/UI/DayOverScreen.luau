--!nonstrict
--[[
	Экран «На сегодня всё»: время, которое родитель отвёл на день, вышло.
	См. docs/13-PARENT-MODE.md § 3 и Services/PlayLimitService.

	Спокойный, а не запрещающий: ночное небо, луна, «до завтра». Голос говорит
	то же самое (ui_goodbye), текст — для родителя рядом. Ни таймеров,
	ни «ещё пять минуточек за Robux» — только прощание.

	Родительский вход на экране свой: кнопка ⚙ в HUD лежит под этим экраном,
	а родителю должно хватить одного касания, чтобы поднять лимит.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local DayOverScreen = {}

local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local onParent: (() -> ())? = nil

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "AlphabetFallDayOver"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	screen.DisplayOrder = 5 -- выше детского интерфейса, ниже экрана родителя
	screen.Parent = player:WaitForChild("PlayerGui")

	local sky = Instance.new("Frame")
	sky.Size = UDim2.fromScale(1, 1)
	sky.BackgroundColor3 = Color3.fromRGB(24, 30, 62)
	sky.BackgroundTransparency = 0.05
	sky.Active = true -- касания не проходят в игру под экраном
	sky.Parent = screen

	local moon = Instance.new("TextLabel")
	moon.Name = "Moon"
	moon.Size = UDim2.fromScale(0.3, 0.3)
	moon.Position = UDim2.fromScale(0.35, 0.12)
	moon.BackgroundTransparency = 1
	moon.Text = "🌙"
	moon.TextScaled = true
	moon.Parent = sky

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.8, 0.12)
	title.Position = UDim2.fromScale(0.1, 0.46)
	title.BackgroundTransparency = 1
	title.Text = "На сегодня всё!"
	title.TextColor3 = Color3.fromRGB(255, 240, 200)
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.Parent = sky

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.fromScale(0.8, 0.07)
	subtitle.Position = UDim2.fromScale(0.1, 0.6)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "До завтра! Буквы будут тебя ждать."
	subtitle.TextColor3 = Color3.fromRGB(200, 205, 235)
	subtitle.TextScaled = true
	subtitle.Font = Enum.Font.FredokaOne
	subtitle.Parent = sky

	--[[
		Экран закрывается: завершение мягкое, и погулять по двору или примерить
		шапку ребёнку никто не запрещает. Запрещены только новые занятия —
		подойдёт к паду, и экран появится снова.
	]]
	local okButton = Instance.new("TextButton")
	okButton.Size = UDim2.fromOffset(200, 64)
	okButton.Position = UDim2.new(0.5, -100, 0.72, 0)
	okButton.BackgroundColor3 = Color3.fromRGB(255, 214, 102)
	okButton.TextColor3 = Color3.fromRGB(40, 40, 50)
	okButton.Text = "Хорошо 👋"
	okButton.TextScaled = true
	okButton.Font = Enum.Font.FredokaOne
	okButton.Parent = sky
	okButton.Activated:Connect(function()
		screen.Enabled = false
	end)

	local okCorner = Instance.new("UICorner")
	okCorner.CornerRadius = UDim.new(0, 16)
	okCorner.Parent = okButton

	local parent = Instance.new("TextButton")
	parent.Size = UDim2.fromOffset(220, 44)
	parent.Position = UDim2.new(0.5, -110, 1, -76)
	parent.BackgroundColor3 = Color3.fromRGB(60, 64, 96)
	parent.TextColor3 = Color3.fromRGB(210, 215, 235)
	parent.Text = "⚙ Для родителей"
	parent.TextSize = 18
	parent.Font = Enum.Font.GothamBold
	parent.Parent = sky
	parent.Activated:Connect(function()
		if onParent then
			onParent()
		end
	end)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = parent

	-- Луна медленно покачивается: экран живой, но ничего не требует.
	TweenService:Create(
		moon,
		TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromScale(0.35, 0.09) }
	):Play()

	gui = screen
end

function DayOverScreen.init(openParent: () -> ())
	onParent = openParent
	if not gui then
		build()
	end
end

function DayOverScreen.show()
	if not gui then
		build()
	end
	gui.Enabled = true
end

function DayOverScreen.hide()
	if gui then
		gui.Enabled = false
	end
end

return DayOverScreen
