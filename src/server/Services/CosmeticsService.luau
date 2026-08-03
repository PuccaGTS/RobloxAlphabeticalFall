--!nonstrict
--[[
	Надевание косметики на персонажа.

	Важно (docs/04-ECONOMY.md § 5): в Roblox нельзя программно подарить игроку предмет
	из каталога Roblox, поэтому вся косметика — наши собственные детали, которые
	привариваются к персонажу заново при каждом появлении (CharacterAdded).

	Пока арта нет, детали собираются из примитивов по рецепту из Config/Shop.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Shop = require(Shared.Config.Shop)

local ProfileService = require(script.Parent.ProfileService)

local CosmeticsService = {}

local FOLDER_NAME = "Cosmetics"

-- R6 и R15 называют части по-разному, поэтому ищем по обоим вариантам.
local ATTACH_POINTS: { [string]: { string } } = {
	hat = { "Head" },
	face = { "Head" },
	back = { "UpperTorso", "Torso" },
}

local function findAttachPart(character: Model, category: string): BasePart?
	local names = ATTACH_POINTS[category]
	if not names then
		return nil
	end
	for _, name in names do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function shapeOf(name: string): Enum.PartType
	if name == "Ball" then
		return Enum.PartType.Ball
	elseif name == "Cylinder" then
		return Enum.PartType.Cylinder
	end
	return Enum.PartType.Block
end

local function clearCosmetics(character: Model)
	local existing = character:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		for _, name in { "AlphabetFallTrail", "AFTrailTop", "AFTrailBottom" } do
			local existing = root:FindFirstChild(name)
			if existing then
				existing:Destroy()
			end
		end
	end
end

--[[
	Предмет собирается из нескольких деталей: из одного куба не получается ни кепка,
	ни корона — получается куб на голове. Каждая деталь приваривается к телу отдельно.
]]
local function attachVisual(character: Model, folder: Folder, item)
	local target = findAttachPart(character, item.category)
	if not target or not item.visual then
		return
	end

	for index, piece in item.visual do
		local part = Instance.new("Part")
		part.Name = `{item.id}_{index}`
		part.Shape = shapeOf(piece.shape)
		part.Size = piece.size
		part.Color = piece.color
		part.Material = piece.material or Enum.Material.SmoothPlastic
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Anchored = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		-- Смещения в рецептах заданы относительно ЦЕНТРА головы или торса.
		part.CFrame = target.CFrame * piece.offset
		part.Parent = folder

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = target
		weld.Part1 = part
		weld.Parent = part
	end
end

local function attachTrail(character: Model, item)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not item.trail then
		return
	end

	-- Attachment обязан быть ребёнком BasePart, поэтому всё вешаем прямо на корень.
	local a0 = Instance.new("Attachment")
	a0.Name = "AFTrailTop"
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent = root

	local a1 = Instance.new("Attachment")
	a1.Name = "AFTrailBottom"
	a1.Position = Vector3.new(0, -1, 0)
	a1.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "AlphabetFallTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = item.trail.color
	trail.Lifetime = item.trail.lifetime
	trail.WidthScale = NumberSequence.new(item.trail.width)
	trail.LightEmission = 0.6
	trail.Parent = root
end

--[[
	Надевает всё, что у игрока экипировано. Вызывается при появлении персонажа
	и после каждой смены экипировки.
]]
function CosmeticsService.apply(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local profile = ProfileService.get(player)
	if not profile then
		return
	end

	clearCosmetics(character)

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = character

	for _, category in Shop.CATEGORIES do
		local itemId = profile.equipped[category]
		if itemId then
			local item = Shop.get(itemId)
			if item then
				if item.trail then
					attachTrail(character, item)
				else
					attachVisual(character, folder, item)
				end
			end
		end
	end
end

function CosmeticsService.start()
	local function hook(player: Player)
		player.CharacterAppearanceLoaded:Connect(function()
			-- профиль может ещё грузиться — ждём, иначе наденем пустоту
			task.spawn(function()
				ProfileService.waitFor(player, 20)
				CosmeticsService.apply(player)
			end)
		end)
	end

	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
end

return CosmeticsService
