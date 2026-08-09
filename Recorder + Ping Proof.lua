-- Load Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

-- State variables (Recorder)
local isRecording = false
local recordedFrames = {}
local recordFPS = 60
local ghostModel = nil
local recordConnection = nil
local playConnection = nil

-- State variables (Ping Tracker)
local pingTrackerOn = false
local pingGhost = nil
local pingConnection = nil
local pingBuffer = {}

-- Helper function to get a unique path for every part
local function getRelativePath(model, part)
    local path = {}
    local current = part
    while current and current ~= model do
        table.insert(path, 1, current.Name)
        current = current.Parent
    end
    return table.concat(path, ".")
end

-- Helper function to find a part from its path
local function getPartFromPath(model, pathStr)
    local current = model
    for partName in string.gmatch(pathStr, "[^.]+") do
        current = current:FindFirstChild(partName)
        if not current then return nil end
    end
    return current
end

-- Helper function to setup a ghost (used for both Recorder and Ping Tracker)
local function setupGhostModel(model)
    for _, obj in pairs(model:GetDescendants()) do
        if obj:IsA("BasePart") then
            if obj.Parent:IsA("Accessory") then
                obj.Anchored = false 
            else
                obj.Anchored = true 
            end
            obj.CanCollide = false
            obj.CanQuery = false
            obj.CanTouch = false
            obj.Massless = true
            
            -- GHOST VISUALS: Make them transparent and ghostly blue
            if obj.Transparency < 1 then
                obj.Transparency = 0.6
            end
            obj.Color = Color3.fromRGB(220, 235, 255)
            
        elseif obj:IsA("BodyColors") then
            -- GHOST VISUALS: Tint the BodyColors (Must use BrickColor!)
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
            obj.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        elseif obj:IsA("Script") or obj:IsA("LocalScript") then
            obj.Disabled = true
        end
    end
end

-- Create Rayfield Window
local Window = Rayfield:CreateWindow({
   Name = "Ghost Recorder System",
   LoadingTitle = "Loading Ghost Recorder...",
   LoadingSubtitle = "by AI",
   Theme = "Default",
   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false,
})

-- ==========================================
-- MAIN TAB (Recorder)
-- ==========================================
local Tab = Window:CreateTab("Main", 4483362458)

Tab:CreateDropdown({
   Name = "Recording FPS",
   Options = {"10", "15", "20", "30", "45", "60"},
   Default = "60",
   Callback = function(Value)
       if type(Value) == "string" then
           recordFPS = tonumber(Value) or 60
       end
   end,
})

Tab:CreateButton({
   Name = "Start Recording",
   Callback = function()
       if isRecording then return end
       local char = player.Character
       if not char then return end

       isRecording = true
       recordedFrames = {}
       local targetDelay = 1 / recordFPS
       local lastRecordTime = os.clock()

       if recordConnection then recordConnection:Disconnect() end

       recordConnection = RunService.Heartbeat:Connect(function()
           if not isRecording then
               if recordConnection then recordConnection:Disconnect() end
               return
           end

           local currentTime = os.clock()
           if currentTime - lastRecordTime >= targetDelay then
               lastRecordTime = currentTime
               local frameData = {}
               for _, part in pairs(char:GetDescendants()) do
                   if part:IsA("BasePart") and not part.Parent:IsA("Accessory") then
                       frameData[getRelativePath(char, part)] = part.CFrame
                   end
               end
               table.insert(recordedFrames, frameData)
           end
       end)
   end,
})

Tab:CreateButton({
   Name = "Stop Recording",
   Callback = function()
       if not isRecording then return end
       isRecording = false
       if recordConnection then 
           recordConnection:Disconnect() 
           recordConnection = nil 
       end
   end,
})

