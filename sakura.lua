-- SAKURA V20 — полный набор функций
local SAKURA_VERSION = 32
local UPDATE_URL = "https://raw.githubusercontent.com/arzamasov23012014-ops/Sakura/main/sakura.lua"
-- Исправлено: синтаксис, tostring в Text, TeamCheck, респавн, ESP, Triggerbot,
-- предсказание, BunnyHop, FullReset (теперь Unload), Teleport, FPS, лаги и т.д.

-- Защита от двойного запуска: при повторном loadstring старая копия выгружается
local env = (getgenv and getgenv()) or _G
if env.SakuraUnload then
    pcall(env.SakuraUnload)
    env.SakuraUnload = nil
    task.wait(0.3)
end

local Players  = game:GetService("Players")
local RS       = game:GetService("RunService")
local UIS      = game:GetService("UserInputService")
local VU       = game:GetService("VirtualUser")
local Http     = game:GetService("HttpService")
local TeleportSvc = game:GetService("TeleportService")
local Stats    = game:GetService("Stats")
local GuiService = game:GetService("GuiService")
local TS       = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local WS       = game:GetService("Workspace")

local player = Players.LocalPlayer
local Camera = WS.CurrentCamera
local origFOV = Camera.FieldOfView
local char, hum, root
local Running = true

-- ============ УТИЛИТЫ ============
local errLog, ErrorHook = {}, nil
local lastErrMsg, lastErrTime = "", 0
local function SafeCall(f, fallback)
    local ok, res = pcall(f)
    if not ok then
        local msg = tostring(res)
        warn("🌸 SAKURA: " .. msg)
        if msg ~= lastErrMsg then
            errLog[#errLog + 1] = os.date("%H:%M:%S") .. "  " .. msg
            if #errLog > 60 then table.remove(errLog, 1) end
        end
        if ErrorHook and (msg ~= lastErrMsg or tick() - lastErrTime > 10) then ErrorHook(msg) end
        lastErrMsg, lastErrTime = msg, tick()
        return fallback
    end
    return res
end

-- Защита циклов: ошибка в одной функции не ломает остальное; после 8 подряд цикл останавливается
do
    local real = RS
    local function report(msg, stopped)
        if msg ~= lastErrMsg or tick() - lastErrTime > 10 then
            errLog[#errLog + 1] = os.date("%H:%M:%S") .. "  [цикл] " .. msg
            if #errLog > 60 then table.remove(errLog, 1) end
            lastErrMsg, lastErrTime = msg, tick()
            if ErrorHook then ErrorHook(msg) end
        end
        if stopped and ErrorHook then ErrorHook("цикл остановлен после повторных ошибок") end
    end
    local function guard(sig)
        return {Connect = function(_, fn)
            local fails, conn = 0, nil
            conn = sig:Connect(function(...)
                local ok, err = pcall(fn, ...)
                if ok then fails = 0 return end
                fails += 1
                report(tostring(err), fails == 8)
                if fails >= 8 then conn:Disconnect() end
            end)
            return conn
        end}
    end
    RS = {
        Heartbeat = guard(real.Heartbeat), RenderStepped = guard(real.RenderStepped), Stepped = guard(real.Stepped),
        BindToRenderStep = function(_, name, prio, fn)
            local fails = 0
            return real:BindToRenderStep(name, prio, function(...)
                local ok, err = pcall(fn, ...)
                if ok then fails = 0 return end
                fails += 1
                report(tostring(err), fails == 8)
                if fails >= 8 then real:UnbindFromRenderStep(name) end
            end)
        end,
        UnbindFromRenderStep = function(_, name) return real:UnbindFromRenderStep(name) end,
    }
end

local function New(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then
        o.Parent = parent
        local lay = parent:FindFirstChildOfClass("UIListLayout") or parent:FindFirstChildOfClass("UIGridLayout")
        if lay and o ~= lay and not o:IsA("UIBase") then o.LayoutOrder = #parent:GetChildren() end
    end
    return o
end

local function Round(o, r) return New("UICorner", {CornerRadius = UDim.new(0, r)}, o) end

local function RainbowColor(speed) return Color3.fromHSV((tick() * speed) % 1, 1, 1) end

local function HealthColor(f)
    if f > 0.6 then return Color3.new(0, 1, 0) elseif f > 0.3 then return Color3.new(1, 1, 0) end
    return Color3.new(1, 0, 0)
end

-- ============ ЗАГРУЗОЧНЫЙ ЭКРАН ============
local Loader = {done = {}}
pcall(function()
    -- стиль (Sakura / Space) берём из сохранённого профиля, если он есть
    local space = false
    pcall(function()
        if readfile and isfile then
            local fname = "Sakura_" .. tostring(game.PlaceId) .. ".json"
            if isfile(fname) then
                local d = Http:JSONDecode(readfile(fname))
                space = (d and d.values and d.values.Misc and d.values.Misc.MenuMode == "space") and true or false
            end
        end
    end)
    local accent = space and Color3.fromRGB(150, 90, 255) or Color3.fromRGB(255, 102, 178)
    local accent2 = space and Color3.fromRGB(110, 160, 255) or Color3.fromRGB(255, 196, 120)
    local logoCol = space and Color3.fromRGB(165, 105, 255) or Color3.fromRGB(255, 102, 178)

    local pg = player:WaitForChild("PlayerGui", 10)
    local gui = Instance.new("ScreenGui")
    gui.Name = "SakuraLoading"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999
    gui.Parent = pg
    local bg = New("CanvasGroup", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0, GroupTransparency = 1}, gui)
    New("UIGradient", {Color = ColorSequence.new(space and Color3.fromRGB(16, 6, 40) or Color3.fromRGB(74, 28, 100),
        space and Color3.fromRGB(2, 1, 8) or Color3.fromRGB(18, 6, 30)), Rotation = 90}, bg)

    local function label(y, w, h, text, size, font, color)
        return New("TextLabel", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, 0, .5, y),
            Size = UDim2.new(0, w, 0, h), BackgroundTransparency = 1, Text = text, TextSize = size, Font = font,
            TextColor3 = color}, bg)
    end

    -- мягкое свечение, вращающееся кольцо и значок Sak
    local glow = New("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, 0, .5, -70),
        Size = UDim2.new(0, 230, 0, 230), BackgroundColor3 = accent, BackgroundTransparency = 0.86, BorderSizePixel = 0}, bg)
    Round(glow, 115)
    TS:Create(glow, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Size = UDim2.new(0, 290, 0, 290), BackgroundTransparency = 0.94}):Play()
    local ring = New("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, 0, .5, -70),
        Size = UDim2.new(0, 132, 0, 132), BackgroundTransparency = 1, BorderSizePixel = 0}, bg)
    Round(ring, 66)
    local ringStroke = New("UIStroke", {Thickness = 4, Color = accent}, ring)
    local ringGrad = New("UIGradient", {Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.4, 0.15), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1)}),
        Rotation = 0}, ringStroke)
    TS:Create(ringGrad, TweenInfo.new(1.3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {Rotation = 360}):Play()
    local logo = New("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, 0, .5, -70),
        Size = UDim2.new(0, 88, 0, 88), BackgroundColor3 = space and Color3.new(0, 0, 0) or Color3.new(1, 1, 1),
        BorderSizePixel = 0}, bg)
    Round(logo, 22)
    New("UIStroke", {Thickness = 2, Color = space and Color3.fromRGB(110, 60, 200) or Color3.fromRGB(255, 190, 220)}, logo)
    New("TextLabel", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "Sak", TextSize = 34,
        Font = Enum.Font.GothamBlack, TextColor3 = logoCol}, logo)
    local logoScale = New("UIScale", {Scale = 0.5}, logo)
    TS:Create(logoScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()

    label(20, 320, 38, "SAKURA", 32, Enum.Font.GothamBlack, accent)
    label(50, 320, 16, "версия " .. tostring(SAKURA_VERSION) .. (space and "  ·  space" or "  ·  sakura"), 12,
        Enum.Font.Gotham, Color3.fromRGB(205, 190, 230))

    -- полоса загрузки
    local barBg = New("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, 0, .5, 84),
        Size = UDim2.new(0, 300, 0, 10), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.9,
        BorderSizePixel = 0}, bg)
    Round(barBg, 5)
    local fill = New("Frame", {Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, barBg)
    Round(fill, 5)
    New("UIGradient", {Color = ColorSequence.new(accent, accent2)}, fill)
    local pct = New("TextLabel", {AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(.5, 150, .5, 68),
        Size = UDim2.new(0, 60, 0, 14), BackgroundTransparency = 1, Text = "0%", TextSize = 11,
        Font = Enum.Font.GothamBold, TextColor3 = accent2, TextXAlignment = Enum.TextXAlignment.Right}, bg)
    local status = New("TextLabel", {AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(.5, -150, .5, 68),
        Size = UDim2.new(0, 220, 0, 14), BackgroundTransparency = 1, Text = "Запуск...", TextSize = 11,
        Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(235, 225, 250), TextXAlignment = Enum.TextXAlignment.Left}, bg)
    local list = New("TextLabel", {AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, .5, 104),
        Size = UDim2.new(0, 300, 0, 48), BackgroundTransparency = 1, Text = "", TextSize = 10, Font = Enum.Font.Gotham,
        TextColor3 = Color3.fromRGB(170, 155, 200), TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top}, bg)

    -- подсказки внизу
    local tips = {
        "Долгое нажатие на функцию закрепляет её в быстрой панели справа.",
        "Кнопку Sak можно перетаскивать, тап открывает и скрывает меню.",
        "Режим Sakura / Space переключается в ⚙️ НАСТР.",
        "«Тест всех функций» в ⚙️ НАСТР найдёт сломанные функции.",
        "Клавиша End мгновенно выгружает скрипт и всё возвращает в норму.",
        "Свою картинку для фона меню можно задать ссылкой в ⚙️ НАСТР.",
    }
    local tip = New("TextLabel", {AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -34),
        Size = UDim2.new(0, 340, 0, 34), BackgroundTransparency = 1, TextWrapped = true, Text = tips[1], TextSize = 11,
        Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(205, 190, 230)}, bg)

    TS:Create(bg, TweenInfo.new(0.35), {GroupTransparency = 0}):Play()
    Loader.gui, Loader.bg, Loader.fill, Loader.status, Loader.pct, Loader.list = gui, bg, fill, status, pct, list
    Loader.logoScale = logoScale
    Loader.t0 = tick()

    task.spawn(function()
        local i = 1
        while Loader.gui == gui do
            task.wait(2.6)
            if Loader.gui ~= gui then break end
            i = i % #tips + 1
            tip.Text = tips[i]
        end
    end)
    -- фон: звёзды (Space) или лепестки (Sakura)
    task.spawn(function()
        local rng = Random.new()
        if space then
            for i = 1, 60 do
                local size = rng:NextInteger(1, 3)
                local star = New("Frame", {Size = UDim2.new(0, size, 0, size),
                    Position = UDim2.new(rng:NextNumber(), 0, rng:NextNumber(), 0),
                    BackgroundColor3 = (i % 4 == 0) and Color3.fromRGB(190, 150, 255) or Color3.new(1, 1, 1),
                    BackgroundTransparency = rng:NextNumber(0.1, 0.5), BorderSizePixel = 0}, bg)
                Round(star, 2)
                if i % 2 == 0 then
                    TS:Create(star, TweenInfo.new(rng:NextNumber(1, 2.6), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                        {BackgroundTransparency = 0.95}):Play()
                end
            end
            while Loader.gui == gui do
                local sx, sy = rng:NextNumber(0.4, 1), rng:NextNumber(0, 0.4)
                local line = New("Frame", {Size = UDim2.new(0, 80, 0, 2), Position = UDim2.new(sx, 0, sy, 0),
                    BackgroundColor3 = Color3.fromRGB(215, 190, 255), BorderSizePixel = 0, Rotation = 35}, bg)
                local tw = TS:Create(line, TweenInfo.new(0.8, Enum.EasingStyle.Quad),
                    {Position = UDim2.new(sx - 0.5, 0, sy + 0.55, 0), BackgroundTransparency = 1})
                tw:Play()
                tw.Completed:Connect(function() line:Destroy() end)
                task.wait(rng:NextNumber(1.2, 2.4))
            end
        else
            while Loader.gui == gui do
                local x = rng:NextNumber()
                local petal = New("TextLabel", {BackgroundTransparency = 1, Text = "🌸", TextSize = rng:NextInteger(14, 26),
                    TextTransparency = 0.35, Position = UDim2.new(x, 0, 0, -30), Size = UDim2.new(0, 30, 0, 30),
                    Rotation = rng:NextInteger(0, 360)}, bg)
                local tw = TS:Create(petal, TweenInfo.new(rng:NextNumber(3, 5), Enum.EasingStyle.Sine),
                    {Position = UDim2.new(x + rng:NextNumber(-0.1, 0.1), 0, 1, 30), Rotation = rng:NextInteger(0, 360)})
                tw:Play()
                tw.Completed:Connect(function() petal:Destroy() end)
                task.wait(0.2)
            end
        end
    end)
    task.delay(10, function() if Loader.gui == gui then Loader.Done(true) end end)
end)

function Loader.Step(text, pct)
    if not Loader.gui then return end
    pcall(function()
        if Loader.lastStage then
            Loader.done[#Loader.done + 1] = "✓ " .. Loader.lastStage
            while #Loader.done > 3 do table.remove(Loader.done, 1) end
            Loader.list.Text = table.concat(Loader.done, "\n")
        end
        Loader.lastStage = text
        Loader.status.Text = text
        Loader.pct.Text = math.floor(pct * 100) .. "%"
        TS:Create(Loader.fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {Size = UDim2.new(pct, 0, 1, 0)}):Play()
    end)
    task.wait(0.55)
end

function Loader.Done(force)
    local gui, bg = Loader.gui, Loader.bg
    if not gui or Loader.closing then return end
    Loader.closing = true
    pcall(function()
        if not force and Loader.t0 then
            local left = 6 - (tick() - Loader.t0)
            if left > 0 then
                Loader.status.Text = "Почти готово..."
                task.wait(left)
            end
        end
        Loader.gui = nil
        Loader.status.Text = "Готово!"
        Loader.pct.Text = "100%"
        task.wait(0.25)
        if Loader.logoScale then
            TS:Create(Loader.logoScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 1.5}):Play()
        end
        local tw = TS:Create(bg, TweenInfo.new(0.5), {GroupTransparency = 1})
        tw:Play()
        tw.Completed:Wait()
    end)
    Loader.gui = nil
    gui:Destroy()
end

-- ============ ПЕРСОНАЖ (обновляется при респавне) ============
local charCallbacks = {}
local origChar = {WalkSpeed = 16, UseJumpPower = true, JumpPower = 50, JumpHeight = 7.2}
local function BindChar(c)
    char = c
    hum = c:WaitForChild("Humanoid")
    root = c:WaitForChild("HumanoidRootPart")
    origChar = {WalkSpeed = hum.WalkSpeed, UseJumpPower = hum.UseJumpPower,
        JumpPower = hum.JumpPower, JumpHeight = hum.JumpHeight}
    for _, cb in ipairs(charCallbacks) do task.spawn(SafeCall, cb) end
end
BindChar(player.Character or player.CharacterAdded:Wait())

Loader.Step("Загрузка конфигурации", 0.12)

-- ============ КОНФИГ ============
local Config = {
    ESP = {
        Enabled = false, Color = Color3.new(1, 0, 0), ColorMode = 0, -- 0 здоровье, 1 радуга, 2 фикс.
        TeamCheck = true, MaxDistance = 100000000, MinDistance = 0, UpdateRate = 0.1,
        Box = false, ShowName = true, ShowHealth = true, ShowDistance = true, ShowFriends = true,
        Lines = false, LineThickness = 2, LineOrigin = 1, MaxPlayers = 0, DistColorRange = 300, Bones = false,
        ShowTool = false, GuiArrows = false, OutlineOnly = false, NameSize = 12, VisCheck = false, ShowSpeed = false, EnemyCount = false,
        Tracers = false, Arrow = false, HeadDot = false, Glow = false, Chams = false, Skeleton = false,
        Transparency = 0.6, OutlineTransparency = 0.2,
    },
    Aimbot = {
        Enabled = false, Mode = "Head", FOV = 200, Smoothness = 0.15,
        Prediction = true, PredictionMultiplier = 0.3,
        TeamCheck = true, Triggerbot = false, TriggerDelay = 0.1, AimLock = false, IgnoreWalls = true,
        TargetHUD = false, Priority = 1, ProjectileSpeed = 0,
        HoldMode = false, MaxDistance = 0, IgnoreFF = false, ShowFOV = true, FovAlpha = 0.9, ShowLine = false,
        NeedTool = false, AimOffsetY = 0, Jitter = 0,
    },
    Movement = {
        Speed = 16, JumpPower = 50, Noclip = false, Fly = false, FlySpeed = 60, InfJump = false,
        NoFall = false, AntiAFK = false, WaterWalk = false, AntiVoid = false,
        Freecam = false, FreecamSpeed = 40, Gravity = false, GravityValue = 100,
        AutoJump = false, AutoRun = false, RouteLoop = false, WallClimb = false, Spin = false, SpinSpeed = 20, SprintBtn = false, SprintMult = 1.6, Freeze = false,
        DashBtn = false, DashPower = 90, DoubleJump = false, Glide = false, SpeedFOV = false, Follow = false,
        BunnyHop = false, BunnyHopSpeed = 1.08, BunnyHopMax = 500,
    },
    Visuals = {
        FullBright = false, NoFog = false, XRay = false, NoShadows = false, ThirdPerson = false,
        ThirdPersonDistance = 15, NoRecoil = false, NoSpread = false, NoCameraShake = false,
        LowGraphics = false, Watermark = false, FPS = false, RainbowUI = false, NoEffects = false,
        CustomFOV = false, FOVValue = 70, Crosshair = false, TimeLock = false, TimeValue = 12,
        Radar = false, RadarRange = 200,
        NoPostFX = false, RainbowBody = false, Trail = false, Flashlight = false,
        Alert = false, AlertRange = 60, StatsHUD = false, ItemESP = false, ItemFilter = "", CoordsHUD = false,
        Petals = false, Aura = false, TimeFlow = false, TimeSpeed = 10, Compass = false, ShowInvisible = false,
        Invisicam = false, FarZoom = false, HideCoreGui = false,
        NoTextures = false, ColorGrade = false, GradeMode = 1, FpsCap = false, FpsCapValue = 60,
        NightVision = false, Rain = false, Vignette = false, CrosshairStyle = 1, CrosshairSize = 14,
    },
    Ultra = {
        GodMode = false, Invisible = false, HitboxExtender = false, HitboxSize = 2.5,
        NoStun = false, NoKnockback = false, NoSound = false, Teleport = false, AntiFling = false, TeleportSpeed = 0,
        AutoClicker = false, CPS = 10, ClickDelete = false,
        SpeedHack = false, SpeedHackMultiplier = 2,
    },
    Misc = {Notify = true, AutoSave = true, AutoRejoin = false, Lang = "ru", Notes = "", UISound = false, Pins = "", UseImage = true, ImageDim = 0.45,
        ImageUrl = "https://raw.githubusercontent.com/arzamasov23012014-ops/Sakura/main/sakura.png",
        SpaceUrl = "https://raw.githubusercontent.com/arzamasov23012014-ops/Sakura/main/space.png", MenuMode = "sakura",
        FontName = "GothamBold", Corner = 16, MenuBlur = false, MenuGlow = false, MenuFX = true, RainbowTitle = false},
    Keys = {Aimbot = "Q", Triggerbot = "T", Noclip = "N", Fly = "F", Invisible = "I", GodMode = "G",
        BunnyHop = "B", SpeedHack = "X", Menu = "RightShift", Unload = "End"},
}

local origLighting = {
    Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient, ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart, GlobalShadows = Lighting.GlobalShadows,
}

-- ============ STATE MANAGER ============
local SM = {connections = {}, objects = {}}
function SM:AddConnection(name, conn)
    self:RemoveConnection(name)
    self.connections[name] = conn
end
function SM:RemoveConnection(name)
    local c = self.connections[name]
    if c then SafeCall(function() c:Disconnect() end) self.connections[name] = nil end
end
function SM:Cleanup()
    for name in pairs(self.connections) do self:RemoveConnection(name) end
    for _, o in ipairs(self.objects) do SafeCall(function() o:Destroy() end) end
    self.objects = {}
end

-- ============ ТЕМА И ФИЧИ ============
local uiColors = {
    Color3.new(1, .4, .7), Color3.new(0, .8, 1), Color3.new(0, 1, 0), Color3.new(1, 1, 0),
    Color3.new(1, 0, 0), Color3.new(1, 0, 1), Color3.new(1, .5, 0), Color3.new(0, 1, 1),
    Color3.new(.3, .3, 1), Color3.new(1, .3, .3), Color3.new(.3, 1, .3), Color3.new(1, .8, .2),
}
local Themes = {
    {"Sakura", Color3.fromRGB(255, 102, 178), Color3.fromRGB(13, 3, 26)},
    {"Ocean",  Color3.fromRGB(0, 170, 255),   Color3.fromRGB(3, 10, 25)},
    {"Toxic",  Color3.fromRGB(80, 255, 80),   Color3.fromRGB(5, 15, 5)},
    {"Blood",  Color3.fromRGB(230, 40, 60),   Color3.fromRGB(20, 3, 5)},
    {"Gold",   Color3.fromRGB(255, 200, 50),  Color3.fromRGB(18, 14, 3)},
    {"Mono",   Color3.fromRGB(200, 200, 200), Color3.fromRGB(10, 10, 10)},
    {"Space",  Color3.fromRGB(150, 90, 255),  Color3.fromRGB(3, 1, 10)},
}
local themeIdx, uiColorIndex = 1, 0 -- uiColorIndex 0 = цвет темы
local bgColor, uiAlpha = Themes[1][3], 0.1
local X = {imageAssets = {}, starTweens = {}, itemObjs = {}, itemLastScan = 0, testReport = "", testing = false, joinLog = {}, menuScale = 1}
local customAccent
local function BaseAccent()
    if customAccent then return customAccent end
    return uiColorIndex > 0 and uiColors[uiColorIndex] or Themes[themeIdx][2]
end
local uiColor = BaseAccent()
local ON_COLOR = Color3.new(0, .8, 0)

