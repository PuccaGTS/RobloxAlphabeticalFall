--!nonstrict
--[[
	Точка входа клиента. Только сборка контроллеров — никакой игровой логики здесь.
	Решения о верности ответов и наградах принимает сервер (docs/07-TECH-ARCH.md § 3).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefs = require(Shared.Net.RemoteDefs)
local Letters = require(Shared.Config.Letters)
local Shop = require(Shared.Config.Shop)

local Controllers = script:WaitForChild("Controllers")
local AudioController = require(Controllers.AudioController)
local SfxController = require(Controllers.SfxController)
local ChallengeController = require(Controllers.ChallengeController)
local TowerController = require(Controllers.TowerController)
local PortalSignController = require(Controllers.PortalSignController)
local TutorialController = require(Controllers.TutorialController)
local PetController = require(Controllers.PetController)
local DailyLetterController = require(Controllers.DailyLetterController)
local ChestController = require(Controllers.ChestController)
local LiveWorldController = require(Controllers.LiveWorldController)
local DevController = require(Controllers.DevController)
local UI = script:WaitForChild("UI")
local HUD = require(UI.HUD)
local ShopUI = require(UI.ShopUI)
local ParentUI = require(UI.ParentUI)
local DayOverScreen = require(UI.DayOverScreen)

--[[
	Окна чата Roblox у нас нет (docs/11-COMPLIANCE.md § 2). Сервер удаляет сами каналы
	(Services/SafetyService), а здесь прячем пустое окно, чтобы ребёнок не искал,
	куда писать. SetCore готов не сразу после старта — пробуем несколько раз.
]]
task.spawn(function()
	local StarterGui = game:GetService("StarterGui")
	for _ = 1, 20 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Chat, false) then
			return
		end
		task.wait(0.5)
	end
end)

AudioController.init()
SfxController.init()
ChallengeController.init()
TowerController.init()
TutorialController.init()
PetController.init()
LiveWorldController.init()
DevController.init() -- панель появится только в Studio и у владельца места

ShopUI.build({
	onBuy = function(itemId: string)
		RemoteDefs.event("BuyItem"):FireServer(itemId)
	end,
	onEquip = function(itemId: string)
		RemoteDefs.event("EquipItem"):FireServer(itemId)
	end,
})

HUD.build({
	onRepeat = function()
		SfxController.play("tap")
		AudioController.repeatLast()
	end,
	onShop = function()
		SfxController.play("tap")
		ShopUI.setOpen(not ShopUI.isOpen())
	end,
	onHome = function()
		SfxController.play("tap")
		RemoteDefs.event("GoHome"):FireServer()
	end,
	onParent = function()
		SfxController.play("tap")
		ParentUI.open()
	end,
})

AudioController.onSubtitle(HUD.subtitle)

ParentUI.build()
DayOverScreen.init(ParentUI.open)

--[[
	Время игры (docs/13-PARENT-MODE.md § 3). Решает сервер: он знает, сколько
	сыграно сегодня и какой лимит выставил родитель. Клиент только показывает.
]]
RemoteDefs.event("PlayTime").OnClientEvent:Connect(function(payload: any)
	local state = typeof(payload) == "table" and payload.state
	if state == "over" then
		DayOverScreen.show()
	elseif state == "ok" then
		DayOverScreen.hide()
	elseif state == "rest" then
		-- Совет, а не запрет: ничего не закрывается, игра идёт дальше.
		HUD.toast("Давай отдохнём? Глазкам нужен перерыв 👀", 8)
	end
end)

--[[
	Срез профиля от сервера: единственный источник состояния для интерфейса.

	Здесь же ловится покупка. Клиент не знает, удалась ли она — решает сервер, —
	но видит, что вещей стало больше, и этого достаточно, чтобы звякнуть.
	Отдельного «покупка прошла» ради звука заводить не за чем.
]]
local knownItems = -1

RemoteDefs.event("ProfileSnapshot").OnClientEvent:Connect(function(snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end

	local items = #(snapshot.inventory or {})
	if knownItems >= 0 and items > knownItems then
		SfxController.play("purchase")
	end
	knownItems = items

	-- Громкости из настроек профиля. Голос всегда громче остального — это правило
	-- родительского режима (docs/13-PARENT-MODE.md § 3), и оно живёт в настройках.
	local settings = snapshot.settings
	if typeof(settings) == "table" then
		AudioController.setVolume("Music", settings.music or 0.5)
		AudioController.setVolume("SFX", settings.sfx or 0.75)
		AudioController.setVolume("VO", settings.voice or 1)
		AudioController.setSubtitles(settings.subtitles == true)
	end

	HUD.setStars(snapshot.stars or 0)
	ShopUI.update(snapshot)
	TowerController.update(snapshot)
	PortalSignController.update(snapshot)
	TutorialController.update(snapshot)
	DailyLetterController.update(snapshot)
	ChestController.update(snapshot)
end)

-- Сундук в парке: вещь уже надета сервером, здесь — чтобы ребёнок понял, что нашёл.
RemoteDefs.event("ChestOpened").OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local item = typeof(payload.itemId) == "string" and Shop.get(payload.itemId)
	if not item then
		return
	end
	if payload.state == "opened" then
		HUD.toast(`🗝 Сундук! {item.icon} {item.title} — теперь твоя!`, 5)
	elseif payload.state == "already" then
		HUD.toast(`Этот сундук ты уже нашёл: там был {item.icon}`, 3)
	end
end)

--[[
	Буква дня: засчитанное задание и пройденный день. Букву на камне обновит
	срез профиля; здесь — то, что ребёнок должен заметить сразу.
]]
RemoteDefs.event("DailyLetter").OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local letter = typeof(payload.letterId) == "string" and Letters.get(payload.letterId)
	if payload.state == "step" then
		HUD.toast(`☀ Буква дня: {payload.done} из {payload.total}`, 3)
	elseif payload.state == "finished" then
		if letter then
			HUD.showIntro(letter.glyph)
		end
		local stars = (tonumber(payload.bonus) or 0) + (tonumber(payload.streakReward) or 0)
		HUD.toast(`☀ Буква дня пройдена! +{stars} ⭐  🔥 {payload.streak}`, 5)
		SfxController.play("reward")
		-- Вещь за серию уже надета: сервер надел её вместе с выдачей.
		if typeof(payload.items) == "table" then
			for _, itemId in payload.items do
				local item = typeof(itemId) == "string" and Shop.get(itemId)
				if item then
					task.delay(5, HUD.toast, `{item.icon} Подарок за серию: {item.title}!`, 5)
				end
			end
		end
	elseif payload.state == "already" then
		HUD.toast("☀ Буква дня уже пройдена. Приходи завтра!", 3)
	end
end)

