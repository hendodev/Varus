local IsDevelopmentBranch, NotificationTime = false,5
local Branch = IsDevelopmentBranch and "development" or "main"
local Source = "https://raw.githubusercontent.com/hendodev/Varus/" .. Branch .. "/Loader.lua"

local function http_get(url)
    if syn and syn.request then
        local res = syn.request({Url = url, Method = "GET"})
        return res and res.Body
    end
    if http and http.request then
        local res = http.request({Url = url, Method = "GET"})
        return res and (res.Body or res.body)
    end
    if httprequest then
        local res = httprequest({Url = url, Method = "GET"})
        return res and res.Body
    end
    if game and game.HttpGet then
        return game:HttpGet(url)
    end
    error("No supported HTTP request function found in this executor.")
end

local function load_code(code, name)
    if loadstring then
        return assert(loadstring(code, name))
    elseif load then
        return assert(load(code, name))
    else
        error("No loadstring/load available in this environment.")
    end
end

local code = http_get(Source)
local fn = load_code(code, "Loader")
fn(Branch, NotificationTime)
