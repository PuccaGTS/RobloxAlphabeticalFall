--!nonstrict
--[[
	Коллекционные сундуки в парке. Правила и места — Config/Chests.

	Сундук общий для всех, а открыт он у каждого свой: крышку поднимает клиент
	по своему инвентарю (ChestController). Сервер только строит сундуки и выдаёт
	вещь — один раз, по конфигу, а не по запросу клиента: клиент присылает
	одно касание, и что внутри, он не выбирает.

	Открывается и подсказкой, и касанием: дошкольник не ищет клавишу E,
	он подходит и трогает сундук (так же устроены пады, WorldService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Chests = require(Shared.Config.Chests)
local Decor = require(Shared.Config.Decor)
local Shop = require(Shared.Config.Shop)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local CosmeticsService = require(script.Parent.CosmeticsService)

local ChestService = {}

local FOLDER_NAME = "Chests"
local TOUCH_DEBOUNCE = 2
local WOOD = Color3.fromRGB(150, 95, 55)
local IRON = Color3.fromRGB(90, 85, 80)
local GOLD = Color3.fromRGB(255, 205, 90)

local lastTouch: { [Player]: number } = {}

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
	Выдаёт вещь из сундука. Уже открытый ничего не даёт второй раз, но на подсказку
	отвечает: «пусто» без ответа выглядело бы поломкой. На касание — молчит:
	ребёнок, стоящий рядом, иначе слушал бы «уже открыт» каждые две секунды.
]]
function ChestService.open(player: Player, chestId: string, byTouch: boolean?): boolean
	local chest = Chests.get(chestId)
	local profile = ProfileService.get(player)
	if not chest or not profile then
		return false
	end

	local item = Shop.get(chest.itemId)
	if not item or Chests.chestIdOf(item.grantedBy) ~= chest.id then
		warn(`[Chests] в сундуке {chest.id} предмет не из сундука: {chest.itemId}`)
		return false
	end

	if Chests.isOpened(chest, profile.inventory) then
		if not byTouch then
			RemoteDefs.event("ChestOpened"):FireClient(player, { state = "already", itemId = item.id })
		end
		return false
	end

	ProfileService.update(player, function(p)
		table.insert(p.inventory, item.id)
		-- Как с покупкой: найденное сразу на ребёнке, искать в гардеробе не нужно.
		p.equipped[item.category] = item.id
	end)
	CosmeticsService.apply(player)

	RemoteDefs.event("PlaySfx"):FireClient(player, "reward")
	RemoteDefs.event("ChestOpened"):FireClient(player, { state = "opened", itemId = item.id })
	print(`[Chests] {player.Name} открыл {chest.id}: {item.id}`)
	return true
end

local function build(folder: Folder, chest: Chests.Chest)
	local position = Chests.position(chest)
	local ground = Decor.groundY(position.X, position.Z)
	local at = CFrame.new(position.X, ground, position.Z) * CFrame.Angles(0, math.rad(chest.rotation), 0)

	local model = Instance.new("Model")
	model.Name = chest.id
	model:SetAttribute("ItemId", chest.itemId)
	model.Parent = folder

	local body = part("Body", Vector3.new(3.4, 2, 2.4), at * CFrame.new(0, 1, 0), WOOD, model)
	part("Band", Vector3.new(3.5, 0.3, 2.5), at * CFrame.new(0, 1.2, 0), IRON, model)
	-- Крышка откидывается на петлях у задней стенки: клиент крутит её вокруг этой оси.
	local lid = part("Lid", Vector3.new(3.4, 0.7, 2.4), at * CFrame.new(0, 2.35, 0), WOOD, model)
	lid:SetAttribute("Hinge", at * CFrame.new(0, 2, 1.2))
	part("Lock", Vector3.new(0.5, 0.6, 0.2), at * CFrame.new(0, 1.9, -1.25), GOLD, model).Material =
		Enum.Material.Neon
	model.PrimaryPart = body

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Открыть"
	prompt.ObjectText = "Сундук"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.Triggered:Connect(function(player: Player)
		ChestService.open(player, chest.id)
	end)

	for _, piece in { body, lid } do
		piece.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end
			local now = os.clock()
			if lastTouch[player] and now - lastTouch[player] < TOUCH_DEBOUNCE then
				return
			end
			lastTouch[player] = now
			ChestService.open(player, chest.id, true)
		end)
	end
end

function ChestService.start()
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace

	for _, chest in Chests.all do
		build(folder, chest)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		lastTouch[player] = nil
	end)

	print(`[Chests] сундуков в парке: {#Chests.all}`)
end

return ChestService
