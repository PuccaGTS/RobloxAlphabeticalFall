--!nonstrict
--[[
	Экономика: ЕДИНСТВЕННАЯ точка начисления и списания Звёздочек.

	Клиент никогда не просит «дай мне N звёздочек» — он сообщает о действии,
	сервер сам решает, что и сколько начислить. См. docs/04-ECONOMY.md § 7.

	Здесь же потолок начислений в час: если он сработал, виноваты мы (баг в балансе
	или дыра в валидации), а не ребёнок — поэтому пишем в лог и режем начисление,
	но ничего у игрока не отбираем и никого не наказываем.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)

local ProfileService = require(script.Parent.ProfileService)

local EconomyService = {}

type Bucket = {
	windowStart: number,
	earned: number,
}

local buckets: { [Player]: Bucket } = {}

-- Разрешённые источники начисления. Строка, которой здесь нет, не может принести звёздочки.
local SOURCES: { [string]: boolean } = {
	correct_answer = true,
	letter_collected = true, -- буква своего отрезка, подобранная на дорожке забега
	challenge_result = true,
	letter_learned = true,
	letter_mastered = true,
	-- Ступень счёта осваивается по тем же правилам, что буква, и стоит столько же:
	-- математика ребёнку не легче алфавита (docs/16-MATH.md § 6).
	math_learned = true,
	math_mastered = true,
	stage_cleared = true,
	letter_of_the_day = true,
	daily_streak = true,
	secret_chest = true,
	coop_help = true,
}

local function bucketFor(player: Player, now: number): Bucket
	local bucket = buckets[player]
	if not bucket or (now - bucket.windowStart) >= 3600 then
		bucket = { windowStart = now, earned = 0 }
		buckets[player] = bucket
	end
	return bucket
end

--[[
	Начисляет звёздочки. Возвращает фактически начисленное количество
	(может быть меньше запрошенного, если сработал часовой потолок).
]]
function EconomyService.award(player: Player, source: string, amount: number, meta: string?): number
	if not SOURCES[source] then
		warn(`[EconomyService] неизвестный источник начисления: {source}`)
		return 0
	end

	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0
	end

	amount = math.floor(amount)

	local now = os.time()
	local bucket = bucketFor(player, now)
	local allowed = math.max(0, Economy.MAX_STARS_PER_HOUR - bucket.earned)
	if allowed <= 0 then
		warn(
			`[EconomyService] потолок начислений для {player.Name}: источник {source}`
		)
		return 0
	end

	local granted = math.min(amount, allowed)
	bucket.earned += granted

	ProfileService.update(player, function(profile)
		profile.stars += granted
	end)

	print(
		string.format(
			"[Economy] +%d ⭐ %s (%s%s)",
			granted,
			player.Name,
			source,
			if meta then ":" .. meta else ""
		)
	)

	return granted
end

--[[
	Списывает звёздочки. Цена приходит НЕ от клиента, а из серверного конфига —
	вызывающий код обязан взять её из Config/Shop.
]]
function EconomyService.spend(player: Player, price: number, reason: string): boolean
	if typeof(price) ~= "number" or price < 0 then
		return false
	end

	local profile = ProfileService.get(player)
	if not profile then
		return false
	end

	if profile.stars < price then
		return false
	end

	ProfileService.update(player, function(p)
		p.stars -= price
	end)

	print(string.format("[Economy] -%d ⭐ %s (%s)", price, player.Name, reason))
	return true
end

function EconomyService.balance(player: Player): number
	local profile = ProfileService.get(player)
	return if profile then profile.stars else 0
end

function EconomyService.forget(player: Player)
	buckets[player] = nil
end

function EconomyService.start()
	game:GetService("Players").PlayerRemoving:Connect(EconomyService.forget)
end

return EconomyService
