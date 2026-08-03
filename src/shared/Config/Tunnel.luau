--!strict
--[[
	Геометрия и параметры туннеля. См. docs/14-TUNNEL-MODE.md.

	Бег свободный: скорость задаёт ребёнок, а не игра. Поэтому здесь нет параметра
	скорости — есть только расстояния, из которых складывается ритм забега.
]]

local Tunnel = {}

Tunnel.LANE_COUNT = 3
Tunnel.LANE_WIDTH = 9 -- расстояние между центрами дорожек
Tunnel.WIDTH = Tunnel.LANE_COUNT * Tunnel.LANE_WIDTH
Tunnel.HEIGHT = 16
Tunnel.WALL_THICKNESS = 2

Tunnel.START_RUNWAY = 30 -- разгон перед первыми воротами
Tunnel.GATE_SPACING = 55 -- расстояние между воротами: место под препятствия и сбор
Tunnel.FINISH_RUNWAY = 35

-- Куда ставится туннель игрока. У каждого он свой, поэтому разносим по оси X.
Tunnel.PLOT_SPACING = 500
Tunnel.PLOT_ORIGIN = Vector3.new(2000, 200, 0)

Tunnel.PARAMS = {
	gates = { 4, 4, 5, 5, 6 },
	choices = { 2, 2, 3, 3, 4 }, -- сколько проёмов в воротах
	barriers = { 1, 1, 2, 2, 3 }, -- препятствий между воротами
	-- Замедление после неверных ворот: ошибка стоит времени, а не прогресса.
	missSlowSeconds = { 1.6, 1.4, 1.2, 1.1, 1.0 },
	missSlowFactor = { 0.45, 0.45, 0.5, 0.5, 0.55 },
}

Tunnel.WALK_SPEED = 20 -- базовая скорость персонажа в туннеле
Tunnel.JUMP_POWER = 55

function Tunnel.laneOffset(lane: number): number
	return (lane - (Tunnel.LANE_COUNT + 1) / 2) * Tunnel.LANE_WIDTH
end

-- Длина забега по числу ворот — нужна и генератору, и таймауту испытания.
function Tunnel.length(gateCount: number): number
	return Tunnel.START_RUNWAY + gateCount * Tunnel.GATE_SPACING + Tunnel.FINISH_RUNWAY
end

return Tunnel
