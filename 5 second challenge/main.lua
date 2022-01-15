local mod = RegisterMod('5 Second Challenge', 1)
local json = require('json')
local game = Game()

mod.text = nil
mod.roomStartTime = nil
mod.allowCountdown = false
mod.incrementAttempt = false
mod.roomTime = 5
mod.rng = RNG()
mod.font = Font()
mod.fonts = {}
mod.kcolor = KColor(255/255, 255/255, 255/255, 1) -- white w/ full alpha
mod.colors = {}
mod.fontSample = '0123456789'
mod.showFontSample = false
mod.animations = { 'none', 'fade', 'nap', 'pixelate', 'teleport', 'teleport (shorter)' }
mod.roomTypes = { 'normal + boss', 'normal + boss + special', 'normal + boss + special + ultrasecret' }

mod.state = {}
mod.state.enableEverywhere = false
mod.state.isTenSecondChallenge = false
mod.state.roomAttempts = {}
mod.state.stageSeed = nil
mod.state.selectedFont = 'upheaval'
mod.state.selectedColor = 'white'
mod.state.selectedAlpha = 10 -- this will be divided by 10 to give us a number between 0 and 1
mod.state.selectedAnimation = 'teleport'
mod.state.selectedRoomTypes = 'normal + boss + special + ultrasecret'

function mod:onGameStart(isContinue)
  local level = game:GetLevel()
  local stageSeed = game:GetSeeds():GetStageSeed(level:GetStage())
  mod.state.stageSeed = stageSeed
  mod:seedRng()
  
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData()) -- deal with bad json data
    
    if type(state) == 'table' then
      if type(state.enableEverywhere) == 'boolean' then
        mod.state.enableEverywhere = state.enableEverywhere
      end
      if type(state.isTenSecondChallenge) == 'boolean' then
        mod.state.isTenSecondChallenge = state.isTenSecondChallenge
        mod.roomTime = state.isTenSecondChallenge and 10 or 5
      end
      if math.type(state.stageSeed) == 'integer' and type(state.roomAttempts) == 'table' then
        -- quick check to see if this is the same run being continued
        if state.stageSeed == stageSeed then
          mod.state.roomAttempts = state.roomAttempts
        end
      end
      if type(state.selectedFont) == 'string' and mod:getSelectedFontIndex(state.selectedFont) >= 1 then
        mod.state.selectedFont = state.selectedFont
      end
      if type(state.selectedColor) == 'string' then
        local colorIdx = mod:getSelectedColorIndex(state.selectedColor)
        if colorIdx >= 1 then
          mod.state.selectedColor = state.selectedColor
          mod.kcolor.Red = mod.colors[colorIdx][2] / 255
          mod.kcolor.Green = mod.colors[colorIdx][3] / 255
          mod.kcolor.Blue = mod.colors[colorIdx][4] / 255
        end
      end
      if math.type(state.selectedAlpha) == 'integer' and state.selectedAlpha >= 0 and state.selectedAlpha <= 10 then
        mod.state.selectedAlpha = state.selectedAlpha
        mod.kcolor.Alpha = state.selectedAlpha / 10
      end
      if type(state.selectedAnimation) == 'string' and mod:getSelectedAnimationIndex(state.selectedAnimation) >= 1 then
        mod.state.selectedAnimation = state.selectedAnimation
      end
      if type(state.selectedRoomTypes) == 'string' and mod:getSelectedRoomTypesIndex(state.selectedRoomTypes) >= 1 then
        mod.state.selectedRoomTypes = state.selectedRoomTypes
      end
    end
    
    if isContinue then
      -- we don't want to increment if continuing
      -- this happens after onNewRoom
      mod.incrementAttempt = false
    else
      -- clear attempts if we're starting a new run
      mod:clearRoomAttempts()
    end
  end
  
  mod.font:Load(mod.fonts[mod:getSelectedFontIndex(mod.state.selectedFont)][2])
end

function mod:onGameExit()
  mod:SaveData(json.encode(mod.state))
end

function mod:onNewLevel()
  local level = game:GetLevel()
  local stageSeed = game:GetSeeds():GetStageSeed(level:GetStage())
  mod.state.stageSeed = stageSeed
  mod:clearRoomAttempts()
end

function mod:onNewRoom()
  local level = game:GetLevel()
  local roomDesc = level:GetCurrentRoomDesc()
  mod.roomStartTime = nil
  mod.text = nil
  mod.allowCountdown = mod:allowRoomCountdown(roomDesc)
  mod.incrementAttempt = true
