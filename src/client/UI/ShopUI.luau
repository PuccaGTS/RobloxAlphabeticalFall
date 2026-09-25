--!nonstrict
--[[
	Магазин и гардероб — один экран.

	Из docs/08-UX-UI.md: крупные карточки, цена цифрой И звёздочками (ребёнок ещё
	не знает цифр), кнопка примерки важнее кнопки покупки, недоступное показываем
	не замком, а тем, сколько осталось накопить.
]]

local Players = game:GetService("Players")

local Shop = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.Shop)
local Chests = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.Chests)

local CloseButton = require(script.Parent.CloseButton)

local ShopUI = {}

local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local cards: { [string]: Frame } = {}
local handlers: any = nil
local lastSnapshot: any = nil

local COLOR_BUY = Color3.fromRGB(120, 200, 130)
local COLOR_EQUIP = Color3.fromRGB(255, 214, 102)
local COLOR_EQUIPPED = Color3.fromRGB(150, 160, 180)
local COLOR_LOCKED = Color3.fromRGB(90, 95, 110)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

--[[
	Цена показывается и цифрой, и звёздочками: цифру ребёнок ещё не читает,
	а «сколько звёздочек» считывает по количеству значков.
]]
--[[
	Наряд буквят без единого буквёнка — покупка «в пустоту»: на проверке
	24.09.2026 купили скин и спросили, кто такие буквята, — ничего не произошло.
	Пока буквёнка нет, карточка говорит, откуда он берётся, и не продаёт.
]]
local function needsPet(item, snapshot): boolean
	if item.category ~= "petskin" or not snapshot then
		return false
	end
	local pets = snapshot.equipped and snapshot.equipped.pets
	return typeof(pets) ~= "table" or #pets == 0
end

local function priceText(price: number): string
	local pips = math.clamp(math.ceil(price / 25), 1, 5)
	return `{price} ` .. string.rep("⭐", pips)
end

local function makeCard(item): Frame
	local card = Instance.new("Frame")
	card.Name = item.id
	card.Size = UDim2.fromOffset(180, 210)
	card.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
	corner(card, 18)

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.fromScale(1, 0.42)
	icon.BackgroundTransparency = 1
	icon.Text = item.icon
	icon.TextScaled = true
	icon.Parent = card

	-- Редкая вещь со шлейфом: ребёнок не читает, поэтому метка — искры, а не слово.
	if item.effect then
		local glow = Instance.new("UIStroke")
		glow.Color = Color3.fromRGB(255, 214, 102)
		glow.Thickness = 3
		glow.Parent = card

		local badge = Instance.new("TextLabel")
		badge.Name = "EffectBadge"
		badge.Size = UDim2.fromOffset(40, 40)
		badge.Position = UDim2.new(1, -44, 0, 4)
		badge.BackgroundTransparency = 1
		badge.Text = "✨"
		badge.TextScaled = true
		badge.Parent = card
	end

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.16)
	title.Position = UDim2.fromScale(0, 0.42)
	title.BackgroundTransparency = 1
	title.Text = item.title
	title.TextColor3 = Color3.fromRGB(235, 235, 245)
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.Parent = card

	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.Size = UDim2.fromScale(1, 0.14)
	price.Position = UDim2.fromScale(0, 0.58)
	price.BackgroundTransparency = 1
	local streakDays = Shop.streakDays(item)
	price.Text = if item.price
		then priceText(item.price)
		elseif streakDays then `☀ {streakDays} дней`
		elseif Chests.chestIdOf(item.grantedBy) then "🗝 в сундуке"
		elseif Shop.weekNumber(item) then "🏆 за неделю"
		else ""
	price.TextColor3 = Color3.fromRGB(255, 214, 102)
	price.TextScaled = true
	price.Font = Enum.Font.FredokaOne
	price.Parent = card

	local action = Instance.new("TextButton")
	action.Name = "Action"
	action.Size = UDim2.fromScale(0.84, 0.2)
	action.Position = UDim2.fromScale(0.08, 0.74)
	action.BackgroundColor3 = COLOR_BUY
	action.TextColor3 = Color3.fromRGB(30, 30, 40)
	action.Text = "Купить"
	action.TextScaled = true
	action.Font = Enum.Font.FredokaOne
	action.Parent = card
	corner(action, 12)

	action.Activated:Connect(function()
		if not handlers or not lastSnapshot then
			return
		end
		local owned = table.find(lastSnapshot.inventory or {}, item.id) ~= nil
		if not owned and needsPet(item, lastSnapshot) then
			return
		end
		if owned then
			handlers.onEquip(item.id)
		else
			handlers.onBuy(item.id)
		end
	end)

	cards[item.id] = card
	return card
end

