--!strict
--[[
	Посуточная история занятий. Нужна отчёту родителя: строка «Занимался 6 дней
	из последних 7» (docs/13-PARENT-MODE.md § 2) не выводится ни из серии подряд,
	ни из суммарного времени — нужна запись по дням.

	Чистая логика без Roblox API — покрыта тестами. Время сюда приносит
	ProfileService: раз в минуту и при выходе он отдаёт секунды, прошедшие
	с прошлого учёта. Поэтому сеанс, перешедший через полночь, ошибается
	не больше чем на минуту — вся порция пишется в тот день, когда её принесли.

	Здесь же ведётся серия дней подряд (dailyStreak): до этого модуля её
	никто не писал, и отчёт честно показывал ноль.
]]

local Types = require(script.Parent.Parent.Types)

local PlayLog = {}

PlayLog.DAY_SEC = 24 * 60 * 60
--[[
	Сутки считаем по Москве. Сервер Roblox живёт по UTC, и без сдвига сеанс
	в половине первого ночи по Москве попал бы во вчерашний день. Аудитория
	русскоязычная; для Владивостока граница суток уезжает на 7 утра, где дети
	ещё спят, — точнее без часового пояса клиента не сделать.
]]
PlayLog.TZ_OFFSET_SEC = 3 * 60 * 60
-- Сколько дней храним. Отчёту хватает недели, запас — на «за месяц» в будущем.
PlayLog.KEEP_DAYS = 28
-- Окно строки отчёта «N дней из последних 7».
PlayLog.REPORT_WINDOW = 7
-- Зашёл и сразу вышел — не занимался. Порог равен одному тику учёта.
PlayLog.MIN_ACTIVE_SEC = 60

-- Номер суток по московскому времени. Сравнивать можно только номера между собой.
function PlayLog.dayOf(t: number): number
	return math.floor((t + PlayLog.TZ_OFFSET_SEC) / PlayLog.DAY_SEC)
end

local function isCount(value: any): boolean
	return typeof(value) == "number" and value == value and value >= 0 and value < math.huge
end

--[[
	Приводит историю в порядок: выкидывает мусорные записи, склеивает дубли
	одного дня и сортирует по дням. Нужна миграции — профиль мог быть испорчен.
]]
function PlayLog.sanitize(raw: any): { Types.PlayDay }
	if typeof(raw) ~= "table" then
		return {}
	end

	local byDay: { [number]: number } = {}
	for _, entry in raw do
		if typeof(entry) == "table" and isCount(entry.sec) and isCount(entry.day) then
			local day = math.floor(entry.day)
			byDay[day] = (byDay[day] or 0) + entry.sec
		end
	end

	local log: { Types.PlayDay } = {}
	for day, sec in byDay do
		table.insert(log, { day = day, sec = sec })
	end
	table.sort(log, function(a, b)
		return a.day < b.day
	end)
	while #log > PlayLog.KEEP_DAYS do
		table.remove(log, 1)
	end
	return log
end

--[[
	Серия на момент now. В профиле лежит серия на день последней игры;
	если с тех пор пропущены сутки, серия уже прервалась, хотя поле этого не знает.
]]
function PlayLog.currentStreak(profile: Types.Profile, now: number): number
	if profile.lastLoginDay < PlayLog.dayOf(now) - 1 then
		return 0
	end
	return profile.dailyStreak
end

-- Сколько дней из последних window (считая сегодня) ребёнок действительно играл.
function PlayLog.activeDays(log: { Types.PlayDay }, now: number, window: number): number
	local today = PlayLog.dayOf(now)
	local count = 0
	for _, entry in log do
		if entry.day > today - window and entry.day <= today and entry.sec >= PlayLog.MIN_ACTIVE_SEC then
			count += 1
		end
	end
	return count
end

--[[
	Записывает порцию игрового времени: в историю дня, в общий счётчик минут
	и в серию дней подряд. Отрицательное и нечисловое время молча игнорирует —
	часы сервера не должны уметь отнимать у ребёнка занятия.
]]
function PlayLog.addPlay(profile: Types.Profile, now: number, seconds: number)
	if not isCount(seconds) or seconds == 0 then
		return
	end

	local today = PlayLog.dayOf(now)
	local log = profile.playLog
	local entry = log[#log]

	if entry ~= nil and entry.day >= today then
		-- Сегодняшняя запись уже есть. Если часы ушли назад, пишем в последнюю:
		-- порядок по дням дороже точности одной минуты.
		entry.sec += seconds
	else
		entry = { day = today, sec = seconds }
		table.insert(log, entry)
	end

	while #log > 0 and log[1].day <= today - PlayLog.KEEP_DAYS do
		table.remove(log, 1)
	end

	profile.stats.totalPlayMin += seconds / 60

	--[[
		Серия. Поле зовётся lastLoginDay по истории, а значит «последний день игры».
		День входит в серию по тому же порогу, что и в счётчик дней отчёта:
		иначе вход на двадцать секунд продлевал бы серию, а днём занятий не считался.
	]]
	local countsToday = entry.day == today and entry.sec >= PlayLog.MIN_ACTIVE_SEC
	if countsToday and profile.lastLoginDay < today then
		profile.dailyStreak = if profile.lastLoginDay == today - 1 then profile.dailyStreak + 1 else 1
		profile.lastLoginDay = today
	end
end

return PlayLog
