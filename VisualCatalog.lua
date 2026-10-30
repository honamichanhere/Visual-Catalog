-- Visual Catalog (standalone) - by Honami
-- UI is built in this file (styled after Mugiwara UI); the accessory logic is ported from Mugiwara HUB's
-- Manager/VisualAccessories.lua (and the rig lookup of Rigs.lua). Browses the Roblox avatar catalog (accessories,
-- clothing, body parts) and wears items client side. Runs in its own window, in any game: Evade uses its custom
-- rigs, every other game the normal Roblox character.

local SCRIPT_NAME = "Visual Catalog"

-- ==========================================================
-- Shared shell (identical in Visual Emotes, Visual Carry and Visual Unusual)
-- A script adds its own page to the shell. If another Visual script is already running, the page joins
-- the same window (sidebar with one tab per script, like the hub); alone, a script gets the plain window.
-- ==========================================================


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

-- Mugiwara UI, Gear 5 theme
local THEME = {
    Background = rgb(12, 13, 21), BackgroundAlpha = 0.12,
    Sidebar = rgb(0, 0, 0), SidebarAlpha = 0.5,
    Card = rgb(255, 255, 255), CardAlpha = 0.91,
    Stroke = rgb(255, 255, 255), StrokeAlpha = 0.84,
    Field = rgb(0, 0, 0), FieldAlpha = 0.45,
    Popup = rgb(14, 14, 20), PopupAlpha = 0.08,
    Text = rgb(252, 252, 255), SubText = rgb(200, 204, 220), Muted = rgb(142, 146, 164),
    Accent = rgb(255, 255, 255), OnAccent = rgb(16, 18, 30),
    Success = rgb(80, 230, 150), Danger = rgb(255, 72, 92),
    Swapped = rgb(255, 200, 62),
}
local GRADIENT_STOPS = { rgb(255, 255, 255), rgb(224, 234, 255), rgb(255, 247, 226), rgb(255, 224, 160) }

local function Linear(stops)
    local points = {}
    for index, color in ipairs(stops) do
        points[index] = ColorSequenceKeypoint.new((index - 1) / (#stops - 1), color)
    end
    return ColorSequence.new(points)
end
local GRADIENT = Linear(GRADIENT_STOPS)
local CYCLE = (function()
    local mirrored = table.clone(GRADIENT_STOPS)
    for index = #GRADIENT_STOPS - 1, 1, -1 do table.insert(mirrored, GRADIENT_STOPS[index]) end
    return Linear(mirrored)
end)()

local FONT_TITLE, FONT_LABEL, FONT_BODY = Enum.Font.GothamBold, Enum.Font.GothamSemibold, Enum.Font.GothamMedium

local function New(class, props, parent)
    local instance = Instance.new(class)
    for key, value in pairs(props) do instance[key] = value end
    instance.Parent = parent
    return instance
end

local function Round(instance, radius)
    return New("UICorner", { CornerRadius = UDim.new(0, radius) }, instance)
end

local function Stroke(instance, transparency, thickness, color)
    return New("UIStroke", {
        Color = color or THEME.Stroke,
        Transparency = transparency,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, instance)
end

local function Gradient(parent, rotation, sequence)
    return New("UIGradient", { Rotation = rotation or 0, Color = sequence or GRADIENT }, parent)
end

local function Label(parent, props)
    local merged = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = FONT_BODY,
        TextColor3 = THEME.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }
    for key, value in pairs(props) do merged[key] = value end
    return New("TextLabel", merged, parent)
end

local function Tween(instance, props, duration, style)
    TweenService:Create(instance, TweenInfo.new(duration or 0.2, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

-- Icons drawn from rotated bars, like Mugiwara UI draws its own glyphs.
local function Glyph(parent, size)
    return New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1,
    }, parent)
end

local function Bar(root, length, thickness, rotation, x, y, color)
    local bar = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(x, y),
        Size = UDim2.fromOffset(length, thickness),
        Rotation = rotation,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, root)
    Round(bar, thickness)
    return bar
end

local function ChevronGlyph(parent, size, color)
    local root = Glyph(parent, size)
    local length = size * 0.56
    return root, { Bar(root, length, 2, 45, 0.31, 0.5, color), Bar(root, length, 2, -45, 0.69, 0.5, color) }
end

local function CheckGlyph(parent, size, color)
    local root = Glyph(parent, size)
    Bar(root, size * 0.34, 2, 42, 0.3, 0.63, color)
    Bar(root, size * 0.64, 2, -48, 0.63, 0.51, color)
    return root
end

local function CloseGlyph(parent, size, color)
    local root = Glyph(parent, size)
    return { Bar(root, size * 0.78, 2, 45, 0.5, 0.5, color), Bar(root, size * 0.78, 2, -45, 0.5, 0.5, color) }
end

local function MinusGlyph(parent, size, color)
    local root = Glyph(parent, size)
    return { Bar(root, size * 0.7, 2, 0, 0.5, 0.5, color) }
end

-- A pill button: gradient fill (primary) or a white translucent card (secondary).
local function MakeButton(parent, text, primary, width)
    local pill = New("Frame", {
        Size = UDim2.fromOffset(width, 32),
        BackgroundColor3 = primary and Color3.new(1, 1, 1) or THEME.Card,
        BackgroundTransparency = primary and 0 or THEME.CardAlpha,
        BorderSizePixel = 0,
    }, parent)
    Round(pill, 9)
    if primary then Gradient(pill, 0) else Stroke(pill, THEME.StrokeAlpha) end
    local label = Label(pill, {
        Text = text,
        Font = FONT_TITLE,
        TextColor3 = primary and THEME.OnAccent or THEME.Text,
        TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1),
    })
    local hit = New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, pill)
    local button = { Frame = pill, Label = label, Hit = hit, Primary = primary, Width = width }
    hit.MouseButton1Down:Connect(function()
        Tween(pill, { Size = UDim2.fromOffset(width - 6, 28) }, 0.08)
    end)
    hit.MouseButton1Up:Connect(function()
        Tween(pill, { Size = UDim2.fromOffset(width, 32) }, 0.3, Enum.EasingStyle.Back)
    end)
    hit.MouseLeave:Connect(function()
        Tween(pill, { Size = UDim2.fromOffset(width, 32) }, 0.2)
    end)
    if not primary then
        hit.MouseEnter:Connect(function() Tween(pill, { BackgroundTransparency = 0.84 }, 0.15) end)
        hit.MouseLeave:Connect(function() Tween(pill, { BackgroundTransparency = THEME.CardAlpha }, 0.2) end)
    end
    return button
end

local function SetEnabled(button, enabled)
    button.Frame.BackgroundTransparency = enabled and (button.Primary and 0 or THEME.CardAlpha) or 0.6
    button.Label.TextTransparency = enabled and 0 or 0.45
end

-- A grid whose number of columns follows the width of its scroll frame: as many columns as fit with every cell at
-- least minCell wide (never fewer than 2). Resizing the window adds or removes columns. onChange (optional) runs
-- shortly after the columns changed, for grids that load content for the visible cells only.
local function ResponsiveGrid(scroll, gap, cellHeight, minCell, onChange)
    local layout = New("UIGridLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        CellSize = UDim2.new(1 / 3, -math.ceil(gap * 2 / 3), 0, cellHeight),
        CellPadding = UDim2.fromOffset(gap, gap),
    }, scroll)

    local columns, token = 3, 0
    local function Update()
        local width = scroll.AbsoluteWindowSize.X - 9 -- the scroll frame's own side padding
        if width <= 0 then return end
        local count = math.max(2, math.floor((width + gap) / (minCell + gap)))
        if count == columns then return end
        columns = count
        layout.CellSize = UDim2.new(1 / count, -math.ceil(gap * (count - 1) / count), 0, cellHeight)
        if onChange then
            token = token + 1
            local mine = token
            task.delay(0.15, function()
                if mine == token then onChange() end
            end)
        end
    end
    scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(Update)
    Update()
    return layout
end

