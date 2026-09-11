--!strict
--[[
	Отчёт родителю словами: то, что показывает экран родительского режима.
	Раскладка экрана — docs/13-PARENT-MODE.md § 2, карточки «Как заниматься
	дома» — там же, § 5.

	Числа собирает Logic/ParentReport, здесь они становятся строками. Отдельно
	от экрана — чтобы склонения («1 буква», «3 буквы», «11 букв») и формат
	времени проверялись тестом, а не глазами в Studio.

	Родитель — единственный читатель в игре, поэтому здесь полноценный текст.
	Имени и пола ребёнка игра не знает и не спрашивает (docs/13 § 7), так что
	фразы построены без глаголов прошедшего времени: «Дней с занятиями», а не
	«Занимался».
]]

local ParentReport = require(script.Parent.ParentReport)

local ParentReportText = {}

ParentReportText.BAR_WIDTH = 25

local DAY = 24 * 60 * 60

-- Русское склонение по числу: 1 буква, 2 буквы, 5 букв, 11 букв, 21 буква.
function ParentReportText.plural(count: number, one: string, few: string, many: string): string
	local n = math.abs(math.floor(count))
	local lastTwo = n % 100
	local last = n % 10
	if lastTwo >= 11 and lastTwo <= 14 then
		return many
	end
	if last == 1 then
		return one
	end
	if last >= 2 and last <= 4 then
		return few
	end
	return many
end

local function counted(count: number, one: string, few: string, many: string): string
	return `{count} {ParentReportText.plural(count, one, few, many)}`
end

-- «2 ч 40 мин», «14 мин», «меньше минуты».
function ParentReportText.duration(minutes: number): string
	local total = math.floor(minutes)
	if total < 1 then
		return "меньше минуты"
	end
	local hours = total // 60
	local rest = total % 60
	if hours == 0 then
		return `{rest} мин`
	end
	if rest == 0 then
		return `{hours} ч`
	end
	return `{hours} ч {rest} мин`
end