local themed, uiRefreshers = {}, {}
local mainFrame
local function Themed(o, prop) themed[#themed + 1] = {o, prop} end
local function AddRefresher(owner, fn) uiRefreshers[#uiRefreshers + 1] = {owner = owner, fn = fn} end
local function RefreshUI()
    for i = #uiRefreshers, 1, -1 do
        local r = uiRefreshers[i]
        if r.owner:IsDescendantOf(game) then SafeCall(r.fn) else table.remove(uiRefreshers, i) end
    end
end
local function ApplyTheme()
    for i = #themed, 1, -1 do
        local t = themed[i]
        if t[1]:IsDescendantOf(game) then t[1][t[2]] = uiColor else table.remove(themed, i) end
    end
    if mainFrame and mainFrame.Parent then
        mainFrame.BackgroundColor3, mainFrame.BackgroundTransparency = bgColor, uiAlpha
        local dim = mainFrame:FindFirstChild("SakuraBGDim")
        if dim then dim.BackgroundColor3 = bgColor end
    end
    RefreshUI()
end

local function BindCam(name, fn)
    RS:BindToRenderStep("Sakura_" .. name, Enum.RenderPriority.Camera.Value + 1, fn)
    SM:AddConnection(name, {Disconnect = function() RS:UnbindFromRenderStep("Sakura_" .. name) end})
end

local toastGui, toastLbl, toastToken = nil, nil, 0
local function Toast(text, dur)
    if not Running then return end
    SafeCall(function()
        if not toastGui or not toastGui.Parent then
            toastGui = New("ScreenGui", {Name = "SakuraToast", ResetOnSpawn = false, IgnoreGuiInset = true}, player.PlayerGui)
            toastLbl = New("TextLabel", {AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 8),
                Size = UDim2.new(0, 0, 0, 26), AutomaticSize = Enum.AutomaticSize.XY,
                BackgroundColor3 = Color3.new(.05, .01, .1), BackgroundTransparency = 0.2,
                TextColor3 = Color3.new(1, 1, 1), TextSize = 13, Font = Enum.Font.GothamBold,
                BorderSizePixel = 0, Visible = false}, toastGui)
            Round(toastLbl, 8)
            local toastStroke = New("UIStroke", {Thickness = 1.5, Color = uiColor, Transparency = 0.3}, toastLbl)
            Themed(toastStroke, "Color")
            New("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12)}, toastLbl)
            SM.objects[#SM.objects + 1] = toastGui
        end
        toastToken += 1
        local my = toastToken
        toastLbl.Text = text
        toastLbl.Position = UDim2.new(.5, 0, 0, -24)
        toastLbl.Visible = true
        TS:Create(toastLbl, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Position = UDim2.new(.5, 0, 0, 8)}):Play()
        task.delay(dur or 1.8, function() if my == toastToken and toastLbl then toastLbl.Visible = false end end)
    end)
end

ErrorHook = function(msg) Toast("⚠️ " .. msg:sub(1, 70)) end

local F, Features = {}, {}
local featureKeys = {}
local Loading = false
local MarkDirty = function() end
local function Feature(id, label, tbl, key, apply)
    local f = {Id = id, Label = label, Tbl = tbl, Key = key}
    featureKeys[tbl] = featureKeys[tbl] or {}
    featureKeys[tbl][key] = true
    function f.Set(state)
        state = state and true or false
        if tbl[key] == state then return end
        tbl[key] = state
        local ok, err = pcall(function() if apply then apply(state) end end)
        if not ok then
            warn("🌸 SAKURA [" .. label .. "]: " .. tostring(err))
            errLog[#errLog + 1] = os.date("%H:%M:%S") .. "  " .. label .. ": " .. tostring(err)
            if state then
                tbl[key] = false
                pcall(function() if apply then apply(false) end end)
                Toast("⚠️ " .. label .. ": ошибка, отключено")
                RefreshUI()
                return
            end
        end
        if Config.Misc.Notify and not Loading then Toast((state and "✅ " or "❌ ") .. label) end
        RefreshUI()
        MarkDirty()
    end
    function f.Toggle() f.Set(not tbl[key]) end
    F[id] = f
    Features[#Features + 1] = f
    return f
end

-- ============ ИГРОКИ / ЦЕЛИ ============
local function IsAlive(plr)
    local c = plr and plr.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    return h ~= nil and h.Health > 0
end

local friends = {}   -- [UserId] = true
local Shared = {}
local spectating
local function IsEnemy(plr, teamCheck)
    if plr == player then return false end
    if friends[plr.UserId] then return false end
    if teamCheck and player.Team and plr.Team == player.Team then return false end
    return true
end

local function GetPart(c, mode)
    if not c then return nil end
    if mode == "Head" then return c:FindFirstChild("Head") end
    if mode == "Torso" then return c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso") end
    if mode == "Nearest" then
        local vp = Camera.ViewportSize
        local center = Vector2.new(vp.X / 2, vp.Y / 2)
        local best, bestD
        for _, n in ipairs({"Head", "UpperTorso", "Torso", "HumanoidRootPart", "LeftUpperArm", "RightUpperArm",
            "LeftUpperLeg", "RightUpperLeg", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}) do
            local part = c:FindFirstChild(n)
            if part then
                local pos, on = Camera:WorldToViewportPoint(part.Position)
                if on then
                    local dd = (Vector2.new(pos.X, pos.Y) - center).Magnitude
                    if not bestD or dd < bestD then best, bestD = part, dd end
                end
            end
        end
        return best or c:FindFirstChild("HumanoidRootPart")
    end
    return c:FindFirstChild("HumanoidRootPart")
end

Loader.Step("Модули движения", 0.28)

-- ============ ДВИЖЕНИЕ ============
local M = Config.Movement
local speedTouched, jumpTouched = false, false

local function ApplySpeed()
    if not hum or M.BunnyHop or not speedTouched then return end
    hum.WalkSpeed = M.Speed * (Config.Ultra.SpeedHack and Config.Ultra.SpeedHackMultiplier or 1)
end
local function ApplyJump()
    if hum and jumpTouched then hum.UseJumpPower = true hum.JumpPower = M.JumpPower end
end

X.ncSaved = {}
Feature("Noclip", "Noclip (N)", M, "Noclip", function(on)
    if on then
        SM:AddConnection("Noclip", RS.Stepped:Connect(function()
            if not char then return end
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then X.ncSaved[p] = true p.CanCollide = false end
            end
        end))
    else
        SM:RemoveConnection("Noclip")
        for p in pairs(X.ncSaved) do if p.Parent then p.CanCollide = true end end
        X.ncSaved = {}
    end
end)

Feature("InfJump", "InfJump", M, "InfJump", function(on)
    if on then
        SM:AddConnection("InfJump", UIS.JumpRequest:Connect(function()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end))
    else SM:RemoveConnection("InfJump") end
end)

Feature("Fly", "Fly (F)", M, "Fly", function(on)
    if on then
        SM:AddConnection("Fly", RS.RenderStepped:Connect(function()
            if not root or not hum then return end
            if not X.flyBV or X.flyBV.Parent ~= root then
                if X.flyBV then X.flyBV:Destroy() end
                X.flyBV = New("BodyVelocity", {MaxForce = Vector3.new(1e5, 1e5, 1e5), Velocity = Vector3.zero}, root)
            end
            hum.PlatformStand = true
            local move = hum.MoveDirection
            if move.Magnitude > 0 then
                local look = Camera.CFrame.LookVector
                local flat = Vector3.new(look.X, 0, look.Z)
                local sign = (flat.Magnitude > 0 and move:Dot(flat.Unit) < 0) and -1 or 1
                X.flyBV.Velocity = Vector3.new(move.X, look.Y * sign, move.Z) * M.FlySpeed
            else
                X.flyBV.Velocity = Vector3.zero
            end
        end))
    else
        SM:RemoveConnection("Fly")
        if X.flyBV then X.flyBV:Destroy() X.flyBV = nil end
        if hum then hum.PlatformStand = false end
    end
end)

Feature("AntiAFK", "AntiAFK", M, "AntiAFK", function(on)
    if on then
        SM:AddConnection("AntiAFK", player.Idled:Connect(function()
            VU:CaptureController()
            VU:ClickButton2(Vector2.new())
        end))
    else SM:RemoveConnection("AntiAFK") end
end)

Feature("WaterWalk", "WaterWalk", M, "WaterWalk", function(on)
    if on then
        X.waterPlat = New("Part", {Size = Vector3.new(10, 1, 10), Anchored = true, Transparency = 1,
            CFrame = CFrame.new(0, -1e4, 0)}, WS)
        SM:AddConnection("WaterWalk", RS.Heartbeat:Connect(function()
            if not root or not X.waterPlat then return end
            local p = RaycastParams.new()
            p.FilterType = Enum.RaycastFilterType.Exclude
            p.FilterDescendantsInstances = {char, X.waterPlat}
            p.IgnoreWater = false
            local r = WS:Raycast(root.Position, Vector3.new(0, -8, 0), p)
            if r and r.Material == Enum.Material.Water then
                X.waterPlat.CFrame = CFrame.new(root.Position.X, r.Position.Y - 0.5, root.Position.Z)
            else
                X.waterPlat.CFrame = CFrame.new(0, -1e4, 0)
            end
        end))
    else
        SM:RemoveConnection("WaterWalk")
        if X.waterPlat then X.waterPlat:Destroy() X.waterPlat = nil end
    end
end)

Feature("NoFall", "NoFall", M, "NoFall", function(on)
    if on then
        SM:AddConnection("NoFall", RS.Stepped:Connect(function()
            if root then
                local v = root.AssemblyLinearVelocity
                if v.Y < -50 then root.AssemblyLinearVelocity = Vector3.new(v.X, -30, v.Z) end
            end
        end))
    else SM:RemoveConnection("NoFall") end
end)

-- ---------- BunnyHop ----------
X.bhopSpeed, X.bhopHeld, X.lastJump = 16, false, 0

local function CreateBhopGui()
    X.bhopGui = New("ScreenGui", {Name = "SakuraBhop", ResetOnSpawn = false}, player.PlayerGui)
    local frame = New("Frame", {Size = UDim2.new(0, 160, 0, 40), Position = UDim2.new(0.5, -80, 0, 60),
        BackgroundColor3 = Color3.fromRGB(255, 80, 180), BackgroundTransparency = 0.2, BorderSizePixel = 0}, X.bhopGui)
    Round(frame, 10)
    X.bhopLabel = New("TextLabel", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "🐰 BHOP: 16",
        TextColor3 = Color3.new(1, 1, 1), TextSize = 16, Font = Enum.Font.GothamBold}, frame)
    local btn = New("TextButton", {Size = UDim2.new(0, 70, 0, 70), Position = UDim2.new(1, -180, 1, -180),
        BackgroundColor3 = Color3.fromRGB(255, 80, 180), BackgroundTransparency = 0.2, Text = "🐰",
        TextSize = 32, Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), ZIndex = 100}, X.bhopGui)
    Round(btn, 35)
    local function isPress(i) return i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 end
    btn.InputBegan:Connect(function(i) if isPress(i) then X.bhopHeld = true btn.BackgroundTransparency = 0.5 end end)
    btn.InputEnded:Connect(function(i) if isPress(i) then X.bhopHeld = false btn.BackgroundTransparency = 0.2 end end)
end

Feature("BunnyHop", "🐰 BunnyHop (B)", M, "BunnyHop", function(on)
    if on then
        if Config.Ultra.SpeedHack then F.SpeedHack.Set(false) end
        X.bhopSpeed = M.Speed
        CreateBhopGui()
        SM:AddConnection("Bhop", RS.Heartbeat:Connect(function()
            if not hum then return end
            local grounded = hum.FloorMaterial ~= Enum.Material.Air
            local want = UIS:IsKeyDown(Enum.KeyCode.Space) or X.bhopHeld
            if grounded and tick() - X.lastJump > 0.2 then
                if want then
                    hum.Jump = true
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    X.bhopSpeed = math.min(X.bhopSpeed * M.BunnyHopSpeed, M.BunnyHopMax)
                    hum.WalkSpeed = X.bhopSpeed
                    X.lastJump = tick()
                else
                    X.bhopSpeed = M.Speed
                    hum.WalkSpeed = M.Speed
                end
                if X.bhopLabel then X.bhopLabel.Text = "🐰 BHOP: " .. math.floor(X.bhopSpeed) end
            end
        end))
    else
        SM:RemoveConnection("Bhop")
        X.bhopHeld = false
        if X.bhopGui then X.bhopGui:Destroy() X.bhopGui, X.bhopLabel = nil, nil end
        if hum then hum.WalkSpeed = M.Speed end
        ApplySpeed()
    end
end)

Feature("AntiVoid", "🕳 Anti-Void", M, "AntiVoid", function(on)
    if on then
        local lastSafe
        SM:AddConnection("AntiVoid", RS.Heartbeat:Connect(function()
            if not root or not hum then return end
            if hum.FloorMaterial ~= Enum.Material.Air then lastSafe = root.CFrame end
            if lastSafe and root.Position.Y < WS.FallenPartsDestroyHeight + 80 then
                root.AssemblyLinearVelocity = Vector3.zero
                root.CFrame = lastSafe + Vector3.new(0, 5, 0)
            end
        end))
    else SM:RemoveConnection("AntiVoid") end
end)

X.fcCF, X.fcYaw, X.fcPitch = CFrame.new(), 0, 0
Feature("Freecam", "🎥 Freecam", M, "Freecam", function(on)
    if on then
        if M.Fly then F.Fly.Set(false) end
        X.fcCF = Camera.CFrame
        X.fcPitch, X.fcYaw = X.fcCF:ToEulerAnglesYXZ()
        if root then root.Anchored = true end
        Camera.CameraType = Enum.CameraType.Scriptable
        SM:AddConnection("FreecamLook", UIS.InputChanged:Connect(function(i, gp)
            if gp then return end
            if i.UserInputType == Enum.UserInputType.Touch
                or (i.UserInputType == Enum.UserInputType.MouseMovement and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)) then
                X.fcYaw = X.fcYaw - i.Delta.X * 0.005
                X.fcPitch = math.clamp(X.fcPitch - i.Delta.Y * 0.005, -1.5, 1.5)
            end
        end))
        BindCam("Freecam", function(dt)
            local rot = CFrame.fromEulerAnglesYXZ(X.fcPitch, X.fcYaw, 0)
            local move = hum and hum.MoveDirection or Vector3.zero
            local pos = X.fcCF.Position
            if move.Magnitude > 0 then
                local lv = rot.LookVector
                local flat = Vector3.new(lv.X, 0, lv.Z)
                local sign = (flat.Magnitude > 0 and move:Dot(flat.Unit) < 0) and -1 or 1
                pos = pos + Vector3.new(move.X, lv.Y * sign, move.Z) * M.FreecamSpeed * dt
            end
            X.fcCF = CFrame.new(pos) * rot
            Camera.CFrame = X.fcCF
        end)
    else
        SM:RemoveConnection("FreecamLook")
        SM:RemoveConnection("Freecam")
        if root then root.Anchored = false end
        Camera.CameraType = Enum.CameraType.Custom
        if hum then Camera.CameraSubject = hum end
    end
end)

Feature("AutoJump", "🦘 Автопрыжок", M, "AutoJump", function(on)
    if on then
        if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
        local last = 0
        SM:AddConnection("AutoJump", RS.Heartbeat:Connect(function()
            if not hum or not root or M.BunnyHop or M.Freecam or hum.PlatformStand then return end
            if hum.Sit then hum.Sit = false end
            local st = hum:GetState()
            local grounded = hum.FloorMaterial ~= Enum.Material.Air
                or st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics
                or st == Enum.HumanoidStateType.Landed
            if grounded and tick() - last > 0.08 then
                last = tick()
                hum.Jump = true
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end))
    else SM:RemoveConnection("AutoJump") end
end)

Feature("AutoRun", "🏃 Бег без остановки", M, "AutoRun", function(on)
    if on then
        SM:AddConnection("AutoRun", RS.Heartbeat:Connect(function()
            if hum and hum.MoveDirection.Magnitude == 0 then hum:Move(Vector3.new(0, 0, -1), true) end
        end))
    else
        SM:RemoveConnection("AutoRun")
        if hum then hum:Move(Vector3.zero) end
    end
end)

X.sprintGui, X.sprintHeld = nil, false
Feature("SprintBtn", "🏃 Кнопка спринта", M, "SprintBtn", function(on)
    local function release()
        if not hum then return end
        if speedTouched then ApplySpeed() else hum.WalkSpeed = origChar.WalkSpeed end
    end
    if on then
        X.sprintGui = New("ScreenGui", {Name = "SakuraSprint", ResetOnSpawn = false}, player.PlayerGui)
        local btn = New("TextButton", {Size = UDim2.new(0, 64, 0, 64), Position = UDim2.new(1, -170, 1, -250),
            BackgroundColor3 = Color3.fromRGB(60, 160, 255), BackgroundTransparency = 0.25, Text = "⚡", TextSize = 28,
            Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, X.sprintGui)
        Round(btn, 32)
        local function press(i) return i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 end
        btn.InputBegan:Connect(function(i) if press(i) then X.sprintHeld = true btn.BackgroundTransparency = 0.05 end end)
        btn.InputEnded:Connect(function(i)
            if press(i) then X.sprintHeld = false btn.BackgroundTransparency = 0.25 release() end
        end)
        SM:AddConnection("SprintBtn", RS.Heartbeat:Connect(function()
            if X.sprintHeld and hum and not M.BunnyHop then
                hum.WalkSpeed = (speedTouched and M.Speed or origChar.WalkSpeed) * M.SprintMult
            end
        end))
    else
        SM:RemoveConnection("SprintBtn")
        X.sprintHeld = false
        if X.sprintGui then X.sprintGui:Destroy() X.sprintGui = nil end
        release()
    end
end)

Feature("DashBtn", "💨 Рывок (кнопка)", M, "DashBtn", function(on)
    if on then
        X.dashGui = New("ScreenGui", {Name = "SakuraDash", ResetOnSpawn = false}, player.PlayerGui)
        local btn = New("TextButton", {Size = UDim2.new(0, 64, 0, 64), Position = UDim2.new(1, -250, 1, -170),
            BackgroundColor3 = Color3.fromRGB(255, 120, 80), BackgroundTransparency = 0.25, Text = "💨", TextSize = 28,
            Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, X.dashGui)
        Round(btn, 32)
        local cooldown = 0
        btn.MouseButton1Click:Connect(function()
            if not root or tick() - cooldown < 0.6 then return end
            cooldown = tick()
            local look = Camera.CFrame.LookVector
            local dir = Vector3.new(look.X, 0, look.Z)
            if dir.Magnitude < 0.01 then return end
            local v = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = dir.Unit * M.DashPower + Vector3.new(0, math.max(v.Y, 12), 0)
        end)
    else
        if X.dashGui then X.dashGui:Destroy() X.dashGui = nil end
    end
end)

Feature("DoubleJump", "⏫ Двойной прыжок", M, "DoubleJump", function(on)
    if on then
        X.djUsed = false
        SM:AddConnection("DoubleJump", UIS.JumpRequest:Connect(function()
            if not hum then return end
            if hum.FloorMaterial == Enum.Material.Air and not X.djUsed then
                X.djUsed = true
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end))
        SM:AddConnection("DoubleJumpReset", RS.Heartbeat:Connect(function()
            if hum and hum.FloorMaterial ~= Enum.Material.Air then X.djUsed = false end
        end))
    else
        SM:RemoveConnection("DoubleJump")
        SM:RemoveConnection("DoubleJumpReset")
    end
end)

Feature("Glide", "🪂 Планирование", M, "Glide", function(on)
    if on then
        SM:AddConnection("Glide", RS.Heartbeat:Connect(function()
            if not hum or not root then return end
            if hum:GetState() == Enum.HumanoidStateType.Freefall and (UIS:IsKeyDown(Enum.KeyCode.Space) or hum.Jump) then
                local v = root.AssemblyLinearVelocity
                if v.Y < -14 then root.AssemblyLinearVelocity = Vector3.new(v.X, -14, v.Z) end
            end
        end))
    else SM:RemoveConnection("Glide") end
end)

Feature("SpeedFOV", "🌀 FOV от скорости", M, "SpeedFOV", function(on)
    if on then
        X.sfBase = Camera.FieldOfView
        BindCam("SpeedFOV", function()
            if not root then return end
            local v = root.AssemblyLinearVelocity
            local sp = Vector3.new(v.X, 0, v.Z).Magnitude
            local goal = X.sfBase + math.clamp(sp * 0.25, 0, 35)
            Camera.FieldOfView = Camera.FieldOfView + (goal - Camera.FieldOfView) * 0.15
        end)
    else
        SM:RemoveConnection("SpeedFOV")
        if X.sfBase then Camera.FieldOfView = X.sfBase X.sfBase = nil end
    end
end)

Feature("Follow", "🚶 Следовать за игроком", M, "Follow", function(on)
    if on then
        local last = 0
        SM:AddConnection("Follow", RS.Heartbeat:Connect(function()
            if not hum or not root or tick() - last < 0.3 then return end
            last = tick()
            local best, bd = nil, math.huge
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= player and IsAlive(plr) then
                    local r = plr.Character:FindFirstChild("HumanoidRootPart")
                    if r then
                        local d = (r.Position - root.Position).Magnitude
                        if d < bd then best, bd = r, d end
                    end
                end
            end
            if best and bd > 7 then hum:MoveTo(best.Position) end
        end))
    else SM:RemoveConnection("Follow") end
end)

Feature("Freeze", "🧊 Заморозка", M, "Freeze", function(on)
    if root then root.Anchored = on end
    if on then
        SM:AddConnection("Freeze", RS.Heartbeat:Connect(function()
            if root and not M.Freecam then root.Anchored = true end
        end))
    else SM:RemoveConnection("Freeze") end
end)

Feature("Spin", "🌀 Вращение", M, "Spin", function(on)
    if on then
        SM:AddConnection("Spin", RS.RenderStepped:Connect(function()
            if root and hum and not M.Freecam then
                hum.AutoRotate = false
                root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(M.SpinSpeed), 0)
            end
        end))
    else
        SM:RemoveConnection("Spin")
        if hum then hum.AutoRotate = true end
    end
end)

Feature("WallClimb", "🧗 Лазание по стенам", M, "WallClimb", function(on)
    if on then
        SM:AddConnection("WallClimb", RS.Heartbeat:Connect(function()
            if not root or not hum then return end
            local dir = hum.MoveDirection
            if dir.Magnitude == 0 then return end
            local p = RaycastParams.new()
            p.FilterType = Enum.RaycastFilterType.Exclude
            p.FilterDescendantsInstances = {char}
            if WS:Raycast(root.Position, dir.Unit * 2.5, p) then
                local v = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = Vector3.new(v.X, 28, v.Z)
            end
        end))
    else SM:RemoveConnection("WallClimb") end
end)

-- Запись и повтор маршрута
local route, routeRec, routePlaying = {}, false, false
Feature("RouteLoop", "🔁 Повтор маршрута", M, "RouteLoop")
local function RouteToggleRecord()
    if routeRec then
        routeRec = false
        SM:RemoveConnection("RouteRec")
        Toast("⏹ Запись окончена: " .. #route .. " точек")
        return
    end
    route = {}
    routeRec = true
    local last = 0
    SM:AddConnection("RouteRec", RS.Heartbeat:Connect(function()
        if not root or tick() - last < 0.2 then return end
        local pos = root.Position
        local prev = route[#route]
        if not prev or (pos - prev).Magnitude > 3 then route[#route + 1] = pos last = tick() end
    end))
    Toast("⏺ Идёт запись маршрута...")
end
local function RoutePlay()
    if routePlaying then routePlaying = false Toast("⏹ Маршрут остановлен") return end
    if #route < 2 then Toast("Сначала запиши маршрут") return end
    routePlaying = true
    Toast("▶ Иду по маршруту")
    task.spawn(function()
        repeat
            for _, pt in ipairs(route) do
                if not (routePlaying and Running and hum and root) then break end
                hum:MoveTo(pt)
                local t0 = tick()
                while routePlaying and Running and root and (root.Position - pt).Magnitude > 4 and tick() - t0 < 2.5 do
                    task.wait(0.1)
                end
            end
        until not (routePlaying and Running and M.RouteLoop)
        if routePlaying then Toast("✅ Маршрут завершён") end
        routePlaying = false
    end)
end

Feature("Gravity", "🪐 Гравитация", M, "Gravity", function(on)
    if on then
        X.gravSaved = WS.Gravity
        SM:AddConnection("Gravity", RS.Heartbeat:Connect(function() WS.Gravity = M.GravityValue end))
    else
        SM:RemoveConnection("Gravity")
        if X.gravSaved then WS.Gravity = X.gravSaved X.gravSaved = nil end
    end
end)

-- ============ ULTRA ============
local U = Config.Ultra

X.invSaved = {}
Feature("Invisible", "👻 Invisible (I)", U, "Invisible", function(on)
    if on then
        SM:AddConnection("Invisible", RS.Stepped:Connect(function()
            if not char then return end
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") or p:IsA("Decal") then
                    if X.invSaved[p] == nil then X.invSaved[p] = p.Transparency end
                    p.Transparency = 1
                end
            end
        end))
    else
        SM:RemoveConnection("Invisible")
        for p, t in pairs(X.invSaved) do if p.Parent then p.Transparency = t end end
        X.invSaved = {}
    end
end)

Feature("GodMode", "🛡️ God Mode (G)", U, "GodMode", function(on)
    if on then
        SM:AddConnection("GodMode", RS.Heartbeat:Connect(function()
            if hum then hum.Health = hum.MaxHealth end
        end))
    else SM:RemoveConnection("GodMode") end
end)

Feature("NoKnockback", "🚫 Anti Knockback", U, "NoKnockback", function(on)
    if on then
        SM:AddConnection("AntiKB", RS.Heartbeat:Connect(function()
            if not hum or not root then return end
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.FallingDown or st == Enum.HumanoidStateType.Ragdoll
                or st == Enum.HumanoidStateType.Physics then
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
            -- гасим толчки только когда стоим на месте (иначе сломаем ходьбу)
            if hum.MoveDirection.Magnitude == 0 and hum.FloorMaterial ~= Enum.Material.Air then
                local v = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
            end
        end))
    else SM:RemoveConnection("AntiKB") end
end)

X.sndSaved = {}
Feature("NoSound", "🔇 No Sound", U, "NoSound", function(on)
    if on then
        for _, s in ipairs(WS:GetDescendants()) do
            if s:IsA("Sound") then X.sndSaved[s] = s.Volume s.Volume = 0 end
        end
        SM:AddConnection("NoSound", WS.DescendantAdded:Connect(function(s)
            if s:IsA("Sound") then X.sndSaved[s] = s.Volume s.Volume = 0 end
        end))
    else
        SM:RemoveConnection("NoSound")
        for s, v in pairs(X.sndSaved) do if s.Parent then s.Volume = v end end
        X.sndSaved = {}
    end
end)

local stunStates = {Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.FallingDown,
    Enum.HumanoidStateType.PlatformStanding}
local function SetStunStates(enabled)
    if not hum then return end
    for _, s in ipairs(stunStates) do hum:SetStateEnabled(s, enabled) end
end
Feature("NoStun", "⛔ No Stun", U, "NoStun", function(on) SetStunStates(not on) end)

Feature("SpeedHack", "⚡ Волчек (X)", U, "SpeedHack", function(on)
    if on then
        if M.BunnyHop then F.BunnyHop.Set(false) end
        speedTouched = true
        SM:AddConnection("SpeedHack", RS.Stepped:Connect(ApplySpeed))
    else
        SM:RemoveConnection("SpeedHack")
        ApplySpeed()
    end
end)

local function GotoCFrame(cf)
    if not root then return end
    X.lastCF = root.CFrame
    if U.TeleportSpeed > 0 then
        local dist = (root.Position - cf.Position).Magnitude
        TS:Create(root, TweenInfo.new(math.max(dist / U.TeleportSpeed, 0.05), Enum.EasingStyle.Linear), {CFrame = cf}):Play()
    else
        root.CFrame = cf
    end
end
local function TeleportTo(pos)
    if pos then GotoCFrame(CFrame.new(pos + Vector3.new(0, 3, 0))) end
end
Feature("Teleport", "🌀 Teleport", U, "Teleport", function(on)
    if on then
        local mouse = player:GetMouse()
        SM:AddConnection("TeleportPC", UIS.InputBegan:Connect(function(input, gp)
            if gp or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl) and mouse.Hit then TeleportTo(mouse.Hit.Position) end
        end))
        SM:AddConnection("TeleportTouch", UIS.TouchTapInWorld:Connect(function(pos, processed)
            if processed then return end
            local ray = Camera:ViewportPointToRay(pos.X, pos.Y)
            local p = RaycastParams.new()
            p.FilterType = Enum.RaycastFilterType.Exclude
            p.FilterDescendantsInstances = {char}
            local r = WS:Raycast(ray.Origin, ray.Direction * 1000, p)
            if r then TeleportTo(r.Position) end
        end))
    else
        SM:RemoveConnection("TeleportPC")
        SM:RemoveConnection("TeleportTouch")
    end
end)

Feature("AutoClicker", "🖱 Автоклик", U, "AutoClicker", function(on)
    if on then
        local acc = 0
        SM:AddConnection("AutoClicker", RS.Heartbeat:Connect(function(dt)
            acc += dt
            if acc < 1 / math.max(U.CPS, 1) then return end
            acc = 0
            local tool = char and char:FindFirstChildOfClass("Tool")
            if tool then tool:Activate()
            elseif mouse1click then mouse1click()
            else VU:ClickButton1(Vector2.new()) end
        end))
    else SM:RemoveConnection("AutoClicker") end
end)

X.cdSaved = {}
local function CDHide(part)
    if not part or not part:IsA("BasePart") or part:IsA("Terrain") or (char and part:IsDescendantOf(char)) then return end
    local m = part:FindFirstAncestorOfClass("Model")
    if m and Players:GetPlayerFromCharacter(m) then return end
    if not X.cdSaved[part] then X.cdSaved[part] = {t = part.Transparency, c = part.CanCollide} end
    part.Transparency = 1
    part.CanCollide = false
end
Feature("ClickDelete", "🗑 Клик-удаление", U, "ClickDelete", function(on)
    if on then
        local function hitAt(x, y)
            local ray = Camera:ViewportPointToRay(x, y)
            local p = RaycastParams.new()
            p.FilterType = Enum.RaycastFilterType.Exclude
            p.FilterDescendantsInstances = {char}
            local r = WS:Raycast(ray.Origin, ray.Direction * 1000, p)
            if r and r.Instance then CDHide(r.Instance) end
        end
        SM:AddConnection("ClickDelTouch", UIS.TouchTapInWorld:Connect(function(pos, processed)
            if not processed then hitAt(pos.X, pos.Y) end
        end))
        SM:AddConnection("ClickDelMouse", UIS.InputBegan:Connect(function(i, gp)
            if gp or i.UserInputType ~= Enum.UserInputType.MouseButton1 or not UIS:IsKeyDown(Enum.KeyCode.LeftAlt) then return end
            local pos = UIS:GetMouseLocation()
            hitAt(pos.X, pos.Y)
        end))
    else
        SM:RemoveConnection("ClickDelTouch")
        SM:RemoveConnection("ClickDelMouse")
        for part, d in pairs(X.cdSaved) do
            if part.Parent then part.Transparency = d.t part.CanCollide = d.c end
        end
        X.cdSaved = {}
    end
end)

X.flingSaved = {}
Feature("AntiFling", "🛡 Анти-флинг", U, "AntiFling", function(on)
    if on then
        SM:AddConnection("AntiFling", RS.Stepped:Connect(function()
            for _, plr in ipairs(Players:GetPlayers()) do
                local c = plr ~= player and plr.Character
                if c then
                    for _, p in ipairs(c:GetChildren()) do
                        if p:IsA("BasePart") and p.CanCollide then X.flingSaved[p] = true p.CanCollide = false end
                    end
                end
            end
            if root and not M.Fly and not M.BunnyHop and root.AssemblyLinearVelocity.Magnitude > 300 then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end))
    else
        SM:RemoveConnection("AntiFling")
        for p in pairs(X.flingSaved) do if p.Parent then p.CanCollide = true end end
        X.flingSaved = {}
    end
end)

-- Hitbox
local hbSaved = setmetatable({}, {__mode = "k"})
local function HitboxApply()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character then
            for _, part in ipairs(plr.Character:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    if not hbSaved[part] then hbSaved[part] = part.Size end
                    part.Size = hbSaved[part] * U.HitboxSize
                end
            end
        end
    end
end
Feature("Hitbox", "Hitbox Extender", U, "HitboxExtender", function(on)
    if on then
        HitboxApply()
        local last = 0
        SM:AddConnection("Hitbox", RS.Heartbeat:Connect(function()
            if tick() - last > 1 then last = tick() HitboxApply() end
        end))
    else
        SM:RemoveConnection("Hitbox")
        for part, size in pairs(hbSaved) do if part.Parent then part.Size = size end end
        hbSaved = setmetatable({}, {__mode = "k"})
    end
end)

Loader.Step("Визуальные эффекты", 0.44)

-- ============ ВИЗУАЛЫ ============
local V = Config.Visuals

X.xraySaved = {}
local function XrayPart(o)
    if o:IsA("BasePart") and not o:IsA("Terrain") and o.Transparency < 0.3
        and not (o.Parent and o.Parent:FindFirstChildOfClass("Humanoid")) then
        X.xraySaved[o] = o.Transparency
        o.Transparency = 0.3
    end
end
Feature("XRay", "👀 X-Ray", V, "XRay", function(on)
    if on then
        for _, o in ipairs(WS:GetDescendants()) do XrayPart(o) end
        SM:AddConnection("XRay", WS.DescendantAdded:Connect(XrayPart))
    else
        SM:RemoveConnection("XRay")
        for o, t in pairs(X.xraySaved) do if o.Parent then o.Transparency = t end end
        X.xraySaved = {}
    end
end)

Feature("FullBright", "☀️ Full Bright", V, "FullBright", function(on)
    if on then
        X.fbSaved = {Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient, ClockTime = Lighting.ClockTime}
        Lighting.Brightness = 2
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
        Lighting.ClockTime = 12
    elseif X.fbSaved then
        for k, v in pairs(X.fbSaved) do Lighting[k] = v end
        X.fbSaved = nil
    end
end)

Feature("NoFog", "🌫️ No Fog", V, "NoFog", function(on)
    if on then
        X.fogSaved = {FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart, atm = {}}
        Lighting.FogEnd, Lighting.FogStart = 1e6, 0
        for _, a in ipairs(Lighting:GetChildren()) do
            if a:IsA("Atmosphere") then X.fogSaved.atm[a] = a.Density a.Density = 0 end
        end
    elseif X.fogSaved then
        Lighting.FogEnd, Lighting.FogStart = X.fogSaved.FogEnd, X.fogSaved.FogStart
        for a, d in pairs(X.fogSaved.atm) do if a.Parent then a.Density = d end end
        X.fogSaved = nil
    end
end)

Feature("RainbowUI", "🌈 Радужный UI", V, "RainbowUI", function(on)
    if on then
        local last = 0
        SM:AddConnection("RainbowUI", RS.RenderStepped:Connect(function()
            if tick() - last < 0.06 then return end
            last = tick()
            uiColor = RainbowColor(0.3)
            ApplyTheme()
        end))
    else
        SM:RemoveConnection("RainbowUI")
        uiColor = BaseAccent()
        ApplyTheme()
    end
end)

Feature("Watermark", "💧 Watermark", V, "Watermark", function(on)
    if on then
        X.wmGui = New("ScreenGui", {Name = "SakuraWatermark", ResetOnSpawn = false}, player.PlayerGui)
        local l = New("TextLabel", {Size = UDim2.new(0, 220, 0, 28), Position = UDim2.new(0.5, -110, 0, 10),
            BackgroundColor3 = Color3.new(.05, .01, .1), BackgroundTransparency = 0.2, BorderSizePixel = 0,
            Text = "🌸 SAKURA V20", TextColor3 = Color3.new(1, 1, 1), TextSize = 14, Font = Enum.Font.GothamBold}, X.wmGui)
        Round(l, 10)
    elseif X.wmGui then X.wmGui:Destroy() X.wmGui = nil end
end)

X.shadowSaved = {}
local function NoShadowPart(o)
    if o:IsA("BasePart") and o.CastShadow then X.shadowSaved[o] = true o.CastShadow = false end
end
Feature("NoShadows", "🌑 No Shadow", V, "NoShadows", function(on)
    if on then
        for _, o in ipairs(WS:GetDescendants()) do NoShadowPart(o) end
        SM:AddConnection("NoShadow", WS.DescendantAdded:Connect(NoShadowPart))
    else
        SM:RemoveConnection("NoShadow")
        for o in pairs(X.shadowSaved) do if o.Parent then o.CastShadow = true end end
        X.shadowSaved = {}
    end
end)

Feature("NoCameraShake", "📷 No Camera Shake", V, "NoCameraShake", function(on)
    if on then
        BindCam("NoShake", function()
            if hum then hum.CameraOffset = Vector3.zero end
        end)
    else SM:RemoveConnection("NoShake") end
end)

Feature("NoRecoil", "🔫 No Recoil", V, "NoRecoil", function(on)
    if on then
        SM:AddConnection("NoRecoil", RS.Heartbeat:Connect(function()
            local tool = char and char:FindFirstChildOfClass("Tool")
            local r = tool and tool:FindFirstChild("Recoil")
            if r then r:Destroy() end
        end))
    else SM:RemoveConnection("NoRecoil") end
end)

Feature("NoSpread", "🎯 No Spread", V, "NoSpread", function(on)
    if on then
        local last = 0
        SM:AddConnection("NoSpread", RS.Heartbeat:Connect(function()
            if tick() - last < 0.5 then return end
            last = tick()
            local tool = char and char:FindFirstChildOfClass("Tool")
            if not tool then return end
            for _, o in ipairs(tool:GetDescendants()) do
                if o:IsA("NumberValue") and o.Name:find("Spread") then o.Value = 0 end
            end
        end))
    else SM:RemoveConnection("NoSpread") end
end)

Feature("ThirdPerson", "👤 Third Person", V, "ThirdPerson", function(on)
    if on then
        X.tpSaved = {min = player.CameraMinZoomDistance, max = player.CameraMaxZoomDistance}
        player.CameraMaxZoomDistance = V.ThirdPersonDistance
        player.CameraMinZoomDistance = V.ThirdPersonDistance
    elseif X.tpSaved then
        player.CameraMinZoomDistance, player.CameraMaxZoomDistance = X.tpSaved.min, X.tpSaved.max
        X.tpSaved = nil
    end
end)

X.lowSaved, X.lowShadows = {}, nil
Feature("LowGraphics", "💻 Low Graphics", V, "LowGraphics", function(on)
    if on then
        X.lowShadows = Lighting.GlobalShadows
        Lighting.GlobalShadows = false
        for _, o in ipairs(WS:GetDescendants()) do
            if o:IsA("BasePart") and not o:IsA("Terrain") then X.lowSaved[o] = o.Material o.Material = Enum.Material.SmoothPlastic end
        end
    else
        Lighting.GlobalShadows = X.lowShadows ~= nil and X.lowShadows or origLighting.GlobalShadows
        for o, m in pairs(X.lowSaved) do if o.Parent then o.Material = m end end
        X.lowSaved = {}
    end
end)

X.effSaved = {}
local function IsEffect(o)
    return o:IsA("ParticleEmitter") or o:IsA("Fire") or o:IsA("Smoke") or o:IsA("Sparkles")
        or o:IsA("Trail") or o:IsA("Beam")
end
local function KillEffect(o) if IsEffect(o) and o.Enabled then X.effSaved[o] = true o.Enabled = false end end
Feature("NoEffects", "🚫 No Effects", V, "NoEffects", function(on)
    if on then
        for _, o in ipairs(WS:GetDescendants()) do KillEffect(o) end
        SM:AddConnection("NoEffects", WS.DescendantAdded:Connect(KillEffect))
    else
        SM:RemoveConnection("NoEffects")
        for o in pairs(X.effSaved) do if o.Parent then o.Enabled = true end end
        X.effSaved = {}
    end
end)

Feature("FPS", "⚡ FPS HUD", V, "FPS", function(on)
    if on then
        X.fpsGui = New("ScreenGui", {Name = "SakuraFPS", ResetOnSpawn = false}, player.PlayerGui)
        local fr = New("Frame", {Size = UDim2.new(0, 140, 0, 32), Position = UDim2.new(0, 10, 1, -42),
            BackgroundColor3 = Color3.new(.08, .02, .12), BackgroundTransparency = 0.2, BorderSizePixel = 0}, X.fpsGui)
        Round(fr, 8)
        local lbl = New("TextLabel", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "⚡ 0",
            TextColor3 = Color3.new(0, 1, 0), TextSize = 16, Font = Enum.Font.GothamBold}, fr)
        local acc, frames = 0, 0
        SM:AddConnection("FPS", RS.Heartbeat:Connect(function(dt)
            acc += dt frames += 1
            if acc >= 0.5 then
                local fps = math.round(frames / acc)
                acc, frames = 0, 0
                local ping = SafeCall(function() return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end, 0)
                lbl.Text = "⚡ " .. fps .. " · " .. ping .. "ms"
                lbl.TextColor3 = HealthColor(fps / 60)
            end
        end))
    else
        SM:RemoveConnection("FPS")
        if X.fpsGui then X.fpsGui:Destroy() X.fpsGui = nil end
    end
end)

function X.ClearItems()
    for _, d in pairs(X.itemObjs) do SafeCall(function() d.hl:Destroy() d.gui:Destroy() end) end
    X.itemObjs = {}
end
function X.ScanItems()
    local q = (V.ItemFilter or ""):lower()
    if q == "" or not root then X.ClearItems() return end
    local list = {}
    for _, o in ipairs(WS:GetDescendants()) do
        if (o:IsA("BasePart") or o:IsA("Model")) and o.Name:lower():find(q, 1, true) then
            local m = o:IsA("Model") and o or o:FindFirstAncestorOfClass("Model")
            if not (m and Players:GetPlayerFromCharacter(m)) then
                local part = o:IsA("BasePart") and o or (o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart", true))
                if part then list[#list + 1] = {o, part, (part.Position - root.Position).Magnitude} end
            end
        end
    end
    table.sort(list, function(a, b) return a[3] < b[3] end)
    local keep = {}
    for i = 1, math.min(25, #list) do
        local o, part = list[i][1], list[i][2]
        keep[o] = true
        if not X.itemObjs[o] then
            local hl = New("Highlight", {Name = "SakuraItemHL", Adornee = o, FillColor = uiColor,
                OutlineColor = Color3.new(1, 1, 1), FillTransparency = 0.6,
                DepthMode = Enum.HighlightDepthMode.AlwaysOnTop}, o)
            local gui = New("BillboardGui", {Name = "SakuraItemGUI", Adornee = part, Size = UDim2.new(0, 120, 0, 30),
                AlwaysOnTop = true, StudsOffset = Vector3.new(0, 2, 0)}, part)
            local lbl = New("TextLabel", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
                TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = Enum.Font.GothamBold,
                TextStrokeTransparency = 0.3, Text = o.Name}, gui)
            X.itemObjs[o] = {hl = hl, gui = gui, lbl = lbl, part = part}
        end
    end
    for o, d in pairs(X.itemObjs) do
        if not keep[o] then SafeCall(function() d.hl:Destroy() d.gui:Destroy() end) X.itemObjs[o] = nil end
    end
end
Feature("ItemESP", "🔍 ESP предметов", V, "ItemESP", function(on)
    if on then
        X.itemLastScan = 0
        local lastUpd = 0
        SM:AddConnection("ItemESP", RS.Heartbeat:Connect(function()
            local now = tick()
            if now - X.itemLastScan > 3 then X.itemLastScan = now X.ScanItems() end
            if now - lastUpd > 0.5 and root then
                lastUpd = now
                for o, d in pairs(X.itemObjs) do
                    if o.Parent and d.part.Parent then
                        d.lbl.Text = o.Name .. "\n" .. math.floor((d.part.Position - root.Position).Magnitude) .. "m"
                    end
                end
            end
        end))
    else
        SM:RemoveConnection("ItemESP")
        X.ClearItems()
    end
end)

Feature("Petals", "🌸 Лепестки вокруг", V, "Petals", function(on)
    if on then
        X.petalPart = New("Part", {Name = "SakuraPetals", Anchored = true, CanCollide = false, CanQuery = false,
            CanTouch = false, Transparency = 1, Size = Vector3.new(70, 1, 70)}, WS)
        New("ParticleEmitter", {Rate = 40, Lifetime = NumberRange.new(6, 9), Speed = NumberRange.new(3, 6),
            SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Bottom, Size = NumberSequence.new(0.35),
            LightEmission = 0.4, RotSpeed = NumberRange.new(-90, 90), Rotation = NumberRange.new(0, 360),
            Color = ColorSequence.new(Config.Misc.MenuMode == "space" and Color3.new(1, 1, 1) or Color3.fromRGB(255, 183, 197)),
            Transparency = NumberSequence.new(0.1, 0.9)}, X.petalPart)
        SM:AddConnection("Petals", RS.Heartbeat:Connect(function()
            if X.petalPart then X.petalPart.CFrame = CFrame.new(Camera.CFrame.Position + Vector3.new(0, 28, 0)) end
        end))
    else
        SM:RemoveConnection("Petals")
        if X.petalPart then X.petalPart:Destroy() X.petalPart = nil end
    end
end)

Feature("Aura", "💠 Аура", V, "Aura", function(on)
    if on then
        SM:AddConnection("Aura", RS.Heartbeat:Connect(function()
            if not char then return end
            local hl = char:FindFirstChild("SakuraAura")
            if not hl then
                hl = New("Highlight", {Name = "SakuraAura", FillTransparency = 1, OutlineTransparency = 0,
                    DepthMode = Enum.HighlightDepthMode.Occluded}, char)
            end
            hl.OutlineColor = uiColor
        end))
    else
        SM:RemoveConnection("Aura")
        local hl = char and char:FindFirstChild("SakuraAura")
        if hl then hl:Destroy() end
    end
end)

Feature("TimeFlow", "🕑 Бег времени", V, "TimeFlow", function(on)
    if on then
        X.timeFlowSaved = Lighting.ClockTime
        SM:AddConnection("TimeFlow", RS.Heartbeat:Connect(function(dt)
            Lighting.ClockTime = (Lighting.ClockTime + dt * V.TimeSpeed / 60) % 24
        end))
    else
        SM:RemoveConnection("TimeFlow")
        if X.timeFlowSaved then Lighting.ClockTime = X.timeFlowSaved X.timeFlowSaved = nil end
    end
end)

Feature("Compass", "🧭 Компас", V, "Compass", function(on)
    if on then
        X.compassGui = New("ScreenGui", {Name = "SakuraCompass", ResetOnSpawn = false}, player.PlayerGui)
        local lbl = New("TextLabel", {AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 44),
            Size = UDim2.new(0, 120, 0, 24), BackgroundColor3 = Color3.new(.05, .01, .1), BackgroundTransparency = 0.3,
            TextColor3 = Color3.new(1, 1, 1), TextSize = 13, Font = Enum.Font.GothamBold, BorderSizePixel = 0, Text = ""}, X.compassGui)
        Round(lbl, 8)
        local dirs = {"С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"}
        SM:AddConnection("Compass", RS.RenderStepped:Connect(function()
            local look = Camera.CFrame.LookVector
            local deg = (math.deg(math.atan2(look.X, -look.Z)) + 360) % 360
            lbl.Text = dirs[math.floor((deg + 22.5) / 45) % 8 + 1] .. "  " .. math.floor(deg) .. "°"
        end))
    else
        SM:RemoveConnection("Compass")
        if X.compassGui then X.compassGui:Destroy() X.compassGui = nil end
    end
end)

X.wallSaved = {}
local function ShowInv(o)
    if o:IsA("BasePart") and not o:IsA("Terrain") and o.CanCollide and o.Transparency >= 0.95
        and not (o.Parent and o.Parent:FindFirstChildOfClass("Humanoid")) then
        X.wallSaved[o] = o.Transparency
        o.Transparency = 0.6
    end
end
Feature("ShowInvisible", "🧱 Невидимые стены", V, "ShowInvisible", function(on)
    if on then
        for _, o in ipairs(WS:GetDescendants()) do ShowInv(o) end
        SM:AddConnection("ShowInvisible", WS.DescendantAdded:Connect(ShowInv))
    else
        SM:RemoveConnection("ShowInvisible")
        for o, t in pairs(X.wallSaved) do if o.Parent then o.Transparency = t end end
        X.wallSaved = {}
    end
end)

Feature("Invisicam", "👓 Камера сквозь стены", V, "Invisicam", function(on)
    if on then
        X.occSaved = player.DevCameraOcclusionMode
        player.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
    elseif X.occSaved then
        player.DevCameraOcclusionMode = X.occSaved
        X.occSaved = nil
    end
end)

Feature("FarZoom", "🔭 Дальний зум", V, "FarZoom", function(on)
    if on then
        X.zoomSaved = {player.CameraMinZoomDistance, player.CameraMaxZoomDistance}
        player.CameraMaxZoomDistance = 600
        player.CameraMinZoomDistance = 0.5
    elseif X.zoomSaved then
        player.CameraMinZoomDistance, player.CameraMaxZoomDistance = X.zoomSaved[1], X.zoomSaved[2]
        X.zoomSaved = nil
    end
end)

Feature("HideCoreGui", "📸 Без интерфейса Roblox", V, "HideCoreGui", function(on)
    game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, not on)
end)

X.texSaved = {}
local function HideTex(o)
    if (o:IsA("Decal") or o:IsA("Texture")) and o.Transparency < 1 then
        local m = o:FindFirstAncestorOfClass("Model")
        if m and m:FindFirstChildOfClass("Humanoid") then return end
        X.texSaved[o] = o.Transparency
        o.Transparency = 1
    end
end
Feature("NoTextures", "🧹 Без текстур", V, "NoTextures", function(on)
    if on then
        for _, o in ipairs(WS:GetDescendants()) do HideTex(o) end
        SM:AddConnection("NoTextures", WS.DescendantAdded:Connect(HideTex))
    else
        SM:RemoveConnection("NoTextures")
        for o, t in pairs(X.texSaved) do if o.Parent then o.Transparency = t end end
        X.texSaved = {}
    end
end)

X.gradeModes = {
    {"Яркий", {Saturation = 0.5, Contrast = 0.15, TintColor = Color3.new(1, 1, 1)}},
    {"Ч/Б", {Saturation = -1, Contrast = 0.2, TintColor = Color3.new(1, 1, 1)}},
    {"Тёплый", {Saturation = 0.2, Contrast = 0.05, TintColor = Color3.fromRGB(255, 225, 195)}},
    {"Холодный", {Saturation = 0.1, Contrast = 0.1, TintColor = Color3.fromRGB(195, 220, 255)}},
    {"Закат", {Saturation = 0.35, Contrast = 0.1, TintColor = Color3.fromRGB(255, 190, 215)}},
}
function X.ApplyGrade()
    local e = Lighting:FindFirstChild("SakuraGrade")
    if not V.ColorGrade then
        if e then e:Destroy() end
        return
    end
    if not e then e = New("ColorCorrectionEffect", {Name = "SakuraGrade"}, Lighting) end
    local m = X.gradeModes[V.GradeMode] or X.gradeModes[1]
    for k, v in pairs(m[2]) do e[k] = v end
end
Feature("ColorGrade", "🎨 Цветокоррекция", V, "ColorGrade", function() X.ApplyGrade() end)

Feature("FpsCap", "🎞 Лимит FPS", V, "FpsCap", function(on)
    if not setfpscap then error("executor не поддерживает setfpscap") end
    if on then
        X.origFps = getfpscap and getfpscap() or 60
        setfpscap(V.FpsCapValue)
    else
        setfpscap(X.origFps or 60)
    end
end)

Feature("NightVision", "🌙 Ночное зрение", V, "NightVision", function(on)
    local e = Lighting:FindFirstChild("SakuraNV")
    if e then e:Destroy() end
    if on then
        X.nvSaved = {Brightness = Lighting.Brightness, Ambient = Lighting.Ambient}
        New("ColorCorrectionEffect", {Name = "SakuraNV", TintColor = Color3.fromRGB(150, 255, 170), Brightness = 0.15,
            Contrast = 0.2, Saturation = -0.3}, Lighting)
        Lighting.Brightness = 3
        Lighting.Ambient = Color3.fromRGB(120, 140, 120)
    elseif X.nvSaved then
        Lighting.Brightness = X.nvSaved.Brightness
        Lighting.Ambient = X.nvSaved.Ambient
        X.nvSaved = nil
    end
end)

Feature("Rain", "🌧 Дождь", V, "Rain", function(on)
    if on then
        X.rainPart = New("Part", {Name = "SakuraRain", Anchored = true, CanCollide = false, CanQuery = false,
            CanTouch = false, Transparency = 1, Size = Vector3.new(80, 1, 80)}, WS)
        New("ParticleEmitter", {Rate = 220, Lifetime = NumberRange.new(1.4, 1.8), Speed = NumberRange.new(60, 75),
            SpreadAngle = Vector2.new(3, 3), EmissionDirection = Enum.NormalId.Bottom, Size = NumberSequence.new(0.18, 0.18),
            Color = ColorSequence.new(Color3.fromRGB(190, 215, 255)), LightEmission = 0.3,
            Transparency = NumberSequence.new(0.35, 0.8)}, X.rainPart)
        SM:AddConnection("Rain", RS.Heartbeat:Connect(function()
            if X.rainPart then X.rainPart.CFrame = CFrame.new(Camera.CFrame.Position + Vector3.new(0, 40, 0)) end
        end))
    else
        SM:RemoveConnection("Rain")
        if X.rainPart then X.rainPart:Destroy() X.rainPart = nil end
    end
end)

Feature("Vignette", "🌑 Виньетка", V, "Vignette", function(on)
    if X.vigGui then X.vigGui:Destroy() X.vigGui = nil end
    if not on then return end
    X.vigGui = New("ScreenGui", {Name = "SakuraVignette", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = -2}, player.PlayerGui)
    local function edge(pos, size, rot)
        local f = New("Frame", {Position = pos, Size = size, BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0}, X.vigGui)
        New("UIGradient", {Transparency = NumberSequence.new(0.25, 1), Rotation = rot}, f)
    end
    edge(UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.22, 0), 90)
    edge(UDim2.new(0, 0, 0.78, 0), UDim2.new(1, 0, 0.22, 0), 270)
    edge(UDim2.new(0, 0, 0, 0), UDim2.new(0.16, 0, 1, 0), 0)
    edge(UDim2.new(0.84, 0, 0, 0), UDim2.new(0.16, 0, 1, 0), 180)
end)

Feature("CoordsHUD", "📍 Координаты", V, "CoordsHUD", function(on)
    if on then
        X.coordsGui = New("ScreenGui", {Name = "SakuraCoords", ResetOnSpawn = false}, player.PlayerGui)
        local lbl = New("TextButton", {Position = UDim2.new(0, 10, 0, 220), Size = UDim2.new(0, 170, 0, 38),
            BackgroundColor3 = Color3.new(.05, .01, .1), BackgroundTransparency = 0.25, TextColor3 = Color3.new(1, 1, 1),
            TextSize = 11, Font = Enum.Font.GothamBold, BorderSizePixel = 0, Text = ""}, X.coordsGui)
        Round(lbl, 8)
        lbl.MouseButton1Click:Connect(function()
            if setclipboard and root then
                local pp = root.Position
                setclipboard(string.format("%.1f, %.1f, %.1f", pp.X, pp.Y, pp.Z))
                Toast("📋 Координаты скопированы")
            end
        end)
        local last = 0
        SM:AddConnection("CoordsHUD", RS.Heartbeat:Connect(function()
            if not root or tick() - last < 0.1 then return end
            last = tick()
            local pp, v = root.Position, root.AssemblyLinearVelocity
            lbl.Text = string.format("X %.0f  Y %.0f  Z %.0f\n⚡ %.0f ст/с (тап = копия)", pp.X, pp.Y, pp.Z,
                Vector3.new(v.X, 0, v.Z).Magnitude)
        end))
    else
        SM:RemoveConnection("CoordsHUD")
        if X.coordsGui then X.coordsGui:Destroy() X.coordsGui = nil end
    end
end)

X.alerted = {}
Feature("Alert", "🔔 Сигнал о врагах", V, "Alert", function(on)
    if on then
        local last = 0
        SM:AddConnection("Alert", RS.Heartbeat:Connect(function()
            if tick() - last < 0.3 or not root then return end
            last = tick()
            for _, plr in ipairs(Players:GetPlayers()) do
                if IsEnemy(plr, true) and IsAlive(plr) then
                    local r = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                    if r then
                        local near = (r.Position - root.Position).Magnitude <= V.AlertRange
                        if near and not X.alerted[plr] then
                            X.alerted[plr] = true
                            local snd = New("Sound", {SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 1}, WS)
                            snd:Play()
                            game:GetService("Debris"):AddItem(snd, 2)
                            Toast("⚠️ Рядом " .. plr.DisplayName)
                        elseif not near then X.alerted[plr] = nil end
                    end
                end
            end
        end))
    else
        SM:RemoveConnection("Alert")
        X.alerted = {}
    end
end)

X.startTime = os.time()
Feature("StatsHUD", "📊 Статистика", V, "StatsHUD", function(on)
    if on then
        X.statsGui = New("ScreenGui", {Name = "SakuraStats", ResetOnSpawn = false}, player.PlayerGui)
        local fr = New("Frame", {Position = UDim2.new(0, 10, 0, 150), Size = UDim2.new(0, 160, 0, 62),
            BackgroundColor3 = Color3.new(.05, .01, .1), BackgroundTransparency = 0.25, BorderSizePixel = 0}, X.statsGui)
        Round(fr, 8)
        local lbl = New("TextLabel", {Size = UDim2.new(1, -10, 1, -6), Position = UDim2.new(0, 5, 0, 3),
            BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = ""}, fr)
        local acc, frames = 0, 0
        SM:AddConnection("StatsHUD", RS.Heartbeat:Connect(function(dt)
            acc += dt frames += 1
            if acc < 0.5 then return end
            local fps = math.round(frames / acc)
            acc, frames = 0, 0
            local ping = SafeCall(function() return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end, 0)
            local total, near = 0, 0
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= player then
                    total += 1
                    local r = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                    if r and root and (r.Position - root.Position).Magnitude <= 100 then near += 1 end
                end
            end
            local t = os.time() - X.startTime
            lbl.Text = string.format("⏱ %02d:%02d:%02d\n👥 %d игроков (%d рядом)\n📶 %dms · ⚡ %d FPS",
                t // 3600, (t % 3600) // 60, t % 60, total, near, ping, fps)
        end))
    else
        SM:RemoveConnection("StatsHUD")
        if X.statsGui then X.statsGui:Destroy() X.statsGui = nil end
    end
end)

X.pfxSaved = {}
local function KillPFX(o)
    if o.Name == "SakuraGrade" or o.Name == "SakuraBlur" or o.Name == "SakuraNV" then return end
    if (o:IsA("BlurEffect") or o:IsA("ColorCorrectionEffect") or o:IsA("BloomEffect")
        or o:IsA("DepthOfFieldEffect") or o:IsA("SunRaysEffect")) and o.Enabled then
        X.pfxSaved[o] = true o.Enabled = false
    end
end
Feature("NoPostFX", "✨ Без пост-эффектов", V, "NoPostFX", function(on)
    if on then
        for _, o in ipairs(Lighting:GetChildren()) do KillPFX(o) end
        for _, o in ipairs(Camera:GetChildren()) do KillPFX(o) end
        SM:AddConnection("NoPostFX", Lighting.ChildAdded:Connect(KillPFX))
    else
        SM:RemoveConnection("NoPostFX")
        for o in pairs(X.pfxSaved) do if o.Parent then o.Enabled = true end end
        X.pfxSaved = {}
    end
end)

X.rbSaved = {}
Feature("RainbowBody", "🌈 Радужное тело", V, "RainbowBody", function(on)
    if on then
        SM:AddConnection("RainbowBody", RS.Heartbeat:Connect(function()
            if not char then return end
            local col = Color3.fromHSV((tick() * 0.4) % 1, 0.8, 1)
            for _, p in ipairs(char:GetChildren()) do
                if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                    if X.rbSaved[p] == nil then X.rbSaved[p] = p.Color end
                    p.Color = col
                end
            end
        end))
    else
        SM:RemoveConnection("RainbowBody")
        for p, c in pairs(X.rbSaved) do if p.Parent then p.Color = c end end
        X.rbSaved = {}
    end
end)

Feature("Trail", "💫 След", V, "Trail", function(on)
    local function clear()
        if root then
            for _, n in ipairs({"SakuraTrail", "SakuraA0", "SakuraA1"}) do
                local o = root:FindFirstChild(n)
                if o then o:Destroy() end
            end
        end
    end
    if on then
        local last = 0
        SM:AddConnection("Trail", RS.Heartbeat:Connect(function()
            if tick() - last < 0.5 or not root then return end
            last = tick()
            if not root:FindFirstChild("SakuraTrail") then
                local a0 = New("Attachment", {Name = "SakuraA0", Position = Vector3.new(0, 1, 0)}, root)
                local a1 = New("Attachment", {Name = "SakuraA1", Position = Vector3.new(0, -1, 0)}, root)
                New("Trail", {Name = "SakuraTrail", Attachment0 = a0, Attachment1 = a1, Lifetime = 0.7,
                    LightEmission = 1, Color = ColorSequence.new(uiColor, Color3.new(1, 1, 1)),
                    Transparency = NumberSequence.new(0.2, 1)}, root)
            end
        end))
    else
        SM:RemoveConnection("Trail")
        clear()
    end
end)

Feature("Flashlight", "💡 Фонарик", V, "Flashlight", function(on)
    if on then
        SM:AddConnection("Flashlight", RS.Heartbeat:Connect(function()
            local head = char and char:FindFirstChild("Head")
            if head and not head:FindFirstChild("SakuraLight") then
                New("PointLight", {Name = "SakuraLight", Range = 40, Brightness = 2}, head)
            end
        end))
    else
        SM:RemoveConnection("Flashlight")
        local head = char and char:FindFirstChild("Head")
        local l = head and head:FindFirstChild("SakuraLight")
        if l then l:Destroy() end
    end
end)

X.radarDots = {}
Feature("Radar", "📡 Радар", V, "Radar", function(on)
    if on then
        X.radarGui = New("ScreenGui", {Name = "SakuraRadar", ResetOnSpawn = false}, player.PlayerGui)
        local rf = New("Frame", {Size = UDim2.new(0, 130, 0, 130), Position = UDim2.new(1, -140, 0, 60),
            BackgroundColor3 = Color3.new(.05, .01, .1), BackgroundTransparency = 0.3, BorderSizePixel = 0,
            ClipsDescendants = true}, X.radarGui)
        Round(rf, 65)
        New("UIStroke", {Color = uiColor, Thickness = 2}, rf)
        New("Frame", {Size = UDim2.new(0, 6, 0, 6), Position = UDim2.new(.5, -3, .5, -3),
            BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, rf)
        X.radarDots = {}
        SM:AddConnection("Radar", RS.RenderStepped:Connect(function()
            if not root then return end
            local look = Camera.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude < 0.01 then return end
            local cf = CFrame.lookAt(Vector3.zero, flat.Unit)
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= player then
                    local c = plr.Character
                    local r = c and c:FindFirstChild("HumanoidRootPart")
                    local dot = X.radarDots[plr]
                    if r and IsAlive(plr) then
                        if not dot then
                            dot = New("Frame", {Size = UDim2.new(0, 6, 0, 6), BorderSizePixel = 0}, rf)
                            Round(dot, 3)
                            X.radarDots[plr] = dot
                        end
                        local rel = r.Position - root.Position
                        local o = cf:VectorToObjectSpace(Vector3.new(rel.X, 0, rel.Z)) / V.RadarRange * 60
                        local v = Vector2.new(o.X, o.Z)
                        if v.Magnitude > 60 then v = v.Unit * 60 end
                        dot.Position = UDim2.new(0.5, v.X - 3, 0.5, v.Y - 3)
                        dot.BackgroundColor3 = friends[plr.UserId] and Color3.fromRGB(60, 255, 120)
                            or ((player.Team and plr.Team == player.Team) and Color3.fromRGB(80, 160, 255)
                            or Color3.fromRGB(255, 60, 60))
                        dot.Visible = true
                    elseif dot then dot.Visible = false end
                end
            end
            for plr, dot in pairs(X.radarDots) do
                if not plr.Parent then dot:Destroy() X.radarDots[plr] = nil end
            end
        end))
    else
        SM:RemoveConnection("Radar")
        if X.radarGui then X.radarGui:Destroy() X.radarGui = nil end
        X.radarDots = {}
    end
end)

Feature("CustomFOV", "🔭 FOV", V, "CustomFOV", function(on)
    if on then
        X.fovSaved = Camera.FieldOfView
        BindCam("CustomFOV", function() Camera.FieldOfView = V.FOVValue end)
    else
        SM:RemoveConnection("CustomFOV")
        if X.fovSaved then Camera.FieldOfView = X.fovSaved X.fovSaved = nil end
    end
end)

function X.BuildCrosshair()
    if X.chGui then X.chGui:Destroy() X.chGui = nil end
    if not V.Crosshair then return end
    X.chGui = New("ScreenGui", {Name = "SakuraCrosshair", ResetOnSpawn = false, IgnoreGuiInset = true}, player.PlayerGui)
    local sz = V.CrosshairSize
    local function piece(w, h, round)
        local f = New("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, 0, .5, 0),
            Size = UDim2.new(0, w, 0, h), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, X.chGui)
        if round then Round(f, 100) end
        return f
    end
    local st = V.CrosshairStyle
    if st == 1 then
        piece(sz, 2) piece(2, sz)
    elseif st == 2 then
        piece(math.max(4, sz / 3), math.max(4, sz / 3), true)
    elseif st == 3 then
        local ring = piece(sz * 1.6, sz * 1.6, true)
        ring.BackgroundTransparency = 1
        New("UIStroke", {Thickness = 2, Color = Color3.new(1, 1, 1)}, ring)
        piece(3, 3, true)
    else
        piece(sz, 2) piece(2, sz) piece(4, 4, true)
    end
end
Feature("Crosshair", "➕ Прицел", V, "Crosshair", function() X.BuildCrosshair() end)

Feature("TimeLock", "🕐 Фикс. время", V, "TimeLock", function(on)
    if on then
        X.timeSaved = Lighting.ClockTime
        SM:AddConnection("TimeLock", RS.Heartbeat:Connect(function() Lighting.ClockTime = V.TimeValue end))
    else
        SM:RemoveConnection("TimeLock")
        if X.timeSaved then Lighting.ClockTime = X.timeSaved X.timeSaved = nil end
    end
end)

-- Точки, респавн, реджойн
local waypoints = {}
local function RespawnHere()
    if not root or not char then return end
    local cf = root.CFrame
    local conn
    conn = player.CharacterAdded:Connect(function(c)
        conn:Disconnect()
        local r = c:WaitForChild("HumanoidRootPart", 5)
        if r then task.wait(0.15) r.CFrame = cf end
    end)
    char:BreakJoints()
end
local function Rejoin(sameServer)
    if sameServer and game.JobId ~= "" then
        TeleportSvc:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
    else
        TeleportSvc:Teleport(game.PlaceId, player)
    end
end
Feature("AutoRejoin", "🔁 Авто-реджойн", Config.Misc, "AutoRejoin", function(on)
    if on then
        SM:AddConnection("AutoRejoin", GuiService.ErrorMessageChanged:Connect(function(msg)
            if msg and msg ~= "" then task.wait(3) SafeCall(function() Rejoin(true) end) end
        end))
    else SM:RemoveConnection("AutoRejoin") end
end)

Loader.Step("ESP система", 0.58)

-- ============ ESP ============
local E = Config.ESP
local hasDrawing = type(Drawing) == "table" or type(Drawing) == "userdata"

local R15 = {{"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"}, {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"}, {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"},
    {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"}}
local R6 = {{"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"}, {"Torso", "Left Leg"}, {"Torso", "Right Leg"}}

local function NewDraw(kind, props)
    if not hasDrawing then return nil end
    return SafeCall(function()
        local d = Drawing.new(kind)
        for k, v in pairs(props) do d[k] = v end
        return d
    end)
end
local function KillDraw(o)
    if not o then return end
    SafeCall(function() if o.Remove then o:Remove() else o:Destroy() end end)
end

local ESP = {data = {}, last = 0}

function ESP:Remove(plr)
    local d = self.data[plr]
    if not d then return end
    self.data[plr] = nil
    for _, k in ipairs({"Highlight", "Gui", "Dot", "Box", "Line", "Arrow2"}) do
        if d[k] then SafeCall(function() d[k]:Destroy() end) end
    end
    for part, m in pairs(d.Mats) do SafeCall(function() if part.Parent then part.Material = m end end) end
    KillDraw(d.Tracer) KillDraw(d.Arrow)
    if d.Bones then for _, l in pairs(d.Bones) do SafeCall(function() l:Destroy() end) end end
    for _, l in ipairs(d.Lines) do KillDraw(l.line) end
end

function ESP:Clear()
    for plr in pairs(self.data) do self:Remove(plr) end
    if self.linesGui then self.linesGui:Destroy() self.linesGui = nil end
    if self.arrowsGui then self.arrowsGui:Destroy() self.arrowsGui = nil end
end

-- Линии до игроков (рисуются обычными GUI-рамками, Drawing не нужен)
function ESP:UpdateLines()
    if not (E.Lines or E.Bones) then return end
    if not self.linesGui or not self.linesGui.Parent then
        self.linesGui = New("ScreenGui", {Name = "SakuraLines", ResetOnSpawn = false, IgnoreGuiInset = true,
            DisplayOrder = -1}, player.PlayerGui)
    end
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local origin = E.LineOrigin == 1 and Vector2.new(vp.X / 2, vp.Y)
        or (E.LineOrigin == 3 and Vector2.new(vp.X / 2, 0) or center)
    for _, d in pairs(self.data) do
        local fr = d.Line
        local target = E.Lines and d.Show and d.Char and d.Char:FindFirstChild("HumanoidRootPart")
        if target then
            if not fr then
                fr = New("Frame", {AnchorPoint = Vector2.new(.5, .5), BorderSizePixel = 0,
                    BackgroundTransparency = 0.15}, self.linesGui)
                d.Line = fr
            end
            local p = Camera:WorldToViewportPoint(target.Position)
            local pt = Vector2.new(p.X, p.Y)
            if p.Z < 0 then pt = center - (pt - center) end
            local v = pt - origin
            if v.Magnitude > 4000 then pt = origin + v.Unit * 4000 v = pt - origin end
            fr.BackgroundColor3 = d.Color or E.Color
            fr.Size = UDim2.new(0, v.Magnitude, 0, E.LineThickness)
            fr.Position = UDim2.new(0, (origin.X + pt.X) / 2, 0, (origin.Y + pt.Y) / 2)
            fr.Rotation = math.deg(math.atan2(v.Y, v.X))
            fr.Visible = true
        elseif fr then
            fr.Visible = false
        end
        if E.Bones and d.Show and d.Char then
            d.Bones = d.Bones or {}
            local c = d.Char
            local hm = c:FindFirstChildOfClass("Humanoid")
            local list = (hm and hm.RigType == Enum.HumanoidRigType.R15) and R15 or R6
            for i, pair in ipairs(list) do
                local pa, pb = c:FindFirstChild(pair[1]), c:FindFirstChild(pair[2])
                local ln = d.Bones[i]
                local drawn = false
                if pa and pb then
                    local a, oa = Camera:WorldToViewportPoint(pa.Position)
                    local b, ob = Camera:WorldToViewportPoint(pb.Position)
                    if oa and ob then
                        if not ln then
                            ln = New("Frame", {AnchorPoint = Vector2.new(.5, .5), BorderSizePixel = 0}, self.linesGui)
                            d.Bones[i] = ln
                        end
                        local v = Vector2.new(b.X - a.X, b.Y - a.Y)
                        ln.BackgroundColor3 = d.Color or E.Color
                        ln.Size = UDim2.new(0, v.Magnitude, 0, 2)
                        ln.Position = UDim2.new(0, (a.X + b.X) / 2, 0, (a.Y + b.Y) / 2)
                        ln.Rotation = math.deg(math.atan2(v.Y, v.X))
                        ln.Visible = true
                        drawn = true
                    end
                end
                if not drawn and ln then ln.Visible = false end
            end
        elseif d.Bones then
            for _, ln in pairs(d.Bones) do ln.Visible = false end
        end
    end
end

function ESP:Create(plr)
    local c = plr.Character
    if not c then return end
    local d = self.data[plr]
    if d and d.Char == c then return end
    if d then self:Remove(plr) end
    local head, h = c:FindFirstChild("Head"), c:FindFirstChildOfClass("Humanoid")
    if not head or not h then return end

    d = {Char = c, Mats = {}, Lines = {}}
    d.Highlight = New("Highlight", {Name = "ESP_HL", Adornee = c, FillColor = E.Color, OutlineColor = E.Color,
        FillTransparency = E.Chams and 0.1 or E.Transparency, OutlineTransparency = E.OutlineTransparency,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop}, c)

    d.Gui = New("BillboardGui", {Name = "ESP_GUI", Size = UDim2.new(0, 160, 0, 58), Adornee = head,
        AlwaysOnTop = true, StudsOffset = Vector3.new(0, 3, 0)}, c)
    local function lbl(y, h2, size, x, w)
        return New("TextLabel", {Size = UDim2.new(w or 1, 0, 0, h2), Position = UDim2.new(x or 0, 0, 0, y),
            BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), TextSize = size, Font = Enum.Font.GothamBold,
            TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0.3, Text = ""}, d.Gui)
    end
    d.NameLbl = lbl(0, 16, 12)
    d.NameLbl.Text = plr.Name
    local bg = New("Frame", {Size = UDim2.new(0.7, 0, 0, 5), Position = UDim2.new(0.05, 0, 0, 20),
        BackgroundColor3 = Color3.new(.2, .2, .2), BorderSizePixel = 0}, d.Gui)
    d.HealthBar = New("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 1, 0), BorderSizePixel = 0}, bg)
    d.HealthBg = bg
    d.HealthLbl = lbl(16, 14, 10, 0.77, 0.2)
    d.DistLbl = lbl(28, 14, 10)
    d.ToolLbl = lbl(42, 14, 10)

    if E.HeadDot then
        d.Dot = New("BillboardGui", {Name = "ESP_Dot", Size = UDim2.new(0, 10, 0, 10), Adornee = head, AlwaysOnTop = true}, c)
        local f = New("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = E.Color, BorderSizePixel = 0}, d.Dot)
        Round(f, 5)
    end
    if E.Box then
        local hrp = c:FindFirstChild("HumanoidRootPart")
        if hrp then
            d.Box = New("BillboardGui", {Name = "ESP_Box", Adornee = hrp, Size = UDim2.new(4, 0, 5.5, 0), AlwaysOnTop = true}, c)
            local bf = New("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1}, d.Box)
            d.BoxStroke = New("UIStroke", {Thickness = 1.5, Color = E.Color}, bf)
        end
    end
    if E.Glow then
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then d.Mats[p] = p.Material p.Material = Enum.Material.Neon end
        end
    end
    if E.Tracers then d.Tracer = NewDraw("Line", {Thickness = 2, Transparency = 0.7, Visible = false}) end
    if E.Arrow then d.Arrow = NewDraw("Triangle", {Thickness = 2, Filled = true, Transparency = 0.7, Visible = false}) end
    if E.Skeleton and hasDrawing then
        for _, pair in ipairs(h.RigType == Enum.HumanoidRigType.R15 and R15 or R6) do
            local line = NewDraw("Line", {Thickness = 2, Visible = false})
            if line then d.Lines[#d.Lines + 1] = {line = line, a = pair[1], b = pair[2]} end
        end
    end
    self.data[plr] = d
end

-- Стрелки к игрокам за экраном (обычные GUI, Drawing не нужен)
function ESP:UpdateArrows()
    if not E.GuiArrows then
        if self.arrowsGui then self.arrowsGui:Destroy() self.arrowsGui = nil end
        return
    end
    if not self.arrowsGui or not self.arrowsGui.Parent then
        self.arrowsGui = New("ScreenGui", {Name = "SakuraArrows", ResetOnSpawn = false, IgnoreGuiInset = true,
            DisplayOrder = -1}, player.PlayerGui)
    end
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    for _, d in pairs(self.data) do
        local target = d.Show and d.Char and d.Char:FindFirstChild("HumanoidRootPart")
        local ar = d.Arrow2
        if target then
            local p = Camera:WorldToViewportPoint(target.Position)
            local offscreen = p.Z < 0 or p.X < 0 or p.X > vp.X or p.Y < 0 or p.Y > vp.Y
            if offscreen then
                if not ar then
                    ar = New("TextLabel", {AnchorPoint = Vector2.new(.5, .5), Size = UDim2.new(0, 30, 0, 30),
                        BackgroundTransparency = 1, Text = "▲", TextSize = 26, Font = Enum.Font.GothamBold}, self.arrowsGui)
                    d.Arrow2 = ar
                end
                local dir = Vector2.new(p.X, p.Y) - center
                if p.Z < 0 then dir = -dir end
                if dir.Magnitude < 1 then dir = Vector2.new(0, 1) end
                dir = dir.Unit
                local k = math.min((vp.X / 2 - 34) / math.max(math.abs(dir.X), 0.001),
                    (vp.Y / 2 - 34) / math.max(math.abs(dir.Y), 0.001))
                local pos = center + dir * k
                ar.Position = UDim2.new(0, pos.X, 0, pos.Y)
                ar.Rotation = math.deg(math.atan2(dir.Y, dir.X)) + 90
                ar.TextColor3 = d.Color or E.Color
                ar.Visible = true
            elseif ar then ar.Visible = false end
        elseif ar then ar.Visible = false end
    end
end

function ESP:Update()
    self:UpdateLines()
    self:UpdateArrows()
    if tick() - self.last < E.UpdateRate then return end
    self.last = tick()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character then self:Create(plr) end
    end
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local rainbow = RainbowColor(0.5)

    local allowed
    if E.MaxPlayers > 0 then
        local list = {}
        for plr, d in pairs(self.data) do
            local hd = d.Char and d.Char:FindFirstChild("Head")
            if hd and IsAlive(plr) and (IsEnemy(plr, E.TeamCheck) or (friends[plr.UserId] and E.ShowFriends)) then
                list[#list + 1] = {plr, (Camera.CFrame.Position - hd.Position).Magnitude}
            end
        end
        table.sort(list, function(a, b) return a[2] < b[2] end)
        allowed = {}
        for i = 1, math.min(E.MaxPlayers, #list) do allowed[list[i][1]] = true end
    end

    for plr, d in pairs(self.data) do
        local c = d.Char
        local head, h = c:FindFirstChild("Head"), c:FindFirstChildOfClass("Humanoid")
        local friend = friends[plr.UserId]
        local show = (IsAlive(plr) and plr.Character == c and (IsEnemy(plr, E.TeamCheck) or (friend and E.ShowFriends))
            and head ~= nil and h ~= nil and (not allowed or allowed[plr])) and true or false
        local dist = 0
        if show then
            dist = (Camera.CFrame.Position - head.Position).Magnitude
            if dist > E.MaxDistance or dist < E.MinDistance then show = false end
        end
        d.Show = show
        d.Highlight.Enabled, d.Gui.Enabled = show, show
        if d.Dot then d.Dot.Enabled = show end
        if d.Box then d.Box.Enabled = show end

        if not show then
            if d.Tracer then d.Tracer.Visible = false end
            if d.Arrow then d.Arrow.Visible = false end
            for _, l in ipairs(d.Lines) do l.line.Visible = false end
        else
            local frac = math.clamp(h.Health / math.max(h.MaxHealth, 1), 0, 1)
            local color
            if E.ColorMode == 0 then color = HealthColor(frac)
            elseif E.ColorMode == 1 then color = rainbow
            elseif E.ColorMode == 3 then color = Color3.fromHSV(math.clamp(dist / E.DistColorRange, 0, 1) * 0.6, 1, 1)
            elseif E.ColorMode == 4 then color = plr.TeamColor and plr.TeamColor.Color or E.Color
            else color = E.Color end
            if friend then color = Color3.fromRGB(60, 255, 120) end
            if Shared.aimTarget == plr then color = Color3.fromRGB(255, 215, 0) end
            if E.VisCheck then
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = {char, c}
                if WS:Raycast(Camera.CFrame.Position, head.Position - Camera.CFrame.Position, rp) == nil then
                    color = Color3.fromRGB(255, 255, 90)
                end
            end
            d.Color = color
            d.Highlight.FillColor, d.Highlight.OutlineColor = color, color
            d.Highlight.FillTransparency = E.OutlineOnly and 1 or (E.Chams and 0.1 or E.Transparency)
            d.HealthBar.Size = UDim2.new(frac, 0, 1, 0)
            d.HealthBar.BackgroundColor3 = HealthColor(frac)
            d.HealthLbl.Text = tostring(math.floor(frac * 100))
            d.HealthLbl.TextColor3 = HealthColor(frac)
            d.DistLbl.Text = math.round(dist) .. "m"
            if E.ShowSpeed then
                local rp2 = c:FindFirstChild("HumanoidRootPart")
                local sv = rp2 and rp2.AssemblyLinearVelocity or Vector3.zero
                d.DistLbl.Text = math.round(dist) .. "m · " .. math.floor(Vector3.new(sv.X, 0, sv.Z).Magnitude) .. " st/s"
            end
            local tool = c:FindFirstChildOfClass("Tool")
            d.ToolLbl.Text = (E.ShowTool and tool) and ("🔧 " .. tool.Name) or ""
            d.NameLbl.TextSize = E.NameSize
            d.NameLbl.Text = plr.Name .. (friend and " ⭐" or "")
            d.NameLbl.Visible, d.HealthBg.Visible = E.ShowName, E.ShowHealth
            d.HealthLbl.Visible, d.DistLbl.Visible = E.ShowHealth, E.ShowDistance
            if d.BoxStroke then d.BoxStroke.Color = color end
            if d.Dot then d.Dot.Frame.BackgroundColor3 = color end

            local target = c:FindFirstChild("HumanoidRootPart") or head
            local p, on = Camera:WorldToViewportPoint(target.Position)
            if d.Tracer then
                d.Tracer.Visible = on
                if on then d.Tracer.From = Vector2.new(center.X, 10) d.Tracer.To = Vector2.new(p.X, p.Y) d.Tracer.Color = color end
            end
            if d.Arrow then
                if on then d.Arrow.Visible = false else
                    local dir = Vector2.new(p.X, p.Y) - center
                    if p.Z < 0 then dir = -dir end
                    dir = dir.Magnitude > 1 and dir.Unit or Vector2.new(0, 1)
                    local radius = math.min(vp.X, vp.Y) / 2 - 50
                    local pos = center + dir * radius
                    local ang, s = math.atan2(dir.Y, dir.X), 15
                    d.Arrow.PointA = pos + Vector2.new(math.cos(ang + 2.5), math.sin(ang + 2.5)) * s
                    d.Arrow.PointB = pos + Vector2.new(math.cos(ang - 2.5), math.sin(ang - 2.5)) * s
                    d.Arrow.PointC = pos + Vector2.new(math.cos(ang), math.sin(ang)) * s * 1.5
                    d.Arrow.Color = color
                    d.Arrow.Visible = true
                end
            end
            for _, l in ipairs(d.Lines) do
                local pa, pb = c:FindFirstChild(l.a), c:FindFirstChild(l.b)
                if pa and pb then
                    local a, oa = Camera:WorldToViewportPoint(pa.Position)
                    local b, ob = Camera:WorldToViewportPoint(pb.Position)
                    l.line.Visible = oa and ob
                    if oa and ob then l.line.From = Vector2.new(a.X, a.Y) l.line.To = Vector2.new(b.X, b.Y) l.line.Color = color end
                else l.line.Visible = false end
            end
        end
    end
end

function ESP:RefreshAll() self:Clear() end -- пересоздастся в Update

Feature("ESP", "👁 ESP", E, "Enabled", function(on)
    if on then
        ESP.last = 0
        SM:AddConnection("ESPUpdate", RS.RenderStepped:Connect(function() ESP:Update() end))
        SM:AddConnection("ESPLeave", Players.PlayerRemoving:Connect(function(p) ESP:Remove(p) end))
    else
        SM:RemoveConnection("ESPUpdate")
        SM:RemoveConnection("ESPLeave")
        ESP:Clear()
    end
end)

Loader.Step("Модуль прицеливания", 0.72)

-- ============ AIMBOT ============
local A = Config.Aimbot
local Aim = {target = nil, clicking = false}

local function Click()
    if mouse1click then mouse1click() else VU:ClickButton1(Vector2.new()) end
end

function X.UpdateAimLine(wp)
    if not (X.aimLineGui and X.aimLineGui.Parent) then
        X.aimLineGui = New("ScreenGui", {Name = "SakuraAimLine", ResetOnSpawn = false, IgnoreGuiInset = true,
            DisplayOrder = -1}, player.PlayerGui)
        X.aimLine = New("Frame", {AnchorPoint = Vector2.new(.5, .5), BorderSizePixel = 0,
            BackgroundColor3 = Color3.fromRGB(255, 215, 0), BackgroundTransparency = 0.2}, X.aimLineGui)
    end
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local p = Camera:WorldToViewportPoint(wp)
    if p.Z < 0 then X.aimLine.Visible = false return end
    local pt = Vector2.new(p.X, p.Y)
    local v = pt - center
    X.aimLine.Size = UDim2.new(0, v.Magnitude, 0, 2)
    X.aimLine.Position = UDim2.new(0, (center.X + pt.X) / 2, 0, (center.Y + pt.Y) / 2)
    X.aimLine.Rotation = math.deg(math.atan2(v.Y, v.X))
    X.aimLine.Visible = true
end

function Aim:Score(plr, center)
    local part = GetPart(plr.Character, A.Mode)
    if not part then return nil end
    if A.MaxDistance > 0 and (part.Position - Camera.CFrame.Position).Magnitude > A.MaxDistance then return nil end
    if A.IgnoreFF and plr.Character:FindFirstChildOfClass("ForceField") then return nil end
    local pos, on = Camera:WorldToViewportPoint(part.Position)
    if not on then return nil end
    if not A.IgnoreWalls then
        local p = RaycastParams.new()
        p.FilterType = Enum.RaycastFilterType.Exclude
        p.FilterDescendantsInstances = {char, plr.Character}
        p.IgnoreWater = true
        if WS:Raycast(Camera.CFrame.Position, part.Position - Camera.CFrame.Position, p) then return nil end
    end
    return (Vector2.new(pos.X, pos.Y) - center).Magnitude, part
end

function Aim:Find()
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    if A.AimLock and self.target and IsEnemy(self.target, A.TeamCheck) and IsAlive(self.target) then
        local d = self:Score(self.target, center)
        if d then return self.target end
    end
    local best, bestMetric = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if IsEnemy(plr, A.TeamCheck) and IsAlive(plr) then
            local d, part = self:Score(plr, center)
            if d and d < A.FOV then
                local metric = d
                if A.Priority == 2 then
                    local h2 = plr.Character:FindFirstChildOfClass("Humanoid")
                    metric = h2 and h2.Health or d
                elseif A.Priority == 3 then
                    metric = (part.Position - Camera.CFrame.Position).Magnitude
                end
                if metric < bestMetric then best, bestMetric = plr, metric end
            end
        end
    end
    return best
end

function Aim:Update()
    local active
    if A.HoldMode then active = X.aimHeld else active = A.Enabled end
    if not active or spectating or M.Freecam or (A.NeedTool and not (char and char:FindFirstChildOfClass("Tool"))) then
        self.target = nil Shared.aimTarget = nil
        if X.aimLine then X.aimLine.Visible = false end
        return
    end
    local target = self:Find()
    self.target = target
    Shared.aimTarget = target
    if not target then return end
    local part = GetPart(target.Character, A.Mode)
    if not part then return end

    local pos = part.Position + Vector3.new(0, A.AimOffsetY, 0)
    if A.Jitter > 0 then
        pos = pos + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * A.Jitter
    end
    if A.Prediction then
        local mult = A.PredictionMultiplier
        if A.ProjectileSpeed > 0 then mult = (part.Position - Camera.CFrame.Position).Magnitude / A.ProjectileSpeed end
        pos += part.AssemblyLinearVelocity * mult
    end
    local cur = Camera.CFrame
    local goal = CFrame.new(cur.Position, pos)
    Camera.CFrame = A.Smoothness > 0 and cur:Lerp(goal, A.Smoothness) or goal

    if A.ShowLine then X.UpdateAimLine(part.Position)
    elseif X.aimLine then X.aimLine.Visible = false end

    if A.Triggerbot and not self.clicking then
        local p, on = Camera:WorldToViewportPoint(part.Position)
        local vp = Camera.ViewportSize
        if on and (Vector2.new(p.X, p.Y) - Vector2.new(vp.X / 2, vp.Y / 2)).Magnitude < 50 then
            self.clicking = true
            SafeCall(Click)
            task.delay(A.TriggerDelay, function() self.clicking = false end)
        end
    end
end

-- FOV круг
local function UpdateFOV()
    if not X.fovCircle then return end
    X.fovCircle.Visible = (A.Enabled or (A.HoldMode and X.aimHeld)) and A.ShowFOV
    X.fovCircle.BackgroundTransparency = A.FovAlpha
    X.fovCircle.Size = UDim2.new(0, A.FOV * 2, 0, A.FOV * 2)
end
local function CreateFOV()
    X.fovGui = New("ScreenGui", {Name = "SakuraFOV", ResetOnSpawn = false, IgnoreGuiInset = true}, player.PlayerGui)
    X.fovCircle = New("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, 0, .5, 0),
        BackgroundTransparency = 0.9, BackgroundColor3 = Color3.fromRGB(0, 255, 0), Visible = false, ZIndex = 999}, X.fovGui)
    New("UIStroke", {Color = Color3.fromRGB(0, 255, 0), Thickness = 2}, X.fovCircle)
    Round(X.fovCircle, 1000)
    SM.objects[#SM.objects + 1] = X.fovGui
    UpdateFOV()
end

Feature("Aimbot", "🎯 Aimbot (Q)", A, "Enabled", UpdateFOV)
Feature("Triggerbot", "Triggerbot (T)", A, "Triggerbot")
Feature("AimLock", "Aim Lock", A, "AimLock")
Feature("Prediction", "Prediction", A, "Prediction")
Feature("AimTeam", "Team Check", A, "TeamCheck")
Feature("IgnoreWalls", "Ignore Walls", A, "IgnoreWalls")
Feature("AimHold", "🖐 Аим только при зажатии", A, "HoldMode")
Feature("AimFF", "🛡 Игнор ForceField", A, "IgnoreFF")
Feature("AimNeedTool", "🔧 Аим только с оружием", A, "NeedTool")
Feature("AimShowFOV", "⭕ Круг FOV", A, "ShowFOV", UpdateFOV)
Feature("AimLine", "〰 Линия к цели", A, "ShowLine", function(on)
    if not on and X.aimLineGui then
        X.aimLineGui:Destroy()
        X.aimLineGui, X.aimLine = nil, nil
    end
end)
Feature("TargetHUD", "📋 Инфо о цели", A, "TargetHUD", function(on)
    if on then
        X.thGui = New("ScreenGui", {Name = "SakuraTargetHUD", ResetOnSpawn = false}, player.PlayerGui)
        X.thLbl = New("TextLabel", {Size = UDim2.new(0, 190, 0, 40), Position = UDim2.new(0.5, -95, 0, 100),
            BackgroundColor3 = Color3.new(.05, .01, .1), BackgroundTransparency = 0.2, TextColor3 = Color3.new(1, 1, 1),
            TextSize = 12, Font = Enum.Font.GothamBold, BorderSizePixel = 0, Visible = false}, X.thGui)
        Round(X.thLbl, 8)
        SM:AddConnection("TargetHUD", RS.Heartbeat:Connect(function()
            local t = Aim.target
            local c = t and t.Character
            local h2 = c and c:FindFirstChildOfClass("Humanoid")
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if h2 and r and root then
                X.thLbl.Visible = true
                X.thLbl.Text = t.DisplayName .. "\n❤ " .. math.floor(h2.Health) .. " | " .. math.floor((r.Position - root.Position).Magnitude) .. "m"
            else X.thLbl.Visible = false end
        end))
    else
        SM:RemoveConnection("TargetHUD")
        if X.thGui then X.thGui:Destroy() X.thGui = nil end
    end
end)

for _, id in ipairs({"Tracers", "Arrow", "HeadDot", "Glow", "Chams", "Skeleton", "Box"}) do
    Feature("ESP_" .. id, id, E, id, function() ESP:RefreshAll() end)
end
Feature("ESPTeam", "Team Check", E, "TeamCheck")
Feature("ESP_Lines", "📏 Линии", E, "Lines", function() ESP:RefreshAll() end)
Feature("ESP_Bones", "🦴 Скелет (GUI)", E, "Bones", function() ESP:RefreshAll() end)
Feature("ESP_Tool", "🔧 Оружие в руках", E, "ShowTool")
Feature("ESP_Arrows", "🧭 Стрелки (GUI)", E, "GuiArrows")
Feature("ESP_Outline", "▭ Только контур", E, "OutlineOnly")
Feature("ESP_VisCheck", "👁 Видимых — жёлтым", E, "VisCheck")
Feature("ESP_Speed", "💨 Скорость цели", E, "ShowSpeed")
Feature("EnemyCount", "🔢 Счётчик врагов", E, "EnemyCount", function(on)
    if on then
        X.countGui = New("ScreenGui", {Name = "SakuraCount", ResetOnSpawn = false}, player.PlayerGui)
        local lbl = New("TextLabel", {AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 74),
            Size = UDim2.new(0, 200, 0, 24), BackgroundColor3 = Color3.new(.05, .01, .1), BackgroundTransparency = 0.3,
            TextColor3 = Color3.new(1, 1, 1), TextSize = 12, Font = Enum.Font.GothamBold, BorderSizePixel = 0, Text = ""}, X.countGui)
        Round(lbl, 8)
        local last = 0
        SM:AddConnection("EnemyCount", RS.Heartbeat:Connect(function()
            if tick() - last < 0.4 or not root then return end
            last = tick()
            local n, nearest = 0, math.huge
            for _, plr in ipairs(Players:GetPlayers()) do
                if IsEnemy(plr, E.TeamCheck) and IsAlive(plr) then
                    n += 1
                    local r = plr.Character:FindFirstChild("HumanoidRootPart")
                    if r then nearest = math.min(nearest, (r.Position - root.Position).Magnitude) end
                end
            end
            lbl.Text = "👥 Врагов: " .. n .. (n > 0 and (" · ближайший " .. math.floor(nearest) .. "m") or "")
        end))
    else
        SM:RemoveConnection("EnemyCount")
        if X.countGui then X.countGui:Destroy() X.countGui = nil end
    end
end)
Feature("ESP_Name", "Имя", E, "ShowName")
Feature("ESP_Health", "Здоровье", E, "ShowHealth")
Feature("ESP_Dist", "Дистанция", E, "ShowDistance")
Feature("ESP_Friends", "Друзья (зелёные)", E, "ShowFriends")
Feature("Notify", "🔔 Уведомления", Config.Misc, "Notify")
Feature("AutoSave", "💾 Автосохранение", Config.Misc, "AutoSave")
Feature("UISound", "🔊 Звуки меню", Config.Misc, "UISound")
Feature("UseImage", "🖼 Картинка-фон", Config.Misc, "UseImage", function() X.ApplyImage() end)

Loader.Step("Профили и настройки", 0.82)

-- ============ ПРОФИЛЬ (сохранение настроек) ============
local canFile = (writefile ~= nil and readfile ~= nil and isfile ~= nil)
local profileStatus = canFile and "Готово к работе" or "⚠️ Executor не поддерживает файлы"
local profileSlot = 1
local function ProfilePath() return "Sakura_" .. game.PlaceId .. (profileSlot > 1 and ("_" .. profileSlot) or "") .. ".json" end

local function Ser(v)
    if typeof(v) == "Color3" then return {__c = {v.R, v.G, v.B}} end
    if type(v) == "table" then
        local o = {}
        for k, x in pairs(v) do o[k] = Ser(x) end
        return o
    end
    return v
end
local function Deser(v)
    if type(v) == "table" then
        if v.__c then return Color3.new(v.__c[1], v.__c[2], v.__c[3]) end
        local o = {}
        for k, x in pairs(v) do o[k] = Deser(x) end
        return o
    end
    return v
end

local function BuildProfile()
    local values = {}
    for section, tbl in pairs(Config) do
        local o = {}
        for k, v in pairs(tbl) do
            if not (featureKeys[tbl] and featureKeys[tbl][k]) then o[k] = Ser(v) end
        end
        values[section] = o
    end
    local feats, fr = {}, {}
    for _, f in ipairs(Features) do feats[f.Id] = f.Tbl[f.Key] end
    for uid in pairs(friends) do fr[#fr + 1] = uid end
    local wp = {}
    for i, cf in pairs(waypoints) do wp[tostring(i)] = {cf:GetComponents()} end
    return {version = 14, values = values, features = feats, friends = fr,
        theme = {idx = themeIdx, accent = uiColorIndex, alpha = uiAlpha,
            custom = customAccent and {customAccent.R, customAccent.G, customAccent.B} or nil,
            scale = X.menuScale},
        touched = {speed = speedTouched, jump = jumpTouched}, waypoints = wp}
end

local function SaveConfig()
    if not canFile then return false, "файлы не поддерживаются" end
    local ok, err = pcall(function() writefile(ProfilePath(), Http:JSONEncode(BuildProfile())) end)
    return ok, err
end

local function ApplyProfile(data)
    Loading = true
    for section, vals in pairs(data.values or {}) do
        local tbl = Config[section]
        if tbl and type(vals) == "table" then
            for k, v in pairs(vals) do
                v = Deser(v)
                if tbl[k] ~= nil and typeof(v) == typeof(tbl[k]) and not (featureKeys[tbl] and featureKeys[tbl][k]) then
                    tbl[k] = v
                end
            end
        end
    end
    local th = data.theme
    if type(th) == "table" then
        if Themes[th.idx] then themeIdx = th.idx end
        if type(th.accent) == "number" and th.accent >= 0 and th.accent <= #uiColors then uiColorIndex = th.accent end
        if type(th.alpha) == "number" then uiAlpha = math.clamp(th.alpha, 0, 0.9) end
        if type(th.custom) == "table" and #th.custom == 3 then
            customAccent = Color3.new(th.custom[1], th.custom[2], th.custom[3])
        else customAccent = nil end
        if type(th.scale) == "number" then X.menuScale = math.clamp(th.scale, 0.6, 1.3) end
        bgColor = Themes[themeIdx][3]
        if not Config.Visuals.RainbowUI then uiColor = BaseAccent() end
    end
    if type(data.touched) == "table" then
        speedTouched, jumpTouched = data.touched.speed == true, data.touched.jump == true
    end
    friends = {}
    for _, uid in ipairs(data.friends or {}) do friends[uid] = true end
    if type(data.waypoints) == "table" then
        for k, comps in pairs(data.waypoints) do
            local i = tonumber(k)
            if i and type(comps) == "table" and #comps == 12 then waypoints[i] = CFrame.new(table.unpack(comps)) end
        end
    end
    for id, st in pairs(data.features or {}) do
        local f = F[id]
        if f and type(st) == "boolean" then f.Set(st) end
    end
    ApplySpeed() ApplyJump()
    Loading = false
    ApplyTheme()
    if X.RebuildQuick then pcall(X.RebuildQuick) end
    return true
end

local function LoadConfig()
    if not (canFile and isfile(ProfilePath())) then return false, "профиль не найден" end
    local ok, data = pcall(function() return Http:JSONDecode(readfile(ProfilePath())) end)
    if not ok or type(data) ~= "table" then return false, "файл повреждён" end
    return ApplyProfile(data)
end

X.dirtyPending = false
MarkDirty = function()
    if not Running or Loading or not Config.Misc.AutoSave or X.dirtyPending then return end
    X.dirtyPending = true
    task.delay(3, function()
        X.dirtyPending = false
        if Running and Config.Misc.AutoSave then SaveConfig() end
    end)
end

-- ============ КАРТИНКА И РЕЖИМЫ МЕНЮ (Sakura / Space) ============
-- Roblox не умеет показывать картинки по ссылке напрямую, поэтому файл скачивается в папку executor
-- и подключается через getcustomasset. Нужны writefile, isfile и getcustomasset.
function X.CurAsset()
    if not Config.Misc.UseImage then return nil end
    return X.imageAssets[Config.Misc.MenuMode]
end

function X.BuildStars(main)
    for _, tw in ipairs(X.starTweens) do pcall(function() tw:Cancel() end) end
    X.starTweens = {}
    local old = main:FindFirstChild("SakuraStars")
    if old then old:Destroy() end
    if Config.Misc.MenuMode ~= "space" then return end
    local box = New("Frame", {Name = "SakuraStars", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        ZIndex = -1, ClipsDescendants = true}, main)
    local rng = Random.new(7)
    for i = 1, 55 do
        local size = rng:NextInteger(1, 3)
        local star = New("Frame", {Size = UDim2.new(0, size, 0, size),
            Position = UDim2.new(rng:NextNumber(), 0, rng:NextNumber(), 0),
            BackgroundColor3 = (i % 4 == 0) and Color3.fromRGB(190, 150, 255) or Color3.new(1, 1, 1),
            BackgroundTransparency = rng:NextNumber(0.1, 0.5), BorderSizePixel = 0, ZIndex = -1}, box)
        Round(star, 2)
        if i % 3 == 0 then
            local tw = TS:Create(star, TweenInfo.new(rng:NextNumber(1.2, 2.8), Enum.EasingStyle.Sine,
                Enum.EasingDirection.InOut, -1, true), {BackgroundTransparency = 0.95})
            tw:Play()
            X.starTweens[#X.starTweens + 1] = tw
        end
    end
end

function X.BuildBG(main)
    if not main then return end
    for _, n in ipairs({"SakuraBG", "SakuraBGDim"}) do
        local o = main:FindFirstChild(n)
        if o then o:Destroy() end
    end
    local asset = X.CurAsset()
    if asset then
        local img = New("ImageLabel", {Name = "SakuraBG", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
            Image = asset, ScaleType = Enum.ScaleType.Crop, ZIndex = -4}, main)
        Round(img, Config.Misc.Corner)
        local dim = New("Frame", {Name = "SakuraBGDim", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = bgColor,
            BackgroundTransparency = Config.Misc.ImageDim, BorderSizePixel = 0, ZIndex = -3}, main)
        Round(dim, Config.Misc.Corner)
    end
    X.BuildStars(main)
end

-- значок слева от названия: Sakura = белый квадрат с розовым «Sak», Space = чёрный с фиолетовым «Sak»
function X.UpdateLogo()
    local sp = Config.Misc.MenuMode == "space"
    local function paint(lg)
        if not lg or not lg.frame.Parent then return end
        lg.frame.BackgroundColor3 = sp and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
        lg.text.TextColor3 = sp and Color3.fromRGB(165, 105, 255) or Color3.fromRGB(255, 102, 178)
        lg.stroke.Color = sp and Color3.fromRGB(110, 60, 200) or Color3.fromRGB(255, 190, 220)
    end
    paint(X.logo)
    paint(X.menuLogo)
end

function X.ApplyImage()
    pcall(function()
        if mainFrame and mainFrame.Parent then X.BuildBG(mainFrame) end
    end)
end

function X.SetCorner(r)
    Config.Misc.Corner = r
    local function set(c) if c and c.Parent then c.CornerRadius = UDim.new(0, r) end end
    set(X.cornerMain) set(X.cornerTitle)
    if mainFrame then
        for _, n in ipairs({"SakuraBG", "SakuraBGDim"}) do
            local o = mainFrame:FindFirstChild(n)
            set(o and o:FindFirstChildOfClass("UICorner"))
        end
    end
    MarkDirty()
end

function X.SetMode(mode)
    Config.Misc.MenuMode = mode
    local want = (mode == "space") and "Space" or "Sakura"
    for i, th in ipairs(Themes) do
        if th[1] == want then themeIdx = i end
    end
    uiColorIndex, customAccent = 0, nil
    bgColor = Themes[themeIdx][3]
    if not Config.Visuals.RainbowUI then uiColor = BaseAccent() end
    ApplyTheme()
    X.UpdateLogo()
    X.ApplyImage()
    if mainFrame then X.StartFX(mainFrame) end
    MarkDirty()
    Toast(mode == "space" and "🌌 Режим Space" or "🌸 Режим Sakura")
end

function X.LoadImage(url, force, key)
    key = key or Config.Misc.MenuMode
    X.imgStatus = "⏳ Загрузка картинки..."
    task.spawn(function()
        local gca = getcustomasset or getsynasset
        if not (writefile and isfile and gca) then
            X.imgStatus = "⚠️ Executor не поддерживает картинки (нужны writefile и getcustomasset)"
            return
        end
        local ok, err = pcall(function()
            local base = "Sakura_img_" .. (tostring(url):gsub("[^%w]", "")):sub(-40)
            if force and delfile then
                for _, ext in ipairs({".png", ".jpg"}) do
                    if isfile(base .. ext) then delfile(base .. ext) end
                end
            end
            local file
            if isfile(base .. ".png") then file = base .. ".png"
            elseif isfile(base .. ".jpg") then file = base .. ".jpg"
            else
                local body = game:HttpGet(url)
                if type(body) ~= "string" or #body < 100 then error("пустой ответ по ссылке") end
                local isPng = body:sub(2, 4) == "PNG"
                local isJpg = body:sub(1, 3) == "\255\216\255"
                if not (isPng or isJpg) then error("по ссылке не картинка (нужен PNG или JPG)") end
                file = base .. (isPng and ".png" or ".jpg")
                writefile(file, body)
            end
            X.imageAssets[key] = gca(file)
        end)
        if ok and X.imageAssets[key] then
            X.imgStatus = "✅ Картинка загружена"
            if key == Config.Misc.MenuMode then X.ApplyImage() end
        else
            X.imgStatus = "❌ " .. tostring(err)
        end
    end)
end

function X.PinList()
    local list = {}
    for id in (Config.Misc.Pins or ""):gmatch("[^,]+") do
        if F[id] then list[#list + 1] = id end
    end
    return list
end

function X.RebuildQuick()
    if X.quickGui then X.quickGui:Destroy() X.quickGui = nil end
    local pins = X.PinList()
    if #pins == 0 then return end
    local gui = New("ScreenGui", {Name = "SakuraQuick", ResetOnSpawn = false}, player.PlayerGui)
    local frame = New("Frame", {AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -8, .5, 0),
        Size = UDim2.new(0, 54, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1}, gui)
    New("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, frame)
    for _, id in ipairs(pins) do
        local f = F[id]
        local btn = New("TextButton", {Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.new(.13, .08, .2),
            BackgroundTransparency = 0.15, Text = (f.Label:match("^(%S+)") or id), TextColor3 = Color3.new(1, 1, 1),
            TextSize = 12, Font = Enum.Font.GothamBold, BorderSizePixel = 0,
            TextTruncate = Enum.TextTruncate.AtEnd}, frame)
        Round(btn, 8)
        local qs = New("UIStroke", {Thickness = 1.5, Color = uiColor, Transparency = 1}, btn)
        btn.MouseButton1Click:Connect(f.Toggle)
        AddRefresher(btn, function()
            local on = f.Tbl[f.Key]
            btn.BackgroundColor3 = on and uiColor or Color3.new(.13, .08, .2)
            qs.Color = uiColor
            qs.Transparency = on and 0.2 or 1
        end)
    end
    X.quickGui = gui
    SM.objects[#SM.objects + 1] = gui
    RefreshUI()
end

function X.TogglePin(id)
    local list, out, found = X.PinList(), {}, false
    for _, v in ipairs(list) do
        if v == id then found = true else out[#out + 1] = v end
    end
    if not found then
        if #list >= 6 then Toast("Максимум 6 закреплённых функций") return nil end
        out[#out + 1] = id
    end
    Config.Misc.Pins = table.concat(out, ",")
    X.RebuildQuick()
    MarkDirty()
    return not found
end

function X.LogEvent(text)
    X.joinLog[#X.joinLog + 1] = os.date("%H:%M:%S") .. "  " .. text
    if #X.joinLog > 25 then table.remove(X.joinLog, 1) end
end

-- Самотест: по очереди включает/выключает каждую функцию и ловит ошибки
function X.SelfTest(onStatus, onDone)
    if X.testing then return end
    X.testing = true
    task.spawn(function()
        local LogService = game:GetService("LogService")
        local results, bad = {}, 0
        local skip = {Notify = true, AutoSave = true, AutoRejoin = true, Freecam = true}
        Loading = true
        for i, f in ipairs(Features) do
            if not skip[f.Id] and Running then
                local was = f.Tbl[f.Key]
                local msgs = {}
                local conn = LogService.MessageOut:Connect(function(m, t)
                    if t == Enum.MessageType.MessageError then msgs[#msgs + 1] = m end
                end)
                local errBefore = #errLog
                if was then f.Set(false) end
                f.Set(true)
                local failed = not f.Tbl[f.Key]
                task.wait(0.35)
                f.Set(false)
                conn:Disconnect()
                if was then f.Set(true) end
                local problem
                if failed then problem = "не включилась"
                elseif #msgs > 0 then problem = tostring(msgs[1]):sub(1, 80)
                elseif #errLog > errBefore then problem = tostring(errLog[#errLog]):sub(1, 90) end
                if problem then
                    bad += 1
                    results[#results + 1] = "❌ " .. f.Label .. " — " .. problem
                else
                    results[#results + 1] = "✅ " .. f.Label
                end
                if onStatus then onStatus("Тест: " .. i .. "/" .. #Features) end
            end
        end
        Loading = false
        X.testing = false
        table.sort(results)
        X.testReport = "Результат теста (" .. (#results - bad) .. " ок, " .. bad .. " проблем):\n" .. table.concat(results, "\n")
        for _, r in ipairs(results) do
            if r:find("^❌") then errLog[#errLog + 1] = os.date("%H:%M:%S") .. "  ТЕСТ " .. r end
        end
        if onDone then onDone(X.testReport, bad) end
    end)
end

-- ============ ПРОВЕРКА ОБНОВЛЕНИЙ ============
local function CheckUpdate(silent)
    local ok, body = pcall(function() return game:HttpGet(UPDATE_URL .. "?t=" .. os.time()) end)
    if not ok or type(body) ~= "string" then
        if not silent then Toast("❌ Нет связи с GitHub") end
        return nil
    end
    local v = tonumber(body:match("SAKURA_VERSION%s*=%s*(%d+)"))
    if not v then
        if not silent then Toast("❌ Версия на GitHub не найдена") end
        return nil
    end
    if v > SAKURA_VERSION then
        X.latestBody = body
        Toast("🔔 Вышла версия " .. v .. "! НАСТР → Обновить")
        return v, body
    end
    if not silent then Toast("✅ Установлена последняя версия") end
    return v
end

-- ============ НАБЛЮДЕНИЕ ЗА ИГРОКОМ ============
local function StopSpectate()
    SM:RemoveConnection("Spectate")
    spectating = nil
    if hum then Camera.CameraSubject = hum end
end
local function SetSpectate(plr)
    if spectating == plr then StopSpectate() RefreshUI() return end
    spectating = plr
    SM:AddConnection("Spectate", RS.RenderStepped:Connect(function()
        local c = spectating and spectating.Character
        local h2 = c and c:FindFirstChildOfClass("Humanoid")
        if h2 then Camera.CameraSubject = h2 else StopSpectate() RefreshUI() end
    end))
    RefreshUI()
end

-- ============ UI ============
local mainGui
-- Возврат персонажа и камеры в обычное состояние
local function ResetCharacter()
    speedTouched, jumpTouched = false, false
    if hum and hum.Parent then
        hum.WalkSpeed = origChar.WalkSpeed
        hum.UseJumpPower = origChar.UseJumpPower
        hum.JumpPower = origChar.JumpPower
        hum.JumpHeight = origChar.JumpHeight
        hum.PlatformStand = false
        hum.AutoRotate = true
        hum.CameraOffset = Vector3.zero
        hum.BreakJointsOnDeath = true
        SetStunStates(true)
    end
    if root and root.Parent then
        root.Anchored = false
        root.AssemblyAngularVelocity = Vector3.zero
    end
    Camera.CameraType = Enum.CameraType.Custom
    Camera.FieldOfView = origFOV
    if hum then Camera.CameraSubject = hum end
    for _, plr in ipairs(Players:GetPlayers()) do
        local c = plr.Character
        if c then
            for _, o in ipairs(c:GetChildren()) do
                if o.Name:find("^ESP_") then SafeCall(function() o:Destroy() end) end
            end
        end
    end
end

-- Выключить всё и вернуть в норму, не закрывая меню
local function ResetAll()
    routePlaying = false
    StopSpectate()
    for _, f in ipairs(Features) do if f.Tbl[f.Key] and f.Tbl ~= Config.Misc then f.Set(false) end end
    ESP:Clear()
    ResetCharacter()
    Toast("🔄 Всё возвращено в норму")
end

local function Unload()
    if Config.Misc.AutoSave then SaveConfig() end
    Running = false
    StopSpectate()
    for _, f in ipairs(Features) do if f.Tbl[f.Key] then f.Set(false) end end
    ESP:Clear()
    ResetCharacter()
    SM:Cleanup()
    for _, g in ipairs(player.PlayerGui:GetChildren()) do
        if g.Name:find("^Sakura") or g.Name:find("^SAKURA") then SafeCall(function() g:Destroy() end) end
    end
    if mainGui then mainGui:Destroy() mainGui = nil end
    print("🌸 SAKURA V32 — выгружена, всё в норме")
end
env.SakuraUnload = Unload

-- ============ ОФОРМЛЕНИЕ МЕНЮ ============
function X.ApplyFont()
    local name = Config.Misc.FontName
    if name == "GothamBold" or not mainGui then return end
    local ok, font = pcall(function() return Enum.Font[name] end)
    if not ok or not font then return end
    for _, o in ipairs(mainGui:GetDescendants()) do
        if (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")) and not (X.logo and o == X.logo.text) then
            o.Font = font
        end
    end
end

function X.ApplyGlow()
    if X.glowTween then X.glowTween:Cancel() X.glowTween = nil end
    local st = X.mainStroke
    if not (st and st.Parent) then return end
    if Config.Misc.MenuGlow then
        X.glowTween = TS:Create(st, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Thickness = 5})
        X.glowTween:Play()
    else
        st.Thickness = 2
    end
end

function X.StartFX(main)
    X.fxToken = (X.fxToken or 0) + 1
    local my = X.fxToken
    local old = main and main:FindFirstChild("SakuraFX")
    if old then old:Destroy() end
    if not main or not Config.Misc.MenuFX then return end
    local box = New("Frame", {Name = "SakuraFX", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        ZIndex = -1, ClipsDescendants = true}, main)
    task.spawn(function()
        local rng = Random.new()
        while X.fxToken == my and Running and box.Parent do
            if not (mainGui and mainGui.Enabled) then
                task.wait(0.5)
            elseif Config.Misc.MenuMode == "space" then
                local sx, sy = rng:NextNumber(0.3, 1), rng:NextNumber(-0.1, 0.4)
                local line = New("Frame", {Size = UDim2.new(0, 60, 0, 2), Position = UDim2.new(sx, 0, sy, 0),
                    BackgroundColor3 = Color3.fromRGB(210, 180, 255), BorderSizePixel = 0, Rotation = 35, ZIndex = -1}, box)
                local tw = TS:Create(line, TweenInfo.new(0.9, Enum.EasingStyle.Quad),
                    {Position = UDim2.new(sx - 0.5, 0, sy + 0.6, 0), BackgroundTransparency = 1})
                tw:Play()
                tw.Completed:Connect(function() line:Destroy() end)
                task.wait(rng:NextNumber(2.5, 5))
            else
                local px = rng:NextNumber()
                local petal = New("TextLabel", {BackgroundTransparency = 1, Text = "🌸", TextSize = rng:NextInteger(10, 18),
                    TextTransparency = 0.45, Size = UDim2.new(0, 20, 0, 20), Position = UDim2.new(px, 0, 0, -20),
                    Rotation = rng:NextInteger(0, 360), ZIndex = -1}, box)
                local tw = TS:Create(petal, TweenInfo.new(rng:NextNumber(5, 8), Enum.EasingStyle.Sine),
                    {Position = UDim2.new(px + rng:NextNumber(-0.15, 0.15), 0, 1, 20), Rotation = rng:NextInteger(0, 360)})
                tw:Play()
                tw.Completed:Connect(function() petal:Destroy() end)
                task.wait(rng:NextNumber(0.9, 1.6))
            end
        end
    end)
end

Feature("MenuFX", "🌸 Частицы в меню", Config.Misc, "MenuFX", function() if mainFrame then X.StartFX(mainFrame) end end)
Feature("MenuGlow", "✨ Свечение рамки", Config.Misc, "MenuGlow", function() X.ApplyGlow() end)
Feature("MenuBlur", "🌫 Размытие фона", Config.Misc, "MenuBlur", function(on)
    if on then
        local blur = New("BlurEffect", {Name = "SakuraBlur", Size = 0}, Lighting)
        SM:AddConnection("MenuBlur", RS.Heartbeat:Connect(function()
            local goal = (mainGui and mainGui.Enabled) and 14 or 0
            blur.Size = blur.Size + (goal - blur.Size) * 0.2
        end))
    else
        SM:RemoveConnection("MenuBlur")
        local b = Lighting:FindFirstChild("SakuraBlur")
        if b then b:Destroy() end
    end
end)
Feature("RainbowTitle", "🌈 Радужное название", Config.Misc, "RainbowTitle", function(on)
    if on then
        local last = 0
        SM:AddConnection("RainbowTitle", RS.Heartbeat:Connect(function()
            if tick() - last < 0.05 or not (X.titleLbl and X.titleLbl.Parent) then return end
            last = tick()
            X.titleLbl.TextColor3 = RainbowColor(0.4)
        end))
    else
        SM:RemoveConnection("RainbowTitle")
        if X.titleLbl and X.titleLbl.Parent then X.titleLbl.TextColor3 = Color3.new(1, 1, 1) end
    end
end)

X.Desc = {
    Noclip = "Проходишь сквозь стены и объекты",
    InfJump = "Бесконечные прыжки в воздухе",
    Fly = "Полёт по направлению камеры (скорость в ГЛАВНАЯ)",
    Freecam = "Свободная камера, персонаж замирает",
    AntiAFK = "Не даёт выкинуть за бездействие",
    WaterWalk = "Ходьба по воде",
    NoFall = "Гасит урон от падения (клиентский)",
    AntiVoid = "Возвращает на безопасное место при падении в пустоту",
    Gravity = "Меняет гравитацию мира",
    AutoJump = "Прыгаешь без остановки, даже стоя на месте",
    AutoRun = "Бежишь вперёд без джойстика",
    WallClimb = "Упёрся в стену — поднимаешься вверх",
    BunnyHop = "Каждый прыжок разгоняет скорость",
    RouteLoop = "Записанный маршрут идёт по кругу",
    Invisible = "Скрывает твоё тело (виден только тебе)",
    GodMode = "Постоянно восстанавливает здоровье (клиентский)",
    NoKnockback = "Гасит отбрасывание и падение в рэгдолл",
    NoSound = "Выключает звуки в игре",
    NoStun = "Отключает оглушение и рэгдолл",
    SpeedHack = "Умножает скорость бега",
    Teleport = "Телепорт по тапу (ПК: Ctrl+клик)",
    AntiFling = "Защита от флинга других игроков",
    Hitbox = "Увеличивает хитбоксы игроков (клиентский)",
    XRay = "Делает объекты полупрозрачными",
    FullBright = "Максимальная яркость",
    NoFog = "Убирает туман",
    RainbowUI = "Цвет меню плавно меняется",
    Watermark = "Надпись SAKURA сверху экрана",
    NoShadows = "Отключает тени",
    NoCameraShake = "Убирает тряску камеры",
    NoRecoil = "Убирает отдачу оружия (зависит от игры)",
    NoSpread = "Убирает разброс оружия (зависит от игры)",
    ThirdPerson = "Вид от третьего лица",
    LowGraphics = "Простые материалы — больше FPS",
    NoEffects = "Отключает частицы и эффекты",
    FPS = "Счётчик FPS и пинга",
    CustomFOV = "Своё поле зрения камеры",
    Crosshair = "Перекрестие в центре экрана",
    TimeLock = "Фиксирует время суток",
    Radar = "Мини-радар с игроками вокруг",
    NoPostFX = "Убирает блюр, bloom и цветокоррекцию",
    RainbowBody = "Радужное тело (виден только тебе)",
    Trail = "Красивый след за персонажем",
    Flashlight = "Свет вокруг головы",
    Alert = "Звук и уведомление, когда враг рядом",
    StatsHUD = "Таймер, игроки рядом, пинг, FPS",
    ItemESP = "Подсвечивает предметы по части имени",
    ESP = "Подсветка игроков через стены",
    ESP_Box = "Рамка вокруг игрока",
    ESP_Lines = "Линии от экрана до игроков",
    ESP_Bones = "Скелет игрока линиями (без Drawing)",
    ESP_Tracers = "Трейсеры через Drawing (нужен Drawing)",
    ESP_Arrow = "Стрелки к игрокам вне экрана (Drawing)",
    ESP_HeadDot = "Точка на голове",
    ESP_Glow = "Неоновое свечение тел",
    ESP_Chams = "Плотная заливка через стены",
    ESP_Skeleton = "Скелет через Drawing",
    ESPTeam = "Не показывать свою команду",
    ESP_Name = "Показывать имена",
    ESP_Health = "Показывать здоровье",
    ESP_Dist = "Показывать расстояние",
    ESP_Friends = "Друзья зелёным цветом",
    Aimbot = "Автонаведение камеры на цель",
    Triggerbot = "Автоклик, когда цель в прицеле",
    AimLock = "Держится за цель, пока она в зоне",
    Prediction = "Упреждение по скорости цели",
    AimTeam = "Не целиться в свою команду",
    IgnoreWalls = "Целиться сквозь стены",
    TargetHUD = "Инфо о текущей цели аимбота",
    Notify = "Всплывающие уведомления сверху",
    AutoSave = "Сохранять настройки автоматически",
    AutoRejoin = "Перезаход после вылета",
    UISound = "Тихий звук при нажатии кнопок",
    UseImage = "Картинка на фоне меню (своя для каждого режима)",
    Spin = "Персонаж крутится вокруг своей оси",
    AutoClicker = "Автоклик предметом в руках (или мышью)",
    ClickDelete = "Прячет объект по тапу (ПК: Alt+клик), только у тебя",
    CoordsHUD = "Координаты и скорость, тап копирует",
    MenuFX = "Лепестки (Sakura) или падающие звёзды (Space) в меню",
    MenuGlow = "Пульсирующее свечение рамки меню",
    MenuBlur = "Размывает игру за меню, пока оно открыто",
    RainbowTitle = "Название меню переливается",
    Petals = "Лепестки (или снег) падают вокруг тебя",
    Aura = "Светящийся контур вокруг твоего персонажа",
    TimeFlow = "Время суток течёт быстро",
    Compass = "Компас с направлением камеры",
    ShowInvisible = "Показывает невидимые стены (только у тебя)",
    Invisicam = "Камера видит персонажа сквозь стены",
    FarZoom = "Можно отдалять камеру очень далеко",
    HideCoreGui = "Скрывает интерфейс Roblox — для скриншотов",
    SprintBtn = "Кнопка на экране: зажми — бежишь быстрее",
    Freeze = "Замораживает персонажа на месте",
    NoTextures = "Прячет текстуры и наклейки — больше FPS",
    ColorGrade = "Цветокоррекция: яркий, ч/б, тёплый, холодный, закат",
    FpsCap = "Лимит или снятие лимита FPS (нужен setfpscap)",
    EnemyCount = "Сколько врагов жив и как далеко ближайший",
    ESP_Tool = "Показывает оружие в руках у игрока",
    ESP_Arrows = "Стрелки к игрокам вне экрана (без Drawing)",
    ESP_Outline = "Только контур без заливки",
    ESP_VisCheck = "Игроки без стен на пути подсвечиваются жёлтым",
    ESP_Speed = "Скорость цели рядом с расстоянием",
    AimLine = "Линия от центра экрана к цели аимбота",
    AimHold = "Аим работает, только пока держишь кнопку Aim",
    AimFF = "Не целиться в игроков с ForceField",
    AimNeedTool = "Аим только когда в руках предмет",
    AimShowFOV = "Показывать круг FOV",
    DashBtn = "Кнопка рывка вперёд",
    DoubleJump = "Второй прыжок в воздухе",
    Glide = "Зажми прыжок в падении — медленно планируешь",
    SpeedFOV = "FOV растёт вместе со скоростью",
    Follow = "Персонаж идёт к ближайшему игроку",
    NightVision = "Зелёное ночное зрение",
    Rain = "Дождь вокруг камеры",
    Vignette = "Затемнение по краям экрана",
}

function X.Click()
    SafeCall(function()
        local snd = New("Sound", {SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25}, WS)
        snd:Play()
        game:GetService("Debris"):AddItem(snd, 1.5)
    end)
end

local TL
do
    local EN = {
        ["ГЛАВНАЯ"] = "MAIN", ["УЛЬТРА"] = "ULTRA", ["ВИЗУАЛ"] = "VISUAL", ["ИГРОКИ"] = "PLAYERS", ["НАСТР"] = "SETTINGS",
        ["🦘 Автопрыжок"] = "🦘 Auto Jump", ["🏃 Бег без остановки"] = "🏃 Auto Run", ["🔁 Повтор маршрута"] = "🔁 Loop Route",
        ["🪐 Гравитация"] = "🪐 Gravity", ["⚡ Волчек (X)"] = "⚡ Speed Hack (X)", ["🛡 Анти-флинг"] = "🛡 Anti-Fling",
        ["🌈 Радужный UI"] = "🌈 Rainbow UI", ["🔔 Сигнал о врагах"] = "🔔 Enemy Alert", ["📊 Статистика"] = "📊 Stats HUD",
        ["✨ Без пост-эффектов"] = "✨ No Post-FX", ["🌈 Радужное тело"] = "🌈 Rainbow Body", ["💫 След"] = "💫 Trail",
        ["💡 Фонарик"] = "💡 Flashlight", ["📡 Радар"] = "📡 Radar", ["➕ Прицел"] = "➕ Crosshair",
        ["🕐 Фикс. время"] = "🕐 Lock Time", ["🔁 Авто-реджойн"] = "🔁 Auto Rejoin", ["📋 Инфо о цели"] = "📋 Target Info",
        ["📏 Линии"] = "📏 Lines", ["Имя"] = "Name", ["Здоровье"] = "Health", ["Дистанция"] = "Distance",
        ["Друзья (зелёные)"] = "Friends (green)", ["🔔 Уведомления"] = "🔔 Notifications", ["💾 Автосохранение"] = "💾 Autosave",
        ["🦴 Скелет (GUI)"] = "🦴 Skeleton", ["🧗 Лазание по стенам"] = "🧗 Wall Climb", ["🔍 ESP предметов"] = "🔍 Item ESP",
        ["⚙️ ПЕРЕКЛЮЧАТЕЛИ"] = "⚙️ TOGGLES", ["🎨 Свой цвет ESP (RGB)"] = "🎨 Custom ESP color (RGB)",
        ["🎯 НАСТРОЙКИ AIMBOT"] = "🎯 AIMBOT SETTINGS", ["📍 ТОЧКИ И СЕРВЕР"] = "📍 WAYPOINTS & SERVER",
        ["🛤 МАРШРУТ (запись и повтор)"] = "🛤 ROUTE (record & replay)", ["👥 Игроки"] = "👥 Players", ["🎨 ТЕМА"] = "🎨 THEME",
        ["🎨 Свой цвет акцента (RGB)"] = "🎨 Custom accent (RGB)", ["💾 ПРОФИЛЬ (эта игра)"] = "💾 PROFILE (this game)",
        ["🧪 ДИАГНОСТИКА"] = "🧪 DIAGNOSTICS", ["📰 ЧТО НОВОГО"] = "📰 WHAT'S NEW",
        ["🪟 РАЗМЕР И ПОЛОЖЕНИЕ МЕНЮ"] = "🪟 MENU SIZE & POSITION", ["⌨ ГОРЯЧИЕ КЛАВИШИ (ПК)"] = "⌨ HOTKEYS (PC)",
        ["📤 ЭКСПОРТ / ИМПОРТ НАСТРОЕК"] = "📤 EXPORT / IMPORT", ["📝 БЛОКНОТ"] = "📝 NOTES",
        ["🔍 ESP предметов (часть имени объекта)"] = "🔍 Item ESP (part of object name)",
        ["🪽 Скорость полёта"] = "🪽 Fly speed", ["🎥 Скорость Freecam"] = "🎥 Freecam speed",
        ["🪐 Значение гравитации"] = "🪐 Gravity value", ["📏 Макс. дистанция"] = "📏 Max distance",
        ["📏 Мин. дистанция"] = "📏 Min distance", ["🎨 Прозрачность заливки"] = "🎨 Fill transparency",
        ["👥 Макс. игроков (0 = все)"] = "👥 Max players (0 = all)", ["🌈 Радиус цвета (по дист.)"] = "🌈 Color range",
        ["📏 Толщина линий"] = "📏 Line thickness", ["🎯 Плавность"] = "🎯 Smoothness", ["🔭 Значение FOV"] = "🔭 FOV value",
        ["🕐 Время суток"] = "🕐 Time of day", ["📡 Радиус радара"] = "📡 Radar range", ["🔔 Дистанция сигнала"] = "🔔 Alert distance",
        ["🪟 Прозрачность окна"] = "🪟 Window transparency", ["🏃 Скорость"] = "🏃 Speed", ["🦘 Прыжок"] = "🦘 Jump",
        ["🚀 Скорость снаряда (0 = выкл)"] = "🚀 Projectile speed (0 = off)",
        ["🌀 Скорость телепорта (0 = мгновенно)"] = "🌀 Teleport speed (0 = instant)",
        ["♻️ Респавн на месте"] = "♻️ Respawn here", ["🔁 Реджойн"] = "🔁 Rejoin", ["🆕 Др. сервер"] = "🆕 Other server",
        ["⏺ Запись"] = "⏺ Record", ["▶ Играть"] = "▶ Play", ["🗑 Очистить"] = "🗑 Clear", ["💾 Сохранить"] = "💾 Save",
        ["📂 Загрузить"] = "📂 Load", ["🗑 Удалить"] = "🗑 Delete", ["🔄 Вернуть всё в норму"] = "🔄 Reset everything",
        ["⏏ Выгрузить скрипт (End)"] = "⏏ Unload script (End)", ["📋 Копировать лог ошибок"] = "📋 Copy error log",
        ["Компакт"] = "Compact", ["Обычный"] = "Normal", ["Крупный"] = "Large", ["⬅ Лево"] = "⬅ Left",
        ["⏺ Центр"] = "⏺ Center", ["➡ Право"] = "➡ Right", ["📤 Экспорт"] = "📤 Export", ["📥 Импорт"] = "📥 Import",
        ["🧪 Тест всех функций"] = "🧪 Test all features", ["🔊 Звуки меню"] = "🔊 Menu sounds", ["🖼 Картинка-фон"] = "🖼 Background image", ["🌌 РЕЖИМ МЕНЮ"] = "🌌 MENU MODE", ["🌫 Размытие фона"] = "🌫 Menu blur", ["✨ Свечение рамки"] = "✨ Border glow",
        ["🌸 Частицы в меню"] = "🌸 Menu particles", ["🌈 Радужное название"] = "🌈 Rainbow title", ["🌸 Лепестки вокруг"] = "🌸 Falling petals",
        ["💠 Аура"] = "💠 Aura", ["🕑 Бег времени"] = "🕑 Time flow", ["🧭 Компас"] = "🧭 Compass", ["🧱 Невидимые стены"] = "🧱 Invisible walls",
        ["👓 Камера сквозь стены"] = "👓 Camera through walls", ["🔭 Дальний зум"] = "🔭 Far zoom", ["📸 Без интерфейса Roblox"] = "📸 Hide Roblox UI",
        ["🏃 Кнопка спринта"] = "🏃 Sprint button", ["✨ ВНЕШНИЙ ВИД МЕНЮ"] = "✨ MENU LOOK", ["🔲 Скругление углов"] = "🔲 Corner radius",
        ["🕑 Скорость времени (ч/мин)"] = "🕑 Time speed (h/min)", ["🏃 Множитель спринта"] = "🏃 Sprint multiplier", ["🖥 Сервер"] = "🖥 Server",
        ["🕘 Журнал входов"] = "🕘 Join log", ["🧊 Заморозка"] = "🧊 Freeze", ["🧹 Без текстур"] = "🧹 No textures",
        ["🎨 Цветокоррекция"] = "🎨 Color grade", ["🎞 Лимит FPS"] = "🎞 FPS cap", ["🎞 Значение лимита FPS"] = "🎞 FPS cap value",
        ["⚡ Пресет: больше FPS"] = "⚡ Preset: more FPS", ["🧼 Выключить визуалы"] = "🧼 Turn off visuals",
        ["↩ Назад после ТП"] = "↩ Back after TP", ["🔢 Счётчик врагов"] = "🔢 Enemy counter", ["🔧 Оружие в руках"] = "🔧 Held weapon",
        ["🧭 Стрелки (GUI)"] = "🧭 Arrows (GUI)", ["▭ Только контур"] = "▭ Outline only", ["👁 Видимых — жёлтым"] = "👁 Visible = yellow",
        ["💨 Скорость цели"] = "💨 Target speed", ["〰 Линия к цели"] = "〰 Line to target", ["🖐 Аим только при зажатии"] = "🖐 Aim on hold",
        ["🛡 Игнор ForceField"] = "🛡 Ignore ForceField", ["🔧 Аим только с оружием"] = "🔧 Aim only with tool", ["⭕ Круг FOV"] = "⭕ FOV circle",
        ["💨 Рывок (кнопка)"] = "💨 Dash button", ["⏫ Двойной прыжок"] = "⏫ Double jump", ["🪂 Планирование"] = "🪂 Glide",
        ["🌀 FOV от скорости"] = "🌀 Speed FOV", ["🚶 Следовать за игроком"] = "🚶 Follow player", ["🌙 Ночное зрение"] = "🌙 Night vision",
        ["🌧 Дождь"] = "🌧 Rain", ["🌑 Виньетка"] = "🌑 Vignette", ["🔤 Размер имени"] = "🔤 Name size", ["💨 Сила рывка"] = "💨 Dash power",
        ["📏 Дальность аима (0 = любая)"] = "📏 Aim range (0 = any)", ["🎲 Дрожание прицела"] = "🎲 Aim jitter", ["↕ Смещение прицела"] = "↕ Aim offset",
        ["⭕ Прозрачность круга FOV"] = "⭕ FOV circle opacity", ["⏱ Задержка триггербота"] = "⏱ Triggerbot delay", ["➕ Размер прицела"] = "➕ Crosshair size", ["🖱 Автоклик"] = "🖱 Auto Clicker", ["🌀 Вращение"] = "🌀 Spin", ["📍 Координаты"] = "📍 Coordinates", ["🗑 Клик-удаление"] = "🗑 Click Delete", ["🖱 Кликов в секунду"] = "🖱 Clicks per second", ["🌀 Скорость вращения"] = "🌀 Spin speed", ["⬇ Загрузить / обновить"] = "⬇ Download / refresh", ["🖼 Затемнение картинки"] = "🖼 Image dimming", ["🖼 КАРТИНКА (фон меню)"] = "🖼 IMAGE (menu background)", ["🧹 Очистить быструю панель"] = "🧹 Clear quick panel",
    }
    TL = function(s)
        if Config.Misc.Lang ~= "en" or type(s) ~= "string" then return s end
        if EN[s] then return EN[s] end
        local head, tail = s:match("^(.-): (.*)$")
        if head and EN[head] then return EN[head] .. ": " .. tail end
        return s
    end
end

-- Анимация кнопки: наведение, «вдавливание» при нажатии с пружинкой и вспышка при клике.
-- Кнопка должна иметь AnchorPoint (0.5, 0.5), чтобы масштабироваться от центра.
local TW_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TW_BOUNCE = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local function Animate(btn, corner)
    local sc = New("UIScale", {Scale = 1}, btn)
    local hover = false
    btn.MouseEnter:Connect(function() hover = true TS:Create(sc, TW_FAST, {Scale = 1.05}):Play() end)
    btn.MouseLeave:Connect(function() hover = false TS:Create(sc, TW_BOUNCE, {Scale = 1}):Play() end)
    btn.MouseButton1Down:Connect(function() TS:Create(sc, TW_FAST, {Scale = 0.9}):Play() end)
    btn.MouseButton1Up:Connect(function() TS:Create(sc, TW_BOUNCE, {Scale = hover and 1.05 or 1}):Play() end)
    btn.MouseButton1Click:Connect(function()
        if Config.Misc.UISound then X.Click() end
        local fl = New("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 20}, btn)
        Round(fl, corner or 8)
        local tw = TS:Create(fl, TweenInfo.new(0.35), {BackgroundTransparency = 1})
        tw.Completed:Connect(function() fl:Destroy() end)
        tw:Play()
    end)
end

local function Button(parent, text, size, pos)
    local holder = New("Frame", {Size = size, Position = pos or UDim2.new(), BackgroundTransparency = 1}, parent)
    local b = New("TextButton", {Size = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(.5, .5),
        Position = UDim2.new(.5, 0, .5, 0), BackgroundColor3 = uiColor, BackgroundTransparency = 0.3, Text = TL(text),
        TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = Enum.Font.GothamBold, BorderSizePixel = 0,
        TextWrapped = true, AutoButtonColor = false}, holder)
    Round(b, 6)
    Themed(b, "BackgroundColor3")
    Animate(b, 6)
    return b
end

local function CreateUI()
    local vp = Camera.ViewportSize
    local w, h = math.min(420, vp.X - 20), math.min(520, vp.Y - 20)
    mainGui = New("ScreenGui", {Name = "SAKURA_V20", ResetOnSpawn = false}, player.PlayerGui)

    local main = New("Frame", {Size = UDim2.new(0, w, 0, h), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundColor3 = bgColor, BackgroundTransparency = uiAlpha,
        BorderSizePixel = 0, ClipsDescendants = true}, mainGui)
    X.cornerMain = Round(main, Config.Misc.Corner)
    mainFrame = main
    local mainStroke = New("UIStroke", {Color = uiColor, Thickness = 2, Transparency = 0.1}, main)
    X.mainStroke = mainStroke
    Themed(mainStroke, "Color")
    local strokeGrad = New("UIGradient", {Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(0.5, Color3.new(.4, .4, .5)), ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1))}),
        Rotation = 0}, mainStroke)
    TS:Create(strokeGrad, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {Rotation = 360}):Play()
    New("UIGradient", {Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(.55, .55, .65)), Rotation = 90}, main)
    local mainScale = New("UIScale", {Scale = 0.85 * X.menuScale}, main)
    X.BuildBG(main)

    local title = New("Frame", {Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = uiColor,
        BackgroundTransparency = 0.35, BorderSizePixel = 0}, main)
    X.cornerTitle = Round(title, Config.Misc.Corner)
    Themed(title, "BackgroundColor3")
    New("UIGradient", {Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(.6, .6, .7)), Rotation = 0}, title)
    local logo = New("Frame", {Size = UDim2.new(0, 34, 0, 34), Position = UDim2.new(0, 9, 0, 5),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, title)
    Round(logo, 9)
    local logoStroke = New("UIStroke", {Thickness = 1.5, Color = Color3.fromRGB(255, 190, 220)}, logo)
    local logoText = New("TextLabel", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "Sak",
        TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 102, 178)}, logo)
    X.logo = {frame = logo, text = logoText, stroke = logoStroke}
    X.UpdateLogo()
    X.titleLbl = New("TextLabel", {Size = UDim2.new(0.55, 0, 0, 24), Position = UDim2.new(0, 50, 0, 4), BackgroundTransparency = 1,
        Text = "SAKURA", TextColor3 = Color3.new(1, 1, 1), TextSize = 17, Font = Enum.Font.GothamBlack,
        TextXAlignment = Enum.TextXAlignment.Left}, title)
    local titleTab = New("TextLabel", {Size = UDim2.new(0.55, 0, 0, 14), Position = UDim2.new(0, 50, 0, 27),
        BackgroundTransparency = 1, Text = "V32 · " .. TL("ГЛАВНАЯ"), TextColor3 = Color3.new(1, .92, .96), TextTransparency = 0.15,
        TextSize = 10, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left}, title)

    -- перетаскивание
    local dragging, dragStart, startPos
    title.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, i.Position, main.Position
            i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    SM:AddConnection("Drag", UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))

    local toggleBtn = New("TextButton", {Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(1, -51, 0.5, 0), AnchorPoint = Vector2.new(.5, .5),
        BackgroundColor3 = Color3.new(.2, .6, 1), Text = "▼", TextColor3 = Color3.new(1, 1, 1), TextSize = 14,
        Font = Enum.Font.GothamBold, BorderSizePixel = 0}, title)
    Round(toggleBtn, 6)
    Animate(toggleBtn, 6)
    local closeBtn = New("TextButton", {Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(1, -18, 0.5, 0), AnchorPoint = Vector2.new(.5, .5),
        BackgroundColor3 = Color3.fromRGB(255, 70, 100), Text = "✕", TextColor3 = Color3.new(1, 1, 1), TextSize = 14,
        Font = Enum.Font.GothamBold, BorderSizePixel = 0}, title)
    Round(closeBtn, 6)
    Animate(closeBtn, 6)
    closeBtn.MouseButton1Click:Connect(Unload)

    local content = New("Frame", {Size = UDim2.new(1, 0, 1, -44), Position = UDim2.new(0, 0, 0, 44),
        BackgroundTransparency = 1, ClipsDescendants = true}, main)
    local collapsed = false
    toggleBtn.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        local newH = collapsed and 44 or h
        local curH = main.Size.Y.Offset
        local pos = main.Position
        TS:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Size = UDim2.new(0, w, 0, newH),
            Position = UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset + (newH - curH) / 2)}):Play()
        toggleBtn.Text = collapsed and "▲" or "▼"
    end)

    -- вкладки
    local tabNames = {"ГЛАВНАЯ", "ESP", "AIM", "УЛЬТРА", "ВИЗУАЛ", "ИГРОКИ", "НАСТР"}
    local tabIcons = {"🏠", "👁", "🎯", "🔥", "🌈", "👥", "⚙️"}
    local searchBox, SwitchTab, currentTab = nil, nil, "ГЛАВНАЯ"
    local tabBar = New("Frame", {Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1}, content)
    searchBox = New("TextBox", {Size = UDim2.new(1, -12, 0, 26), Position = UDim2.new(0, 6, 0, 38),
        BackgroundColor3 = Color3.new(.1, .05, .15), BackgroundTransparency = 0.2, Text = "",
        PlaceholderText = "🔍 Поиск функций...", PlaceholderColor3 = Color3.new(.6, .5, .6),
        TextColor3 = Color3.new(1, 1, 1), TextSize = 12, Font = Enum.Font.Gotham, ClearTextOnFocus = false,
        BorderSizePixel = 0}, content)
    Round(searchBox, 8)
    New("UIStroke", {Color = Color3.new(.35, .25, .45), Thickness = 1}, searchBox)
    local area = New("Frame", {Size = UDim2.new(1, 0, 1, -70), Position = UDim2.new(0, 0, 0, 70),
        BackgroundTransparency = 1}, content)

    local pages, tabBtns = {}, {}
    local function Page(name)
        local sf = New("ScrollingFrame", {Size = UDim2.new(1, -10, 1, -10), Position = UDim2.new(0, 5, 0, 5),
            BackgroundTransparency = 1, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false}, area)
        New("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, sf)
        Themed(sf, "ScrollBarImageColor3")
        pages[name] = sf
        return sf
    end
    local function Header(parent, text)
        local l = New("TextLabel", {Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Text = TL(text),
            TextColor3 = uiColor, TextSize = 12, Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left}, parent)
        Themed(l, "TextColor3")
        local line = New("Frame", {Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = uiColor,
            BackgroundTransparency = 0.55, BorderSizePixel = 0}, l)
        Themed(line, "BackgroundColor3")
        return l
    end
    local function Grid(parent, cellW, cellH)
        local g = New("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1}, parent)
        New("UIGridLayout", {CellSize = UDim2.new(cellW or 0.5, -4, 0, cellH or 32), CellPadding = UDim2.new(0, 6, 0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder}, g)
        return g
    end
    local OFF_TRACK = Color3.new(.3, .3, .36)
    local function FeatureButton(parent, f)
        local holder = New("Frame", {BackgroundTransparency = 1}, parent)
        local b = New("TextButton", {Size = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(.5, .5),
            Position = UDim2.new(.5, 0, .5, 0), BackgroundColor3 = Color3.new(.13, .08, .2), BackgroundTransparency = 0.1,
            Text = "", AutoButtonColor = false, BorderSizePixel = 0}, holder)
        Round(b, 8)
        Animate(b, 8)
        local lbl = New("TextLabel", {Size = UDim2.new(1, -52, 1, 0), Position = UDim2.new(0, 8, 0, 0),
            BackgroundTransparency = 1, Text = TL(f.Label), TextColor3 = Color3.new(1, 1, 1), TextSize = 11,
            Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd}, b)
        local track = New("Frame", {Size = UDim2.new(0, 30, 0, 16), Position = UDim2.new(1, -38, 0.5, -8),
            BackgroundColor3 = OFF_TRACK, BorderSizePixel = 0}, b)
        Round(track, 8)
        local knob = New("Frame", {Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(0, 2, 0.5, -6),
            BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, track)
        Round(knob, 6)
        local cardStroke = New("UIStroke", {Thickness = 1.5, Color = uiColor, Transparency = 1}, b)
        local last
        local function refresh()
            local on = f.Tbl[f.Key] and true or false
            local col = on and uiColor or OFF_TRACK
            cardStroke.Color = uiColor
            cardStroke.Transparency = on and 0.35 or 1
            if on ~= last then
                local goal = {Position = on and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)}
                if last == nil then
                    knob.Position = goal.Position
                    track.BackgroundColor3 = col
                else
                    TS:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), goal):Play()
                    TS:Create(track, TweenInfo.new(0.18), {BackgroundColor3 = col}):Play()
                end
                lbl.TextColor3 = on and Color3.new(1, 1, 1) or Color3.new(.72, .68, .78)
                last = on
            elseif on then
                track.BackgroundColor3 = col
            end
        end
        AddRefresher(b, refresh)
        local holding, longDone, pressId = false, false, 0
        b.MouseButton1Down:Connect(function()
            holding, longDone = true, false
            pressId += 1
            local my = pressId
            task.delay(0.6, function()
                if holding and my == pressId then
                    longDone = true
                    local state = X.TogglePin(f.Id)
                    if state ~= nil then
                        Toast((state and "⭐ В быстрой панели: " or "☆ Откреплено: ") .. TL(f.Label)
                            .. "\n" .. (X.Desc[f.Id] or ""), 3)
                    end
                end
            end)
        end)
        b.MouseButton1Up:Connect(function() holding = false end)
        b.MouseLeave:Connect(function() holding = false end)
        b.MouseButton1Click:Connect(function()
            if longDone then longDone = false return end
            f.Toggle()
        end)
        refresh()
        return b
    end
    local function Stepper(parent, text, get, fmt, onStep)
        text = TL(text)
        local row = New("Frame", {Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1}, parent)
        local lbl = New("TextLabel", {Size = UDim2.new(0.55, 0, 1, 0), BackgroundTransparency = 1,
            TextColor3 = Color3.new(1, .8, .9), TextSize = 11, Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left, Text = text .. ": " .. fmt(get())}, row)
        local function step(txt, x, dir)
            Button(row, txt, UDim2.new(0, 36, 0, 26), UDim2.new(x, 0, 0, 1)).MouseButton1Click:Connect(function()
                onStep(dir) MarkDirty()
                lbl.Text = text .. ": " .. fmt(get())
            end)
        end
        step("−", 0.62, -1) step("+", 0.82, 1)
    end
    local function Presets(parent, text, values, onPick)
        text = TL(text)
        local lbl = Header(parent, text)
        local g = Grid(parent, 1 / #values, 26)
        for _, v in ipairs(values) do
            Button(g, tostring(v), UDim2.new()).MouseButton1Click:Connect(function()
                onPick(v) MarkDirty()
                lbl.Text = text:match("^[^:]+") .. ": " .. v
            end)
        end
    end

    -- ползунок (RGB и т.п.)
    local activeSlider, activeScroll
    SM:AddConnection("SliderDrag", UIS.InputChanged:Connect(function(i)
        if activeSlider and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            activeSlider(i.Position.X)
        end
    end))
    SM:AddConnection("SliderEnd", UIS.InputEnded:Connect(function(i)
        if activeSlider and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
            activeSlider = nil
            if activeScroll then activeScroll.ScrollingEnabled = true activeScroll = nil end
            MarkDirty()
        end
    end))
    local function Slider(parent, text, min, max, get, onSet)
        text = TL(text)
        local row = New("Frame", {Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1}, parent)
        local lbl = New("TextLabel", {Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1,
            TextColor3 = Color3.new(1, .85, .92), TextSize = 11, Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left}, row)
        local bar = New("Frame", {Position = UDim2.new(0, 8, 0, 24), Size = UDim2.new(1, -16, 0, 8),
            BackgroundColor3 = Color3.fromRGB(45, 28, 65), BorderSizePixel = 0, Active = true}, row)
        Round(bar, 4)
        local fill = New("Frame", {Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = uiColor, BorderSizePixel = 0}, bar)
        Round(fill, 4)
        Themed(fill, "BackgroundColor3")
        local knob = New("Frame", {AnchorPoint = Vector2.new(.5, .5), Size = UDim2.new(0, 16, 0, 16),
            Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, bar)
        Round(knob, 8)
        local function render()
            local v = get()
            local a = math.clamp((v - min) / (max - min), 0, 1)
            fill.Size = UDim2.new(a, 0, 1, 0)
            knob.Position = UDim2.new(a, 0, 0.5, 0)
            lbl.Text = text .. ": " .. math.floor(v + 0.5)
        end
        local function setFromX(x)
            local a = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
            onSet(min + (max - min) * a)
            render()
        end
        bar.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                activeSlider = setFromX
                activeScroll = bar:FindFirstAncestorOfClass("ScrollingFrame")
                if activeScroll then activeScroll.ScrollingEnabled = false end
                setFromX(i.Position.X)
            end
        end)
        render()
    end

    local function BuildModeButtons(parent)
        Header(parent, "🌌 РЕЖИМ МЕНЮ")
        local g = Grid(parent, 0.5, 36)
        local bSpace = Button(g, "🌌 Space", UDim2.new())
        local bSak = Button(g, "🌸 Sakura", UDim2.new())
        local function visual()
            local sp = Config.Misc.MenuMode == "space"
            bSpace.BackgroundTransparency = sp and 0.05 or 0.65
            bSak.BackgroundTransparency = sp and 0.65 or 0.05
        end
        AddRefresher(bSpace, visual)
        bSpace.MouseButton1Click:Connect(function() X.SetMode("space") end)
        bSak.MouseButton1Click:Connect(function() X.SetMode("sakura") end)
        visual()
    end

    -- ГЛАВНАЯ
    local pMain = Page("ГЛАВНАЯ")
    Presets(pMain, "🏃 Скорость: " .. M.Speed, {16, 50, 100, 150, 200, 300}, function(v)
        M.Speed = v speedTouched = true ApplySpeed()
    end)
    Presets(pMain, "🦘 Прыжок: " .. M.JumpPower, {50, 75, 100, 125, 150, 200}, function(v)
        M.JumpPower = v jumpTouched = true ApplyJump()
    end)
    Header(pMain, "⚙️ ПЕРЕКЛЮЧАТЕЛИ")
    local gm = Grid(pMain)
    for _, id in ipairs({"Noclip", "InfJump", "Fly", "Freecam", "AntiAFK", "WaterWalk", "NoFall", "AntiVoid", "Gravity", "AutoJump", "AutoRun", "WallClimb", "Spin", "Freeze", "SprintBtn", "DashBtn", "DoubleJump", "Glide", "SpeedFOV", "Follow", "BunnyHop"}) do
        FeatureButton(gm, F[id])
    end

    -- ESP
    local pEsp = Page("ESP")
    local g1 = Grid(pEsp, 1, 32)
    FeatureButton(g1, F.ESP)
    local g2 = Grid(pEsp)
    for _, id in ipairs({"ESP_Box", "ESP_Lines", "ESP_Bones", "ESP_Tracers", "ESP_Arrow", "ESP_HeadDot", "ESP_Glow", "ESP_Chams", "ESP_Skeleton", "ESPTeam",
        "ESP_Name", "ESP_Health", "ESP_Dist", "ESP_Friends",
        "ESP_Tool", "ESP_Arrows", "ESP_Outline", "ESP_VisCheck", "ESP_Speed", "EnemyCount"}) do
        FeatureButton(g2, F[id])
    end
    local espColors = {Color3.new(1, 0, 0), Color3.new(0, 1, 0), Color3.new(0, 0, 1), Color3.new(1, 1, 0),
        Color3.new(1, 0, 1), Color3.new(0, 1, 1), Color3.new(1, .5, 0), Color3.new(1, 1, 1)}
    local espIdx = 1
    local g3 = Grid(pEsp)
    local colorBtn = New("TextButton", {Text = "🎨 Цвет ESP", BackgroundColor3 = E.Color, TextColor3 = Color3.new(1, 1, 1),
        TextSize = 11, Font = Enum.Font.GothamBold, BorderSizePixel = 0}, g3)
    Round(colorBtn, 6)
    local modeNames = {[0] = "Режим: здоровье", [1] = "Режим: радуга 🌈", [2] = "Режим: фикс. цвет", [3] = "Режим: по дистанции", [4] = "Режим: цвет команды"}
    local modeBtn = Button(g3, modeNames[E.ColorMode], UDim2.new())
    colorBtn.MouseButton1Click:Connect(function()
        espIdx = espIdx % #espColors + 1
        E.Color = espColors[espIdx] E.ColorMode = 2
        colorBtn.BackgroundColor3 = E.Color
        modeBtn.Text = modeNames[2]
    end)
    modeBtn.MouseButton1Click:Connect(function()
        E.ColorMode = (E.ColorMode + 1) % 5
        modeBtn.Text = modeNames[E.ColorMode]
    end)

    Presets(pEsp, "📏 Макс. дистанция: " .. (E.MaxDistance >= 1e7 and "∞" or E.MaxDistance),
        {250, 500, 1000, 2500, "∞"}, function(v) E.MaxDistance = (v == "∞") and 100000000 or v end)
    Stepper(pEsp, "📏 Мин. дистанция", function() return E.MinDistance end, tostring, function(dir)
        E.MinDistance = math.clamp(E.MinDistance + dir * 25, 0, 1000)
    end)
    Stepper(pEsp, "🎨 Прозрачность заливки", function() return E.Transparency end,
        function(v) return string.format("%.1f", v) end, function(dir)
            E.Transparency = math.clamp(E.Transparency + dir * 0.1, 0, 1)
        end)

    Stepper(pEsp, "📏 Толщина линий", function() return E.LineThickness end, tostring, function(dir)
        E.LineThickness = math.clamp(E.LineThickness + dir, 1, 6)
    end)
    Stepper(pEsp, "👥 Макс. игроков (0 = все)", function() return E.MaxPlayers end, tostring, function(dir)
        E.MaxPlayers = math.clamp(E.MaxPlayers + dir, 0, 30)
    end)
    Stepper(pEsp, "🔤 Размер имени", function() return E.NameSize end, tostring, function(dir)
        E.NameSize = math.clamp(E.NameSize + dir, 8, 24)
    end)
    Stepper(pEsp, "🌈 Радиус цвета (по дист.)", function() return E.DistColorRange end, tostring, function(dir)
        E.DistColorRange = math.clamp(E.DistColorRange + dir * 50, 50, 2000)
    end)
    Header(pEsp, "🎨 Свой цвет ESP (RGB)")
    for idx, nm in ipairs({"R", "G", "B"}) do
        Slider(pEsp, nm, 0, 255, function()
            local c = E.Color
            return ({c.R, c.G, c.B})[idx] * 255
        end, function(v)
            local c = E.Color
            local t = {c.R, c.G, c.B}
            t[idx] = v / 255
            E.Color = Color3.new(t[1], t[2], t[3])
            E.ColorMode = 2
        end)
    end
    local originNames = {"Низ экрана", "Центр", "Верх экрана"}
    local originBtn = Button(pEsp, "Начало линий: " .. originNames[E.LineOrigin], UDim2.new(1, 0, 0, 28))
    originBtn.MouseButton1Click:Connect(function()
        E.LineOrigin = E.LineOrigin % 3 + 1
        originBtn.Text = "Начало линий: " .. originNames[E.LineOrigin]
        MarkDirty()
    end)

    -- AIM
    local pAim = Page("AIM")
    Header(pAim, "🎯 НАСТРОЙКИ AIMBOT")
    local ga = Grid(pAim)
    for _, id in ipairs({"Aimbot", "Triggerbot", "AimLock", "Prediction", "AimTeam", "IgnoreWalls", "TargetHUD",
        "AimHold", "AimFF", "AimNeedTool", "AimShowFOV", "AimLine"}) do
        FeatureButton(ga, F[id])
    end
    Stepper(pAim, "📏 FOV", function() return A.FOV end, tostring, function(dir)
        A.FOV = math.clamp(A.FOV + dir * 10, 50, 500) UpdateFOV()
    end)
    Stepper(pAim, "🎯 Плавность", function() return A.Smoothness end, function(v) return string.format("%.2f", v) end,
        function(dir) A.Smoothness = math.clamp(A.Smoothness + dir * 0.05, 0.05, 0.9) end)
    local modeAim = Button(pAim, "Цель: " .. A.Mode, UDim2.new(1, 0, 0, 28))
    modeAim.MouseButton1Click:Connect(function()
        local order = {"Head", "Torso", "Root", "Nearest"}
        local idx = 1
        for i2, n in ipairs(order) do if n == A.Mode then idx = i2 end end
        A.Mode = order[idx % #order + 1]
        modeAim.Text = "Цель: " .. A.Mode
    end)
    local prioNames = {"Ближе к прицелу", "Меньше HP", "Ближе по дистанции"}
    local prioBtn = Button(pAim, "Приоритет: " .. prioNames[A.Priority], UDim2.new(1, 0, 0, 28))
    prioBtn.MouseButton1Click:Connect(function()
        A.Priority = A.Priority % 3 + 1
        prioBtn.Text = "Приоритет: " .. prioNames[A.Priority]
        MarkDirty()
    end)
    Stepper(pAim, "🚀 Скорость снаряда (0 = выкл)", function() return A.ProjectileSpeed end, tostring, function(dir)
        A.ProjectileSpeed = math.clamp(A.ProjectileSpeed + dir * 25, 0, 1000)
    end)
    Stepper(pAim, "📏 Дальность аима (0 = любая)", function() return A.MaxDistance end, tostring, function(dir)
        A.MaxDistance = math.clamp(A.MaxDistance + dir * 50, 0, 3000)
    end)
    Stepper(pAim, "🎲 Дрожание прицела", function() return A.Jitter end,
        function(v) return string.format("%.2f", v) end, function(dir)
            A.Jitter = math.clamp(A.Jitter + dir * 0.25, 0, 3)
        end)
    Stepper(pAim, "↕ Смещение прицела", function() return A.AimOffsetY end,
        function(v) return string.format("%.2f", v) end, function(dir)
            A.AimOffsetY = math.clamp(A.AimOffsetY + dir * 0.25, -2, 2)
        end)
    Stepper(pAim, "⭕ Прозрачность круга FOV", function() return A.FovAlpha end,
        function(v) return string.format("%.1f", v) end, function(dir)
            A.FovAlpha = math.clamp(A.FovAlpha + dir * 0.1, 0, 1)
            UpdateFOV()
        end)
    Stepper(pAim, "⏱ Задержка триггербота", function() return A.TriggerDelay end,
        function(v) return string.format("%.2f", v) end, function(dir)
            A.TriggerDelay = math.clamp(A.TriggerDelay + dir * 0.02, 0.02, 0.5)
        end)

    -- УЛЬТРА
    local pUltra = Page("УЛЬТРА")
    Stepper(pUltra, "💀 Hitbox", function() return U.HitboxSize end, tostring, function(dir)
        U.HitboxSize = math.clamp(U.HitboxSize + dir * 0.5, 1, 10)
        if U.HitboxExtender then HitboxApply() end
    end)
    Stepper(pUltra, "🌀 Скорость телепорта (0 = мгновенно)", function() return U.TeleportSpeed end, tostring, function(dir)
        U.TeleportSpeed = math.clamp(U.TeleportSpeed + dir * 25, 0, 500)
    end)
    Stepper(pUltra, "🖱 Кликов в секунду", function() return U.CPS end, tostring, function(dir)
        U.CPS = math.clamp(U.CPS + dir, 1, 30)
    end)
    local gu = Grid(pUltra)
    for _, id in ipairs({"Hitbox", "Invisible", "GodMode", "NoKnockback", "NoSound", "NoStun", "SpeedHack", "Teleport", "AntiFling", "AutoClicker", "ClickDelete"}) do
        FeatureButton(gu, F[id])
    end

    -- ВИЗУАЛ
    local pVis = Page("ВИЗУАЛ")
    local gv = Grid(pVis)
    for _, id in ipairs({"XRay", "FullBright", "NoFog", "RainbowUI", "Watermark", "NoShadows", "NoCameraShake",
        "NoRecoil", "NoSpread", "ThirdPerson", "LowGraphics", "NoEffects", "FPS", "CustomFOV", "Crosshair", "TimeLock", "Radar", "NoPostFX", "RainbowBody", "Trail", "Flashlight", "Alert", "StatsHUD", "ItemESP", "CoordsHUD", "Petals", "Aura", "TimeFlow", "Compass", "ShowInvisible", "Invisicam", "FarZoom", "HideCoreGui", "NoTextures", "ColorGrade", "FpsCap", "NightVision", "Rain", "Vignette"}) do
        FeatureButton(gv, F[id])
    end

    -- доп. настройки ГЛАВНАЯ
    Stepper(pMain, "🪽 Скорость полёта", function() return M.FlySpeed end, tostring, function(dir)
        M.FlySpeed = math.clamp(M.FlySpeed + dir * 10, 10, 300)
    end)
    Stepper(pMain, "🎥 Скорость Freecam", function() return M.FreecamSpeed end, tostring, function(dir)
        M.FreecamSpeed = math.clamp(M.FreecamSpeed + dir * 10, 10, 300)
    end)
    Stepper(pMain, "🪐 Значение гравитации", function() return M.GravityValue end, tostring, function(dir)
        M.GravityValue = math.clamp(M.GravityValue + dir * 10, 10, 400)
    end)
    Stepper(pMain, "🌀 Скорость вращения", function() return M.SpinSpeed end, tostring, function(dir)
        M.SpinSpeed = math.clamp(M.SpinSpeed + dir * 5, 5, 60)
    end)
    Stepper(pMain, "🏃 Множитель спринта", function() return M.SprintMult end,
        function(v) return string.format("%.1f", v) end, function(dir)
            M.SprintMult = math.clamp(M.SprintMult + dir * 0.2, 1.2, 4)
        end)
    Stepper(pMain, "💨 Сила рывка", function() return M.DashPower end, tostring, function(dir)
        M.DashPower = math.clamp(M.DashPower + dir * 10, 30, 250)
    end)
    Header(pMain, "📍 ТОЧКИ И СЕРВЕР")
    local gw = Grid(pMain, 0.5, 28)
    for i = 1, 3 do
        local sb = Button(gw, "💾 Точка " .. i .. (waypoints[i] and " ✓" or ""), UDim2.new())
        sb.MouseButton1Click:Connect(function()
            if root then waypoints[i] = root.CFrame sb.Text = "💾 Точка " .. i .. " ✓" MarkDirty() end
        end)
        Button(gw, "🌀 К точке " .. i, UDim2.new()).MouseButton1Click:Connect(function()
            if root and waypoints[i] then GotoCFrame(waypoints[i]) end
        end)
    end
    Header(pMain, "🛤 МАРШРУТ (запись и повтор)")
    local gr = Grid(pMain, 1 / 3, 30)
    local bRec = Button(gr, "⏺ Запись", UDim2.new())
    local bPlay = Button(gr, "▶ Играть", UDim2.new())
    local bClr = Button(gr, "🗑 Очистить", UDim2.new())
    bRec.MouseButton1Click:Connect(function()
        RouteToggleRecord()
        bRec.Text = routeRec and "⏹ Стоп" or "⏺ Запись"
    end)
    bPlay.MouseButton1Click:Connect(RoutePlay)
    bClr.MouseButton1Click:Connect(function() route = {} Toast("🗑 Маршрут очищен") end)
    FeatureButton(Grid(pMain), F.RouteLoop)

    local gx = Grid(pMain, 1 / 3, 34)
    Button(gx, "♻️ Респавн на месте", UDim2.new()).MouseButton1Click:Connect(RespawnHere)
    Button(gx, "🔁 Реджойн", UDim2.new()).MouseButton1Click:Connect(function() Rejoin(true) end)
    Button(gx, "🆕 Др. сервер", UDim2.new()).MouseButton1Click:Connect(function() Rejoin(false) end)
    Button(gx, "↩ Назад после ТП", UDim2.new()).MouseButton1Click:Connect(function()
        if X.lastCF and root then
            local cf = X.lastCF
            X.lastCF = root.CFrame
            root.CFrame = cf
            Toast("↩ Вернул на прошлое место")
        else Toast("Пока некуда возвращаться") end
    end)

    -- доп. настройки ВИЗУАЛ
    local gtime = Grid(pVis, 0.25, 30)
    for _, tp in ipairs({{"🌅 6", 6}, {"☀️ 12", 12}, {"🌇 18", 18}, {"🌙 0", 0}}) do
        Button(gtime, tp[1], UDim2.new()).MouseButton1Click:Connect(function()
            V.TimeValue = tp[2]
            Lighting.ClockTime = tp[2]
            MarkDirty()
        end)
    end
    local gpre = Grid(pVis, 0.5, 32)
    Button(gpre, "⚡ Пресет: больше FPS", UDim2.new()).MouseButton1Click:Connect(function()
        for _, id in ipairs({"LowGraphics", "NoShadows", "NoEffects", "NoPostFX", "NoTextures"}) do F[id].Set(true) end
        Toast("⚡ Включён пресет «больше FPS»")
    end)
    Button(gpre, "🧼 Выключить визуалы", UDim2.new()).MouseButton1Click:Connect(function()
        for _, id in ipairs({"XRay", "FullBright", "NoFog", "NoShadows", "NoCameraShake", "LowGraphics", "NoEffects",
            "NoPostFX", "NoTextures", "ColorGrade", "Petals", "Aura", "Flashlight", "Trail", "RainbowBody",
            "ShowInvisible", "Crosshair", "TimeLock", "TimeFlow", "CustomFOV", "FarZoom", "Invisicam"}) do
            if F[id] then F[id].Set(false) end
        end
        Toast("🧼 Визуалы выключены")
    end)
    Stepper(pVis, "🔭 Значение FOV", function() return V.FOVValue end, tostring, function(dir)
        V.FOVValue = math.clamp(V.FOVValue + dir * 5, 30, 120)
    end)
    Stepper(pVis, "🕐 Время суток", function() return V.TimeValue end, tostring, function(dir)
        V.TimeValue = (V.TimeValue + dir) % 24
    end)
    Stepper(pVis, "📡 Радиус радара", function() return V.RadarRange end, tostring, function(dir)
        V.RadarRange = math.clamp(V.RadarRange + dir * 50, 50, 1000)
    end)
    Stepper(pVis, "🔔 Дистанция сигнала", function() return V.AlertRange end, tostring, function(dir)
        V.AlertRange = math.clamp(V.AlertRange + dir * 10, 10, 300)
    end)
    Stepper(pVis, "🕑 Скорость времени (ч/мин)", function() return V.TimeSpeed end, tostring, function(dir)
        V.TimeSpeed = math.clamp(V.TimeSpeed + dir * 5, 1, 120)
    end)
    Stepper(pVis, "🎞 Значение лимита FPS", function() return V.FpsCapValue end, tostring, function(dir)
        V.FpsCapValue = math.clamp(V.FpsCapValue + dir * 30, 30, 360)
        if V.FpsCap and setfpscap then setfpscap(V.FpsCapValue) end
    end)
    local gradeBtn = Button(pVis, "🎨 Стиль цвета: " .. X.gradeModes[V.GradeMode][1], UDim2.new(1, 0, 0, 28))
    gradeBtn.MouseButton1Click:Connect(function()
        V.GradeMode = V.GradeMode % #X.gradeModes + 1
        gradeBtn.Text = "🎨 Стиль цвета: " .. X.gradeModes[V.GradeMode][1]
        X.ApplyGrade()
        MarkDirty()
    end)
    local chNames = {"Крест", "Точка", "Кольцо", "Крест + точка"}
    local chBtn = Button(pVis, "➕ Стиль прицела: " .. chNames[V.CrosshairStyle], UDim2.new(1, 0, 0, 28))
    chBtn.MouseButton1Click:Connect(function()
        V.CrosshairStyle = V.CrosshairStyle % #chNames + 1
        chBtn.Text = "➕ Стиль прицела: " .. chNames[V.CrosshairStyle]
        X.BuildCrosshair()
        MarkDirty()
    end)
    Stepper(pVis, "➕ Размер прицела", function() return V.CrosshairSize end, tostring, function(dir)
        V.CrosshairSize = math.clamp(V.CrosshairSize + dir * 2, 8, 40)
        X.BuildCrosshair()
    end)
    Header(pVis, "🔍 ESP предметов (часть имени объекта)")
    local itemBox = New("TextBox", {Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Color3.new(.1, .05, .15),
        TextColor3 = Color3.new(1, 1, 1), Text = V.ItemFilter, PlaceholderText = "например: Coin", ClearTextOnFocus = false,
        TextSize = 12, Font = Enum.Font.Gotham, BorderSizePixel = 0}, pVis)
    Round(itemBox, 8)
    itemBox.FocusLost:Connect(function() V.ItemFilter = itemBox.Text X.itemLastScan = 0 MarkDirty() end)

    -- ИГРОКИ
    local pPl = Page("ИГРОКИ")
    local plHeader = Header(pPl, "👥 Игроки")
    local logHdr = Header(pPl, "🕘 Журнал входов")
    local logLbl = New("TextLabel", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.new(.8, .78, .9), TextSize = 10,
        Font = Enum.Font.Gotham, Text = ""}, pPl)
    logHdr.LayoutOrder, logLbl.LayoutOrder = 100000, 100001
    local srvHdr = Header(pPl, "🖥 Сервер")
    local srvLbl = New("TextLabel", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.new(.8, .78, .9), TextSize = 10,
        Font = Enum.Font.Gotham, Text = "PlaceId: " .. tostring(game.PlaceId) .. "\nJobId: " .. (game.JobId ~= "" and game.JobId or "—")}, pPl)
    local srvBtns = Grid(pPl, 0.5, 28)
    Button(srvBtns, "📋 JobId", UDim2.new()).MouseButton1Click:Connect(function()
        if setclipboard then setclipboard(game.JobId) Toast("📋 JobId скопирован") end
    end)
    Button(srvBtns, "📋 PlaceId", UDim2.new()).MouseButton1Click:Connect(function()
        if setclipboard then setclipboard(tostring(game.PlaceId)) Toast("📋 PlaceId скопирован") end
    end)
    srvHdr.LayoutOrder, srvLbl.LayoutOrder, srvBtns.LayoutOrder = 100002, 100003, 100004
    local plRows = {}
    local function RemoveRow(plr)
        if plRows[plr] then plRows[plr].frame:Destroy() plRows[plr] = nil end
    end
    local function AddRow(plr)
        if plr == player or plRows[plr] then return end
        local fr = New("Frame", {Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.new(.1, .05, .15),
            BackgroundTransparency = 0.3, BorderSizePixel = 0}, pPl)
        Round(fr, 6)
        New("TextLabel", {Size = UDim2.new(0.34, 0, 1, 0), Position = UDim2.new(0, 6, 0, 0), BackgroundTransparency = 1,
            Text = plr.DisplayName, TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd}, fr)
        local info = New("TextLabel", {Size = UDim2.new(0.22, 0, 1, 0), Position = UDim2.new(0.35, 0, 0, 0),
            BackgroundTransparency = 1, Text = "", TextColor3 = Color3.new(.8, .8, 1), TextSize = 10,
            Font = Enum.Font.Gotham}, fr)
        local function mini(txt, x)
            local b = Button(fr, txt, UDim2.new(0.12, 0, 0, 26), UDim2.new(x, 0, 0, 4))
            b.TextSize = 14
            return b
        end
        local bSpec, bTp, bFr = mini("👁", 0.58), mini("🌀", 0.71), mini("⭐", 0.84)
        AddRefresher(bSpec, function() bSpec.BackgroundColor3 = (spectating == plr) and ON_COLOR or uiColor end)
        AddRefresher(bFr, function() bFr.BackgroundColor3 = friends[plr.UserId] and ON_COLOR or uiColor end)
        bSpec.MouseButton1Click:Connect(function() SetSpectate(plr) end)
        bTp.MouseButton1Click:Connect(function()
            local c = plr.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if r and root then GotoCFrame(r.CFrame * CFrame.new(0, 0, 3)) end
        end)
        bFr.MouseButton1Click:Connect(function()
            friends[plr.UserId] = (not friends[plr.UserId]) or nil
            MarkDirty() RefreshUI()
        end)
        local lastTap = 0
        fr.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
                if tick() - lastTap < 0.35 then
                    local c = plr.Character
                    local r = c and c:FindFirstChild("HumanoidRootPart")
                    if r and root then GotoCFrame(r.CFrame * CFrame.new(0, 0, 3)) Toast("🌀 ТП к " .. plr.DisplayName) end
                end
                lastTap = tick()
            end
        end)
        plRows[plr] = {frame = fr, info = info}
    end
    local function UpdateRows()
        local n = 0
        for plr, row in pairs(plRows) do
            n += 1
            local c = plr.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            local h2 = c and c:FindFirstChildOfClass("Humanoid")
            if r and root and h2 then
                local d = (r.Position - root.Position).Magnitude
                row.info.Text = math.floor(d) .. "m\n❤" .. math.floor(h2.Health)
                row.frame.LayoutOrder = 100 + math.floor(d)
            else
                row.info.Text = "—"
                row.frame.LayoutOrder = 99999
            end
        end
        logLbl.Text = table.concat(X.joinLog, "\n", math.max(1, #X.joinLog - 11))
        plHeader.Text = "👥 Игроков: " .. n .. "   (👁 смотреть · 🌀 ТП · ⭐ друг · 2×тап = ТП)"
    end
    local lastPl = 0
    SM:AddConnection("PlayerList", RS.Heartbeat:Connect(function()
        if pPl.Visible and tick() - lastPl > 0.5 then lastPl = tick() UpdateRows() end
    end))
    SM:AddConnection("PL_Add", Players.PlayerAdded:Connect(AddRow))
    SM:AddConnection("PL_Rem", Players.PlayerRemoving:Connect(RemoveRow))
    for _, p in ipairs(Players:GetPlayers()) do AddRow(p) end

    local function RebuildMenu()
        local pos = mainFrame.Position
        if mainGui then mainGui:Destroy() mainGui = nil end
        CreateUI()
        if mainFrame then mainFrame.Position = pos end
    end

    -- НАСТРОЙКИ
    local pSet = Page("НАСТР")
    BuildModeButtons(pSet)
    Header(pSet, "🎨 ТЕМА")
    local gt = Grid(pSet, 1 / 3, 28)
    for i, th in ipairs(Themes) do
        if th[1] ~= "Space" and th[1] ~= "Sakura" then
            local b = New("TextButton", {Text = th[1], BackgroundColor3 = th[2], TextColor3 = Color3.new(0, 0, 0),
                TextSize = 11, Font = Enum.Font.GothamBold, BorderSizePixel = 0}, gt)
            Round(b, 6)
            b.MouseButton1Click:Connect(function()
                themeIdx, uiColorIndex, bgColor, customAccent = i, 0, th[3], nil
                if not V.RainbowUI then uiColor = BaseAccent() end
                ApplyTheme() MarkDirty()
            end)
        end
    end
    local accBtn = Button(pSet, "", UDim2.new(1, 0, 0, 28))
    local function accText()
        accBtn.Text = customAccent and "Акцент: свой цвет (нажми — сбросить)" or (uiColorIndex == 0 and "Акцент: цвет темы (нажми — сменить)" or ("Акцент: #" .. uiColorIndex))
    end
    accText()
    accBtn.MouseButton1Click:Connect(function()
        customAccent = nil
        uiColorIndex = (uiColorIndex + 1) % (#uiColors + 1)
        if not V.RainbowUI then uiColor = BaseAccent() end
        accText() ApplyTheme() MarkDirty()
    end)
    Stepper(pSet, "🪟 Прозрачность окна", function() return uiAlpha end,
        function(v) return string.format("%.1f", v) end, function(dir)
            uiAlpha = math.clamp(uiAlpha + dir * 0.1, 0, 0.9) ApplyTheme()
        end)
    Header(pSet, "🎨 Свой цвет акцента (RGB)")
    for idx, nm in ipairs({"R", "G", "B"}) do
        Slider(pSet, nm, 0, 255, function()
            local c = BaseAccent()
            return ({c.R, c.G, c.B})[idx] * 255
        end, function(v)
            local c = BaseAccent()
            local t = {c.R, c.G, c.B}
            t[idx] = v / 255
            customAccent = Color3.new(t[1], t[2], t[3])
            if not V.RainbowUI then uiColor = customAccent end
            ApplyTheme() accText()
        end)
    end
    local gs = Grid(pSet)
    for _, id in ipairs({"RainbowUI", "Notify", "AutoSave", "AutoRejoin", "UISound"}) do FeatureButton(gs, F[id]) end

    Header(pSet, "💾 ПРОФИЛЬ (эта игра)")
    local status = New("TextLabel", {Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = profileStatus,
        TextColor3 = Color3.new(.8, .9, 1), TextSize = 10, Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true}, pSet)
    local gsl = Grid(pSet, 1 / 3, 28)
    local slotBtns = {}
    for i = 1, 3 do
        local b = Button(gsl, "Профиль " .. i, UDim2.new())
        slotBtns[i] = b
        b.MouseButton1Click:Connect(function()
            profileSlot = i
            local exists = canFile and isfile(ProfilePath())
            profileStatus = "Профиль " .. i .. (exists and ": сохранён" or ": пусто")
            status.Text = profileStatus
            for j, bb in ipairs(slotBtns) do bb.BackgroundTransparency = (j == i) and 0.05 or 0.65 end
        end)
        b.BackgroundTransparency = (i == profileSlot) and 0.05 or 0.65
    end
    local gp = Grid(pSet, 1 / 3, 28)
    local bSave = Button(gp, "💾 Сохранить", UDim2.new())
    local bLoad = Button(gp, "📂 Загрузить", UDim2.new())
    local bDel = Button(gp, "🗑 Удалить", UDim2.new())
    bSave.MouseButton1Click:Connect(function()
        local ok, err = SaveConfig()
        profileStatus = ok and "✅ Сохранено" or ("❌ " .. tostring(err))
        status.Text = profileStatus
    end)
    bDel.MouseButton1Click:Connect(function()
        if canFile and delfile and isfile(ProfilePath()) then delfile(ProfilePath()) profileStatus = "🗑 Профиль удалён"
        else profileStatus = "❌ Нечего удалять" end
        status.Text = profileStatus
    end)
    bLoad.MouseButton1Click:Connect(function()
        local ok, err = LoadConfig()
        profileStatus = ok and "✅ Загружено" or ("❌ " .. tostring(err))
        status.Text = profileStatus
        if ok then
            local pos = mainFrame.Position
            task.defer(function()
                if mainGui then mainGui:Destroy() mainGui = nil end
                CreateUI()
                if mainFrame then mainFrame.Position = pos end
            end)
        end
    end)
    New("TextLabel", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        TextWrapped = true, TextColor3 = Color3.new(.82, .78, .9), TextSize = 10, Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        Text = "📌 Долгое нажатие на любую функцию закрепляет её в быстрой панели справа и показывает описание."}, pSet)
    Button(pSet, "🧹 Очистить быструю панель", UDim2.new(1, 0, 0, 28)).MouseButton1Click:Connect(function()
        Config.Misc.Pins = ""
        X.RebuildQuick()
        MarkDirty()
        Toast("🧹 Быстрая панель очищена")
    end)
    Header(pSet, "🪟 РАЗМЕР И ПОЛОЖЕНИЕ МЕНЮ")
    local gsz = Grid(pSet, 1 / 3, 28)
    for _, pr in ipairs({{"Компакт", 0.75}, {"Обычный", 1}, {"Крупный", 1.2}}) do
        Button(gsz, pr[1], UDim2.new()).MouseButton1Click:Connect(function()
            X.menuScale = pr[2]
            TS:Create(mainScale, TweenInfo.new(0.2), {Scale = X.menuScale}):Play()
            MarkDirty()
        end)
    end
    local gpos = Grid(pSet, 1 / 3, 28)
    for _, pp in ipairs({{"⬅ Лево", 0.25}, {"⏺ Центр", 0.5}, {"➡ Право", 0.75}}) do
        Button(gpos, pp[1], UDim2.new()).MouseButton1Click:Connect(function()
            TS:Create(main, TweenInfo.new(0.25), {Position = UDim2.new(pp[2], 0, 0.5, 0)}):Play()
        end)
    end
    Header(pSet, "✨ ВНЕШНИЙ ВИД МЕНЮ")
    Stepper(pSet, "🔲 Скругление углов", function() return Config.Misc.Corner end, tostring, function(dir)
        X.SetCorner(math.clamp(Config.Misc.Corner + dir * 2, 0, 30))
    end)
    local fontNames = {"GothamBold", "FredokaOne", "Ubuntu", "SourceSansBold", "Arcade", "Code", "Cartoon", "Antique"}
    local fontBtn = Button(pSet, "🔤 Шрифт: " .. Config.Misc.FontName .. " (нажми — сменить)", UDim2.new(1, 0, 0, 28))
    fontBtn.MouseButton1Click:Connect(function()
        local idx = 1
        for i, n in ipairs(fontNames) do if n == Config.Misc.FontName then idx = i end end
        Config.Misc.FontName = fontNames[idx % #fontNames + 1]
        MarkDirty()
        task.defer(RebuildMenu)
    end)
    local gfx = Grid(pSet, 0.5, 32)
    for _, id in ipairs({"MenuFX", "MenuGlow", "MenuBlur", "RainbowTitle"}) do FeatureButton(gfx, F[id]) end

    Header(pSet, "🖼 КАРТИНКА (фон меню)")
    local imgBox = New("TextBox", {Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Color3.new(.1, .05, .15),
        TextColor3 = Color3.new(1, 1, 1), Text = (Config.Misc.MenuMode == "space" and Config.Misc.SpaceUrl or Config.Misc.ImageUrl), PlaceholderText = "прямая ссылка на PNG или JPG",
        ClearTextOnFocus = false, TextSize = 10, Font = Enum.Font.Gotham, BorderSizePixel = 0}, pSet)
    Round(imgBox, 8)
    AddRefresher(imgBox, function()
        if not imgBox:IsFocused() then
            imgBox.Text = Config.Misc.MenuMode == "space" and Config.Misc.SpaceUrl or Config.Misc.ImageUrl
        end
    end)
    local imgStatus = New("TextLabel", {Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = X.imgStatus or "",
        TextColor3 = Color3.new(.8, .9, 1), TextSize = 10, Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true}, pSet)
    local gim = Grid(pSet, 0.5, 32)
    FeatureButton(gim, F.UseImage)
    Button(gim, "⬇ Загрузить / обновить", UDim2.new()).MouseButton1Click:Connect(function()
        local key = Config.Misc.MenuMode
        if key == "space" then Config.Misc.SpaceUrl = imgBox.Text else Config.Misc.ImageUrl = imgBox.Text end
        MarkDirty()
        X.LoadImage(imgBox.Text, true, key)
        task.spawn(function()
            for _ = 1, 24 do
                task.wait(0.5)
                imgStatus.Text = X.imgStatus or ""
                if X.imgStatus ~= "⏳ Загрузка картинки..." then break end
            end
        end)
    end)
    Stepper(pSet, "🖼 Затемнение картинки", function() return Config.Misc.ImageDim end,
        function(v) return string.format("%.1f", v) end, function(dir)
            Config.Misc.ImageDim = math.clamp(Config.Misc.ImageDim + dir * 0.1, 0, 0.9)
            X.BuildBG(mainFrame)
        end)
    local langBtn = Button(pSet, Config.Misc.Lang == "en" and "🌐 Language: English" or "🌐 Язык: Русский", UDim2.new(1, 0, 0, 28))
    langBtn.MouseButton1Click:Connect(function()
        Config.Misc.Lang = Config.Misc.Lang == "en" and "ru" or "en"
        MarkDirty()
        task.defer(RebuildMenu)
    end)

    Header(pSet, "⌨ ГОРЯЧИЕ КЛАВИШИ (ПК)")
    local gk = Grid(pSet, 0.5, 28)
    for _, name in ipairs({"Aimbot", "Triggerbot", "Noclip", "Fly", "Invisible", "GodMode", "BunnyHop", "SpeedHack", "Menu", "Unload"}) do
        local kb = Button(gk, "", UDim2.new())
        local function r() kb.Text = (X.Rebind == name) and (name .. ": нажми клавишу...") or (name .. ": " .. Config.Keys[name]) end
        AddRefresher(kb, r)
        kb.MouseButton1Click:Connect(function() X.Rebind = (X.Rebind == name) and nil or name RefreshUI() end)
        r()
    end

    Header(pSet, "📤 ЭКСПОРТ / ИМПОРТ НАСТРОЕК")
    local impBox = New("TextBox", {Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Color3.new(.1, .05, .15),
        TextColor3 = Color3.new(1, 1, 1), Text = "", PlaceholderText = "вставь сюда экспортированные настройки",
        ClearTextOnFocus = false, TextSize = 10, Font = Enum.Font.Gotham, BorderSizePixel = 0}, pSet)
    Round(impBox, 8)
    local gxi = Grid(pSet, 0.5, 28)
    Button(gxi, "📤 Экспорт", UDim2.new()).MouseButton1Click:Connect(function()
        local txt = Http:JSONEncode(BuildProfile())
        if setclipboard then setclipboard(txt) Toast("📤 Скопировано в буфер")
        else impBox.Text = txt Toast("Текст в поле — скопируй вручную") end
    end)
    Button(gxi, "📥 Импорт", UDim2.new()).MouseButton1Click:Connect(function()
        local ok, data = pcall(function() return Http:JSONDecode(impBox.Text) end)
        if ok and type(data) == "table" and data.values then
            ApplyProfile(data) MarkDirty() Toast("📥 Настройки импортированы")
            task.defer(RebuildMenu)
        else Toast("❌ Неверный формат") end
    end)

    Header(pSet, "🧪 ДИАГНОСТИКА")
    local caps = {
        {"Drawing: трейсеры, стрелки, скелет", hasDrawing},
        {"Файлы: сохранение профиля", canFile},
        {"mouse1click: Triggerbot", mouse1click ~= nil},
        {"setclipboard: копирование лога", setclipboard ~= nil},
    }
    local capText = {}
    for _, c in ipairs(caps) do capText[#capText + 1] = (c[2] and "✅ " or "❌ ") .. c[1] end
    New("TextLabel", {Size = UDim2.new(1, 0, 0, 70), BackgroundTransparency = 1, Text = table.concat(capText, "\n"),
        TextColor3 = Color3.new(.8, .9, 1), TextSize = 10, Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top}, pSet)
    Button(pSet, "📋 Копировать лог ошибок", UDim2.new(1, 0, 0, 28)).MouseButton1Click:Connect(function()
        local text = #errLog > 0 and table.concat(errLog, "\n") or "Ошибок нет"
        if setclipboard then setclipboard(text) Toast("📋 Скопировано (" .. #errLog .. ")")
        else print(text) Toast("Лог выведен в консоль (" .. #errLog .. ")") end
    end)
    local testLbl = New("TextLabel", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, TextWrapped = true, TextColor3 = Color3.new(.8, .9, 1), TextSize = 10,
        Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        Text = X.testReport}, pSet)
    local testBtn = Button(pSet, "🧪 Тест всех функций", UDim2.new(1, 0, 0, 28))
    testBtn.MouseButton1Click:Connect(function()
        X.SelfTest(function(st) testBtn.Text = st end, function(report, bad)
            testBtn.Text = TL("🧪 Тест всех функций")
            testLbl.Text = report
            if setclipboard then setclipboard(report) end
            Toast(bad == 0 and "✅ Все функции прошли тест" or ("⚠️ Проблем: " .. bad .. " (отчёт скопирован)"))
        end)
    end)
    local updBtn = Button(pSet, "🔄 Проверить обновления (v" .. SAKURA_VERSION .. ")", UDim2.new(1, 0, 0, 28))
    updBtn.MouseButton1Click:Connect(function()
        if X.latestBody then
            local f = loadstring(X.latestBody)
            if f then Toast("⬇ Обновляю...") task.spawn(f) end
            return
        end
        task.spawn(function()
            local v = CheckUpdate(false)
            if v and v > SAKURA_VERSION then updBtn.Text = "⬇ Обновить до v" .. v end
        end)
    end)
    Button(pSet, "🔄 Вернуть всё в норму", UDim2.new(1, 0, 0, 28)).MouseButton1Click:Connect(ResetAll)
    Button(pSet, "⏏ Выгрузить скрипт (End)", UDim2.new(1, 0, 0, 28)).MouseButton1Click:Connect(Unload)
    Header(pSet, "📝 БЛОКНОТ")
    local notes = New("TextBox", {Size = UDim2.new(1, 0, 0, 90), BackgroundColor3 = Color3.new(.1, .05, .15),
        TextColor3 = Color3.new(1, 1, 1), Text = Config.Misc.Notes or "", PlaceholderText = "Заметки (сохраняются в профиль)",
        MultiLine = true, TextWrapped = true, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, TextSize = 12, Font = Enum.Font.Gotham, BorderSizePixel = 0}, pSet)
    Round(notes, 8)
    notes.FocusLost:Connect(function() Config.Misc.Notes = notes.Text MarkDirty() end)
    Header(pSet, "📰 ЧТО НОВОГО")
    New("TextLabel", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        TextWrapped = true, TextColor3 = Color3.new(.82, .78, .9), TextSize = 10, Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        Text = "V32: загрузка не короче 6 сек (убирается сама через 10), много новых функций ESP / Aim / движения / визуалов.\nV31: новый загрузочный экран (значок Sak, вращающееся кольцо, этапы, подсказки), украшения меню, заморозка, цветокоррекция, лимит FPS, без текстур, пресеты, возврат после ТП.\nV30: убрана смена названия меню.\nV29: положение кнопок больше не сохраняется (при запуске они стоят на месте).\nV28: красивая кнопка Aim (прицел), кнопки двигаются.\nV27: кнопка меню — квадрат Sak (бело-розовый в Sakura, чёрно-фиолетовый в Space), переключатель режимов только в НАСТР.\nV26: оформление меню (углы, шрифт, частицы, свечение, блюр), лепестки, аура, компас, бег времени, спринт-кнопка, камера сквозь стены, дальний зум, режим скриншота, невидимые стены, сервер.\nV25: режимы меню Space (космос) и Sakura, значок Sak, звёзды, бегущая рамка.\nV24: исправлен автопрыжок (прыгает без остановки), автоклик, вращение, клик-удаление, координаты.\nV23: картинка сакуры как фон меню и на кнопке 🌸 (своя ссылка в НАСТР).\nV22: защита от ошибок в циклах (сломанный цикл сам останавливается), закреплённые функции и быстрая панель, описания по долгому нажатию, звуки меню, крупнее кнопки.\nV21: самотест функций, ESP предметов, скелет без Drawing, приоритет целей, скорость снаряда, масштаб и положение меню, свои горячие клавиши, экспорт/импорт настроек, язык RU/EN, плавный ТП, сохранение точек, лазание по стенам, блокнот, журнал входов.\nV20: цвет ESP по дистанции, ближайшие N, RGB, сигнал о врагах, статистика, маршрут, автопрыжок/бег, профили 1–3, проверка обновлений.\nV19: линии до игроков, анимации кнопок.\nV18: загрузочный экран, новый дизайн.\nV17: сброс в норму при закрытии, авто-реджойн."}, pSet)

    -- ПОИСК
    local pSearch = Page("ПОИСК")
    local aliases = {
        Noclip = "сквозь стены ноуклип", Fly = "полет полёт летать", SpeedHack = "скорость волчек быстро",
        BunnyHop = "бхоп прыжки банихоп", GodMode = "бессмертие год", Invisible = "невидимка невидимость",
        InfJump = "бесконечный прыжок", ESP = "есп вх подсветка", Aimbot = "аим аимбот прицел",
        Teleport = "телепорт тп", NoFall = "падение урон", XRay = "рентген", FullBright = "яркость свет",
        Hitbox = "хитбокс", ESP_Box = "бокс рамка box", ESP_Friends = "друзья", NoSound = "звук тишина",
        FPS = "фпс", Watermark = "ватермарк", LowGraphics = "графика лаги", ThirdPerson = "третье лицо",
        AntiVoid = "бездна пустота падение", CustomFOV = "поле зрения фов", Crosshair = "прицел перекрестие",
        TimeLock = "время ночь день", Freecam = "свободная камера фрикам", AntiFling = "флинг защита",
        ESP_Lines = "линии полоски трейсеры лучи", Radar = "радар карта миникарта", TargetHUD = "цель инфо худ",
        Gravity = "гравитация луна низкая", NoPostFX = "блюр эффекты размытие", RainbowBody = "радуга тело цвет",
        Trail = "след шлейф хвост", Flashlight = "фонарик свет лампа",
        AutoJump = "автопрыжок прыгать", AutoRun = "бег автобег вперёд", Alert = "сигнал враги звук тревога",
        StatsHUD = "статистика время таймер", RouteLoop = "маршрут повтор цикл",
        MenuFX = "частицы лепестки звёзды меню", MenuGlow = "свечение рамка", MenuBlur = "размытие блюр", RainbowTitle = "радужное название",
        Petals = "лепестки снег падающие", Aura = "аура контур свечение", TimeFlow = "время ускорение сутки", Compass = "компас север",
        ShowInvisible = "невидимые стены коллизии", Invisicam = "камера сквозь стены", FarZoom = "зум камера отдалить",
        HideCoreGui = "скрыть интерфейс скриншот", SprintBtn = "спринт ускорение кнопка бег",
        Freeze = "заморозка стоп якорь", NoTextures = "текстуры наклейки фпс", ColorGrade = "цвет цветокоррекция фильтр",
        FpsCap = "фпс лимит кадры",
        EnemyCount = "счётчик врагов количество", ESP_Tool = "оружие предмет", ESP_Arrows = "стрелки указатели",
        ESP_Outline = "контур обводка", ESP_VisCheck = "видимость стены", ESP_Speed = "скорость цель",
        AimLine = "линия цель", AimHold = "зажатие удержание аим", AimFF = "форсфилд щит", AimNeedTool = "оружие предмет аим",
        AimShowFOV = "круг фов", DashBtn = "рывок деш", DoubleJump = "двойной прыжок", Glide = "планирование парить",
        SpeedFOV = "фов скорость", Follow = "следовать идти", NightVision = "ночное зрение", Rain = "дождь",
        Vignette = "виньетка затемнение края",
    }
    local function Hay(f) return (f.Label .. " " .. f.Id .. " " .. (aliases[f.Id] or "")):lower() end
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local q = (searchBox.Text:lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if q == "" then SwitchTab(currentTab) return end
        for n, p in pairs(pages) do p.Visible = (n == "ПОИСК") end
        for _, c in ipairs(pSearch:GetChildren()) do
            if not c:IsA("UIListLayout") then c:Destroy() end
        end
        local hdr = Header(pSearch, "")
        local g = Grid(pSearch)
        local n = 0
        for _, f in ipairs(Features) do
            if Hay(f):find(q, 1, true) then FeatureButton(g, f) n += 1 end
        end
        hdr.Text = "🔍 Найдено: " .. n
    end)

    -- переключение вкладок
    SwitchTab = function(name)
        currentTab = name
        for n, p in pairs(pages) do p.Visible = (n == name) end
        for n, b in pairs(tabBtns) do b.BackgroundTransparency = (n == name) and 0.05 or 0.72 end
        titleTab.Text = "V32 · " .. TL(name)
        local pg = pages[name]
        if pg then
            pg.Position = UDim2.new(0, 5, 0, 18)
            TS:Create(pg, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {Position = UDim2.new(0, 5, 0, 5)}):Play()
        end
    end
    for i, name in ipairs(tabNames) do
        local b = Button(tabBar, tabIcons[i], UDim2.new(1 / #tabNames, -4, 1, -4),
            UDim2.new((i - 1) / #tabNames, 2, 0, 2))
        b.TextSize = 17
        tabBtns[name] = b
        b.MouseButton1Click:Connect(function() searchBox.Text = "" SwitchTab(name) end)
    end
    SwitchTab("ГЛАВНАЯ")
    RefreshUI()
    X.ApplyFont()
    X.ApplyGlow()
    X.StartFX(main)
    TS:Create(mainScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = X.menuScale}):Play()
end

local function ToggleMenu() if mainGui then mainGui.Enabled = not mainGui.Enabled end end
-- Перетаскиваемая кнопка: короткий тап = действие, перетаскивание = перемещение (позиция не сохраняется)
function X.MakeDraggable(btn, connName, onTap, onDone)
    local dragging, moved, startInput, startPos = false, false, nil, nil
    btn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, moved, startInput, startPos = true, false, i.Position, btn.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if moved then
                        if onDone then onDone(btn.Position) end
                    elseif onTap then
                        onTap()
                    end
                end
            end)
        end
    end)
    SM:AddConnection(connName, UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            if d.Magnitude > 6 then moved = true end
            if moved then
                local vp = Camera.ViewportSize
                btn.Position = UDim2.new(0, math.clamp(startPos.X.Offset + d.X, 24, vp.X - 24),
                    0, math.clamp(startPos.Y.Offset + d.Y, 24, vp.Y - 24))
            end
        end
    end))
end

local function CreateMenuButton()
    local gui = New("ScreenGui", {Name = "SakuraMenuButton", ResetOnSpawn = false}, player.PlayerGui)
    local btn = New("TextButton", {Size = UDim2.new(0, 46, 0, 46), AnchorPoint = Vector2.new(.5, .5),
        Position = UDim2.new(0, 38, 0, 138),
        BackgroundColor3 = Color3.new(1, 1, 1), Text = "Sak", TextSize = 16, Font = Enum.Font.GothamBlack,
        TextColor3 = Color3.fromRGB(255, 102, 178), AutoButtonColor = false, BorderSizePixel = 0}, gui)
    Round(btn, 12)
    local btnStroke = New("UIStroke", {Thickness = 1.5, Color = Color3.fromRGB(255, 190, 220)}, btn)
    Animate(btn, 12)
    X.menuBtn = btn
    X.menuLogo = {frame = btn, text = btn, stroke = btnStroke}
    X.UpdateLogo()
    X.MakeDraggable(btn, "MenuBtnDrag", ToggleMenu)
    SM.objects[#SM.objects + 1] = gui
end

-- Кнопка Aimbot: прицел в квадрате. Sakura = белый фон, розовый прицел; Space = чёрный фон, фиолетовый;
-- при включённом аимботе прицел и рамка светятся зелёным.
local function CreateAimbotButton()
    local gui = New("ScreenGui", {Name = "SakuraAimbotBtn", ResetOnSpawn = false}, player.PlayerGui)
    local btn = New("TextButton", {Size = UDim2.new(0, 46, 0, 46), AnchorPoint = Vector2.new(.5, .5),
        Position = UDim2.new(0, 38, 0, 80),
        BackgroundColor3 = Color3.new(1, 1, 1), Text = "", AutoButtonColor = false, BorderSizePixel = 0}, gui)
    Round(btn, 12)
    local stroke = New("UIStroke", {Thickness = 1.5, Color = Color3.fromRGB(255, 190, 220)}, btn)
    Animate(btn, 12)
    local parts = {}
    local ring = New("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, 0, .5, 0),
        Size = UDim2.new(0, 22, 0, 22), BackgroundTransparency = 1, BorderSizePixel = 0}, btn)
    Round(ring, 11)
    local ringStroke = New("UIStroke", {Thickness = 2, Color = Color3.new(1, 1, 1)}, ring)
    local function tickMark(x, y, w, h)
        parts[#parts + 1] = New("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, x, .5, y),
            Size = UDim2.new(0, w, 0, h), BorderSizePixel = 0}, btn)
    end
    tickMark(0, -15, 2, 9) tickMark(0, 15, 2, 9) tickMark(-15, 0, 9, 2) tickMark(15, 0, 9, 2)
    local dot = New("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, 0, .5, 0),
        Size = UDim2.new(0, 5, 0, 5), BorderSizePixel = 0}, btn)
    Round(dot, 3)
    parts[#parts + 1] = dot
    local function paint()
        local sp = Config.Misc.MenuMode == "space"
        local on = A.Enabled or (A.HoldMode and X.aimHeld)
        btn.BackgroundColor3 = sp and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
        local col = on and Color3.fromRGB(50, 230, 120) or (sp and Color3.fromRGB(165, 105, 255) or Color3.fromRGB(255, 102, 178))
        ringStroke.Color = col
        for _, part in ipairs(parts) do part.BackgroundColor3 = col end
        stroke.Color = on and Color3.fromRGB(50, 230, 120) or (sp and Color3.fromRGB(110, 60, 200) or Color3.fromRGB(255, 190, 220))
        stroke.Thickness = on and 3 or 1.5
    end
    AddRefresher(btn, paint)
    paint()
    local function isPress(i) return i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 end
    btn.InputBegan:Connect(function(i) if isPress(i) then X.aimHeld = true RefreshUI() end end)
    btn.InputEnded:Connect(function(i) if isPress(i) then X.aimHeld = false RefreshUI() end end)
    X.MakeDraggable(btn, "AimBtnDrag", function() if not A.HoldMode then F.Aimbot.Toggle() end end)
    SM.objects[#SM.objects + 1] = gui
end

-- ============ ХОТКЕИ ============
local hotkeyActions = {
    Aimbot = function() F.Aimbot.Toggle() end, Triggerbot = function() F.Triggerbot.Toggle() end,
    Noclip = function() F.Noclip.Toggle() end, Fly = function() F.Fly.Toggle() end,
    Invisible = function() F.Invisible.Toggle() end, GodMode = function() F.GodMode.Toggle() end,
    BunnyHop = function() F.BunnyHop.Toggle() end, SpeedHack = function() F.SpeedHack.Toggle() end,
    Menu = function() ToggleMenu() end, Unload = function() Unload() end,
}
SM:AddConnection("Hotkeys", UIS.InputBegan:Connect(function(input, gp)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if X.Rebind then
        local name = X.Rebind
        X.Rebind = nil
        if input.KeyCode ~= Enum.KeyCode.Escape then Config.Keys[name] = input.KeyCode.Name MarkDirty() end
        RefreshUI()
        return
    end
    if gp then return end
    local kn = input.KeyCode.Name
    for action, fn in pairs(hotkeyActions) do
        if Config.Keys[action] == kn then SafeCall(fn) end
    end
end))

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= player then X.LogEvent("в игре: " .. p.Name) end
end
SM:AddConnection("JoinLogAdd", Players.PlayerAdded:Connect(function(p) X.LogEvent("➕ зашёл " .. p.Name) end))
SM:AddConnection("JoinLogRem", Players.PlayerRemoving:Connect(function(p) X.LogEvent("➖ вышел " .. p.Name) end))

-- ============ ЦИКЛ И РЕСПАВН ============
BindCam("Main", function()
    if Running then Aim:Update() end
end)

SM:AddConnection("CharBind", player.CharacterAdded:Connect(BindChar))

charCallbacks[#charCallbacks + 1] = function()
    ApplySpeed()
    ApplyJump()
    if U.NoStun then SetStunStates(false) end
end

-- ============ ЗАПУСК ============
Loader.Step("Загрузка профиля", 0.9)
SafeCall(function()
    local ok, msg = LoadConfig()
    profileStatus = ok and "✅ Профиль загружен" or ("ℹ️ " .. tostring(msg))
end)
task.spawn(X.LoadImage, Config.Misc.ImageUrl, false, "sakura")
task.spawn(X.LoadImage, Config.Misc.SpaceUrl, false, "space")
Loader.Step("Построение меню", 0.96)
SafeCall(function()
    CreateUI()
    CreateFOV()
    CreateAimbotButton()
    CreateMenuButton()
end)
SafeCall(X.RebuildQuick)
if not mainGui then Toast("⚠️ Меню не построилось — ошибки в консоли и в логе") end
Loader.Step("Готово!", 1)
Loader.Done()
task.spawn(function() task.wait(2) if Running then CheckUpdate(true) end end)

print("🌸 SAKURA V32 загружена")
print("Хоткеи: Q Aimbot | T Triggerbot | N Noclip | F Fly | I Invisible | G God | B BunnyHop | X Волчек")
print("Teleport: Ctrl+ЛКМ на ПК, тап по миру на телефоне (включить в УЛЬТРА)")
