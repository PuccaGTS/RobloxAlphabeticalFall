--!strict
--[[
	Вход в родительский режим: PIN, его хеш, пауза после неудачных попыток
	и «взрослый» вопрос перед экраном PIN. См. docs/13-PARENT-MODE.md § 1 и § 8.

	Чистая логика без Roblox API — покрыта тестами. Проверку PIN делает сервер,
	клиент только собирает цифры: хеш и счётчик попыток на клиент не уходят никогда.

	О хеше честно. Четыре цифры — это десять тысяч вариантов, и перебрать их
	можно за миг любым хешем, хоть самым стойким. Хеш здесь нужен не против
	того, у кого есть доступ к DataStore, а чтобы PIN не лежал в профиле открытым
	текстом: его не должно быть видно ни в логе, ни в выгрузке, ни в отладчике.
	Настоящая защита — пауза после пяти неверных попыток, и она на сервере.

	Поэтому хеш простой — FNV-1a, прогнанный по кругу, с солью из UserId, —
	и с меткой версии впереди: захотим сменить алгоритм, старые записи
	отличатся по метке, и родителю не придётся ничего сбрасывать.
]]

local ParentGate = {}

ParentGate.PIN_LENGTH = 4
ParentGate.MAX_ATTEMPTS = 5
ParentGate.LOCK_SECONDS = 60
-- Сколько живёт вход: родитель листает отчёт, а не держит игру открытой часами.
ParentGate.SESSION_SECONDS = 15 * 60
ParentGate.HASH_PREFIX = "fnv1a-1000:"
ParentGate.HASH_ROUNDS = 1000

local FNV_OFFSET = 2166136261
local TWO_32 = 4294967296

--[[
	Умножение на простое FNV (16777619 = 2^24 + 403) по частям: целиком
	произведение вылезает за 2^53, и число с плавающей точкой теряет младшие
	биты. По частям обе половины точны, а сумма берётся по модулю 2^32.
]]
local function fnvMultiply(hash: number): number
	return (bit32.lshift(hash, 24) + hash * 403) % TWO_32
end

local function fnv1a(text: string, seed: number): number
	local hash = seed
	for index = 1, #text do
		hash = fnvMultiply(bit32.bxor(hash, string.byte(text, index)))
	end
	return hash
end

function ParentGate.isValidPin(pin: any): boolean
	return typeof(pin) == "string" and #pin == ParentGate.PIN_LENGTH and string.match(pin, "^%d+$") ~= nil
end

function ParentGate.hash(pin: string, salt: string): string
	local material = `{salt}:{pin}`
	local hash = FNV_OFFSET
	for _ = 1, ParentGate.HASH_ROUNDS do
		hash = fnv1a(material, hash)
	end
	return ParentGate.HASH_PREFIX .. string.format("%08x", hash)
end

function ParentGate.matches(pin: any, salt: string, stored: any): boolean
	if not ParentGate.isValidPin(pin) or typeof(stored) ~= "string" then
		return false
	end
	return ParentGate.hash(pin, salt) == stored
end

-- ===== Пауза после неверных попыток ==============================================

export type Guard = {
	failures: number,
	lockedUntil: number,
}

function ParentGate.newGuard(): Guard
	return { failures = 0, lockedUntil = 0 }
end

-- Сколько секунд ещё ждать. Ноль — можно пробовать.
function ParentGate.lockedFor(guard: Guard, now: number): number
	return math.max(0, math.ceil(guard.lockedUntil - now))
end

--[[
	Неверная попытка. Пятая подряд включает паузу на минуту, и счёт начинается
	заново: после паузы снова пять попыток, а не одна. Возвращает, сколько
	попыток осталось до паузы.
]]
function ParentGate.registerFailure(guard: Guard, now: number): number
	guard.failures += 1
	if guard.failures >= ParentGate.MAX_ATTEMPTS then
		guard.failures = 0
		guard.lockedUntil = now + ParentGate.LOCK_SECONDS
		return 0
	end
	return ParentGate.MAX_ATTEMPTS - guard.failures
end

function ParentGate.registerSuccess(guard: Guard)
	guard.failures = 0
	guard.lockedUntil = 0
end

-- ===== «Взрослый» вопрос =========================================================

export type Question = {
	text: string,
	answer: number,
}

--[[
	Вопрос, на который пятилетний не ответит, а взрослый ответит сразу:
	таблица умножения на числах от шести до девяти. Произведение всегда
	двузначное, и угадать его перебором кнопок ребёнку не выйдет.

	Это не защита, а барьер от случайного входа: настоящая защита — PIN.
]]
function ParentGate.adultQuestion(random: Random): Question
	local a = random:NextInteger(6, 9)
	local b = random:NextInteger(6, 9)
	return { text = `Сколько будет {a} × {b}?`, answer = a * b }
end

function ParentGate.checkAnswer(question: Question, typed: any): boolean
	if typeof(typed) ~= "string" then
		return false
	end
	local trimmed = string.match(typed, "^%s*(%d+)%s*$")
	return trimmed ~= nil and tonumber(trimmed) == question.answer
end

return ParentGate
