local DelayArmedResponse = _G.DelayArmedResponse or {}
_G.DelayArmedResponse = DelayArmedResponse

DelayArmedResponse.mod_path = DelayArmedResponse.mod_path or ModPath
DelayArmedResponse.save_path = DelayArmedResponse.save_path or SavePath
DelayArmedResponse.settings_file = DelayArmedResponse.settings_file or (DelayArmedResponse.save_path .. "delay_armed_response.json")
DelayArmedResponse.defaults = DelayArmedResponse.defaults or {
    delay = 32,
    show_hint = true
}

local unpack = unpack or table.unpack
local json_library = json

local function deep_clone(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end

    local copy = {}

    for key, value in pairs(tbl) do
        if type(value) == "table" then
            copy[key] = deep_clone(value)
        else
            copy[key] = value
        end
    end

    return copy
end

function DelayArmedResponse:_merge_settings(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            target[key] = target[key] or {}
            self:_merge_settings(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function DelayArmedResponse:load()
    self.settings = deep_clone(self.defaults)

    local file = io.open(self.settings_file, "r")

    if file and json_library then
        local content = file:read("*all")
        file:close()

        if content and content ~= "" then
            local data = nil

            pcall(function()
                data = json_library.decode(content)
            end)

            if type(data) == "table" then
                self:_merge_settings(self.settings, data)
            end
        end
    else
        if file then
            file:close()
        end

        if json_library then
            self:save()
        end
    end

    return self.settings
end

function DelayArmedResponse:save()
    if not json_library then
        return
    end

    local file = io.open(self.settings_file, "w")

    if file then
        file:write(json_library.encode(self.settings or {}))
        file:close()
    end
end

if not DelayArmedResponse.settings then
    DelayArmedResponse:load()
end

if RequiredScript == "lib/managers/group_ai_states/groupaistatebase" then
    local original_on_police_called = GroupAIStateBase.on_police_called

    function GroupAIStateBase:on_police_called(...)
        local delay_seconds = DelayArmedResponse.settings and DelayArmedResponse.settings.delay or DelayArmedResponse.defaults.delay
        delay_seconds = tonumber(delay_seconds) or DelayArmedResponse.defaults.delay

        if Network:is_server() and delay_seconds > 0 and not self._delay_armed_response_done then
            if self._delay_armed_response_scheduled then
                return
            end

            if not DelayedCalls then
                return original_on_police_called(self, ...)
            end

            self._delay_armed_response_scheduled = true
            self._delay_armed_response_call_id = (self._delay_armed_response_call_id or 0) + 1
            local args = {...}
            local call_id = string.format("DelayArmedResponse_on_police_called_%s_%s", tostring(self._id or "state"), tostring(self._delay_armed_response_call_id))

            log(string.format("[Delay Armed Response] Operator triggering alarm in %.1f seconds.", delay_seconds))

            if DelayArmedResponse.settings.show_hint and managers and managers.hud and managers.hud.show_hint then
                managers.hud:show_hint({
                    text = string.format("Operator triggering alarm in %.1f seconds", delay_seconds)
                })
            end

            DelayedCalls:Add(call_id, delay_seconds, function()
                self._delay_armed_response_scheduled = nil
                self._delay_armed_response_done = true
                log("[Delay Armed Response] Police are now responding.")
                original_on_police_called(self, unpack(args))
            end)

            return
        end

        return original_on_police_called(self, ...)
    end
end