-- The usual page layout: a row of panes (PaneHolder) above a bottom bar with a status line.
-- The script adds its own buttons to the bottom bar.
local BAR_H = 56
local function BuildPageLayout(frame)
    local paneHolder = New("Frame", { Name = "Panes", Size = UDim2.new(1, 0, 1, -BAR_H), BackgroundTransparency = 1 }, frame)
    New("UIPadding", {
        PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 8),
    }, paneHolder)
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
    }, paneHolder)

    local bottomBar = New("Frame", {
        Name = "BottomBar",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, BAR_H),
        BackgroundTransparency = 1,
    }, frame)
    New("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = THEME.Stroke,
        BackgroundTransparency = THEME.StrokeAlpha,
        BorderSizePixel = 0,
    }, bottomBar)

    local statusLabel = Label(bottomBar, {
        Position = UDim2.fromOffset(16, 0),
        Size = UDim2.new(1, -290, 1, 0),
        TextColor3 = THEME.SubText,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    return { PaneHolder = paneHolder, BottomBar = bottomBar, StatusLabel = statusLabel }
end

-- ----------------------------------------------------------
-- The shell itself
-- ----------------------------------------------------------
local TOPBAR, SIDEBAR = 54, 150
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 340, 340, 1200, 760

local function CreateShell()
    local Shell = { ApiVersion = 1, Alive = true, Pages = {}, Active = nil }
    local connections, tweens = {}, {}
    local opened = true

    local function Spin(gradient, seconds)
        local tween = TweenService:Create(gradient, TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = gradient.Rotation + 360 })
        tween:Play()
        table.insert(tweens, tween)
    end

    local guiParent
    pcall(function() guiParent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not guiParent then guiParent = Players.LocalPlayer:WaitForChild("PlayerGui") end

    local Gui = New("ScreenGui", {
        Name = "VisualCatalog",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 10000,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, guiParent)
    Shell.Gui = Gui

    local Main = New("Frame", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(680, 470),
        BackgroundTransparency = 1,
    }, Gui)
    local MainScale = New("UIScale", { Scale = 1 }, Main)

    local Pop = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    }, Main)
    local PopScale = New("UIScale", { Scale = 0.9 }, Pop)

    -- neon glow rings behind the window
    local glowRings = {}
    for _, layer in ipairs({ { 0, 3, 0.5 }, { 3, 7, 0.8 }, { 10, 14, 0.92 } }) do
        local pad, thickness, transparency = layer[1], layer[2], layer[3]
        local ring = New("Frame", {
            Name = "Glow",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, pad * 2, 1, pad * 2),
            BackgroundTransparency = 1,
        }, Pop)
        Round(ring, 16 + pad)
        local stroke = Stroke(ring, 1, thickness)
        Spin(Gradient(stroke, 0, CYCLE), 9)
        table.insert(glowRings, { Stroke = stroke, Base = transparency })
    end

    local Win = New("CanvasGroup", {
        Name = "Window",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = THEME.Background,
        BackgroundTransparency = THEME.BackgroundAlpha,
        GroupTransparency = 1,
        BorderSizePixel = 0,
    }, Pop)
    Round(Win, 16)

    -- glass wash + sheen
    local wash = New("Frame", { Name = "Wash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, Win)
    Gradient(wash, 35).Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0.9),
    })
    local sheen = New("Frame", { Name = "Sheen", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, Win)
    New("UIGradient", {
        Rotation = 20,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.92), NumberSequenceKeypoint.new(0.35, 1), NumberSequenceKeypoint.new(1, 0.97),
        }),
    }, sheen)

    -- spinning neon border above the window
    local border = New("Frame", { Name = "Border", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, Pop)
    Round(border, 16)
    local borderStroke = Stroke(border, 1, 1.5)
    Spin(Gradient(borderStroke, 0, CYCLE), 9)
    table.insert(glowRings, { Stroke = borderStroke, Base = 0.3 })

    -- topbar
    local TopBar = New("Frame", { Name = "Topbar", Size = UDim2.new(1, 0, 0, TOPBAR), BackgroundTransparency = 1 }, Win)

    local brand = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 16, 0.5, 0),
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, TopBar)
    Round(brand, 9)
    Gradient(brand, 45)
    Label(brand, {
        Text = "V",
        Font = Enum.Font.GothamBlack,
        TextSize = 17,
        TextColor3 = THEME.OnAccent,
        TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1),
    })

    local titleRow = New("Frame", {
        Position = UDim2.fromOffset(56, 8),
        Size = UDim2.new(1, -200, 0, 22),
        BackgroundTransparency = 1,
    }, TopBar)
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8),
    }, titleRow)
    local titleLabel = Label(titleRow, {
        Text = "Visual",
        Font = FONT_TITLE,
        TextSize = 16,
        TextColor3 = Color3.new(1, 1, 1),
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 20),
        LayoutOrder = 1,
    })
    Gradient(titleLabel, 0)

    local versionPill = New("Frame", {
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        LayoutOrder = 2,
    }, titleRow)
    Round(versionPill, 8)
    New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, versionPill)
    Gradient(versionPill, 0)
    local versionLabel = Label(versionPill, {
        Text = "v2.0",
        Font = FONT_TITLE,
        TextSize = 11,
        TextColor3 = THEME.OnAccent,
        TextXAlignment = Enum.TextXAlignment.Center,
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 16),
    })

    Label(TopBar, {
        Text = "by Honami  ·  L to hide or show",
        TextSize = 12,
        TextColor3 = THEME.SubText,
        Position = UDim2.fromOffset(56, 30),
        Size = UDim2.new(1, -200, 0, 14),
    })

    local function ControlButton(offset, makeGlyph, hoverColor)
        local button = New("TextButton", {
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, offset, 0.5, 0),
            Size = UDim2.fromOffset(34, 34),
        }, TopBar)
        Round(button, 9)
        local bars = makeGlyph(button, 20, THEME.SubText)
        button.MouseEnter:Connect(function()
            Tween(button, { BackgroundTransparency = 0.88 }, 0.15)
            for _, bar in ipairs(bars) do Tween(bar, { BackgroundColor3 = hoverColor or THEME.Text }, 0.15) end
        end)
        button.MouseLeave:Connect(function()
            Tween(button, { BackgroundTransparency = 1 }, 0.2)
            for _, bar in ipairs(bars) do Tween(bar, { BackgroundColor3 = THEME.SubText }, 0.2) end
        end)
        return button
    end

    local CloseButton = ControlButton(-12, CloseGlyph, THEME.Danger)
    local MinimizeButton = ControlButton(-50, MinusGlyph)

    local topLine = New("Frame", {
        Position = UDim2.fromOffset(0, TOPBAR),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, Win)
    Gradient(topLine, 0).Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 0.9),
    })

    local Body = New("Frame", {
        Name = "Body",
        Position = UDim2.fromOffset(0, TOPBAR + 1),
        Size = UDim2.new(1, 0, 1, -(TOPBAR + 1)),
        BackgroundTransparency = 1,
    }, Win)

    -- sidebar (only shown when two or more scripts share the window)
    local Sidebar = New("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, SIDEBAR, 1, 0),
        BackgroundColor3 = THEME.Sidebar,
        BackgroundTransparency = THEME.SidebarAlpha,
        BorderSizePixel = 0,
        Visible = false,
    }, Body)
    New("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = THEME.Stroke,
        BackgroundTransparency = THEME.StrokeAlpha,
        BorderSizePixel = 0,
    }, Sidebar)
    local TabList = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, Sidebar)
    New("UIPadding", {
        PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 9),
    }, TabList)
    New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, TabList)

    local PageArea = New("Frame", { Name = "Pages", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, Body)

    -- ---------- layout ----------
    local function ViewportSize()
        local camera = workspace.CurrentCamera
        return camera and camera.ViewportSize or Vector2.new(1280, 720)
    end

    local function PaintTab(page)
        local tab = page.Tab
        if not tab then return end
        local on = Shell.Active == page
        tab.Button.BackgroundTransparency = on and 0.78 or 1
        tab.Stroke.Color = on and THEME.Accent or THEME.Stroke
        tab.Stroke.Transparency = on and 0.45 or THEME.StrokeAlpha
        tab.Label.TextColor3 = on and THEME.Text or THEME.SubText
    end

    local function MakeTab(page)
        local button = New("TextButton", {
            Name = page.Id,
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 1,
            LayoutOrder = page.Order,
            Size = UDim2.new(1, 0, 0, 38),
        }, TabList)
        Round(button, 10)
        Gradient(button, 0)
        local stroke = Stroke(button, THEME.StrokeAlpha)

        local badge = New("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 8, 0.5, 0),
            Size = UDim2.fromOffset(22, 22),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
        }, button)
        Round(badge, 7)
        Gradient(badge, 45)
        Label(badge, {
            Text = page.Letter,
            Font = Enum.Font.GothamBlack,
            TextSize = 13,
            TextColor3 = THEME.OnAccent,
            TextXAlignment = Enum.TextXAlignment.Center,
            Size = UDim2.fromScale(1, 1),
        })
        local label = Label(button, {
            Text = page.TabTitle,
            Font = FONT_LABEL,
            Position = UDim2.fromOffset(38, 0),
            Size = UDim2.new(1, -44, 1, 0),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })

        page.Tab = { Button = button, Stroke = stroke, Label = label }
        button.MouseEnter:Connect(function()
            if Shell.Active ~= page then Tween(button, { BackgroundTransparency = 0.92 }, 0.12) end
        end)
        button.MouseLeave:Connect(function()
            if Shell.Active ~= page then Tween(button, { BackgroundTransparency = 1 }, 0.15) end
        end)
        button.MouseButton1Click:Connect(function() Shell:SelectPage(page) end)
    end

    function Shell:SelectPage(page)
        self.Active = page
        for _, other in ipairs(self.Pages) do
            other.Frame.Visible = other == page
            PaintTab(other)
        end
        if page.OnShow then task.defer(page.OnShow) end
    end

    local function Relayout()
        local count = #Shell.Pages
        if count == 0 then return end
        local combined = count >= 2

        Sidebar.Visible = combined
        PageArea.Position = UDim2.fromOffset(combined and SIDEBAR or 0, 0)
        PageArea.Size = UDim2.new(1, combined and -SIDEBAR or 0, 1, 0)

        local width, height = MIN_WIDTH, MIN_HEIGHT
        for _, page in ipairs(Shell.Pages) do
            width = math.max(width, page.Width)
            height = math.max(height, page.Height)
            if combined and not page.Tab then MakeTab(page) end
            if not combined and page.Tab then
                page.Tab.Button:Destroy()
                page.Tab = nil
            end
        end
        width = width + (combined and SIDEBAR or 0)

        if combined then
            titleLabel.Text = "Visual Suite"
        else
            titleLabel.Text = Shell.Pages[1].Title
        end

        -- small screens (phones) shrink the whole window so it fits
        local screen = ViewportSize()
        local scale = math.clamp(math.min(1, (screen.X - 24) / width, (screen.Y - 24) / height), 0.45, 1)
        MainScale.Scale = scale
        Tween(Main, { Size = UDim2.fromOffset(width, height) }, 0.3, Enum.EasingStyle.Quint)

        for _, page in ipairs(Shell.Pages) do PaintTab(page) end
    end

    -- A script adds its page here. spec: Id, Title (window title when alone), TabTitle, Letter, Order,
    -- Width, Height (preferred size of its content), Cleanup (called when the window is closed), OnShow.
    function Shell:AddPage(spec)
        local page = {
            Id = spec.Id,
            Title = spec.Title,
            TabTitle = spec.TabTitle or spec.Title,
            Letter = spec.Letter or string.sub(spec.Title, 1, 1),
            Order = spec.Order or 99,
            Width = spec.Width or 680,
            Height = spec.Height or 470,
            Cleanup = spec.Cleanup,
            OnShow = spec.OnShow,
        }
        page.Frame = New("Frame", { Name = page.Id, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, PageArea)

        table.insert(self.Pages, page)
        table.sort(self.Pages, function(a, b) return a.Order < b.Order end)
        Relayout()
        self:SelectPage(page)
        if not opened then self:SetOpen(true) end
        return page
    end

    function Shell:RemovePage(id)
        for index, page in ipairs(self.Pages) do
            if page.Id == id then
                table.remove(self.Pages, index)
                if page.Tab then page.Tab.Button:Destroy() end
                page.Frame:Destroy()
                if self.Active == page then self.Active = nil end
                break
            end
        end
        if #self.Pages == 0 then
            self:Destroy()
            return
        end
        Relayout()
        if not self.Active then self:SelectPage(self.Pages[1]) end
    end

    function Shell:Destroy()
        if not self.Alive then return end
        self.Alive = false
        for _, tween in ipairs(tweens) do pcall(function() tween:Cancel() end) end
        for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
        pcall(function() Gui:Destroy() end)
        if getgenv().VisualCatalogShell == self then getgenv().VisualCatalogShell = nil end
    end

    -- Every page puts its swaps / effects back, then the window goes away.
    function Shell:CloseAll()
        for _, page in ipairs(table.clone(self.Pages)) do
            if page.Cleanup then pcall(page.Cleanup) end
        end
        self:Destroy()
    end

    -- ---------- drag, resize ----------
    local dragging, dragStart, startPosition = false, nil, nil
    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPosition = true, input.Position, Main.Position
        end
    end)

    local grip = New("TextButton", {
        Name = "ResizeGrip",
        Text = "",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -4, 1, -4),
        Size = UDim2.fromOffset(22, 22),
        ZIndex = 8,
    }, Pop)
    Bar(grip, 14, 2, -45, 0.58, 0.58, THEME.Muted)
    Bar(grip, 7, 2, -45, 0.78, 0.78, THEME.Muted)

    local resizing, resizeStart, startSize, resizeOrigin = false, nil, nil, nil
    grip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            resizing, resizeStart, startSize, resizeOrigin = true, input.Position, Main.Size, Main.Position
        end
    end)

    -- Mouse buttons reuse one InputObject, so releases are caught once, here, instead of connecting
    -- to every press (those connections would pile up and fire on every later release).
    local pressed, moved, pressStart, pressPosition = false, false, nil, nil

    table.insert(connections, UserInputService.InputChanged:Connect(function(input)
        local isMove = input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
        if not isMove then return end
        local scale = MainScale.Scale

        if dragging then
            local delta = (input.Position - dragStart) / scale
            Main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end

        if resizing then
            local screen = ViewportSize()
            local delta = (input.Position - resizeStart) / scale
            local maxWidth = math.max(MIN_WIDTH, math.min(MAX_WIDTH, (screen.X - 24) / scale))
            local maxHeight = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, (screen.Y - 24) / scale))
            local width = math.clamp(startSize.X.Offset + delta.X, MIN_WIDTH, maxWidth)
            local height = math.clamp(startSize.Y.Offset + delta.Y, MIN_HEIGHT, maxHeight)
            Main.Size = UDim2.fromOffset(width, height)
            Main.Position = UDim2.new(
                resizeOrigin.X.Scale, resizeOrigin.X.Offset + (width - startSize.X.Offset) / 2,
                resizeOrigin.Y.Scale, resizeOrigin.Y.Offset + (height - startSize.Y.Offset) / 2
            )
        end

        if pressed then
            local delta = (input.Position - pressStart) / scale
            if delta.Magnitude * scale > 6 then moved = true end
            if moved then
                Shell.OpenButton.Position = UDim2.new(pressPosition.X.Scale, pressPosition.X.Offset + delta.X, pressPosition.Y.Scale, pressPosition.Y.Offset + delta.Y)
            end
        end
    end))

    -- ---------- minimize / open button ----------
    local OpenButton = New("TextButton", {
        Name = "OpenButton",
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 36, 0.5, 0),
        Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = THEME.Popup,
        BackgroundTransparency = THEME.PopupAlpha,
        Visible = false,
    }, Gui)
    Shell.OpenButton = OpenButton
    New("UICorner", { CornerRadius = UDim.new(1, 0) }, OpenButton)
    local OpenScale = New("UIScale", { Scale = 1 }, OpenButton)
    Spin(Gradient(Stroke(OpenButton, 0.15, 2), 0, CYCLE), 6)
    Spin(Gradient(Stroke(OpenButton, 0.7, 6), 0, CYCLE), 6)
    local openMark = Label(OpenButton, {
        Text = "V",
        Font = Enum.Font.GothamBlack,
        TextSize = 22,
        TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1),
    })
    Gradient(openMark, 45)

    function Shell:SetOpen(state)
        if state == opened or not self.Alive then return end
        opened = state
        OpenScale.Scale = MainScale.Scale
        if state then
            Main.Visible = true
            PopScale.Scale = 0.9
            Tween(PopScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Quint)
            Tween(Win, { GroupTransparency = 0 }, 0.3)
            for _, ring in ipairs(glowRings) do Tween(ring.Stroke, { Transparency = ring.Base }, 0.4) end
            Tween(OpenButton, { Size = UDim2.fromOffset(0, 0) }, 0.18)
            task.delay(0.18, function()
                if opened then OpenButton.Visible = false end
            end)
            if self.Active and self.Active.OnShow then task.defer(self.Active.OnShow) end
        else
            Tween(PopScale, { Scale = 0.92 }, 0.3, Enum.EasingStyle.Quint)
            Tween(Win, { GroupTransparency = 1 }, 0.24)
            for _, ring in ipairs(glowRings) do Tween(ring.Stroke, { Transparency = 1 }, 0.2) end
            task.delay(0.3, function()
                if not opened then Main.Visible = false end
            end)
            OpenButton.Visible = true
            Tween(OpenButton, { Size = UDim2.fromOffset(52, 52) }, 0.5, Enum.EasingStyle.Back)
        end
    end

    OpenButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            pressed, moved, pressStart, pressPosition = true, false, input.Position, OpenButton.Position
        end
    end)

    table.insert(connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging, resizing = false, false
        if pressed then
            pressed = false
            -- a tap (no drag) on the open button opens the window again
            if not moved then Shell:SetOpen(true) end
        end
    end))

    MinimizeButton.MouseButton1Click:Connect(function() Shell:SetOpen(false) end)

    table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.L then Shell:SetOpen(not opened) end
    end))

    -- ---------- close confirmation ----------
    local dialogOpen = false
    local function ConfirmClose()
        if dialogOpen then return end
        dialogOpen = true

        local overlay = New("TextButton", {
            Name = "Dialog",
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 1,
            ZIndex = 50,
        }, Win)
        Tween(overlay, { BackgroundTransparency = 0.42 }, 0.25)

        local card = New("CanvasGroup", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(0, 330, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = THEME.Popup,
            BackgroundTransparency = THEME.PopupAlpha,
            GroupTransparency = 1,
            BorderSizePixel = 0,
            Active = true,
            ZIndex = 51,
        }, overlay)
        Round(card, 14)
        local outline = Stroke(card, 1, 1.4, Color3.new(1, 1, 1))
        Spin(Gradient(outline, 45, CYCLE), 8)
        New("UIPadding", {
            PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18),
            PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18),
        }, card)
        New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }, card)
        local cardScale = New("UIScale", { Scale = 0.9 }, card)
        Tween(cardScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Quint)
        Tween(card, { GroupTransparency = 0 }, 0.25)
        Tween(outline, { Transparency = 0.3 }, 0.25)

        local title = Label(card, {
            Text = "Close " .. titleLabel.Text .. "?",
            Font = FONT_TITLE,
            TextSize = 16,
            TextColor3 = Color3.new(1, 1, 1),
            TextWrapped = true,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
            LayoutOrder = 1,
        })
        Gradient(title, 0)
        Label(card, {
            Text = "The interface will be closed and everything you swapped or applied will be put back to normal. Run the script again to reopen it.",
            TextSize = 14,
            TextColor3 = THEME.SubText,
            TextWrapped = true,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
            LayoutOrder = 2,
        })

        local row = New("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 3 }, card)
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8),
        }, row)

        local function CloseDialog()
            Tween(cardScale, { Scale = 0.93 }, 0.2)
            Tween(card, { GroupTransparency = 1 }, 0.2)
            Tween(outline, { Transparency = 1 }, 0.2)
            Tween(overlay, { BackgroundTransparency = 1 }, 0.2)
            task.delay(0.22, function()
                overlay:Destroy()
                dialogOpen = false
            end)
        end

        local function DialogButton(text, danger, order, callback)
            local button = New("TextButton", {
                Text = text,
                Font = FONT_TITLE,
                TextSize = 13,
                TextColor3 = danger and THEME.OnAccent or THEME.Text,
                AutoButtonColor = false,
                BorderSizePixel = 0,
                AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2.fromOffset(0, 36),
                BackgroundColor3 = danger and THEME.Danger or THEME.Card,
                BackgroundTransparency = danger and 0 or 0.84,
                LayoutOrder = order,
            }, row)
            Round(button, 9)
            New("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, button)
            button.MouseButton1Click:Connect(callback)
        end

        DialogButton("Cancel", false, 1, CloseDialog)
        DialogButton("Close", true, 2, function() Shell:CloseAll() end)
    end
    CloseButton.MouseButton1Click:Connect(ConfirmClose)

    -- open animation: pop in and fade the glow up
    Tween(PopScale, { Scale = 1 }, 0.45, Enum.EasingStyle.Back)
    Tween(Win, { GroupTransparency = 0 }, 0.35)
    for _, ring in ipairs(glowRings) do Tween(ring.Stroke, { Transparency = ring.Base }, 0.45) end

    return Shell
end

-- The shell shared by every Visual script that is running; the first one to start creates it.
local function GetShell()
    local existing = getgenv().VisualCatalogShell
    if existing and existing.Alive and existing.Gui and existing.Gui.Parent then return existing end
    local shell = CreateShell()
    getgenv().VisualCatalogShell = shell
    return shell
end


-- ==========================================================
-- This script
-- ==========================================================

local cleanupFns = {}
local function RegisterCleanup(fn)
    table.insert(cleanupFns, fn)
end

local Shell, Page
local function ModuleCleanup()
    local fns = cleanupFns
    cleanupFns = {}
    for _, fn in ipairs(fns) do pcall(fn) end
    if Shell and Page then Shell:RemovePage(Page.Id) end
end

-- Run again while an older copy is still open: that copy puts everything back first.
local env = getgenv()
if env.VisualCatalogCleanup then pcall(env.VisualCatalogCleanup) end
env.VisualCatalogCleanup = ModuleCleanup

-- ==========================================================
-- Rigs: which models get the items
--   Evade     : the custom rigs in Workspace.Rigs named after the player (menu/inventory and in-game; both are
--               visual copies, from Games/Evade/Rigs.lua)
--   any other : the normal Roblox character (R6 or R15)
-- ==========================================================
local Rigs = {}
do
    local LocalPlayer = Players.LocalPlayer
    local EVADE_PLACE_IDS = { [9872472334] = true, [99214917572799] = true, [10668472534] = true }

    function Rigs.GetAll()
        local list = {}

        if EVADE_PLACE_IDS[game.PlaceId] then
            local container = workspace:FindFirstChild("Rigs")
            if container then
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("Model") and child.Name == LocalPlayer.Name then
                        local humanoid = child:FindFirstChildOfClass("Humanoid")
                        if humanoid then table.insert(list, { Rig = child, Humanoid = humanoid }) end
                    end
                end
            end
        end

        if #list == 0 then
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if humanoid then table.insert(list, { Rig = character, Humanoid = humanoid }) end
        end

        return list
    end
end

-- ==========================================================
-- Catalog engine: puts catalog items on the rigs (client side only, nothing is bought or saved)
--   Accessory   hats, hair, face / neck / shoulder / front / back / waist items, 3D (layered) clothing, shoes
--   Clothing    classic shirt, pants, t-shirt
--   Face        classic faces
--   Body        dynamic heads: the head of the rig is rebuilt to match an avatar made with that head (size, mesh and
--               joints), see "body" below. R15 only.
-- Also: what the rig wears right now (and taking even the original items off), and the colors of the body parts.
-- The kind of an item comes from its asset type (asked from Roblox the first time), so any asset id works.
-- Accessory handling is ported from Manager/VisualAccessories.lua.
-- ==========================================================
local Catalog = {}
do
    local MarketplaceService = game:GetService("MarketplaceService")

    Catalog.Templates = {
        { Name = "Violet Valkyrie", ID = 1402432199 },
        { Name = "8-Bit Royal Crown", ID = 10159600649 },
        { Name = "Fiery Horns of the Netherworld", ID = 215718515 },
        { Name = "Frozen Horns of the Frigid Planes", ID = 74891470 },
        { Name = "Poisoned Horns of the Toxic Wasteland", ID = 1744060292 },
    }

    Catalog.OnChange = nil -- called (no arguments) whenever the set of worn items changes

    -- asset type id -> how it is worn. Slot = only one item per slot at a time.
    local TYPE_INFO = {
        [2] = { Kind = "Clothing", Slot = "TShirt", Class = "ShirtGraphic" },
        [11] = { Kind = "Clothing", Slot = "Shirt", Class = "Shirt" },
        [12] = { Kind = "Clothing", Slot = "Pants", Class = "Pants" },
        [18] = { Kind = "Face", Slot = "Face" },
        -- Field = the property of a HumanoidDescription that takes this asset
        [79] = { Kind = "Body", Field = "Head", NeedsR15 = "Dynamic heads" },
    }
    for _, assetType in ipairs({ 8, 41, 42, 43, 44, 45, 46, 47 }) do
        TYPE_INFO[assetType] = { Kind = "Accessory" }
    end
    -- 3D (layered) clothing and shoes wrap around an R15 body
    for _, assetType in ipairs({ 64, 65, 66, 67, 68, 69, 70, 71, 72 }) do
        TYPE_INFO[assetType] = { Kind = "Accessory", NeedsR15 = "3D clothing" }
    end

    local applied = {}      -- [assetId] = { Info = TYPE_INFO entry, AssetType = number }
    local slotOwner = {}    -- [slot] = assetId
    local loadedCache = {}  -- [assetId] = instance returned by GetObjects (kept in memory, never parented)
    local accessoryCache = {} -- [assetId] = ready-to-wear Accessory
    local typeCache = {}    -- [assetId] = asset type id, or false when unknown
    local originals = setmetatable({}, { __mode = "k" }) -- [rig] = what was there before we changed it
    local handledRigs = setmetatable({}, { __mode = "k" })
    local alive = true

    local function Changed()
        if Catalog.OnChange then task.spawn(Catalog.OnChange) end
    end

    local function GetAllRigs()
        local ok, list = pcall(Rigs.GetAll)
        return ok and type(list) == "table" and list or {}
    end

    local function Store(rig)
        originals[rig] = originals[rig] or {}
        return originals[rig]
    end

    -- ---------- looking at an item ----------
    local function IdText(assetId)
        return string.format("%.0f", assetId)
    end

    -- May yield (the first time). The asset type id of an item, from the catalog.
    function Catalog.AssetTypeOf(assetId, hint)
        if hint then return hint end
        if typeCache[assetId] ~= nil then return typeCache[assetId] or nil end
        local ok, info = pcall(function() return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset) end)
        local assetType = ok and type(info) == "table" and tonumber(info.AssetTypeId) or false
        typeCache[assetId] = assetType
        return assetType or nil
    end

    function Catalog.IsSupportedType(assetType)
        return TYPE_INFO[assetType] ~= nil
    end

    local function LoadAsset(assetId)
        if loadedCache[assetId] then return loadedCache[assetId] end
        local ok, objects = pcall(function() return game:GetObjects("rbxassetid://" .. IdText(assetId)) end)
        if not ok or type(objects) ~= "table" or not objects[1] then return nil end
        for index = 2, #objects do pcall(function() objects[index]:Destroy() end) end
        loadedCache[assetId] = objects[1]
        return objects[1]
    end

    -- ---------- shared helpers (ported from Manager/VisualAccessories.lua) ----------
    local function FindBodyAttachment(character, attachmentName)
        for _, object in ipairs(character:GetDescendants()) do
            if object:IsA("Attachment") and object.Name == attachmentName and object.Parent:IsA("BasePart") then
                return object
            end
        end
        return nil
    end

    local function SetMeshProp(part, prop, value)
        if pcall(function() part[prop] = value end) then return "direct" end
        if sethiddenproperty and pcall(sethiddenproperty, part, prop, value) then return "sethiddenproperty" end
        return nil
    end

    local function ApplyMeshById(part, meshId)
        local method = SetMeshProp(part, "MeshId", meshId)
        if method then return method end
        local okNew, newMesh = pcall(function()
            return game:GetService("InsertService"):CreateMeshPartAsync(meshId, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Automatic)
        end)
        if okNew and newMesh then
            local okApply = pcall(function() part:ApplyMesh(newMesh) end)
            newMesh:Destroy()
            if okApply then return "ApplyMesh" end
        end
        return nil
    end

    local function ReadLook(part)
        local look = { MeshId = part.MeshId, TextureID = part.TextureID, Color = part.Color, Material = part.Material, Transparency = part.Transparency, Appearance = {} }
        for _, child in ipairs(part:GetChildren()) do
            if child:IsA("SurfaceAppearance") then table.insert(look.Appearance, child:Clone()) end
        end
        return look
    end

    local function ApplyLook(dst, look)
        if not dst:IsA("MeshPart") then return false end

        local meshMethod, texMethod = "same", "same"
        if dst.MeshId ~= look.MeshId then meshMethod = ApplyMeshById(dst, look.MeshId) end
        if dst.TextureID ~= look.TextureID then texMethod = SetMeshProp(dst, "TextureID", look.TextureID) end
        if not meshMethod or not texMethod then return false end

        for _, child in ipairs(dst:GetChildren()) do
            if child:IsA("SurfaceAppearance") then child:Destroy() end
        end
        for _, appearance in ipairs(look.Appearance) do appearance:Clone().Parent = dst end

        pcall(function()
            dst.Color = look.Color
            dst.Material = look.Material
            dst.Transparency = look.Transparency
        end)
        return true
    end

    local function IsR15(humanoid)
        return humanoid.RigType == Enum.HumanoidRigType.R15
    end

    -- ---------- accessories ----------
    local function PrepareAccessory(assetId, loaded)
        if accessoryCache[assetId] then return accessoryCache[assetId] end
        local acc = loaded:IsA("Accessory") and loaded or loaded:FindFirstChildWhichIsA("Accessory", true)
        local handle = acc and acc:FindFirstChild("Handle")
        if not (handle and handle:IsA("BasePart")) then return nil end

        handle.CanCollide = false
        handle.CanTouch = false
        handle.CanQuery = false
        handle.Massless = true
        handle.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)
        acc:SetAttribute("IsCustomAccessory", true)
        acc:SetAttribute("AssetId", assetId)
        accessoryCache[assetId] = acc:Clone()
        return accessoryCache[assetId]
    end

    local function EquipAccessory(character, humanoid, cachedAcc, assetId)
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Accessory") and child:GetAttribute("AssetId") == assetId then
                return true
            end
        end

        local newAcc = cachedAcc:Clone()
        local handle = newAcc:FindFirstChild("Handle")
        local itemAtt = handle:FindFirstChildWhichIsA("Attachment")

        if itemAtt then
            local bodyAtt = FindBodyAttachment(character, itemAtt.Name)
            if bodyAtt then
                local bodyPart = bodyAtt.Parent
                newAcc.Parent = character

                local oldWeld = handle:FindFirstChild("AccessoryWeld")
                if oldWeld then oldWeld:Destroy() end

                local weld = Instance.new("Weld")
                weld.Name = "AccessoryWeld"
                weld.Part0 = bodyPart
                weld.Part1 = handle
                weld.C0 = bodyAtt.CFrame
                weld.C1 = itemAtt.CFrame
                weld.Parent = handle
            else
                pcall(function() humanoid:AddAccessory(newAcc) end)
                pcall(function() humanoid:BuildRigFromAttachments() end)
            end
        else
            pcall(function() humanoid:AddAccessory(newAcc) end)
            pcall(function() humanoid:BuildRigFromAttachments() end)
        end

        return true
    end

    local function RemoveAccessory(rig, assetId)
        for _, child in ipairs(rig:GetChildren()) do
            if child:IsA("Accessory") and child:GetAttribute("AssetId") == assetId then child:Destroy() end
        end
    end

    -- ---------- classic clothing ----------
    local function ApplyClothing(rig, assetId, loaded, info)
        local source = loaded.ClassName == info.Class and loaded or loaded:FindFirstChildWhichIsA(info.Class, true)
        if not source then return false end

        local store = Store(rig)
        local key = "Clothing:" .. info.Class
        for _, child in ipairs(rig:GetChildren()) do
            if child.ClassName == info.Class then
                if not child:GetAttribute("VisualCatalogId") and store[key] == nil then store[key] = child:Clone() end
                child:Destroy()
            end
        end

        local clone = source:Clone()
        clone:SetAttribute("VisualCatalogId", assetId)
        clone.Parent = rig
        return true
    end

    local function RemoveClothing(rig, assetId, info)
        for _, child in ipairs(rig:GetChildren()) do
            if child.ClassName == info.Class and child:GetAttribute("VisualCatalogId") == assetId then child:Destroy() end
        end
        local store = Store(rig)
        local key = "Clothing:" .. info.Class
        if store[key] then
            store[key]:Clone().Parent = rig
            store[key] = nil
        end
    end

    -- ---------- face ----------
    local function FaceDecal(head)
        return head:FindFirstChild("face") or head:FindFirstChildWhichIsA("Decal")
    end

    local function ApplyFace(rig, assetId, loaded)
        local head = rig:FindFirstChild("Head")
        local source = loaded:IsA("Decal") and loaded or loaded:FindFirstChildWhichIsA("Decal", true)
        if not (head and source) then return false end

        local store = Store(rig)
        local face = FaceDecal(head)
        if face then
            if store.Face == nil then store.Face = { Decal = face, Texture = face.Texture } end
            face.Texture = source.Texture
        else
            local clone = source:Clone()
            clone.Name = "face"
            clone:SetAttribute("VisualCatalogId", assetId)
            clone.Parent = head
        end
        return true
    end

    local function RemoveFace(rig, assetId)
        local store = Store(rig)
        if store.Face then
            if store.Face.Decal.Parent then store.Face.Decal.Texture = store.Face.Texture end
            store.Face = nil
        end
        local head = rig:FindFirstChild("Head")
        local face = head and head:FindFirstChild("face")
        if face and face:GetAttribute("VisualCatalogId") == assetId then face:Destroy() end
    end

    -- ---------- body (head, torso, arms, legs) ----------
    -- Body parts are not copied one mesh at a time: the proportions and the joints of a body change with them (a
    -- short body wearing a tall torso ends up in pieces). So a whole avatar is built from the player's own
    -- description with the chosen parts put in (Players:CreateHumanoidModelFromDescription), and then the size, mesh,
    -- attachments and joint offsets of every body part of the rig are made to match that model. Taking the parts off
    -- puts every value back from the copy that was made before the first change.
    local R15_BODY = {
        "Head", "UpperTorso", "LowerTorso",
        "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
        "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
    }
    local bodyOverrides = {} -- [description field] = assetId
    local baseDescription
    local bodyModels = {}    -- [rig type .. overrides] = the model built for them
    local bodyBusy = false

    local function BaseDescription()
        if baseDescription then return baseDescription end
        local ok, description = pcall(function() return Players:GetHumanoidDescriptionFromUserId(Players.LocalPlayer.UserId) end)
        if not ok or not description then return nil end
        -- only the body is wanted from the model: no accessories or clothes of the player's own
        pcall(function() description:SetAccessories({}, true) end)
        for _, field in ipairs({ "Shirt", "Pants", "GraphicTShirt" }) do
            pcall(function() description[field] = 0 end)
        end
        baseDescription = description
        return description
    end

    local function OverridesKey()
        local fields = {}
        for field in pairs(bodyOverrides) do table.insert(fields, field) end
        table.sort(fields)
        local parts = {}
        for _, field in ipairs(fields) do table.insert(parts, field .. "=" .. IdText(bodyOverrides[field])) end
        return table.concat(parts, ",")
    end

    -- May yield (the avatar data and the meshes are downloaded).
    local function BuildBodyModel(r15)
        local prefix = r15 and "R15:" or "R6:"
        local key = prefix .. OverridesKey()
        if bodyModels[key] then return bodyModels[key] end

        local base = BaseDescription()
        if not base then return nil, "Could not read your avatar data." end
        local description = base:Clone()
        for field, assetId in pairs(bodyOverrides) do description[field] = assetId end

        local rigType = r15 and Enum.HumanoidRigType.R15 or Enum.HumanoidRigType.R6
        local ok, model = pcall(function() return Players:CreateHumanoidModelFromDescription(description, rigType) end)
        if not ok or not model then return nil, "Could not build a body from these parts." end

        -- wait (not forever) for the meshes, so the sizes are the real ones
        local loaded = false
        task.spawn(function()
            pcall(function() game:GetService("ContentProvider"):PreloadAsync({ model }) end)
            loaded = true
        end)
        local started = os.clock()
        while not loaded and os.clock() - started < 5 do task.wait() end

        for oldKey, old in pairs(bodyModels) do
            if string.sub(oldKey, 1, #prefix) == prefix then
                pcall(function() old:Destroy() end)
                bodyModels[oldKey] = nil
            end
        end
        bodyModels[key] = model
        return model
    end

    local function JointsByPart1(root)
        local map = {}
        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:IsA("Motor6D") and descendant.Part1 then map[descendant.Part1.Name] = descendant end
        end
        return map
    end

    local function MeshState(mesh)
        return { Mesh = mesh, MeshType = mesh.MeshType, MeshId = mesh.MeshId, TextureId = mesh.TextureId, Scale = mesh.Scale, Offset = mesh.Offset }
    end

    local function RestoreMesh(saved)
        if saved and saved.Mesh.Parent then
            saved.Mesh.MeshType = saved.MeshType
            saved.Mesh.MeshId = saved.MeshId
            saved.Mesh.TextureId = saved.TextureId
            saved.Mesh.Scale = saved.Scale
            saved.Mesh.Offset = saved.Offset
        end
    end

    -- The head part of the rig can be a Part with a SpecialMesh or a MeshPart, and so can the model's.
    local function SyncHead(dst, src, original)
        if dst:IsA("MeshPart") then
            if src:IsA("MeshPart") then return ApplyLook(dst, ReadLook(src)) end
            local mesh = src:FindFirstChildWhichIsA("SpecialMesh")
            if not mesh then return false end
            return ApplyLook(dst, { MeshId = mesh.MeshId, TextureID = mesh.TextureId, Color = dst.Color, Material = dst.Material, Transparency = dst.Transparency, Appearance = {} })
        end

        local mesh = dst:FindFirstChildWhichIsA("SpecialMesh")
        if not mesh then
            mesh = Instance.new("SpecialMesh")
            mesh:SetAttribute("VisualCatalogMade", true)
            mesh.Parent = dst
            original.MadeMesh = mesh
        end
        local srcMesh = src:FindFirstChildWhichIsA("SpecialMesh")
        if srcMesh then
            mesh.MeshType = srcMesh.MeshType
            mesh.MeshId = srcMesh.MeshId
            mesh.TextureId = srcMesh.TextureId
            mesh.Scale = srcMesh.Scale
            mesh.Offset = srcMesh.Offset
            return true
        elseif src:IsA("MeshPart") then
            mesh.MeshType = Enum.MeshType.FileMesh
            mesh.MeshId = src.MeshId
            mesh.TextureId = src.TextureID
            mesh.Scale = Vector3.new(1, 1, 1)
            mesh.Offset = Vector3.new(0, 0, 0)
            return true
        end
        return false
    end

    local function SyncBody15(rig, humanoid, model)
        local store = Store(rig)
        if not store.Body then
            local original = { Humanoid = humanoid, HipHeight = humanoid.HipHeight, Parts = {} }
            local joints = JointsByPart1(rig)
            for _, name in ipairs(R15_BODY) do
                local part = rig:FindFirstChild(name)
                if part and part:IsA("BasePart") then
                    local data = { Part = part, Size = part.Size, Attachments = {} }
                    if part:IsA("MeshPart") then
                        data.Look = ReadLook(part)
                    else
                        local mesh = part:FindFirstChildWhichIsA("SpecialMesh")
                        if mesh then data.Mesh = MeshState(mesh) end
                    end
                    for _, child in ipairs(part:GetChildren()) do
                        if child:IsA("Attachment") then data.Attachments[child] = child.CFrame end
                    end
                    local joint = joints[name]
                    if joint then data.Joint = { Motor = joint, C0 = joint.C0, C1 = joint.C1 } end
                    original.Parts[name] = data
                end
            end
            store.Body = original
        end

        local modelJoints = JointsByPart1(model)
        local changed = false
        for name, data in pairs(store.Body.Parts) do
            local dst, src = data.Part, model:FindFirstChild(name)
            if dst.Parent and src and src:IsA("BasePart") then
                if name == "Head" then
                    if SyncHead(dst, src, store.Body) then changed = true end
                elseif dst:IsA("MeshPart") and src:IsA("MeshPart") then
                    if ApplyLook(dst, ReadLook(src)) then changed = true end
                end
                pcall(function() dst.Size = src.Size end)
                for attachment in pairs(data.Attachments) do
                    local counterpart = src:FindFirstChild(attachment.Name)
                    if counterpart and counterpart:IsA("Attachment") then attachment.CFrame = counterpart.CFrame end
                end
                local modelJoint = modelJoints[name]
                if data.Joint and modelJoint then
                    data.Joint.Motor.C0 = modelJoint.C0
                    data.Joint.Motor.C1 = modelJoint.C1
                end
            end
        end

        local modelHumanoid = model:FindFirstChildOfClass("Humanoid")
        if modelHumanoid then pcall(function() humanoid.HipHeight = modelHumanoid.HipHeight end) end
        return changed
    end

    local function RestoreBody15(store)
        local body = store.Body
        if not body then return end
        for _, data in pairs(body.Parts) do
            local part = data.Part
            if part.Parent then
                if data.Look then ApplyLook(part, data.Look) end
                RestoreMesh(data.Mesh)
                pcall(function() part.Size = data.Size end)
                for attachment, cframe in pairs(data.Attachments) do
                    if attachment.Parent then attachment.CFrame = cframe end
                end
                if data.Joint and data.Joint.Motor.Parent then
                    data.Joint.Motor.C0 = data.Joint.C0
                    data.Joint.Motor.C1 = data.Joint.C1
                end
            end
        end
        if body.MadeMesh and body.MadeMesh.Parent then body.MadeMesh:Destroy() end
        pcall(function() body.Humanoid.HipHeight = body.HipHeight end)
        store.Body = nil
    end

    local function RestoreBody(rig)
        RestoreBody15(Store(rig))
    end

    local function ApplyBodyToRig(rig, humanoid)
        if not IsR15(humanoid) then return false, "Dynamic heads need an R15 avatar." end
        local model, problem = BuildBodyModel(true)
        if not model then return false, problem end
        local ok, changed = pcall(SyncBody15, rig, humanoid, model)
        if not ok then return false, tostring(changed) end
        return changed, changed and nil or "The head did not fit this rig."
    end

    -- May yield. Makes every rig match the current overrides (or its own body again when there are none).
    local function RefreshBody()
        while bodyBusy do task.wait(0.1) end
        bodyBusy = true
        local anyOk, lastProblem = false, nil
        local ok, err = pcall(function()
            for _, rigEntry in ipairs(GetAllRigs()) do
                if next(bodyOverrides) == nil then
                    RestoreBody(rigEntry.Rig)
                    anyOk = true
                else
                    local done, problem = ApplyBodyToRig(rigEntry.Rig, rigEntry.Humanoid)
                    if done then anyOk = true else lastProblem = problem end
                end
            end
        end)
        bodyBusy = false
        if not ok then return false, tostring(err) end
        return anyOk, lastProblem
    end

    -- ---------- one item on one rig ----------
    local function SourceOf(assetId, info)
        if info.Kind == "Accessory" then return accessoryCache[assetId] end
        return loadedCache[assetId]
    end

    local function ApplyToRig(entry, assetId, rig, humanoid)
        local info = entry.Info
        if info.NeedsR15 and not IsR15(humanoid) then return false end
        local source = SourceOf(assetId, info)
        if not source then return false end

        if info.Kind == "Accessory" then return EquipAccessory(rig, humanoid, source, assetId) end
        if info.Kind == "Clothing" then return ApplyClothing(rig, assetId, source, info) end
        if info.Kind == "Face" then return ApplyFace(rig, assetId, source) end
        return false
    end

    local function RemoveFromRig(entry, assetId, rig, humanoid)
        local info = entry.Info
        if info.Kind == "Accessory" then RemoveAccessory(rig, assetId) end
        if info.Kind == "Clothing" then RemoveClothing(rig, assetId, info) end
        if info.Kind == "Face" then RemoveFace(rig, assetId) end
    end

    -- ---------- what the rig wears, taking original items off, body colors ----------
    local taken = {}      -- items taken off the rig(s): { Instance, Rig, Name, Kind }
    local bodyColors = {} -- [region] = Color3 chosen for it

    Catalog.Regions = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
    local REGION_PARTS = {
        Head = { "Head" },
        Torso = { "UpperTorso", "LowerTorso", "Torso" },
        LeftArm = { "LeftUpperArm", "LeftLowerArm", "LeftHand", "Left Arm" },
        RightArm = { "RightUpperArm", "RightLowerArm", "RightHand", "Right Arm" },
        LeftLeg = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "Left Leg" },
        RightLeg = { "RightUpperLeg", "RightLowerLeg", "RightFoot", "Right Leg" },
    }
    local BODY_COLOR_PROPERTY = {
        Head = "HeadColor3", Torso = "TorsoColor3", LeftArm = "LeftArmColor3",
        RightArm = "RightArmColor3", LeftLeg = "LeftLegColor3", RightLeg = "RightLegColor3",
    }
    local WEARABLE = { Accessory = "Accessory", Shirt = "Shirt", Pants = "Pants", ShirtGraphic = "T-Shirt" }

    local function IsOurs(instance)
        return instance:GetAttribute("IsCustomAccessory") == true or instance:GetAttribute("VisualCatalogId") ~= nil
    end

    -- What the first rig wears now: accessories, shirt, pants and t-shirt (also the ones that came with the
    -- avatar). Ours carry their asset id, so they can be taken off like any catalog item.
    function Catalog.ListWorn()
        local first = GetAllRigs()[1]
        local list = {}
        if not first then return list end
        for _, child in ipairs(first.Rig:GetChildren()) do
            local kind = WEARABLE[child.ClassName]
            if kind then
                table.insert(list, {
                    Instance = child, Kind = kind, Name = child.Name,
                    AssetId = child:GetAttribute("AssetId") or child:GetAttribute("VisualCatalogId"),
                    Ours = IsOurs(child),
                })
            end
        end
        return list
    end

    -- Takes a worn item off. Our own items are removed; original ones are lifted off the rig(s) and kept, so they
    -- can be put back (RestoreTaken). May yield for our own items.
    function Catalog.TakeOff(item)
        if item.Ours and item.AssetId then
            Catalog.Remove(item.AssetId)
            return
        end
        local name, class = item.Instance.Name, item.Instance.ClassName
        for _, rigEntry in ipairs(GetAllRigs()) do
            for _, child in ipairs(rigEntry.Rig:GetChildren()) do
                if child.ClassName == class and child.Name == name and not IsOurs(child) then
                    table.insert(taken, { Instance = child, Rig = rigEntry.Rig, Name = name, Kind = item.Kind })
                    child.Parent = nil
                    break
                end
            end
        end
        Changed()
    end

    -- The original items that were taken off, one line per name.
    function Catalog.ListTaken()
        local list, seen = {}, {}
        for _, entry in ipairs(taken) do
            local key = entry.Kind .. ":" .. entry.Name
            if not seen[key] then
                seen[key] = true
                table.insert(list, { Name = entry.Name, Kind = entry.Kind })
            end
        end
        return list
    end

    function Catalog.RestoreTaken(name, kind)
        for index = #taken, 1, -1 do
            local entry = taken[index]
            if (name == nil or (entry.Name == name and entry.Kind == kind)) then
                if entry.Rig.Parent then entry.Instance.Parent = entry.Rig end
                table.remove(taken, index)
            end
        end
        Changed()
    end

    local function ApplyColors(rig)
        local store = Store(rig)
        store.Colors = store.Colors or {}
        store.BodyColorValues = store.BodyColorValues or {}
        local bodyColorsInstance = rig:FindFirstChildOfClass("BodyColors")
        for _, region in ipairs(Catalog.Regions) do
            local color = bodyColors[region]
            for _, name in ipairs(REGION_PARTS[region]) do
                local part = rig:FindFirstChild(name)
                if part and part:IsA("BasePart") then
                    if store.Colors[part] == nil then store.Colors[part] = part.Color end
                    pcall(function() part.Color = color or store.Colors[part] end)
                end
            end
            local property = BODY_COLOR_PROPERTY[region]
            if bodyColorsInstance then
                if store.BodyColorValues[property] == nil then store.BodyColorValues[property] = bodyColorsInstance[property] end
                pcall(function() bodyColorsInstance[property] = color or store.BodyColorValues[property] end)
            end
        end
    end

    -- region = "All" or one of Catalog.Regions; color = a Color3, or nil to give the region its own color back.
    function Catalog.SetBodyColor(region, color)
        for _, name in ipairs(Catalog.Regions) do
            if region == "All" or region == name then bodyColors[name] = color end
        end
        for _, rigEntry in ipairs(GetAllRigs()) do pcall(ApplyColors, rigEntry.Rig) end
        Changed()
    end

    function Catalog.GetBodyColor(region)
        return bodyColors[region]
    end

    function Catalog.ResetColors()
        Catalog.SetBodyColor("All", nil)
    end

    -- ---------- API ----------
    function Catalog.IsApplied(assetId)
        return applied[assetId] ~= nil
    end

    function Catalog.AppliedCount()
        local count = 0
        for _ in pairs(applied) do count = count + 1 end
        return count
    end

    -- takes a worn item off the rigs (body parts are handled by RefreshBody instead)
    local function RemoveInternal(assetId)
        local entry = applied[assetId]
        if not entry then return end
        for _, rigEntry in ipairs(GetAllRigs()) do
            pcall(RemoveFromRig, entry, assetId, rigEntry.Rig, rigEntry.Humanoid)
        end
        applied[assetId] = nil
        if entry.Info.Slot and slotOwner[entry.Info.Slot] == assetId then slotOwner[entry.Info.Slot] = nil end
    end

    -- One item. Body parts are only recorded in bodyAdded (the body is rebuilt once for all of them afterwards).
    local function ApplyItem(rigs, assetId, assetTypeHint, bodyAdded)
        local assetType = Catalog.AssetTypeOf(assetId, assetTypeHint)
        local info = assetType and TYPE_INFO[assetType]
        if not info then
            return false, assetType and ("This item type (" .. assetType .. ") can not be worn here yet.") or "Could not read this item from the catalog."
        end

        if info.NeedsR15 then
            local fitting = {}
            for _, rigEntry in ipairs(rigs) do
                if IsR15(rigEntry.Humanoid) then table.insert(fitting, rigEntry) end
            end
            if #fitting == 0 then return false, info.NeedsR15 .. " need an R15 avatar." end
            rigs = fitting
        end

        if info.Kind == "Body" then
            local previous = bodyOverrides[info.Field]
            local record = { Id = assetId, Field = info.Field }
            if previous and previous ~= assetId then
                record.Previous, record.PreviousEntry = previous, applied[previous]
                applied[previous] = nil
            end
            bodyOverrides[info.Field] = assetId
            applied[assetId] = { Info = info, AssetType = assetType }
            table.insert(bodyAdded, record)
            return true
        end

        local loaded = LoadAsset(assetId)
        if not loaded then return false, "Could not load that asset." end
        if info.Kind == "Accessory" and not PrepareAccessory(assetId, loaded) then
            return false, "Could not load that asset. Make sure it is an accessory ID."
        end

        -- a slot holds one item: the item that was in it goes back first
        if info.Slot and slotOwner[info.Slot] and slotOwner[info.Slot] ~= assetId then
            RemoveInternal(slotOwner[info.Slot])
        end

        local entry = { Info = info, AssetType = assetType }
        local worn = false
        for _, rigEntry in ipairs(rigs) do
            local ok, result = pcall(ApplyToRig, entry, assetId, rigEntry.Rig, rigEntry.Humanoid)
            if ok and result then worn = true end
        end
        if not worn then return false, "This item did not fit the character (" .. info.Kind .. ")." end

        applied[assetId] = entry
        if info.Slot then slotOwner[info.Slot] = assetId end
        return true
    end

    -- May yield. items = a list of { Id, AssetType (optional hint) }. Body parts of one call are put on with a
    -- single rebuild of the body. Returns true, message or false, the first problem.
    function Catalog.ApplyMany(items)
        local rigs = GetAllRigs()
        if #rigs == 0 then return false, "No character found yet. Wait until you have spawned." end

        local firstProblem
        local bodyAdded = {}
        for _, item in ipairs(items) do
            local ok, message = ApplyItem(rigs, item.Id, item.AssetType, bodyAdded)
            if not ok then firstProblem = firstProblem or message end
        end

        if #bodyAdded > 0 then
            local ok, message = RefreshBody()
            if not ok then
                -- put the earlier body parts back
                for index = #bodyAdded, 1, -1 do
                    local record = bodyAdded[index]
                    applied[record.Id] = nil
                    bodyOverrides[record.Field] = record.Previous
                    if record.Previous then applied[record.Previous] = record.PreviousEntry end
                end
                RefreshBody()
                firstProblem = firstProblem or message or "This body part did not fit the character."
            end
        end

        Changed()
        return firstProblem == nil, firstProblem or "Equipped."
    end

    function Catalog.Apply(assetId, assetTypeHint)
        return Catalog.ApplyMany({ { Id = assetId, AssetType = assetTypeHint } })
    end

    -- May yield (a body part leaves the body to be rebuilt without it).
    function Catalog.Remove(assetId)
        local entry = applied[assetId]
        if entry and entry.Info.Kind == "Body" then
            if bodyOverrides[entry.Info.Field] == assetId then bodyOverrides[entry.Info.Field] = nil end
            applied[assetId] = nil
            RefreshBody()
        else
            RemoveInternal(assetId)
        end
        Changed()
    end

    -- May yield. Takes several items off; the body is rebuilt once for all the body parts among them.
    function Catalog.RemoveMany(assetIds)
        local hadBody = false
        for _, assetId in ipairs(assetIds) do
            local entry = applied[assetId]
            if entry and entry.Info.Kind == "Body" then
                hadBody = true
                if bodyOverrides[entry.Info.Field] == assetId then bodyOverrides[entry.Info.Field] = nil end
                applied[assetId] = nil
            else
                RemoveInternal(assetId)
            end
        end
        if hadBody then RefreshBody() end
        Changed()
    end

    -- Takes everything off. Returns how many items were worn.
    function Catalog.Clear()
        local count = 0
        local hadBody = false
        for assetId, entry in pairs(table.clone(applied)) do
            if entry.Info.Kind == "Body" then
                hadBody = true
                applied[assetId] = nil
            else
                RemoveInternal(assetId)
            end
            count = count + 1
        end
        if hadBody then
            bodyOverrides = {}
            RefreshBody()
        end
        Changed()
        return count
    end

    -- A new rig (respawn, or a rig the game rebuilt) gets everything that is worn again.
    task.spawn(function()
        while alive do
            task.wait(1)
            for _, rigEntry in ipairs(GetAllRigs()) do
                if not handledRigs[rigEntry.Rig] then
                    handledRigs[rigEntry.Rig] = true
                    task.wait(0.5)
                    if alive and rigEntry.Rig.Parent then
                        for assetId, entry in pairs(table.clone(applied)) do
                            if entry.Info.Kind ~= "Body" then
                                pcall(ApplyToRig, entry, assetId, rigEntry.Rig, rigEntry.Humanoid)
                            end
                        end
                        if next(bodyOverrides) ~= nil then pcall(ApplyBodyToRig, rigEntry.Rig, rigEntry.Humanoid) end
                        if next(bodyColors) ~= nil then pcall(ApplyColors, rigEntry.Rig) end
                    end
                end
            end
        end
    end)

    RegisterCleanup(function()
        alive = false
        Catalog.OnChange = nil
        pcall(Catalog.Clear)
        pcall(Catalog.ResetColors)
        pcall(Catalog.RestoreTaken)
    end)
