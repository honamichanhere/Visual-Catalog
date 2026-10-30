-- Visual Accessories (standalone) - by Honami
-- UI is built in this file (styled after Mugiwara UI); the accessory logic is ported from Mugiwara HUB's
-- Manager/VisualAccessories.lua (and the rig lookup of Rigs.lua). Runs in its own window.

local SCRIPT_NAME = "Visual Accessories"

-- ==========================================================
-- Shared shell (identical in Visual Emotes, Visual Carry and Visual Unusual)
-- A script adds its own page to the shell. If another Visual script is already running, the page joins
-- the same window (sidebar with one tab per script, like the hub); alone, a script gets the plain window.
-- ==========================================================

-- Only runs in Evade (same place ids as Mugiwara HUB); in any other game nothing is loaded.
local EVADE_PLACE_IDS = { [9872472334] = true, [99214917572799] = true, [10668472534] = true }
if not EVADE_PLACE_IDS[game.PlaceId] then
    warn("[" .. SCRIPT_NAME .. "] This script only works in Evade.")
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", { Title = SCRIPT_NAME, Text = "This script only works in Evade.", Duration = 6 })
    end)
    return
end

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
        Name = "VisualAccessories",
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
        if getgenv().VisualAccessoriesShell == self then getgenv().VisualAccessoriesShell = nil end
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
    local existing = getgenv().VisualAccessoriesShell
    if existing and existing.Alive and existing.Gui and existing.Gui.Parent then return existing end
    local shell = CreateShell()
    getgenv().VisualAccessoriesShell = shell
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
if env.VisualAccessoriesCleanup then pcall(env.VisualAccessoriesCleanup) end
env.VisualAccessoriesCleanup = ModuleCleanup

