--[[
	Вставляет отобранные модели декора в Studio — одним запуском.

	КАК ПОЛЬЗОВАТЬСЯ
	  1. ОДИН РАЗ: открыть ссылки из docs/21-DECOR.md § 7.1 и нажать на каждой
	     зелёную кнопку Get. Модели бесплатные; Studio не даёт вставлять то,
	     чего нет в инвентаре, и без этого шага скрипт напишет
	     «User is not authorized to access Asset».
	  2. Открыть Studio (любое место, лучше с подключённым Rojo).
	  3. View → Command Bar.
	  4. Скопировать сюда всё содержимое этого файла, нажать Enter.
	  5. В Workspace появится папка DecorToSave с моделями.
	  6. Каждую модель: правая кнопка → Save to File… → сохранить в
	     assets/models/decor/<имя модели>.rbxm — имя уже проставлено верное.
	  7. rojo serve → Play. Эскизы заменятся на модели.

	ЕСЛИ ПИШЕТ «User is not authorized to access Asset»
	  Значит, Studio отказалась брать модель, которой нет у вас в инвентаре.
	  Лечится один раз: открыть ссылки из docs/21-DECOR.md § 7.1 и нажать на каждой
	  зелёную кнопку Get (модели бесплатные, это не покупка). После этого запустить
	  скрипт снова — или взять их из Toolbox → вкладка Inventory.

	  Скрипт сначала пробует game:GetObjects — он умеет брать публичные модели
	  и без инвентаря, — и только потом InsertService. Какой из путей сработает,
	  зависит от версии Studio, поэтому пробуем оба.

	ПОЧЕМУ ЭТО НЕ ДЕЛАЕТСЯ САМО. Скачать модель Creator Store можно только
	из-под аккаунта: раздача ассетов требует авторизации, а сохранение в файл
	умеет только Studio. Поэтому выбор моделей, чистку и подгонку размера
	берёт на себя этот скрипт, а на человеке остаются два клика на модель.

	ЧТО ЗА МОДЕЛИ. Все — бесплатные, из Creator Store, отобраны по четырём
	признакам: без скриптов внутри (это видно в данных Store ещё до вставки),
	мало полигонов, не меньше 75% положительных оценок и стиль, который
	не спорит с остальным миром. Скрипты всё равно вырезаются ниже — доверять
	метаданным на слово в детской игре не стоит.
]]

local InsertService = game:GetService("InsertService")
local Selection = game:GetService("Selection")

--[[
	Отобранные модели. Ссылка на любую: create.roblox.com/store/asset/<assetId>

	Столбец «tri» — число треугольников по данным Store: по нему видно цену
	модели для дешёвого планшета, ради которого вся эта осторожность.
]]
local PICKS = {
	{
		id = "tree_pine",
		assetId = 5616880673,
		title = "Low poly pine tree",
		author = "smartycar23",
		tri = 384,
	},
	{
		id = "tree_round",
		assetId = 13870570014,
		title = "Low Poly Tree - Cartoon",
		author = "lukabricks",
		tri = 3240,
	},
	{
		id = "bush_round",
		assetId = 14720410685,
		title = "Low poly big bush",
		author = "Tanakob12345",
		tri = 296,
	},
	{
		id = "flower_bed",
		assetId = 1353190583,
		title = "Low Poly Flower Bush",
		author = "Catmen126",
		tri = 4676,
	},
	{ id = "rock_small", assetId = 2557020130, title = "Low Poly Rock", author = "FWS_Sinister", tri = 80 },
	{ id = "bench", assetId = 7499829922, title = "Bench Wooden", author = "TacoMcRocco", tri = 156 },
	{ id = "lamp", assetId = 565846542, title = "Street Lamp", author = "Dimmy_Turner", tri = 2032 },
	{
		id = "fountain",
		assetId = 5477511653,
		title = "Fancy fountain with benches",
		author = "jsvxsophie165",
		tri = 7974,
	},
}

--[[
	Габариты, под которые посчитана расстановка на площади.

	Список повторяет Config/Decor и нужен для случая, когда скрипт запускают
	в пустом месте без подключённого Rojo, — а именно так его обычно и запускают.
	Если конфиг доступен, он главнее: правда живёт там.
]]
local FALLBACK_SIZES = {
	tree_pine = Vector3.new(8, 16, 8),
	tree_round = Vector3.new(10, 14, 10),
	bush_round = Vector3.new(5, 2.5, 5),
	flower_bed = Vector3.new(6, 2, 6),
	rock_small = Vector3.new(4, 3, 4),
	bench = Vector3.new(6, 3, 2.5),
	lamp = Vector3.new(2, 12, 2),
	fountain = Vector3.new(14, 6, 14),
}