end


-- ==========================================================
-- Page in the shared window
-- ==========================================================
Shell = GetShell()
Page = Shell:AddPage({
    Id = "Catalog",
    Title = "Visual Catalog",
    TabTitle = "Catalog",
    Letter = "C",
    Order = 4,
    Width = 470,
    Height = 640,
    Cleanup = ModuleCleanup,
})
local PageLayout = BuildPageLayout(Page.Frame)
local PaneHolder, StatusLabel = PageLayout.PaneHolder, PageLayout.StatusLabel
StatusLabel.Size = UDim2.new(1, -150, 1, 0)
local RemoveAllButton = MakeButton(PageLayout.BottomBar, "Remove All", false, 116)
RemoveAllButton.Frame.AnchorPoint = Vector2.new(1, 0.5)
RemoveAllButton.Frame.Position = UDim2.new(1, -12, 0.5, 0)

-- ==========================================================
-- Catalog browser (same look as Visual Unusual). Every cell shows the item's picture (loaded from its id).
-- Pick a group (Accessories / Clothing / Body) and a type in the rows at the top, search by keyword, change the
-- order, and more load as you scroll. Bundles (full bodies, dynamic heads, shoes) open into their parts, which
-- are worn one by one or all at once. "Featured" holds the hub's templates and anything added by asset id.
-- The list comes from the game's own catalog (AvatarEditorService); the web catalog is the fallback and needs
-- the executor's request function.
-- ==========================================================
local MarketplaceService = game:GetService("MarketplaceService")

