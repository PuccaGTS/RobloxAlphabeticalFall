--!strict
--[[
	Буквы, нарисованные штрихами, — чтобы их можно было честно отразить.

	Интерфейс Roblox поворачивает надпись, но не отражает её. Поэтому «Зеркало»
	раньше отражало только три буквы, для которых нашёлся похожий готовый знак
	(Я ↔ R, И ↔ N, Э ↔ Є), а Р, З, Ю и остальные ждали картинок.

	Здесь каждая буква — несколько ломаных в квадрате 1×1 (x вправо, y вниз),
	как если бы её провели толстым фломастером. Ломаная — это просто точки,
	а точки отражаются и поворачиваются одной формулой. Клиент рисует каждый
	отрезок скруглённой полоской (UI/Glyph), сервер по тем же точкам решает,
	отличается ли отражение от самой буквы (Challenges/Mirror).

	Чистая логика без Roblox API — покрыта тестами. Форму глазами проверяет
	`python tools/glyphs/preview.py`: он читает этот файл и рисует все буквы
	и их отражения в PNG. Поэтому каждая буква — одна строка из вызовов
	line/poly/arc/dot с числами, без переменных, кроме T, M, B.
]]

local StrokeGlyphs = {}

export type Point = { number }
export type Stroke = { Point }

-- Толщина штриха в долях квадрата и обводки под ним.
StrokeGlyphs.WIDTH = 0.12
StrokeGlyphs.OUTLINE = 0.05

-- Верх, середина и низ заглавной буквы.
local T, M, B = 0.12, 0.5, 0.88

local function line(x1: number, y1: number, x2: number, y2: number): Stroke
	return { { x1, y1 }, { x2, y2 } }
end

local function poly(...: number): Stroke
	local values = { ... }
	local stroke: Stroke = {}
	for i = 1, #values - 1, 2 do
		table.insert(stroke, { values[i], values[i + 1] })
	end
	return stroke
end

-- Точка: полоска нулевой длины рисуется кружком (точки над Ё).
local function dot(x: number, y: number): Stroke
	return { { x, y }, { x, y } }
end

--[[
	Дуга эллипса от угла from до угла to в градусах. Угол 0 — вправо, 90 — вниз
	(y смотрит вниз). Направление обхода задаёт знак разницы: from < to — по
	часовой стрелке на экране.
]]
local function arc(cx: number, cy: number, rx: number, ry: number, from: number, to: number): Stroke
	local steps = math.max(3, math.ceil(math.abs(to - from) / 15))
	local stroke: Stroke = {}
	for i = 0, steps do
		local angle = math.rad(from + (to - from) * i / steps)
		table.insert(stroke, { cx + rx * math.cos(angle), cy + ry * math.sin(angle) })
	end
	return stroke
end

-- Склеивает куски в одну ломаную: так на стыке нет щели.
local function join(...: Stroke): Stroke
	local stroke: Stroke = {}
	for _, part in { ... } do
		for _, point in part do
			table.insert(stroke, point)
		end
	end
	return stroke
end

