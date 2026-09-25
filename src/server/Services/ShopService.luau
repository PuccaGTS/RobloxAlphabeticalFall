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
local PetService = require(script.Parent.PetService)
local RateLimiter = require(script.Parent.RateLimiter)

local ShopService = {}

--[[
	Хуки на удачную покупку. Нужны обучению: первая шапка закрывает его шаг
	«магазин». Сервис при этом не знает про обучение — обучение знает про сервис.
]]
local purchaseHooks: { (player: Player, itemId: string) -> () } = {}

function ShopService.onPurchase(hook: (player: Player, itemId: string) -> ())
	table.insert(purchaseHooks, hook)
end

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

	if not item.price or item.retired then
		-- предмет выдаётся за прогресс, продаётся за Robux или снят с продажи — здесь его не купить
		return
	end

	if item.unlockStage > ProgressService.unlockedStageIndex(profile) then
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
	-- Скин буквят надевается не на персонажа, а на буквят: их ведёт PetService.
	PetService.refresh(player)
	print(`[Shop] {player.Name} купил {itemId} за {item.price} ⭐`)

	for _, hook in purchaseHooks do
		task.spawn(hook, player, itemId)
	end
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
	PetService.refresh(player)
end

function ShopService.start()
	RemoteDefs.event("BuyItem").OnServerEvent:Connect(onBuy)
	RemoteDefs.event("EquipItem").OnServerEvent:Connect(onEquip)
end

return ShopService
