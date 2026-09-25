--!nocheck
--[[
	Забег мира букв глазами ребёнка: станция буквы и каждый аттракцион.
	ZZ_ONLY=7 — какой уровень пути (по умолчанию 7: там есть все аттракционы).

	Кроме снимков проверяет механику: станция открывается, когда встаёшь в круг;
	лава и валун возвращают к флажку.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local ChallengeService = require(Services.ChallengeService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local Attractions = require(game:GetService("ReplicatedStorage").Shared.Config.Attractions)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)

	local level = tonumber(workspace:GetAttribute("ZZ_Only")) or 7
	ProfileService.update(player, function(p)
		p.levels = p.levels or {}
		p.levels.letters = level - 1
		p.runs = {}
	end)
	ChallengeService.startFor(player, "tunnel_run")
	task.wait(6)
	local model = workspace.Tunnels:FindFirstChild(`Tunnel_{player.UserId}`)
	if not model then
		note("NO TUNNEL")
		return
	end
	local root = player.Character.HumanoidRootPart
	note(`level {level} tunnel parts {#model:GetDescendants()}`)
	-- Финал уровня: золотая арка перед последними аттракционами.
	local bossBeam = model:FindFirstChild("BossBeam")
	note(`boss arch: {bossBeam and "yes" or "no"}`)
	if bossBeam then
		Teleport.to(player, CFrame.new(bossBeam.Position + Vector3.new(0, -8, 0) + bossBeam.CFrame.LookVector * 20))
		task.wait(2)
		_G.ZZ_Shot(
			player,
			"run_boss_arch",
			CFrame.lookAt(
				bossBeam.Position + bossBeam.CFrame.LookVector * 30 + Vector3.new(0, -4, 0),
				bossBeam.Position - bossBeam.CFrame.LookVector * 30 + Vector3.new(0, -8, 0)
			),
			70
		)
		task.wait(5)
	end

	local function pivotOf(name)
		local found = model:FindFirstChild(name, true)
		if not found then
			return nil
		end
		return if found:IsA("Model") then found:GetPivot() else found.CFrame
	end

	-- Станция: вид от входа, потом шаг в круг.
	local letter = pivotOf("StationLetter_1")
	if letter then
		local look = letter.Position
		local eye = (letter * CFrame.new(0, 2, -22)).Position
		_G.ZZ_Shot(player, "run_station", CFrame.lookAt(eye, look), 70)
		local ring = pivotOf("StationRing_1")
		Teleport.to(
			player,
			CFrame.new(ring.Position + Vector3.new(0, 4, 0)) * letter.Rotation * CFrame.Angles(0, math.pi, 0)
		)
		task.wait(3.5)
		note(`station barrier after touch: {model:FindFirstChild("StationBarrier_1", true) ~= nil}`)
		_G.ZZ_Shot(player, "run_station_open", CFrame.lookAt(eye, look + Vector3.new(0, 6, 0)), 70)
	else
		note("NO STATION")
	end

	-- Где движущаяся деталь сейчас у клиента: сервер держит её в исходном месте.
	local function livePosition(p)
		local base = p:GetAttribute("Base")
		local now = workspace:GetServerTimeNow()
		local period = p:GetAttribute("Period") or 1
		local phase = p:GetAttribute("Phase") or 0
		local kind = p:GetAttribute("Mover")
		if kind == "slide" then
			local x = (p:GetAttribute("Travel") or 0) * math.sin(2 * math.pi * (now + phase) / period)
			return (base * CFrame.new(x, 0, 0)).Position
		elseif kind == "lift" then
			local y = (p:GetAttribute("Travel") or 0) * math.sin(2 * math.pi * (now + phase) / period)
			return (base * CFrame.new(0, y, 0)).Position
		elseif kind == "pendulum" then
			local angle = (p:GetAttribute("Amplitude") or 0) * math.sin(2 * math.pi * (now + phase) / period)
			return (base * CFrame.Angles(angle, 0, 0) * CFrame.new(0, -(p:GetAttribute("Hang") or 0), 0)).Position
		end
		return p.Position
	end

	-- Поставить прямо на деталь: сначала перенос (он держит якорем и грузит место), потом точно.
	local function standOn(p)
		Teleport.to(player, CFrame.new(livePosition(p) + Vector3.new(0, 4, 0)))
		local r = player.Character.HumanoidRootPart
		for _ = 1, 40 do
			if not r.Anchored then
				break
			end
			task.wait(0.1)
		end
		task.wait(0.3)
		r.AssemblyLinearVelocity = Vector3.zero
		r.CFrame = CFrame.new(livePosition(p) + Vector3.new(0, p.Size.Y / 2 + 3, 0)) * r.CFrame.Rotation
		return r
	end

	for _, child in model:GetChildren() do
		local index, id = string.match(child.Name, "^Attraction_(%d+)_(%a+)$")
		if not index then
			continue
		end
		local pole = pivotOf(`FlagPole_{index}`)
		local center, size = child:GetBoundingBox()
		if not pole then
			continue
		end
		local only = workspace:GetAttribute("ZZ_Ride")
		if only and not string.find("," .. only .. ",", "," .. id .. ",", 1, true) then
			continue
		end
		-- Вид от флажка: чуть сверху и сзади, на середину аттракциона.
		local forward = (center.Position - pole.Position) * Vector3.new(1, 0, 1)
		local dir = forward.Unit
		-- С оси трассы: флажок стоит у бортика, и с него видна только стена.
		local axis = Vector3.new(center.Position.X, pole.Position.Y, center.Position.Z)
			- dir * ((center.Position - pole.Position) * Vector3.new(1, 0, 1)).Magnitude
		local eye = axis - dir * 8 + Vector3.new(0, 13, 0)
		Teleport.to(player, CFrame.new(pole.Position + Vector3.new(0, 1, 0) - dir * 6))
		task.wait(2)
		_G.ZZ_Shot(player, `run_{index}_{id}`, CFrame.lookAt(eye, center.Position), 70)
		note(`{id} #{index}: length {math.floor(size.Z)} center {center.Position}`)

		-- Облачко должно везти: встать на первое и посмотреть, не соскользнёт ли.
		if id == "clouds" then
			local cloud = child:FindFirstChild(`Cloud_{index}_1`)
			local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if cloud and r then
				Teleport.to(player, CFrame.new(livePosition(cloud) + Vector3.new(0, 4, 0)))
				local startX = r.Position
				local worst = 0
				for _ = 1, 16 do
					task.wait(0.25)
					local offset = (r.Position - livePosition(cloud)) * Vector3.new(1, 0, 1)
					worst = math.max(worst, offset.Magnitude)
				end
				note(
					string.format(
						"   clouds: rode %.1f studs, farthest from cloud centre %.1f (cloud radius %.1f), y above %.1f",
						((r.Position - startX) * Vector3.new(1, 0, 1)).Magnitude,
						worst,
						cloud.Size.Y / 2,
						r.Position.Y - livePosition(cloud).Y
					)
				)
				_G.ZZ_Shot(
					player,
					`run_{index}_clouds_ride`,
					CFrame.lookAt(r.Position + Vector3.new(-12, 8, 14), r.Position),
					70
				)
			end
		end

		-- Лента должна тащить: встать на середину первой и не двигаться.
		if id == "belts" then
			local beltPart = child:FindFirstChild(`Belt_{index}_1`)
			local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if beltPart and r then
				standOn(beltPart)
				local trace = {}
				for _ = 1, 8 do
					local rel = beltPart.CFrame:PointToObjectSpace(r.Position)
					table.insert(trace, string.format("(%.1f,%.1f,%.1f)", rel.X, rel.Y, rel.Z))
					task.wait(0.1)
				end
				note("   belts trace (x along belt, y up): " .. table.concat(trace, " "))
				_G.ZZ_Shot(
					player,
					`run_{index}_belts_on`,
					CFrame.lookAt(r.Position + Vector3.new(-10, 9, 14), r.Position),
					70
				)
			end
		end

		-- Доска качелей должна везти: встать на первую и посмотреть, не соскользнёт ли.
		if id == "swings" then
			local seat = child:FindFirstChild(`Swing_{index}_1`)
			local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if seat and r then
				standOn(seat)
				local worst, travelled, last = 0, 0, r.Position
				for _ = 1, 16 do
					task.wait(0.25)
					local offset = (r.Position - livePosition(seat)) * Vector3.new(1, 0, 1)
					worst = math.max(worst, offset.Magnitude)
					travelled += ((r.Position - last) * Vector3.new(1, 0, 1)).Magnitude
					last = r.Position
				end
				note(
					string.format(
						"   swings: rode %.1f studs, farthest from board centre %.1f (half board %.1f), y above %.1f",
						travelled,
						worst,
						seat.Size.X / 2,
						r.Position.Y - livePosition(seat).Y
					)
				)
				_G.ZZ_Shot(
					player,
					`run_{index}_swings_ride`,
					CFrame.lookAt(r.Position + Vector3.new(-16, 6, 4), r.Position),
					70
				)
			end
		end

		-- Батут должен подбросить выше островка: встать на первый и смотреть высоту.
		if id == "bounce" then
			local pad = child:FindFirstChild(`BouncePad_{index}_1`)
			local island = child:FindFirstChild(`BounceIsland_{index}_1`)
			if pad and island then
				local r = standOn(pad)
				local peak = -math.huge
				for step = 1, 60 do
					task.wait(0.05)
					peak = math.max(peak, r.Position.Y)
					if step == 7 then
						_G.ZZ_Shot(
							player,
							`run_{index}_bounce_air`,
							CFrame.lookAt(r.Position + Vector3.new(-18, 2, 10), r.Position),
							70
						)
					end
				end
				note(
					string.format(
						"   bounce: root peak %.1f above pad, island top %.1f above pad",
						peak - pad.Position.Y,
						island.Position.Y + 0.6 - pad.Position.Y
					)
				)
			end
		end

		-- Буквенные кочки: верная держит и называет букву, чужая уходит вниз.
		if id == "letterstones" then
			local right, wrong
			for _, stone in child:GetChildren() do
				if string.sub(stone.Name, 1, 6) == "Stone_" and stone:IsA("BasePart") then
					local glyph = stone:FindFirstChild("Glyph")
					local label = glyph and glyph:FindFirstChildWhichIsA("TextLabel", true)
					if stone:GetAttribute("Mover") == "letterstone" then
						right = right or stone
					else
						wrong = wrong or stone
					end
					if label and stone == right then
						note(`   letterstones: right glyph {label.Text}`)
					end
				end
			end
			local first = child:FindFirstChild(`Stone_{index}_2`)
			if first then
				_G.ZZ_Shot(
					player,
					`run_{index}_letterstones_close`,
					CFrame.lookAt(
						first.Position + Vector3.new(0, 9, 14),
						first.Position + Vector3.new(0, 0, -8)
					),
					70
				)
				task.wait(4.5)
			end
			for label, stone in { right = right, wrong = wrong } do
				if stone then
					local r = standOn(stone)
					local startY = r.Position.Y
					local lowest = startY
					for _ = 1, 25 do
						task.wait(0.1)
						lowest = math.min(lowest, r.Position.Y)
					end
					note(
						string.format("   letterstones %s: stood at %.1f, lowest %.1f", label, startY, lowest)
					)
				end
			end
		end

		-- Мост из букв: верная доска держит и кладёт настил, чужая уходит вниз.
		if id == "letterbridge" then
			local rights, wrong = {}, nil
			for _, board in child:GetChildren() do
				if string.sub(board.Name, 1, 11) == "BridgeStep_" and board:IsA("BasePart") then
					local label = board:FindFirstChild("Glyph")
					label = label and label:FindFirstChildWhichIsA("TextLabel", true)
					if board:GetAttribute("Mover") == "bridgestep" then
						rights[board:GetAttribute("Row")] = board
						note(`   letterbridge: row {board:GetAttribute("Row")} right {label and label.Text}`)
					else
						wrong = wrong or board
					end
				end
			end
			local start = child:FindFirstChild(`BridgeStart_{index}`)
			local startLabel = start and start:FindFirstChild("Glyph")
			startLabel = startLabel and startLabel:FindFirstChildWhichIsA("TextLabel", true)
			note(`   letterbridge: start {startLabel and startLabel.Text}`)
			for row = 1, #rights do
				standOn(rights[row])
				task.wait(1.2)
			end
			local last = rights[#rights]
			if start and last then
				_G.ZZ_Shot(
					player,
					`run_{index}_letterbridge_built`,
					CFrame.lookAt(
						start.Position + Vector3.new(0, 16, 0) - (last.Position - start.Position).Unit * 10,
						last.Position
					),
					70
				)
				task.wait(4.5)
			end
			if wrong then
				local r = standOn(wrong)
				local startY = r.Position.Y
				local lowest = startY
				for _ = 1, 25 do
					task.wait(0.1)
					lowest = math.min(lowest, r.Position.Y)
				end
				note(string.format("   letterbridge wrong: stood at %.1f, lowest %.1f", startY, lowest))
			end
		end

		-- Печенька должна раскрошиться под стоящим: встать и подождать.
		if id == "cookies" then
			local cookie = child:FindFirstChild(`Cookie_{index}_2`)
			if cookie then
				local r = standOn(cookie)
				local startY = r.Position.Y
				task.wait(0.5)
				_G.ZZ_Shot(
					player,
					`run_{index}_cookies_crack`,
					CFrame.lookAt(r.Position + Vector3.new(-12, 7, 10), r.Position),
					70
				)
				local lowest = startY
				for _ = 1, 30 do
					task.wait(0.1)
					lowest = math.min(lowest, r.Position.Y)
				end
				note(string.format("   cookies: stood at %.1f, fell to %.1f", startY, lowest))
			end
		end

		-- Ветер должен сносить с открытого мостика, а за щитом — нет.
		if id == "wind" then
			local zone = child:FindFirstChild(`WindZone_{index}_1`)
			local deck = child:FindFirstChild(`WindBridge_{index}_1`)
			local cloud = child:FindFirstChild(`WindCloud_{index}_1`)
			if zone and deck and cloud then
				local period = zone:GetAttribute("Period")
				local gust = zone:GetAttribute("Gust")
				local phase = zone:GetAttribute("Phase")
				local startAt = period - gust
				local function cycle()
					return (workspace:GetServerTimeNow() + phase) % period
				end
				-- Дождаться момента цикла (с запасом lead секунд до него).
				local function waitFor(moment, lead)
					local target = (moment - lead) % period
					while math.abs(cycle() - target) > 0.05 do
						task.wait(0.02)
					end
				end
				local face = cloud:GetAttribute("Base")
				local view = CFrame.lookAt(
					(deck.CFrame * CFrame.new(0, 7, 14)).Position
						+ (face.Position - deck.Position) * Vector3.new(-0.9, 0, -0.9),
					face.Position:Lerp(deck.Position, 0.5)
				)
				-- Снимок уходит примерно через 4 с после вызова: целимся заранее.
				waitFor(startAt - 0.4, 4.1)
				_G.ZZ_Shot(player, `run_{index}_wind_puff`, view, 70)
				waitFor(startAt + gust * 0.5, 4.1)
				_G.ZZ_Shot(player, `run_{index}_wind_blow`, view, 70)

				local function trial(label, offset)
					waitFor(0.2, 0)
					local r = standOn(deck)
					r.CFrame = deck.CFrame * offset * CFrame.new(0, deck.Size.Y / 2 + 3, 0)
					local start = zone.CFrame:PointToObjectSpace(r.Position)
					local drift, lowest = 0, 0
					local deadline = os.clock() + period + 0.5
					while os.clock() < deadline do
						task.wait(0.05)
						local now = zone.CFrame:PointToObjectSpace(r.Position)
						drift = math.max(drift, math.abs(now.X - start.X))
						lowest = math.min(lowest, now.Y - start.Y)
					end
					note(
						string.format(
							"   wind %s: drift %.1f across, lowest %.1f (bridge half %.1f)",
							label,
							drift,
							lowest,
							deck.Size.X / 2
						)
					)
				end
				-- Открытое место: четверть участка до щита, посреди мостика.
				trial("open", CFrame.new(0, 0, deck.Size.Z * 0.3))
				-- За щитом: вплотную к нему с подветренной стороны.
				local shelter = child:FindFirstChild(`WindShelter_{index}_1`)
				if shelter then
					local rel = deck.CFrame:PointToObjectSpace(shelter.Position)
					trial("shelter", CFrame.new(rel.X - math.sign(rel.X) * 1.8, 0, rel.Z))
				end
			end
		end

		-- Подъёмник должен везти стоящего вверх и вниз, а горка — спускать к полу выхода.
		if id == "lifts" then
			local deck = child:FindFirstChild(`LiftDeck_{index}_1`)
			local balcony = child:FindFirstChild(`LiftBalcony_{index}`)
			if deck and balcony then
				local r = standOn(deck)
				local low, high, worst = math.huge, -math.huge, 0
				local deadline = os.clock() + (deck:GetAttribute("Period") or 5) + 0.3
				while os.clock() < deadline do
					task.wait(0.1)
					local live = livePosition(deck)
					low = math.min(low, r.Position.Y)
					high = math.max(high, r.Position.Y)
					worst = math.max(worst, math.abs(r.Position.Y - (live.Y + deck.Size.X / 2 + 3)))
				end
				note(
					string.format(
						"   lifts: rode %.1f..%.1f (travel %.1f), worst off-deck %.1f",
						low,
						high,
						deck:GetAttribute("Travel") or 0,
						worst
					)
				)
				local view = CFrame.lookAt(
					r.Position
						+ (balcony.Position - r.Position) * Vector3.new(0.3, 0, 0.3)
						+ Vector3.new(16, 8, 0),
					balcony.Position:Lerp(r.Position, 0.5)
				)
				_G.ZZ_Shot(player, `run_{index}_lifts_ride`, view, 70)
				task.wait(4.5)
				-- На балкон и вперёд, на горку: съехать должен к полу выхода.
				Teleport.to(player, balcony.CFrame * CFrame.new(0, 4, 0))
				for _ = 1, 40 do
					if not r.Anchored then
						break
					end
					task.wait(0.1)
				end
				local startY = r.Position.Y
				local ahead = balcony.CFrame.LookVector
				-- То же значение второй раз сигнала не даёт: сначала сбросить.
				workspace:SetAttribute("ZZ_Walk", nil)
				task.wait(0.3)
				workspace:SetAttribute("ZZ_Walk", string.format("%.2f,%.2f,6", ahead.X, ahead.Z))
				local lowest = startY
				for _ = 1, 60 do
					task.wait(0.1)
					lowest = math.min(lowest, r.Position.Y)
				end
				note(
					string.format(
						"   lifts slide: from %.1f down to %.1f (floor ~%.1f)",
						startY,
						lowest,
						pole.Position.Y
					)
				)
			end
		end

		-- Механика: поставить в опасное место и посмотреть, вернёт ли к флажку.
		if id == "lava" or id == "boulders" or id == "spinner" or id == "hammers" or id == "stompers" then
			-- Сначала через флажок: он и есть точка возврата.
			local trigger = model:FindFirstChild(`FlagTrigger_{index}`)
			if trigger then
				Teleport.to(player, CFrame.new(trigger.Position))
			end
			task.wait(1.5)
			local danger = center.Position + Vector3.new(0, 4, 0)
			if id == "spinner" then
				danger = center.Position + dir * 7 + Vector3.new(0, 4, 0)
			elseif id == "stompers" then
				-- Прямо под кубиком: он топнет в течение цикла.
				local cube = child:FindFirstChild(`Stomper_{index}_2`)
				danger = cube:GetAttribute("Base").Position
					+ Vector3.new(0, -Attractions.STOMPER_SIZE / 2 + 3, 0)
				task.delay(1.2, function()
					_G.ZZ_Shot(
						player,
						`run_{index}_stompers_under`,
						CFrame.lookAt(danger + Vector3.new(-16, 8, 14), danger + Vector3.new(0, 6, 0)),
						70
					)
				end)
			elseif id == "lava" then
				-- Середина между колонками кочек — там лава.
				danger = Vector3.new(center.Position.X, center.Position.Y - size.Y / 2 + 4, center.Position.Z)
			end
			Teleport.to(player, CFrame.new(danger))
			local returned = false
			for _ = 1, 40 do
				task.wait(0.25)
				local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local home = if trigger then trigger.Position else pole.Position
				if r and (r.Position - home).Magnitude < 8 then
					returned = true
					break
				end
			end
			note(`   {id}: returned to flag = {returned}`)
		end
	end
	ChallengeService.abort(player)
end
