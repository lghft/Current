-- Modified Rayfield Gen2 v1.2.0 with InputDropdown (Custom Input Dropdown)
-- Original: https://sirius.menu/gen2
-- Modifications: Added CreateInputDropdown method and InputDropdown element class

-- Load the base Rayfield Gen2 library
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

-- ========================================================================
-- InputDropdown Element Class
-- ========================================================================
local InputDropdown = {}
InputDropdown.__index = InputDropdown
InputDropdown.__type = "InputDropdown"

local Icons = {
	chevron = 7072717612,
	dropdown_highlight = "rbxasset://textures/ui/inset_bg_dark.png"
}

function InputDropdown.new(tab, props)
	props = if typeof(props) == "table" then props else {}
	
	local self = setmetatable({
		tab = assert(tab, "Missing argument #1 (Tab expected)"),
		window = tab.window,
		name = props.name or props.Name or "Input Dropdown",
		icon = props.icon or props.Icon,
		options = props.options or props.Options or {},
		callback = props.callback or props.Callback or function() end,
		values = {},
		_isOpen = false,
		_inputFrames = {},
		_textBoxes = {},
	}, InputDropdown)
	
	-- Initialize values table from options
	for _, opt in ipairs(self.options) do
		table.insert(self.values, "")
	end
	
	self:_build()
	return self
end

function InputDropdown:_build()
	local window = self.window
	
	-- Main container
	self.main = window:Create("Frame", {
		Size = UDim2.new(1, -20, 0, 41),
		BorderSizePixel = 0,
		Name = self.name,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		Parent = self.tab.tabPage,
	}, {
		BackgroundTransparency = "ElementTransparency",
	})
	
	-- Top bar (header with chevron)
	self.top = window:Create("Frame", {
		Size = UDim2.new(1, 0, 0, 41),
		Position = UDim2.fromScale(0, 0),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = self.main,
	}, {
		BackgroundTransparency = "ElementTransparency",
	})
	
	self.stroke = window:StyleElementBody(self.top)
	self.hoverOverlay = window:CreateHoverOverlay(self.top)
	
	-- Header container
	self.container = window:Create("Frame", {
		BorderSizePixel = 0,
		Parent = self.top,
		Size = UDim2.new(0, 170, 0, 16),
		Position = UDim2.new(0, 20, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 5,
	})
	
	window:Create("UIListLayout", {
		Padding = UDim.new(0, 5),
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Parent = self.container,
	})
	
	-- Icon
	if self.icon then
		self.iconLabel = window:Create("ImageLabel", {
			Image = self.icon,
			Size = UDim2.fromOffset(16, 16),
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			ImageTransparency = 1,
			ZIndex = 5,
			Parent = self.container,
		}, {
			ImageColor3 = "ContentColor",
		})
	end
	
	-- Title
	self.title = window:Create("TextLabel", {
		Text = self.name,
		Size = UDim2.fromOffset(150, 16),
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		TextSize = 16,
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		TextTransparency = 1,
		ZIndex = 5,
		Parent = self.container,
	}, {
		TextColor3 = "ContentColor",
		FontFace = "Font",
	})
	
	-- Chevron
	self.chevron = window:Create("ImageLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		Image = "rbxassetid://" .. tostring(Icons.chevron),
		Rotation = 180,
		ImageTransparency = 1,
		ZIndex = 5,
		Parent = self.top,
	}, {
		ImageColor3 = "ContentColor",
	})
	
	-- Interact button
	self.interact = window:Create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 41),
		Position = UDim2.fromScale(0, 0),
		BorderSizePixel = 0,
		Text = "",
		TextTransparency = 1,
		ZIndex = 10,
		AutoButtonColor = false,
		Parent = self.main,
	})
	
	-- Panel (dropdown content)
	self.panel = window:Create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 0),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 1,
		BackgroundTransparency = 1,
		Parent = self.main,
	})
	
	self.panelStroke = window:StyleElementPanel(self.panel)
	
	window:Create("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = self.panel,
	})
	
	-- Scroll frame for inputs
	self.scroll = window:Create("ScrollingFrame", {
		Active = true,
		Size = UDim2.new(1, 0, 1, 0),
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarImageColor3 = Color3.fromRGB(240, 240, 240),
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 1,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 1,
		Parent = self.panel,
	})
	
	self.scrollLayout = window:Create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = self.scroll,
	})
	
	-- Create input field for each option
	for i, opt in ipairs(self.options) do
		self:_addInputField(i, opt)
	end
	
	-- Connect interact
	window:ConnectFor(self, self.interact.MouseButton1Click, function()
		if self._isOpen then
			self:_close()
		else
			self:_open()
		end
	end)
	
	-- Hover effects
	window:ConnectFor(self, self.main.MouseEnter, function()
		if self._isOpen or not window:_interactive() then
			return
		end
		window.tweenService:Create(self.title, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			TextColor3 = window.theme.ElementTextHoverColor,
		}):Play()
		window.tweenService:Create(self.stroke, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Transparency = window.theme.ElementStrokeHoverTransparency,
			Color = window.theme.ElementStrokeHover,
		}):Play()
		window.tweenService:Create(self.hoverOverlay, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.97,
		}):Play()
	end)
	
	window:ConnectFor(self, self.main.MouseLeave, function()
		window.tweenService:Create(self.title, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			TextColor3 = window.theme.ContentColor,
		}):Play()
		window.tweenService:Create(self.stroke, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Transparency = window.theme.ElementStrokeTransparency,
			Color = window.theme.ElementStroke,
		}):Play()
		window.tweenService:Create(self.hoverOverlay, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
	end)
