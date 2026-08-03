--!nonstrict
--[[
	Ограничение частоты вызовов Remote'ов. Лимиты объявлены в Shared/Net/RemoteDefs.

	Смысл двойной: защита от спама и защита от лагающего клиента, который решил
	отправить сотню тапов разом. Превышение — это не повод наказывать ребёнка,
	поэтому лишние вызовы просто отбрасываются молча.
]]

local Players = game:GetService("Players")

local RateLimiter = {}

type Bucket = {
	tokens: number,
	lastRefill: number,
}

local buckets: { [Player]: { [string]: Bucket } } = {}

--[[
	Возвращает true, если вызов разрешён.
	perSecond — сколько вызовов в секунду допустимо; допускается всплеск на секунду вперёд.
]]
function RateLimiter.allow(player: Player, key: string, perSecond: number): boolean
	if perSecond <= 0 then
		return false
	end

	local byKey = buckets[player]
	if not byKey then
		byKey = {}
		buckets[player] = byKey
	end

	local now = os.clock()
	local bucket = byKey[key]
	if not bucket then
		bucket = { tokens = perSecond, lastRefill = now }
		byKey[key] = bucket
	end

	local elapsed = now - bucket.lastRefill
	bucket.lastRefill = now
	bucket.tokens = math.min(perSecond, bucket.tokens + elapsed * perSecond)

	if bucket.tokens < 1 then
		return false
	end

	bucket.tokens -= 1
	return true
end

function RateLimiter.forget(player: Player)
	buckets[player] = nil
end

function RateLimiter.start()
	Players.PlayerRemoving:Connect(RateLimiter.forget)
end

return RateLimiter
