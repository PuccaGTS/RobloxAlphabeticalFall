--!strict
--[[
	Выдаёт значки Roblox (Config/Badges), как только ребёнок их заработал.
	Смотрит на профиль после каждого изменения (ProfileService.onChanged)
	и выдаёт то, что заработано и ещё не выдано. Вызовы к Roblox — в pcall
	и в отдельной задаче: сбой сети не мешает игре, значок догонит в следующий раз.
]]

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Badges = require(ReplicatedStorage.Shared.Config.Badges)
local ProfileService = require(script.Parent.ProfileService)

local BadgeAwardService = {}

-- Что уже выдано или выдаётся в эту сессию: не спрашиваем Roblox на каждое изменение профиля.
local given: { [Player]: { [string]: boolean } } = {}

local function award(player: Player, badge: Badges.Badge)
	local id = badge.badgeId :: number
	local ok, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, id)
	if ok and has then
		return
	end
	local awarded, err = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, id)
	if not awarded then
		warn(`[Badges] {badge.key} для {player.Name} не выдан: {err}`)
		-- Попробуем снова при следующем изменении профиля.
		local mine = given[player]
		if mine then
			mine[badge.key] = nil
		end
	end
end

local function check(player: Player, profile: any)
	local mine = given[player]
	if not mine then
		mine = {}
		given[player] = mine
	end
	local earned = Badges.earned(profile)
	for _, badge in Badges.LIST do
		if badge.badgeId and earned[badge.key] and not mine[badge.key] then
			mine[badge.key] = true
			task.spawn(award, player, badge)
		end
	end
end

function BadgeAwardService.start()
	ProfileService.onChanged(check)
	Players.PlayerRemoving:Connect(function(player)
		given[player] = nil
	end)
end

return BadgeAwardService
