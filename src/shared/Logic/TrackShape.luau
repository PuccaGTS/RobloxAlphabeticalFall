--!strict
--[[
	Профиль трассы забега: повороты, зигзаги, горки и ямки.

	Раньше забег был прямой доской: пол, две стены и так до финиша. На первой
	проверке это назвали «уныло и очень легко», а беговые клетки между связками
	паркура — «длинно и пусто». Этот модуль отвечает за обе жалобы сразу.

	Главное правило: форма живёт ТОЛЬКО на беговых клетках. Препятствия, ворота,
	ряды букв, секрет и сохранки стоят на ровных прямых участках, как стояли.
	Так ни один элемент паркура не надо пересчитывать под наклон, ворота всегда
	видно заранее на ровном месте, а пустая пробежка превращается в горку,
	вираж или змейку — то, ради чего по ней и хочется бежать.

	Чистая логика без мира: план формы детерминирован по сиду (забег собирается
	из рецепта заново и обязан получиться тем же), а геометрия считается
	численно с шагом в один студ.
]]

local TrackShape = {}

export type Zone = { from: number, to: number, kind: string }
export type Span = { from: number, to: number }

--[[
	Числа подобраны под ребёнка на планшете. Горка в пять студов на отрезке
	в пятьдесят — уклон меньше двадцати градусов: забегается без прыжка.
	Поворот на двадцать градусов — заметный вираж, но не разворот: ворота после
	него видно так же, как на прямой.
]]
TrackShape.HILL_HEIGHT = 5
TrackShape.DIP_DEPTH = 3.5
TrackShape.WAVE_HEIGHT = 2.2
TrackShape.STEP_HEIGHT = 4 -- подъём или спуск, после которого трасса идёт на новой высоте
TrackShape.ZIGZAG_ANGLE = math.rad(18)
TrackShape.TURN_ANGLE = math.rad(20)

-- Коридор высот: трасса не уходит ни в облака, ни к дну.
TrackShape.MIN_HEIGHT = -8
TrackShape.MAX_HEIGHT = 14

--[[
	Насколько трасса может уйти вбок. Туннели разных игроков стоят рядом
	(Config/Tunnel.PLOT_SPACING), и вираж не должен завести один в другой.
	Повороты выбираются так, чтобы тянуть трассу обратно к оси.
]]
TrackShape.MAX_SIDE = 160

TrackShape.KINDS = { "hill", "dip", "wave", "zigzag", "turn", "climb", "descent" }

local function smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

