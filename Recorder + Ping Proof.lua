-- Load Rayfield Library
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

--==================================================
-- RECORDER STATE
--==================================================

local isRecording = false
local recordedFrames = {}
local recordFPS = 60

local ghostModel = nil
local recordConnection = nil
local playConnection = nil

--==================================================
-- SERVER-VIEW GHOST STATE
--==================================================

local serverGhostEnabled = false
local serverGhost = nil
local serverGhostConnection = nil

local serverBuffer = {}

-- Keep enough history for high ping
local SERVER_BUFFER_TIME = 3

--==================================================
-- PATH HELPERS
--==================================================

local function getRelativePath(model, part)
    local path = {}
    local current = part

    while current and current ~= model do
        table.insert(path, 1, current.Name)
        current = current.Parent
    end

    return table.concat(path, ".")
end

local function getPartFromPath(model, pathStr)
    local current = model

    for partName in string.gmatch(pathStr, "[^.]+") do
        current = current:FindFirstChild(partName)

        if not current then
            return nil
        end
    end

    return current
end

--==================================================
-- GHOST SETUP
--==================================================

local function setupGhostModel(model)
    for _, obj in pairs(model:GetDescendants()) do

        if obj:IsA("BasePart") then

            obj.Anchored = true
            obj.CanCollide = false
            obj.CanQuery = false
            obj.CanTouch = false
            obj.Massless = true

            if obj.Transparency < 1 then
                obj.Transparency = 0.6
            end

            obj.Color = Color3.fromRGB(220, 235, 255)

        elseif obj:IsA("BodyColors") then

            local ghostColor = BrickColor.new("Pastel Blue")

            obj.HeadColor = ghostColor
            obj.LeftArmColor = ghostColor
            obj.RightArmColor = ghostColor
            obj.LeftLegColor = ghostColor
            obj.RightLegColor = ghostColor
            obj.TorsoColor = ghostColor

        elseif obj:IsA("Humanoid") then

            obj.RequiresNeck = false
            obj.Health = 100
            obj.MaxHealth = 100

            obj.WalkSpeed = 0
            obj.JumpPower = 0

            obj.AutoRotate = false
            obj.PlatformStand = true

            obj.DisplayDistanceType =
                Enum.HumanoidDisplayDistanceType.None

        elseif obj:IsA("Script") or obj:IsA("LocalScript") then

            obj.Disabled = true
        end
    end
end

--==================================================
-- CAPTURE CHARACTER
--==================================================

local function captureCharacter(character)
    local frameData = {}

    if not character then
        return frameData
    end

    for _, part in pairs(character:GetDescendants()) do

        if part:IsA("BasePart")
            and not part.Parent:IsA("Accessory") then

            frameData[getRelativePath(character, part)] = part.CFrame
        end
    end

    return frameData
end

--==================================================
-- APPLY FRAME
--==================================================

local function applyFrame(model, frameData)

    if not model or not model.Parent then
        return
    end

    for pathStr, cframe in pairs(frameData) do

        local part = getPartFromPath(model, pathStr)

        if part and part:IsA("BasePart") then
            part.CFrame = cframe
        end
    end
end

--==================================================
-- RAYFIELD WINDOW
--==================================================

local Window = Rayfield:CreateWindow({
    Name = "Ghost Recorder System",

    LoadingTitle = "Loading Ghost Recorder...",

    LoadingSubtitle = "by AI",

    Theme = "Default",

    DisableRayfieldPrompts = false,

    DisableBuildWarnings = false,
})

--==================================================
-- MAIN TAB
--==================================================

local Tab = Window:CreateTab(
    "Main",
    4483362458
)

Tab:CreateDropdown({
    Name = "Recording FPS",

    Options = {
        "10",
        "15",
        "20",
        "30",
        "45",
        "60"
    },

    CurrentOption = {"60"},

    Callback = function(Value)

        local selected = Value

        if type(Value) == "table" then
            selected = Value[1]
        end

        if type(selected) == "string" then
            recordFPS = tonumber(selected) or 60
        end
    end,
})

