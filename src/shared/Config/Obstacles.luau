--!strict
--[[
	Каталог элементов полосы препятствий. См. docs/19-OBSTACLES.md.

	Здесь лежат только те элементы, которые сервер умеет строить прямо сейчас.
	Полный список задуманного (вращающийся цилиндр, поршни, карусель) живёт
	в документе, а не в конфиге: данные без реализации — это обещание игре,
	которое она не может выполнить.

	Общее правило для всех элементов: препятствие можно пройти медленно.
	Нет ни одного, которое требует точного тайминга — пятилетний ребёнок
	не должен зависеть от реакции, чтобы дойти до буквы.
]]

local Types = require(script.Parent.Parent.Types)

local Obstacles: { [string]: Types.Obstacle } = {
	--[[
		Барьер. Перепрыгнуть или обойти по соседней дорожке — выбор есть всегда.
		Самый первый элемент, который встречает новичок: он безопасен целиком.
	]]
	barrier = {
		id = "barrier",
		kind = "barrier",
		title = "Барьер",
		tier = 1,
		lanes = 1,
		blocking = false,
		moving = false,
	},

	-- Яма поперёк одной дорожки. Упал — вернулся к последней сохранке.
	gap = {
		id = "gap",
		kind = "gap",
		title = "Яма",
		tier = 1,
		lanes = 1,
		blocking = false,
		moving = false,
	},

	--[[
		Низкий свод. Перепрыгнуть его нельзя — только обойти, и в этом весь смысл:
		элемент учит смотреть вперёд и заранее менять дорожку, а это ровно тот навык,
		который потом нужен на воротах.
	]]
	arch = {
		id = "arch",
		kind = "arch",
		title = "Низкий свод",
		tier = 1,
		lanes = 1,
		blocking = true,
		moving = false,
	},

	-- Узкая балка: пола нет нигде, кроме средней дорожки.
	beam = {
		id = "beam",
		kind = "beam",
		title = "Балка",
		tier = 1,
		lanes = 3,
		blocking = false,
		moving = false,
	},

	-- Ступени во всю ширину: подъём прыжками и спуск. Падать здесь некуда.
	steps = {
		id = "steps",
		kind = "steps",
		title = "Ступени",
		tier = 1,
		lanes = 3,
		blocking = false,
		moving = false,
	},

	--[[
		Средний ряд (tier 2). Появляется, когда ребёнок уже уверенно проходит базовые.

		Все пятеро подчиняются тому же правилу, что и базовые: ничто не движется
		быстрее ребёнка, ничто не требует точного тайминга и ничто не занимает
		все три дорожки. Соседняя дорожка свободна всегда — можно просто обойти
		и не связываться. См. docs/19-OBSTACLES.md § 3.2.
	]]

	--[[
		Маятник: мягкий шар качается поперёк одной дорожки.
		Он не сбивает и не отнимает — он мешает пройти, пока не отойдёт.
		Ждать не обязательно: соседние дорожки свободны.
	]]
	pendulum = {
		id = "pendulum",
		kind = "pendulum",
		title = "Маятник",
		tier = 2,
		lanes = 1,
		blocking = false,
		moving = true,
	},

	--[[
		Движущаяся платформа над ямой в одну дорожку: подождал, встал, проехал.
		Спешка не нужна — платформа возвращается сама, ждать её можно сколько угодно.
	]]
	platform = {
		id = "platform",
		kind = "platform",
		title = "Движущаяся платформа",
		tier = 2,
		lanes = 1,
		blocking = false,
		moving = true,
	},

	--[[
		Исчезающие плиты: три плиты над ямой гаснут и возвращаются по очереди,
		и каждая стоит на месте несколько секунд. Это не проверка реакции,
		а «посмотри и шагни».
	]]
	fading = {
		id = "fading",
		kind = "fading",
		title = "Исчезающие плиты",
		tier = 2,
		lanes = 1,
		blocking = false,
		moving = true,
	},

	-- Батут: подбрасывает вверх. Ничего не отнимает и ничем не грозит, просто весело.
	trampoline = {
		id = "trampoline",
		kind = "trampoline",
		title = "Батут",
		tier = 2,
		lanes = 1,
		blocking = false,
		moving = false,
	},

	--[[
		Скользкий лёд во всю ширину: разгоняет и заносит, но падать с него некуда —
		под ним обычный пол. Единственный элемент среднего ряда, который стоит
		на всех дорожках, и он же самый безобидный.
	]]
	ice = {
		id = "ice",
		kind = "ice",
		title = "Скользкий лёд",
		tier = 2,
		lanes = 3,
		blocking = false,
		moving = false,
	},
}

local Module = {}

Module.all = Obstacles

function Module.get(id: string): Types.Obstacle?
	return Obstacles[id]
end

function Module.expect(id: string): Types.Obstacle
	local obstacle = Obstacles[id]
	assert(obstacle, `Obstacles: неизвестный элемент "{id}"`)
	return obstacle
end

function Module.ids(): { string }
	local ids: { string } = {}
	for id in Obstacles do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Живёт ли элемент сам: качается, ездит, гаснет.
function Module.isMoving(id: string): boolean
	local obstacle = Obstacles[id]
	return obstacle ~= nil and obstacle.moving
end

-- Элементы не выше указанного уровня: на первой ступени алфавита — только базовые.
function Module.upToTier(tier: number): { string }
	local ids: { string } = {}
	for _, id in Module.ids() do
		if Obstacles[id].tier <= tier then
			table.insert(ids, id)
		end
	end
	return ids
end

return Module
