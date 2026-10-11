--[[

    w0rmerVNGine 2.0 RC3

    ----------------------

    Lightweight Visual Novel Engine for LÖVE

    Features:

      - Dialogue

      - Choices / branching

      - Conditions / flags

      - Variables

      - Character sprites

      - Backgrounds

      - Music / SFX

      - UTF-8 safe typewriter

      - Click / keyboard controls

      - Auto mode

      - Skip mode

      - Save / Load

      - Restart

      - Fullscreen

      - Resizable window

      - Fade transitions

      - Story validation

      - Missing asset protection

      - No arbitrary Lua execution from save files

      - No external dependencies

    Authoring:

      Edit story.lua

--]]

local story = require("story")

local utf8 = require("utf8")

------------------------------------------------------------

-- CONFIGURATION

------------------------------------------------------------

local CONFIG = {

    title = "",
    startScene = nil,

    width = 1280,

    height = 720,

    dialogueHeight = 190,

    dialoguePadding = 28,

    nameFontSize = 28,

    dialogueFontSize = 25,

    choiceFontSize = 24,

    typewriterSpeed = 0.025,

    autoDelay = 1.8,

    choiceWidth = 900,

    choiceHeight = 62,

    choiceSpacing = 14,

    transitionSpeed = 4.0,

    masterVolume = 1.0,

    musicVolume = 0.7,

    sfxVolume = 1.0,

    voiceVolume = 1.0,

    saveFile = "save.dat",
    settingsFile = "settings.dat",
    saveSlots = 3

}

------------------------------------------------------------

-- UTILITIES

------------------------------------------------------------

local function clamp(value, minimum, maximum)

    return math.max(minimum, math.min(maximum, value))

end

local function utf8Length(text)

    if not text or text == "" then

        return 0

    end

    return utf8.len(text) or #text

end

-- LÖVE's utf8 library does NOT provide utf8.sub().

-- This implements a UTF-8 safe substring using utf8.offset().

local function utf8Sub(text, first, last)

    if not text or text == "" then

        return ""

    end

    first = first or 1

    if first < 1 then

        first = 1

    end

    local startByte = utf8.offset(text, first)

    if not startByte then

        return ""

    end

    local endByte

    if last then

        local nextByte = utf8.offset(text, last + 1)

        if nextByte then

            endByte = nextByte - 1

        else

            endByte = #text

        end

    else

        endByte = #text

    end

    return text:sub(startByte, endByte)

end

local function fileExists(path)

    if not path or path == "" then

        return false

    end

    return love.filesystem.getInfo(path) ~= nil

end

local function shallowCopy(source)

    local result = {}

    for key, value in pairs(source or {}) do

        result[key] = value

    end

    return result

end

local function serializeValue(value)

    if type(value) == "boolean" then

        return "bool:" .. tostring(value)

    elseif type(value) == "number" then

        return "number:" .. tostring(value)

    elseif type(value) == "string" then

        value = value:gsub("%%", "%%25")

        value = value:gsub("\n", "%%0A")

        value = value:gsub("\r", "%%0D")

        value = value:gsub("=", "%%3D")

        return "string:" .. value

    end

    return nil

end

local function deserializeValue(value)

    if not value then

        return nil

    end

    local valueType, data = value:match("^(%w+):(.*)$")

    if valueType == "bool" then

        return data == "true"

    elseif valueType == "number" then

        return tonumber(data)

    elseif valueType == "string" then

        data = data:gsub("%%3D", "=")

        data = data:gsub("%%0D", "\r")

        data = data:gsub("%%0A", "\n")

        data = data:gsub("%%25", "%%")

        return data

    end

    return nil

end

------------------------------------------------------------

-- GAME STATE

------------------------------------------------------------

local Game = {

    width = CONFIG.width,

    height = CONFIG.height,

    scene = "cover",

    vars = {},

    backgroundCache = {},

    spriteCache = {},

    audioCache = {},

    activeSprites = {},
    characterState = {},
    history = {},
    backlogOpen = false,

    fonts = {},

    text = "",

    textVisible = 0,

    typing = false,

    hoveredChoice = 1,

    choiceRects = {},

    autoMode = false,

    autoTimer = 0,

    skipMode = false,

    currentMusic = nil,

    currentMusicPath = nil,

    currentVoice = nil,

    fullscreen = false,

    transition = {

        active = false,

        alpha = 0,

        direction = 0,

        nextScene = nil

    },

    statusMessage = "",

    statusTimer = 0,
    selectedSaveSlot = 1,
    uiSounds = {},
    uiSoundInstances = {},
    oneShotAudio = {},
    settingsSelection = 1,
    unlockedEndings = {}

}

------------------------------------------------------------

-- BUILT-IN UI AUDIO (generated with LÖVE SoundData; no SFX files required)

------------------------------------------------------------

function Game:initializeUISounds()
    local rate = 22050
    local function tone(frequency, duration, volume, endFrequency)
        local samples = math.max(1, math.floor(rate * duration))
        local data = love.sound.newSoundData(samples, rate, 16, 1)
        for i = 0, samples - 1 do
            local t = i / rate
            local progress = i / samples
            local freq = frequency + ((endFrequency or frequency) - frequency) * progress
            local envelope = math.min(1, progress * 18) * math.max(0, 1 - progress) ^ 2
            local sample = math.sin(2 * math.pi * freq * t) * envelope * volume
            data:setSample(i, sample)
        end
        return love.audio.newSource(data, "static")
    end
    local ok, result = pcall(function()
        self.uiSounds.move = tone(720, 0.045, 0.18, 980)
        self.uiSounds.select = tone(520, 0.085, 0.28, 980)
        self.uiSounds.back = tone(520, 0.075, 0.22, 320)
        self.uiSounds.error = tone(180, 0.12, 0.22, 130)
    end)
    if not ok then
        self.uiSounds = {}
        print("[w0rmerVNGine] UI sound synthesis unavailable: " .. tostring(result))
    else
        print("[w0rmerVNGine] Built-in UI sounds ready (LÖVE SoundData; no external SFX required).")
    end
end

