--!nocheck
-- Дома, крыши и заборы всех уровней на свободных участках: фасад и вид сбоку.
-- ZZ_ONLY=3 — снять только участок с уровнем 3.
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local BaseService = require(Services.BaseService)
	local ProfileService = require(Services.ProfileService)
	for _ = 1, 60 do
		if ProfileService.get(player) then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)

	-- Свой участок: часть категорий достроена, часть нет — подписи падов у калитки.
	ProfileService.update(player, function(p)
		p.base.house, p.base.roof, p.base.yard, p.base.fence = 3, 4, 2, 4
		p.base.furniture, p.base.decor = 4, 1
	end)
	BaseService.refresh(player)
	BaseService.sendHome(player)
	task.wait(4)
	local home = BaseService.plotCFrame(BaseService.plotOf(player).index)
	_G.ZZ_Shot(
		player,
		"yard_pads",
		CFrame.lookAt((home * CFrame.new(6, 9, -46)).Position, (home * CFrame.new(0, 3, -24)).Position),
		60
	)
	_G.ZZ_Shot(
		player,
		"yard_pads_near",
		CFrame.lookAt((home * CFrame.new(3, 6, -38)).Position, (home * CFrame.new(0, 3, -26)).Position),
		60
	)
	if workspace:GetAttribute("ZZ_Yard") then
		return
	end

	local only = workspace:GetAttribute("ZZ_Only")
	local levels = if only then { tonumber(only) } else { 1, 2, 3, 4 }
	-- Смешанный участок: башенка под соломой, забор первого уровня — крыша обязана сесть на любой дом.
	local sets = {}
	for _, level in levels do
		table.insert(sets, {
			name = `house_{level}`,
			levels = {
				house = level,
				roof = level,
				yard = level,
				fence = level,
				furniture = level,
				decor = level,
			},
		})
	end
	if not only then
		table.insert(sets, { name = "house_mixed", levels = { house = 4, roof = 1, yard = 2, fence = 1 } })
		table.insert(sets, { name = "house_noroof", levels = { house = 2, roof = 0, yard = 1, fence = 2 } })
	end

	for order, set in sets do
		local index = order + 1
		local ok, err = pcall(BaseService.preview, index, set.levels, {
			stageFlags = { 1, 2, 3, 4, 5 },
			letterRooms = { "a", "b", "v" },
			mathRooms = {},
			flags = 4,
			mathFlags = 2,
			arch = false,
			spire = false,
			countSpire = false,
		})
		note(`{set.name} on plot {index}: {ok} {err}`)
		local at = BaseService.plotCFrame(index)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = at * CFrame.new(0, 6, -40)
		end
		task.wait(3)
		_G.ZZ_Shot(
			player,
			`{set.name}_front`,
			CFrame.lookAt((at * CFrame.new(10, 13, -46)).Position, (at * CFrame.new(0, 8, 0)).Position),
			60
		)
		_G.ZZ_Shot(
			player,
			`{set.name}_corner`,
			CFrame.lookAt((at * CFrame.new(-40, 22, -30)).Position, (at * CFrame.new(0, 6, 0)).Position),
			60
		)
	end
end
