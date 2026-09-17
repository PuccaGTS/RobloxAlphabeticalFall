--!nocheck
-- Какие эмодзи рисует Roblox: сетка кандидатов в картинки к буквам на щите в небе.
local CANDIDATES = {
	"🍉", "🍌", "🐺", "🪿", "🦢", "🏠", "🎄", "🌲", "🦔", "🐞", "🪲", "☂️", "☂", "🪡", "🍵", "🐱", "🌙", "⚽",
	"👃", "☁️", "👨", "🐟", "🧃", "🎂", "🦆", "🔦", "🏮", "🍞", "🌷", "🫖", "🎈", "🪥", "🏢", "🧀", "🧂",
	"🍦", "🪐", "🪀", "🍎", "🐸", "🦋", "🍓", "🐘", "🌈", "🫐", "🧸", "🪁", "🚂",
}
return function(player, note)
	task.wait(8)
	local board = Instance.new("Part")
	board.Anchored = true
	board.Size = Vector3.new(1, 1, 1)
	board.Transparency = 1
	board.CFrame = CFrame.new(0, 300, 0)
	board.Parent = workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(60, 40)
	gui.AlwaysOnTop = true
	gui.Parent = board
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(250, 248, 240)
	bg.Parent = gui
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(1 / 8, 1 / 6)
	grid.CellPadding = UDim2.new()
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = bg
	for index, emoji in CANDIDATES do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = index
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.Text = emoji
		label.Parent = bg
	end
	_G.ZZ_Shot(player, "emoji_grid", CFrame.lookAt(Vector3.new(0, 300, 55), Vector3.new(0, 300, 0)), 50)
end