local CELL_HEIGHT, TITLE_HEIGHT, GAP = 112, 20, 6
local PAGE_SIZE = 30
local CACHE_SECONDS = 300
local SEARCH_DELAY = 0.6
local REQUEST_GAP = 0.9 -- seconds between two catalog requests; Roblox answers bursts with 403 / 429

-- The catalog is asked directly first. Some executors / networks get a 403 from it, so a public mirror of the same
-- API (same paths, same answers) is the fallback; whichever host answers last is used first next time.
local HOSTS = { "https://catalog.roblox.com", "https://catalog.roproxy.com" }
local BROWSER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

-- Groups and types. Category / Sub are the web catalog's filters; AssetTypes are the asset type numbers the game's
-- own catalog takes (8 hat, 41 hair, 42 face, 43 neck, 44 shoulder, 45 front, 46 back, 47 waist, 11 shirt,
-- 12 pants, 2 t-shirt, 64-72 layered clothing, 18 face); Bundle is a bundle type (3 shoes, 4 dynamic head)
-- instead. Direct bundles are worn with one click instead of opening into their parts.
local GROUPS = {
    { Title = "Featured" },
    { Title = "Accessories", Types = {
        { Title = "All", Category = 11, AssetTypes = { 8, 42, 43, 44, 45, 46, 47 } },
        { Title = "Head", Category = 11, Sub = 54, AssetTypes = { 8 } },
        { Title = "Hair", Category = 18, Sub = 20, AssetTypes = { 41 } },
        { Title = "Face", Category = 11, Sub = 21, AssetTypes = { 42 } },
        { Title = "Neck", Category = 11, Sub = 22, AssetTypes = { 43 } },
        { Title = "Shoulder", Category = 11, Sub = 23, AssetTypes = { 44 } },
        { Title = "Front", Category = 11, Sub = 24, AssetTypes = { 45 } },
        { Title = "Back", Category = 11, Sub = 25, AssetTypes = { 46 } },
        { Title = "Waist", Category = 11, Sub = 26, AssetTypes = { 47 } },
    } },
    { Title = "Clothing", Types = {
        { Title = "All", Category = 3, AssetTypes = { 11, 2, 12, 64, 65, 66, 67, 68, 69, 72 } },
        { Title = "Classic Shirt", Category = 3, Sub = 56, AssetTypes = { 11 } },
        { Title = "Classic Pants", Category = 3, Sub = 57, AssetTypes = { 12 } },
        { Title = "Classic T-Shirt", Category = 3, Sub = 55, AssetTypes = { 2 } },
        { Title = "Shirt 3D", Category = 3, Sub = 59, AssetTypes = { 65 } },
        { Title = "Pants 3D", Category = 3, Sub = 60, AssetTypes = { 66 } },
        { Title = "T-Shirt 3D", Category = 3, Sub = 58, AssetTypes = { 64 } },
        { Title = "Jacket 3D", Category = 3, Sub = 61, AssetTypes = { 67 } },
        { Title = "Sweater 3D", Category = 3, Sub = 62, AssetTypes = { 68 } },
        { Title = "Shorts 3D", Category = 3, Sub = 63, AssetTypes = { 69 } },
        { Title = "Dress 3D", Category = 3, Sub = 65, AssetTypes = { 72 } },
        { Title = "Shoes", Category = 3, Sub = 64, Bundle = 3, Direct = true },
    } },
    { Title = "Body", Types = {
        { Title = "Dynamic Heads", Category = 18, Sub = 66, Bundle = 4, Direct = true },
        { Title = "Classic Faces", Category = 18, Sub = 10, AssetTypes = { 18 } },
    } },
    -- not a catalog list: the avatar itself (what it wears, with a preview) and the colors of its body parts
    { Title = "Avatar", Pages = { "Wearing", "Colors" } },
}
local DEFAULT_GROUP = 2 -- Accessories, "All", most popular first