--==================================================
-- START RECORDING
--==================================================

Tab:CreateButton({
    Name = "Start Recording",

    Callback = function()

        if isRecording then
            return
        end

        local char = player.Character

        if not char then
            return
        end

        isRecording = true
        recordedFrames = {}

        local targetDelay = 1 / recordFPS
        local lastRecordTime = os.clock()

        if recordConnection then
            recordConnection:Disconnect()
        end

        recordConnection = RunService.Heartbeat:Connect(function()

            if not isRecording then

                if recordConnection then
                    recordConnection:Disconnect()
                    recordConnection = nil
                end

                return
            end

            local now = os.clock()

            if now - lastRecordTime >= targetDelay then

                lastRecordTime = now

                local frameData =
                    captureCharacter(player.Character)

                table.insert(recordedFrames, frameData)
            end
        end)
    end,
})

--==================================================
-- STOP RECORDING
--==================================================

Tab:CreateButton({
    Name = "Stop Recording",

    Callback = function()

        if not isRecording then
            return
        end

        isRecording = false

        if recordConnection then
            recordConnection:Disconnect()
            recordConnection = nil
        end
    end,
})

--==================================================
-- PLAY RECORDED GHOST
--==================================================

Tab:CreateButton({
    Name = "Play Ghost",

    Callback = function()

        if isRecording then
            return
        end

        if #recordedFrames == 0 then
            return
        end

        if ghostModel then
            ghostModel:Destroy()
            ghostModel = nil
        end

        local char = player.Character

        if not char then
            return
        end

        char.Archivable = true

        ghostModel = char:Clone()

        ghostModel.Name =
            "Ghost_" .. player.Name

        setupGhostModel(ghostModel)

        ghostModel.Parent = workspace

        local currentIndex = 1

        local targetDelay = 1 / recordFPS

        local lastPlayTime = os.clock()

        if playConnection then
            playConnection:Disconnect()
        end

        playConnection = RunService.Heartbeat:Connect(function()

            if not ghostModel
                or not ghostModel.Parent then

                if playConnection then
                    playConnection:Disconnect()
                    playConnection = nil
                end

                return
            end

            local now = os.clock()

            if now - lastPlayTime >= targetDelay then

                lastPlayTime = now

                local frame =
                    recordedFrames[currentIndex]

                if frame then
                    applyFrame(
                        ghostModel,
                        frame
                    )
                end

                currentIndex += 1

                if currentIndex > #recordedFrames then

                    if ghostModel then
                        ghostModel:Destroy()
                        ghostModel = nil
                    end

                    if playConnection then
                        playConnection:Disconnect()
                        playConnection = nil
                    end
                end
            end
        end)
    end,
})

--==================================================
-- CLEAR RECORDING
--==================================================

Tab:CreateButton({
    Name = "Clear Recording Data",

    Callback = function()

        recordedFrames = {}

        if ghostModel then
            ghostModel:Destroy()
            ghostModel = nil
        end
    end,
})

--==================================================
-- SERVER VIEW TAB
--==================================================

local ServerTab = Window:CreateTab(
    "Server View",
    4483362458
)

ServerTab:CreateParagraph({
    Title = "Replication Ghost",

    Content =
        "Shows an approximation of how your character may appear after network replication. The delay uses approximately half of your measured round-trip ping."
})

--==================================================
-- SERVER GHOST
--==================================================

