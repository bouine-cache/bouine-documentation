-- redbean request hook for the bouine documentation site.
-- Optional markdown content negotiation for agents; otherwise default routing.

ProgramContentType('md', 'text/markdown; charset=utf-8')

function OnHttpRequest()
    local accept = GetHeader('Accept') or ''
    if accept:find('text/markdown') then
        local path = GetPath()
        local mdpath = (path:sub(-1) == '/') and (path .. 'index.md') or (path .. '/index.md')
        mdpath = mdpath:gsub('//', '/')
        local asset = LoadAsset(mdpath)
        if asset then
            SetStatus(200)
            SetHeader('Content-Type', 'text/markdown; charset=utf-8')
            Write(asset)
            return
        end
    end
    Route()
end
