--!nonstrict
--[[
	Безопасный перенос ребёнка по миру.

	Поляны занятий и туннели стоят за тысячи студов от площади, а в месте включён
	StreamingEnabled: клиент получает детали только вокруг персонажа. Раньше сервер
	просто ставил персонажа на поляну — пол там у клиента ещё не подгрузился,
	физика персонажа (она клиентская) роняла его в пустоту, и ребёнок «умирал».

	Поэтому перенос идёт в три шага:
	1. поставить персонажа и придержать его якорем на корне;
	2. попросить стриминг подгрузить место и отпустить якорь, когда пол пришёл;
	3. запомнить точку как «безопасную» — если ребёнок всё же провалится,
	   страж падения вернёт его туда, а не в смерть и не на площадь.

	Страж падения общий для всего мира: смерти в игре нет нигде.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Teleport = {}

local HOLD_SECONDS = 0.6 -- сколько персонаж стоит на якоре после переноса
local STREAM_TIMEOUT = 5
local FALL_DEPTH = 90 -- насколько ниже безопасной точки считаем, что ребёнок падает
local CHECK_EVERY = 0.25

-- Точка появления на площади: сюда страж возвращает, если другой точки нет.
Teleport.HUB = CFrame.new(0, 5, 26)

local safeOf: { [Player]: CFrame } = {}
local holdToken: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Запомнить безопасную точку без переноса: например, пройденную арку туннеля.
function Teleport.setSafe(player: Player, cframe: CFrame)
	safeOf[player] = cframe
end

function Teleport.safeOf(player: Player): CFrame
	return safeOf[player] or Teleport.HUB
end

--[[
	Перенести персонажа. Возвращается сразу: персонаж уже стоит на месте
	и держится якорем, а подгрузка места идёт в фоне. Якорь снимается,
	когда клиент получил пол под ногами (или вышло время ожидания).
]]
function Teleport.to(player: Player, cframe: CFrame)
	safeOf[player] = cframe

	local character = player.Character
	local root = rootOf(player)
	if not character or not root then
		return
	end

	local token = (holdToken[player] or 0) + 1
	holdToken[player] = token

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	character:PivotTo(cframe)

	task.spawn(function()
		if player.Parent then
			pcall(function()
				player:RequestStreamAroundAsync(cframe.Position, STREAM_TIMEOUT)
			end)
		end
		task.wait(HOLD_SECONDS)
		if holdToken[player] == token and root.Parent then
			root.Anchored = false
		end
	end)
end

function Teleport.start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < CHECK_EVERY then
			return
		end
		elapsed = 0

		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			local safe = Teleport.safeOf(player)
			if root and not root.Anchored and root.Position.Y < safe.Position.Y - FALL_DEPTH then
				Teleport.to(player, safe)
			end
		end
	end)

	-- Новый персонаж появляется на площади или у дома: старая точка ему не нужна.
	local function track(player: Player)
		player.CharacterAdded:Connect(function()
			safeOf[player] = nil
			holdToken[player] = nil
		end)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		safeOf[player] = nil
		holdToken[player] = nil
	end)
end

return Teleport