end

function mod:onUpdate()
  if not mod:isChallenge() then
    return
  end
  
  if mod.allowCountdown then
    local level = game:GetLevel()
    local roomDesc = level:GetCurrentRoomDesc()
    
    if roomDesc.Clear then
      mod.roomStartTime = nil
      mod.text = nil
    else
      -- game:GetRoom():GetFrameCount()
      local frameCount = game:GetFrameCount()
      
      if mod.roomStartTime == nil then
        mod.roomStartTime = frameCount
        if mod.incrementAttempt then
          mod:incrementRoomAttempt(roomDesc.ListIndex)
          mod.incrementAttempt = false
        end
      end
      
      -- 30 frames per second
      -- https://wofsauge.github.io/IsaacDocs/rep/Game.html#getframecount
      local countdown = (mod:getRoomAttempt(roomDesc.ListIndex) * mod.roomTime) - math.floor((frameCount - mod.roomStartTime) / 30)
      mod.text = tostring(countdown)
      
      if countdown == 0 then
        mod:switchToRandomRoom()
      end
    end
  end
end

-- not using: MC_POST_PLAYER_RENDER (mirror dimension flips text, issue with reflections in water in large rooms, text can be hidden behind objects in some cases)
--     using: MC_POST_RENDER        (mirror dimension does not flip text, issue with positioning in the mirror dimension but we deal with that below)
function mod:onRenderPlayer()
  if not mod:isChallenge() then
    return
  end
  
  if mod.text ~= nil then
    for i = 0, game:GetNumPlayers() - 1 do
      -- Isaac.GetPlayer(i)
      local player = game:GetPlayer(i)
      local playerPos = Isaac.WorldToScreen(player.Position)
      -- game:GetLevel():GetCurrentRoom():IsMirrorWorld()
      if game:GetRoom():IsMirrorWorld() then
        local wtrp320x280 = Isaac.WorldToRenderPosition(Vector(320, 280)) -- center pos normal room, WorldToRenderPosition makes this work in large rooms too
        mod.font:DrawString(mod.text, wtrp320x280.X*2 - playerPos.X - mod.font:GetStringWidth(mod.text)/2, playerPos.Y, mod.kcolor, 0, true)
      else
        -- we're only drawing integers so DrawString and DrawStringUTF8 should both work
        mod.font:DrawString(mod.text, playerPos.X - mod.font:GetStringWidth(mod.text)/2, playerPos.Y, mod.kcolor, 0, true)
      end
    end
  end
end

