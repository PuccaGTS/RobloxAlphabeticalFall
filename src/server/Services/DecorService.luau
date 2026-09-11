--!nonstrict
--[[
	Расстановка декора на площади. Данные — Config/Decor, инструкция — docs/21-DECOR.md.

	Сервис делает три вещи и ничего больше:

	  1. берёт модель из ReplicatedStorage.Assets.decor (туда её кладёт Rojo
	     из папки assets/models/decor) и ставит её в точку из конфига;
	  2. если модели ещё нет — собирает эскиз из примитивов (World/DecorShapes):
	     дерево, лавочку, фонтан. Площадь выглядит площадью до прихода арта,
	     а не полем серых коробок. Нет и эскиза — остаётся коробка по габариту;
	  3. ОБЕЗВРЕЖИВАЕТ модель перед установкой: выкидывает скрипты, отключает
	     физику и лишние взаимодействия.

	Третий пункт — не паранойя, а пункт чек-листа. Модели из библиотеки Roblox
	регулярно приезжают со скриптами внутри, и в игре для детей чужой скрипт
	на сервере — это чужой код рядом с профилями и покупками. Поэтому здесь
	не «проверить глазами», а снести программно и написать в лог, что снесли.

	Декор ничего не делает: не запускает испытаний, не даёт звёздочек, не мешает
	пройти. На него можно залезть, его можно обойти — и всё.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Decor = require(Shared.Config.Decor)

local DecorShapes = require(script.Parent.Parent.World.DecorShapes)

local DecorService = {}

-- Насколько модель вправе отличаться от заявленного в каталоге размера.
-- Больше — это не «немного другой эскиз», а модель не того масштаба.
local SIZE_TOLERANCE = 2

local removedScripts = 0
local missingModels: { [string]: boolean } = {}

--[[
	Обезвреживает копию чужой модели.

	Скрипты уничтожаются, а не отключаются: отключённый скрипт кто-нибудь однажды
	включит. Всё остальное — про поведение: декор не падает, не толкается
	и не перехватывает касания, предназначенные падам.
]]
--[[
	Настраивает поведение деталей — общее и для чужой модели, и для нашего эскиза.

	Декор не падает, не толкается и не перехватывает касания, предназначенные падам.
	Сталкиваемость берётся из каталога: сквозь куст ребёнок проходит насквозь,
	дерево обходит.
]]
local function harden(model: Instance, item)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = item.collide
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
end

local function sanitize(model: Instance, item, source: string)
	local scripts = 0

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			scripts += 1
			descendant:Destroy()
		elseif descendant:IsA("ProximityPrompt") or descendant:IsA("ClickDetector") then
			-- Декор ничего не запускает: подсказка на дереве обещает ребёнку действие,
			-- которого нет, и он будет жать на неё, пока не решит, что игра сломалась.
			descendant:Destroy()
		end
	end

	harden(model, item)

	if scripts > 0 then
		removedScripts += scripts
		warn(
			`[Decor] в модели "{source}" было {scripts} скриптов — они удалены. `
				.. `Проверьте, откуда взята модель.`
		)
	end
end

--[[
	Ставит модель так, чтобы она СТОЯЛА на земле, а не висела и не тонула в ней.

	Высоту берём из конфига: площадь на полстуда выше травы, и одна константа
	на всех оставила бы деревья за краем плитки висеть в воздухе.

	Двигаем в два приёма — сперва ставим и меряем, потом поднимаем на нужное:
	у чужой модели точка привязки бывает где угодно, в том числе в кроне дерева.
]]
local function placeOnGround(model: Model, placement)
	model:PivotTo(CFrame.new(placement.x, 0, placement.z) * CFrame.Angles(0, math.rad(placement.rotation), 0))

	local box, size = model:GetBoundingBox()
	local bottom = box.Position.Y - size.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, Decor.groundY(placement.x, placement.z) - bottom, 0))

	return size
end

--[[
	Последняя соломинка: коробка размером с обещанную модель.

	Ставится, когда нет ни модели художника, ни эскиза, — то есть у предмета,
	который только что завели в каталоге. Она не притворяется артом, она держит
	место: расстановку надо на чём-то проверять с первого же дня.
]]
local function buildStandIn(item, placement): Model
	local model = Instance.new("Model")
	model.Name = `{item.id}_standin`

	local part = Instance.new("Part")
	part.Name = item.id
	part.Size = item.size * (placement.scale or 1)
	part.Color = item.color
	part.Anchored = true
	part.CanCollide = item.collide
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model

	model.PrimaryPart = part
	return model
end

