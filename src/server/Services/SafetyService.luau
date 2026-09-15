--!nonstrict
--[[
	Чата в игре нет — docs/11-COMPLIANCE.md § 2. Аудитория 4–7 лет, и любой канал
	переписки с чужими людьми здесь недопустим.

	Держим это в три слоя, потому что каждый по отдельности ломается тихо:
	  1. default.project.json: TextChatService не создаёт каналы и команды.
	     Но место публикуют из Studio, и галочку там легко вернуть руками;
	  2. этот сервис: любой TextChannel, который появится, сразу удаляется, а окно
	     и строка ввода чата выключаются. Без канала отправить сообщение нельзя
	     даже подменённым клиентом — сообщения ходят только через канал на сервере;
	  3. клиент прячет чат из интерфейса Roblox (init.client).

	Голосовой чат выключается в настройках опыта (Communication → Voice), кодом его
	не выключить; ребёнку до 13 лет Roblox его и так не даёт. Проверка — CHECKLIST.
]]

local TextChatService = game:GetService("TextChatService")

local SafetyService = {}

local function silence(instance: Instance)
	if instance:IsA("TextChannel") then
		warn(
			`[Safety] найден канал чата «{instance.Name}» — удалён: чата в игре нет`
		)
		instance:Destroy()
	elseif
		instance:IsA("ChatWindowConfiguration")
		or instance:IsA("ChatInputBarConfiguration")
		or instance:IsA("BubbleChatConfiguration")
	then
		instance.Enabled = false
	end
end

function SafetyService.start()
	local ok, err = pcall(function()
		TextChatService.CreateDefaultTextChannels = false
		TextChatService.CreateDefaultCommands = false
	end)
	if not ok then
		-- На сервере свойства бывают только для чтения — тогда держимся на удалении каналов.
		warn(`[Safety] настройки TextChatService не поменять из кода: {err}`)
	end

	for _, descendant in TextChatService:GetDescendants() do
		silence(descendant)
	end
	TextChatService.DescendantAdded:Connect(function(descendant: Instance)
		-- Канал может появиться до конца своей сборки: удаляем на следующем кадре.
		task.defer(silence, descendant)
	end)

	print("[Safety] чат выключен")
end

return SafetyService