function mod:switchToRandomRoom()
  local level = game:GetLevel()
  local rooms = level:GetRooms()
  local randomRooms = {}
  
  -- game:MoveToRandomRoom(bool, int) and level:GetRandomRoomIndex(bool, int) exist, but they don't do exactly what we're doing here
  for i = 0, #rooms - 1 do
    local roomDesc = rooms:Get(i)
    if not roomDesc.Clear and mod:allowRoomCountdown(roomDesc) and mod:getCurrentDimension() == mod:getDimension(roomDesc) then
      table.insert(randomRooms, roomDesc)
    end
  end
  
  if #randomRooms == 0 then
    -- if no random rooms to choose from then reload the current room
    table.insert(randomRooms, level:GetCurrentRoomDesc())
  end
  
  -- math.random(num) returns 1 to num
  -- rng:RandomInt(num) returns 0 to num-1
  -- we need the math.random behavior here because lua uses a 1-based index
  local randomRoom = randomRooms[mod.rng:RandomInt(#randomRooms) + 1]
  
  -- most animation options seem to default back to FADE when used in the way we're using here
  -- interestingly, GLOWING_HOURGLASS includes its actual behavior: ignoring the index you set and returning you to the previous room
  if mod.state.selectedAnimation == 'fade' then
    game:StartRoomTransition(randomRoom.SafeGridIndex, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, nil, -1)
  elseif mod.state.selectedAnimation == 'nap' then -- lol
    game:StartRoomTransition(randomRoom.SafeGridIndex, Direction.NO_DIRECTION, RoomTransitionAnim.DEATH_CERTIFICATE, nil, -1)
  elseif mod.state.selectedAnimation == 'pixelate' then
    game:StartRoomTransition(randomRoom.SafeGridIndex, Direction.NO_DIRECTION, RoomTransitionAnim.PIXELATION, nil, -1)
  elseif mod.state.selectedAnimation == 'teleport' then
    game:StartRoomTransition(randomRoom.SafeGridIndex, Direction.NO_DIRECTION, RoomTransitionAnim.TELEPORT, nil, -1)
  elseif mod.state.selectedAnimation == 'teleport (shorter)' then
    game:StartRoomTransition(randomRoom.SafeGridIndex, Direction.NO_DIRECTION, RoomTransitionAnim.D7, nil, -1)
  else -- none
    level.LeaveDoor = -1                          -- https://github.com/Meowlala/RepentanceAPIIssueTracker/issues/244
    game:ChangeRoom(randomRoom.SafeGridIndex, -1) -- the documentation says to use this over level:ChangeRoom
  end
end

function mod:allowRoomCountdown(roomDesc)
  -- this filters: mother, mega satan, beast, boss rush, angel/devil, etc
  -- some of these special rooms can be reloaded, some crash the game when reloaded, some can't be re-entered if you leave them
  -- you'd need to write a bunch of special rules for these if you want to include some of them
  -- https://wofsauge.github.io/IsaacDocs/rep/enums/GridRooms.html
  if roomDesc.SafeGridIndex < 0 then
    return false
  end
  
  local level = game:GetLevel()
  local stage = level:GetStage()
  local stageType = level:GetStageType()
  
  -- knife piece 2 in mines alt dimension (otherwise you can trigger mother's shadow multiple times)
  if stage == LevelStage.STAGE2_2 and (stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B) and mod:getDimension(roomDesc) == 1 then
    return false
  end
  
  -- mom/dad's note (you're supposed to be trapped in this fight, there's no door to leave)
  if stage == LevelStage.STAGE3_2 and roomDesc.Data.Type == RoomType.ROOM_BOSS then
    return false
  end
  
  -- hush (this is too similar to mother/mega satan)
  if stage == LevelStage.STAGE4_3 and roomDesc.Data.Type == RoomType.ROOM_BOSS then
    return false
  end
  
  -- delirium (this is too similar to mother/mega satan)
  if stage == LevelStage.STAGE7 and roomDesc.Data.Type == RoomType.ROOM_BOSS and roomDesc.Data.Shape == RoomShape.ROOMSHAPE_2x2 then
    return false
  end
  
  -- dogma (this is too similar to hush)
  if stage == LevelStage.STAGE8 and roomDesc.Data.Shape == RoomShape.ROOMSHAPE_1x2 then
    return false
  end
  
  local roomTypes = {}
  
  -- normal + boss / normal + boss + special / normal + boss + special + ultrasecret
  table.insert(roomTypes, RoomType.ROOM_DEFAULT)
  table.insert(roomTypes, RoomType.ROOM_BOSS)
  table.insert(roomTypes, RoomType.ROOM_MINIBOSS)
  
  -- other room types we shouldn't have to worry about:
  -- ROOM_BLACK_MARKET, ROOM_BLUE, ROOM_BOSSRUSH, ROOM_DUNGEON, ROOM_GREED_EXIT, ROOM_TELEPORTER, ROOM_TELEPORTER_EXIT, ROOM_SECRET_EXIT
  if mod.state.selectedRoomTypes == 'normal + boss + special' or mod.state.selectedRoomTypes == 'normal + boss + special + ultrasecret' then
    table.insert(roomTypes, RoomType.ROOM_ANGEL)     -- can exist on the grid in a red room
    table.insert(roomTypes, RoomType.ROOM_ARCADE)
    table.insert(roomTypes, RoomType.ROOM_BARREN)    -- bedroom
    table.insert(roomTypes, RoomType.ROOM_CHALLENGE) -- normal / boss
    table.insert(roomTypes, RoomType.ROOM_CHEST)     -- vault
    table.insert(roomTypes, RoomType.ROOM_CURSE)
    table.insert(roomTypes, RoomType.ROOM_DEVIL)     -- can exist on the grid in a red room
    table.insert(roomTypes, RoomType.ROOM_DICE)
    table.insert(roomTypes, RoomType.ROOM_ISAACS)    -- bedroom
    table.insert(roomTypes, RoomType.ROOM_LIBRARY)
    table.insert(roomTypes, RoomType.ROOM_PLANETARIUM)
    table.insert(roomTypes, RoomType.ROOM_SACRIFICE)
    table.insert(roomTypes, RoomType.ROOM_SECRET)
    table.insert(roomTypes, RoomType.ROOM_SHOP)
    table.insert(roomTypes, RoomType.ROOM_SUPERSECRET)
    table.insert(roomTypes, RoomType.ROOM_TREASURE)
  end
  
  if mod.state.selectedRoomTypes == 'normal + boss + special + ultrasecret' then
    table.insert(roomTypes, RoomType.ROOM_ULTRASECRET)
  end
  
  if not mod:tableHasValue(roomTypes, roomDesc.Data.Type) then
    return false
  end
  
  return true
end

function mod:clearRoomAttempts()
  for key, _ in pairs(mod.state.roomAttempts) do
    mod.state.roomAttempts[key] = nil
  end
end

function mod:getRoomAttempt(listIdx)
  listIdx = tostring(listIdx)
  return mod.state.roomAttempts[listIdx]
end

function mod:incrementRoomAttempt(listIdx)
  listIdx = tostring(listIdx) -- json.encode has trouble if this is numeric (tables are ambiguous -> array/object)
  if mod.state.roomAttempts[listIdx] == nil then
    mod.state.roomAttempts[listIdx] = 1
  else
    mod.state.roomAttempts[listIdx] = mod.state.roomAttempts[listIdx] + 1
  end
end

function mod:getCurrentDimension()
  local level = game:GetLevel()
  local currentRoom = level:GetCurrentRoomDesc()
  return mod:getDimension(currentRoom)
end

-- bit of a hack to get dimension info
function mod:getDimension(roomDesc)
  local level = game:GetLevel()
  local ptrHash = GetPtrHash(roomDesc)
  
  -- 0: main dimension
  -- 1: secondary dimension, used by downpour mirror dimension and mines escape sequence
  -- 2: death certificate dimension
  for i = 0, 2 do
    if ptrHash == GetPtrHash(level:GetRoomByIdx(roomDesc.SafeGridIndex, i)) then
      return i
    end
  end
  return -1
end

function mod:isChallenge()
  -- game.Challenge
  local challenge = Isaac.GetChallenge()
  return challenge == Isaac.GetChallengeIdByName('5 Second Challenge (Mom)') or
         challenge == Isaac.GetChallengeIdByName('5 Second Challenge (It Lives)') or
         challenge == Isaac.GetChallengeIdByName('5 Second Challenge (Mother)') or
         challenge == Isaac.GetChallengeIdByName('5 Second Challenge (Blue Baby)') or
         challenge == Isaac.GetChallengeIdByName('5 Second Challenge (The Lamb)') or
         (challenge == Challenge.CHALLENGE_NULL and mod.state.enableEverywhere and not game:IsGreedMode())
end

function mod:seedRng()
  repeat
    local rand = Random()  -- 0 to 2^32
    if rand > 0 then       -- if this is 0, it causes a crash later on
      mod.rng:SetSeed(rand, 1)
    end
  until(rand > 0)
end

function mod:getSelectedFontIndex(name)
  for i, value in ipairs(mod.fonts) do
    if name == value[1] then
      return i
    end
  end
  return -1
end

function mod:getSelectedColorIndex(name)
  for i, value in ipairs(mod.colors) do
    if name == value[1] then
      return i
    end
  end
  return -1
end

function mod:getSelectedAnimationIndex(name)
  for i, value in ipairs(mod.animations) do
    if name == value then
      return i
    end
  end
  return -1
end

function mod:getSelectedRoomTypesIndex(name)
  for i, value in ipairs(mod.roomTypes) do
    if name == value then
      return i
    end
  end
  return -1
end

function mod:tableHasValue(tbl, val)
  for _, value in ipairs(tbl) do
    if val == value then
      return true
    end
  end
  return false
end

function mod:populateFontsTable()
  -- these are all the fonts found in repentance with the resource extractor
  -- fonts are found in the main resources folder, as well as jp/kr/zh specific folders, these require that the language option is set to jp/kr/zh
  -- the jp fonts are duplicated in the main resources folder
  -- the zh fonts are extended versions of other fonts, for our purposes: integer display is the same
  table.insert(mod.fonts, { 'droid', 'font/droid.fnt' })
  if Options.Language == 'kr' then
    table.insert(mod.fonts, { 'kr_font12', 'font/kr_font12.fnt' })
    table.insert(mod.fonts, { 'kr_font14', 'font/kr_font14.fnt' })
    table.insert(mod.fonts, { 'kr_meatfont14', 'font/kr_meatfont14.fnt' })
  end
  table.insert(mod.fonts, { 'lanapixel', 'font/cjk/lanapixel.fnt' })
  table.insert(mod.fonts, { 'luamini', 'font/luamini.fnt' })
  table.insert(mod.fonts, { 'luaminioutlined', 'font/luaminioutlined.fnt' })
  table.insert(mod.fonts, { 'mplus_10r', 'font/japanese/mplus_10r.fnt' })
  table.insert(mod.fonts, { 'mplus_12b', 'font/japanese/mplus_12b.fnt' })
  --if Options.Language == 'jp' then
  --  table.insert(mod.fonts, { 'mplus_10r', 'font/mplus_10r.fnt' })
  --  table.insert(mod.fonts, { 'mplus_12b', 'font/mplus_12b.fnt' })
  --end
  table.insert(mod.fonts, { 'pftempestasevencondensed', 'font/pftempestasevencondensed.fnt' })
  table.insert(mod.fonts, { 'teammeatfont10', 'font/teammeatfont10.fnt' })
  table.insert(mod.fonts, { 'teammeatfont12', 'font/teammeatfont12.fnt' })
  table.insert(mod.fonts, { 'teammeatfont16', 'font/teammeatfont16.fnt' })
  table.insert(mod.fonts, { 'teammeatfont16bold', 'font/teammeatfont16bold.fnt' })
  table.insert(mod.fonts, { 'teammeatfont20bold', 'font/teammeatfont20bold.fnt' })
  --if Options.Language == 'zh' then
  --  table.insert(mod.fonts, { 'teammeatfontextended10', 'font/teammeatfontextended10.fnt' })
  --  table.insert(mod.fonts, { 'teammeatfontextended12', 'font/teammeatfontextended12.fnt' })
  --  table.insert(mod.fonts, { 'teammeatfontextended16bold', 'font/teammeatfontextended16bold.fnt' })
  --end
  table.insert(mod.fonts, { 'terminus', 'font/terminus.fnt' })
  table.insert(mod.fonts, { 'terminus8', 'font/terminus8.fnt' })
  table.insert(mod.fonts, { 'upheaval', 'font/upheaval.fnt' })
  --if Options.Language == 'zh' then
  --  table.insert(mod.fonts, { 'upheavalextended', 'font/upheavalextended.fnt' })
  --end
  table.insert(mod.fonts, { 'upheavalmini', 'font/upheavalmini.fnt' })
end

function mod:populateColorsTable()
  table.insert(mod.colors, { 'white', 255, 255, 255 })
  table.insert(mod.colors, { 'silver', 192, 192, 192 })
  table.insert(mod.colors, { 'gray', 128, 128, 128 })
  table.insert(mod.colors, { 'black', 0, 0, 0 })
  table.insert(mod.colors, { 'red', 255, 0, 0 })
  table.insert(mod.colors, { 'maroon', 128, 0, 0 })
  table.insert(mod.colors, { 'yellow', 255, 255, 0 })
  table.insert(mod.colors, { 'olive', 128, 128, 0 })
  table.insert(mod.colors, { 'lime', 0, 255, 0 })
  table.insert(mod.colors, { 'green', 0, 128, 0 })
  table.insert(mod.colors, { 'aqua', 0, 255, 255 })
  table.insert(mod.colors, { 'teal', 0, 128, 128 })
  table.insert(mod.colors, { 'blue', 0, 0, 255 })
  table.insert(mod.colors, { 'navy', 0, 0, 128 })
  table.insert(mod.colors, { 'fuchsia', 255, 0, 255 })
  table.insert(mod.colors, { 'purple', 128, 0, 128 })
end

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  ModConfigMenu.AddSetting(
    mod.Name,
    'General',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.enableEverywhere
      end,
      Display = function()
        return (mod.state.enableEverywhere and 'Enabled' or 'Disabled') .. ' in normal/hard'
      end,
      OnChange = function(b)
        mod.state.enableEverywhere = b
      end,
      Info = { 'Disabled: only enabled via challenge menu', 'Enabled: also enabled in normal/hard mode', 'Does not work in greed/greedier mode' }
    }
  )
  ModConfigMenu.AddSetting(
    mod.Name,
    'General',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.isTenSecondChallenge
      end,
      Display = function()
        return (mod.state.isTenSecondChallenge and '10' or '5') .. ' second challenge'
      end,
      OnChange = function(b)
        mod.state.isTenSecondChallenge = b
        mod.roomTime = b and 10 or 5
      end,
      Info = { '5 second challenge: default', '10 second challenge: easier' }
    }
  )
  ModConfigMenu.AddSetting(
    mod.Name,
    'General',
    {
      Type = ModConfigMenu.OptionType.NUMBER,
      CurrentSetting = function()
        return mod:getSelectedAnimationIndex(mod.state.selectedAnimation)
      end,
      Minimum = 1,
      Maximum = #mod.animations,
      Display = function()
        return mod.state.selectedAnimation
      end,
      OnChange = function(n)
        mod.state.selectedAnimation = mod.animations[n]
      end,
      Info = { 'Select a room transition animation' }
    }
  )
  ModConfigMenu.AddSpace(mod.Name, 'General')
  ModConfigMenu.AddSetting(
    mod.Name,
    'General',
    {
      Type = ModConfigMenu.OptionType.NUMBER,
      CurrentSetting = function()
        return mod:getSelectedRoomTypesIndex(mod.state.selectedRoomTypes)
      end,
      Minimum = 1,
      Maximum = #mod.roomTypes,
      Display = function()
        return mod.state.selectedRoomTypes
      end,
      OnChange = function(n)
        mod.state.selectedRoomTypes = mod.roomTypes[n]
      end,
      Info = { 'Select the room types this mod applies to' }
    }
  )
  ModConfigMenu.AddText(mod.Name, 'General', 'boss: boss, miniboss')
  ModConfigMenu.AddText(mod.Name, 'General', 'special: arcade, bedroom, challenge, curse,')
  ModConfigMenu.AddText(mod.Name, 'General', 'dice, library, planetarium, sacrifice, secret,')
  ModConfigMenu.AddText(mod.Name, 'General', 'shop, supersecret, treasure, vault')
  ModConfigMenu.AddSetting(
    mod.Name,
    'Display',
    {
      Type = ModConfigMenu.OptionType.NUMBER,
      CurrentSetting = function()
        return mod:getSelectedFontIndex(mod.state.selectedFont)
      end,
      Minimum = 1,
      Maximum = #mod.fonts,
      Display = function()
        mod.showFontSample = true
        return mod.state.selectedFont
      end,
      OnChange = function(n)
        mod.state.selectedFont = mod.fonts[n][1]
        mod.font:Load(mod.fonts[n][2])
      end,
      Info = { 'Select a font' }
    }
  )
  ModConfigMenu.AddSetting(
    mod.Name,
    'Display',
    {
      Type = ModConfigMenu.OptionType.NUMBER,
      CurrentSetting = function()
        return mod:getSelectedColorIndex(mod.state.selectedColor)
      end,
      Minimum = 1,
      Maximum = #mod.colors,
      Display = function()
        return mod.state.selectedColor
      end,
      OnChange = function(n)
        mod.state.selectedColor = mod.colors[n][1]
        mod.kcolor.Red = mod.colors[n][2] / 255
        mod.kcolor.Green = mod.colors[n][3] / 255
        mod.kcolor.Blue = mod.colors[n][4] / 255
      end,
      Info = { 'Select a color' }
    }
  )
  ModConfigMenu.AddSetting(
    mod.Name,
    'Display',
    {
      Type = ModConfigMenu.OptionType.SCROLL, -- shows 10 bars, you can select 0-10 for a total of 11 options
      CurrentSetting = function()
        return mod.state.selectedAlpha
      end,
      Display = function()
        return '$scroll' .. mod.state.selectedAlpha
      end,
      OnChange = function(n)
        mod.state.selectedAlpha = n
        mod.kcolor.Alpha = n / 10
      end,
      Info = { 'Select an opacity' }
    }
  )
end

function mod:onRenderMenu()
  if mod.showFontSample then
    if ScreenHelper then                                           -- this is from ModConfigMenu
      local pos = ScreenHelper.GetScreenCenter() + Vector(68, -18) -- the positioning is copied from ModConfigMenu
      mod.font:DrawString(mod.fontSample, pos.X - mod.font:GetStringWidth(mod.fontSample)/2, pos.Y, mod.kcolor, 0, true)
    end
    mod.showFontSample = false
  end
end
-- end ModConfigMenu --

mod:populateFontsTable()
mod:populateColorsTable()
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.onNewLevel)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRenderPlayer)

if ModConfigMenu then
  mod:setupModConfigMenu()
  mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRenderMenu)
end