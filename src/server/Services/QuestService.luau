--!nonstrict
--[[
	Задания дня на сервере. Правила — Logic/Quests, награды — Config/Economy.

	Сервис слушает то, что уже происходит в игре: конец занятия, финиш уровня,
	стройку у дома, покупку, найденный сундук, — и двигает счётчики. Выполнил —
	звёзды сразу и тост у клиента; все три — ещё бонус. Клиенту уходит список
	с дорогой: где на карте цель задания (пад, портал, свой дом, сундук).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Base = require(Shared.Config.Base)
local Chests = require(Shared.Config.Chests)
local Decor = require(Shared.Config.Decor)
local Economy = require(Shared.Config.Economy)
local Playground = require(Shared.Config.Playground)
local Shop = require(Shared.Config.Shop)
local PlayLog = require(Shared.Logic.PlayLog)
local Quests = require(Shared.Logic.Quests)
local LetterGarden = require(Shared.Logic.LetterGarden)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local EconomyService = require(script.Parent.EconomyService)
local ChallengeService = require(script.Parent.ChallengeService)
local ShopService = require(script.Parent.ShopService)
local BaseService = require(script.Parent.BaseService)
local ChestService = require(script.Parent.ChestService)
local RentalService = require(script.Parent.RentalService)
local CosmeticsService = require(script.Parent.CosmeticsService)
local GardenService = require(script.Parent.GardenService)
local RateLimiter = require(script.Parent.RateLimiter)

--[[
	Сколько студов сверх радиуса места ребёнок может стоять от его середины, когда
	клиент сообщает «сделано»: посадочные круги и тарзанка — у края места, остров
	на стебле шире самого стебля.
]]
local PARK_REACH = 25

local spotById = {}
for _, spot in Playground.spots do
	spotById[spot.id] = spot
end

-- Середина места парка на земле: сюда ведёт стрелка заданий и доска «Куда пойти».
local function spotPosition(id: string): Vector3?
	local spot = spotById[id]
	if not spot then
		return nil
	end
	local position = Playground.position(spot)
	return Vector3.new(position.X, Decor.groundY(position.X, position.Z), position.Z)
end

local QuestService = {}

local function today(): number
	return PlayLog.dayOf(os.time())
end

-- Первый ненайденный сундук по порядку в Config/Chests: сначала простые, у дорожек.
local function nextChest(profile): Chests.Chest?
	for _, chest in Chests.all do
		if not Chests.isOpened(chest, profile.inventory) then
			return chest
		end
	end
	return nil
end

local function canBuild(profile): boolean
	local levels = Base.sanitize(profile.base)
	for _, category in Base.CATEGORIES do
		if Base.priceFor(category.id, levels[category.id] or 0) then
			return true
		end
	end
	return false
end

-- Какие задания сейчас выполнимы: найденные сундуки и достроенный дом не просим.
local function available(profile): { string }
	local ids = {}
	for _, quest in Quests.POOL do
		if quest.id == "chest" and not nextChest(profile) then
			continue
		end
		if quest.id == "build" and not canBuild(profile) then
			continue
		end
		if
			quest.id == "plant"
			and not LetterGarden.hasEmpty(LetterGarden.sanitize(profile.garden), os.time())
		then
			continue
		end
		table.insert(ids, quest.id)
	end
	return ids
end

local function targetOf(player: Player, profile, quest): Vector3?
	if quest.target == "garden" then
		return GardenService.position(player)
	elseif quest.target == "home" then
		local home = BaseService.homeCFrame(player)
		return home and home.Position
	elseif quest.target == "chest" then
		local chest = nextChest(profile)
		local folder = workspace:FindFirstChild("Chests")
		local model = chest and folder and folder:FindFirstChild(chest.id)
		return if model and model:IsA("Model") then model:GetPivot().Position else nil
	elseif quest.target and string.sub(quest.target, 1, 5) == "spot:" then
		return spotPosition(string.sub(quest.target, 6))
	elseif quest.target then
		local hub = workspace:FindFirstChild("Hub")
		local part = hub and hub:FindFirstChild(quest.target)
		if part and part:IsA("BasePart") then
			return part.Position
		elseif part and part:IsA("Model") then
			return part:GetPivot().Position
		end
	end
	return nil
end

-- Задание недели для панели: что, сколько сделано и какая вещь ждёт в конце.
local function weekOf(profile)
	local state = Quests.sanitize(profile.quests)
	local week = state.week
	local weekly = week and Quests.weekly(week.id)
	if not week or not weekly then
		return nil
	end
	local prizeId = Quests.weekReward(profile.inventory)
	local prize = prizeId and Shop.get(prizeId)
	return {
		id = weekly.id,
		icon = weekly.icon,
		title = weekly.title,
		have = week.have,
		need = weekly.need,
		done = week.done,
		prizeIcon = if prize then prize.icon else "⭐",
		prizeTitle = if prize then prize.title else `{Economy.REWARDS.weeklyQuestNoItem} ⭐`,
		daysLeft = 7 - (state.day % 7),
	}
end

local function push(player: Player, justDone: { string }?, awarded: number?, weekPrize: string?)
	local profile = ProfileService.get(player)
	if not profile then
		return
	end
	local state = Quests.sanitize(profile.quests)
	local items = {}
	for _, id in state.list do
		local quest = Quests.get(id)
		if quest then
			table.insert(items, {
				id = id,
				icon = quest.icon,
				title = quest.title,
				have = state.progress[id] or 0,
				need = quest.need,
				done = Quests.isDone(state, id),
				target = targetOf(player, profile, quest),
			})
		end
	end
	RemoteDefs.event("Quests"):FireClient(player, {
		day = state.day,
		bonus = state.bonus,
		items = items,
		justDone = justDone or {},
		awarded = awarded or 0,
		week = weekOf(profile),
		-- Неделя выполнена только что: какая вещь выдана (id из Config/Shop) или "stars".
		weekPrize = weekPrize,
	})
end

--[[
	Неделя выполнена: следующая вещь из Quests.WEEK_REWARDS — сразу на ребёнке,
	как из сундука, и 100 ⭐ сверху. Все вещи собраны — 150 ⭐ вместо вещи.
]]
local function rewardWeek(player: Player): (number, string)
	local itemId: string? = nil
	ProfileService.update(player, function(p)
		itemId = Quests.weekReward(p.inventory)
		if itemId then
			table.insert(p.inventory, itemId)
			p.equipped[Shop.expect(itemId).category] = itemId
		end
	end)
	if itemId then
		CosmeticsService.apply(player)
		print(`[Quests] {player.Name} выполнил задание недели: {itemId}`)
		return EconomyService.award(player, "weekly_quest", Economy.REWARDS.weeklyQuest, itemId), itemId
	end
	return EconomyService.award(player, "weekly_quest", Economy.REWARDS.weeklyQuestNoItem), "stars"
end

-- Новый день — новые задания. Зовётся при входе и перед каждым событием.
function QuestService.refresh(player: Player): boolean
	local profile = ProfileService.get(player)
	if not profile then
		return false
	end
	local changed = false
	ProfileService.update(player, function(p)
		p.quests, changed = Quests.refresh(p.quests, today(), available(p))
	end)
	return changed
end

--[[
	Событие игры: "finished" (с id занятия), "level:letters", "level:math",
	"build", "purchase", "chest". Выполненные задания платят сразу.
]]
function QuestService.record(player: Player, event: string, detail: string?)
	if not ProfileService.get(player) then
		return
	end
	QuestService.refresh(player)

	local completed = {}
	local allNow = false
	local weekNow = false
	ProfileService.update(player, function(p)
		p.quests, completed = Quests.record(p.quests, event, detail)
		allNow = Quests.allDone(p.quests) and not p.quests.bonus
		if allNow then
			p.quests.bonus = true
		end
		-- Неделя слышит то же событие, а каждое выполненное задание дня — как "daily_quest".
		local done
		p.quests, done = Quests.recordWeek(p.quests, event)
		weekNow = weekNow or done
		for _ in completed do
			p.quests, done = Quests.recordWeek(p.quests, "daily_quest")
			weekNow = weekNow or done
		end
	end)

	local awarded = 0
	for _, id in completed do
		awarded += EconomyService.award(player, "daily_quest", Economy.REWARDS.dailyQuest, id)
	end
	if allNow then
		awarded += EconomyService.award(player, "daily_quests_all", Economy.REWARDS.dailyQuestsAll)
	end
	local weekPrize: string? = nil
	if weekNow then
		local stars
		stars, weekPrize = rewardWeek(player)
		awarded += stars
	end
	if #completed > 0 or weekNow then
		RemoteDefs.event("PlaySfx"):FireClient(player, "reward")
		push(player, completed, awarded, weekPrize)
	else
		-- Счётчик «три разных», задание недели или цель стрелки (следующий сундук) могли сдвинуться.
		push(player)
	end
end

function QuestService.start()
	--[[
		Засчитывается законченное занятие, в котором ребёнок хоть раз ответил:
		топтание на паде задание не выполняет, как и звёзд не приносит.
	]]
	ChallengeService.onFinished(function(player: Player, spec: any, reason: string, answers: number)
		if answers <= 0 or (reason ~= "completed" and reason ~= "timeout") then
			return
		end
		QuestService.record(player, "finished", spec.challengeId)
		if reason == "completed" and spec.level then
			QuestService.record(player, "level:letters")
		end
		if reason == "completed" and typeof(spec.params) == "table" and spec.params.mathLevel then
			QuestService.record(player, "level:math")
		end
	end)
	ShopService.onPurchase(function(player: Player)
		QuestService.record(player, "purchase")
	end)
	BaseService.onUpgrade(function(player: Player)
		QuestService.record(player, "build")
	end)
	ChestService.onOpened(function(player: Player)
		QuestService.record(player, "chest")
	end)
	-- Секрет уровня найден впервые (Logic/Secrets): для задания недели «найди 3 секрета».
	ChallengeService.onAnswer(function(player: Player, _spec: any, result: any)
		if typeof(result) == "table" and result.secret then
			QuestService.record(player, "secret")
		end
	end)
	GardenService.onAction(function(player: Player, action: string)
		QuestService.record(player, action)
	end)
	RentalService.onMount(function(player: Player)
		QuestService.record(player, "park:rental")
	end)

	--[[
		Уголок парка: катание, фото, азбука-дорожка — всё это живёт на клиенте,
		и сообщает о себе клиент. Верим, только если ребёнок стоит у этого места:
		из дальнего угла карты задание не выполнить.
	]]
	RemoteDefs.event("ParkDone").OnServerEvent:Connect(function(player: Player, spotId: any)
		if not RateLimiter.allow(player, "ParkDone", RemoteDefs.RATE_LIMITS.ParkDone) then
			return
		end
		if typeof(spotId) ~= "string" or #spotId > 32 then
			return
		end
		local spot = spotById[spotId]
		local center = spotPosition(spotId)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not spot or not center or not root then
			return
		end
		local flat = (root.Position - center) * Vector3.new(1, 0, 1)
		if flat.Magnitude > spot.radius + PARK_REACH then
			return
		end
		QuestService.record(player, `park:{spotId}`)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			if ProfileService.waitFor(player, 20) then
				QuestService.refresh(player)
				-- Клиенту нужно подняться, а участку — выдаться: иначе у «Построй» нет дороги.
				task.wait(4)
				push(player)
			end
		end)
	end)
end

-- Для панели разработчика и стенда: прислать список заново.
QuestService.push = push
QuestService.spotPosition = spotPosition

return QuestService