-- stylua: ignore start
local SHAPES: { [string]: { Stroke } } = {
	a = { poly(0.22, B, 0.5, T, 0.78, B), line(0.33, 0.64, 0.67, 0.64) },
	b = { poly(0.72, T, 0.3, T, 0.3, B), join(poly(0.3, 0.47, 0.52, 0.47), arc(0.52, 0.675, 0.2, 0.205, -90, 90), poly(0.3, B)) },
	v = { line(0.3, T, 0.3, B), join(poly(0.3, T, 0.5, T), arc(0.5, 0.3, 0.17, 0.18, -90, 90), poly(0.3, 0.48)), join(poly(0.3, 0.48, 0.52, 0.48), arc(0.52, 0.68, 0.2, 0.2, -90, 90), poly(0.3, B)) },
	g = { poly(0.72, T, 0.3, T, 0.3, B) },
	d = { poly(0.16, 0.96, 0.16, 0.8, 0.84, 0.8, 0.84, 0.96), poly(0.27, 0.8, 0.4, T, 0.6, T, 0.73, 0.8) },
	ye = { poly(0.72, T, 0.3, T, 0.3, B, 0.72, B), line(0.3, M, 0.66, M) },
	yo = { poly(0.72, 0.2, 0.3, 0.2, 0.3, B, 0.72, B), line(0.3, 0.54, 0.66, 0.54), dot(0.4, 0.05), dot(0.62, 0.05) },
	zh = { line(0.5, T, 0.5, B), poly(0.16, T, 0.36, M, 0.13, B), poly(0.84, T, 0.64, M, 0.87, B), line(0.36, M, 0.64, M) },
	z = { join(arc(0.49, 0.31, 0.21, 0.19, -155, 90), poly(0.4, M)), join(poly(0.4, M, 0.5, M), arc(0.5, 0.69, 0.23, 0.19, -90, 155)) },
	i = { poly(0.28, T, 0.28, B, 0.72, T, 0.72, B) },
	j = { poly(0.28, 0.2, 0.28, B, 0.72, 0.2, 0.72, B), arc(0.5, 0.0, 0.13, 0.1, 35, 145) },
	k = { line(0.3, T, 0.3, B), poly(0.72, T, 0.34, 0.52, 0.76, B) },
	l = { poly(0.18, B, 0.36, T, 0.74, T, 0.74, B) },
	m = { poly(0.2, B, 0.24, T, 0.5, 0.62, 0.76, T, 0.8, B) },
	n = { line(0.28, T, 0.28, B), line(0.72, T, 0.72, B), line(0.28, M, 0.72, M) },
	o = { arc(0.5, 0.5, 0.28, 0.38, 0, 360) },
	p = { poly(0.28, B, 0.28, T, 0.72, T, 0.72, B) },
	r = { join(poly(0.3, B, 0.3, T, 0.5, T), arc(0.5, 0.31, 0.2, 0.19, -90, 90), poly(0.3, M)) },
	s = { arc(0.54, 0.5, 0.29, 0.38, -45, -315) },
	t = { line(0.2, T, 0.8, T), line(0.5, T, 0.5, B) },
	u = { poly(0.22, T, 0.52, 0.66), join(poly(0.8, T, 0.52, 0.76), arc(0.33, 0.76, 0.19, 0.12, 0, 90)) },
	f = { arc(0.5, 0.47, 0.32, 0.21, 0, 360), line(0.5, 0.08, 0.5, 0.92) },
	h = { line(0.22, T, 0.78, B), line(0.78, T, 0.22, B) },
	c = { poly(0.24, T, 0.24, 0.8, 0.84, 0.8, 0.84, 0.96), line(0.7, T, 0.7, 0.8) },
	ch = { join(poly(0.28, T, 0.28, 0.34), arc(0.44, 0.34, 0.16, 0.16, 180, 90), poly(0.72, M)), line(0.72, T, 0.72, B) },
	sh = { poly(0.2, T, 0.2, B, 0.8, B, 0.8, T), line(0.5, T, 0.5, B) },
	shch = { poly(0.16, T, 0.16, 0.8, 0.86, 0.8, 0.86, 0.96), line(0.44, T, 0.44, 0.8), line(0.72, T, 0.72, 0.8) },
	hard = { join(poly(0.14, T, 0.32, T, 0.32, B, 0.54, B), arc(0.54, 0.67, 0.2, 0.21, 90, -90), poly(0.32, 0.46)) },
	y = { join(poly(0.2, T, 0.2, B, 0.4, B), arc(0.4, 0.67, 0.18, 0.21, 90, -90), poly(0.2, 0.46)), line(0.8, T, 0.8, B) },
	soft = { join(poly(0.32, T, 0.32, B, 0.52, B), arc(0.52, 0.67, 0.2, 0.21, 90, -90), poly(0.32, 0.46)) },
	e = { arc(0.46, 0.5, 0.29, 0.38, -135, 135), line(0.42, M, 0.75, M) },
	yu = { line(0.2, T, 0.2, B), line(0.2, M, 0.38, M), arc(0.6, 0.5, 0.22, 0.38, 0, 360) },
	ya = { join(poly(0.7, B, 0.7, T, 0.5, T), arc(0.5, 0.31, 0.2, 0.19, -90, -270), poly(0.7, M)), line(0.52, M, 0.28, B) },
}
-- stylua: ignore end

function StrokeGlyphs.has(letterId: string): boolean
	return SHAPES[letterId] ~= nil
end

function StrokeGlyphs.ids(): { string }
	local ids = {}
	for id in SHAPES do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

