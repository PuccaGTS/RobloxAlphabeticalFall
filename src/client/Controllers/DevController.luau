--!nonstrict
--[[
	Панель разработчика: полёт, звёзды, радуга, перенос по локациям.

	Строится, только если сервер поставил игроку атрибут DevTools (Studio или
	владелец места, Services/DevService). Ребёнок её не видит никогда.

	Полёт — здесь, на клиенте: физика персонажа клиентская. Персонаж «стоит
	на платформе» (PlatformStand), а двигают его LinearVelocity и AlignOrientation
	на корне. Направление берётся у стандартного управления (клавиатура и стик
	на планшете одинаково), вверх — Пробел или E, вниз — Shift или Q, на планшете —
	кнопки ▲ ▼ на панели. Клавиша F включает и выключает полёт.

	Бег ×2, ×3 — тоже здесь. Прежняя кнопка «Скорость» меняла только полёт,
	и на проверке 24.09.2026 решили, что она не работает. Множитель ложится
	поверх любой скорости, которую ставит игра (туннель, замедление после
	неверных ворот, самокат): ходьбу персонажа считает клиент, и сервер
	свою скорость менять не перестаёт — клиент домножает каждое её изменение.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefs = require(Shared.Net.RemoteDefs)
local Venues = require(Shared.Config.Venues)

local LiveWorldController = require(script.Parent.LiveWorldController)
local FireworksController = require(script.Parent.FireworksController)
local EveningController = require(script.Parent.EveningController)

local DevController = {}

local SPEEDS = { 60, 200 }
local RUN_FACTORS = { 1, 2, 3 }

local player = Players.LocalPlayer

local flying = false
local speedIndex = 1
local touchVertical = 0
local steer: RBXScriptConnection? = nil
local velocity: LinearVelocity? = nil
local align: AlignOrientation? = nil
local attachment: Attachment? = nil
local flyButton: TextButton? = nil
local speedButton: TextButton? = nil
local runButton: TextButton? = nil
local runIndex = 1
local baseWalk: number? = nil -- скорость, которую поставила игра, без множителя
local applying = false
local walkWatch: RBXScriptConnection? = nil
local controls = nil

local function getControls()
	if controls then
		return controls
	end
	local ok, module = pcall(function()
		local scripts = player:WaitForChild("PlayerScripts")
		return require(scripts:WaitForChild("PlayerModule", 5)):GetControls()
	end)
	controls = if ok then module else nil
	return controls
end

local function moveVector(): Vector3
	local control = getControls()
	if control then
		local ok, vector = pcall(function()
			return control:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" then
			return vector
		end
	end
	local x, z = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		z -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		z += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		x -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		x += 1
	end
	return Vector3.new(x, 0, z)
end

local function verticalInput(): number
	local up = UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E)
	local down = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.Q)
	return (if up then 1 else 0) - (if down then 1 else 0) + touchVertical
end

local function refreshButtons()
	if flyButton then
		flyButton.Text = if flying then "✈ Полёт: да (F)" else "✈ Полёт: нет (F)"
		flyButton.BackgroundColor3 = if flying
			then Color3.fromRGB(120, 210, 140)
			else Color3.fromRGB(235, 235, 240)
	end
	if speedButton then
		speedButton.Text = `✈ Скорость полёта {SPEEDS[speedIndex]}`
	end
	if runButton then
		runButton.Text = `🏃 Бег ×{RUN_FACTORS[runIndex]}`
		runButton.BackgroundColor3 = if runIndex > 1
			then Color3.fromRGB(120, 210, 140)
			else Color3.fromRGB(235, 235, 240)
	end
end

local function applyRun(humanoid: Humanoid)
	if not baseWalk then
		return
	end
	applying = true
	humanoid.WalkSpeed = baseWalk * RUN_FACTORS[runIndex]
	applying = false
end

-- Следит за скоростью персонажа: любое изменение от игры — новая основа для множителя.
local function watchRun(character: Model)
	if walkWatch then
		walkWatch:Disconnect()
		walkWatch = nil
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	baseWalk = humanoid.WalkSpeed
	applyRun(humanoid)
	walkWatch = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if applying then
			return
		end
		baseWalk = humanoid.WalkSpeed
		applyRun(humanoid)
	end)
end

local function stopFly()
	flying = false
	if steer then
		steer:Disconnect()
		steer = nil
	end
	for _, instance in { velocity, align, attachment } do
		if instance then
			instance:Destroy()
		end
	end
	velocity, align, attachment = nil, nil, nil
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	refreshButtons()
end

