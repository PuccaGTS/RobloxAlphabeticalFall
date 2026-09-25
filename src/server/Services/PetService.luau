--!nonstrict
--[[
	Питомцы-буквята на сервере: кто за кем летает. Правила — Logic/Pets.

	Сервер решает и проверяет, клиент рисует. Буквёнок, который летает за
	игроком, записывается атрибутами игрока PetLetter и PetLetter2 (id букв), а каждый
	клиент сам строит и водит буквят всех игроков вокруг — PetController.
	Так в мире нет ни одной физической детали питомца (docs/07-TECH-ARCH.md § 8):
	ничего не толкается, не падает и не тормозит сервер, а соседям буквёнка
	видно точно так же, как хозяину.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Shop = require(Shared.Config.Shop)
local Pets = require(Shared.Logic.Pets)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local ProgressService = require(script.Parent.ProgressService)
local RateLimiter = require(script.Parent.RateLimiter)

local PetService = {}

-- Атрибут слота: PetLetter за правым плечом, PetLetter2 — за левым.
PetService.ATTRIBUTES = { "PetLetter", "PetLetter2" }
-- Все 33 буквы освоены: над головой титул «Хранитель Азбуки», его видят все вокруг.
PetService.KEEPER_ATTRIBUTE = "AlphabetKeeper"
-- Скин всех буквят игрока: id предмета Config/Shop категории "petskin".
PetService.SKIN_ATTRIBUTE = "PetSkin"

--[[
	Приводит питомцев в профиле в порядок и выставляет атрибуты. Зовётся при входе
	и после любой смены: так в атрибуте никогда не окажется буквёнок, которого
	у ребёнка нет, даже если профиль испорчен.
]]
function PetService.refresh(player: Player)
	local profile = ProfileService.get(player)
	if not profile then
		return
	end

	local equipped = Pets.sanitizeEquipped(profile.equipped.pets, profile.letters)
	--[[
		Буквята есть, а не летает никто: так бывает у тех, кто выучил буквы
		до того, как буквёнок стал прилетать за изученную (Logic/Pets.OWNED_AT).
		Первый по алфавиту вылетает сам — спутника не надо искать на Башне.
	]]
	if #equipped == 0 then
		local owned = Pets.owned(profile.letters)
		if #owned > 0 then
			equipped = { owned[1] }
		end
	end
	if table.concat(equipped, ",") ~= table.concat(profile.equipped.pets, ",") then
		ProfileService.update(player, function(p)
			p.equipped.pets = equipped
		end)
	end

	for slot, attribute in PetService.ATTRIBUTES do
		player:SetAttribute(attribute, equipped[slot])
	end

	-- Скин — только купленный или заработанный: в атрибут не попадёт чужой id из профиля.
	local skinId = profile.equipped.petskin
	local skin = if typeof(skinId) == "string" then Shop.get(skinId) else nil
	local owned = skin ~= nil and skin.category == "petskin" and table.find(profile.inventory, skinId) ~= nil
	player:SetAttribute(PetService.SKIN_ATTRIBUTE, if owned then skinId else nil)
	player:SetAttribute(PetService.KEEPER_ATTRIBUTE, Pets.isKeeper(profile.letters) or nil)
end

--[[
	Буква изучена: буквёнок прилетает. Публичная, чтобы проверить прилёт в Studio
	из командной строки (docs/HOW-TO-CHECK.md § 3.9).
	Выдаёт только тому, у кого буква и правда изучена: Logic/Pets проверит.
]]
function PetService.grant(player: Player, letterId: string)
	local profile = ProfileService.get(player)
	if not profile or not Pets.isOwned(profile.letters, letterId) then
		return
	end

	local wasKeeper = player:GetAttribute(PetService.KEEPER_ATTRIBUTE) == true
	local hadSecond = player:GetAttribute(PetService.ATTRIBUTES[2]) ~= nil
	ProfileService.update(player, function(p)
		p.equipped.pets = Pets.afterMastered(p.equipped.pets, p.letters, letterId)
	end)
	PetService.refresh(player)

	--[[
		Прилетел новый буквёнок — это главная награда за обучение, и её обязаны
		заметить. Клиент покажет букву крупно, а голос назовёт её: буквёнок
		с первой секунды учит своей букве. Заодно клиент узнаёт, не открылся ли
		второй слот и не стал ли ребёнок Хранителем — это тоже надо увидеть сейчас.
	]]
	RemoteDefs.event("PetGranted"):FireClient(player, letterId, {
		secondSlot = not hadSecond and player:GetAttribute(PetService.ATTRIBUTES[2]) ~= nil,
		keeper = not wasKeeper and player:GetAttribute(PetService.KEEPER_ATTRIBUTE) == true,
	})
	RemoteDefs.event("PlayVO"):FireClient(player, Letters.expect(letterId).vo.name, false)
	print(`[Pets] {player.Name}: прилетел буквёнок {Letters.expect(letterId).glyph}`)
end

local function onEquip(player: Player, letterId: any)
	if not RateLimiter.allow(player, "EquipPet", RemoteDefs.RATE_LIMITS.EquipPet) then
		return
	end
	local profile = ProfileService.get(player)
	if not profile then
		return
	end

	-- Буква не освоена — буквёнка нет, и выбрать его нельзя. Клиенту не верим.
	local chosen = Pets.choose(profile.letters, letterId, profile.equipped.pets)
	if not chosen then
		return
	end

	ProfileService.update(player, function(p)
		p.equipped.pets = chosen
	end)
	PetService.refresh(player)
end

function PetService.start()
	ProgressService.onTransition(function(player: Player, transition)
		-- Прилетает один раз: освоение изученной буквы второго буквёнка не даёт.
		if transition.from < Pets.OWNED_AT and transition.to >= Pets.OWNED_AT then
			PetService.grant(player, transition.letterId)
		end
	end)

	RemoteDefs.event("EquipPet").OnServerEvent:Connect(onEquip)

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			if ProfileService.waitFor(player, 20) then
				PetService.refresh(player)
			end
		end)
	end)
end

return PetService