--[[
	Штрихи буквы, отражённые (если mirrored) и затем повёрнутые на rotation
	градусов по часовой стрелке — так же, как поворачивает Rotation в интерфейсе.
	Поворот вокруг центра квадрата, поэтому буква не выезжает за него.
	Годятся только углы, кратные 90: другие игре не нужны.
]]
function StrokeGlyphs.strokes(letterId: string, mirrored: boolean?, rotation: number?): { Stroke }
	local shape = SHAPES[letterId]
	assert(shape, `StrokeGlyphs: нет штрихов для буквы {letterId}`)
	local quarter = math.round((rotation or 0) / 90) % 4

	local result: { Stroke } = {}
	for _, stroke in shape do
		local out: Stroke = {}
		for _, point in stroke do
			local x, y = point[1], point[2]
			if mirrored then
				x = 1 - x
			end
			-- Поворот на 90° по часовой при y вниз: (x, y) → (1 − y, x).
			for _ = 1, quarter do
				x, y = 1 - y, x
			end
			table.insert(out, { x, y })
		end
		table.insert(result, out)
	end
	return result
end

local function distanceToSegment(px: number, py: number, a: Point, b: Point): number
	local dx, dy = b[1] - a[1], b[2] - a[2]
	local lengthSq = dx * dx + dy * dy
	local t = if lengthSq > 0 then math.clamp(((px - a[1]) * dx + (py - a[2]) * dy) / lengthSq, 0, 1) else 0
	local cx, cy = a[1] + dx * t - px, a[2] + dy * t - py
	return math.sqrt(cx * cx + cy * cy)
end

-- Клеток на сторону при сравнении рисунков: мельче глаз разницы не заметит.
local GRID = 32

-- Какие клетки сетки закрашены штрихами нужной толщины.
local function coverage(strokes: { Stroke }): { boolean }
	local half = StrokeGlyphs.WIDTH / 2
	local cells: { boolean } = {}
	for row = 0, GRID - 1 do
		for col = 0, GRID - 1 do
			local px, py = (col + 0.5) / GRID, (row + 0.5) / GRID
			local inked = false
			for _, stroke in strokes do
				for j = 1, math.max(1, #stroke - 1) do
					if distanceToSegment(px, py, stroke[j], stroke[j + 1] or stroke[j]) <= half then
						inked = true
						break
					end
				end
				if inked then
					break
				end
			end
			cells[row * GRID + col + 1] = inked
		end
	end
	return cells
end

--[[
	Насколько два рисунка отличаются: доля закрашенного, которое есть только
	в одном из них. Ноль — совпадают, единица — не пересекаются вовсе.

	Считается по закраске, а не по расстоянию между линиями: у И и её отражения
	все штрихи проходят через одни и те же места (диагональ упирается в стойки),
	и расстояние выходит нулевым, хотя это две разные буквы.
]]
function StrokeGlyphs.difference(a: { Stroke }, b: { Stroke }): number
	local left, right = coverage(a), coverage(b)
	local either, only = 0, 0
	for index = 1, GRID * GRID do
		if left[index] or right[index] then
			either += 1
			if left[index] ~= right[index] then
				only += 1
			end
		end
	end
	return if either > 0 then only / either else 0
end

--[[
	Отражённая буква заметно отличается от самой себя. А, О, Т, Ш симметричны —
	их отражение ничему не учит, и раунд с ним нечестен.
]]
--[[
	Симметричные буквы дают ровно ноль, самая «похожая на себя» несимметричная (Й) —
	около 0.3. Порог посередине, чтобы подправленный штрих не перекинул букву.
]]
StrokeGlyphs.MIRROR_MIN_DIFFERENCE = 0.15

local mirrorCache: { [string]: boolean } = {}

function StrokeGlyphs.mirrorDiffers(letterId: string): boolean
	if not SHAPES[letterId] then
		return false
	end
	if mirrorCache[letterId] == nil then
		local plain = StrokeGlyphs.strokes(letterId)
		local mirrored = StrokeGlyphs.strokes(letterId, true)
		mirrorCache[letterId] = StrokeGlyphs.difference(plain, mirrored) >= StrokeGlyphs.MIRROR_MIN_DIFFERENCE
	end
	return mirrorCache[letterId]
end

return StrokeGlyphs
