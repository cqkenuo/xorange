local ipairs = ipairs
local type = type
local tostring = tostring

local utils = require("orange.utils.utils")
local judge_util = require("orange.utils.judge")
local BasePlugin = require("orange.plugins.base_handler")
local counter = require("orange.plugins.rate_limiting.counter")
local rules_cache = require("orange.utils.rules_cache")

local function get_current_stat(limit_key)
    return counter.get(limit_key)
end

local function incr_stat(limit_key, limit_type)
    counter.incr(limit_key, 1, limit_type)
end

local function get_limit_type(period)
    if not period then return nil end

    if period == 1 then
        return "Second"
    elseif period == 60 then
        return "Minute"
    elseif period == 3600 then
        return "Hour"
    elseif period == 86400 then
        return "Day"
    else
        return nil
    end
end

local function filter_rules(sid, plugin, ngx_var_uri)
    local rules = rules_cache.get_rules(plugin,sid)
    if not rules or type(rules) ~= "table" or #rules <= 0 then
        return false
    end

    for i, rule in ipairs(rules) do
        if rule.enable == true then
            -- judge阶段
            local pass = judge_util.judge_rule(rule, plugin)

            -- handle阶段
            local handle = rule.handle
            if pass then
                local limit_type = get_limit_type(handle.period)

                -- only work for valid limit type(1 second/minute/hour/day)
                if limit_type then
                    local current_timetable = utils.current_timetable()
                    local time_key = current_timetable[limit_type]
                    local limit_key = rule.id .. "#" .. time_key
                    local current_stat = get_current_stat(limit_key) or 0
                        
                    ngx.header["X-RateLimit-Limit" .. "-" .. limit_type] = handle.count

                    if current_stat >= handle.count then
                        if handle.log == true then
                            ngx.log(ngx.INFO, "[RateLimiting-Forbidden-Rule] ", rule.name, " uri:", ngx_var_uri, " limit:", handle.count, " reached:", current_stat, " remaining:", 0)
                        end

                        ngx.header["X-RateLimit-Remaining" .. "-" .. limit_type] = 0
                        ngx.exit(429)
                        return true
                    else
                        ngx.header["X-RateLimit-Remaining" .. "-" .. limit_type] = handle.count - current_stat - 1
                        incr_stat(limit_key, limit_type)

                        -- only for test, comment it in production
                        -- if handle.log == true then
                        --     ngx.log(ngx.INFO, "[RateLimiting-Rule] ", rule.name, " uri:", ngx_var_uri, " limit:", handle.count, " reached:", current_stat + 1)
                        -- end
                    end
                end
            end -- end `pass`

        end -- end `enable`
    end -- end for

    return false
end


local RateLimitingHandler = BasePlugin:extend()
RateLimitingHandler.PRIORITY = 1000

function RateLimitingHandler:new(store)
    RateLimitingHandler.super.new(self, "rate-limiting-plugin")
    self.store = store
end

function RateLimitingHandler:access(conf)
    RateLimitingHandler.super.access(self)
    
    local enable = rules_cache.get_enable("rate_limiting")
    if not enable or enable ~= true then
        return
    end

    local meta = rules_cache.get_meta("rate_limiting")
    local selectors = rules_cache.get_selectors("rate_limiting")
    local ordered_selectors = meta and meta.selectors
    
    if not meta or not ordered_selectors or not selectors then
        return
    end

    ngx.log(ngx.INFO, "[RateLimiting] check selector")

    local ngx_var_uri = ngx.var.uri
    for i, sid in ipairs(ordered_selectors) do
        local selector = selectors[sid]
        if selector and selector.enable == true then
            local selector_pass 
            if selector.type == 0 then -- 全流量选择器
                selector_pass = true
            else
                selector_pass = judge_util.judge_selector(selector, "rate_limiting")-- selector judge
            end

            if selector_pass then
                if selector.handle and selector.handle.log == true then
                    ngx.log(ngx.INFO, "[RateLimiting][PASS-SELECTOR:", sid, "] ", ngx_var_uri)
                end

                local stop = filter_rules(sid, "rate_limiting", ngx_var_uri)
                local selector_continue = selector.handle and selector.handle.continue
                if stop or not selector_continue then -- 不再执行此插件其他逻辑
                    return
                end
            else
                if selector.handle and selector.handle.log == true then
                    ngx.log(ngx.INFO, "[RateLimiting][NOT-PASS-SELECTOR:", sid, "] ", ngx_var_uri)
                end
            end
        end
    end

end

return RateLimitingHandler
