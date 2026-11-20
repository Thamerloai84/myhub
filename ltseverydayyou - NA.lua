local url = "https://gitlab.com/ltseverydayyou/Nameless-Admin/-/raw/main/Source.lua"
local cache = "NA-split-gitlab/Source.lua"
local ok, source = pcall(game.HttpGet, game, url)
local chunk, compileError

if ok and type(source) == "string" and source ~= "" then
    chunk, compileError = loadstring(source)
    if chunk and type(writefile) == "function" then
        if type(makefolder) == "function" then pcall(makefolder, "NA-split-gitlab") end
        pcall(writefile, cache, source)
    end
end

if not chunk and type(readfile) == "function" then
    local readOk, cached = pcall(readfile, cache)
    if readOk and type(cached) == "string" and cached ~= "" then
        chunk, compileError = loadstring(cached)
    end
end

assert(chunk, compileError or "Nameless Admin loader unavailable and no local cache exists")
chunk()
