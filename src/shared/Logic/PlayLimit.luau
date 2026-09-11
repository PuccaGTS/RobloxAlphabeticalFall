--!strict
--[[
	Лимит времени в день и напоминание об отдыхе. См. docs/13-PARENT-MODE.md § 3.

	  · Лимит: выключен или 15 / 20 / 30 / 45 минут. Завершение мягкое: начатый
	    забег доигрывается до финиша, новые занятия не начинаются, голос прощается
	    до завтра. Из игры никого не выкидывает — выкинутый ребёнок плачет,
	    а попрощавшийся идёт ужинать.
	  · Отдых: раз в двадцать минут голос предлагает передохнуть. Ничего
	    не блокирует — это совет, а не запрет.

	Чистая логика без Roblox API — покрыта тестами. Задаёт настройки только
	родитель, после входа по PIN (Services/ParentService).
]]

local PlayLimit = {}

PlayLimit.OPTIONS = { 15, 20, 30, 45 }
PlayLimit.REST_EVERY_SEC = 20 * 60

--[[
	Лимит из профиля: одно из разрешённых значений или nil (выключен).
	Любое другое число — мусор или подделка, и считается выключенным лимитом,
	а не «ближайшим разрешённым»: угадывать за родителя нельзя.
]]
function PlayLimit.sanitizeLimit(value: any): number?
	if typeof(value) ~= "number" then
		return nil
	end
	for _, option in PlayLimit.OPTIONS do
		if value == option then
			return option
		end
	end
	return nil
end

function PlayLimit.isOver(limitMin: number?, secondsToday: number): boolean
	local limit = PlayLimit.sanitizeLimit(limitMin)
	return limit ~= nil and secondsToday >= limit * 60
end

-- Сколько минут осталось на сегодня; nil — лимита нет.
function PlayLimit.minutesLeft(limitMin: number?, secondsToday: number): number?
	local limit = PlayLimit.sanitizeLimit(limitMin)
	if limit == nil then
		return nil
	end
	return math.max(0, math.ceil(limit - secondsToday / 60))
end

--[[
	Пора ли напомнить об отдыхе: с начала сеанса или с прошлого напоминания
	прошло двадцать минут. sessionSec — сколько идёт этот заход,
	lastRestSec — на какой его секунде звучало прошлое напоминание (0 — не звучало).
]]
function PlayLimit.restDue(enabled: boolean, sessionSec: number, lastRestSec: number): boolean
	return enabled and sessionSec - lastRestSec >= PlayLimit.REST_EVERY_SEC
end

--[[
	Настройки родителя в профиле, приведённые в порядок. Напоминание об отдыхе
	включено, пока родитель его явно не выключил: так в доке, и так безопаснее.
]]
function PlayLimit.sanitizeParent(
	raw: any
): { pinHash: string?, dailyLimitMin: number?, restReminder: boolean }
	local parent = if typeof(raw) == "table" then raw else {}
	return {
		pinHash = if typeof(parent.pinHash) == "string" then parent.pinHash else nil,
		dailyLimitMin = PlayLimit.sanitizeLimit(parent.dailyLimitMin),
		restReminder = parent.restReminder ~= false,
	}
end

return PlayLimit
