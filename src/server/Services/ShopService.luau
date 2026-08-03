--!nonstrict
--[[
	Покупки и гардероб.

	Клиент присылает только id предмета. Цена, доступность и владение проверяются
	на сервере по Config/Shop — из запроса клиента не берётся ничего, кроме id.
	См. docs/07-TECH-ARCH.md § 7.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Shop = require(Shared.Config.Shop)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local EconomyService = require(script.Parent.EconomyService)
local ProgressService = require(script.Parent.ProgressService)
local CosmeticsService = require(script.Parent.CosmeticsService)
local RateLimiter = require(script.Parent.RateLimiter)

local ShopService = {}

local function owns(profile, itemId: string): boolean
	return table.find(profile.inventory, itemId) ~= nil
end

local function onBuy(player: Player, itemId: any)
	if typeof(itemId) ~= "string" then
		return
	end
	if not RateLimiter.allow(player, "BuyItem", RemoteDefs.RATE_LIMITS.BuyItem) then
		return
	end

	local item = Shop.get(itemId)
	if not item then
		warn(`[ShopService] попытка купить неизвестный предмет: {itemId}`)
		return
	end

	local profile = ProfileService.get(player)
	if not profile then
		return
	end

	if owns(profile, itemId) then
		return
	end

	if not item.price then
		-- предмет выдаётся за прогресс или продаётся за Robux — здесь его не купить
		return
	end

	if item.unlockIsland > ProgressService.unlockedIslandIndex(profile) then
		return
	end

	if not EconomyService.spend(player, item.price, `shop:{itemId}`) then
		return
	end

	ProfileService.update(player, function(p)
		table.insert(p.inventory, itemId)
		-- Купленное сразу надевается: ребёнок должен увидеть покупку на себе немедленно,
		-- а не искать её в гардеробе.
		p.equipped[item.category] = itemId
	end)

	CosmeticsService.apply(player)
	print(`[Shop] {player.Name} купил {itemId} за {item.price} ⭐`)
end

local function onEquip(player: Player, itemId: any)
	if not RateLimiter.allow(player, "EquipItem", RemoteDefs.RATE_LIMITS.EquipItem) then
		return
	end

	local profile = ProfileService.get(player)
	if not profile then
		return
	end

	-- nil или пустая строка = снять всё из категории (кнопка «снять»)
	if typeof(itemId) ~= "string" or itemId == "" then
		return
	end

	local item = Shop.get(itemId)
	if not item or not owns(profile, itemId) then
		return
	end

	ProfileService.update(player, function(p)
		-- повторный тап по надетому предмету снимает его
		if p.equipped[item.category] == itemId then
			p.equipped[item.category] = nil
		else
			p.equipped[item.category] = itemId
		end
	end)

	CosmeticsService.apply(player)
end

function ShopService.start()
	RemoteDefs.event("BuyItem").OnServerEvent:Connect(onBuy)
	RemoteDefs.event("EquipItem").OnServerEvent:Connect(onEquip)
end

return ShopService
