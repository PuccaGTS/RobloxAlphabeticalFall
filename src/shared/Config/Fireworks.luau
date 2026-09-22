--!strict
--[[
	Салют за пройденный уровень пути (Controllers/FireworksController).

	Звёзд не даёт и ничего не проверяет: это праздник за уже засчитанный
	уровень. Звук — «свистящие» ракеты из библиотеки Pro Sound Effects
	(AudioRegistry.sfx_fireworks), грузить ничего не надо.
]]

local Fireworks = {}

Fireworks.ROCKETS = 9
Fireworks.INTERVAL = 0.45 -- секунд между ракетами
Fireworks.FLIGHT_SECONDS = 1.1
Fireworks.DISTANCE = 70 -- как далеко перед камерой рвутся
Fireworks.WIDTH = 70 -- на сколько расходятся веером
Fireworks.HEIGHT = { 28, 48 } -- выше камеры
Fireworks.SPARKS = 80 -- искр во внешнем шаре разрыва, во внутреннем вдвое меньше: до сотни с небольшим
Fireworks.BURST_SPEED = 30

Fireworks.COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 200, 70),
	Color3.fromRGB(110, 220, 120),
	Color3.fromRGB(90, 180, 255),
	Color3.fromRGB(200, 120, 255),
	Color3.fromRGB(255, 140, 200),
}

return Fireworks
