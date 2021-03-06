--
-- Created by IntelliJ IDEA.
-- User: soul11201 <soul11201@gmail.com>
-- Date: 2017/4/26
-- Time: 20:50
-- To change this template use File | Settings | File Templates.
--

local handle_util = require("orange.utils.handle")
local extractor_util = require("orange.utils.extractor")

local _M = {}

local function set_header(k,v,overide)
    local override = overide or false

end

function _M:set_headers(rule)
    local extractor,headers_config= rule.extractor,rule.headers

    if not headers_config or type(headers_config) ~= 'table' then
        return
    end

    local variables = extractor_util.extract_variables(extractor)
    local req_headers = ngx.req.get_headers();

    for _, v in pairs(headers_config) do
        --  不存在 || 存在且覆蓋
        if not req_headers[v.name] or  v.override == '1' then
            if v.type == "normal" then
                if v.category == 'req' then
                    ngx.req.set_header(v.name,v.value)
                else
                    ngx.header[v.name] = v.value
                end
                ngx.log(ngx.INFO,'[Header] add normal ',v.category,' headers [',v.name,":",v.value,']')
            elseif v.type == "extraction" then
                local value = handle_util.build_uri(extractor.type, v.value, variables)
                if v.category == 'req' then
                    ngx.req.set_header(v.name,value)
                else
                    ngx.header[v.name] = value
                end
                ngx.log(ngx.INFO,'[Header] add extrator ',v.category,' headers [',v.name,":",value,']')
            end
        end

    end
end

return _M