-- ==========================================================
-- Rigs (from Games/Evade/Rigs.lua, only what Visual Accessories needs)
-- ==========================================================
-- Evade can have TWO rigs named after the player in Workspace.Rigs (menu/inventory and in-game); both
-- are visual copies and both get the accessories.
local Rigs = {}
do
    local LocalPlayer = Players.LocalPlayer

    function Rigs.GetAll()
        local list = {}

        local container = workspace:FindFirstChild("Rigs")
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model") and child.Name == LocalPlayer.Name then
                    local humanoid = child:FindFirstChildOfClass("Humanoid")
                    if humanoid then table.insert(list, { Rig = child, Humanoid = humanoid }) end
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
-- Accessories engine (ported from Manager/VisualAccessories.lua: Marketplace accessories only)
-- ==========================================================
local Accessories = {}
do
    Accessories.Templates = {
        { Name = "Violet Valkyrie", ID = 1402432199 },
        { Name = "8-Bit Royal Crown", ID = 10159600649 },
        { Name = "Fiery Horns of the Netherworld", ID = 215718515 },
        { Name = "Frozen Horns of the Frigid Planes", ID = 74891470 },
        { Name = "Poisoned Horns of the Toxic Wasteland", ID = 1744060292 },
    }

    Accessories.OnChange = nil -- called (no arguments) whenever the list of worn accessories changes

    local applied = {}  -- [assetId] = true
    local cache = {}    -- [assetId] = Accessory (kept in memory, never parented)
    local alive = true
    local handledRigs = setmetatable({}, { __mode = "k" })

    local function Changed()
        if Accessories.OnChange then task.spawn(Accessories.OnChange) end
    end

    local function GetAllRigs()
        local ok, list = pcall(Rigs.GetAll)
        return ok and type(list) == "table" and list or {}
    end

    local function FindBodyAttachment(character, attachmentName)
        for _, object in ipairs(character:GetDescendants()) do
            if object:IsA("Attachment") and object.Name == attachmentName and object.Parent:IsA("BasePart") then
                return object
            end
        end
        return nil
    end

    -- Puts one accessory on one rig. Returns true when it was really added.
    local function EquipOnRig(character, humanoid, cachedAcc, assetId)
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Accessory") and child:GetAttribute("AssetId") == assetId then
                return false
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

    function Accessories.IsApplied(assetId)
        return applied[assetId] == true
    end

    function Accessories.AppliedCount()
        local count = 0
        for _ in pairs(applied) do count = count + 1 end
        return count
    end

    -- May yield (the asset is downloaded the first time). Returns true, message or false, reason.
    function Accessories.Apply(assetId)
        local rigs = GetAllRigs()
        if #rigs == 0 then return false, "No character found. Spawn into a round first." end

        local cachedAcc = cache[assetId]
        if not cachedAcc then
            local success, objects = pcall(function() return game:GetObjects("rbxassetid://" .. tostring(assetId)) end)
            if success and objects and objects[1] then
                local loaded = objects[1]
                local acc = loaded:IsA("Accessory") and loaded or loaded:FindFirstChildWhichIsA("Accessory", true)
                if acc then
                    local handle = acc:FindFirstChild("Handle")
                    if handle and handle:IsA("BasePart") then
                        handle.CanCollide = false
                        handle.CanTouch = false
                        handle.CanQuery = false
                        handle.Massless = true
                        handle.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)
                        acc:SetAttribute("IsCustomAccessory", true)
                        acc:SetAttribute("AssetId", assetId)

                        cache[assetId] = acc:Clone()
                        cachedAcc = cache[assetId]
                    end
                end
                loaded:Destroy()
            end
        end

        if not cachedAcc then return false, "Could not load that asset. Make sure it is an accessory ID." end

        for _, entry in ipairs(rigs) do
            EquipOnRig(entry.Rig, entry.Humanoid, cachedAcc, assetId)
        end

        applied[assetId] = true
        Changed()
        return true, "Accessory equipped."
    end

    function Accessories.Remove(assetId)
        applied[assetId] = nil
        for _, entry in ipairs(GetAllRigs()) do
            for _, child in ipairs(entry.Rig:GetChildren()) do
                if child:IsA("Accessory") and child:GetAttribute("AssetId") == assetId then child:Destroy() end
            end
        end
        Changed()
    end

    -- Removes every accessory added here. Returns how many were removed from the rigs.
    function Accessories.Clear()
        applied = {}
        local count = 0
        for _, entry in ipairs(GetAllRigs()) do
            for _, child in ipairs(entry.Rig:GetChildren()) do
                if child:IsA("Accessory") and child:GetAttribute("IsCustomAccessory") then
                    child:Destroy()
                    count = count + 1
                end
            end
        end
        Changed()
        return count
    end

    -- A new rig (respawn, or a rig the game rebuilt) gets every active accessory again.
    task.spawn(function()
        while alive do
            task.wait(1)
            for _, entry in ipairs(GetAllRigs()) do
                if not handledRigs[entry.Rig] then
                    handledRigs[entry.Rig] = true
                    task.wait(0.5)
                    if alive and entry.Rig.Parent then
                        for assetId in pairs(table.clone(applied)) do
                            local cachedAcc = cache[assetId]
                            if cachedAcc then pcall(EquipOnRig, entry.Rig, entry.Humanoid, cachedAcc, assetId) end
                        end
                    end
                end
            end
        end
    end)

    RegisterCleanup(function()
        alive = false
        Accessories.OnChange = nil
        pcall(Accessories.Clear)
    end)
end


-- ==========================================================
-- Page in the shared window
-- ==========================================================
Shell = GetShell()
Page = Shell:AddPage({
    Id = "Accessories",
    Title = "Visual Accessories",
    TabTitle = "Accessories",
    Letter = "A",
    Order = 4,
    Width = 430,
    Height = 560,
    Cleanup = ModuleCleanup,
})
local PageLayout = BuildPageLayout(Page.Frame)
local PaneHolder, StatusLabel = PageLayout.PaneHolder, PageLayout.StatusLabel
StatusLabel.Size = UDim2.new(1, -150, 1, 0)
local RemoveAllButton = MakeButton(PageLayout.BottomBar, "Remove All", false, 116)
RemoveAllButton.Frame.AnchorPoint = Vector2.new(1, 0.5)
RemoveAllButton.Frame.Position = UDim2.new(1, -12, 0.5, 0)

-- ==========================================================
-- Accessories browser (same look as Visual Unusual). Every cell shows the accessory's picture (loaded from
-- its asset id). The list comes from the Roblox catalog (accessories only): pick a type in the row at the top,
-- search by keyword, change the order, and more load as you scroll. "Featured" holds the hub's templates and
-- anything added by asset id. Catalog access needs the executor's request function; without it the script
-- falls back to Featured.
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

