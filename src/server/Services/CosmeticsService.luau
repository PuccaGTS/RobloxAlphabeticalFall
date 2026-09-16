--!nonstrict
--[[
	Надевание косметики на персонажа.

	Важно (docs/04-ECONOMY.md § 5): в Roblox нельзя программно подарить игроку предмет
	из каталога Roblox. Поэтому косметика двух видов, и обе живут только внутри игры:

	  · аксессуар каталога — бесплатная вещь Roblox, которую игра надевает
	    через HumanoidDescription, как примерочная. В инвентарь Roblox она
	    не попадает и за пределами игры на ребёнке не видна;
	  · рецепт из деталей — наши примитивы, привариваются к телу.

	Надевается при каждом появлении персонажа и после смены экипировки.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Shop = require(Shared.Config.Shop)

local ProfileService = require(script.Parent.ProfileService)

local CosmeticsService = {}

local FOLDER_NAME = "Cosmetics"
local EFFECT_PREFIX = "AFEffect_"

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
			local leftover = root:FindFirstChild(name)
			if leftover then
				leftover:Destroy()
			end
		end
		for _, child in root:GetChildren() do
			if string.sub(child.Name, 1, #EFFECT_PREFIX) == EFFECT_PREFIX then
				child:Destroy()
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
		-- Прозрачность — для стекла: шлем космонавта не должен закрывать лицо.
		part.Transparency = piece.transparency or 0
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
	Поля HumanoidDescription, куда ложатся аксессуары наших категорий.
	Слоты ребёнка вне игры не трогаются: убираются только номера наших вещей.
]]
local ACCESSORY_FIELDS: { [string]: string } = {
	hat = "HatAccessory",
	back = "BackAccessory",
	face = "FaceAccessory",
}

local SHOP_ACCESSORIES: { [string]: boolean } = {}
for _, item in Shop.all do
	if item.accessory then
		SHOP_ACCESSORIES[tostring(item.accessory)] = true
	end
end

--[[
	Надевает аксессуары каталога. Берём описание, которое уже на персонаже
	(его собственная одежда и вещи), выбрасываем из него всё наше и кладём
	то, что надето сейчас. Возвращает false, если Roblox вещь не выдал —
	тогда вызывающий наденет запасной рецепт из деталей.
]]
local function applyAccessories(character: Model, worn: { any }): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not ok or not description then
		return false
	end

	local changed = false
	for category, field in ACCESSORY_FIELDS do
		local kept: { string } = {}
		for id in string.gmatch(description[field], "[^,%s]+") do
			if SHOP_ACCESSORIES[id] then
				changed = true
			else
				table.insert(kept, id)
			end
		end
		for _, item in worn do
			if item.category == category then
				table.insert(kept, tostring(item.accessory))
				changed = true
			end
		end
		description[field] = table.concat(kept, ",")
	end

	if not changed then
		return true
	end

	local applied = pcall(function()
		humanoid:ApplyDescription(description)
	end)
	if not applied then
		warn(`[Cosmetics] аксессуары каталога не надеты у {character.Name}`)
	end
	return applied
end

--[[
	Шлейф редкой вещи: частицы из-за спины и светящаяся лента. Висит на корне,
	как след: у аксессуаров каталога своих деталей у нас нет, а у корня есть всегда.
]]
local function attachEffect(character: Model, item)
	local root = character:FindFirstChild("HumanoidRootPart")
	local effect = item.effect
	if not root or not effect then
		return
	end

	local emitterAt = Instance.new("Attachment")
	emitterAt.Name = `{EFFECT_PREFIX}{item.id}_Emitter`
	emitterAt.Position = if item.category == "hat" then Vector3.new(0, 2.2, 0.4) else Vector3.new(0, 0.3, 0.9)
	emitterAt.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = `{EFFECT_PREFIX}{item.id}_Particles`
	emitter.Texture = Shop.PARTICLE_TEXTURES[effect.particles] or Shop.PARTICLE_TEXTURES.sparkle
	emitter.Color = effect.color
	emitter.Rate = effect.rate
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(0.5, 2)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Acceleration = if effect.particles == "sparkle"
		then Vector3.new(0, -2, 0)
		else Vector3.new(0, 3, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, effect.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.LightEmission = effect.lightEmission or 0.5
	emitter.EmissionDirection = Enum.NormalId.Back
	-- Шлейф остаётся в мире, а не летит за ребёнком: так и получается след.
	emitter.LockedToPart = false
	emitter.Parent = emitterAt

	if effect.trail then
		local top = Instance.new("Attachment")
		top.Name = `{EFFECT_PREFIX}{item.id}_Top`
		top.Position = Vector3.new(0, 0.6, 0.6)
		top.Parent = root
		local bottom = Instance.new("Attachment")
		bottom.Name = `{EFFECT_PREFIX}{item.id}_Bottom`
		bottom.Position = Vector3.new(0, -0.6, 0.6)
		bottom.Parent = root

		local ribbon = Instance.new("Trail")
		ribbon.Name = `{EFFECT_PREFIX}{item.id}_Trail`
		ribbon.Attachment0 = top
		ribbon.Attachment1 = bottom
		ribbon.Color = effect.trail.color
		ribbon.Lifetime = effect.trail.lifetime
		ribbon.WidthScale = NumberSequence.new(effect.trail.width)
		ribbon.Transparency = NumberSequence.new(0.2, 1)
		ribbon.LightEmission = 0.8
		ribbon.FaceCamera = true
		ribbon.Parent = root
	end
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

	local worn = {}
	for _, category in Shop.CATEGORIES do
		local itemId = profile.equipped[category]
		if itemId then
			local item = Shop.get(itemId)
			if item then
				attachEffect(character, item)
				if item.trail then
					attachTrail(character, item)
				elseif item.accessory then
					table.insert(worn, item)
				else
					attachVisual(character, folder, item)
				end
			end
		end
	end

	-- Снимать чужие наши вещи надо и тогда, когда ничего не надето: вызов нужен всегда.
	if not applyAccessories(character, worn) then
		for _, item in worn do
			attachVisual(character, folder, item)
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