function Game:playUISound(name)
    local template = self.uiSounds and self.uiSounds[name]
    if not template then return end
    local ok, source = pcall(function() return template:clone() end)
    if not ok or not source then return end
    source:setVolume(clamp(CONFIG.masterVolume * CONFIG.sfxVolume, 0, 1))
    pcall(function() source:play() end)
    self.uiSoundInstances[#self.uiSoundInstances + 1] = source
end

function Game:updateOneShotAudio()
    local function prune(list)
        for i = #list, 1, -1 do
            local source = list[i]
            local ok, playing = pcall(function() return source:isPlaying() end)
            if not ok or not playing then table.remove(list, i) end
        end
    end
    prune(self.uiSoundInstances)
    prune(self.oneShotAudio)
end

function Game:loadSettings()
    if not love.filesystem.getInfo(CONFIG.settingsFile) then return end
    local data = love.filesystem.read(CONFIG.settingsFile)
    if not data then return end
    local ranges = {
        masterVolume = {0, 1}, musicVolume = {0, 1}, sfxVolume = {0, 1}, voiceVolume = {0, 1},
        typewriterSpeed = {0.005, 0.12}, autoDelay = {0.2, 8}
    }
    for key, value in data:gmatch("([%w_]+)=([%d%.%-]+)") do
        local range = ranges[key]
        local number = tonumber(value)
        if range and number then CONFIG[key] = clamp(number, range[1], range[2]) end
    end
    if self.currentMusic then self.currentMusic:setVolume(clamp(CONFIG.masterVolume * CONFIG.musicVolume, 0, 1)) end
    if self.currentVoice then self.currentVoice:setVolume(clamp(CONFIG.masterVolume * CONFIG.voiceVolume, 0, 1)) end
    print("[w0rmerVNGine] Settings loaded.")
end

function Game:saveSettings()
    local data = table.concat({
        "masterVolume=" .. CONFIG.masterVolume,
        "musicVolume=" .. CONFIG.musicVolume,
        "sfxVolume=" .. CONFIG.sfxVolume,
        "voiceVolume=" .. CONFIG.voiceVolume,
        "typewriterSpeed=" .. CONFIG.typewriterSpeed,
        "autoDelay=" .. CONFIG.autoDelay
    }, "\n")
    local ok, err = love.filesystem.write(CONFIG.settingsFile, data)
    if not ok then self:status("Settings could not be saved: " .. tostring(err)) end
end

function Game:loadEndings()
    self.unlockedEndings = {}
    local data = love.filesystem.read("endings.dat")
    if not data then return end
    for id in data:gmatch("([^\r\n]+)") do
        if id:match("^[%w_%-]+$") then self.unlockedEndings[id] = true end
    end
end

function Game:saveEndings()
    local ids = {}
    for id, unlocked in pairs(self.unlockedEndings) do
        if unlocked and type(id) == "string" and id:match("^[%w_%-]+$") then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local ok, err = love.filesystem.write("endings.dat", table.concat(ids, "\n"))
    if not ok then print("[w0rmerVNGine] Could not save ending progress: " .. tostring(err)) end
end

function Game:unlockEnding(sceneId)
    if type(sceneId) ~= "string" then return end
    if not self.unlockedEndings[sceneId] then
        self.unlockedEndings[sceneId] = true
        self:saveEndings()
        print("[w0rmerVNGine] Ending unlocked: " .. sceneId)
    end
end

function Game:hasSaveSlot(slot)
    local path = "save_slot_" .. tostring(slot) .. ".dat"
    if love.filesystem.getInfo(path) then return true end
    return slot == 1 and love.filesystem.getInfo(CONFIG.saveFile) ~= nil or false
end

function Game:getSavePath(slot)
    slot = tonumber(slot) or self.selectedSaveSlot or 1
    slot = math.floor(clamp(slot, 1, CONFIG.saveSlots))
    return "save_slot_" .. tostring(slot) .. ".dat", slot
end

------------------------------------------------------------

-- STATUS MESSAGE

------------------------------------------------------------

function Game:status(message)

    self.statusMessage = message or ""

    self.statusTimer = 2.5

    if message and message ~= "" then

        print("[w0rmerVNGine] " .. message)

    end

end

------------------------------------------------------------

-- ASSET LOADING

------------------------------------------------------------

function Game:loadImage(path, cache)

    if not path or path == "" then

        return nil

    end

    cache = cache or self.backgroundCache

    if cache[path] ~= nil then

        return cache[path]

    end

    if not fileExists(path) then

        print("[w0rmerVNGine] Missing image: " .. tostring(path))

        cache[path] = false

        return nil

    end

    local success, image = pcall(function()

        return love.graphics.newImage(path)

    end)

    if not success then

        print("[w0rmerVNGine] Failed to load image: " .. tostring(path))

        cache[path] = false

        return nil

    end

    image:setFilter("linear", "linear")

    cache[path] = image

    return image

end

function Game:loadAudio(path, audioType)

    if not path or path == "" then

        return nil

    end

    local cacheKey = audioType .. ":" .. path

    if self.audioCache[cacheKey] ~= nil then

        return self.audioCache[cacheKey]

    end

    if not fileExists(path) then

        print("[w0rmerVNGine] Missing audio: " .. tostring(path))

        self.audioCache[cacheKey] = false

        return nil

    end

    local success, source = pcall(function()

        return love.audio.newSource(path, audioType)

    end)

    if not success then

        print("[w0rmerVNGine] Failed to load audio: " .. tostring(path))

        self.audioCache[cacheKey] = false

        return nil

    end

    self.audioCache[cacheKey] = source

    return source

end

------------------------------------------------------------

-- FONTS

------------------------------------------------------------

function Game:loadFonts()

    self.fonts.name = love.graphics.newFont(CONFIG.nameFontSize)

    self.fonts.dialogue = love.graphics.newFont(CONFIG.dialogueFontSize)

    self.fonts.choice = love.graphics.newFont(CONFIG.choiceFontSize)

    self.fonts.title = love.graphics.newFont(64)

    self.fonts.subtitle = love.graphics.newFont(28)
    self.fonts.menuTitle = love.graphics.newFont(54)
    self.fonts.menuItem = love.graphics.newFont(22)
    self.fonts.menuHint = love.graphics.newFont(13)

end

------------------------------------------------------------

-- VARIABLES

------------------------------------------------------------

function Game:setVariables(values)

    if not values then

        return

    end

    for key, value in pairs(values) do

        self.vars[key] = value

    end

end

function Game:getVariable(name)

    return self.vars[name]

end

function Game:evaluateCondition(condition)

    if condition == nil then

        return true

    end

    if type(condition) == "boolean" then

        return condition

    end

    if type(condition) == "function" then

        local success, result = pcall(condition, self.vars)

        if not success then

            print("[w0rmerVNGine] Condition error: " .. tostring(result))

            return false

        end

        return result == true

    end

    if type(condition) == "string" then

        return self.vars[condition] == true

    end

    return false

end

------------------------------------------------------------

-- AUDIO

------------------------------------------------------------

function Game:stopMusic()

    if self.currentMusic then

        pcall(function()

            self.currentMusic:stop()

        end)

        self.currentMusic = nil

    end

    self.currentMusicPath = nil

end

function Game:playMusic(path)

    if not path or path == "" then

        return

    end

    if self.currentMusicPath == path and self.currentMusic then

        return

    end

    self:stopMusic()

    local source = self:loadAudio(path, "stream")

    if not source then

        return

    end

    source:setLooping(true)

    source:setVolume(

        CONFIG.masterVolume * CONFIG.musicVolume

    )

    local success = pcall(function()

        source:play()

    end)

    if success then

        self.currentMusic = source

        self.currentMusicPath = path

    end

end

function Game:playSFX(path)

    if not path or path == "" then

        return

    end

    local source = self:loadAudio(path, "static")

    if not source then

        return

    end

    local clone = source:clone()

    clone:setVolume(

        CONFIG.masterVolume * CONFIG.sfxVolume

    )

    clone:play()
    self.oneShotAudio[#self.oneShotAudio + 1] = clone

end

function Game:stopVoice()
    if self.currentVoice then pcall(function() self.currentVoice:stop() end) end
    self.currentVoice = nil
end

function Game:playVoice(path)
    self:stopVoice()
    if type(path) ~= "string" or path == "" then return end
    local template = self:loadAudio(path, "static")
    if not template then return end
    local ok, source = pcall(function() return template:clone() end)
    if not ok or not source then
        print("[w0rmerVNGine] Failed to prepare voice line: " .. tostring(path))
        return
    end
    source:setVolume(clamp(CONFIG.masterVolume * CONFIG.voiceVolume, 0, 1))
    local played, err = pcall(function() source:play() end)
    if played then self.currentVoice = source
    else print("[w0rmerVNGine] Failed to play voice line " .. tostring(path) .. ": " .. tostring(err)) end
end

------------------------------------------------------------

-- BACKGROUND

------------------------------------------------------------

function Game:getBackground(scene)

    if not scene then

        return nil

    end

    if scene.background then

        return scene.background

    end

    -- Backwards-compatible authoring style:

    -- image = "background.png"

    if scene.image then

        return scene.image

    end

    return nil

end

function Game:drawBackground(scene)

    local path = self:getBackground(scene)

    if not path then

        love.graphics.clear(0.035, 0.035, 0.045, 1)

        return

    end

    local image = self:loadImage(path, self.backgroundCache)

    if not image then

        love.graphics.clear(0.035, 0.035, 0.045, 1)

        return

    end

    local imageWidth = image:getWidth()

    local imageHeight = image:getHeight()

    local scaleX = self.width / imageWidth

    local scaleY = self.height / imageHeight

    local scale = math.max(scaleX, scaleY)

    local drawWidth = imageWidth * scale

    local drawHeight = imageHeight * scale

    local x = (self.width - drawWidth) / 2

    local y = (self.height - drawHeight) / 2

    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.draw(

        image,

        x,

        y,

        0,

        scale,

        scale

    )

end

------------------------------------------------------------

-- SPRITES / CHARACTER MODELS

------------------------------------------------------------

local CHARACTER_ROOT = "assets/characters/"

local CHARACTER_EXPRESSIONS = {
    neutral = true,
    happy = true,
    worried = true,
    sad = true,
    angry = true,
    surprised = true,
    shocked = true
}

local function normalizeAssetPath(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    path = path:gsub("\\", "/")

    if path:sub(1, 1) == "/" then
        path = path:sub(2)
    end

    return path
end

local function normalizeCharacterName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    name = name:gsub("\\", "/")
    name = name:gsub("^.*/", "")
    name = name:gsub("%.png$", "")
    name = name:lower()

    return name
end

function Game:resolveCharacterImage(sprite)
    if type(sprite) == "string" then
        sprite = { image = sprite }
    end

    if type(sprite) ~= "table" then
        return nil
    end

    -- Explicit image path.
    local explicit = sprite.image

    if type(explicit) == "string" and explicit ~= "" then
        explicit = normalizeAssetPath(explicit)

        if not explicit:match("%.png$") then
            explicit = explicit .. ".png"
        end

        if fileExists(explicit) then
            return explicit
        end

        if not explicit:match("^assets/") then
            local candidate = CHARACTER_ROOT .. explicit

            if fileExists(candidate) then
                return candidate
            end
        end
    end

    -- Support image = "maya_neutral" and image = "maya_neutral.png".
    local imageName = normalizeCharacterName(explicit)

    if imageName then
        local candidate = CHARACTER_ROOT .. imageName .. ".png"

        if fileExists(candidate) then
            return candidate
        end
    end

    local name =
        sprite.character
        or sprite.name
        or sprite.id
        or sprite.char

    local expression =
        sprite.expression
        or sprite.pose
        or sprite.mood
        or "neutral"

    name = normalizeCharacterName(name)
    expression = tostring(expression):lower()

    if not name then
        return nil
    end

    -- A complete character filename supplied as the name.
    if name:match("_neutral$")
        or name:match("_happy$")
        or name:match("_worried$")
        or name:match("_sad$")
        or name:match("_angry$")
        or name:match("_surprised$")
        or name:match("_shocked$")
    then
        local candidate = CHARACTER_ROOT .. name .. ".png"

        if fileExists(candidate) then
            return candidate
        end
    end

    if not CHARACTER_EXPRESSIONS[expression] then
        expression = "neutral"
    end

    local candidate =
        CHARACTER_ROOT .. name .. "_" .. expression .. ".png"

    if fileExists(candidate) then
        return candidate
    end

    -- Always try neutral as the final fallback for a valid character.
    local neutral = CHARACTER_ROOT .. name .. "_neutral.png"

    if fileExists(neutral) then
        return neutral
    end

    return nil
end

function Game:getSceneSprites(scene)
    if not scene then return {} end
    -- Legacy scenes can still supply a complete sprite list.
    if type(scene.sprites) == "table" then return scene.sprites end
    -- New authoring model: characters persist and scenes patch only what changes.
    return self.activeSprites or {}
end

local function copyTable(source)
    local result = {}
    if type(source) == "table" then
        for key, value in pairs(source) do result[key] = value end
    end
    return result
end

function Game:resetCharacters()
    self.activeSprites = {}
    self.characterState = {}
    local definitions = story.characterDefinitions or {}
    for id, definition in pairs(definitions) do
        if type(definition) == "table" then
            local sprite = copyTable(definition)
            sprite.character = sprite.character or id
            sprite.id = id
            sprite.visible = sprite.visible ~= false
            self.characterState[id] = sprite
            table.insert(self.activeSprites, sprite)
        end
    end
end

function Game:applyCharacterChanges(scene)
    if not scene then return end
    -- Legacy sprite arrays intentionally retain their original per-scene behavior.
    if type(scene.sprites) == "table" then
        self.activeSprites = scene.sprites
        self.characterState = {}
        for _, sprite in pairs(scene.sprites) do
            if type(sprite) == "table" then
                local id = sprite.id or sprite.character or sprite.name
                if id then self.characterState[id] = sprite end
            end
        end
        return
    end

    local changes = scene.characterChanges or scene.characters
    if type(changes) ~= "table" then return end
    for id, patch in pairs(changes) do
        if type(patch) == "table" then
            local current = self.characterState[id]
            if patch.visible == false and not current then
                -- An unknown character can be explicitly hidden without creating a sprite.
            else
                if not current then
                    current = { id = id, character = id, visible = true }
                    self.characterState[id] = current
                    table.insert(self.activeSprites, current)
                end
                for key, value in pairs(patch) do current[key] = value end
                current.id = id
                current.character = current.character or id
            end
        end
    end
end

function Game:resolveSpriteX(sprite)
    local x = sprite.x or sprite.position or sprite.pos

    if type(x) == "number" then
        return x
    end

    if type(x) == "string" then
        x = x:lower()

        if x == "left" then
            return self.width * 0.25
        elseif x == "center" or x == "middle" then
            return self.width * 0.50
        elseif x == "right" then
            return self.width * 0.75
        end

        local numeric = tonumber(x)

        if numeric then
            return numeric
        end
    end

    return self.width * 0.50
end

function Game:resolveSpriteY(sprite)
    if type(sprite.y) == "number" then
        return sprite.y
    end

    if type(sprite.offsetY) == "number" then
        return self.height + sprite.offsetY
    end

    -- Character artwork is full-body. Bottom-anchor it to the scene.
    return self.height
end

function Game:resolveSpriteScale(sprite, image)
    if type(sprite.scale) == "number" then
        return sprite.scale
    end

    if type(sprite.size) == "number" then
        return sprite.size
    end

    -- 600x1000 character art -> roughly 560px tall at 720p.
    return (self.height * 0.78) / image:getHeight()
end

function Game:drawSprites(scene)
    local sprites = self:getSceneSprites(scene)

    if type(sprites) ~= "table" then
        return
    end

    local drawList = {}

    -- Support both array-style and named-table character definitions.
    for key, value in pairs(sprites) do
        local sprite = value

        if type(value) == "string" then
            sprite = { image = value }
        end

        if type(sprite) == "table" then
            local copy = {}

            for k, v in pairs(sprite) do
                copy[k] = v
            end

            copy.__order = tonumber(key) or (#drawList + 1)
            table.insert(drawList, copy)
        end
    end

    table.sort(drawList, function(a, b)
        local az = tonumber(a.z)
            or tonumber(a.layer)
            or tonumber(a.__order)
            or 0

        local bz = tonumber(b.z)
            or tonumber(b.layer)
            or tonumber(b.__order)
            or 0

        return az < bz
    end)

    for _, sprite in ipairs(drawList) do
        if sprite.visible ~= false then
            local path = self:resolveCharacterImage(sprite)

            if path then
                local image = self:loadImage(
                    path,
                    self.spriteCache
                )

                if image then
                    local x = self:resolveSpriteX(sprite)
                    local y = self:resolveSpriteY(sprite)
                    local scale = self:resolveSpriteScale(sprite, image)

                    local alpha = tonumber(sprite.alpha) or 1

                    if sprite.dim == true then
                        alpha = alpha * 0.45
                    elseif type(sprite.dim) == "number" then
                        alpha = alpha * clamp(sprite.dim, 0, 1)
                    end

                    alpha = clamp(alpha, 0, 1)

                    local sx = math.abs(scale)
                    local sy = math.abs(scale)

                    if sprite.mirror
                        or sprite.flip
                        or sprite.flipped
                    then
                        sx = -sx
                    end

                    love.graphics.setColor(
                        1,
                        1,
                        1,
                        alpha
                    )

                    love.graphics.draw(
                        image,
                        x,
                        y,
                        tonumber(sprite.rotation) or 0,
                        sx,
                        sy,
                        image:getWidth() / 2,
                        image:getHeight()
                    )
                else
                    print(
                        "[w0rmerVNGine] Could not load character: "
                        .. tostring(path)
                    )
                end
            else
                print(
                    "[w0rmerVNGine] No character asset resolved for sprite."
                )
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

------------------------------------------------------------

-- TYPEWRITER

------------------------------------------------------------

function Game:startTyping(text)

    self.text = text or ""

    self.textVisible = 0

    self.typing = true

    self.autoTimer = 0

end

function Game:finishTyping()

    self.textVisible = utf8Length(self.text)

    self.typing = false

    self.autoTimer = 0

end

function Game:getVisibleText()

    if not self.typing then

        return self.text

    end

    return utf8Sub(

        self.text,

        1,

        self.textVisible

    )

end

------------------------------------------------------------

-- SCENE

------------------------------------------------------------

function Game:getScene()

    return story[self.scene]

end

function Game:applySceneSet(scene)

    if scene and scene.set then

        self:setVariables(scene.set)

    end

end

function Game:prepareScene(scene, restoring)

    if not scene then

        return

    end

    if not restoring then
        self:applySceneSet(scene)
        self:applyCharacterChanges(scene)
    end
    if scene.type == "ending" then self:unlockEnding(self.scene) end
    self:stopVoice()

    if scene.type == "dialogue" and type(scene.text) == "string" then
        local entry = { scene = self.scene, speaker = scene.speaker or scene.name or "", text = scene.text }
        local previous = self.history[#self.history]
        if not previous or previous.scene ~= entry.scene then
            self.history[#self.history + 1] = entry
            if #self.history > 250 then table.remove(self.history, 1) end
        end
    end

    self.hoveredChoice = 1

    self.choiceRects = {}

    self.autoTimer = 0

    if scene.type == "dialogue" then

        self:startTyping(scene.text or "")

    elseif scene.type == "choice" then

        self.text = scene.text or ""

        self.textVisible = utf8Length(self.text)

        self.typing = false

    elseif scene.type == "cover" then

        self.text = scene.text or ""

        self.textVisible = utf8Length(self.text)

        self.typing = false

    elseif scene.type == "ending" then

        self.text = scene.text or ""

        self.textVisible = utf8Length(self.text)

        self.typing = false

    end

    if scene.music then

        self:playMusic(scene.music)

    end

    if scene.sfx then

        self:playSFX(scene.sfx)

    end
    if scene.voice then self:playVoice(scene.voice) end

end

function Game:goToScene(sceneName, instant)

    if not sceneName then

        return

    end

    if not story[sceneName] then

        self:status(

            "Unknown scene: " .. tostring(sceneName)

        )

        return

    end

    if self.scene == sceneName and not instant then

        return

    end

    if instant then

        self.scene = sceneName

        self:prepareScene(story[self.scene])

        return

    end

    self.transition.nextScene = sceneName

    self.transition.active = true

    self.transition.direction = 1

end

function Game:finishTransition()

    local nextScene = self.transition.nextScene

    if nextScene then

        self.scene = nextScene

        self:prepareScene(story[self.scene])

    end

    self.transition.nextScene = nil

    self.transition.direction = -1

end

------------------------------------------------------------

-- ADVANCING

------------------------------------------------------------

function Game:advance()

    local scene = self:getScene()

    if not scene then

        return

    end

    if self.typing then

        self:finishTyping()

        return

    end

    self.autoTimer = 0

    if scene.type == "dialogue" then

        local destination = scene.next or scene.target
        if destination then
            self:goToScene(destination)
        else
            self:status("Dialogue has no next scene.")

        end

    elseif scene.type == "cover" then

        local destination = scene.next or scene.target
        if destination then self:goToScene(destination) end

    elseif scene.type == "ending" then

        -- Endings intentionally stop here.

    elseif scene.type == "choice" then

        self:selectChoice(self.hoveredChoice)

    end

end

------------------------------------------------------------

-- CHOICES

------------------------------------------------------------

function Game:getAvailableChoices(scene)

    local result = {}

    if not scene or not scene.choices then

        return result

    end

    for index, choice in ipairs(scene.choices) do

        if self:evaluateCondition(choice.condition) then

            table.insert(result, {

                sourceIndex = index,

                data = choice

            })

        end

    end

    return result

end

function Game:selectChoice(index)

    local scene = self:getScene()

    if not scene or scene.type ~= "choice" then

        return

    end

    local choices = self:getAvailableChoices(scene)

    local selected = choices[index]

    if not selected then

        return

    end

    local choice = selected.data
    self:playUISound("select")

    local choiceSet = choice.set or choice.setFlags
    if choiceSet then
        self:setVariables(choiceSet)
    end

    if choice.sfx then

        self:playSFX(choice.sfx)

    end

    local destination = choice.next or choice.target
    if destination then
        self:goToScene(destination)
    end

end

function Game:getChoiceRects(scene)

    self.choiceRects = {}

    if not scene or scene.type ~= "choice" then

        return self.choiceRects

    end

    local choices = self:getAvailableChoices(scene)

    local totalHeight =

        (#choices * CONFIG.choiceHeight) +

        (math.max(0, #choices - 1) * CONFIG.choiceSpacing)

    local startY =

        self.height / 2 -

        totalHeight / 2 +

        20

    local x =

        (self.width - CONFIG.choiceWidth) / 2

    for index = 1, #choices do

        local y =

            startY +

            (index - 1) *

            (CONFIG.choiceHeight + CONFIG.choiceSpacing)

        self.choiceRects[index] = {

            x = x,

            y = y,

            width = CONFIG.choiceWidth,

            height = CONFIG.choiceHeight

        }

    end

    return self.choiceRects

end

function Game:updateChoiceHover(mouseX, mouseY)

    local scene = self:getScene()

    if not scene or scene.type ~= "choice" then

        return

    end

    local rects = self:getChoiceRects(scene)

    for index, rect in ipairs(rects) do

        if mouseX >= rect.x

            and mouseX <= rect.x + rect.width

            and mouseY >= rect.y

            and mouseY <= rect.y + rect.height then

            if self.hoveredChoice ~= index then
                self.hoveredChoice = index
                self:playUISound("move")
            end
            return

        end

    end

end

------------------------------------------------------------

-- AUTO MODE

------------------------------------------------------------

function Game:toggleAuto()

    self.autoMode = not self.autoMode

    self.autoTimer = 0

    if self.autoMode then

        self:status("AUTO ON")

    else

        self:status("AUTO OFF")

    end

end

function Game:updateAuto(dt)

    if not self.autoMode then

        return

    end

    local scene = self:getScene()

    if not scene then

        return

    end

    if self.typing then

        return

    end

    if scene.type ~= "dialogue" then

        return

    end

    self.autoTimer = self.autoTimer + dt

    if self.autoTimer >= CONFIG.autoDelay then

        self:advance()

    end

end

------------------------------------------------------------

-- SAVE

------------------------------------------------------------

function Game:save(slot)

    local path
    path, slot = self:getSavePath(slot)
    local lines = {}

    table.insert(

        lines,

        "W0RMERVNGINE_SAVE=2"

    )

    table.insert(

        lines,

        "scene=" .. tostring(self.scene)

    )
    table.insert(lines, "slot=" .. tostring(slot))
    table.insert(lines, "textVisible=" .. tostring(self.textVisible or 0))
    table.insert(lines, "typing=" .. tostring(self.typing == true))
    table.insert(lines, "autoMode=" .. tostring(self.autoMode == true))

    for key, value in pairs(self.vars) do

        local serialized = serializeValue(value)

        if serialized and type(key) == "string" and key:match("^[%w_%-]+$") then

            table.insert(

                lines,

                "var." .. tostring(key) .. "=" .. serialized

            )

        end

    end

    local persistentSpriteFields = {
        "character", "expression", "x", "y", "offsetY", "scale", "size",
        "mirror", "flip", "flipped", "alpha", "dim", "rotation", "z",
        "layer", "visible", "image"
    }
    for id, sprite in pairs(self.characterState or {}) do
        if type(id) == "string" and id:match("^[%w_%-]+$") and type(sprite) == "table" then
            for _, field in ipairs(persistentSpriteFields) do
                local serialized = serializeValue(sprite[field])
                if serialized then
                    table.insert(lines, "char." .. id .. "." .. field .. "=" .. serialized)
                end
            end
        end
    end

    local data = table.concat(lines, "\n")

    local success, message =

        love.filesystem.write(

            path,

            data

        )

    if success then

        if slot == 1 then pcall(love.filesystem.write, CONFIG.saveFile, data) end -- legacy compatibility
        self.selectedSaveSlot = slot
        self:status("Game saved to slot " .. tostring(slot) .. ".")

        return true

    end

    self:status(

        "Save failed: " .. tostring(message)

    )

    return false

end

------------------------------------------------------------

-- LOAD

------------------------------------------------------------

function Game:loadSave(slot)

    local path
    path, slot = self:getSavePath(slot)
    if not love.filesystem.getInfo(path) and slot == 1 and love.filesystem.getInfo(CONFIG.saveFile) then path = CONFIG.saveFile end
    if not love.filesystem.getInfo(path) then

        self:status("No save file found.")

        return false

    end

    local data, message =

        love.filesystem.read(path)

    if not data then

        self:status(

            "Load failed: " .. tostring(message)

        )

        return false

    end

    local savedScene = nil
    local savedVars = {}
    local savedCharacters = {}
    local validHeader = false
    local savedTextVisible = nil
    local savedTyping = false
    local savedAutoMode = false

    for line in data:gmatch("[^\r\n]+") do
        if line == "W0RMERVNGINE_SAVE=1" or line == "W0RMERVNGINE_SAVE=2" then
            validHeader = true
        else

            local visibleValue = line:match("^textVisible=(%d+)$")
            if visibleValue then savedTextVisible = tonumber(visibleValue) end
            local typingValue = line:match("^typing=(%a+)$")
            if typingValue then savedTyping = typingValue == "true" end
            local autoValue = line:match("^autoMode=(%a+)$")
            if autoValue then savedAutoMode = autoValue == "true" end

            local sceneValue =

                line:match("^scene=(.+)$")

            if sceneValue then

                savedScene = sceneValue

            end

            local key, value =

                line:match("^var%.([^=]+)=(.+)$")

            if key and value then
                local decoded = deserializeValue(value)
                if decoded ~= nil then savedVars[key] = decoded end
            end

            local charId, field, charValue = line:match("^char%.([%w_%-]+)%.([%w_]+)=(.+)$")
            if charId and field and charValue then
                local decoded = deserializeValue(charValue)
                if decoded ~= nil then
                    savedCharacters[charId] = savedCharacters[charId] or {}
                    savedCharacters[charId][field] = decoded
                end
            end
        end
    end

    if not validHeader or not savedScene or type(story[savedScene]) ~= "table" or not story[savedScene].type then

        self:status("Save file is invalid.")

        return false

    end

    self.vars = savedVars
    self.history = {}
    self.selectedSaveSlot = slot
    self.autoMode = savedAutoMode
    self.skipMode = false
    self:resetCharacters()
    for id, fields in pairs(savedCharacters) do
        local sprite = self.characterState[id]
        if not sprite then
            sprite = { id = id, character = id, visible = true }
            self.characterState[id] = sprite
            table.insert(self.activeSprites, sprite)
        end
        for field, value in pairs(fields) do sprite[field] = value end
    end

    self.scene = savedScene

    self.transition.active = false

    self.transition.nextScene = nil

    self.transition.alpha = 0

    self:prepareScene(story[self.scene], true)
    if savedTextVisible ~= nil then
        self.textVisible = clamp(savedTextVisible, 0, utf8Length(self.text))
        self.typing = savedTyping and self.textVisible < utf8Length(self.text)
        if not self.typing then self.textVisible = utf8Length(self.text) end
    end

    self:status("Game loaded from slot " .. tostring(slot) .. ".")

    return true

end

------------------------------------------------------------

-- RESTART

------------------------------------------------------------

function Game:getStartScene()
    local configured = story.startScene or CONFIG.startScene
    if type(configured) == "string" then
        local candidate = story[configured]
        if type(candidate) == "table" and candidate.type then return configured end
    end
    if type(story.cover) == "table" and story.cover.type then return "cover" end
    local names = {}
    for name, scene in pairs(story) do
        if type(name) == "string" and type(scene) == "table" and scene.type then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names[1]
end

function Game:restart()

    self.vars = {}
    self.history = {}
    self.backlogOpen = false

    self.autoMode = false

    self.skipMode = false

    self.transition.active = false

    self.transition.nextScene = nil

    self.transition.alpha = 0

    self:stopMusic()

    self:resetCharacters()

    self.scene = self:getStartScene()

    if self.scene then

        self:prepareScene(

            story[self.scene]

        )

    end

    self:status("Game restarted.")

end

------------------------------------------------------------

-- VALIDATION

------------------------------------------------------------

function Game:validateStory()
    local errors, warnings, sceneCount = 0, 0, 0
    print("\n========================================")
    print(" w0rmerVNGine 2.0 RC3 STORY VALIDATION")
    print("========================================")
    if type(story) ~= "table" then
        print("[ERROR] story.lua did not return a table.")
        return false
    end

    local metadata = { startScene = true, characterDefinitions = true, meta = true, config = true }
    local validTypes = { dialogue = true, choice = true, cover = true, ending = true }
    local scenes = {}
    for name, value in pairs(story) do
        if type(name) == "string" and not metadata[name] then
            if type(value) ~= "table" then
                print("[ERROR] Scene '" .. name .. "' must be a table.")
                errors = errors + 1
            else
                sceneCount = sceneCount + 1
                scenes[name] = value
                if type(value.type) ~= "string" then
                    print("[ERROR] Scene '" .. name .. "' has no string type.")
                    errors = errors + 1
                elseif not validTypes[value.type] then
                    print("[ERROR] Scene '" .. name .. "' uses unknown type '" .. tostring(value.type) .. "'.")
                    errors = errors + 1
                end
            end
        end
    end

    local function checkTarget(from, target, label)
        if target ~= nil and (type(target) ~= "string" or not scenes[target]) then
            print("[ERROR] " .. label .. " in scene '" .. tostring(from) .. "' points to missing scene '" .. tostring(target) .. "'.")
            errors = errors + 1
        end
    end

    for name, scene in pairs(scenes) do
        if scene.type == "dialogue" then
            if type(scene.text) ~= "string" then
                print("[ERROR] Dialogue '" .. name .. "' has no string text.")
                errors = errors + 1
            end
            checkTarget(name, scene.next or scene.target, "next")
        elseif scene.type == "choice" then
            if type(scene.text) ~= "string" then
                print("[WARNING] Choice scene '" .. name .. "' has no prompt text.")
                warnings = warnings + 1
            end
            if type(scene.choices) ~= "table" or #scene.choices == 0 then
                print("[ERROR] Choice '" .. name .. "' has no choices.")
                errors = errors + 1
            else
                for index, choice in ipairs(scene.choices) do
                    if type(choice) ~= "table" then
                        print("[ERROR] Choice '" .. name .. "' option " .. index .. " must be a table.")
                        errors = errors + 1
                    else
                        if type(choice.text) ~= "string" then
                            print("[ERROR] Choice '" .. name .. "' option " .. index .. " has no string text.")
                            errors = errors + 1
                        end
                        checkTarget(name, choice.next or choice.target, "choice destination")
                    end
                end
            end
        elseif scene.type == "cover" then
            checkTarget(name, scene.next or scene.target, "next")
            if not (scene.next or scene.target) then
                print("[WARNING] Cover '" .. name .. "' has no next destination.")
                warnings = warnings + 1
            end
        elseif scene.type == "ending" then
            checkTarget(name, scene.next or scene.target, "next")
        end
        if scene.background ~= nil and type(scene.background) ~= "string" then
            print("[ERROR] Scene '" .. name .. "' background must be a path string.")
            errors = errors + 1
        end
        if scene.characterChanges ~= nil and type(scene.characterChanges) ~= "table" then
            print("[ERROR] Scene '" .. name .. "' characterChanges must be a table.")
            errors = errors + 1
        end
    end

    if story.characterDefinitions ~= nil and type(story.characterDefinitions) ~= "table" then
        print("[ERROR] characterDefinitions must be a table.")
        errors = errors + 1
    else
        for id, definition in pairs(story.characterDefinitions or {}) do
            if type(definition) ~= "table" then
                print("[ERROR] Character definition '" .. tostring(id) .. "' must be a table.")
                errors = errors + 1
            end
        end
    end

    local start = self:getStartScene()
    if not start or not scenes[start] then
        print("[ERROR] No valid start scene. Set story.startScene to an existing scene ID.")
        errors = errors + 1
    else
        local reached, stack = {}, { start }
        while #stack > 0 do
            local name = table.remove(stack)
            if not reached[name] and scenes[name] then
                reached[name] = true
                local scene = scenes[name]
                local nextScene = scene.next or scene.target
                if type(nextScene) == "string" and scenes[nextScene] then stack[#stack + 1] = nextScene end
                for _, choice in ipairs(type(scene.choices) == "table" and scene.choices or {}) do
                    local target = type(choice) == "table" and (choice.next or choice.target) or nil
                    if type(target) == "string" and scenes[target] then
                        stack[#stack + 1] = target
                    end
                end
            end
        end
        for name in pairs(scenes) do
            if not reached[name] then
                print("[WARNING] Scene '" .. name .. "' is unreachable from start scene '" .. start .. "'.")
                warnings = warnings + 1
            end
        end
    end

    print("\nScenes:   " .. tostring(sceneCount))
    print("Errors:   " .. tostring(errors))
    print("Warnings: " .. tostring(warnings))
    print(errors == 0 and "\nVALIDATION PASSED." or "\nVALIDATION FAILED.")
    print("========================================\n")
    return errors == 0
end

------------------------------------------------------------

-- DRAW HELPERS

------------------------------------------------------------

function Game:drawPanel(x, y, width, height, alpha)

    love.graphics.setColor(

        0.02,

        0.02,

        0.025,

        alpha or 0.90

    )

    love.graphics.rectangle(

        "fill",

        x,

        y,

        width,

        height,

        8,

        8

    )

    love.graphics.setColor(

        1,

        1,

        1,

        0.12

    )

    love.graphics.setLineWidth(1)

    love.graphics.rectangle(

        "line",

        x,

        y,

        width,

        height,

        8,

        8

    )

    love.graphics.setColor(1, 1, 1, 1)

end

function Game:drawDialogue(scene)

    local panelY =

        self.height - CONFIG.dialogueHeight

    self:drawPanel(

        0,

        panelY,

        self.width,

        CONFIG.dialogueHeight,

        0.92

    )

    local speakerName = scene.speaker or scene.name
    if speakerName and speakerName ~= "" then

        love.graphics.setFont(

            self.fonts.name

        )

        love.graphics.setColor(

            1,

            1,

            1,

            1

        )

        love.graphics.print(

            speakerName,

            CONFIG.dialoguePadding,

            panelY + 18

        )

    end

    love.graphics.setFont(

        self.fonts.dialogue

    )

    local textY = panelY + 62

    love.graphics.setColor(

        0.92,

        0.92,

        0.94,

        1

    )

    love.graphics.printf(

        self:getVisibleText(),

        CONFIG.dialoguePadding,

        textY,

        self.width -

            CONFIG.dialoguePadding * 2,

        "left"

    )

    love.graphics.setColor(

        1,

        1,

        1,

        1

    )

end

function Game:drawChoice(scene)

    local choices =

        self:getAvailableChoices(scene)

    love.graphics.setFont(

        self.fonts.dialogue

    )

    love.graphics.setColor(

        1,

        1,

        1,

        1

    )

    love.graphics.printf(

        scene.text or "",

        100,

        80,

        self.width - 200,

        "center"

    )

    local rects =

        self:getChoiceRects(scene)

    for index, choice in ipairs(choices) do

        local rect = rects[index]

        if rect then

            local selected =

                index == self.hoveredChoice

            if selected then

                love.graphics.setColor(

                    0.16,

                    0.16,

                    0.20,

                    0.98

                )

            else

                love.graphics.setColor(

                    0.07,

                    0.07,

                    0.09,

                    0.94

                )

            end

            love.graphics.rectangle(

                "fill",

                rect.x,

                rect.y,

                rect.width,

                rect.height,

                8,

                8

            )

            love.graphics.setColor(

                1,

                1,

                1,

                selected and 0.65 or 0.18

            )

            love.graphics.rectangle(

                "line",

                rect.x,

                rect.y,

                rect.width,

                rect.height,

                8,

                8

            )

            love.graphics.setFont(

                self.fonts.choice

            )

            love.graphics.setColor(

                1,

                1,

                1,

                1

            )

            love.graphics.printf(

                tostring(choice.data.text),

                rect.x + 20,

                rect.y + 18,

                rect.width - 40,

                "center"

            )

        end

    end

    love.graphics.setColor(

        1,

        1,

        1,

        1

    )

end

function Game:drawCover(scene)

    love.graphics.setFont(

        self.fonts.title

    )

    love.graphics.setColor(

        1,

        1,

        1,

        1

    )

    love.graphics.printf(

        scene.text or "",

        80,

        self.height * 0.32,

        self.width - 160,

        "center"

    )

    love.graphics.setFont(

        self.fonts.subtitle

    )

    love.graphics.setColor(

        1,

        1,

        1,

        0.55

    )

    love.graphics.printf(

        "CLICK OR PRESS ENTER",

        80,

        self.height * 0.72,

        self.width - 160,

        "center"

    )

    love.graphics.setColor(

        1,

        1,

        1,

        1

    )

end

function Game:drawEnding(scene)

    love.graphics.setFont(

        self.fonts.title

    )

    love.graphics.setColor(

        1,

        1,

        1,

        1

    )

    love.graphics.printf(

        "THE END",

        80,

        self.height * 0.22,

        self.width - 160,

        "center"

    )

    love.graphics.setFont(

        self.fonts.dialogue

    )

    love.graphics.printf(

        scene.text or "",

        140,

        self.height * 0.42,

        self.width - 280,

        "center"

    )

    love.graphics.setFont(

        self.fonts.subtitle

    )

    love.graphics.setColor(

        1,

        1,

        1,

        0.55

    )

    love.graphics.printf(

        "R = RESTART",

        100,

        self.height - 90,

        self.width - 200,

        "center"

    )

    love.graphics.setColor(

        1,

        1,

        1,

        1

    )

end

function Game:drawStatus()

    if self.statusTimer <= 0 then

        return

    end

    local alpha =

        clamp(self.statusTimer, 0, 1)

    love.graphics.setFont(

        self.fonts.subtitle

    )

    love.graphics.setColor(

        1,

        1,

        1,

        alpha

    )

    love.graphics.print(

        self.statusMessage,

        20,

        20

    )

    love.graphics.setColor(

        1,

        1,

        1,

        1

    )

end

------------------------------------------------------------

-- TRANSITION

------------------------------------------------------------

function Game:updateTransition(dt)

    if not self.transition.active then

        return

    end

    self.transition.alpha =

        self.transition.alpha +

        self.transition.direction *

        CONFIG.transitionSpeed *

        dt

    self.transition.alpha =

        clamp(

            self.transition.alpha,

            0,

            1

        )

    if self.transition.direction == 1

        and self.transition.alpha >= 1 then

        self:finishTransition()

    elseif self.transition.direction == -1

        and self.transition.alpha <= 0 then

        self.transition.active = false

    end

end

function Game:drawTransition()

    if not self.transition.active

        and self.transition.alpha <= 0 then

        return

    end

    love.graphics.setColor(

        0,

        0,

        0,

        self.transition.alpha

    )

    love.graphics.rectangle(

        "fill",

        0,

        0,

        self.width,

        self.height

    )

    love.graphics.setColor(

        1,

        1,

        1,

        1

    )

end

------------------------------------------------------------

-- UPDATE

------------------------------------------------------------

function Game:update(dt)

    self:updateOneShotAudio()
    if self.backlogOpen then return end

    if self.statusTimer > 0 then

        self.statusTimer =

            self.statusTimer - dt

    end

    self:updateTransition(dt)

    if self.transition.active then

        return

    end

    if self.typing then

        local length =

            utf8Length(self.text)

        if self.skipMode then

            self:finishTyping()

        else

            self.textVisible =

                self.textVisible +

                dt / CONFIG.typewriterSpeed

            self.textVisible =

                math.floor(self.textVisible)

            if self.textVisible >= length then

                self:finishTyping()

            end

        end

    end

    self:updateAuto(dt)

end

------------------------------------------------------------

-- DRAW

------------------------------------------------------------

function Game:draw()

    local scene = self:getScene()

    if not scene then

        love.graphics.clear(

            0.03,

            0.03,

            0.04,

            1

        )

        love.graphics.setColor(

            1,

            0.3,

            0.3,

            1

        )

        love.graphics.setFont(

            self.fonts.dialogue

        )

        love.graphics.printf(

            "Invalid scene: " ..

            tostring(self.scene),

            40,

            40,

            self.width - 80,

            "center"

        )

        return

    end

    love.graphics.clear(

        0.03,

        0.03,

        0.04,

        1

    )

    self:drawBackground(scene)

    self:drawSprites(scene)

    if scene.type == "dialogue" then

        self:drawDialogue(scene)

    elseif scene.type == "choice" then

        self:drawChoice(scene)

    elseif scene.type == "cover" then

        self:drawCover(scene)

    elseif scene.type == "ending" then

        self:drawEnding(scene)

    end

    self:drawStatus()
    self:drawTransition()
    if self.backlogOpen then self:drawBacklog() end

end

function Game:drawBacklog()
    love.graphics.setColor(0, 0, 0, 0.88)
    love.graphics.rectangle("fill", 24, 24, self.width - 48, self.height - 48, 10, 10)
    love.graphics.setColor(1, 0.35, 0.42, 1)
    love.graphics.setFont(self.fonts.name)
    love.graphics.printf("DIALOGUE BACKLOG", 48, 42, self.width - 96, "left")
    love.graphics.setColor(1, 1, 1, 0.72)
    love.graphics.setFont(self.fonts.choice)
    love.graphics.printf("Press B or BACKSPACE to return", 48, self.height - 74, self.width - 96, "left")

    local y = 92
    local bottom = self.height - 104
    local first = math.max(1, #self.history - 9)
    for index = first, #self.history do
        local entry = self.history[index]
        local speaker = entry.speaker ~= "" and (entry.speaker .. ": ") or ""
        local line = speaker .. entry.text
        love.graphics.setColor(1, 0.62, 0.66, 1)
        love.graphics.setFont(self.fonts.name)
        love.graphics.printf(entry.speaker ~= "" and entry.speaker or "Narration", 48, y, self.width - 96, "left")
        y = y + 30
        love.graphics.setColor(1, 1, 1, 0.92)
        love.graphics.setFont(self.fonts.dialogue)
        love.graphics.printf(entry.text, 48, y, self.width - 96, "left")
        local _, wrapped = self.fonts.dialogue:getWrap(entry.text, self.width - 96)
        y = y + math.max(1, #wrapped) * (CONFIG.dialogueFontSize + 4) + 18
        if y > bottom then break end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

------------------------------------------------------------

-- KEYBOARD

------------------------------------------------------------

function Game:keypressed(key)

    if key == "b" or (self.backlogOpen and key == "backspace") then
        self.backlogOpen = not self.backlogOpen
        return
    end
    if self.backlogOpen then return end

    if key == "escape" then

        love.event.quit()

        return

    end

    if key == "f5" then

        self:save(self.selectedSaveSlot)

        return

    end

    if key == "f9" then

        self:loadSave(self.selectedSaveSlot)

        return

    end

    if key == "f11" then

        self.fullscreen = not self.fullscreen

        love.window.setFullscreen(

            self.fullscreen

        )

        return

    end

    if key == "r" then

        self:restart()

        return

    end

    if key == "a" then

        self:toggleAuto()

        return

    end

    if key == "s"

        or key == "lctrl"

        or key == "rctrl" then

        self.skipMode = true

        self:advance()

        return

    end

    if key == "up" then

        local scene = self:getScene()

        if scene and scene.type == "choice" then

            local count =

                #self:getAvailableChoices(scene)

            if count > 0 then

                self.hoveredChoice =

                    self.hoveredChoice - 1
                self:playUISound("move")

                if self.hoveredChoice < 1 then

                    self.hoveredChoice = count

                end

            end

        end

        return

    end

    if key == "down" then

        local scene = self:getScene()

        if scene and scene.type == "choice" then

            local count =

                #self:getAvailableChoices(scene)

            if count > 0 then

                self.hoveredChoice =

                    self.hoveredChoice + 1
                self:playUISound("move")

                if self.hoveredChoice > count then

                    self.hoveredChoice = 1

                end

            end

        end

        return

    end

    if key == "return"

        or key == "space" then

        self:playUISound("select")
        self.skipMode = false

        self:advance()

        return

    end

    local number = tonumber(key)

    if number then

        local scene = self:getScene()

        if scene and scene.type == "choice" then

            self:selectChoice(number)

        end

    end

end

------------------------------------------------------------

-- MOUSE

------------------------------------------------------------

function Game:mousepressed(x, y, button)

    if self.backlogOpen then return end

    if button ~= 1 then

        return

    end

    local scene = self:getScene()

    if not scene then

        return

    end

    if scene.type == "choice" then

        local rects =

            self:getChoiceRects(scene)

        for index, rect in ipairs(rects) do

            if x >= rect.x

                and x <= rect.x + rect.width

                and y >= rect.y

                and y <= rect.y + rect.height then

                self:selectChoice(index)

                return

            end

        end

        return

    end

    self:playUISound("select")
    self:advance()

end

function Game:mousereleased(x, y, button)

    -- Reserved for future UI features.

end

function Game:mousemoved(x, y)

    self:updateChoiceHover(x, y)

end

------------------------------------------------------------

-- WINDOW

------------------------------------------------------------

function Game:resize(width, height)

    self.width = width

    self.height = height

end

------------------------------------------------------------

-- LÖVE CALLBACKS

------------------------------------------------------------

function Game:validateAssets()
    print("[w0rmerVNGine] Asset validation started.")
    local seen = {}
    local missingCharacterRequests = {}
    local function reportMissingCharacter(sprite, context)
        local character = type(sprite) == "table" and (sprite.character or sprite.name or sprite.id or sprite.char) or sprite
        local expression = type(sprite) == "table" and (sprite.expression or sprite.mood or sprite.pose or "neutral") or "neutral"
        local key = tostring(character) .. ":" .. tostring(expression)
        if not missingCharacterRequests[key] then
            missingCharacterRequests[key] = true
            print("[w0rmerVNGine] Asset MISSING (character): " .. tostring(character) .. " expression=" .. tostring(expression) .. (context and (" [" .. context .. "]") or ""))
        end
    end
    local function check(path, kind)
        if type(path) ~= "string" or path == "" or seen[path] then return end
        seen[path] = true
        if fileExists(path) then
            print("[w0rmerVNGine] Asset OK (" .. kind .. "): " .. path)
        else
            print("[w0rmerVNGine] Asset MISSING (" .. kind .. "): " .. path)
        end
    end
    local backgroundFiles = love.filesystem.getDirectoryItems("assets/backgrounds") or {}
    local cgCount = 0
    for _, filename in ipairs(backgroundFiles) do
        if filename:lower():match("^cg[_%-].+%.png$") then
            check("assets/backgrounds/" .. filename, "CG gallery image")
            cgCount = cgCount + 1
        end
    end
    if cgCount == 0 then print("[w0rmerVNGine] INFO: No CG gallery images found; add assets/backgrounds/cg_<name>.png to populate the gallery.") end
    for name, scene in pairs(story) do
        if type(scene) == "table" and scene.type then
            if scene.background then check(scene.background, "background") end
            if scene.music then check(scene.music, "music") end
            if scene.sfx then check(scene.sfx, "sound effect") end
            if scene.voice then check(scene.voice, "voice line") end
            if type(scene.choices) == "table" then
                for _, choice in ipairs(scene.choices) do
                    if type(choice) == "table" and choice.sfx then check(choice.sfx, "choice sound effect") end
                end
            end
            local lists = { scene.sprites }
            local changes = scene.characterChanges or scene.characters
            if type(changes) == "table" then
                for id, patch in pairs(changes) do
                    if type(patch) == "table" then
                        local sprite = copyTable(story.characterDefinitions and story.characterDefinitions[id] or {})
                        for k, v in pairs(patch) do sprite[k] = v end
                        sprite.character = sprite.character or id
                        local resolved = self:resolveCharacterImage(sprite)
                        if resolved then check(resolved, "character")
                        else reportMissingCharacter(sprite, "scene " .. tostring(name)) end
                    end
                end
            end
            for _, list in ipairs(lists) do
                if type(list) == "table" then
                    for _, sprite in pairs(list) do
                        if type(sprite) == "table" then
                            local resolved = self:resolveCharacterImage(sprite)
                            if resolved then check(resolved, "character")
                            else reportMissingCharacter(sprite, "scene " .. tostring(name)) end
                        elseif type(sprite) == "string" then
                            local resolved = self:resolveCharacterImage(sprite)
                            if resolved then check(resolved, "character")
                            else reportMissingCharacter(sprite, "scene " .. tostring(name)) end
                        end
                    end
                end
            end
        end
    end
    -- Check all expression variants for declared character definitions, but don't hard-code demo characters.
    local expressions = { "neutral", "happy", "worried", "sad", "angry", "surprised", "shocked" }
    for id, definition in pairs(story.characterDefinitions or {}) do
        if type(definition) == "table" then
            for _, expression in ipairs(expressions) do
                local sprite = copyTable(definition)
                sprite.character = sprite.character or id
                sprite.expression = expression
                local base = CHARACTER_ROOT .. tostring(sprite.character):lower() .. "_" .. expression .. ".png"
                check(base, "character expression")
                if not fileExists(base) and expression ~= "neutral" then
                    local neutral = CHARACTER_ROOT .. tostring(sprite.character):lower() .. "_neutral.png"
                    if fileExists(neutral) then
                        print("[w0rmerVNGine] FALLBACK AVAILABLE: " .. base .. " -> " .. neutral)
                    end
                end
            end
        end
    end
    print("[w0rmerVNGine] Asset validation complete.")
end

function love.load()

    love.window.setTitle(CONFIG.title)

    love.window.setMode(

        CONFIG.width,

        CONFIG.height,

        {

            resizable = true,

            vsync = 1,

            minwidth = 800,

            minheight = 450

        }

    )

    Game.width,

    Game.height =

        love.graphics.getDimensions()

    Game:loadFonts()

    Game:validateStory()
    Game:resetCharacters()
    Game:validateAssets()
    -- The title/menu wrapper owns the first transition into gameplay. Do not prepare
    -- the start scene here: doing so would fire story audio and scene-entry effects
    -- underneath the intro/menu. New Game and Continue prepare the selected scene.
    Game.scene = Game:getStartScene()
    Game.text = ""
    Game.textVisible = 0
    Game.typing = false
    Game.history = {}
    Game.vars = {}

    print("")

    print("========================================")

    print(" w0rmerVNGine 2.0 RC3")

    print("========================================")

    print("Controls:")

    print("  ENTER / SPACE / CLICK  Advance")

    print("  UP / DOWN              Select choice")

    print("  1-9                    Choose option")

    print("  A                      Auto")
    print("  B                      Dialogue backlog")

    print("  S / CTRL               Skip")

    print("  F5                     Save to selected slot")

    print("  F9                     Load selected slot")
    print("  Title menu              Gallery, endings, settings, save slots")

    print("  F11                    Fullscreen")

    print("  R                      Restart")

    print("  ESC                    Quit")

    print("========================================")

    print("")

end

function love.update(dt)

    Game:update(dt)

end

function love.draw()

    Game:draw()

end

function love.keypressed(key, scancode, isrepeat)

    Game:keypressed(key)

end

function love.keyreleased(key, scancode)

    if key == "s"

        or key == "lctrl"

        or key == "rctrl" then

        Game.skipMode = false

    end

end

function love.mousepressed(x, y, button)

    Game:mousepressed(x, y, button)

end

function love.mousereleased(x, y, button)

    Game:mousereleased(x, y, button)

end

function love.mousemoved(x, y, dx, dy, istouch)

    Game:mousemoved(x, y)

end

function love.resize(width, height)

    Game:resize(width, height)

end

------------------------------------------------------------
-- W0RMERVNGINE 2.0: INTRO, TITLE MENU, LOAD SLOTS AND SETTINGS
-- Uses only built-in LÖVE APIs. UI sounds are synthesized at runtime.
-- Existing assets/backgrounds and assets/audio paths are preserved.
------------------------------------------------------------

local _w0rmerOriginalLoad = love.load
local _w0rmerOriginalDraw = love.draw
local _w0rmerOriginalKeypressed = love.keypressed
local _w0rmerOriginalMousepressed = love.mousepressed
local _w0rmerOriginalMousemoved = love.mousemoved
local _w0rmerOriginalUpdate = love.update
local _w0rmerOriginalResize = love.resize
local _w0rmerScreen = "intro"
local _w0rmerIntroAudio = nil
local _w0rmerIntroImage = nil
local _w0rmerMenuImage = nil
local _w0rmerMenuSelection = 1
local _w0rmerLoadSelection = 1
local _w0rmerIntroTimer = 0
local _w0rmerGalleryImages = {}
local _w0rmerGallerySelection = 1
local _w0rmerEndingItems = {}
local _w0rmerEndingSelection = 1
local _w0rmerMenuItems = {"NEW GAME", "CONTINUE", "LOAD GAME", "CG GALLERY", "ENDINGS", "SETTINGS", "SAVE SLOT", "QUIT"}
local _w0rmerSettingsItems = {"MASTER VOLUME", "MUSIC VOLUME", "SFX VOLUME", "VOICE VOLUME", "TEXT SPEED", "AUTO DELAY", "BACK"}

local function _w0rmerLoadImage(path)
    if not love.filesystem.getInfo(path) then
        print("[w0rmerVNGine] Asset MISSING (menu/intro image): " .. path)
        return nil
    end
    local ok, image = pcall(love.graphics.newImage, path)
    if ok then
        image:setFilter("linear", "linear")
        print("[w0rmerVNGine] Asset OK (menu/intro image): " .. path)
        return image
    end
    print("[w0rmerVNGine] Asset ERROR (menu/intro image): " .. path .. " :: " .. tostring(image))
    return nil
end

local function _w0rmerDrawFull(image)
    if not image then
        love.graphics.clear(0.025, 0.025, 0.04, 1)
        return
    end
    local iw, ih = image:getDimensions()
    local sw, sh = love.graphics.getDimensions()
    local scale = math.max(sw / iw, sh / ih)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, (sw - iw * scale) / 2, (sh - ih * scale) / 2, 0, scale, scale)
end

local function _w0rmerEnterMenu()
    if _w0rmerScreen ~= "intro" then return end
    _w0rmerScreen = "menu"
    if _w0rmerIntroAudio then pcall(function() _w0rmerIntroAudio:stop() end) end
    Game:playUISound("select")
end

local function _w0rmerStartGame()
    _w0rmerScreen = "story"
    Game.vars = {}
    Game.history = {}
    Game.backlogOpen = false
    Game.autoMode = false
    Game.skipMode = false
    Game:stopMusic()
    Game:stopVoice()
    for _, source in ipairs(Game.oneShotAudio or {}) do pcall(function() source:stop() end) end
    Game.oneShotAudio = {}
    Game:resetCharacters()
    local start = Game:getStartScene()
    if start then Game:goToScene(start, true) end
end

local function _w0rmerAdjustSetting(index, direction)
    local key, step, minimum, maximum
    if index == 1 then key, step, minimum, maximum = "masterVolume", 0.05, 0, 1
    elseif index == 2 then key, step, minimum, maximum = "musicVolume", 0.05, 0, 1
    elseif index == 3 then key, step, minimum, maximum = "sfxVolume", 0.05, 0, 1
    elseif index == 4 then key, step, minimum, maximum = "voiceVolume", 0.05, 0, 1
    elseif index == 5 then key, step, minimum, maximum = "typewriterSpeed", 0.005, 0.005, 0.12
    elseif index == 6 then key, step, minimum, maximum = "autoDelay", 0.2, 0.2, 8
    else return end
    CONFIG[key] = clamp(CONFIG[key] + step * direction, minimum, maximum)
    Game:saveSettings()
    if Game.currentMusic then Game.currentMusic:setVolume(clamp(CONFIG.masterVolume * CONFIG.musicVolume, 0, 1)) end
    if Game.currentVoice then Game.currentVoice:setVolume(clamp(CONFIG.masterVolume * CONFIG.voiceVolume, 0, 1)) end
    if _w0rmerIntroAudio then _w0rmerIntroAudio:setVolume(clamp(CONFIG.masterVolume * CONFIG.musicVolume, 0, 1)) end
    Game:playUISound("move")
end

local function _w0rmerRefreshGallery()
    _w0rmerGalleryImages = {}
    local files = love.filesystem.getDirectoryItems("assets/backgrounds") or {}
    table.sort(files)
    for _, filename in ipairs(files) do
        if filename:lower():match("^cg[_%-].+%.png$") then
            local path = "assets/backgrounds/" .. filename
            local image = _w0rmerLoadImage(path)
            if image then _w0rmerGalleryImages[#_w0rmerGalleryImages + 1] = {name = filename, image = image} end
        end
    end
    _w0rmerGallerySelection = math.max(1, math.min(_w0rmerGallerySelection, #_w0rmerGalleryImages))
end

local function _w0rmerRefreshEndings()
    _w0rmerEndingItems = {}
    for id, scene in pairs(story) do
        if type(scene) == "table" and scene.type == "ending" then
            _w0rmerEndingItems[#_w0rmerEndingItems + 1] = id
        end
    end
    table.sort(_w0rmerEndingItems)
    _w0rmerEndingSelection = math.max(1, math.min(_w0rmerEndingSelection, math.max(1, #_w0rmerEndingItems)))
end

local function _w0rmerGalleryMove(direction)
    if #_w0rmerGalleryImages == 0 then return end
    _w0rmerGallerySelection = ((_w0rmerGallerySelection - 1 + direction) % #_w0rmerGalleryImages) + 1
    Game:playUISound("move")
end

local function _w0rmerActivateMenu()
    local item = _w0rmerMenuItems[_w0rmerMenuSelection]
    Game:playUISound("select")
    if item == "NEW GAME" then
        _w0rmerStartGame()
    elseif item == "CONTINUE" then
        if Game:loadSave(Game.selectedSaveSlot) then _w0rmerScreen = "story" else Game:playUISound("error") end
    elseif item == "LOAD GAME" then
        _w0rmerScreen = "load"
        _w0rmerLoadSelection = 1
    elseif item == "CG GALLERY" then
        _w0rmerRefreshGallery()
        _w0rmerScreen = "gallery"
    elseif item == "ENDINGS" then
        _w0rmerRefreshEndings()
        _w0rmerScreen = "endings"
    elseif item == "SETTINGS" then
        _w0rmerScreen = "settings"
        Game.settingsSelection = 1
    elseif item == "SAVE SLOT" then
        Game.selectedSaveSlot = (Game.selectedSaveSlot % CONFIG.saveSlots) + 1
        Game:playUISound("move")
    elseif item == "QUIT" then
        love.event.quit()
    end
end

local function _w0rmerActivateLoad()
    if _w0rmerLoadSelection <= CONFIG.saveSlots then
        local slot = _w0rmerLoadSelection
        if Game:hasSaveSlot(slot) and Game:loadSave(slot) then
            _w0rmerScreen = "story"
        else
            Game:playUISound("error")
        end
    else
        _w0rmerScreen = "menu"
        Game:playUISound("back")
    end
end

love.load = function(...)
    Game:loadEndings()
    _w0rmerOriginalLoad(...)
    Game:initializeUISounds()
    Game:loadSettings()
    if _w0rmerIntroAudio then _w0rmerIntroAudio:setVolume(clamp(CONFIG.masterVolume, 0, 1)) end
    _w0rmerScreen = "intro"
    _w0rmerIntroTimer = 0
    _w0rmerIntroImage = _w0rmerLoadImage("assets/backgrounds/cover.png")
    _w0rmerMenuImage = _w0rmerLoadImage("assets/backgrounds/menu_bg.png")
    _w0rmerIntroAudio = nil
    if love.filesystem.getInfo("assets/audio/intro.ogg") then
        local ok, source = pcall(love.audio.newSource, "assets/audio/intro.ogg", "stream")
        if ok then
            print("[w0rmerVNGine] Asset OK (intro audio): assets/audio/intro.ogg")
            _w0rmerIntroAudio = source
            source:setLooping(false)
            source:setVolume(clamp(CONFIG.masterVolume * CONFIG.musicVolume, 0, 1))
            local played, playError = pcall(function() source:play() end)
            if not played then print("[w0rmerVNGine] Audio ERROR (intro): " .. tostring(playError)) end
        else
            print("[w0rmerVNGine] Asset ERROR (intro audio): " .. tostring(source))
        end
    else
        print("[w0rmerVNGine] Asset MISSING (intro audio): assets/audio/intro.ogg (intro remains skippable)")
    end
end

love.update = function(dt, ...)
    Game:updateOneShotAudio()
    if _w0rmerScreen == "intro" then
        _w0rmerIntroTimer = _w0rmerIntroTimer + dt
        if _w0rmerIntroAudio then
            local ok, playing = pcall(function() return _w0rmerIntroAudio:isPlaying() end)
            if not ok or not playing then _w0rmerEnterMenu() end
        elseif _w0rmerIntroTimer >= 1.5 then
            _w0rmerEnterMenu()
        end
        return
    end
    if _w0rmerScreen == "story" then return _w0rmerOriginalUpdate(dt, ...) end
end

local function _w0rmerDrawMenu()
    _w0rmerDrawFull(_w0rmerMenuImage)
    local w, h = love.graphics.getDimensions()
    love.graphics.setColor(0, 0, 0, 0.52)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(Game.fonts.menuTitle or Game.fonts.title)
    love.graphics.printf("c0deg0d", 40, h * 0.10, w - 80, "center")
    love.graphics.setFont(Game.fonts.subtitle)
    love.graphics.setColor(1, 1, 1, 0.76)
    love.graphics.printf("W0RMERVNGINE 2.0", 40, h * 0.10 + 58, w - 80, "center")
    local bw, bh, gap = math.min(400, w * 0.62), math.min(50, h * 0.07), math.min(8, h * 0.01)
    local x, y0 = (w - bw) / 2, h * 0.29
    for i, label in ipairs(_w0rmerMenuItems) do
        if label == "SAVE SLOT" then label = "SAVE SLOT: " .. tostring(Game.selectedSaveSlot) end
        local y = y0 + (i - 1) * (bh + gap)
        love.graphics.setColor(i == _w0rmerMenuSelection and 0.82 or 0.04, i == _w0rmerMenuSelection and 0.12 or 0.04, i == _w0rmerMenuSelection and 0.22 or 0.06, 0.94)
        love.graphics.rectangle("fill", x, y, bw, bh, 7, 7)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(Game.fonts.menuItem or Game.fonts.choice)
        love.graphics.printf(label, x + 8, y + 12, bw - 16, "center")
    end
    love.graphics.setColor(1, 1, 1, 0.62)
    love.graphics.setFont(Game.fonts.menuHint or Game.fonts.name)
    love.graphics.printf("UP / DOWN SELECT   ENTER CONFIRM   ESC BACK", 20, h - 32, w - 40, "center")
end

local function _w0rmerDrawLoad()
    local w, h = love.graphics.getDimensions()
    _w0rmerDrawFull(_w0rmerMenuImage)
    love.graphics.setColor(0, 0, 0, 0.76); love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1); love.graphics.setFont(Game.fonts.menuTitle or Game.fonts.title)
    love.graphics.printf("LOAD GAME", 40, h * 0.15, w - 80, "center")
    local labels = {}
    for slot = 1, CONFIG.saveSlots do labels[slot] = "SLOT " .. slot .. "   " .. (Game:hasSaveSlot(slot) and "LOAD SAVE" or "EMPTY") end
    labels[#labels + 1] = "BACK"
    local bw, bh, gap = math.min(520, w * 0.72), 58, 12
    local x, y0 = (w - bw) / 2, h * 0.34
    for i, label in ipairs(labels) do
        local y = y0 + (i - 1) * (bh + gap)
        love.graphics.setColor(i == _w0rmerLoadSelection and 0.82 or 0.04, i == _w0rmerLoadSelection and 0.12 or 0.04, i == _w0rmerLoadSelection and 0.22 or 0.06, 0.95)
        love.graphics.rectangle("fill", x, y, bw, bh, 7, 7)
        love.graphics.setColor(1, 1, 1, 1); love.graphics.setFont(Game.fonts.menuItem or Game.fonts.choice)
        love.graphics.printf(label, x + 8, y + 16, bw - 16, "center")
    end
    love.graphics.setColor(1, 1, 1, 0.65); love.graphics.setFont(Game.fonts.menuHint or Game.fonts.name)
    love.graphics.printf("UP / DOWN SELECT   ENTER LOAD   ESC BACK", 20, h - 32, w - 40, "center")
end

local function _w0rmerSettingValue(index)
    if index == 1 then return string.format("%d%%", math.floor(CONFIG.masterVolume * 100 + 0.5))
    elseif index == 2 then return string.format("%d%%", math.floor(CONFIG.musicVolume * 100 + 0.5))
    elseif index == 3 then return string.format("%d%%", math.floor(CONFIG.sfxVolume * 100 + 0.5))
    elseif index == 4 then return string.format("%d%%", math.floor(CONFIG.voiceVolume * 100 + 0.5))
    elseif index == 5 then return string.format("%.3fs / char", CONFIG.typewriterSpeed)
    elseif index == 6 then return string.format("%.1fs", CONFIG.autoDelay)
    end
    return "RETURN"
end

local function _w0rmerSettingsLayout()
    local w, h = love.graphics.getDimensions()
    local bw = math.min(650, w * 0.82)
    local gap = math.min(9, h * 0.012)
    local y0 = h * 0.28
    local available = h - y0 - 58
    local bh = math.min(54, math.max(26, (available - (#_w0rmerSettingsItems - 1) * gap) / #_w0rmerSettingsItems))
    return w, h, bw, bh, gap, (w - bw) / 2, y0
end

local function _w0rmerDrawSettings()
    local w, h, bw, bh, gap, x, y0 = _w0rmerSettingsLayout()
    _w0rmerDrawFull(_w0rmerMenuImage)
    love.graphics.setColor(0, 0, 0, 0.78); love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1); love.graphics.setFont(Game.fonts.menuTitle or Game.fonts.title)
    love.graphics.printf("SETTINGS", 40, h * 0.10, w - 80, "center")
    for i, label in ipairs(_w0rmerSettingsItems) do
        local y = y0 + (i - 1) * (bh + gap)
        love.graphics.setColor(i == Game.settingsSelection and 0.82 or 0.04, i == Game.settingsSelection and 0.12 or 0.04, i == Game.settingsSelection and 0.22 or 0.06, 0.95)
        love.graphics.rectangle("fill", x, y, bw, bh, 7, 7)
        love.graphics.setColor(1, 1, 1, 1); love.graphics.setFont(Game.fonts.menuItem or Game.fonts.choice)
        love.graphics.printf(label .. "     " .. _w0rmerSettingValue(i), x + 16, y + 16, bw - 32, "left")
    end
    love.graphics.setColor(1, 1, 1, 0.68); love.graphics.setFont(Game.fonts.menuHint or Game.fonts.name)
    love.graphics.printf("UP / DOWN SELECT   LEFT / RIGHT ADJUST   ENTER BACK", 20, h - 32, w - 40, "center")
end

local function _w0rmerDrawGallery()
    local w, h = love.graphics.getDimensions()
    local item = _w0rmerGalleryImages[_w0rmerGallerySelection]
    if item then _w0rmerDrawFull(item.image)
    else
        love.graphics.clear(0.025, 0.025, 0.04, 1)
        love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.setColor(0, 0, 0, 0.62)
    love.graphics.rectangle("fill", 0, 0, w, 76)
    love.graphics.rectangle("fill", 0, h - 70, w, 70)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(Game.fonts.menuItem or Game.fonts.choice)
    love.graphics.printf("CG GALLERY", 20, 18, w - 40, "center")
    love.graphics.setFont(Game.fonts.menuHint or Game.fonts.name)
    if item then
        love.graphics.printf(item.name .. "   (" .. _w0rmerGallerySelection .. "/" .. #_w0rmerGalleryImages .. ")", 20, h - 54, w - 40, "center")
    else
        love.graphics.printf("No CG images found. Add assets/backgrounds/cg_<name>.png", 20, h * 0.52, w - 40, "center")
        love.graphics.printf("Press ESC or ENTER to return", 20, h - 54, w - 40, "center")
    end
    love.graphics.setColor(1, 1, 1, 1)
end

local function _w0rmerDrawEndings()
    local w, h = love.graphics.getDimensions()
    _w0rmerDrawFull(_w0rmerMenuImage)
    love.graphics.setColor(0, 0, 0, 0.80); love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1); love.graphics.setFont(Game.fonts.menuTitle or Game.fonts.title)
    love.graphics.printf("ENDING RECORD", 30, h * 0.08, w - 60, "center")
    local total = #_w0rmerEndingItems
    local rowHeight = math.min(48, math.max(28, (h - 190) / math.max(1, math.min(total, 8))))
    local visible = math.min(total, 8)
    local first = math.max(1, math.min(_w0rmerEndingSelection - math.floor(visible / 2), total - visible + 1))
    local y = h * 0.24
    if total == 0 then
        love.graphics.setFont(Game.fonts.choice); love.graphics.printf("No ending scenes have been defined in story.lua.", 40, h * 0.48, w - 80, "center")
    else
        for i = first, math.min(total, first + visible - 1) do
            local id = _w0rmerEndingItems[i]
            local unlocked = Game.unlockedEndings[id] == true
            love.graphics.setColor(i == _w0rmerEndingSelection and 0.82 or 0.04, i == _w0rmerEndingSelection and 0.12 or 0.04, i == _w0rmerEndingSelection and 0.22 or 0.06, 0.94)
            love.graphics.rectangle("fill", w * 0.16, y, w * 0.68, rowHeight - 5, 6, 6)
            love.graphics.setColor(1, 1, 1, unlocked and 1 or 0.52)
            love.graphics.setFont(Game.fonts.menuItem or Game.fonts.choice)
            love.graphics.printf((unlocked and "UNLOCKED  " or "LOCKED  ") .. id, w * 0.18, y + math.max(5, (rowHeight - 26) / 2), w * 0.64, "center")
            y = y + rowHeight
        end
    end
    love.graphics.setColor(1, 1, 1, 0.68); love.graphics.setFont(Game.fonts.menuHint or Game.fonts.name)
    love.graphics.printf("UP / DOWN SELECT   ENTER / ESC BACK", 20, h - 32, w - 40, "center")
    love.graphics.setColor(1, 1, 1, 1)
end

love.draw = function(...)
    if _w0rmerScreen == "story" then return _w0rmerOriginalDraw(...) end
    love.graphics.clear(0.02, 0.02, 0.03, 1)
    if _w0rmerScreen == "intro" then _w0rmerDrawFull(_w0rmerIntroImage)
    elseif _w0rmerScreen == "menu" then _w0rmerDrawMenu()
    elseif _w0rmerScreen == "load" then _w0rmerDrawLoad()
    elseif _w0rmerScreen == "settings" then _w0rmerDrawSettings()
    elseif _w0rmerScreen == "gallery" then _w0rmerDrawGallery()
    elseif _w0rmerScreen == "endings" then _w0rmerDrawEndings() end
end

local function _w0rmerMoveSelection(direction, count, current)
    local nextValue = ((current - 1 + direction) % count) + 1
    if nextValue ~= current then Game:playUISound("move") end
    return nextValue
end

love.keypressed = function(key, scancode, isrepeat)
    if _w0rmerScreen == "intro" then _w0rmerEnterMenu(); return end
    if _w0rmerScreen == "menu" then
        if key == "up" or key == "w" then _w0rmerMenuSelection = _w0rmerMoveSelection(-1, #_w0rmerMenuItems, _w0rmerMenuSelection)
        elseif key == "down" or key == "s" then _w0rmerMenuSelection = _w0rmerMoveSelection(1, #_w0rmerMenuItems, _w0rmerMenuSelection)
        elseif (key == "left" or key == "right") and _w0rmerMenuItems[_w0rmerMenuSelection] == "SAVE SLOT" then
            local delta = key == "right" and 1 or -1
            Game.selectedSaveSlot = ((Game.selectedSaveSlot - 1 + delta) % CONFIG.saveSlots) + 1
            Game:playUISound("move")
        elseif key == "return" or key == "space" then _w0rmerActivateMenu()
        elseif key == "escape" then love.event.quit() end
        return
    elseif _w0rmerScreen == "load" then
        if key == "up" or key == "w" then _w0rmerLoadSelection = _w0rmerMoveSelection(-1, CONFIG.saveSlots + 1, _w0rmerLoadSelection)
        elseif key == "down" or key == "s" then _w0rmerLoadSelection = _w0rmerMoveSelection(1, CONFIG.saveSlots + 1, _w0rmerLoadSelection)
        elseif key == "return" or key == "space" then _w0rmerActivateLoad()
        elseif key == "escape" then _w0rmerScreen = "menu"; Game:playUISound("back") end
        return
    elseif _w0rmerScreen == "endings" then
        if key == "up" or key == "w" then
            if #_w0rmerEndingItems > 0 then _w0rmerEndingSelection = _w0rmerMoveSelection(-1, #_w0rmerEndingItems, _w0rmerEndingSelection) end
        elseif key == "down" or key == "s" then
            if #_w0rmerEndingItems > 0 then _w0rmerEndingSelection = _w0rmerMoveSelection(1, #_w0rmerEndingItems, _w0rmerEndingSelection) end
        elseif key == "return" or key == "space" or key == "escape" then _w0rmerScreen = "menu"; Game:playUISound("back") end
        return
    elseif _w0rmerScreen == "gallery" then
        if key == "left" or key == "up" then _w0rmerGalleryMove(-1)
        elseif key == "right" or key == "down" then _w0rmerGalleryMove(1)
        elseif key == "return" or key == "space" or key == "escape" then _w0rmerScreen = "menu"; Game:playUISound("back") end
        return
    elseif _w0rmerScreen == "settings" then
        if key == "up" or key == "w" then Game.settingsSelection = _w0rmerMoveSelection(-1, #_w0rmerSettingsItems, Game.settingsSelection)
        elseif key == "down" or key == "s" then Game.settingsSelection = _w0rmerMoveSelection(1, #_w0rmerSettingsItems, Game.settingsSelection)
        elseif key == "left" then _w0rmerAdjustSetting(Game.settingsSelection, -1)
        elseif key == "right" then _w0rmerAdjustSetting(Game.settingsSelection, 1)
        elseif key == "return" or key == "space" then
            if Game.settingsSelection == #_w0rmerSettingsItems then _w0rmerScreen = "menu"; Game:playUISound("back")
            else _w0rmerAdjustSetting(Game.settingsSelection, 1) end
        elseif key == "escape" then _w0rmerScreen = "menu"; Game:playUISound("back") end
        return
    end
    if key == "escape" then
        _w0rmerScreen = "menu"
        Game:stopMusic()
        Game:stopVoice()
        Game:playUISound("back")
        return
    end
    return _w0rmerOriginalKeypressed(key, scancode, isrepeat)
end

love.mousepressed = function(x, y, button, istouch, presses)
    if button ~= 1 then return end
    if _w0rmerScreen == "intro" then _w0rmerEnterMenu(); return end
    local w, h = love.graphics.getDimensions()
    if _w0rmerScreen == "menu" then
        local bw, bh, gap = math.min(400, w * 0.62), math.min(50, h * 0.07), math.min(8, h * 0.01)
        local bx, y0 = (w - bw) / 2, h * 0.29
        for i = 1, #_w0rmerMenuItems do
            local by = y0 + (i - 1) * (bh + gap)
            if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
                if _w0rmerMenuSelection ~= i then Game:playUISound("move") end
                _w0rmerMenuSelection = i; _w0rmerActivateMenu(); return
            end
        end
        return
    elseif _w0rmerScreen == "load" then
        local bw, bh, gap = math.min(520, w * 0.72), 58, 12
        local bx, y0 = (w - bw) / 2, h * 0.34
        for i = 1, CONFIG.saveSlots + 1 do
            local by = y0 + (i - 1) * (bh + gap)
            if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
                if _w0rmerLoadSelection ~= i then Game:playUISound("move") end
                _w0rmerLoadSelection = i; _w0rmerActivateLoad(); return
            end
        end
        return
    elseif _w0rmerScreen == "endings" then
        _w0rmerScreen = "menu"; Game:playUISound("back"); return
    elseif _w0rmerScreen == "gallery" then
        if x < w * 0.35 then _w0rmerGalleryMove(-1)
        elseif x > w * 0.65 then _w0rmerGalleryMove(1)
        else _w0rmerScreen = "menu"; Game:playUISound("back") end
        return
    elseif _w0rmerScreen == "settings" then
        local _, _, bw, bh, gap, bx, y0 = _w0rmerSettingsLayout()
        for i = 1, #_w0rmerSettingsItems do
            local by = y0 + (i - 1) * (bh + gap)
            if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
                if Game.settingsSelection ~= i then Game:playUISound("move") end
                Game.settingsSelection = i
                if i == #_w0rmerSettingsItems then _w0rmerScreen = "menu"; Game:playUISound("back")
                else _w0rmerAdjustSetting(i, x < bx + bw / 2 and -1 or 1) end
                return
            end
        end
        return
    end
    if _w0rmerScreen == "story" then return _w0rmerOriginalMousepressed(x, y, button, istouch, presses) end
end

love.mousemoved = function(x, y, dx, dy, istouch)
    if _w0rmerScreen == "menu" then
        local w, h = love.graphics.getDimensions()
        local bw, bh, gap = math.min(400, w * 0.62), math.min(50, h * 0.07), math.min(8, h * 0.01)
        local bx, y0 = (w - bw) / 2, h * 0.29
        for i = 1, #_w0rmerMenuItems do
            local by = y0 + (i - 1) * (bh + gap)
            if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
                if _w0rmerMenuSelection ~= i then Game:playUISound("move") end
                _w0rmerMenuSelection = i; return
            end
        end
    elseif _w0rmerScreen == "load" then
        local w, h = love.graphics.getDimensions()
        local bw, bh, gap = math.min(520, w * 0.72), 58, 12
        local bx, y0 = (w - bw) / 2, h * 0.34
        for i = 1, CONFIG.saveSlots + 1 do
            local by = y0 + (i - 1) * (bh + gap)
            if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
                if _w0rmerLoadSelection ~= i then Game:playUISound("move") end
                _w0rmerLoadSelection = i; return
            end
        end
    elseif _w0rmerScreen == "settings" then
        local w, h = love.graphics.getDimensions()
        local _, _, bw, bh, gap, bx, y0 = _w0rmerSettingsLayout()
        for i = 1, #_w0rmerSettingsItems do
            local by = y0 + (i - 1) * (bh + gap)
            if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
                if Game.settingsSelection ~= i then Game:playUISound("move") end
                Game.settingsSelection = i; return
            end
        end
    end
    if _w0rmerScreen == "story" and _w0rmerOriginalMousemoved then return _w0rmerOriginalMousemoved(x, y, dx, dy, istouch) end
end

love.resize = function(width, height, ...)
    if _w0rmerOriginalResize then return _w0rmerOriginalResize(width, height, ...) end
end


-- Optional gamepad support through LÖVE's native gamepad callbacks.
function love.gamepadpressed(joystick, button)
    local map = { dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
        a = "return", b = "escape", x = "b", y = "a", start = "return", back = "escape" }
    local key = map[button]
    if key then love.keypressed(key, key, false) end
end