end

function InputDropdown:_addInputField(index, name)
	local window = self.window
	
	-- Input container
	local container = window:Create("Frame", {
		Size = UDim2.new(1, -12, 0, 44),
		BorderSizePixel = 0,
		LayoutOrder = index,
		BackgroundTransparency = 1,
		Parent = self.scroll,
	})
	
	-- Label
	window:Create("TextLabel", {
		Text = name,
		Size = UDim2.new(1, 0, 0, 16),
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 1,
		Parent = container,
	}, {
		TextColor3 = "ContentColor",
		FontFace = "Font",
	})
	
	-- Input box
	local box = window:Create("Frame", {
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(1, 0, 0, 24),
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		Parent = container,
	}, {
		BackgroundColor3 = "FieldBackground",
	})
	
	window:Create("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = box,
	})
	
	window:Create("UIStroke", {
		Transparency = 1,
		Parent = box,
	}, {
		Color = "SurfaceStroke",
	})
	
	-- TextBox
	local textBox = window:Create("TextBox", {
		Text = self.values[index] or "",
		PlaceholderText = "Enter value...",
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		ClearTextOnFocus = false,
		TextTransparency = 1,
		Parent = box,
	}, {
		TextColor3 = "ContentColor",
		FontFace = "Font",
		PlaceholderColor3 = "PlaceholderColor",
	})
	
	-- Store reference
	table.insert(self._textBoxes, textBox)
	
	-- Text changed callback
	window:ConnectFor(self, textBox:GetPropertyChangedSignal("Text"), function()
		self.values[index] = textBox.Text
		self.window:_runGuarded(self, self.callback, self:GetValues())
	end)
end

function InputDropdown:_open()
	if self._isOpen then
		return
	end
	
	self._isOpen = true
	
	-- Calculate panel height
	local optionCount = #self.options
	local panelHeight = math.min(optionCount * 50 + 12, 250)
	
	-- Animate open
	self.window.tweenService:Create(
		self.main,
		TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, -20, 0, 41 + panelHeight) }
	):Play()
	
	self.window.tweenService:Create(
		self.chevron,
		TweenInfo.new(0.7, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
		{ Rotation = 0 }
	):Play()
	
	self.window.tweenService:Create(
		self.panel,
		TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ BackgroundTransparency = self.window.theme.ElementTransparency or 0 }
	):Play()
	
	self.window.tweenService:Create(
		self.panelStroke,
		TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Transparency = self.window.theme.ElementStrokeTransparency }
	):Play()
	
	-- Close on outside click
	if self._outsideClickConn then
		self.window:Disconnect(self._outsideClickConn)
	end
	self._outsideClickConn = self.window:Connect(self.window.userInputService.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local pos = input.Position
			local mainPos = self.main.AbsolutePosition
			local mainSize = self.main.AbsoluteSize
			
			if pos.X < mainPos.X or pos.X > mainPos.X + mainSize.X or pos.Y < mainPos.Y or pos.Y > mainPos.Y + mainSize.Y then
				self:_close()
			end
		end
	end)
end

function InputDropdown:_close()
	if not self._isOpen then
		return
	end
	
	self._isOpen = false
	
	if self._outsideClickConn then
		self.window:Disconnect(self._outsideClickConn)
		self._outsideClickConn = nil
	end
	
	-- Animate close
	self.window.tweenService:Create(
		self.chevron,
		TweenInfo.new(0.7, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
		{ Rotation = 180 }
	):Play()
	
	self.window.tweenService:Create(
		self.panel,
		TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()
	
	self.window.tweenService:Create(
		self.panelStroke,
		TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Transparency = 1 }
	):Play()
	
	self.window.tweenService:Create(
		self.main,
		TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, -20, 0, 41) }
	):Play()
end

function InputDropdown:GetValues()
	return table.clone(self.values)
end

function InputDropdown:SetValues(newValues)
	for i, val in ipairs(newValues) do
		if self._textBoxes[i] then
			self._textBoxes[i].Text = tostring(val or "")
			self.values[i] = tostring(val or "")
		end
	end
end

function InputDropdown:AddOption(optionName)
	table.insert(self.options, optionName)
	table.insert(self.values, "")
	self:_addInputField(#self.options, optionName)
end

-- ========================================================================
-- Extend Tab class to include CreateInputDropdown
-- ========================================================================
local originalTabClass = getmetatable(Rayfield:CreateWindow({ name = "Temp", subtitle = "" }):CreateTab({ name = "Temp" }))

if originalTabClass then
	function originalTabClass:CreateInputDropdown(props)
		return InputDropdown.new(self, props)
	end
end

-- Export for direct use
Rayfield.InputDropdown = InputDropdown

return Rayfield