local sizes = FALLBACK_SIZES
local hasConfig, Decor = pcall(function()
	return require(game:GetService("ReplicatedStorage").Shared.Config.Decor)
end)
if hasConfig and Decor then
	sizes = {}
	for _, item in Decor.items do
		sizes[item.id] = item.size
	end
	print("[insert] габариты взяты из Config/Decor")
else
	print(
		"[insert] Rojo не подключён — габариты беру из списка внутри скрипта"
	)
end

--[[
	Достаёт модель по id двумя способами.

	game:GetObjects берёт публичный ассет, даже если его нет в инвентаре, и это
	главный путь. InsertService оставлен запасным: он требует, чтобы модель была
	«ваша» (нажата кнопка Get), зато работает там, где GetObjects урезан.

	Распаковка у способов разная, и это важно: GetObjects отдаёт саму модель,
	а LoadAsset заворачивает её в служебный контейнер. Перепутать — значит взять
	вложенную модель вместо целого дерева.
]]
local function fetch(assetId: number): Instance?
	local viaObjects, objects = pcall(function()
		return game:GetObjects(`rbxassetid://{assetId}`)
	end)
	if viaObjects and typeof(objects) == "table" and objects[1] then
		return objects[1]
	end

	local viaInsert, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if viaInsert and typeof(result) == "Instance" then
		local inner = result:FindFirstChildWhichIsA("Model") or result:FindFirstChildWhichIsA("BasePart")
		if inner then
			inner.Parent = nil
			result:Destroy()
			return inner
		end
		return result
	end

	warn(`[insert] не удалось взять {assetId}: {objects} / {result}`)
	return nil
end

local folder = workspace:FindFirstChild("DecorToSave")
if folder then
	folder:Destroy()
end
folder = Instance.new("Folder")
folder.Name = "DecorToSave"
folder.Parent = workspace

local placed = {}
local x = 0

for _, pick in PICKS do
	local fetched = fetch(pick.assetId)
	if not fetched then
		warn(
			`[insert] {pick.id}: пропускаю. Откройте create.roblox.com/store/asset/{pick.assetId}, `
				.. "нажмите Get и запустите скрипт ещё раз"
		)
		continue
	end

	--[[
		Одиночную деталь заворачиваем в модель: дальше всё считается по габариту
		модели, и два вида объекта в этом коде развели бы логику надвое.
	]]
	local model
	if fetched:IsA("Model") then
		model = fetched
	else
		model = Instance.new("Model")
		fetched.Parent = model
	end

	-- Скрипты вырезаем сразу, а не «потом посмотрим»: чужой код в детской игре
	-- не должен дожить даже до сохранения в файл.
	local scripts = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			scripts += 1
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	if scripts > 0 then
		warn(`[insert] {pick.id}: вырезано скриптов — {scripts}`)
	end

	model.Name = pick.id
	model.Parent = folder

	-- Подгонка под габарит каталога: масштабируем по самой тесной оси,
	-- чтобы модель влезла целиком и не потеряла пропорции.
	local want = sizes and sizes[pick.id]
	if want then
		local have = model:GetExtentsSize()
		local scale = math.min(want.X / have.X, want.Y / have.Y, want.Z / have.Z)
		if scale > 0 and math.abs(scale - 1) > 0.02 then
			model:ScaleTo(scale)
		end
	end

	--[[
		Ставим в ряд и низом на ноль: так их удобно осмотреть и так их ждёт игра.
		В два приёма — сперва в точку, потом подъём на измеренную высоту низа:
		точка привязки у чужой модели бывает где угодно, хоть в кроне дерева.
	]]
	model:PivotTo(CFrame.new(x, 0, 0))
	local box, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, -(box.Position.Y - size.Y / 2), 0))
	x += math.max(size.X, 8) + 6

	table.insert(placed, model)

	print(`[insert] {pick.id}: «{pick.title}» от {pick.author}, {pick.tri} треугольников`)
end

Selection:Set(placed)

if #placed == 0 then
	warn(
		"[insert] не взялась ни одна модель. Скорее всего, их нет в инвентаре: "
			.. "откройте ссылки из docs/21-DECOR.md § 7.1, нажмите Get на каждой "
			.. "и запустите скрипт снова."
	)
else
	print(
		`[insert] готово: {#placed} моделей в workspace.DecorToSave. `
			.. "Каждую: правая кнопка → Save to File… → assets/models/decor/<имя>.rbxm"
	)
end