-- Папка с моделями. Её может не быть вовсе — пока в assets/models пусто.
local function assetsFolder(): Instance?
	local root = ReplicatedStorage:FindFirstChild(Decor.FOLDER)
	if not root then
		return nil
	end
	return root:FindFirstChild(Decor.SUBFOLDER)
end

--[[
	Готовая модель предмета, если художник её принёс.

	Ищем по всей ветке, а не только среди прямых детей. Причина бытовая: Studio
	сохраняет выделение в ОДИН файл, поэтому все модели разом кладутся как
	`pack.rbxm`, и внутри игры они оказываются на уровень глубже. Требовать файл
	на предмет значило бы восемь раз пройти через диалог сохранения ради ничего.

	Одиночная деталь тоже годится: заворачиваем её в модель, чтобы дальше
	весь код работал с одним видом объекта.
]]
local function takeModel(folder: Instance?, item): Model?
	if not folder then
		return nil
	end

	local source = folder:FindFirstChild(item.id, true)
	if not source then
		return nil
	end

	local copy = source:Clone()
	if copy:IsA("Model") then
		return copy
	end
	if copy:IsA("BasePart") then
		local model = Instance.new("Model")
		model.Name = item.id
		copy.Parent = model
		model.PrimaryPart = copy
		return model
	end

	warn(`[Decor] "{item.id}" — это {copy.ClassName}, а нужна модель или деталь`)
	copy:Destroy()
	return nil
end

--[[
	Приёмка размера. Модель вдвое крупнее обещанного каталогом ломает расстановку:
	она лезет в проход, которого в конфиге не видно, и заметит это ребёнок.
	Не отказываемся ставить — говорим в лог, чтобы поправили каталог или модель.
]]
local function checkSize(item, actual: Vector3, scale: number)
	local expected = item.size * scale
	for _, axis in { "X", "Y", "Z" } do
		local got, want = actual[axis], expected[axis]
		if want > 0 and (got > want * SIZE_TOLERANCE or got * SIZE_TOLERANCE < want) then
			warn(
				`[Decor] "{item.id}": размер {math.floor(actual.X)}x{math.floor(actual.Y)}x{math.floor(
					actual.Z
				)} `
					.. `не сходится с каталогом {math.floor(expected.X)}x{math.floor(
						expected.Y
					)}x{math.floor(expected.Z)}`
			)
			return
		end
	end
end

--[[
	Строит весь декор площади в переданную папку.

	Ошибка в одном предмете не должна оставить площадь без остального декора,
	поэтому каждая установка идёт в pcall: пропущенное дерево — мелочь,
	пустая площадь — нет.
]]
function DecorService.build(parent: Instance): number
	removedScripts = 0
	missingModels = {}

	local folder = assetsFolder()
	local container = Instance.new("Folder")
	container.Name = "Decor"
	container.Parent = parent

	local placed = 0

	for _, placement in Decor.placements do
		local item = Decor.get(placement.id)
		if not item then
			warn(
				`[Decor] в расстановке предмет "{placement.id}", которого нет в каталоге`
			)
			continue
		end

		local ok, err = pcall(function()
			local scale = placement.scale or 1
			local model = takeModel(folder, item)
			local fromAsset = model ~= nil

			if model then
				sanitize(model, item, item.id)
			else
				--[[
					Модели художника ещё нет. Тогда собираем эскиз из примитивов,
					и только если нет даже его — ставим коробку по габариту.
				]]
				missingModels[item.id] = true
				model = DecorShapes.build(item)
				if model then
					harden(model, item)
				else
					model = buildStandIn(item, placement)
				end
			end

			if scale ~= 1 and model.ScaleTo then
				model:ScaleTo(scale)
			end

			model.Name = `{item.id}_{placed + 1}`
			model.Parent = container

			local size = placeOnGround(model, placement)
			if fromAsset then
				checkSize(item, size, scale)
			end
			placed += 1
		end)

		if not ok then
			warn(`[Decor] не удалось поставить "{placement.id}": {err}`)
		end
	end

	local missing = 0
	for _ in missingModels do
		missing += 1
	end

	if missing > 0 then
		print(
			string.format(
				"[Decor] расставлено %d предметов; моделей нет для %d видов — стоят эскизы (docs/21-DECOR.md)",
				placed,
				missing
			)
		)
	else
		print(
			string.format(
				"[Decor] расставлено %d предметов, все с моделями",
				placed
			)
		)
	end

	return placed
end

-- Сколько чужих скриптов вырезано при последней сборке: для лога и для тестов.
function DecorService.removedScripts(): number
	return removedScripts
end

return DecorService
