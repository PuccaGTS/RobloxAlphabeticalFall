--!nonstrict
--[[
	Почта от буквят (Logic/Mail): освоил букву — открытка в ящике у калитки.

	Атрибут игрока MailUnread — сколько открыток ждёт; по нему клиент каждого
	поднимает флажок на ящике хозяина и зажигает 💌 (MailController). Открыть
	ящик может только хозяин — касанием или подсказкой. Сервер отмечает
	открытки прочитанными и присылает хозяину, какие пришли новые и какие
	собраны в альбом (событие MailOpened). Что показывать, клиент не выбирает.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mail = require(Shared.Logic.Mail)
local MasteryRules = require(Shared.Logic.MasteryRules)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local ProgressService = require(script.Parent.ProgressService)
local Mailbox = require(script.Parent.Parent.World.Mailbox)

local MailService = {}

MailService.ATTRIBUTE = "MailUnread"
local TOUCH_DEBOUNCE = 4 -- стоящий у ящика не открывает его заново каждую секунду

local lastTouch: { [Player]: number } = {}

function MailService.refresh(player: Player)
	local profile = ProfileService.get(player)
	if not profile then
		return
	end
	local unread = #Mail.unread(profile.letters, profile.mail)
	player:SetAttribute(MailService.ATTRIBUTE, if unread > 0 then unread else nil)
end

-- Открыть ящик: новые открытки становятся прочитанными, альбом — все пришедшие.
function MailService.open(player: Player)
	local profile = ProfileService.get(player)
	if not profile then
		return
	end
	local fresh = Mail.unread(profile.letters, profile.mail)
	if #fresh > 0 then
		ProfileService.update(player, function(p)
			p.mail = Mail.markRead(p.mail, p.letters, fresh)
		end)
	end
	MailService.refresh(player)
	RemoteDefs.event("MailOpened"):FireClient(player, {
		fresh = fresh,
		all = Mail.received(profile.letters),
	})
end

local function watchBox(model: Instance)
	local owner = model:GetAttribute("Owner")
	local body = model:FindFirstChild("Box")
	if not body then
		return
	end
	local function openBy(player: Player?, byTouch: boolean)
		if not player or player.UserId ~= owner then
			return
		end
		if byTouch then
			local now = os.clock()
			if now - (lastTouch[player] or 0) < TOUCH_DEBOUNCE then
				return
			end
			lastTouch[player] = now
		end
		MailService.open(player)
	end
	local prompt = body:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(player: Player)
			openBy(player, false)
		end)
	end
	for _, name in { "Box", "Post" } do
		local piece = model:FindFirstChild(name)
		if piece and piece:IsA("BasePart") then
			piece.Touched:Connect(function(hit: BasePart)
				openBy(hit.Parent and Players:GetPlayerFromCharacter(hit.Parent), true)
			end)
		end
	end
end

function MailService.start()
	for _, model in CollectionService:GetTagged(Mailbox.TAG) do
		watchBox(model)
	end
	CollectionService:GetInstanceAddedSignal(Mailbox.TAG):Connect(watchBox)

	-- Буква освоена — буквёнок прилетел и заодно прислал открытку.
	ProgressService.onTransition(function(player: Player, transition)
		if transition.to >= MasteryRules.MASTERED then
			MailService.refresh(player)
		end
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			if ProfileService.waitFor(player, 20) then
				MailService.refresh(player)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastTouch[player] = nil
	end)
end

return MailService
