--!nocheck
--[[
	Инварианты контента. Эти тесты — единственная защита от ошибок в конфигах,
	которые иначе всплывут уже на ребёнке: пропущенная буква алфавита, ступень
	из чужих букв, буква без озвучки.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Letters = require(Shared.Config.Letters)
local Stages = require(Shared.Config.Stages)
local Obstacles = require(Shared.Config.Obstacles)
local Tunnel = require(Shared.Config.Tunnel)
local Challenges = require(Shared.Config.Challenges)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local MathConfig = require(Shared.Config.Math)

local ALPHABET = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"

return function()
	describe("Config: буквы", function()
		it("id совпадает с ключом таблицы", function()
			for id, letter in Letters.all do
				expect(letter.id).to.equal(id)
			end
		end)

		it("в справочнике весь алфавит и ровно один раз", function()
			expect(Letters.count()).to.equal(33)

			local built = ""
			for _, id in Letters.ordered() do
				built ..= Letters.expect(id).glyph
			end
			expect(built).to.equal(ALPHABET)
		end)

		it("порядок сплошной: от 1 до 33 без дыр", function()
			local seen = {}
			for _, id in Letters.ordered() do
				local order = Letters.expect(id).order
				expect(seen[order]).to.equal(nil)
				seen[order] = id
			end
			for order = 1, 33 do
				expect(seen[order]).to.be.ok()
			end
		end)

		it("у каждой буквы есть название и слово-пример", function()
			for _, id in Letters.ordered() do
				local letter = Letters.expect(id)
				expect(letter.vo.name).to.be.a("string")
				expect(#letter.vo.name > 0).to.equal(true)
				expect(#letter.example > 0).to.equal(true)
				-- Картинка к слову есть у каждой буквы, и слово содержит саму букву.
				expect(#letter.picture > 0).to.equal(true)
				expect(string.find(letter.example, letter.glyph, 1, true) ~= nil).to.equal(true)
			end
		end)

		it("буквы-путаницы существуют в алфавите", function()
			for _, id in Letters.ordered() do
				for _, other in Letters.expect(id).confusableWith do
					expect(Letters.get(other)).to.be.ok()
					expect(other).never.to.equal(id)
				end
			end
		end)

		it(
			"следующая буква — соседняя по алфавиту, у Я её нет",
			function()
				local ordered = Letters.ordered()
				for index = 1, #ordered - 1 do
					local next_ = Letters.after(ordered[index])
					expect(next_).to.be.ok()
					expect(next_.id).to.equal(ordered[index + 1])
				end
				expect(Letters.after(ordered[#ordered])).to.equal(nil)
				expect(Letters.before(ordered[1])).to.equal(nil)
			end
		)
	end)

	describe("Config: ступени", function()
		it("одиннадцать ступеней по три буквы", function()
			expect(Stages.count()).to.equal(11)
			for _, stage in Stages.all do
				expect(#stage.letters).to.equal(3)
			end
		end)

		--[[
			Главное свойство разбиения: буквы открытых ступеней — это всегда начало
			алфавита без пропусков. На нём стоит «Алфавитная лестница»: спросить
			«какая следующая» можно только там, где следующая уже открыта.
		]]
		it("ступени идут подряд и покрывают весь алфавит", function()
			local expectedOrder = 1
			for index = 1, Stages.count() do
				for _, id in Stages.expect(index).letters do
					expect(Letters.expect(id).order).to.equal(expectedOrder)
					expectedOrder += 1
				end
			end
			expect(expectedOrder - 1).to.equal(Letters.count())
		end)

		it("подпись ступени совпадает с её буквами", function()
			for _, stage in Stages.all do
				local glyphs = {}
				for _, id in stage.letters do
					table.insert(glyphs, Letters.expect(id).glyph)
				end
				expect(stage.glyphs).to.equal(table.concat(glyphs, " "))
			end
		end)

		it("первая ступень открыта всегда", function()
			expect(Stages.isUnlocked(1, function()
				return 0
			end)).to.equal(true)
		end)

		it(
			"следующая ступень требует 80% изученных букв предыдущей",
			function()
				local first = Stages.expect(1).letters
				local learned = {}

				local function masteryOf(id)
					return if learned[id] then 2 else 0
				end

				expect(Stages.isUnlocked(2, masteryOf)).to.equal(false)

				for _, id in first do
					learned[id] = true
				end
				expect(Stages.isUnlocked(2, masteryOf)).to.equal(true)
			end
		)

		it("ссылается только на существующие испытания", function()
			for _, stage in Stages.all do
				expect(#stage.challenges > 0).to.equal(true)
				for _, challengeId in stage.challenges do
					expect(Challenges.get(challengeId)).to.be.ok()
				end
			end
		end)
	end)

	describe("Config: препятствия", function()
		it(
			"каталог не пустой и все элементы базовые построены",
			function()
				expect(#Obstacles.ids() > 0).to.equal(true)
				expect(#Obstacles.upToTier(1) > 0).to.equal(true)
			end
		)

		it(
			"элемент занимает не больше дорожек, чем их есть",
			function()
				for _, id in Obstacles.ids() do
					local obstacle = Obstacles.expect(id)
					expect(obstacle.lanes >= 1).to.equal(true)
					expect(obstacle.lanes <= 3).to.equal(true)
				end
			end
		)

		--[[
			Перекрывать все три дорожки нельзя ничем: элемент, который нельзя обойти
			и нельзя перепрыгнуть, останавливает ребёнка насовсем.
		]]
		it("ни один элемент не перекрывает путь целиком", function()
			for _, id in Obstacles.ids() do
				local obstacle = Obstacles.expect(id)
				if obstacle.blocking then
					expect(obstacle.lanes < 3).to.equal(true)
				end
			end
		end)

		it("средний ряд заведён и он не первый попавшийся", function()
			local tier2 = 0
			for _, id in Obstacles.upToTier(2) do
				if Obstacles.expect(id).tier == 2 then
					tier2 += 1
				end
			end
			expect(tier2).to.equal(6)
		end)

		it("сложный ряд заведён", function()
			local tier3 = 0
			for _, id in Obstacles.ids() do
				if Obstacles.expect(id).tier == 3 then
					tier3 += 1
				end
			end
			expect(tier3 >= 3).to.equal(true)
		end)

		--[[
			Карусель, подъёмник и спираль (docs/19-OBSTACLES.md § 3.2.1) долго
			лежали в доке как задуманные. Данные без строителя — обещание,
			которого игра не выполняет, поэтому тест держит обе половины:
			элемент есть в каталоге, и у него есть длина, по которой его ставят.
		]]
		--[[
			Первые уровни состоят из базовых элементов, а их на отрезке шесть-девять.
			Пяти видов было мало — отрезок читался как «опять барьер».
		]]
		it(
			"базовых видов не меньше семи: горка и слалом заведены",
			function()
				expect(#Obstacles.upToTier(1) >= 7).to.equal(true)
				for _, id in { "hump", "cones" } do
					local obstacle = Obstacles.expect(id)
					expect(obstacle.tier).to.equal(1)
					expect(obstacle.moving).to.equal(false)
					expect(Tunnel.obstacleLength(obstacle.kind)).to.be.ok()
				end
			end
		)

		it("карусель, подъёмник и спираль построены", function()
			for _, id in { "carousel", "lift", "spiral" } do
				local obstacle = Obstacles.expect(id)
				expect(obstacle.tier).to.equal(3)
				expect(Tunnel.obstacleLength(obstacle.kind)).to.be.ok()
			end
		end)

		--[[
			Живой элемент (качается, ездит, гаснет) обязан занимать одну дорожку:
			две соседние остаются свободными, и ребёнок вправе просто обойти его
			и не связываться. Иначе движение становится обязательным экзаменом
			на реакцию — ровно тем, чего игра не делает.
		]]
		it("живой элемент всегда можно обойти", function()
			for _, id in Obstacles.ids() do
				local obstacle = Obstacles.expect(id)
				if obstacle.moving then
					expect(obstacle.lanes).to.equal(1)
					expect(obstacle.blocking).to.equal(false)
					expect(obstacle.tier >= 2).to.equal(true)
				end
			end
		end)

		--[[
			Длина элемента вдоль бега не больше шага полосы: иначе соседние элементы
			налезают друг на друга и отрезок превращается в кашу.
		]]
		it("каждый элемент влезает в свою клетку", function()
			for _, id in Obstacles.ids() do
				local kind = Obstacles.expect(id).kind
				local length = Tunnel.obstacleLength(kind)
				if length == nil then
					error(`у элемента {id} не записана длина`)
				end
				-- Назад элемент заходит не дальше отступа, вперёд — не дальше конца клетки.
				expect(Tunnel.obstacleLead(kind) <= Tunnel.OBSTACLE_LEAD).to.equal(true)
				expect(Tunnel.OBSTACLE_LEAD + length <= Tunnel.OBSTACLE_PITCH).to.equal(true)
			end
		end)

		it(
			"поршень выезжает медленнее, чем ребёнок идёт, и только в крайнюю дорожку",
			function()
				local travel = Tunnel.WIDTH / 2
					+ (Tunnel.LANE_WIDTH - 1) / 2
					- Tunnel.laneOffset(Tunnel.LANE_COUNT)
				expect(travel / Tunnel.PISTON_SECONDS < Tunnel.WALK_SPEED / 4).to.equal(true)
				expect(Obstacles.expect("pistons").edge).to.equal(true)
			end
		)

		it(
			"в гребёнке щель в каждой дорожке, и в неё проходит ребёнок",
			function()
				expect(Tunnel.COMB_SLOT >= 3.5).to.equal(true)
				expect(Tunnel.COMB_SLOT < Tunnel.LANE_WIDTH).to.equal(true)
			end
		)

		--[[
			Исчезающие плиты не должны гаснуть две подряд: иначе дорожка на время
			превращается в сплошную яму, и элемент начинает требовать точного шага.
			Сдвиг фаз — треть цикла, значит «нет» обязано быть короче этой трети.
		]]
		it("две плиты подряд не гаснут никогда", function()
			local cycle = Tunnel.FADE_SOLID_SECONDS + Tunnel.FADE_GONE_SECONDS
			expect(Tunnel.FADE_GONE_SECONDS < cycle / Tunnel.FADE_TILE_COUNT).to.equal(true)
			-- Плита держится не меньше окна на решение: три секунды, см. 14-TUNNEL-MODE § 6.
			expect(Tunnel.FADE_SOLID_SECONDS >= 3).to.equal(true)
		end)

		--[[
			Ничто не движется быстрее ребёнка: шар маятника и платформа проходят
			свой путь медленнее, чем ребёнок идёт пешком.
		]]
		it("живое движется медленнее, чем ребёнок бежит", function()
			local ball = (Tunnel.PENDULUM_ROPE + Tunnel.PENDULUM_BALL / 2)
				* math.sin(Tunnel.PENDULUM_SWING)
				* 2
			expect(ball / Tunnel.PENDULUM_SECONDS < Tunnel.WALK_SPEED).to.equal(true)
			expect(Tunnel.PLATFORM_TRAVEL / Tunnel.PLATFORM_SECONDS < Tunnel.WALK_SPEED).to.equal(true)

			-- И шар не залезает в соседние дорожки: обойти его можно всегда.
			local arm = Tunnel.PENDULUM_ROPE + Tunnel.PENDULUM_BALL / 2
			local reach = arm * math.sin(Tunnel.PENDULUM_SWING) + Tunnel.PENDULUM_BALL / 2
			expect(reach <= Tunnel.LANE_WIDTH / 2).to.equal(true)

			--[[
				В крайней точке дуги рядом с шаром остаётся широкий проход:
				ребёнок проходит его же дорожкой, не подгадывая момент.
			]]
			local free = Tunnel.LANE_WIDTH / 2
				+ arm * math.sin(Tunnel.PENDULUM_SWING)
				- Tunnel.PENDULUM_BALL / 2
			expect(free >= 4).to.equal(true)
		end)
	end)

	describe("Config: испытания", function()
		it(
			"у каждого параметра ровно пять значений сложности",
			function()
				for _, id in Challenges.ids() do
					local meta = Challenges.expect(id)
					for name, values in meta.params do
						expect(#values).to.equal(5)
						if #values ~= 5 then
							warn(`{id}.{name}: ожидалось 5 значений`)
						end
					end
				end
			end
		)

		it("испытания больше не учат звукам и слогам", function()
			local forbidden = { sound_to_letter = true, letter_to_sound = true, blend = true, word = true }
			for _, id in Challenges.ids() do
				for _, trains in Challenges.expect(id).trains do
					expect(forbidden[trains]).to.equal(nil)
				end
			end
		end)
	end)

	describe("Config: озвучка", function()
		it(
			"все реплики, которые просит игра, объявлены в реестре",
			function()
				local missing = AudioRegistry.unregistered()
				if #missing > 0 then
					warn("нет в реестре: " .. table.concat(missing, ", "))
				end
				expect(#missing).to.equal(0)
			end
		)

		it("в реестре есть название каждой буквы", function()
			local required = AudioRegistry.requiredKeys()
			for _, id in Letters.ordered() do
				expect(table.find(required, Letters.expect(id).vo.name)).to.be.ok()
			end
		end)

		--[[
			Потолок объёма записи. Он тут не ради красоты: концепция сменилась именно
			потому, что 600 реплик со звуками записать не вышло. Если список снова
			начнёт разрастаться, тест обязан об этом сказать.

			Математика влезла в этот же потолок и не подвинула его: задача собирается
			из кусков («Сколько будет» + «два» + «плюс» + «два»), а не пишется
			на каждый пример.
		]]
		it("реплик остаётся немного: не больше сотни", function()
			expect(#AudioRegistry.requiredKeys() <= 100).to.equal(true)
		end)

		it("в реестре есть все реплики математики", function()
			local required = AudioRegistry.requiredKeys()
			for _, key in MathConfig.voKeys() do
				if table.find(required, key) == nil then
					error(`ключа «{key}» нет в реестре озвучки`)
				end
			end
		end)
	end)

	describe("Config: математика", function()
		--[[
			Проёмов в воротах не больше, чем дорожек в туннеле. Ступень, попросившая
			четыре варианта, построила бы ворота, в которые нельзя войти: четвёртый
			проём просто некуда поставить.
		]]
		it("вариантов ступени не больше, чем дорожек", function()
			for stage = 1, MathConfig.count() do
				local spec = MathConfig.expect(stage)
				expect(spec.choices >= 2).to.equal(true)
				expect(spec.choices <= Tunnel.LANE_COUNT).to.equal(true)
			end
		end)

		it(
			"у ворот с числами есть параметры на все пять сложностей",
			function()
				expect(Challenges.get("math_gates")).to.be.ok()
				for name, values in Tunnel.MATH_PARAMS do
					if #values ~= 5 then
						error(`MATH_PARAMS.{name}: ожидалось 5 значений, а не {#values}`)
					end
				end
			end
		)

		--[[
			Ворот в забеге столько же или меньше, чем задач, которые ступень способна
			выдать разными: иначе половина ворот повторяет одно и то же, и ребёнок
			перестаёт считать уже на третьих.

			Проверяем самое узкое место — первую ступень: там всего три числа.
		]]
		it(
			"задач ступени хватает, чтобы ворота не повторялись подряд",
			function()
				local first = MathConfig.expect(1)
				expect(first.max - first.min + 1 >= first.choices).to.equal(true)
			end
		)
	end)
end