function ShopUI.build(callbacks)
	if gui then
		return
	end
	handlers = callbacks

	local screen = Instance.new("ScreenGui")
	screen.Name = "AlphabetFallShop"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	--[[
		Выше HUD, ниже экрана родителей. Раньше слой был общий с HUD, и кнопка 🔊
		рисовалась поверх левой колонки карточек: на проверке 24.09.2026 ребёнок
		хотел купить очки лётчика, а попал в звук. Подложка на весь экран ловит
		нажатия мимо окна — сквозь магазин до кнопок HUD они больше не доходят.
	]]
	screen.DisplayOrder = 6
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	local dim = Instance.new("TextButton")
	dim.Name = "Backdrop"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	dim.BackgroundTransparency = 0.45
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Parent = screen
	-- Тап мимо окна закрывает магазин: так закрывают окна на телефоне.
	dim.Activated:Connect(function()
		ShopUI.setOpen(false)
	end)

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.86, 0.8)
	panel.Position = UDim2.fromScale(0.07, 0.1)
	panel.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
	panel.Active = true
	panel.Parent = screen
	corner(panel, 24)

	local header = Instance.new("TextLabel")
	header.Size = UDim2.fromScale(0.6, 0.1)
	header.Position = UDim2.fromScale(0.04, 0.02)
	header.BackgroundTransparency = 1
	header.Text = "Магазин"
	header.TextColor3 = Color3.fromRGB(255, 255, 255)
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextScaled = true
	header.Font = Enum.Font.FredokaOne
	header.Parent = panel

	local balance = Instance.new("TextLabel")
	balance.Name = "Balance"
	balance.Size = UDim2.fromScale(0.25, 0.09)
	balance.Position = UDim2.fromScale(0.55, 0.025)
	balance.BackgroundTransparency = 1
	balance.Text = "⭐ 0"
	balance.TextColor3 = Color3.fromRGB(255, 214, 102)
	balance.TextScaled = true
	balance.Font = Enum.Font.FredokaOne
	balance.Parent = panel

	local close = CloseButton.make(panel, 52, UDim2.new(1, -66, 0, 14))
	close.Activated:Connect(function()
		ShopUI.setOpen(false)
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(0.94, 0.82)
	scroll.Position = UDim2.fromScale(0.03, 0.14)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 10
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(180, 210)
	layout.CellPadding = UDim2.fromOffset(14, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	for order, id in Shop.ids() do
		local card = makeCard(Shop.expect(id))
		card.LayoutOrder = order
		card.Parent = scroll
	end
end

function ShopUI.setOpen(open: boolean)
	if gui then
		gui.Enabled = open
	end
end

function ShopUI.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function ShopUI.update(snapshot)
	lastSnapshot = snapshot
	if not gui then
		return
	end

	local balance = gui:FindFirstChild("Balance", true)
	if balance and balance:IsA("TextLabel") then
		balance.Text = `⭐ {snapshot.stars or 0}`
	end

	local inventory = snapshot.inventory or {}
	local equipped = snapshot.equipped or {}

	--[[
		Родитель мог выключить показ покупок за Robux (docs/13-PARENT-MODE.md § 3).
		Прячем карточку целиком: кнопка «нельзя» — это всё равно витрина,
		а ребёнок просит то, что видит.
	]]
	local hideRobux = typeof(snapshot.settings) == "table" and snapshot.settings.hideRobux == true

	for id, card in cards do
		local item = Shop.expect(id)
		card.Visible = not (hideRobux and item.robuxProduct)
		local action = card:FindFirstChild("Action") :: TextButton
		local owned = table.find(inventory, id) ~= nil
		local isEquipped = equipped[item.category] == id

		if owned then
			action.Text = if isEquipped then "Снять" else "Надеть"
			action.BackgroundColor3 = if isEquipped then COLOR_EQUIPPED else COLOR_EQUIP
		elseif needsPet(item, snapshot) then
			-- Буквёнок прилетает за выученную букву (Logic/Pets.OWNED_AT): это и есть цель.
			action.Text = "🐾 сначала выучи букву"
			action.BackgroundColor3 = COLOR_LOCKED
		elseif item.price and (snapshot.stars or 0) >= item.price then
			action.Text = "Купить"
			action.BackgroundColor3 = COLOR_BUY
		elseif Shop.streakDays(item) then
			--[[
				За серию не покупается. Цель — огоньки, как на камне буквы дня:
				сколько дней ещё осталось, ребёнок видит там же, где считает серию.
			]]
			local days = Shop.streakDays(item) :: number
			local streak = if typeof(snapshot.daily) == "table"
				then tonumber(snapshot.daily.streak) or 0
				else 0
			action.Text = `🔥 {math.min(streak, days)} из {days}`
			action.BackgroundColor3 = COLOR_LOCKED
		elseif Chests.chestIdOf(item.grantedBy) then
			-- Не купить, а найти: сундук стоит в парке между площадью и домами.
			action.Text = "Найди в парке"
			action.BackgroundColor3 = COLOR_LOCKED
		elseif Shop.weekNumber(item) then
			-- Задание недели в панели заданий: выполнил — вещь приходит сама.
			action.Text = "📋 задание недели"
			action.BackgroundColor3 = COLOR_LOCKED
		else
			-- Не «замок», а сколько осталось накопить: замок демотивирует, цель — нет.
			local left = (item.price or 0) - (snapshot.stars or 0)
			action.Text = `ещё {left} ⭐`
			action.BackgroundColor3 = COLOR_LOCKED
		end
	end
end

return ShopUI
