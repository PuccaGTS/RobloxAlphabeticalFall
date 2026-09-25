--!nocheck
--[[
	Обзор уровня пути сверху: что стоит на трассе и в каком порядке.
	ZZ_ONLY=1 — какой уровень (по умолчанию первый). Пишет список деталей
	верхнего уровня модели по порядку вдоль трассы и снимает её кусками.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local ChallengeService = require(Services.ChallengeService)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)

	local level = tonumber(workspace:GetAttribute("ZZ_Only")) or 1
	ProfileService.update(player, function(p)
		p.levels = p.levels or {}
		p.levels.letters = level - 1
		p.runs = {}
	end)
	local root = player.Character.HumanoidRootPart
	local before = root.Position
	ChallengeService.startFor(player, "tunnel_run")
	task.wait(6)
	local model = workspace.Tunnels:FindFirstChild(`Tunnel_{player.UserId}`)
	if not model then
		note("NO TUNNEL")
		return
	end
	local start = root.Position
	note(`level {level} parts {#model:GetDescendants()} start {start} (was {before})`)

	-- Трасса идёт по -Z от начала (makePath), с виражами: считаем расстояние от старта.
	local rows = {}
	for _, child in model:GetChildren() do
		local pos
		if child:IsA("Model") then
			pos = child:GetPivot().Position
		elseif child:IsA("BasePart") then
			pos = child.Position
		end
		if pos then
			local d = ((pos - start) * Vector3.new(1, 0, 1)).Magnitude
			table.insert(rows, { d = d, name = child.Name, pos = pos })
		end
	end
	table.sort(rows, function(a, b)
		return a.d < b.d
	end)
	local skip = { Floor = true, Wall = true, Rail = true, Scenery = true }
	local line = {}
	for _, row in rows do
		local base = string.match(row.name, "^(%a+)") or row.name
		if not skip[base] then
			table.insert(line, string.format("%d:%s", math.floor(row.d), row.name))
		end
		if #line >= 12 then
			note(table.concat(line, "  "))
			line = {}
		end
	end
	if #line > 0 then
		note(table.concat(line, "  "))
	end

	-- Снимки: камера сзади-сверху, шаг 45 студов вдоль найденных точек.
	local far = rows[#rows].d
	local shots = 0
	local nextD = 0
	for _, row in rows do
		if row.d >= nextD and shots < 14 then
			local ahead
			for _, other in rows do
				if other.d > row.d + 30 then
					ahead = other.pos
					break
				end
			end
			if ahead then
				local dir = ((ahead - row.pos) * Vector3.new(1, 0, 1)).Unit
				local eye = row.pos - dir * 18 + Vector3.new(0, 22, 0)
				shots += 1
				_G.ZZ_Shot(
					player,
					string.format("tour_%02d", shots),
					CFrame.lookAt(eye, row.pos + dir * 25),
					70
				)
				task.wait(4.5)
			end
			nextD = row.d + 45
		end
	end
	note(`track length ~{math.floor(far)} shots {shots}`)
end
