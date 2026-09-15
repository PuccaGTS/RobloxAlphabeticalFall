--!nocheck
--[[
	Никаких ссылок наружу — docs/11-COMPLIANCE.md § 2: ни Discord, ни соцсетей,
	ни сайтов, ни «подпишись». Правило платформы для детской аудитории, и нарушить
	его проще всего случайно: скопированной строкой из чужого примера или адресом
	в подсказке. Поэтому проверяем исходники целиком, а не только тексты интерфейса.

	Шаблоны собраны из кусков, чтобы этот файл не находил сам себя, а тесты
	в поиск и не входят.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ROOTS = {
	"Shared",
	"ServerChallenges",
	"ServerWorld",
	"SourceServices",
	"SourceClientUI",
	"SourceClientControllers",
}

local PATTERNS = {
	"https?" .. "://",
	"www" .. "%.",
	"disc" .. "ord",
	"t%." .. "me/",
	"you" .. "tube",
	"tik" .. "tok",
	"vk%." .. "com",
	"tele" .. "gram",
	"insta" .. "gram",
}

local function sources(): { { name: string, text: string } }
	local found = {}
	for _, rootName in ROOTS do
		local root = ReplicatedStorage:FindFirstChild(rootName)
		if root then
			local all = root:GetDescendants()
			table.insert(all, root)
			for _, instance in all do
				if instance:IsA("LuaSourceContainer") then
					local ok, text = pcall(function()
						return instance.Source
					end)
					if ok and typeof(text) == "string" then
						table.insert(found, { name = instance:GetFullName(), text = string.lower(text) })
					end
				end
			end
		end
	end
	return found
end

return function()
	describe("Нет ссылок наружу", function()
		it("исходники доступны для проверки", function()
			-- Без этого тест ниже прошёл бы на пустом списке и ничего не доказал.
			expect(#sources() > 50).to.equal(true)
		end)

		it(
			"ни в одном скрипте игры нет адресов сайтов и соцсетей",
			function()
				local hits = {}
				for _, source in sources() do
					for _, pattern in PATTERNS do
						if string.find(source.text, pattern) then
							table.insert(hits, `{source.name}: {pattern}`)
						end
					end
				end
				if #hits > 0 then
					warn("[Tests] ссылки наружу:\n" .. table.concat(hits, "\n"))
				end
				expect(#hits).to.equal(0)
			end
		)
	end)
end