ServerTab:CreateToggle({

    Name = "Server-View Ghost",

    Description =
        "Displays your character approximately one-way network latency behind.",

    CurrentValue = false,

    Flag = "ServerViewGhost",

    Callback = function(Value)

        serverGhostEnabled = Value

        --==========================================
        -- TURN OFF
        --==========================================

        if not Value then

            if serverGhostConnection then
                serverGhostConnection:Disconnect()
                serverGhostConnection = nil
            end

            if serverGhost then
                serverGhost:Destroy()
                serverGhost = nil
            end

            serverBuffer = {}

            return
        end

        --==========================================
        -- TURN ON
        --==========================================

        local char = player.Character

        if not char then
            return
        end

        char.Archivable = true

        serverGhost = char:Clone()

        serverGhost.Name =
            "ServerViewGhost_" .. player.Name

        setupGhostModel(serverGhost)

        serverGhost.Parent = workspace

        serverBuffer = {}

        --==========================================
        -- NETWORK HISTORY
        --==========================================

        serverGhostConnection =
            RunService.Heartbeat:Connect(function()

                if not serverGhostEnabled then
                    return
                end

                local character = player.Character

                if not character then
                    return
                end

                if not serverGhost
                    or not serverGhost.Parent then
                    return
                end

                local now = os.clock()

                -- Record current local state
                local frameData =
                    captureCharacter(character)

                table.insert(serverBuffer, {
                    time = now,
                    frames = frameData
                })

                --==================================
                -- GET PING
                --==================================

                local ping = 0

                pcall(function()
                    ping = player:GetNetworkPing()
                end)

                if type(ping) ~= "number"
                    or ping < 0 then

                    ping = 0.1
                end

                --==================================
                -- ESTIMATE ONE-WAY LATENCY
                --==================================

                local oneWayDelay =
                    ping / 2

                -- Don't allow ridiculous delays
                oneWayDelay =
                    math.clamp(
                        oneWayDelay,
                        0,
                        SERVER_BUFFER_TIME
                    )

                local targetTime =
                    now - oneWayDelay

                --==================================
                -- REMOVE OLD HISTORY
                --==================================

                local minimumTime =
                    now - SERVER_BUFFER_TIME

                while #serverBuffer > 0
                    and serverBuffer[1].time < minimumTime do

                    table.remove(
                        serverBuffer,
                        1
                    )
                end

                --==================================
                -- FIND CLOSEST HISTORICAL FRAME
                --==================================

                local bestFrame = nil
                local bestDifference = math.huge

                for i = #serverBuffer, 1, -1 do

                    local entry =
                        serverBuffer[i]

                    local difference =
                        math.abs(
                            entry.time - targetTime
                        )

                    if difference < bestDifference then

                        bestDifference = difference

                        bestFrame = entry.frames

                    elseif entry.time < targetTime then

                        break
                    end
                end

                --==================================
                -- MOVE GHOST
                --==================================

                if bestFrame then

                    applyFrame(
                        serverGhost,
                        bestFrame
                    )
                end
            end)
    end,
})

--==================================================
-- PING DISPLAY
--==================================================

ServerTab:CreateButton({

    Name = "Show Current Ping",

    Callback = function()

        local ping = 0

        pcall(function()
            ping = player:GetNetworkPing()
        end)

        local milliseconds =
            math.floor(
                ping * 1000 + 0.5
            )

        local estimatedOneWay =
            math.floor(
                (ping / 2) * 1000 + 0.5
            )

        Rayfield:Notify({

            Title = "Network Information",

            Content =
                "RTT: "
                .. milliseconds
                .. " ms | Estimated one-way: "
                .. estimatedOneWay
                .. " ms",

            Duration = 4,
        })
    end,
})

--==================================================
-- CHARACTER RESPAWN HANDLING
--==================================================

player.CharacterAdded:Connect(function(character)

    task.wait(1)

    -- Recreate server ghost after respawn
    if serverGhostEnabled then

        if serverGhost then
            serverGhost:Destroy()
            serverGhost = nil
        end

        character.Archivable = true

        serverGhost =
            character:Clone()

        serverGhost.Name =
            "ServerViewGhost_" .. player.Name

        setupGhostModel(serverGhost)

        serverGhost.Parent = workspace

        serverBuffer = {}
    end
end)

--==================================================
-- LOAD CONFIGURATION
--==================================================

Rayfield:LoadConfiguration()