-- Catalog types. Category 11 is Accessories and Sub narrows it to one slot (hair lives under Body, 18) for the web
-- catalog; AssetTypes are the asset type numbers the game's own catalog (AvatarEditorService) takes:
-- 8 Hat, 41 Hair, 42 Face, 43 Neck, 44 Shoulder, 45 Front, 46 Back, 47 Waist.
local ALL_ACCESSORIES = { 8, 41, 42, 43, 44, 45, 46, 47 }
local TYPES = {
    { Key = "Featured", Title = "Featured" },
    { Key = "All", Title = "All", Category = 11, AssetTypes = ALL_ACCESSORIES },
    { Key = "Head", Title = "Head", Category = 11, Sub = 54, AssetTypes = { 8 } },
    { Key = "Hair", Title = "Hair", Category = 18, Sub = 20, AssetTypes = { 41 } },
    { Key = "Face", Title = "Face", Category = 11, Sub = 21, AssetTypes = { 42 } },
    { Key = "Neck", Title = "Neck", Category = 11, Sub = 22, AssetTypes = { 43 } },
    { Key = "Shoulder", Title = "Shoulder", Category = 11, Sub = 23, AssetTypes = { 44 } },
    { Key = "Front", Title = "Front", Category = 11, Sub = 24, AssetTypes = { 45 } },
    { Key = "Back", Title = "Back", Category = 11, Sub = 25, AssetTypes = { 46 } },
    { Key = "Waist", Title = "Waist", Category = 11, Sub = 26, AssetTypes = { 47 } },
}

local SORTS = {
    { Name = "Relevance", Type = 0, Engine = "Relevance" },
    { Name = "Popular", Type = 2, Aggregation = 3, Engine = "Bestselling", EngineAggregation = "PastWeek" },
    { Name = "Newest", Type = 3, Engine = "RecentlyCreated" },
    { Name = "Most Favorited", Type = 1, Engine = "MostFavorited" },
    { Name = "Price: Low to High", Type = 4, Engine = "PriceLowToHigh" },
    { Name = "Price: High to Low", Type = 5, Engine = "PriceHighToLow" },
}
local DEFAULT_SORT, SEARCH_SORT = 2, 1

local function ThumbnailOf(assetId)
    return "rbxthumb://type=Asset&id=" .. string.format("%.0f", assetId) .. "&w=150&h=150"
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

local function EngineStart(typeInfo, keyword, sort)
    local params = CatalogSearchParams.new()
    if keyword ~= "" then params.SearchKeyword = keyword end
    -- enum items are found by their number, so a renamed item cannot break the lookup
    local assetTypes = {}
    for _, item in ipairs(Enum.AvatarAssetType:GetEnumItems()) do
        if table.find(typeInfo.AssetTypes, item.Value) then table.insert(assetTypes, item) end
    end
    if #assetTypes == 0 then error("no matching AvatarAssetType") end
    params.AssetTypes = assetTypes
    local function EnumNamed(enumType, name)
        for _, item in ipairs(enumType:GetEnumItems()) do
            if item.Name == name then return item end
        end
        return nil
    end
    local sortType = EnumNamed(Enum.CatalogSortType, sort.Engine)
    if sortType then params.SortType = sortType end
    if sort.EngineAggregation then
        local aggregation = EnumNamed(Enum.CatalogSortAggregation, sort.EngineAggregation)
        if aggregation then params.SortAggregation = aggregation end
    end
    return game:GetService("AvatarEditorService"):SearchCatalog(params)
end

local function EngineItems(pages)
    local list = {}
    for _, item in ipairs(pages:GetCurrentPage()) do
        local id, name = item.Id, item.Name
        local isBundle = string.find(tostring(item.ItemType or ""), "Bundle", 1, true) ~= nil
        if type(id) == "number" and type(name) == "string" and not isBundle then
            table.insert(list, { Id = id, Name = name, Price = item.Price, Creator = item.CreatorName })
        end
    end
    return list
end

