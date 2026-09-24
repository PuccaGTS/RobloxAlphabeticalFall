--!nocheck
--[[
	Почта от буквят (Logic/Mail): три освоенные буквы — ящик у калитки с поднятым
	флажком и 💌; касание ящика — открытка на экране; второй раз — альбом.
	Снимки ui_* — вместе с интерфейсом.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local BaseService = require(Services.BaseService)
	local MailService = require(Services.MailService)
	local PetService = require(Services.PetService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local MasteryRules = require(ReplicatedStorage.Shared.Logic.MasteryRules)
	local Mailbox = require(ServerScriptService.Server.World.Mailbox)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)

	ProfileService.update(player, function(p)
		p.base.house, p.base.roof, p.base.yard, p.base.fence = 2, 2, 1, 2
		for _, id in { "a", "b", "v" } do
			local progress = MasteryRules.newProgress(os.time())
			progress.mastery = MasteryRules.MASTERED
			p.letters[id] = progress
		end
		p.mail = { seen = {} }
	end)
	BaseService.refresh(player)
	PetService.refresh(player)
	MailService.refresh(player)
	ProfileService.pushSnapshot(player)
	note(`unread attribute: {player:GetAttribute("MailUnread")}`)

	local home = BaseService.plotCFrame(BaseService.plotOf(player).index)
	local box = home * Mailbox.OFFSET
	Teleport.to(player, home * CFrame.new(0, 4, -44))
	task.wait(4)
	_G.ZZ_Shot(
		player,
		"mail_box_flag",
		CFrame.lookAt((box * CFrame.new(6.5, 5.5, -6)).Position, (box * CFrame.new(0, 4.5, 0)).Position),
		60
	)

	-- Подойти к ящику: касание открывает почту у хозяина.
	Teleport.to(player, box * CFrame.new(0, 3.5, -1.8) * CFrame.Angles(0, math.pi, 0))
	task.wait(3)
	note(
		`after touch: unread {player:GetAttribute("MailUnread")}, seen {#ProfileService.get(player).mail.seen}`
	)
	local root = player.Character.HumanoidRootPart
	_G.ZZ_Shot(player, "ui_mail_card", CFrame.lookAt(root.Position + Vector3.new(6, 4, 6), root.Position), 60)

	-- Второй раз новых нет — сразу альбом.
	MailService.open(player)
	task.wait(1)
	_G.ZZ_Shot(
		player,
		"ui_mail_album",
		CFrame.lookAt(root.Position + Vector3.new(6, 4, 6), root.Position),
		60
	)
	_G.ZZ_Shot(
		player,
		"mail_box_read",
		CFrame.lookAt((box * CFrame.new(6.5, 5.5, -6)).Position, (box * CFrame.new(0, 4.5, 0)).Position),
		60
	)
end
