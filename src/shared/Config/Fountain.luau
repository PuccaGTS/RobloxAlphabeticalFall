--!strict
--[[
	Поющий фонтан на площади (Controllers/FountainController). Раз в полторы
	минуты фонтан устраивает шоу: восемь струй по кругу и одна в середине
	пляшут под «Water Ballet» (APM Music, библиотека Roblox), струи красятся
	радугой. Шоу идёт по серверным часам — у всех детей в одной фазе.

	Ничего не даёт и ничему не учит: это то, ради чего хочется вернуться
	на площадь и позвать другого ребёнка — «смотри, сейчас начнётся!».

	Хореография — чистая функция от времени (Fountain.height): её держит тест,
	а клиент только переводит долю высоты в скорость частиц.
]]

local Fountain = {}

Fountain.CENTER = Vector3.new(0, 0, -34) -- там же, где фонтан в Config/Decor
Fountain.JETS = 8 -- струй по кругу, плюс одна в середине
Fountain.RING = 5.2 -- радиус круга струй
Fountain.NOZZLE_Y = 3.2 -- высота сопел над землёй: над водой чаши
Fountain.MAX_HEIGHT = 16 -- выше этого струя кольца не бьёт
Fountain.CENTER_HEIGHT = 24 -- средняя струя в финале
Fountain.GRAVITY = 60 -- ускорение капель вниз, студ/с²
Fountain.EVERY = 90 -- шоу раз в столько секунд
Fountain.SECONDS = 28 -- длительность шоу
Fountain.HEAR = 110 -- дальше этого музыки шоу не слышно
Fountain.COLORS = {
	Color3.fromRGB(255, 110, 110),
	Color3.fromRGB(255, 180, 80),
	Color3.fromRGB(255, 235, 110),
	Color3.fromRGB(120, 230, 130),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(120, 140, 255),
	Color3.fromRGB(200, 130, 255),
	Color3.fromRGB(255, 140, 210),
}

-- Где сейчас шоу: секунда от начала или nil, если фонтан просто журчит.
function Fountain.showTime(now: number): number?
	local t = now % Fountain.EVERY
	return if t < Fountain.SECONDS then t else nil
end

local function wave(x: number): number
	return 0.5 + 0.5 * math.sin(x)
end

--[[
	Высота струи jet (1..JETS — кольцо, 0 — середина) в секунду t шоу,
	доля от 0 (молчит) до 1 (бьёт во всю силу). Номера частей — такты:
	  0–5    волна бежит по кругу;
	  5–9    всё кольцо дышит вместе;
	  9–13   чётные и нечётные по очереди;
	  13–17  середина растёт, кольцо низко;
	  17–22  быстрая волна в обратную сторону;
	  22–26  финал: всё вверх, середина выше всех;
	  26–28  затихает.
]]
function Fountain.height(jet: number, t: number): number
	local phase = if jet == 0 then 0 else (jet - 1) / Fountain.JETS * math.pi * 2
	if t < 0 or t >= Fountain.SECONDS then
		return 0
	elseif t < 5 then
		return if jet == 0 then 0.15 else 0.25 + 0.75 * wave(t * 3 - phase)
	elseif t < 9 then
		return if jet == 0 then 0.3 else 0.35 + 0.65 * wave(t * math.pi * 2 / 1.5)
	elseif t < 13 then
		local beat = math.floor((t - 9) / 0.5) % 2
		return if jet == 0 then 0.2 elseif (jet % 2) == beat then 0.95 else 0.2
	elseif t < 17 then
		return if jet == 0 then 0.3 + 0.7 * math.clamp((t - 13) / 3, 0, 1) else 0.25
	elseif t < 22 then
		return if jet == 0 then 0.4 else 0.2 + 0.8 * wave(t * 6 + phase)
	elseif t < 26 then
		return 1
	end
	return math.clamp((Fountain.SECONDS - t) / 2, 0, 1)
end

-- Цвет струи: радуга по кругу, которая медленно кружится.
function Fountain.color(jet: number, t: number): Color3
	local count = #Fountain.COLORS
	local shift = math.floor(t / 1.5)
	return Fountain.COLORS[(jet + shift) % count + 1]
end

return Fountain
