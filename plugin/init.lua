-- 定义NERDTreeProject类
print ('hello')

local NERDTreeProject = {}
NERDTreeProject.__index = NERDTreeProject

-- 类方法
function NERDTreeProject:Add(name, nerdtree)
    for _, proj in ipairs(self:All()) do
        if proj:getName() == name then
            return proj:update(nerdtree)
        end
    end

    local newProj = self:New(name, nerdtree)
    table.insert(self:All(), newProj)
    self:Write()
    newProj:open()
end

function NERDTreeProject:All()
    if not self._All then
        self._All = {}
        self:Read()
    end
    return self._All
end

function NERDTreeProject:Remove(name)
    for i, proj in ipairs(self:All()) do
        if proj:getName() == name then
            table.remove(self:All(), i)
            self:Write()
            return "Project removed."
        end
    end
    return "No project found with name: '" .. name .. "'"
end

function NERDTreeProject:New(name, nerdtree, opts)
    if name:match(" ") then
        error("NERDTree.IllegalProjectNameError: illegal name:" .. name)
    end

    local newObj = setmetatable({}, NERDTreeProject)
    newObj._name = name
    newObj._rootPath = nerdtree.root.path

    opts = opts or {}
    if opts.openDirs then
        newObj._openDirs = opts.openDirs
    else
        newObj._openDirs = newObj:_extractOpenDirs(nerdtree.root)
    end

    newObj._hiddenDirs = opts.hiddenDirs or {}

    newObj:rebuildHiddenRegex()

    return newObj
end

function NERDTreeProject:FindByName(name)
    for _, proj in ipairs(self:All()) do
        if proj:getName() == name then
            return proj
        end
    end
    error("NERDTree.NoProjectError: no project found for name: \"" .. name .. "\"")
end

function NERDTreeProject:FindByRoot(dir)
    for _, proj in ipairs(self:All()) do
        if proj:getRootPath():equals(dir) then
            return proj
        end
    end
    error("NERDTree.NoProjectError: no project found for root: \"" .. dir:str() .. "\"")
end

function NERDTreeProject:LoadFromCWD()
    local proj = self:FindByRoot(vim.fn.getcwd())
    if proj then
        proj:open()
        vim.cmd("wincmd w")
    else
        vim.fn.NERDTree()
    end
end

function NERDTreeProject:Open(name)
    self:FindByName(name):open()
end

function NERDTreeProject:OpenForRoot(dir)
    local proj = self:FindByRoot(dir)
    if proj then
        proj:open()
    end
end

function NERDTreeProject:ProjectFileName()
    return vim.fn.expand("~/.NERDTreeProjects")
end

function NERDTreeProject:Read()
    local filename = self:ProjectFileName()
    if not vim.fn.filereadable(filename) then
        return {}
    end

    local projHashes = vim.fn.readfile(filename)[1]
    for _, projHash in ipairs(projHashes) do
        local nerdtree = vim.fn.NERDTreeNew(projHash.rootPath, "tab")
        local project = self:New(projHash.name, nerdtree, { openDirs = projHash.openDirs, hiddenDirs = projHash.hiddenDirs })
        table.insert(self:All(), project)
    end
end

function NERDTreeProject:UpdateProjectInBuf(bufnr)
    local nerdtree = vim.fn.getbufvar(bufnr, "NERDTree")

    if not nerdtree then
        return
    end

    if not nerdtree.__currentProject then
        return
    end

    local proj = nerdtree.__currentProject

    proj:update(nerdtree)
end

function NERDTreeProject:Write()
    local projHashes = {}

    for _, proj in ipairs(self:All()) do
        local hash = {
            name = proj:getName(),
            openDirs = proj:getOpenDirs(),
            rootPath = proj:getRootPath():str(),
            hiddenDirs = proj:getHiddenDirs()
        }

        table.insert(projHashes, hash)
    end

    vim.fn.writefile({ vim.fn.string(projHashes) }, self:ProjectFileName())
end

-- 实例方法
function NERDTreeProject:_extractOpenDirs(rootNode)
    local retVal = {}

    for _, node in ipairs(rootNode:getDirChildren()) do
        if node.isOpen then
            table.insert(retVal, node.path:str())

            local childOpenDirs = self:_extractOpenDirs(node)
            if #childOpenDirs > 0 then
                for _, dir in ipairs(childOpenDirs) do
                    table.insert(retVal, dir)
                end
            end
        end
    end

    return retVal