local SORTS = {
    { Name = "Relevance", Type = 0, Engine = "Relevance" },
    { Name = "Popular", Type = 2, Aggregation = 3, Engine = "Bestselling", EngineAggregation = "PastWeek" },
    { Name = "Newest", Type = 3, Engine = "RecentlyCreated" },
    { Name = "Most Favorited", Type = 1, Engine = "MostFavorited" },
    { Name = "Price: Low to High", Type = 4, Engine = "PriceLowToHigh" },
    { Name = "Price: High to Low", Type = 5, Engine = "PriceHighToLow" },
}
local DEFAULT_SORT, SEARCH_SORT = 2, 1

local function ThumbnailOf(entry)
    local kind = entry.IsBundle and "BundleThumbnail" or "Asset"
    return "rbxthumb://type=" .. kind .. "&id=" .. string.format("%.0f", entry.Id) .. "&w=150&h=150"
end

local function ParseId(text)
    local digits = string.match(text or "", "%d+")
    return digits and tonumber(digits) or nil
end

-- "12345678", "https://www.roblox.com/catalog/12345678/Name" or "rbxassetid://12345678"
local function LooksLikeId(text)
    text = text or ""
    if string.match(text, "^%s*%d%d%d%d%d+%s*$") then return true end
    return (string.find(text, "roblox.com", 1, true) or string.find(text, "rbxassetid", 1, true)) ~= nil and ParseId(text) ~= nil
end

local function PriceText(entry)
    if entry.Status == "Off Sale" then return "Off sale" end
    if type(entry.Price) ~= "number" then return "" end
    if entry.Price == 0 then return "Free" end
    return "R$ " .. entry.Price
end

local function RequestFunction()
    local env = getgenv()
    return env.request or env.http_request or (env.syn and env.syn.request) or (env.http and env.http.request) or (env.fluxus and env.fluxus.request)
end

-- ---------- catalog access ----------
local responseCache = {}

-- Catalog descriptions can hold control characters or broken UTF-8, which makes JSONDecode throw for the whole page;
-- those bytes are dropped and the decode is tried again.
local function SanitizeJson(body)
    local text = string.gsub(body, "[%z\1-\8\11\12\14-\31\127]", "")
    if utf8 and utf8.len then
        for _ = 1, 4000 do
            local length, badPosition = utf8.len(text)
            if length then break end
            text = string.sub(text, 1, badPosition - 1) .. string.sub(text, badPosition + 1)
        end
    end
    return text
end

local function DecodeJson(body)
    if type(body) == "table" then return body end
    if type(body) ~= "string" then return nil, "empty response" end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok then ok, data = pcall(function() return HttpService:JSONDecode(SanitizeJson(body)) end) end
    if not ok or type(data) ~= "table" then return nil, "unreadable response" end
    return data
end

local hostIndex, lastSent = 1, -REQUEST_GAP

-- never faster than one catalog request per REQUEST_GAP, whatever the source
local function Throttle()
    while os.clock() - lastSent < REQUEST_GAP do task.wait(0.1) end
    lastSent = os.clock()
end

-- May yield. Takes the path and query of a catalog search. Returns the decoded JSON table, or nil, a kind
-- ("no-request", "rate", "failed") and a detail text.
local function CatalogGet(path)
    local hit = responseCache[path]
    if hit and os.clock() - hit.At < CACHE_SECONDS then return hit.Data end

    local send = RequestFunction()
    if not send then return nil, "no-request" end

    local detail = "unknown error"
    local kind = "failed"
    for attempt = 1, 4 do
        Throttle()

        local host = HOSTS[hostIndex]
        local ok, response = pcall(send, {
            Url = host .. path,
            Method = "GET",
            Headers = { ["Accept"] = "application/json", ["User-Agent"] = BROWSER_AGENT },
        })

        local retryOtherHost = true
        if not ok or type(response) ~= "table" then
            detail = "request error: " .. tostring(response)
        else
            local code = response.StatusCode
            if code == 200 then
                local data, problem = DecodeJson(response.Body)
                if data then
                    responseCache[path] = { At = os.clock(), Data = data }
                    return data
                end
                detail = problem
                retryOtherHost = false
            elseif code == 429 then
                detail = "HTTP 429"
                kind = "rate"
                task.wait(3)
                retryOtherHost = false
            else
                detail = "HTTP " .. tostring(code)
            end
        end

        if retryOtherHost and #HOSTS > 1 then hostIndex = hostIndex % #HOSTS + 1 end
        if detail ~= "HTTP 429" then kind = "failed" end
    end
    return nil, kind, detail
end

local function CatalogUrl(typeInfo, keyword, sort, cursor)
    local parts = { "Limit=" .. PAGE_SIZE, "Category=" .. typeInfo.Category }
    if typeInfo.Sub then table.insert(parts, "Subcategory=" .. typeInfo.Sub) end
    if keyword ~= "" then table.insert(parts, "Keyword=" .. HttpService:UrlEncode(keyword)) end
    table.insert(parts, "SortType=" .. sort.Type)
    if sort.Aggregation then table.insert(parts, "SortAggregation=" .. sort.Aggregation) end
    if cursor then table.insert(parts, "Cursor=" .. HttpService:UrlEncode(cursor)) end
    return "/v1/search/items/details?" .. table.concat(parts, "&")
end


-- ---------- the game's own catalog (AvatarEditorService, no HTTP involved) ----------
-- Tried first: it is the catalog the Roblox avatar editor uses and needs no request function. If it is unusable
-- here (errors three times) the web catalog above takes over for the rest of the session.
local engineBroken, engineFailures = false, 0

local function EnumNamed(enumType, name)
    for _, item in ipairs(enumType:GetEnumItems()) do
        if item.Name == name then return item end
    end
    return nil
end

local function EnumValued(enumType, values)
    local list = {}
    for _, item in ipairs(enumType:GetEnumItems()) do
        if table.find(values, item.Value) then table.insert(list, item) end
    end
    return list
end