--[[
	Полоска из доки: освоено █, изучено ▓, в работе ▒, остальное ░.
	Три оттенка, а не один: родителю важно видеть не только «сколько», но и
	«насколько прочно» — изученная буква без повторения ещё может забыться.
]]
function ParentReportText.bar(report: ParentReport.Report, width: number?): string
	local cells = width or ParentReportText.BAR_WIDTH
	local total = math.max(report.letters.total, 1)

	local function share(count: number): number
		return math.floor(count / total * cells + 0.5)
	end

	local mastered = share(#report.letters.mastered)
	local learned = math.min(share(#report.letters.learned), cells - mastered)
	local familiar = math.min(share(#report.letters.familiar), cells - mastered - learned)
	local empty = cells - mastered - learned - familiar

	return string.rep("█", mastered)
		.. string.rep("▓", learned)
		.. string.rep("▒", familiar)
		.. string.rep("░", empty)
end

--[[
	Главный экран — «Что ребёнок уже знает». Порядок строк тот же, что в доке:
	сначала итог, потом кто где, потом то, что можно проверить дома, потом время.
]]
function ParentReportText.summary(report: ParentReport.Report): { string }
	local letters = report.letters
	local known = #letters.mastered + #letters.learned
	local lines: { string } = {}

	table.insert(
		lines,
		`Азбука: {known} из {counted(letters.total, "буквы", "букв", "букв")}`
	)
	table.insert(lines, ParentReportText.bar(report))
	table.insert(
		lines,
		`освоено {#letters.mastered}   изучено {#letters.learned}   в работе {#letters.familiar}`
	)

	if #letters.mastered > 0 then
		table.insert(lines, `Освоены: {table.concat(letters.mastered, " ")}`)
	end
	if #letters.learned > 0 then
		table.insert(lines, `Изучены: {table.concat(letters.learned, " ")}`)
	end
	if #letters.familiar > 0 then
		table.insert(lines, `В работе: {table.concat(letters.familiar, " ")}`)
	end
	if letters.touched == 0 then
		table.insert(lines, "Пока ни одной буквы: всё впереди.")
	end

	if #report.hard > 0 then
		local parts: { string } = {}
		for _, hard in report.hard do
			table.insert(
				parts,
				`{hard.glyph} ({counted(hard.wrong, "ошибка", "ошибки", "ошибок")})`
			)
		end
		table.insert(lines, `Даются трудно: {table.concat(parts, ", ")}`)
	end

	local inOrder = report.alphabet.inOrder
	if inOrder > 0 then
		local glyphs: { string } = {}
		for index = 1, math.min(inOrder, #report.details) do
			table.insert(glyphs, report.details[index].glyph)
		end
		local count = counted(inOrder, "буква", "буквы", "букв")
		table.insert(lines, `Знает подряд от А: {count} — {table.concat(glyphs, " ")}`)
	else
		table.insert(lines, "Знает подряд от А: пока ни одной")
	end

	table.insert(
		lines,
		`Ступеней открыто: {report.stages.unlocked} из {report.stages.total}`
	)

	local time = report.time
	local total = ParentReportText.duration(time.totalMin)
	table.insert(
		lines,
		`Дней с занятиями: {time.activeDays} из последних {time.windowDays} · всего {total}`
	)
	if time.sessions > 0 then
		table.insert(lines, `Средний сеанс: {ParentReportText.duration(time.avgSessionMin)}`)
	end
	if report.reviewsDue > 0 then
		local due = counted(report.reviewsDue, "буква", "буквы", "букв")
		table.insert(
			lines,
			`Ждут повторения: {due} — игра предложит их сама`
		)
	end

	return lines
end

function ParentReportText.tips(report: ParentReport.Report): { string }
	local lines: { string } = {}
	for _, tip in report.tips do
		table.insert(lines, tip.text)
	end
	if #lines == 0 then
		table.insert(
			lines,
			"Советы появятся, когда наберётся немного ответов. Пока просто играйте."
		)
	end
	return lines
end

local STATUS = {
	[0] = "не встречалась",
	[1] = "в работе",
	[2] = "изучена",
	[3] = "освоена",
}

local function whenNext(nextReview: number, now: number): string
	local days = math.ceil((nextReview - now) / DAY)
	if days <= 0 then
		return "повторить сегодня"
	end
	return `повтор через {counted(days, "день", "дня", "дней")}`
end

-- Вкладка «Подробно»: строка на букву — статус, ответы, доля верных, когда повтор.
function ParentReportText.details(report: ParentReport.Report, now: number): { string }
	local lines: { string } = {}
	for _, detail in report.details do
		local answers = detail.correct + detail.wrong
		local percent = math.floor(detail.accuracy * 100 + 0.5)
		local status = STATUS[detail.mastery] or "?"
		local count = counted(answers, "ответ", "ответа", "ответов")
		local next_ = whenNext(detail.nextReview, now)
		table.insert(lines, `{detail.glyph} — {status} · {count} · {percent}% верных · {next_}`)
	end
	if #lines == 0 then
		table.insert(
			lines,
			"Здесь появится таблица по буквам, как только ребёнок встретит первую."
		)
	end
	return lines
end

--[[
	«Как заниматься дома» — docs/13-PARENT-MODE.md § 5. Это то, что делает
	продукт ценным для родителя: игра заканчивается, а азбука — нет.
	Первая карточка честно говорит, чему игра НЕ учит: слогам и чтению.
]]
ParentReportText.HOME = {
	"Игра учит алфавиту, а не чтению. Ребёнок научится узнавать и называть буквы и знать их порядок. "
		.. "Слияние букв в слоги — следующий шаг, и его игра не делает.",
	"Спрашивайте по порядку. «Назови буквы от А» — самая полезная домашняя проверка, "
		.. "и отчёт показывает, сколько букв ребёнок уже знает подряд.",
	"Ищите знакомые буквы вокруг — на вывеске, обложке, пачке молока. "
		.. "«Смотри, тут буква Ж, как у тебя в игре».",
	"10–20 минут в день лучше, чем час в выходной. Память работает на повторениях.",
	"Хвалите за попытку, а не за результат.",
	"Не заставляйте. Если ребёнок не хочет — сегодня не занимаемся, это нормально.",
}

-- Держится на виду: снимает вопрос до того, как он возник (docs/13 § 4).
ParentReportText.MICROPHONE =
	"Микрофон в игре не используется — ни для записи, ни для распознавания."

return ParentReportText
