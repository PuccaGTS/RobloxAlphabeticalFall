--!nocheck
--[[
	Форма и краска построек: свой участок, забор и крыша каждой формы, дом
	и машинка в разных красках. Плюс экран выбора, открытый с пада забора.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local BaseService = require(Services.BaseService)
	local ProfileService = require(Services.ProfileService)
	local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
	for _ = 1, 60 do
		if ProfileService.get(player) then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)

	ProfileService.update(player, function(p)
		p.base.house, p.base.roof, p.base.yard, p.base.fence = 2, 2, 2, 2
		p.base.transport, p.base.playground = 2, 2
		p.stars = 120
	end)
	BaseService.refresh(player)
	ProfileService.pushSnapshot(player)
	BaseService.sendHome(player)
	task.wait(4)
	local home = BaseService.plotCFrame(BaseService.plotOf(player).index)
	local front =
		CFrame.lookAt((home * CFrame.new(14, 14, -50)).Position, (home * CFrame.new(0, 6, 0)).Position)

	local looks = {
		{ "style_default", {} },
		{ "style_pointed_red", { fence = { 2, 2 }, roof = { 2, 1 }, house = { 2, 6 } } },
		{
			"style_round_green",
			{ fence = { 3, 5 }, roof = { 3, 7 }, house = { 3, 4 }, transport = { 1, 8 } },
		},
	}
	for _, look in looks do
		for id, style in look[2] do
			local ok = BaseService.setStyle(player, id, style[1], style[2])
			if not ok then
				note(`setStyle {id} refused`)
			end
			task.wait(0.3)
		end
		task.wait(1.5)
		_G.ZZ_Shot(player, look[1], front, 60)
	end

	-- Уровни забора с острой формой: верхушки должны сесть на любой уровень.
	for level = 1, 4 do
		ProfileService.update(player, function(p)
			p.base.fence = level
		end)
		BaseService.refresh(player)
		task.wait(1.5)
		_G.ZZ_Shot(
			player,
			`style_fence_{level}`,
			CFrame.lookAt(
				(home * CFrame.new(-22, 6, -44)).Position,
				(home * CFrame.new(-26, 2, -28)).Position
			),
			60
		)
	end

	-- Окна дома каждой формы на каждом уровне дома: круглые и арочные садятся в проём.
	ProfileService.update(player, function(p)
		p.base.roof = 3
	end)
	for level = 1, 4 do
		for shape = 1, 3 do
			ProfileService.update(player, function(p)
				p.base.house = level
			end)
			BaseService.setStyle(player, "house", shape, 1)
			task.wait(1.2)
			_G.ZZ_Shot(
				player,
				`style_house_{level}_{shape}`,
				CFrame.lookAt((home * CFrame.new(9, 10, -30)).Position, (home * CFrame.new(0, 7, 0)).Position),
				60
			)
		end
	end

	-- Вторая форма наборов: самокат… тарелка, шалаш… колесо обозрения.
	ProfileService.update(player, function(p)
		p.base.transport, p.base.playground = 4, 4
	end)
	for _, id in { "transport", "playground" } do
		BaseService.setStyle(player, id, 2, 1)
		task.wait(1.5)
		for level, spot in require(ReplicatedStorage.Shared.Config.Base).expect(id).spots do
			local at = home * CFrame.new(spot.x, 3, spot.z)
			local eye = at * CFrame.new(if spot.x > 0 then -9 else 9, 5, -7)
			_G.ZZ_Shot(player, `style_{id}_2_{level}`, CFrame.lookAt(eye.Position, at.Position), 60)
		end
	end
	-- Краска на второй форме: ложится на кузов и крылья, а не на что попало.
	BaseService.setStyle(player, "transport", 2, 6)
	task.wait(1.5)
	local plane = home * CFrame.new(23, 3, -3)
	_G.ZZ_Shot(
		player,
		"style_transport_2_paint",
		CFrame.lookAt((plane * CFrame.new(-9, 5, -7)).Position, plane.Position),
		60
	)

	-- Экран выбора, как его видит ребёнок у пада забора.
	RemoteDefs.event("OpenUI"):FireClient(player, "build", "fence")
	task.wait(1)
	_G.ZZ_Shot(player, "ui_build_picker", front, 60)
	RemoteDefs.event("OpenUI"):FireClient(player, "build", "house")
	task.wait(1)
	_G.ZZ_Shot(player, "ui_build_picker_house", front, 60)
	RemoteDefs.event("OpenUI"):FireClient(player, "build", "transport")
	task.wait(1)
	_G.ZZ_Shot(player, "ui_build_picker_transport", front, 60)
	note(`style saved: {game:GetService("HttpService"):JSONEncode(ProfileService.get(player).baseStyle)}`)
end