local function EngineStart(typeInfo, keyword, sort)
    local params = CatalogSearchParams.new()
    if keyword ~= "" then params.SearchKeyword = keyword end
    -- enum items are found by their number, so a renamed item cannot break the lookup
    if typeInfo.Bundle then
        local bundleTypes = EnumValued(Enum.BundleType, { typeInfo.Bundle })
        if #bundleTypes == 0 then error("no matching BundleType") end
        params.BundleTypes = bundleTypes
    else
        local assetTypes = EnumValued(Enum.AvatarAssetType, typeInfo.AssetTypes)
        if #assetTypes == 0 then error("no matching AvatarAssetType") end
        params.AssetTypes = assetTypes
    end
    local sortType = EnumNamed(Enum.CatalogSortType, sort.Engine)
    if sortType then params.SortType = sortType end
    if sort.EngineAggregation then
        local aggregation = EnumNamed(Enum.CatalogSortAggregation, sort.EngineAggregation)
        if aggregation then params.SortAggregation = aggregation end
    end
    return game:GetService("AvatarEditorService"):SearchCatalog(params)
end

local function EngineItems(pages, wantBundles)
    local list = {}
    for _, item in ipairs(pages:GetCurrentPage()) do
        local id, name = item.Id, item.Name
        local isBundle = string.find(tostring(item.ItemType or ""), "Bundle", 1, true) ~= nil
        if type(id) == "number" and type(name) == "string" and isBundle == wantBundles then
            table.insert(list, { Id = id, Name = name, IsBundle = isBundle, Price = item.Price, Creator = item.CreatorName })
        end
    end
    return list
end

-- May yield. Returns items (a list of { Id, Name, IsBundle, AssetType, Price, Status, Creator }) and whether it was the
-- last page, or nil, nil, a failure kind ("no-request", "rate", "failed") and a detail text. The view keeps the state
-- of its source (pages / cursor), so the next call returns the next page.
local function FetchPage(view, typeInfo, keyword, sort)
    local wantBundles = typeInfo.Bundle ~= nil
    local engineDetail
    if not engineBroken and view.Backend ~= "web" then
        Throttle()
        local ok, result = pcall(function()
            if not view.Pages then
                view.Pages = EngineStart(typeInfo, keyword, sort)
            elseif not view.Pages.IsFinished then
                view.Pages:AdvanceToNextPageAsync()
            end
            return { Items = EngineItems(view.Pages, wantBundles), Done = view.Pages.IsFinished == true }
        end)
        if ok then
            view.Backend = "engine"
            return result.Items, result.Done
        end
        engineDetail = tostring(result)
        if view.Backend == "engine" then return nil, nil, "failed", engineDetail end
        view.Pages = nil
        engineFailures = engineFailures + 1
        if engineFailures >= 3 then engineBroken = true end
    end

    local data, kind, detail = CatalogGet(CatalogUrl(typeInfo, keyword, sort, view.Cursor))
    if not data then
        return nil, nil, kind, engineDetail and ("game catalog: " .. engineDetail .. " / web: " .. tostring(detail)) or detail
    end
    view.Backend = "web"

    local list = {}
    for _, item in ipairs(type(data.data) == "table" and data.data or {}) do
        local isBundle = item.itemType == "Bundle"
        if type(item.id) == "number" and type(item.name) == "string" and isBundle == wantBundles then
            table.insert(list, {
                Id = item.id, Name = item.name, IsBundle = isBundle, AssetType = (not isBundle) and tonumber(item.assetType) or nil,
                Price = item.price, Status = item.priceStatus, Creator = item.creatorName,
            })
        end
    end
    view.Cursor = type(data.nextPageCursor) == "string" and data.nextPageCursor or nil
    return list, view.Cursor == nil
end

-- May yield. The parts of a bundle: a list of { Id, Name } (assets only). From the game's catalog first, then the web.
local function FetchBundleParts(bundleId)
    local parts = {}

    local ok, details = pcall(function()
        local itemType = EnumNamed(Enum.AvatarItemType, "Bundle")
        return game:GetService("AvatarEditorService"):GetItemDetails(bundleId, itemType)
    end)
    if ok and type(details) == "table" and type(details.BundledItems) == "table" then
        for _, item in ipairs(details.BundledItems) do
            local itemType = tostring(item.Type or item.ItemType or "Asset")
            if type(item.Id) == "number" and not string.find(itemType, "Outfit", 1, true) then
                table.insert(parts, { Id = item.Id, Name = tostring(item.Name or ("Item " .. item.Id)) })
            end
        end
    end

    if #parts == 0 then
        local data = CatalogGet("/v1/bundles/details?bundleIds=" .. string.format("%.0f", bundleId))
        local bundle = type(data) == "table" and data[1]
        for _, item in ipairs(type(bundle) == "table" and type(bundle.items) == "table" and bundle.items or {}) do
            if type(item.id) == "number" and (item.type == nil or item.type == "Asset") then
                table.insert(parts, { Id = item.id, Name = tostring(item.name or ("Item " .. item.id)) })
            end
        end
    end
    return parts
end

