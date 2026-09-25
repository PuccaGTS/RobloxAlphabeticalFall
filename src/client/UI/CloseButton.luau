--!strict
--[[
	Кнопка «закрыть» для всех окон: красный круг с белым крестиком.

	Крестик нарисован двумя повёрнутыми планками, а не буквой. «✕» в FredokaOne
	не рисуется, а «X» с TextScaled на части экранов пропадал: на проверке
	24.09.2026 во всех окнах была «только красная область». Планки видны всегда.
]]

local CloseButton = {}

local RED = Color3.fromRGB(220, 90, 80)

--[[
	parent — окно, size — сторона кнопки в пикселях, position — где её левый
	верхний угол. Кнопка квадратная при любом экране: круг, а не овал.
]]
function CloseButton.make(parent: Instance, size: number, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Close"
	button.Size = UDim2.fromOffset(size, size)
	button.Position = position
	button.BackgroundColor3 = RED
	button.Text = ""
	button.AutoButtonColor = true
	button.ZIndex = 10
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	for _, angle in { 45, -45 } do
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(0.62, 0.14)
		bar.Rotation = angle
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.BorderSizePixel = 0
		bar.ZIndex = 11
		bar.Parent = button
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = bar
	end

	return button
end

return CloseButton