-- May yield. Returns items (a list of { Id, Name, Price, Status, Creator }) and whether it was the last page,
-- or nil, nil, a failure kind ("no-request", "rate", "failed") and a detail text. The view keeps the state of its
-- source (pages / cursor), so the next call returns the next page.
local function FetchPage(view, typeInfo, keyword, sort)
    local engineDetail
    if not engineBroken and view.Backend ~= "web" then
        Throttle()
        local ok, result = pcall(function()
            if not view.Pages then
                view.Pages = EngineStart(typeInfo, keyword, sort)
            elseif not view.Pages.IsFinished then
                view.Pages:AdvanceToNextPageAsync()
            end
            return { Items = EngineItems(view.Pages), Done = view.Pages.IsFinished == true }
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
        if type(item.id) == "number" and type(item.name) == "string" then
            table.insert(list, { Id = item.id, Name = item.name, Price = item.price, Status = item.priceStatus, Creator = item.creatorName })
        end
    end
    view.Cursor = type(data.nextPageCursor) == "string" and data.nextPageCursor or nil
    return list, view.Cursor == nil
end

local function BuildAccessoriesUI()
    local entryById = {}
    local featured = {}
    local side = { Query = "", TileList = {}, TileByEntry = {} }
    local view = { Type = 1, Entries = {}, Cursor = nil, Pages = nil, Backend = nil, Loading = false, Done = false, Failed = false, RetryAt = 0, Token = 0 }
    local sortIndex, sortChosen = DEFAULT_SORT, false
    local statusUntil = 0
    local PaintAll, Render, LoadMore, SelectType, UpdateRow

    -- one entry per asset id, shared by Featured and every catalog result
    local function GetEntry(assetId, name, extra)
        local entry = entryById[assetId]
        if not entry then
            entry = { Id = assetId, Name = name }
            entryById[assetId] = entry
        end
        if name and name ~= "" and not entry.Pinned then entry.Name = name end
        for key, value in pairs(extra or {}) do entry[key] = value end
        return entry
    end

    local function Feature(entry)
        if not table.find(featured, entry) then table.insert(featured, entry) end
    end

    for _, template in ipairs(Accessories.Templates) do
        local entry = GetEntry(template.ID, template.Name, { Pinned = true })
        Feature(entry)
    end

    local function ShowHint()
        local count = Accessories.AppliedCount()
        if count == 0 then
            StatusLabel.Text = "Pick an accessory, or paste an asset ID."
        else
            StatusLabel.Text = "Wearing " .. count .. " accessor" .. (count == 1 and "y" or "ies") .. ". Pick one again to take it off."
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

    -- ---------- cells ----------
    local function PaintTile(tile, hovered)
        local on = Accessories.IsApplied(tile.Entry.Id)
        tile.Button.BackgroundTransparency = on and 0.82 or (hovered and 0.9 or 0.95)
        tile.Badge.Visible = on
        tile.Stroke.Color = on and THEME.Accent or THEME.Stroke
        tile.Stroke.Transparency = on and 0.2 or (hovered and 0.7 or THEME.StrokeAlpha)
        tile.Stroke.Thickness = on and 1.5 or 1
    end

    PaintAll = function()
        for _, tile in ipairs(side.TileList) do PaintTile(tile, false) end
        local count = Accessories.AppliedCount()
        side.CountLabel.Text = "Applied: " .. count
        side.CountLabel.TextColor3 = count > 0 and THEME.Text or THEME.Muted
        if os.clock() >= statusUntil then ShowHint() end
    end

    local function Toggle(entry)
        if Accessories.IsApplied(entry.Id) then
            Accessories.Remove(entry.Id)
            PaintAll()
            return
        end
        SetStatus("Applying " .. entry.Name .. "...")
        task.spawn(function()
            local ok, message = Accessories.Apply(entry.Id)
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
            Image = ThumbnailOf(entry.Id),
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

    -- The list shown now: Featured (filtered by the typed text) or the catalog results of this type.
    local function CurrentList()
        if view.Type == 1 then
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
        if view.Type == 1 or view.Loading or view.Done then return end
        if view.Failed then
            if os.clock() < view.RetryAt then return end
            view.Failed = false
        end
        view.Loading = true
        local mine = view.Token
        local typeInfo = TYPES[view.Type]
        local keyword = string.match(side.Query, "^%s*(.-)%s*$")
        local sort = SORTS[(keyword ~= "" and not sortChosen) and SEARCH_SORT or sortIndex]
        if keyword == "" and sort.Type == 0 then sort = SORTS[DEFAULT_SORT] end

        SetStatus("Loading accessories...", THEME.SubText, 30)
        local items, done, reason, detail = FetchPage(view, typeInfo, keyword, sort)
        if mine ~= view.Token then return end
        view.Loading = false

        if not items then
            view.Failed = true
            view.RetryAt = os.clock() + 5
            if detail then warn("[Visual Accessories] catalog: " .. tostring(detail)) end
            if reason == "no-request" then
                SetStatus("Catalog browsing is unavailable here: the game catalog failed and this executor has no request function.", THEME.Danger, 8)
                if view.Type ~= 1 then SelectType(1) end
            elseif reason == "rate" then
                SetStatus("Roblox is limiting catalog requests. Try again in a moment.", THEME.Danger, 6)
            else
                SetStatus("Could not load the catalog (" .. string.sub(tostring(detail), 1, 60) .. "). Scroll again to retry.", THEME.Danger, 6)
            end
            return
        end

        for _, item in ipairs(items) do
            local entry = GetEntry(item.Id, item.Name, { Price = item.Price, Status = item.Status, Creator = item.Creator })
            if not table.find(view.Entries, entry) then table.insert(view.Entries, entry) end
        end
        view.Done = done

        Render()
        if #view.Entries == 0 then
            SetStatus("No accessories found.", THEME.SubText)
        else
            statusUntil = 0
            ShowHint()
        end
        -- the first pages may not fill the window yet
        if not view.Done and NeedsMore() then task.defer(LoadMore) end
    end

    local function ResetBrowse()
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
        for key, value in pairs(props or {}) do merged[key] = value end
        local field = New(class, merged, parent)
        Round(field, 8)
        Stroke(field, 0.9)
        return field
    end

    -- ---------- layout ----------
    local frame = New("Frame", {
        Name = "Accessories",
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

    Label(inner, { Text = "Accessories", Font = FONT_TITLE, TextSize = 15, Size = UDim2.new(0.5, 0, 0, 20) })
    side.CountLabel = Label(inner, {
        Text = "Applied: 0",
        TextSize = 12,
        TextColor3 = THEME.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Position = UDim2.fromScale(0.5, 0),
        Size = UDim2.new(0.5, 0, 0, 20),
    })

    -- type row: scrolls sideways (mouse wheel, drag or swipe)
    local chipRow = New("ScrollingFrame", {
        Name = "Types",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 26),
        Size = UDim2.new(1, 0, 0, 30),
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.X,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        CanvasSize = UDim2.new(),
    }, inner)
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 6),
    }, chipRow)

    local chips = {}
    local function PaintChips()
        for index, chip in ipairs(chips) do
            local on = index == view.Type
            chip.Button.BackgroundTransparency = on and 0 or THEME.CardAlpha
            chip.Gradient.Enabled = on
            chip.Button.TextColor3 = on and THEME.OnAccent or THEME.SubText
            chip.Stroke.Transparency = on and 1 or THEME.StrokeAlpha
        end
    end

    for index, typeInfo in ipairs(TYPES) do
        local button = New("TextButton", {
            Text = typeInfo.Title,
            Font = FONT_LABEL,
            TextSize = 13,
            AutoButtonColor = false,
            BorderSizePixel = 0,
            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.fromOffset(0, 28),
            BackgroundColor3 = Color3.new(1, 1, 1),
            LayoutOrder = index,
        }, chipRow)
        Round(button, 14)
        New("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, button)
        local gradient = Gradient(button, 0)
        gradient.Enabled = false
        local stroke = Stroke(button, THEME.StrokeAlpha)
        chips[index] = { Button = button, Gradient = gradient, Stroke = stroke }
        button.MouseButton1Click:Connect(function() SelectType(index) end)
    end

    -- the mouse wheel scrolls the row sideways while the cursor is over it
    do
        local hovering = false
        chipRow.MouseEnter:Connect(function() hovering = true end)
        chipRow.MouseLeave:Connect(function() hovering = false end)
        local wheel = UserInputService.InputChanged:Connect(function(input)
            if hovering and input.UserInputType == Enum.UserInputType.MouseWheel then
                local maxX = math.max(0, chipRow.AbsoluteCanvasSize.X - chipRow.AbsoluteWindowSize.X)
                chipRow.CanvasPosition = Vector2.new(math.clamp(chipRow.CanvasPosition.X - input.Position.Z * 70, 0, maxX), 0)
            end
        end)
        RegisterCleanup(function() wheel:Disconnect() end)
    end

    -- search / asset id box, with the sort button (catalog tabs) or the Add button (an id was typed) beside it
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
    SortButton.Frame.Position = UDim2.new(1, 0, 0, 62)
    SortButton.Label.TextSize = 12
    local AddButton = MakeButton(inner, "Add", true, SIDE_BUTTON)
    AddButton.Frame.AnchorPoint = Vector2.new(1, 0)
    AddButton.Frame.Position = UDim2.new(1, 0, 0, 62)

    UpdateRow = function()
        local isId = LooksLikeId(search.Text)
        local browsing = view.Type ~= 1
        AddButton.Frame.Visible = isId
        SortButton.Frame.Visible = browsing and not isId
        local right = (isId or browsing) and (SIDE_BUTTON + 8) or 0
        search.Size = UDim2.new(1, -right, 0, 32)
        local keyword = string.match(side.Query, "^%s*(.-)%s*$")
        local shown = SORTS[(keyword ~= "" and not sortChosen) and SEARCH_SORT or sortIndex]
        if keyword == "" and shown.Type == 0 then shown = SORTS[DEFAULT_SORT] end
        SortButton.Label.Text = shown.Name
    end

    -- grid, open from the start
    side.Scroll = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 102),
        Size = UDim2.new(1, 0, 1, -102),
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
    New("UIGridLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        CellSize = UDim2.new(1 / 3, -math.ceil(GAP * 2 / 3), 0, CELL_HEIGHT),
        CellPadding = UDim2.fromOffset(GAP, GAP),
    }, side.Scroll)

    -- ---------- behaviour ----------
    SelectType = function(index)
        if index ~= 1 and engineBroken and not RequestFunction() then
            SetStatus("Catalog browsing is unavailable here: the game catalog failed and this executor has no request function.", THEME.Danger, 8)
            return
        end
        view.Type = index
        PaintChips()
        UpdateRow()
        if index == 1 then
            view.Token = view.Token + 1
            side.Scroll.CanvasPosition = Vector2.zero
            Render()
        else
            ResetBrowse()
        end
    end

    local function AddFromInput()
        local assetId = ParseId(search.Text)
        if not assetId then
            SetStatus("Type a numeric asset ID or paste a catalog link.", THEME.Danger)
            return
        end
        search.Text = ""

        local entry = entryById[assetId]
        if not entry then
            entry = GetEntry(assetId, "Accessory " .. string.format("%.0f", assetId), {})
            -- the real name comes from the catalog, filled in when it arrives
            task.spawn(function()
                local ok, info = pcall(function() return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset) end)
                if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
                    entry.Name = info.Name
                    Render()
                end
            end)
        end
        Feature(entry)
        if view.Type ~= 1 then SelectType(1) else Render() end
        if not Accessories.IsApplied(assetId) then Toggle(entry) end
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
        if view.Type == 1 then
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
        if view.Type ~= 1 and NeedsMore() then task.spawn(LoadMore) end
    end)

    Accessories.OnChange = function() PaintAll() end

    RemoveAllButton.Hit.MouseButton1Click:Connect(function()
        local count = Accessories.Clear()
        PaintAll()
        SetStatus(count > 0 and ("Removed " .. count .. " accessor" .. (count == 1 and "y" or "ies") .. ".") or "Nothing to remove.", count > 0 and THEME.Success or THEME.SubText)
    end)

    PaintChips()
    UpdateRow()
    SelectType(2) -- "All", most popular first (falls back to Featured when no catalog source works)
end

BuildAccessoriesUI()