--[[
	Сервер просит проиграть эффект: сохранка пройдена, падение. Клиент о таких
	событиях не знает — они целиком про геометрию забега, а она живёт на сервере.
]]
RemoteDefs.event("PlaySfx").OnClientEvent:Connect(function(key: string)
	if typeof(key) == "string" then
		SfxController.play(key)
	end
end)

--[[
	Буква освоена — прилетел буквёнок. Главная награда обучения, и её обязаны
	заметить: буква крупно на экране, звон награды. Имя буквы произносит сервер.
]]
RemoteDefs.event("PetGranted").OnClientEvent:Connect(function(letterId: string, news: any)
	local letter = typeof(letterId) == "string" and Letters.get(letterId)
	if not letter then
		return
	end
	HUD.showIntro(letter.glyph)
	HUD.toast(`Новый друг — буквёнок {letter.glyph}!`, 4)
	SfxController.play("reward")

	-- Вслед за буквёнком — то, что открылось вместе с ним. По очереди, чтобы не слиплось.
	if typeof(news) == "table" then
		if news.secondSlot then
			task.delay(4.5, HUD.toast, "Теперь с тобой летают два буквёнка!", 4)
		end
		if news.keeper then
			task.delay(9, function()
				HUD.toast("👑 Все 33 буквы! Ты — Хранитель Азбуки!", 6)
				SfxController.play("reward")
			end)
		end
	end
end)

-- Объект в мире просит открыть экран (пад магазина в хабе).
RemoteDefs.event("OpenUI").OnClientEvent:Connect(function(screen: string)
	if screen == "shop" then
		ShopUI.setOpen(true)
	elseif screen == "locked_stage" then
		HUD.toast("Эти буквы ещё спят. Поучись ещё немножко!", 3)
	elseif screen == "need_stars" then
		HUD.toast(
			"Звёздочек пока не хватает. Занимайся — и накопишь!",
			3
		)
	end
end)

--[[
	Сервер выдал участок: Азбучная Башня переезжает во двор ребёнка.
	До этого момента Башни нет вовсе — ставить её посреди площади, где стоят
	порталы, значит загородить вход в мир (docs/15-HOME-BASE.md § 4).
]]
RemoteDefs.event("BaseAssigned").OnClientEvent:Connect(function(position: Vector3)
	TowerController.placeAt(position)
end)

-- Сервер просит проиграть реплику: единственный канал озвучки между сервером и клиентом.
RemoteDefs.event("PlayVO").OnClientEvent:Connect(function(key: string, interrupt: boolean?)
	if typeof(key) ~= "string" then
		return
	end
	if interrupt == true then
		AudioController.interrupt(key)
	else
		AudioController.speak(key)
	end
end)

--[[
	Задание, собранное из нескольких реплик: «Сколько будет» + «два» + «плюс» + «два».
	Для ребёнка это одно задание, поэтому и кнопка «повторить» повторяет его целиком.
]]
RemoteDefs.event("PlayPhrase").OnClientEvent:Connect(function(keys: { string }, interrupt: boolean?)
	if typeof(keys) ~= "table" or #keys == 0 then
		return
	end
	if interrupt == true then
		AudioController.stopAll()
	end
	AudioController.speakPhrase(keys)
end)

--[[
	Предзагружаем названия букв первых двух ступеней: задержка перед буквой недопустима.
	Две, а не одна: вторая открывается быстро, и подгружать её в момент открытия —
	значит поймать паузу ровно там, где ребёнок ждёт новую букву.
]]
task.defer(function()
	local keys: { string } = {}
	for _, stage in { 1, 2 } do
		for _, id in Letters.byStage(stage) do
			table.insert(keys, Letters.expect(id).vo.name)
		end
	end
	AudioController.preload(keys)
end)

print("[AlphabetFall] клиент запущен")