--[[
	Что будет на каждой беговой клетке. Одна и та же форма дважды подряд
	не ставится: «ещё одна такая же горка» — это снова однообразие.

	Повороты и подъёмы меняют трассу насовсем, поэтому план ведёт учёт:
	куда смотрит трасса, на какой она высоте и насколько ушла вбок.
]]
function TrackShape.plan(runs: { Span }, seed: number): { Zone }
	local random = Random.new(seed)
	local zones: { Zone } = {}

	local heading = 0
	local height = 0
	local side = 0
	local previous: string? = nil

	for index, run in runs do
		local length = run.to - run.from
		-- Сколько трасса пройдёт до следующей клетки: на этом отрезке она держит направление.
		local nextRun = runs[index + 1]
		local ahead = if nextRun then nextRun.from - run.to else 150

		--[[
			Куда тянуть трассу. Повёрнутая трасса всегда поворачивает обратно,
			а прямая, ушедшая вбок, — к оси. Если трасса уже далеко и дальше
			уходит, поворот здесь обязателен, а не случаен: иначе на длинном
			уровне она дошла бы до соседнего туннеля.
		]]
		local backward = if heading > 0.01 then -1 elseif heading < -0.01 then 1 else 0
		local toCenter = if side > 0 then -1 else 1
		local drifting = math.abs(side) > TrackShape.MAX_SIDE * 0.5
			and (math.sign(heading) == math.sign(side) or math.abs(heading) < 0.01)
		local forceTurn = drifting and previous ~= "turn"

		local options: { string } = {}
		for _, kind in TrackShape.KINDS do
			local allowed = kind ~= previous
			if kind == "climb" then
				allowed = allowed and height + TrackShape.STEP_HEIGHT <= TrackShape.MAX_HEIGHT
			elseif kind == "descent" then
				allowed = allowed and height - TrackShape.STEP_HEIGHT >= TrackShape.MIN_HEIGHT
			elseif kind == "dip" then
				allowed = allowed and height - TrackShape.DIP_DEPTH >= TrackShape.MIN_HEIGHT
			elseif kind == "hill" then
				allowed = allowed and height + TrackShape.HILL_HEIGHT <= TrackShape.MAX_HEIGHT + 4
			end
			if forceTurn then
				allowed = kind == "turn"
			end
			if allowed then
				table.insert(options, kind)
			end
		end

		local kind = options[random:NextInteger(1, #options)]
		local zone: Zone = { from = run.from, to = run.to, kind = kind }

		local before = heading
		if kind == "turn" then
			local direction = backward
			if direction == 0 then
				direction = if math.abs(side) > 20
					then toCenter
					else (if random:NextInteger(1, 2) == 1 then -1 else 1)
			end
			zone.kind = if direction > 0 then "turn_right" else "turn_left"
			heading += direction * TrackShape.TURN_ANGLE
		elseif kind == "climb" then
			height += TrackShape.STEP_HEIGHT
		elseif kind == "descent" then
			height -= TrackShape.STEP_HEIGHT
		end

		-- Уход вбок: половина зоны по старому направлению, половина и пробежка — по новому.
		side += math.sin(before) * length / 2 + math.sin(heading) * (length / 2 + ahead)
		previous = kind
		table.insert(zones, zone)
	end

	return zones
end

--[[
	Высота и поворот трассы внутри одной зоны: t — доля пройденной зоны.
	Возвращает добавку к высоте и к направлению относительно начала зоны.
	Всё гладкое на краях: ни ступеньки в полу, ни излома в стене.
]]
local function shapeAt(kind: string, t: number): (number, number)
	if kind == "hill" then
		return TrackShape.HILL_HEIGHT * (1 - math.cos(2 * math.pi * t)) / 2, 0
	elseif kind == "dip" then
		return -TrackShape.DIP_DEPTH * (1 - math.cos(2 * math.pi * t)) / 2, 0
	elseif kind == "wave" then
		return TrackShape.WAVE_HEIGHT * (1 - math.cos(4 * math.pi * t)) / 2, 0
	elseif kind == "climb" then
		return TrackShape.STEP_HEIGHT * smoothstep(t), 0
	elseif kind == "descent" then
		return -TrackShape.STEP_HEIGHT * smoothstep(t), 0
	elseif kind == "zigzag" then
		-- Полный период синуса: трасса уходит в сторону и возвращается на ту же линию.
		return 0, TrackShape.ZIGZAG_ANGLE * math.sin(2 * math.pi * t)
	elseif kind == "turn_right" then
		return 0, TrackShape.TURN_ANGLE * smoothstep(t)
	elseif kind == "turn_left" then
		return 0, -TrackShape.TURN_ANGLE * smoothstep(t)
	end
	return 0, 0
end

-- Навсегда ли зона меняет трассу: после неё высота или направление остаются новыми.
local function persistent(kind: string): (number, number)
	if kind == "climb" then
		return TrackShape.STEP_HEIGHT, 0
	elseif kind == "descent" then
		return -TrackShape.STEP_HEIGHT, 0
	elseif kind == "turn_right" then
		return 0, TrackShape.TURN_ANGLE
	elseif kind == "turn_left" then
		return 0, -TrackShape.TURN_ANGLE
	end
	return 0, 0
end

export type Sampler = {
	length: number,
	-- Положение и поворот трассы на расстоянии z от старта, в системе начала забега.
	frame: (z: number) -> CFrame,
	-- То же без наклона: для всего, что должно стоять вертикально.
	flat: (z: number) -> CFrame,
	-- Идёт ли на этом месте зона формы (где пол режется на короткие куски).
	zoneAt: (z: number) -> Zone?,
	zones: { Zone },
}

--[[
	Геометрия трассы. Считается один раз на забег шагом в студ: позиция
	накапливается по направлению, высота берётся из формы зоны. Промежуточные
	значения интерполируются.

	Оси: трасса идёт в сторону −Z системы старта, +X — вправо, +Y — вверх.
	Положительный угол поворачивает вправо.
]]
function TrackShape.sampler(zones: { Zone }, length: number): Sampler
	local count = math.ceil(length) + 2
	local xs: { number } = table.create(count + 1, 0)
	local ys: { number } = table.create(count + 1, 0)
	local zs: { number } = table.create(count + 1, 0)
	local headings: { number } = table.create(count + 1, 0)

	local baseHeight = 0
	local baseHeading = 0
	local zoneIndex = 1
	local x, forward = 0, 0

	for step = 0, count do
		local z = step
		while zones[zoneIndex] and z >= zones[zoneIndex].to do
			local dh, da = persistent(zones[zoneIndex].kind)
			baseHeight += dh
			baseHeading += da
			zoneIndex += 1
		end

		local height, heading = baseHeight, baseHeading
		local zone = zones[zoneIndex]
		if zone and z >= zone.from then
			local t = (z - zone.from) / math.max(zone.to - zone.from, 1)
			local dh, da = shapeAt(zone.kind, math.clamp(t, 0, 1))
			height += dh
			heading += da
		end

		xs[step + 1] = x
		ys[step + 1] = height
		zs[step + 1] = forward
		headings[step + 1] = heading

		x += math.sin(heading)
		forward += math.cos(heading)
	end

	local function sample(z: number): (Vector3, number, number)
		local position = math.clamp(z, 0, count - 1)
		local i = math.floor(position)
		local f = position - i
		local a, b = i + 1, i + 2
		local px = xs[a] + (xs[b] - xs[a]) * f
		local py = ys[a] + (ys[b] - ys[a]) * f
		local pz = zs[a] + (zs[b] - zs[a]) * f
		local heading = headings[a] + (headings[b] - headings[a]) * f
		local pitch = math.atan(ys[b] - ys[a])
		return Vector3.new(px, py, -pz), heading, pitch
	end

	local function flat(z: number): CFrame
		local position, heading = sample(z)
		return CFrame.new(position) * CFrame.Angles(0, -heading, 0)
	end

	local function frame(z: number): CFrame
		local position, heading, pitch = sample(z)
		return CFrame.new(position) * CFrame.Angles(0, -heading, 0) * CFrame.Angles(pitch, 0, 0)
	end

	local function zoneAt(z: number): Zone?
		for _, zone in zones do
			if z >= zone.from and z < zone.to then
				return zone
			end
		end
		return nil
	end

	return {
		length = length,
		frame = frame,
		flat = flat,
		zoneAt = zoneAt,
		zones = zones,
	}
end

return TrackShape
