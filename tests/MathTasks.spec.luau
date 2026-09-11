--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MathConfig = require(ReplicatedStorage.Shared.Config.Math)

-- Прогон одной ступени на многих сидах: одиночная задача ничего не доказывает,
-- ломается обычно редкое сочетание чисел.
local function forEachTask(stage, count, fn)
	for seed = 1, count do
		fn(MathConfig.generate(stage, Random.new(seed)), seed)
	end
end

local function contains(list, value)
	return table.find(list, value) ~= nil
end

-- Озвучка задачи — цепочка ключей; для сравнения склеиваем её в строку.
local function voOf(task)
	return table.concat(task.vo, " ")
end

return function()
	describe("Math.Ступени", function()
		it(
			"ступени идут подряд с первой по одиннадцатую без пропусков",
			function()
				expect(MathConfig.count()).to.equal(11)
				for stage = 1, 11 do
					expect(MathConfig.expect(stage).stage).to.equal(stage)
				end
			end
		)

		it("умножение и равные группы стоят последними", function()
			-- Доки требуют, чтобы они опирались на состав числа, а не заменяли его
			expect(MathConfig.expect(10).kind).to.equal("group")
			expect(MathConfig.expect(11).kind).to.equal("mul")
		end)

		it(
			"точки под цифрой есть на ранних ступенях и убраны на поздних",
			function()
				-- Сначала количество, потом значок
				expect(MathConfig.expect(1).showPips).to.equal(true)
				expect(MathConfig.expect(2).showPips).to.equal(true)
				expect(MathConfig.expect(5).showPips).to.equal(false)
			end
		)

		it(
			"на первой ступени считаем предметы, а не абстракции",
			function()
				expect(type(MathConfig.expect(1).objects)).to.equal("string")
			end
		)
	end)

	describe("Math.Открытие ступеней", function()
		it("первая ступень открыта всегда", function()
			expect(MathConfig.isUnlocked(1, function()
				return 0
			end)).to.equal(true)
		end)

		it(
			"следующая ступень закрыта, пока предыдущая не изучена",
			function()
				local mastery = { count_group = 1 }
				local of = function(id)
					return mastery[id] or 0
				end
				expect(MathConfig.isUnlocked(2, of)).to.equal(false)
				mastery.count_group = 2
				expect(MathConfig.isUnlocked(2, of)).to.equal(true)
			end
		)

		it("несуществующая ступень не открыта", function()
			expect(MathConfig.isUnlocked(99, function()
				return 3
			end)).to.equal(false)
		end)

		it(
			"портал играет самую высокую ступень из открытых подряд",
			function()
				local mastery = {}
				local function of(stageId)
					return mastery[stageId] or 0
				end

				expect(MathConfig.current(of)).to.equal(1)

				mastery[MathConfig.expect(1).id] = 2
				mastery[MathConfig.expect(2).id] = 2
				expect(MathConfig.current(of)).to.equal(3)

				-- Пропуск в цепочке: всё, что выше дыры, не считается.
				mastery[MathConfig.expect(5).id] = 3
				expect(MathConfig.current(of)).to.equal(3)
			end
		)

		it("всё освоено — последняя ступень, а не дальше", function()
			expect(MathConfig.current(function()
				return 3
			end)).to.equal(MathConfig.count())
		end)
	end)

	describe("Math.Генератор", function()
		it("один сид даёт одну и ту же задачу", function()
			for stage = 1, 11 do
				local first = MathConfig.generate(stage, Random.new(42))
				local second = MathConfig.generate(stage, Random.new(42))
				expect(first.answer).to.equal(second.answer)
				expect(first.prompt).to.equal(second.prompt)
				expect(voOf(first)).to.equal(voOf(second))
				expect(#first.answers).to.equal(#second.answers)
			end
		end)

		it(
			"верный ответ всегда есть среди вариантов и ровно один раз",
			function()
				for stage = 1, 11 do
					forEachTask(stage, 60, function(task, seed)
						local hits = 0
						for _, value in task.answers do
							if value == task.answer then
								hits += 1
							end
						end
						if hits ~= 1 then
							error(
								`ступень {stage}, сид {seed}: верный ответ встречается {hits} раз`
							)
						end
					end)
				end
			end
		)

		it("варианты не повторяются", function()
			for stage = 1, 11 do
				forEachTask(stage, 60, function(task, seed)
					local seen = {}
					for _, value in task.answers do
						if seen[value] then
							error(
								`ступень {stage}, сид {seed}: вариант {value} задублирован`
							)
						end
						seen[value] = true
					end
				end)
			end
		end)

		it("вариантов не меньше двух", function()
			for stage = 1, 11 do
				forEachTask(stage, 40, function(task, seed)
					if #task.answers < 2 then
						error(
							`ступень {stage}, сид {seed}: вариантов всего {#task.answers}`
						)
					end
				end)
			end
		end)

		it(
			"неверные варианты — соседи, а не случайные числа",
			function()
				-- Ошибка ребёнка должна быть осмысленной: просчитался на единицу-другую.
				-- Сравнение исключено: там варианты — это две величины на чашах.
				for stage = 1, 11 do
					if MathConfig.expect(stage).kind ~= "compare" then
						forEachTask(stage, 40, function(task, seed)
							for _, value in task.answers do
								local distance = math.abs(value - task.answer)
								if distance > 3 and MathConfig.expect(stage).kind ~= "mul" then
									error(
										`ступень {stage}, сид {seed}: вариант {value} далеко от {task.answer}`
									)
								end
							end
						end)
					end
				end
			end
		)

		it("число вариантов можно сузить под сложность", function()
			local task = MathConfig.generate(7, Random.new(5), 2)
			expect(#task.answers).to.equal(2)
			expect(contains(task.answers, task.answer)).to.equal(true)
		end)
	end)

	describe("Math.Границы", function()
		it(
			"потолок десять не пробивается ни на одной ступени кроме умножения",
			function()
				for stage = 1, 11 do
					if MathConfig.expect(stage).kind ~= "mul" then
						forEachTask(stage, 80, function(task, seed)
							if task.answer > MathConfig.MAX_NUMBER then
								error(
									`ступень {stage}, сид {seed}: ответ {task.answer} больше десяти`
								)
							end
							for _, value in task.answers do
								if value > MathConfig.MAX_NUMBER or value < 0 then
									error(
										`ступень {stage}, сид {seed}: вариант {value} вне диапазона`
									)
								end
							end
						end)
					end
				end
			end
		)

		it(
			"сложение до пяти действительно не выходит за пять",
			function()
				forEachTask(7, 100, function(task, seed)
					if task.answer > 5 then
						error(`сид {seed}: сумма {task.prompt} = {task.answer} больше пяти`)
					end
				end)
			end
		)

		it("прибавить один всегда прибавляет ровно один", function()
			forEachTask(6, 60, function(task, seed)
				local a = tonumber(string.match(task.prompt, "^(%d+)"))
				expect(task.prompt).to.equal(`{a} + 1`)
				if task.answer ~= a + 1 then
					error(`сид {seed}: {task.prompt} дало {task.answer}`)
				end
			end)
		end)

		it("вычитание никогда не уходит в минус", function()
			forEachTask(8, 100, function(task, seed)
				if task.answer < 0 then
					error(`сид {seed}: {task.prompt} = {task.answer}`)
				end
				for _, value in task.answers do
					if value < 0 then
						error(`сид {seed}: отрицательный вариант {value}`)
					end
				end
			end)
		end)

		it(
			"состав числа сходится: часть плюс ответ равны целому",
			function()
				forEachTask(9, 80, function(task, seed)
					local part, total = string.match(task.prompt, "^(%d+) %+ %? = (%d+)$")
					if part == nil then
						error(`сид {seed}: непонятный пример «{task.prompt}»`)
					end
					if tonumber(part) + task.answer ~= tonumber(total) then
						error(`сид {seed}: {task.prompt}, ответ {task.answer}`)
					end
				end)
			end
		)

		it(
			"равные группы дают ровно произведение групп на содержимое",
			function()
				forEachTask(10, 80, function(task, seed)
					if task.groups == nil or task.each == nil then
						error(
							`сид {seed}: у равных групп не сказано, сколько тарелок`
						)
					end
					if task.groups * task.each ~= task.answer then
						error(`сид {seed}: {task.groups} по {task.each} дало {task.answer}`)
					end
				end)
			end
		)

		--[[
			Единственное место в игре, где ответ выходит за десяток. Правило,
			которое это оправдывает: ребёнок СЧИТАЕТ группы, а не читает
			двузначное число (docs/16-MATH.md § 1, правило 3).
		]]
		it("за десяток выходит только умножение", function()
			for stage = 1, MathConfig.count() do
				local spec = MathConfig.expect(stage)
				local ceiling = if spec.kind == "mul" then MathConfig.MAX_ANSWER else MathConfig.MAX_NUMBER
				forEachTask(stage, 40, function(task, seed)
					if task.answer > ceiling then
						error(
							`ступень {stage}, сид {seed}: ответ {task.answer} выше потолка {ceiling}`
						)
					end
					for _, answer in task.answers do
						if answer > ceiling then
							error(
								`ступень {stage}, сид {seed}: вариант {answer} выше потолка {ceiling}`
							)
						end
					end
				end)
			end
		end)

		it("умножение всегда показывает группы", function()
			for stage = 1, MathConfig.count() do
				local spec = MathConfig.expect(stage)
				if spec.kind == "mul" then
					expect(spec.showPips).to.equal(true)
					expect(spec.objects).to.be.ok()
				end
			end
		end)

		it("умножение не выходит за пять на пять", function()
			forEachTask(11, 100, function(task, seed)
				local a, b = string.match(task.prompt, "^(%d+) × (%d+)$")
				if a == nil then
					error(`сид {seed}: непонятный пример «{task.prompt}»`)
				end
				if tonumber(a) > MathConfig.MAX_FACTOR or tonumber(b) > MathConfig.MAX_FACTOR then
					error(`сид {seed}: {task.prompt} выходит за 5x5`)
				end
				expect(task.answer).to.equal(tonumber(a) * tonumber(b))
			end)
		end)

		it(
			"сравнение спрашивает ровно про те две величины, что лежат на чашах",
			function()
				forEachTask(4, 80, function(task, seed)
					expect(#task.answers).to.equal(2)
					local a, b = task.answers[1], task.answers[2]
					if a == b then
						error(`сид {seed}: обе чаши одинаковы`)
					end
					local expected = if task.vo[1] == "mtask_more" then math.max(a, b) else math.min(a, b)
					if task.answer ~= expected then
						error(`сид {seed}: {voOf(task)} при {a} и {b} дало {task.answer}`)
					end
				end)
			end
		)
	end)

	describe("Math.Озвучка", function()
		it(
			"каждый кусок сгенерированной фразы есть в списке озвучки",
			function()
				local keys = {}
				for _, key in MathConfig.voKeys() do
					keys[key] = true
				end
				for stage = 1, 11 do
					forEachTask(stage, 60, function(task, seed)
						if #task.vo == 0 then
							error(`ступень {stage}, сид {seed}: задача молчит`)
						end
						for _, key in task.vo do
							if not keys[key] then
								error(
									`ступень {stage}, сид {seed}: ключа «{key}» нет в voKeys()`
								)
							end
						end
					end)
				end
			end
		)

		--[[
			Тот самый потолок, ради которого задача произносится по кускам.
			Реплика на каждый пример — это под три сотни записей, и ровно такой объём
			однажды уже сменил концепцию игры (docs/05-AUDIO-VO.md § 1).
		]]
		it(
			"реплик математики — два десятка, а не три сотни",
			function()
				expect(#MathConfig.voKeys() <= 25).to.equal(true)
			end
		)

		it("фраза читается словами: она же идёт в субтитры", function()
			local task = MathConfig.generate(7, Random.new(11))
			local spelled = MathConfig.spell(task)
			expect(string.find(spelled, "Сколько будет")).to.be.ok()
			expect(string.find(spelled, "плюс")).to.be.ok()
		end)

		it("числа озвучены с одного до десяти", function()
			local keys = {}
			for _, key in MathConfig.voKeys() do
				keys[key] = true
			end
			for value = 1, 10 do
				expect(keys[`num_{value}`]).to.equal(true)
			end
		end)
	end)
end
