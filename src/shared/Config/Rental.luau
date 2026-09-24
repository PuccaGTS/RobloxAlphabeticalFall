--!strict
--[[
	Прокат в парке: самокат, велосипед с корзинкой и лошадка-единорог на палочке.

	Встал на круг перед вещью — едешь на ней по всему парку, быстрее, чем бегом.
	Кнопка ✖ внизу экрана — слезть. Другие дети видят, кто на чём катается:
	вещь прикреплена к персонажу на сервере (Services/RentalService), а колёса
	крутит и лошадку подкидывает клиент (Controllers/RentalController).

	Правило игровых мест то же: ничего не даёт. Кататься весело само по себе.
	Только в парке: у ворот испытания вещь остаётся — на поляне занятий и в забеге
	скорость своя, и самокат там только мешал бы.
]]

local Rental = {}

export type Vehicle = {
	id: string,
	icon: string,
	title: string,
	speed: number, -- WalkSpeed, пока едешь (пешком 16)
	jump: number, -- на сколько выше обычного прыжок
	--[[
		Поза: stand — стоит, как на самокате (анимация «стоять» поверх бега),
		sit — сидит, как на велосипеде, gallop — бежит сам, лошадка скачет.
	]]
	pose: "stand" | "sit" | "gallop",
	sound: string, -- ключ AudioRegistry: звучит, когда садишься
	color: Color3,
}

local LIST: { Vehicle } = {
	{
		id = "scooter",
		icon = "🛴",
		title = "Самокат",
		speed = 26,
		jump = 0,
		pose = "stand",
		sound = "sfx_bike_bell",
		color = Color3.fromRGB(80, 190, 235),
	},
	{
		id = "bike",
		icon = "🚲",
		title = "Велосипед",
		speed = 30,
		jump = 0,
		pose = "sit",
		sound = "sfx_bike_bell",
		color = Color3.fromRGB(245, 105, 120),
	},
	{
		id = "unicorn",
		icon = "🦄",
		title = "Лошадка",
		speed = 22,
		jump = 3,
		pose = "gallop",
		sound = "sfx_magic",
		color = Color3.fromRGB(190, 140, 250),
	},
}
Rental.list = LIST

--[[
	Анимации позы — стандартные анимации Roblox из скрипта Animate, как у танцев
	(Config/Emotes): «стоять» и «сидеть». У R15 и R6 номера разные.
]]
Rental.POSES = {
	stand = { r15 = 507766666, r6 = 180435571 },
	sit = { r15 = 2506281703, r6 = 178130996 },
}

Rental.PAD_RADIUS = 2.6 -- круг перед вещью: встал — поехал
Rental.PAD_SPACING = 7 -- между кругами
Rental.WALK_SPEED = 16 -- пешком: сюда возвращается скорость, когда слез
Rental.GALLOP_BOB = 0.45 -- на сколько лошадка подскакивает на бегу
Rental.WHEEL_RADIUS = 1.2

local byId: { [string]: Vehicle } = {}
for _, vehicle in LIST do
	assert(byId[vehicle.id] == nil, `Rental: дубликат "{vehicle.id}"`)
	byId[vehicle.id] = vehicle
end

function Rental.get(id: any): Vehicle?
	if typeof(id) ~= "string" then
		return nil
	end
	return byId[id]
end

return Rental