end

function NERDTreeProject:getHiddenDirs()
    return self._hiddenDirs
end

function NERDTreeProject:getName()
    return self._name
end

function NERDTreeProject:getOpenDirs()
    return self._openDirs
end

function NERDTreeProject:getRootPath()
    return self._rootPath
end

function NERDTreeProject:hideDir(path)
    if self:isHidden(path) then
        return
    end

    table.insert(self._hiddenDirs, path)
    self:rebuildHiddenRegex()
end

function NERDTreeProject:isHidden(path)
    for _, dir in ipairs(self._hiddenDirs) do
        if dir == path then
            return true
        end
    end
    return false
end

function NERDTreeProject:open()
    vim.fn.NERDTreeCreatorCreateTabTree(self:getRootPath():str())

    for _, dir in ipairs(self:getOpenDirs()) do
        local p = vim.fn.NERDTreePathNew(dir)
        vim.fn.NERDTreeRootReveal(p, { open = 1 })
    end

    vim.fn.setbufvar(vim.fn.bufnr(), "NERDTree.__currentProject", self)
    vim.fn.NERDTreeRender()
end

function NERDTreeProject:rebuildHiddenRegex()
    local hiddenDirs = {}
    for _, dir in ipairs(self._hiddenDirs) do
        table.insert(hiddenDirs, dir .. "\\.*")
    end
    self._hiddenRegex = "\\M(" .. table.concat(hiddenDirs, "|") .. ")"
end

function NERDTreeProject:unhideDir(path)
    if not self:isHidden(path) then
        return
    end

    for i, dir in ipairs(self._hiddenDirs) do
        if dir == path then
            table.remove(self._hiddenDirs, i)
            break
        end
    end

    self:rebuildHiddenRegex()
end

function NERDTreeProject:update(nerdtree)
    if not nerdtree.root.path:equals(self:getRootPath()) then
        return
    end

    self._openDirs = self:_extractOpenDirs(nerdtree.root)
    self:Write()
end

-- 过滤函数
local function ProjectPathFilter(params)
    local nerdtree = params.nerdtree

    if not nerdtree.__currentProject then
        return
    end

    if #nerdtree.__currentProject._hiddenDirs == 0 then
        return 0
    end

    local p = params.path

    return p:str():match(nerdtree.__currentProject._hiddenRegex)
end

-- 添加菜单项
vim.fn.NERDTreeAddPathFilter("ProjectPathFilter")

local projectMenu = vim.fn.NERDTreeAddSubmenu({ text = "(p)rojects", shortcut = "p" })
vim.fn.NERDTreeAddMenuItem({
    text = "(h)ide directory",
    shortcut = "h",
    parent = projectMenu,
    callback = function()
        local node = vim.fn.NERDTreeDirNodeGetSelected()
        if node then
            vim.fn.NERDTreeProjectHideDir(node.path:str())
            vim.fn.NERDTreeRender()
        end
    end
})

vim.fn.NERDTreeAddMenuItem({
    text = "(u)nhide directory",
    shortcut = "u",
    parent = projectMenu,
    callback = function()
        local node = vim.fn.NERDTreeDirNodeGetSelected()
        if node then
            vim.fn.NERDTreeProjectUnhideDir(node.path:str())
            vim.fn.NERDTreeRender()
        end
    end
})

vim.api.nvim_create_user_command("NERDTreeProjectSave", function(opts)
    vim.g.NERDTreeProject:Add(opts.args, vim.b.NERDTree)
end, { nargs = 1 })

vim.api.nvim_create_user_command("NERDTreeProjectLoad", function(opts)
    vim.g.NERDTreeProject:Open(opts.args)
end, { nargs = 1, complete = "customlist,NERDTreeCompleteProjectNames" })

vim.api.nvim_create_user_command("NERDTreeProjectRm", function(opts)
    vim.g.NERDTreeProject:Remove(opts.args)
end, { nargs = 1, complete = "customlist,NERDTreeCompleteProjectNames" })

vim.api.nvim_create_user_command("NERDTreeProjectLoadFromCWD", function()
    vim.g.NERDTreeProject:LoadFromCWD()
end, { nargs = 0 })