local function BuildCatalogUI()
    local entryByKey = {}
    local featured = {}
    local bundleParts = {} -- [bundleId] = list of part entries, once a bundle has been opened
    local side = { Query = "", TileList = {}, TileByEntry = {} }
    local view = {
        Group = 1, TypeIndex = 1, Bundle = nil, BundleEntries = nil,
        Entries = {}, Cursor = nil, Pages = nil, Backend = nil,
        Loading = false, Done = false, Failed = false, RetryAt = 0, Token = 0,
    }
    local sortIndex, sortChosen = DEFAULT_SORT, false
    local statusUntil = 0
    local PaintAll, Render, LoadMore, SelectGroup, SelectType, UpdateRow, Layout, OpenBundle, ResetBrowse
    local ToggleDirect, LoadBundleParts, RefreshAvatar, ShowPage

    -- one entry per item (assets and bundles are numbered separately), shared by Featured and every result
    local function GetEntry(id, name, extra)
        local key = ((extra and extra.IsBundle) and "b" or "a") .. string.format("%.0f", id)
        local entry = entryByKey[key]
        if not entry then
            entry = { Id = id, Name = name }
            entryByKey[key] = entry
        end
        if name and name ~= "" and not entry.Pinned then entry.Name = name end
        for field, value in pairs(extra or {}) do entry[field] = value end
        return entry
    end

    local function Feature(entry)
        if not table.find(featured, entry) then table.insert(featured, entry) end
    end

    for _, template in ipairs(Catalog.Templates) do
        Feature(GetEntry(template.ID, template.Name, { Pinned = true }))
    end

    local function Browsing()
        return GROUPS[view.Group].Types ~= nil and view.Bundle == nil
    end

    local function ShowHint()
        local count = Catalog.AppliedCount()
        if view.Bundle then
            StatusLabel.Text = "Pick the parts of " .. view.Bundle.Name .. " to wear, or all of them."
        elseif count == 0 then
            StatusLabel.Text = "Pick an item, or paste an asset ID."
        else
            StatusLabel.Text = "Wearing " .. count .. " item" .. (count == 1 and "" or "s") .. ". Pick one again to take it off."
        end
        StatusLabel.TextColor3 = THEME.SubText
    end

    local function SetStatus(text, color, duration)
        statusUntil = os.clock() + (duration or 3.5)
        StatusLabel.Text = text
        StatusLabel.TextColor3 = color or THEME.SubText
        task.delay((duration or 3.5) + 0.1, function()
            if os.clock() >= statusUntil then ShowHint() end
        end)
    end

    local function BundleWorn(entry)
        local parts = bundleParts[entry.Id]
        if not parts or #parts == 0 then return false end
        for _, part in ipairs(parts) do
            if not Catalog.IsApplied(part.Id) then return false end
        end
        return true
    end

    -- ---------- cells ----------
    local function PaintTile(tile, hovered)
        local entry = tile.Entry
        local on = entry.IsBundle and BundleWorn(entry) or (not entry.IsBundle and Catalog.IsApplied(entry.Id))
        tile.Button.BackgroundTransparency = on and 0.82 or (hovered and 0.9 or 0.95)
        tile.Badge.Visible = on
        tile.Stroke.Color = on and THEME.Accent or THEME.Stroke
        tile.Stroke.Transparency = on and 0.2 or (hovered and 0.7 or THEME.StrokeAlpha)
        tile.Stroke.Thickness = on and 1.5 or 1
    end

    local BundleAction

    PaintAll = function()
        for _, tile in ipairs(side.TileList) do PaintTile(tile, false) end
        local count = Catalog.AppliedCount()
        side.CountLabel.Text = "Applied: " .. count
        side.CountLabel.TextColor3 = count > 0 and THEME.Text or THEME.Muted
        if BundleAction then
            BundleAction.Label.Text = (view.Bundle and BundleWorn(view.Bundle)) and "Take off all" or "Wear all"
        end
        if os.clock() >= statusUntil then ShowHint() end
    end

    local function Toggle(entry)
        if entry.IsBundle then
            if entry.Direct then ToggleDirect(entry) else OpenBundle(entry) end
            return
        end
        if Catalog.IsApplied(entry.Id) then
            Catalog.Remove(entry.Id)
            PaintAll()
            return
        end
        SetStatus("Applying " .. entry.Name .. "...")
        task.spawn(function()
            local ok, message = Catalog.Apply(entry.Id, entry.AssetType)
            PaintAll()
            if ok then
                SetStatus(entry.Name .. " equipped.", THEME.Success)
            else
                SetStatus(message, THEME.Danger)
            end
        end)
    end

    local function MakeTile(entry)
        local button = New("TextButton", {
            Name = tostring(entry.Id),
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0.95,
        }, side.Scroll)
        Round(button, 10)
        local stroke = Stroke(button, THEME.StrokeAlpha)

        local thumb = New("Frame", {
            Name = "Thumb",
            Position = UDim2.fromOffset(5, 5),
            Size = UDim2.new(1, -10, 0, CELL_HEIGHT - 10 - TITLE_HEIGHT),
            BackgroundColor3 = THEME.Field,
            BackgroundTransparency = THEME.FieldAlpha,
            ClipsDescendants = true,
            BorderSizePixel = 0,
        }, button)
        Round(thumb, 7)
        Label(thumb, {
            Text = string.upper(string.sub(entry.Name, 1, 1)),
            Font = FONT_TITLE,
            TextSize = 26,
            TextColor3 = THEME.Muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            Size = UDim2.fromScale(1, 1),
        })
        New("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, -6, 1, -6),
            BackgroundTransparency = 1,
            Image = ThumbnailOf(entry),
            ScaleType = Enum.ScaleType.Fit,
        }, thumb)

        local price = Label(thumb, {
            Text = "",
            Font = FONT_LABEL,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Center,
            BackgroundTransparency = 0.45,
            BackgroundColor3 = Color3.new(0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Position = UDim2.fromOffset(4, 4),
            Size = UDim2.fromOffset(0, 15),
            ZIndex = 2,
            Visible = false,
        })
        Round(price, 5)
        New("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, price)

        -- bundles are marked: opening one shows its parts
        if entry.IsBundle then
            local tag = Label(thumb, {
                Text = "BUNDLE",
                Font = FONT_TITLE,
                TextSize = 9,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextColor3 = THEME.OnAccent,
                BackgroundTransparency = 0,
                BackgroundColor3 = Color3.new(1, 1, 1),
                AnchorPoint = Vector2.new(0, 1),
                AutomaticSize = Enum.AutomaticSize.X,
                Position = UDim2.new(0, 4, 1, -4),
                Size = UDim2.fromOffset(0, 14),
                ZIndex = 2,
            })
            Round(tag, 5)
            New("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, tag)
        end

        local name = Label(button, {
            Text = entry.Name,
            Font = FONT_LABEL,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.new(0, 6, 0, CELL_HEIGHT - TITLE_HEIGHT - 2),
            Size = UDim2.new(1, -12, 0, TITLE_HEIGHT),
        })

        local badge = New("Frame", {
            Name = "Badge",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -9, 0, 9),
            Size = UDim2.fromOffset(18, 18),
            BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 3,
        }, button)
        Round(badge, 9)
        CheckGlyph(badge, 12, THEME.OnAccent)

        local tile = { Entry = entry, Button = button, Stroke = stroke, Badge = badge, Name = name, Price = price }
        button.MouseEnter:Connect(function() PaintTile(tile, true) end)
        button.MouseLeave:Connect(function() PaintTile(tile, false) end)
        button.MouseButton1Click:Connect(function() Toggle(entry) end)
        return tile
    end

    -- The list shown now: the parts of an open bundle, Featured (filtered by the typed text), or catalog results.
    local function CurrentList()
        if view.Bundle then return view.BundleEntries or {} end
        if GROUPS[view.Group].Pages then return {} end
        if GROUPS[view.Group].Types == nil then
            local query = string.lower(side.Query)
            if query == "" then return featured end
            local list = {}
            for _, entry in ipairs(featured) do
                if string.find(string.lower(entry.Name), query, 1, true) or string.find(tostring(entry.Id), query, 1, true) then
                    table.insert(list, entry)
                end
            end
            return list
        end
        return view.Entries
    end

    Render = function()
        local list, map = {}, {}
        for _, entry in ipairs(CurrentList()) do
            local tile = side.TileByEntry[entry] or MakeTile(entry)
            tile.Button.LayoutOrder = #list + 1
            tile.Name.Text = entry.Name
            local priceText = PriceText(entry)
            tile.Price.Text = priceText
            tile.Price.Visible = priceText ~= ""
            table.insert(list, tile)
            map[entry] = tile
        end
        for entry, tile in pairs(side.TileByEntry) do
            if not map[entry] then tile.Button:Destroy() end
        end
        side.TileList, side.TileByEntry = list, map
        PaintAll()
    end

    -- ---------- catalog loading ----------
    local function NeedsMore()
        local scroll = side.Scroll
        local remaining = scroll.AbsoluteCanvasSize.Y - (scroll.CanvasPosition.Y + scroll.AbsoluteWindowSize.Y)
        return remaining < 160
    end

    LoadMore = function()
        if not Browsing() or view.Loading or view.Done then return end
        if view.Failed then
            if os.clock() < view.RetryAt then return end
            view.Failed = false
        end
        view.Loading = true
        local mine = view.Token
        local typeInfo = GROUPS[view.Group].Types[view.TypeIndex]
        local keyword = string.match(side.Query, "^%s*(.-)%s*$")
        local sort = SORTS[(keyword ~= "" and not sortChosen) and SEARCH_SORT or sortIndex]
        if keyword == "" and sort.Type == 0 then sort = SORTS[DEFAULT_SORT] end

        SetStatus("Loading catalog...", THEME.SubText, 30)
        local items, done, reason, detail = FetchPage(view, typeInfo, keyword, sort)
        if mine ~= view.Token then return end
        view.Loading = false

        if not items then
            view.Failed = true
            view.RetryAt = os.clock() + 5
            if detail then warn("[Visual Catalog] catalog: " .. tostring(detail)) end
            if reason == "no-request" then
                SetStatus("Catalog browsing is unavailable here: the game catalog failed and this executor has no request function.", THEME.Danger, 8)
                if view.Group ~= 1 then SelectGroup(1) end
            elseif reason == "rate" then
                SetStatus("Roblox is limiting catalog requests. Try again in a moment.", THEME.Danger, 6)
            else
                SetStatus("Could not load the catalog (" .. string.sub(tostring(detail), 1, 60) .. "). Scroll again to retry.", THEME.Danger, 6)
            end
            return
        end

        for _, item in ipairs(items) do
            local entry = GetEntry(item.Id, item.Name, {
                IsBundle = item.IsBundle, AssetType = item.AssetType, Price = item.Price, Status = item.Status, Creator = item.Creator,
                Direct = (item.IsBundle and typeInfo.Direct) or nil,
            })
            if not table.find(view.Entries, entry) then table.insert(view.Entries, entry) end
        end
        view.Done = done

        Render()
        if #view.Entries == 0 then
            SetStatus("Nothing found.", THEME.SubText)
        else
            statusUntil = 0
            ShowHint()
        end
        -- the first pages may not fill the window yet
        if not view.Done and NeedsMore() then task.defer(LoadMore) end
    end

    ResetBrowse = function()
        view.Token = view.Token + 1
        view.Entries, view.Cursor, view.Pages, view.Backend = {}, nil, nil, nil
        view.Loading, view.Done, view.Failed = false, false, false
        side.Scroll.CanvasPosition = Vector2.zero
        Render()
        task.spawn(LoadMore)
    end

    -- dark inset field (Base.Field in Mugiwara UI)
    local function Field(parent, position, size, class, props)
        local merged = {
            BorderSizePixel = 0,
            BackgroundColor3 = THEME.Field,
            BackgroundTransparency = THEME.FieldAlpha,
            Position = position,
            Size = size,
        }
        for field, value in pairs(props or {}) do merged[field] = value end
        local instance = New(class, merged, parent)
        Round(instance, 8)
        Stroke(instance, 0.9)
        return instance
    end

    -- ---------- layout ----------
    local frame = New("Frame", {
        Name = "Catalog",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = THEME.Card,
        BackgroundTransparency = THEME.CardAlpha,
        BorderSizePixel = 0,
    }, PaneHolder)
    Round(frame, 10)
    Stroke(frame, 0.9)

    local inner = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, frame)
    New("UIPadding", {
        PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
    }, inner)

    Label(inner, { Text = "Catalog", Font = FONT_TITLE, TextSize = 15, Size = UDim2.new(0.5, 0, 0, 20) })
    side.CountLabel = Label(inner, {
        Text = "Applied: 0",
        TextSize = 12,
        TextColor3 = THEME.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Position = UDim2.fromScale(0.5, 0),
        Size = UDim2.new(0.5, 0, 0, 20),
    })

    local function MakeChip(parent, title, order)
        local button = New("TextButton", {
            Text = title,
            Font = FONT_LABEL,
            TextSize = 13,
            AutoButtonColor = false,
            BorderSizePixel = 0,
            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.fromOffset(0, 28),
            BackgroundColor3 = Color3.new(1, 1, 1),
            LayoutOrder = order,
        }, parent)
        Round(button, 14)
        New("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, button)
        local gradient = Gradient(button, 0)
        gradient.Enabled = false
        local stroke = Stroke(button, THEME.StrokeAlpha)
        return { Button = button, Gradient = gradient, Stroke = stroke }
    end

    local function PaintChip(chip, on)
        chip.Button.BackgroundTransparency = on and 0 or THEME.CardAlpha
        chip.Gradient.Enabled = on
        chip.Button.TextColor3 = on and THEME.OnAccent or THEME.SubText
        chip.Stroke.Transparency = on and 1 or THEME.StrokeAlpha
    end

    -- sideways-scrolling row of chips (mouse wheel, drag or swipe)
    local function MakeChipRow(y, parent)
        local row = New("ScrollingFrame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, y),
            Size = UDim2.new(1, 0, 0, 30),
            ScrollBarThickness = 0,
            ScrollingDirection = Enum.ScrollingDirection.X,
            ElasticBehavior = Enum.ElasticBehavior.Never,
            AutomaticCanvasSize = Enum.AutomaticSize.X,
            CanvasSize = UDim2.new(),
        }, parent or inner)
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 6),
        }, row)

        -- the mouse wheel scrolls the row sideways while the cursor is over it
        local hovering = false
        row.MouseEnter:Connect(function() hovering = true end)
        row.MouseLeave:Connect(function() hovering = false end)
        local wheel = UserInputService.InputChanged:Connect(function(input)
            if hovering and input.UserInputType == Enum.UserInputType.MouseWheel then
                local maxX = math.max(0, row.AbsoluteCanvasSize.X - row.AbsoluteWindowSize.X)
                row.CanvasPosition = Vector2.new(math.clamp(row.CanvasPosition.X - input.Position.Z * 70, 0, maxX), 0)
            end
        end)
        RegisterCleanup(function() wheel:Disconnect() end)
        return row
    end

    -- row 1: groups
    local groupRow = MakeChipRow(26)
    local groupChips = {}
    for index, group in ipairs(GROUPS) do
        groupChips[index] = MakeChip(groupRow, group.Title, index)
        groupChips[index].Button.MouseButton1Click:Connect(function() SelectGroup(index) end)
    end

    -- row 2: the types of the group (rebuilt per group), or the bar of an open bundle
    local typeRow = MakeChipRow(60)
    local typeChips = {}

    local function PaintChips()
        for index, chip in ipairs(groupChips) do PaintChip(chip, index == view.Group) end
        for index, chip in ipairs(typeChips) do PaintChip(chip, index == view.TypeIndex) end
    end

    local function BuildTypeChips()
        for _, chip in ipairs(typeChips) do chip.Button:Destroy() end
        typeChips = {}
        typeRow.CanvasPosition = Vector2.zero
        local group = GROUPS[view.Group]
        for index, typeInfo in ipairs(group.Types or group.Pages or {}) do
            typeChips[index] = MakeChip(typeRow, type(typeInfo) == "table" and typeInfo.Title or typeInfo, index)
            typeChips[index].Button.MouseButton1Click:Connect(function() SelectType(index) end)
        end
    end

    local bundleBar = New("Frame", {
        Position = UDim2.fromOffset(0, 60),
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        Visible = false,
    }, inner)
    local BackButton = MakeButton(bundleBar, "Back", false, 66)
    BackButton.Frame.Size = UDim2.fromOffset(66, 30)
    local bundleName = Label(bundleBar, {
        Text = "",
        Font = FONT_LABEL,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Position = UDim2.fromOffset(76, 0),
        Size = UDim2.new(1, -186, 1, 0),
    })
    BundleAction = MakeButton(bundleBar, "Wear all", true, 100)
    BundleAction.Frame.AnchorPoint = Vector2.new(1, 0)
    BundleAction.Frame.Position = UDim2.new(1, 0, 0, 0)

    -- row 3: search / asset id box, with the sort button (catalog) or the Add button (an id was typed) beside it
    local SIDE_BUTTON = 118
    local search = Field(inner, UDim2.fromOffset(0, 62), UDim2.new(1, 0, 0, 32), "TextBox", {
        Text = "",
        PlaceholderText = "Search, or paste an asset ID / link...",
        PlaceholderColor3 = THEME.Muted,
        TextColor3 = THEME.Text,
        Font = FONT_BODY,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
    })
    New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, search)

    local SortButton = MakeButton(inner, SORTS[sortIndex].Name, false, SIDE_BUTTON)
    SortButton.Frame.AnchorPoint = Vector2.new(1, 0)
    SortButton.Label.TextSize = 12
    local AddButton = MakeButton(inner, "Add", true, SIDE_BUTTON)
    AddButton.Frame.AnchorPoint = Vector2.new(1, 0)

    -- grid, open from the start
    side.Scroll = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.Muted,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
    }, inner)
    New("UIPadding", {
        PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3),
        PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 6),
    }, side.Scroll)
    ResponsiveGrid(side.Scroll, GAP, CELL_HEIGHT, 110)

    -- ---------- the Avatar group: what is worn (with a preview) and the colors of the body ----------
    local avatarPanel = New("Frame", {
        BackgroundTransparency = 1,
        Visible = false,
        Position = UDim2.fromOffset(0, 96),
        Size = UDim2.new(1, 0, 1, -96),
    }, inner)

    local function SmallButton(parent, text, width)
        local button = New("TextButton", {
            Text = text,
            Font = FONT_LABEL,
            TextSize = 12,
            TextColor3 = THEME.Text,
            AutoButtonColor = false,
            BorderSizePixel = 0,
            BackgroundColor3 = THEME.Card,
            BackgroundTransparency = 0.88,
            Size = UDim2.fromOffset(width, 26),
        }, parent)
        Round(button, 8)
        Stroke(button, 0.85)
        button.MouseEnter:Connect(function() button.BackgroundTransparency = 0.78 end)
        button.MouseLeave:Connect(function() button.BackgroundTransparency = 0.88 end)
        return button
    end

    -- page 1: preview and the list of what is worn
    local wearPage = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, avatarPanel)
    local viewHolder = Field(wearPage, UDim2.fromOffset(0, 0), UDim2.new(0.4, -4, 1, 0), "Frame", { ClipsDescendants = true })
    local viewport = New("ViewportFrame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Ambient = Color3.fromRGB(190, 190, 190),
        LightColor = Color3.fromRGB(255, 255, 255),
    }, viewHolder)
    local viewCamera = New("Camera", { FieldOfView = 30 }, viewport)
    viewport.CurrentCamera = viewCamera
    local viewHint = Label(viewHolder, {
        Text = "Drag to turn",
        TextSize = 11,
        TextColor3 = THEME.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 18),
        ZIndex = 3,
    })

    local wearList = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0.4, 4, 0, 0),
        Size = UDim2.new(0.6, -4, 1, -36),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.Muted,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
    }, wearPage)
    New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, wearList)
    New("UIPadding", { PaddingRight = UDim.new(0, 6) }, wearList)

    local RestoreAllButton = SmallButton(wearPage, "Put originals back", 140)
    RestoreAllButton.AnchorPoint = Vector2.new(0, 1)
    RestoreAllButton.Position = UDim2.new(0.4, 4, 1, 0)
    RestoreAllButton.MouseButton1Click:Connect(function()
        Catalog.RestoreTaken()
        SetStatus("Original items put back.", THEME.Success)
    end)

    local wearRows = {}
    local function RefreshWearing()
        for _, row in ipairs(wearRows) do row:Destroy() end
        wearRows = {}
        local order = 0

        local function AddRow(title, subtitle, buttonText, callback)
            order = order + 1
            local row = New("Frame", {
                Size = UDim2.new(1, 0, 0, 40),
                BackgroundColor3 = THEME.Card,
                BackgroundTransparency = 0.94,
                BorderSizePixel = 0,
                LayoutOrder = order,
            }, wearList)
            Round(row, 8)
            Stroke(row, THEME.StrokeAlpha)
            Label(row, { Text = title, Font = FONT_LABEL, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -92, 0, 18) })
            Label(row, { Text = subtitle, TextSize = 11, TextColor3 = THEME.Muted, Position = UDim2.fromOffset(10, 22), Size = UDim2.new(1, -92, 0, 14) })
            local button = SmallButton(row, buttonText, 70)
            button.AnchorPoint = Vector2.new(1, 0.5)
            button.Position = UDim2.new(1, -7, 0.5, 0)
            button.MouseButton1Click:Connect(callback)
            table.insert(wearRows, row)
        end

        local worn = Catalog.ListWorn()
        if #worn == 0 then
            order = order + 1
            local empty = Label(wearList, { Text = "Nothing found on the character.", TextColor3 = THEME.Muted, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = order })
            table.insert(wearRows, empty)
        end
        for _, item in ipairs(worn) do
            AddRow(item.Name, item.Kind .. (item.Ours and "  ·  added here" or "  ·  original"), "Remove", function()
                task.spawn(function() Catalog.TakeOff(item) end)
            end)
        end

        local takenList = Catalog.ListTaken()
        if #takenList > 0 then
            order = order + 1
            local header = Label(wearList, { Text = "Taken off", Font = FONT_TITLE, TextSize = 13, TextColor3 = THEME.SubText, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order })
            table.insert(wearRows, header)
            for _, item in ipairs(takenList) do
                AddRow(item.Name, item.Kind .. "  ·  taken off", "Put back", function()
                    Catalog.RestoreTaken(item.Name, item.Kind)
                end)
            end
        end
        RestoreAllButton.Visible = #takenList > 0
    end

    -- the preview: a copy of the rig in a viewport, turned by dragging
    local yaw, viewCenter, viewFront, viewDistance = 0, Vector3.new(), Vector3.new(0, 0, -1), 10
    local function PlaceViewCamera()
        local direction = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(viewFront)
        viewCamera.CFrame = CFrame.lookAt(viewCenter + direction * viewDistance, viewCenter)
    end

    local function RefreshViewport()
        for _, child in ipairs(viewport:GetChildren()) do
            if child ~= viewCamera then child:Destroy() end
        end
        local first = Rigs.GetAll()[1]
        if not first then
            viewHint.Text = "No character found yet."
            return
        end
        local ok, clone = pcall(function() return first.Rig:Clone() end)
        if not ok or not clone then
            viewHint.Text = "Preview is not available for this character."
            return
        end
        viewHint.Text = "Drag to turn"
        for _, descendant in ipairs(clone:GetDescendants()) do
            if descendant:IsA("BaseScript") then
                descendant:Destroy()
            elseif descendant:IsA("BasePart") then
                descendant.Anchored = true
            end
        end
        clone.Parent = viewport

        local ok2, boxCFrame, boxSize = pcall(function() return clone:GetBoundingBox() end)
        if not ok2 then return end
        viewCenter = boxCFrame.Position
        local head = clone:FindFirstChild("Head")
        local look = head and head.CFrame.LookVector or boxCFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        viewFront = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
        viewDistance = math.max(boxSize.X, boxSize.Y, boxSize.Z) / (2 * math.tan(math.rad(15))) * 1.15
        PlaceViewCamera()
    end

    local viewToken = 0
    local function ScheduleViewport(delay)
        viewToken = viewToken + 1
        local mine = viewToken
        task.delay(delay or 0.35, function()
            if mine == viewToken and avatarPanel.Visible and wearPage.Visible then RefreshViewport() end
        end)
    end

    do
        local dragging, lastX = false, 0
        viewHolder.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging, lastX = true, input.Position.X
            end
        end)
        local moved = UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                yaw = yaw - (input.Position.X - lastX) * 0.012
                lastX = input.Position.X
                PlaceViewCamera()
            end
        end)
        local ended = UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
        RegisterCleanup(function()
            moved:Disconnect()
            ended:Disconnect()
        end)
    end

    -- page 2: body colors
    local colorPage = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, avatarPanel)
    local REGION_TITLES = {
        { Key = "All", Title = "All" }, { Key = "Head", Title = "Head" }, { Key = "Torso", Title = "Torso" },
        { Key = "LeftArm", Title = "Left Arm" }, { Key = "RightArm", Title = "Right Arm" },
        { Key = "LeftLeg", Title = "Left Leg" }, { Key = "RightLeg", Title = "Right Leg" },
    }
    local colorRegion = 1
    local regionRow = MakeChipRow(0, colorPage)
    local regionChips = {}
    local colorInfo

    local PALETTE = {
        { 255, 224, 189 }, { 241, 194, 125 }, { 224, 172, 105 }, { 198, 134, 66 }, { 141, 85, 36 }, { 92, 58, 33 }, { 62, 38, 24 },
        { 255, 204, 153 }, { 234, 184, 146 }, { 204, 142, 105 }, { 255, 255, 255 }, { 242, 243, 243 }, { 160, 165, 169 }, { 99, 95, 98 },
        { 27, 42, 53 }, { 0, 0, 0 }, { 196, 40, 28 }, { 218, 133, 65 }, { 245, 205, 48 }, { 75, 151, 75 }, { 40, 127, 71 }, { 18, 238, 212 },
        { 13, 105, 172 }, { 16, 42, 220 }, { 107, 50, 124 }, { 255, 102, 204 }, { 255, 152, 220 }, { 170, 85, 255 },
    }

    local function ToHex(color)
        return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
    end

    local function RefreshColorInfo()
        local key = REGION_TITLES[colorRegion].Key
        local text
        if key == "All" then
            local first, mixed = Catalog.GetBodyColor("Head"), false
            for _, region in ipairs(Catalog.Regions) do
                if Catalog.GetBodyColor(region) ~= first then mixed = true end
            end
            text = mixed and "Different colors per part" or (first and ToHex(first) or "Original colors")
        else
            local color = Catalog.GetBodyColor(key)
            text = color and ToHex(color) or "Original color"
        end
        colorInfo.Text = REGION_TITLES[colorRegion].Title .. ":  " .. text
    end

    local function PaintRegionChips()
        for index, chip in ipairs(regionChips) do PaintChip(chip, index == colorRegion) end
    end
    for index, region in ipairs(REGION_TITLES) do
        regionChips[index] = MakeChip(regionRow, region.Title, index)
        regionChips[index].Button.MouseButton1Click:Connect(function()
            colorRegion = index
            PaintRegionChips()
            RefreshColorInfo()
        end)
    end
    PaintRegionChips()

    local swatches = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 38),
        Size = UDim2.new(1, 0, 1, -118),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.Muted,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
    }, colorPage)
    New("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 6) }, swatches)
    New("UIGridLayout", { SortOrder = Enum.SortOrder.LayoutOrder, CellSize = UDim2.fromOffset(40, 40), CellPadding = UDim2.fromOffset(8, 8) }, swatches)
    for index, rgb in ipairs(PALETTE) do
        local swatch = New("TextButton", {
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
            LayoutOrder = index,
        }, swatches)
        Round(swatch, 10)
        Stroke(swatch, 0.6)
        swatch.MouseButton1Click:Connect(function()
            Catalog.SetBodyColor(REGION_TITLES[colorRegion].Key, Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
            RefreshColorInfo()
        end)
    end

    local colorBottom = New("Frame", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 74),
    }, colorPage)
    local hexBox = Field(colorBottom, UDim2.fromOffset(0, 0), UDim2.new(1, -86, 0, 32), "TextBox", {
        Text = "",
        PlaceholderText = "Hex color, like #FFAA00",
        PlaceholderColor3 = THEME.Muted,
        TextColor3 = THEME.Text,
        Font = FONT_BODY,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
    })
    New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, hexBox)
    local HexApply = MakeButton(colorBottom, "Apply", true, 78)
    HexApply.Frame.AnchorPoint = Vector2.new(1, 0)
    HexApply.Frame.Position = UDim2.new(1, 0, 0, 0)

    colorInfo = Label(colorBottom, { Text = "", TextColor3 = THEME.SubText, Position = UDim2.fromOffset(2, 42), Size = UDim2.new(1, -190, 0, 28) })
    local ResetColor = SmallButton(colorBottom, "Reset part", 86)
    ResetColor.AnchorPoint = Vector2.new(1, 0)
    ResetColor.Position = UDim2.new(1, -94, 0, 42)
    ResetColor.MouseButton1Click:Connect(function()
        Catalog.SetBodyColor(REGION_TITLES[colorRegion].Key, nil)
        RefreshColorInfo()
    end)
    local ResetAllColors = SmallButton(colorBottom, "Reset all", 86)
    ResetAllColors.AnchorPoint = Vector2.new(1, 0)
    ResetAllColors.Position = UDim2.new(1, 0, 0, 42)
    ResetAllColors.MouseButton1Click:Connect(function()
        Catalog.ResetColors()
        RefreshColorInfo()
    end)

    local function ApplyHex()
        local hex = string.match(hexBox.Text, "^%s*#?(%x%x%x%x%x%x)%s*$")
        if not hex then
            SetStatus("Type a color like #FFAA00 (six hex digits).", THEME.Danger)
            return
        end
        local color = Color3.fromRGB(tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16))
        Catalog.SetBodyColor(REGION_TITLES[colorRegion].Key, color)
        RefreshColorInfo()
    end
    HexApply.Hit.MouseButton1Click:Connect(ApplyHex)
    hexBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then ApplyHex() end
    end)
    RefreshColorInfo()

    ShowPage = function(index)
        wearPage.Visible = index == 1
        colorPage.Visible = index == 2
        if index == 1 then
            RefreshWearing()
            ScheduleViewport(0.05)
        else
            RefreshColorInfo()
        end
    end

    -- called whenever something is worn, taken off or recolored
    RefreshAvatar = function()
        if not avatarPanel.Visible then return end
        if wearPage.Visible then
            RefreshWearing()
            ScheduleViewport(0.4)
        end
        RefreshColorInfo()
    end


    -- Positions follow what is visible: the type row only exists for groups with types, an open bundle swaps it
    -- for the bundle bar and hides the search box.
    Layout = function()
        local group = GROUPS[view.Group]
        local inBundle = view.Bundle ~= nil
        local isPanel = group.Pages ~= nil
        local hasTypes = (group.Types ~= nil or isPanel) and not inBundle
        typeRow.Visible = hasTypes
        bundleBar.Visible = inBundle
        avatarPanel.Visible = isPanel
        side.Scroll.Visible = not isPanel

        local searchY = (hasTypes or inBundle) and 96 or 62
        search.Visible = not inBundle and not isPanel
        search.Position = UDim2.fromOffset(0, searchY)
        SortButton.Frame.Position = UDim2.new(1, 0, 0, searchY)
        AddButton.Frame.Position = UDim2.new(1, 0, 0, searchY)

        local gridY = inBundle and (searchY - 0) or (searchY + 40)
        side.Scroll.Position = UDim2.fromOffset(0, gridY)
        side.Scroll.Size = UDim2.new(1, 0, 1, -gridY)
    end

    UpdateRow = function()
        local isId = LooksLikeId(search.Text)
        local browsing = Browsing()
        local isPanel = GROUPS[view.Group].Pages ~= nil
        AddButton.Frame.Visible = isId and view.Bundle == nil and not isPanel
        SortButton.Frame.Visible = browsing and not isId
        local right = ((isId or browsing) and view.Bundle == nil and not isPanel) and (SIDE_BUTTON + 8) or 0
        search.Size = UDim2.new(1, -right, 0, 32)
        local keyword = string.match(side.Query, "^%s*(.-)%s*$")
        local shown = SORTS[(keyword ~= "" and not sortChosen) and SEARCH_SORT or sortIndex]
        if keyword == "" and shown.Type == 0 then shown = SORTS[DEFAULT_SORT] end
        SortButton.Label.Text = shown.Name
    end

    -- ---------- behaviour ----------
    local function CatalogUnavailable()
        return engineBroken and not RequestFunction()
    end

    SelectGroup = function(index)
        if GROUPS[index].Types and CatalogUnavailable() then
            SetStatus("Catalog browsing is unavailable here: the game catalog failed and this executor has no request function.", THEME.Danger, 8)
            return
        end
        view.Group = index
        view.TypeIndex = 1
        view.Bundle, view.BundleEntries = nil, nil
        BuildTypeChips()
        PaintChips()
        Layout()
        UpdateRow()
        if GROUPS[index].Types then
            ResetBrowse()
        else
            view.Token = view.Token + 1
            side.Scroll.CanvasPosition = Vector2.zero
            Render()
            if GROUPS[index].Pages then ShowPage(1) end
        end
    end

    SelectType = function(index)
        view.TypeIndex = index
        PaintChips()
        if GROUPS[view.Group].Pages then
            ShowPage(index)
        else
            ResetBrowse()
        end
    end

    -- May yield. The wearable parts of a bundle as entries (cached).
    LoadBundleParts = function(entry)
        local cached = bundleParts[entry.Id]
        if cached then return cached end
        local parts = {}
        for _, part in ipairs(FetchBundleParts(entry.Id)) do
            local assetType = Catalog.AssetTypeOf(part.Id)
            if assetType and Catalog.IsSupportedType(assetType) then
                table.insert(parts, GetEntry(part.Id, part.Name, { AssetType = assetType }))
            end
        end
        bundleParts[entry.Id] = parts
        return parts
    end

    -- Opens a bundle: its parts (shoes, head, face...) become the grid, each worn on its own.
    OpenBundle = function(entry)
        view.Bundle, view.BundleEntries = entry, nil
        bundleName.Text = entry.Name
        side.Scroll.CanvasPosition = Vector2.zero
        Layout()
        UpdateRow()
        Render()
        SetStatus("Loading " .. entry.Name .. "...", THEME.SubText, 30)

        task.spawn(function()
            local parts = LoadBundleParts(entry)
            if view.Bundle ~= entry then return end
            view.BundleEntries = parts
            Render()
            if #parts == 0 then
                SetStatus("Nothing in this bundle can be worn here.", THEME.SubText)
            else
                statusUntil = 0
                ShowHint()
            end
        end)
    end

    -- A bundle that is worn with one click (dynamic heads, shoes): all its parts together, or all of them off.
    ToggleDirect = function(entry)
        if BundleWorn(entry) then
            local ids = {}
            for _, part in ipairs(bundleParts[entry.Id]) do table.insert(ids, part.Id) end
            task.spawn(function()
                Catalog.RemoveMany(ids)
                PaintAll()
                SetStatus(entry.Name .. " taken off.", THEME.Success)
            end)
            return
        end
        SetStatus("Applying " .. entry.Name .. "...", THEME.SubText, 30)
        task.spawn(function()
            local parts = LoadBundleParts(entry)
            if #parts == 0 then
                SetStatus("Nothing in this bundle can be worn here.", THEME.Danger)
                return
            end
            local list = {}
            for _, part in ipairs(parts) do
                if not Catalog.IsApplied(part.Id) then table.insert(list, { Id = part.Id, AssetType = part.AssetType }) end
            end
            local ok, message = Catalog.ApplyMany(list)
            PaintAll()
            if ok then
                SetStatus(entry.Name .. " equipped.", THEME.Success)
            else
                SetStatus(tostring(message), THEME.Danger, 6)
            end
        end)
    end

    local function CloseBundle()
        view.Bundle, view.BundleEntries = nil, nil
        Layout()
        UpdateRow()
        side.Scroll.CanvasPosition = Vector2.zero
        Render()
    end

    BackButton.Hit.MouseButton1Click:Connect(CloseBundle)

    BundleAction.Hit.MouseButton1Click:Connect(function()
        local entry = view.Bundle
        local parts = entry and view.BundleEntries
        if not parts or #parts == 0 then return end
        if BundleWorn(entry) then
            local ids = {}
            for _, part in ipairs(parts) do table.insert(ids, part.Id) end
            task.spawn(function()
                Catalog.RemoveMany(ids)
                PaintAll()
                SetStatus(entry.Name .. " taken off.", THEME.Success)
            end)
            return
        end
        SetStatus("Applying " .. entry.Name .. "...", THEME.SubText, 30)
        task.spawn(function()
            -- all parts in one go: the body is rebuilt once for the whole bundle
            local list = {}
            for _, part in ipairs(parts) do
                if not Catalog.IsApplied(part.Id) then table.insert(list, { Id = part.Id, AssetType = part.AssetType }) end
            end
            local ok, message = Catalog.ApplyMany(list)
            PaintAll()
            if ok then
                SetStatus(entry.Name .. " equipped.", THEME.Success)
            else
                SetStatus("Some parts did not fit: " .. tostring(message), THEME.Danger, 6)
            end
        end)
    end)

    local function AddFromInput()
        local text = search.Text
        local id = ParseId(text)
        if not id then
            SetStatus("Type a numeric asset ID or paste a catalog link.", THEME.Danger)
            return
        end
        search.Text = ""

        local isBundle = string.find(text, "/bundles/", 1, true) ~= nil
        local key = (isBundle and "b" or "a") .. string.format("%.0f", id)
        local entry = entryByKey[key]
        if not entry then
            entry = GetEntry(id, (isBundle and "Bundle " or "Item ") .. string.format("%.0f", id), { IsBundle = isBundle or nil })
            -- the real name comes from the catalog, filled in when it arrives
            task.spawn(function()
                local ok, info = pcall(function()
                    return MarketplaceService:GetProductInfo(id, isBundle and Enum.InfoType.Bundle or Enum.InfoType.Asset)
                end)
                if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
                    entry.Name = info.Name
                    Render()
                end
            end)
        end
        Feature(entry)
        if GROUPS[view.Group].Types or view.Bundle then SelectGroup(1) else Render() end
        if isBundle then
            OpenBundle(entry)
        elseif not Catalog.IsApplied(id) then
            Toggle(entry)
        end
    end

    AddButton.Hit.MouseButton1Click:Connect(AddFromInput)
    SortButton.Hit.MouseButton1Click:Connect(function()
        local keyword = string.match(side.Query, "^%s*(.-)%s*$")
        sortChosen = true
        -- Relevance only makes sense with a keyword; without one the list goes Popular -> Newest -> ...
        repeat
            sortIndex = sortIndex % #SORTS + 1
        until keyword ~= "" or SORTS[sortIndex].Type ~= 0
        UpdateRow()
        ResetBrowse()
    end)

    local searchToken = 0
    search.FocusLost:Connect(function(enterPressed)
        if enterPressed and LooksLikeId(search.Text) then AddFromInput() end
    end)
    search:GetPropertyChangedSignal("Text"):Connect(function()
        side.Query = search.Text
        UpdateRow()
        if not Browsing() then
            side.Scroll.CanvasPosition = Vector2.zero
            Render()
        elseif not LooksLikeId(search.Text) then
            searchToken = searchToken + 1
            local mine = searchToken
            task.delay(SEARCH_DELAY, function()
                if mine == searchToken then ResetBrowse() end
            end)
        end
    end)

    -- more results load as the grid nears its end
    side.Scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        if Browsing() and NeedsMore() then task.spawn(LoadMore) end
    end)

    Catalog.OnChange = function()
        PaintAll()
        RefreshAvatar()
    end

    RemoveAllButton.Hit.MouseButton1Click:Connect(function()
        local count = Catalog.Clear()
        PaintAll()
        SetStatus(count > 0 and ("Took off " .. count .. " item" .. (count == 1 and "" or "s") .. ".") or "Nothing to take off.", count > 0 and THEME.Success or THEME.SubText)
    end)

    Layout()
    SelectGroup(DEFAULT_GROUP) -- Accessories / All, most popular first (falls back to Featured when no source works)
end

BuildCatalogUI()