local function startFly()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	flying = true

	local at = Instance.new("Attachment")
	at.Name = "DevFlyAttachment"
	at.Parent = root
	attachment = at

	local linear = Instance.new("LinearVelocity")
	linear.Attachment0 = at
	linear.MaxForce = math.huge
	linear.VectorVelocity = Vector3.zero
	linear.Parent = root
	velocity = linear

	local orient = Instance.new("AlignOrientation")
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = at
	orient.MaxTorque = math.huge
	orient.Responsiveness = 30
	orient.CFrame = root.CFrame.Rotation
	orient.Parent = root
	align = orient

	humanoid.PlatformStand = true

	steer = RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera or not velocity or not align then
			return
		end
		local look = camera.CFrame.LookVector
		local right = camera.CFrame.RightVector
		local move = moveVector()
		local direction = right * move.X - look * move.Z + Vector3.yAxis * math.clamp(verticalInput(), -1, 1)
		if direction.Magnitude > 1 then
			direction = direction.Unit
		end
		velocity.VectorVelocity = direction * SPEEDS[speedIndex]

		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.05 then
			align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
		end
	end)
	refreshButtons()
end

local function toggleFly()
	if flying then
		stopFly()
	else
		startFly()
	end
end

local function button(parent: Instance, text: string, order: number, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Name = `Dev_{order}`
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, 30)
	b.BackgroundColor3 = Color3.fromRGB(235, 235, 240)
	b.TextColor3 = Color3.fromRGB(40, 40, 50)
	b.Text = text
	b.TextScaled = true
	b.Font = Enum.Font.FredokaOne
	b.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = b
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = b
	b.Activated:Connect(onClick)
	return b
end

local function command(payload: any)
	RemoteDefs.event("DevCommand"):FireServer(payload)
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "AlphabetFallDev"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 50
	screen.Parent = player:WaitForChild("PlayerGui")

	local toggle = Instance.new("TextButton")
	toggle.Name = "DevToggle"
	toggle.Size = UDim2.fromOffset(44, 44)
	toggle.Position = UDim2.new(0, 8, 0.3, 0)
	toggle.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	toggle.TextColor3 = Color3.new(1, 1, 1)
	toggle.Text = "🛠"
	toggle.TextScaled = true
	toggle.Parent = screen
	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 10)
	toggleCorner.Parent = toggle

	local panel = Instance.new("ScrollingFrame")
	panel.Name = "DevPanel"
	panel.Size = UDim2.fromOffset(210, 360)
	panel.Position = UDim2.new(0, 60, 0.3, 0)
	panel.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.ScrollBarThickness = 6
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.CanvasSize = UDim2.new()
	panel.Visible = false
	panel.Parent = screen
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = panel

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	flyButton = button(panel, "", 1, toggleFly)
	speedButton = button(panel, "", 2, function()
		speedIndex = speedIndex % #SPEEDS + 1
		refreshButtons()
	end)
	runButton = button(panel, "", 0, function()
		runIndex = runIndex % #RUN_FACTORS + 1
		refreshButtons()
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			applyRun(humanoid)
		end
	end)

	-- Вверх и вниз для планшета: кнопка держится, пока её не отпустят.
	for order, spec in { { "▲ Вверх", 1 }, { "▼ Вниз", -1 } } do
		local hold = button(panel, spec[1], 2 + order, function() end)
		hold.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				touchVertical = spec[2]
			end
		end)
		hold.InputEnded:Connect(function()
			touchVertical = 0
		end)
	end

	button(panel, "⭐ +100", 10, function()
		command({ kind = "stars", amount = 100 })
	end)
	button(panel, "⭐ +1000", 11, function()
		command({ kind = "stars", amount = 1000 })
	end)
	-- Радуга приходит сама раз в несколько минут или за три звезды — ждать долго.
	button(panel, "🌈 Радуга", 12, function()
		LiveWorldController.rainbow(60)
	end)
	-- Салют бывает только за пройденный уровень — проверять его так дольше всего.
	button(panel, "🎆 Салют", 13, function()
		FireworksController.show()
	end)
	-- Закат бывает раз в двенадцать минут. Днём кнопка зовёт золотой час, вечером — утро.
	button(panel, "🌅 Закат", 14, function()
		local at = EveningController.now()
		EveningController.skipTo(if at >= 470 and at < 700 then 700 else 500)
	end)

	button(panel, "➜ Площадь", 20, function()
		command({ kind = "teleport", target = "hub" })
	end)
	button(panel, "➜ Мой дом", 21, function()
		command({ kind = "teleport", target = "home" })
	end)
	for index, venue in Venues.all do
		button(panel, `➜ {venue.title}`, 30 + index, function()
			command({ kind = "teleport", target = venue.id })
		end)
	end

	refreshButtons()

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F then
			toggleFly()
		end
	end)

	player.CharacterAdded:Connect(function(character)
		if flying then
			stopFly()
		end
		watchRun(character)
	end)
	if player.Character then
		task.spawn(watchRun, player.Character)
	end
end

function DevController.init()
	local built = false
	local function check()
		if not built and player:GetAttribute("DevTools") == true then
			built = true
			build()
		end
	end
	player:GetAttributeChangedSignal("DevTools"):Connect(check)
	check()
end

return DevController