Tab:CreateButton({
   Name = "Play Ghost",
   Callback = function()
       if isRecording then return end
       if #recordedFrames == 0 then return end

       if ghostModel then ghostModel:Destroy() end

       local char = player.Character
       if not char then return end

       char.Archivable = true 
       ghostModel = char:Clone()
       ghostModel.Name = "Ghost_" .. player.Name
       setupGhostModel(ghostModel)
       ghostModel.Parent = workspace

       local currentIndex = 1
       local targetDelay = 1 / recordFPS
       local lastPlayTime = os.clock()

       if playConnection then playConnection:Disconnect() end

       playConnection = RunService.Heartbeat:Connect(function()
           if not ghostModel or not ghostModel.Parent then
               if playConnection then playConnection:Disconnect() end
               return
           end

           local currentTime = os.clock()
           if currentTime - lastPlayTime >= targetDelay then
               lastPlayTime = currentTime
               local frame = recordedFrames[currentIndex]
               if frame then
                   for pathStr, cframe in pairs(frame) do
                       local part = getPartFromPath(ghostModel, pathStr)
                       if part and part:IsA("BasePart") then
                           part.CFrame = cframe
                           part.CanCollide = false 
                       end
                   end
               end
               currentIndex = currentIndex + 1
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

Tab:CreateButton({
   Name = "Clear Recording Data",
   Callback = function()
       recordedFrames = {}
   end,
})

-- ==========================================
-- PING PROOF TAB
-- ==========================================
local PingTab = Window:CreateTab("Ping Proof", 4483362458)

PingTab:CreateParagraph({
   Title = "Ping Proof Explanation",
   Content = "This tab will maybe show proof that you are lagging or the server makes your ping like this"
})

PingTab:CreateToggle({
   Name = "Ping Tracker",
   Description = "Spawns a live ghost that mimics your actions delayed by your exact ping.",
   CurrentValue = false,
   Flag = "PingTrackerToggle",
   Callback = function(Value)
       pingTrackerOn = Value
       
       if Value then
           -- Turn ON
           local char = player.Character
           if not char then return end
           
           char.Archivable = true
           pingGhost = char:Clone()
           pingGhost.Name = "PingGhost_" .. player.Name
           setupGhostModel(pingGhost)
           pingGhost.Parent = workspace
           
           pingBuffer = {}
           
           pingConnection = RunService.Heartbeat:Connect(function()
               if not pingTrackerOn then return end
               if not pingGhost or not pingGhost.Parent or not player.Character then return end
               
               local currentTime = os.clock()
               
               -- 1. Record current frame
               local frameData = {}
               for _, part in pairs(player.Character:GetDescendants()) do
                   if part:IsA("BasePart") and not part.Parent:IsA("Accessory") then
                       frameData[getRelativePath(player.Character, part)] = part.CFrame
                   end
               end
               table.insert(pingBuffer, {time = currentTime, frames = frameData})
               
               -- 2. Clean buffer (keep max 2 seconds of history)
               local maxAge = currentTime - 2.0
               while #pingBuffer > 0 and pingBuffer[1].time < maxAge do
                   table.remove(pingBuffer, 1)
               end
               
               -- 3. Get Ping safely
               local ping = 0.1 -- default to 100ms
               pcall(function()
                   ping = player:GetNetworkPing()
               end)
               
               -- 4. Find the frame that matches the ping delay
               local targetTime = currentTime - ping
               local bestFrame = nil
               local bestDiff = math.huge
               
               for i = #pingBuffer, 1, -1 do
                   local diff = math.abs(pingBuffer[i].time - targetTime)
                   if diff < bestDiff then
                       bestDiff = diff
                       bestFrame = pingBuffer[i].frames
                   else
                       break
                   end
               end
               
               -- 5. Apply delayed frame to ghost
               if bestFrame then
                   for pathStr, cframe in pairs(bestFrame) do
                       local part = getPartFromPath(pingGhost, pathStr)
                       if part and part:IsA("BasePart") then
                           part.CFrame = cframe
                           part.CanCollide = false
                       end
                   end
               end
           end)
       else
           -- Turn OFF
           if pingConnection then 
               pingConnection:Disconnect() 
               pingConnection = nil 
           end
           if pingGhost then
               pingGhost:Destroy()
               pingGhost = nil
           end
           pingBuffer = {}
       end
   end,
})

Rayfield:LoadConfiguration()
