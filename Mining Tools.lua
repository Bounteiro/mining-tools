script_name('Mining Tools')
script_author('SaBoARZ (t.me/SaBoARZ)')
script_version('6.7 beta')
script_version_number(2)
script_description('Скрипт для упрощения майнинга на сервере.')

local sampfuncs = require("sampfuncs")
local sampev = require("samp.events")
local encoding = require("encoding")
encoding.default = 'CP1251'
u8 = encoding.UTF8
local imgui = require("mimgui")
local effil = require('effil')
local ffi = require('ffi')
local fa = require('fAwesome6')
local raknet = require('samp.raknet')
local wm = require('windows.message')
local new = imgui.new

--local UPDATE_CHECK_URL = "https://raw.githubusercontent.com/Bounteiro/mining-tools/main/version.json"
local UPDATE_CHECK_URL = "https://raw.githubusercontent.com/Bounteiro/mining-tools/main/version.json"

local searchBuffer = new.char[256]()
local currentStatusFilter = new.int(0)
local selectedCardLevels = {}
local selectedCities = {}
local _snapshotSaveT = 0

local sortItems = { u8 "По номеру", u8 "По балансу", u8 "По циклам", u8 "По жидкости", u8 "По видеокартам", u8 "По городу" }
local statusItems = { u8 "Все дома", u8 "В норме", u8 "Требует внимания", u8 "Есть проблемы", u8 "Без подвала" }
require('samp.synchronization')

do
    local ok, needsPatch = pcall(function()
        local rpc61 = sampev.INTERFACE.INCOMING_RPCS[61]
        if type(rpc61) ~= "table" then return false end
        local entry2 = rpc61[2]
        if type(entry2) ~= "table" then return false end
        return entry2.dialogId == "uint16"
    end)
    if ok and needsPatch then
        sampev.INTERFACE.INCOMING_RPCS[61] = {
            "onShowDialog",
            {
                dialogId = "uint16"
            },
            {
                style = "uint8"
            },
            {
                title = "string8"
            },
            {
                button1 = "string8"
            },
            {
                button2 = "string8"
            },
            {
                text = "encodedString4096"
            },
            {
                placeholder = "string8"
            }
        }
    end
end

local dialogIdTable          = {
    arizona = {
        videoCardSt = 25244,             -- ID диалога полки
        videoCardDialogId = 25245,       -- ID диалога управления видеокартой (Стойка/Полка)
        coolantDialogId = 25271,         -- ID диалога выбора охлаждающей жидкости
        houseDialogId = 7238,            -- ID диалога выбора дома
        houseFlashMinerDialogId = 25182, -- ID диалога выбора видеокарты в доме
        videoCardAcceptDialogId = 25246, -- ID диалога подтверждения вывода прибыли

        phoneBankMenuId = 6565,          -- ID главного меню банка в телефоне
        payAllTaxesDialogId = 15252,     -- ID диалога подтверждения оплаты всех налогов
        houseListBankId = 7238,          -- ID диалога выбора дома для пополнения (тот же что и houseDialogId)
        topUpBalanceDialogId = 27036,    -- ID диалога ввода суммы пополнения

    },
    rodina = {
        videoCardSt = 25244,           -- ID диалога полки
        videoCardDialogId = 270,       -- ID диалога управления видеокартой (Стойка/Полка)
        coolantDialogId = 25271,       -- ID диалога выбора охлаждающей жидкости
        houseDialogId = 7238,          -- ID диалога выбора дома
        houseFlashMinerDialogId = 269, -- ID диалога выбора видеокарты в доме
        videoCardAcceptDialogId = 271, -- ID диалога подтверждения вывода прибыли
    }
}

do
    Jcfg = {
        _version = 0.1,
        _author = "SaBoARZ",
        _telegram = "@SaBoARZ",
        _help = [[Jcfg - модуль для сохранения и загрузки конфигурационных файлов...]]
    }

    function Jcfg.__init()
        local self = {}
        local json = require('dkjson')

        local function makeDirectory(path)
            assert(type(path) == "string" and path:find('moonloader'),
                "Path must be a string and include 'moonloader' folder")
            path = path:gsub("[\\/][^\\/]+%.json$", "")
            if doesDirectoryExist(path) then return end

            -- Создаём папки по цепочке (path может быть вложенным, например profiles\КлючПрофиля)
            local accum = ""
            for part in path:gmatch("[^\\/]+") do
                accum = (accum == "") and part or (accum .. "\\" .. part)
                if not doesDirectoryExist(accum) then
                    createDirectory(accum)
                end
            end

            if not doesDirectoryExist(path) then
                return error("Failed to create directory: " .. path)
            end
        end

        local function setupImguiConfig(table)
            assert(type(table) == "table",
                ("bad argument #1 to 'setupImgui' (table expected, got %s)"):format(type(table)))
            local function setupImguiConfigRecursive(tbl)
                local imcfg = {}
                for k, v in pairs(tbl) do
                    if type(v) == "table" then
                        imcfg[k] = setupImguiConfigRecursive(v)
                    elseif type(v) == "number" then
                        if v % 1 == 0 then
                            imcfg[k] = imgui.new.int(v)
                        else
                            imcfg[k] = imgui.new.float(v)
                        end
                    elseif type(v) == "string" then
                        imcfg[k] = imgui.new.char[256](u8(v))
                    elseif type(v) == "boolean" then
                        imcfg[k] = imgui.new.bool(v)
                    else
                        error(("Unsupported type for imguiConfig: %s"):format(type(v)))
                    end
                end
                return imcfg
            end
            return setupImguiConfigRecursive(table)
        end

        function self.save(table, path)
            assert(type(table) == "table", ("bad argument #1 to 'save' (table expected, got %s)"):format(type(table)))
            assert(path == nil or type(path) == "string", "Path must be nil or a valid file path.")
            if not path then
                assert(thisScript().name, "Script name is not defined")
                path = getWorkingDirectory() .. '\\config\\' .. thisScript().name .. '\\config.json'
            end
            makeDirectory(path)
            local file = io.open(path, "w")
            if file then
                file:write(json.encode(table, { indent = true }))
                file:close()
            else
                error("Could not open file for writing: " .. path)
            end
        end

        function self.load(path)
            if not path then
                path = getWorkingDirectory() .. '\\config\\' .. thisScript().name .. '\\config.json'
            end
            if doesFileExist(path) then
                local file = io.open(path, "r")
                if file then
                    local content = file:read("*all")
                    file:close()
                    return json.decode(content)
                else
                    return error("Could not load configuration")
                end
            end
            return {}
        end

        function self.update(table, path)
            assert(type(table) == "table", ("bad argument #1 to 'update' (table expected, got %s)"):format(type(table)))
            local loadedCfg = self.load(path)
            if loadedCfg then
                for k, v in pairs(table) do
                    if loadedCfg[k] ~= nil then
                        table[k] = loadedCfg[k]
                    end
                end
            end
            return true
        end

        function self.setupImgui(table)
            assert(imgui ~= nil, "The imgui library is not loaded.")
            return setupImguiConfig(table)
        end

        return self
    end

    setmetatable(Jcfg, {
        __call = function(self)
            return self.__init()
        end
    })
end

local jcfg = Jcfg()

-- === Профили по серверу + нику ===
-- Идея: у каждой связки "сервер + ник" — свой отдельный config.json (свои дома,
-- своя доходность, свои снапшоты карт), чтобы Drake и Faraway (или разные аккаунты)
-- не смешивались в одном файле.

local function sanitizeForPath(s)
    if not s or s == '' then return 'unknown' end
    s = tostring(s)
    s = s:gsub('[\\/:%*%?"<>|]', '_') -- запрещённые в именах папок символы
    s = s:gsub('%s+', '_')
    s = s:gsub('_+', '_')
    s = s:gsub('^_+', ''):gsub('_+$', '')
    if s == '' then s = 'unknown' end
    return s
end

local function getProfilesDir()
    return getWorkingDirectory() .. '\\config\\' .. thisScript().name .. '\\profiles\\'
end

local function getPointerPath()
    return getWorkingDirectory() .. '\\config\\' .. thisScript().name .. '\\active_profile.txt'
end

local function readPointer()
    local p = getPointerPath()
    if doesFileExist(p) then
        local f = io.open(p, 'r')
        if f then
            local v = f:read('*all')
            f:close()
            if v then v = v:gsub('%s+$', ''):gsub('^%s+', '') end
            if v and v ~= '' then return v end
        end
    end
    return nil
end

local function writePointer(key)
    local dir = getWorkingDirectory() .. '\\config\\' .. thisScript().name
    if not doesDirectoryExist(dir) then createDirectory(dir) end
    local f = io.open(getPointerPath(), 'w')
    if f then
        f:write(key)
        f:close()
    end
end

local function getProfileConfigPath(key)
    return getProfilesDir() .. key .. '\\config.json'
end

local function getProfileLogsPath(key)
    return getProfilesDir() .. key .. '\\logs.json'
end

-- Ждём, пока станет известен ник локального игрока (сразу после коннекта его может
-- ещё не быть, поэтому пробуем в течение timeoutMs).
local function waitForNickname(timeoutMs)
    local start = os.clock()
    while (os.clock() - start) * 1000 < timeoutMs do
        if isSampAvailable and isSampAvailable() then
            local pok, found, pid = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
            if pok and found and pid then
                local nok, nick = pcall(sampGetPlayerNickname, pid)
                if nok and nick and nick ~= '' then return nick end
            end
        end
        wait(100)
    end
    return nil
end

-- Профиль, который был активен на прошлой загрузке (если есть указатель на диске).
-- Пока сервер/ник не определены (в самом начале, до коннекта) — используем его как есть,
-- либо legacy-путь по умолчанию, если указателя ещё нет (первый запуск/старые пользователи).
local activeProfileKey = readPointer()
local activeConfigPath = activeProfileKey and getProfileConfigPath(activeProfileKey) or nil

local function getDefaultCfg()
    return {
        isReloaded               = false,
        active                   = true,
        debug                    = false,
        silentMode               = false,
        checkForUpdates          = true,
        useDialogMode            = false,
        helpShown                = false,

        -- Оформление
        accentColor              = { 0.16, 0.38, 0.62 },

        -- Заливка
        useSuperCoolant          = false,
        useCoolantPercent        = 50,
        economyMode              = false,
        pause_duration           = 300,
        count_action             = 8,

        -- Дома
        housesWithoutBasement    = {},
        excludedHouses           = {},
        basementScanned          = {},
        cardSnapshots            = {},
        lastHouseListHash        = "",
        currentSort              = 0,
        sortAscending            = true,
        showExcludedHouses       = false,
        groupByCity              = false,
        targetHouseBalance       = 10000000,
        minBalanceWarning        = 5000000,

        -- Включение карт
        autoEnableCards          = false,
        autoEnableCardsOnCollect = false,
        autoEnableCardsOnOpen    = false,

        -- Авто-сбор
        cheatModeEnabled         = false,
        autoCollectEnabled       = false,
        collectTimesPerDay       = 2,
        lastCollectTime          = 0,
        collectOnlyIfMin         = 0,
        pauseOnPayday            = true,
        smartCollectEnabled      = false,
        smartCollectTarget       = 160,
        randomDelayEnabled       = false,
        randomDelayMin           = 1,
        randomDelayMax           = 120,

        -- Налоги
        autoPayTaxesEnabled      = false,
        autoPayTaxesWithCollect  = true,
        autoPayTaxesByTimer      = false,
        autoPayTaxesInterval     = 24,
        lastTaxPayTime           = 0,

        -- Пополнение баланса
        autoTopUpEnabled         = false,
        autoTopUpWithCollect     = true,
        autoTopUpByThreshold     = false,
        autoTopUpThreshold       = 3000000,
        autoTopUpByTimer         = false,
        autoTopUpTimerInterval   = 12,
        lastAutoTopUpTime        = 0,
        useSimpleTopUp           = true,
        fixTopUpEnabled          = true,

        -- Фон. обновление статусов
        autoRefreshEnabled       = false,
        autoRefreshInterval      = 30,
        lastAutoRefreshTime      = 0,
        refreshPostponeOnDialog  = true,
        refreshPostponeMinutes   = 1,

        -- Подключение
        waitForConnection        = true,
        delayAfterConnectMin     = 5,

        -- Уведомления
        reminderEnabled          = false,
        reminderInterval         = 10,
        btcThreshold             = 100,
        notifyAutoCollectEnabled = true,
        notifyBeforeSec          = 120,
        notifyShowDuration       = 8,
        notifyWindowPosX         = 0.75,
        notifyWindowPosY         = 0.05,
        logsWindowPosX           = 0.3,
        logsWindowPosY           = 0.1,

        -- Фиксы
        fixSwitchEnabled         = true,
        fixCollectEnabled        = true,
        fixCoolantEnabled        = false,
    }
end

local cfg = getDefaultCfg()

jcfg.update(cfg, activeConfigPath)
local imcfg = jcfg.setupImgui(cfg)

function save()
    jcfg.save(cfg, activeConfigPath)
end

-- === Акцентный цвет интерфейса ===
-- jcfg.setupImgui разворачивает {r,g,b} в три отдельных imgui.new.float,
-- а не в единый float[3]-буфер, поэтому для ColorEdit3 держим свой буфер отдельно.
local accentColorBuf = imgui.new.float[3](
    cfg.accentColor[1], cfg.accentColor[2], cfg.accentColor[3])

-- Состояние наведения на вкладки настроек (для контрастного текста при hover)
local _settingsTabHover = {}

local function clamp01(x)
    return math.max(0, math.min(1, x))
end

-- Акцентный цвет как ImVec4 с заданной альфой (по умолчанию непрозрачный)
local function accentRGBA(alpha)
    return imgui.ImVec4(cfg.accentColor[1], cfg.accentColor[2], cfg.accentColor[3], alpha or 1)
end

-- Акцентный цвет, осветлённый/затемнённый в mul раз — для hover/active состояний
local function accentShade(mul, alpha)
    return imgui.ImVec4(
        clamp01(cfg.accentColor[1] * mul),
        clamp01(cfg.accentColor[2] * mul),
        clamp01(cfg.accentColor[3] * mul),
        alpha or 1)
end

-- Контрастный цвет текста (чёрный/белый) для плашек, залитых акцентным цветом,
-- чтобы текст оставался читаемым, если акцент светлый (например, белый).
local function accentLuma()
    return 0.299 * cfg.accentColor[1] + 0.587 * cfg.accentColor[2] + 0.114 * cfg.accentColor[3]
end

local function accentContrastVec()
    if accentLuma() > 0.6 then
        return imgui.ImVec4(0.08, 0.09, 0.11, 1)
    end
    return imgui.ImVec4(1, 1, 1, 1)
end

local function accentContrastHex()
    if accentLuma() > 0.6 then
        return "{0F1014}"
    end
    return "{FFFFFF}"
end

-- Подмешивает выбранный акцентный цвет в тёмный базовый фон (baseR/G/B),
-- чтобы фон главного окна, вкладок, плашек "Всего домов" и карточек домов
-- сохранял тёмную тему, но перенимал оттенок выбранной палитры.
-- strength: 0 = фон без изменений, 1 = полностью цвет акцента.
local function accentTint(baseR, baseG, baseB, strength, alpha)
    strength = strength or 0.25
    return imgui.ImVec4(
        clamp01(baseR + (cfg.accentColor[1] - baseR) * strength),
        clamp01(baseG + (cfg.accentColor[2] - baseG) * strength),
        clamp01(baseB + (cfg.accentColor[3] - baseB) * strength),
        alpha or 1)
end

local function saveAccentColor()
    cfg.accentColor = { accentColorBuf[0], accentColorBuf[1], accentColorBuf[2] }
    save()
end

local function resetAccentColor()
    cfg.accentColor  = { 0.16, 0.38, 0.62 }
    accentColorBuf[0] = cfg.accentColor[1]
    accentColorBuf[1] = cfg.accentColor[2]
    accentColorBuf[2] = cfg.accentColor[3]
    save()
end

function resetDefaultCfg()
    cfg = getDefaultCfg()
    save()
    thisScript():reload()
end

local data = {
    -- Окна
    main                   = imgui.new.bool(false),
    showHouseControlWindow = imgui.new.bool(false),
    showLogsWindow         = imgui.new.bool(false),
    showSettingsWindow     = imgui.new.bool(false),
    showHelpWindow         = imgui.new.bool(false),
    helpPage               = 1,
    setupPage              = 1,
    helpWindowMode         = 'reference',
    settingsTab            = 0,
    cheatSubTab            = 0,
    debugSubTab            = 0,
    logsTab                = imgui.new.int(0),
    lastWindowState        = {
        main         = false,
        houseControl = false,
    },

    -- Список домов
    selectedHouseIndex     = 1,
    lastSelectedHouse      = -1,
    currentFlashminerHouseNumber = nil,
    currentFlashminerHouseAt     = 0,
    pendingHouseNumber     = nil,
    pendingHouseAt         = 0,
    scrollToSelection      = false,
    dialogData             = {
        flashminer = {},
        videocards = {},
    },
    taskTypeNow            = '',
    houseStatuses          = {},
    isFlashminer           = false,
    hasFlashminer          = nil,
    noHousesNotified       = false,
    dFlashminerId          = 0,
    flashminerSwitchId     = { direction = 0, id = 0 },
    houseHasNoBasement     = false,
    initialScanCompleted   = false,
    filteredHouses         = nil,

    -- Сервер
    isRodina               = false,
    isViceCity             = false,

    -- Состояние
    working                = false,
    fix                    = false,
    silentWindowOpen       = false,
    stopAction             = false,
    topUpLastFailed       = false,
    suppressDialogs        = false,
    suppressDialogsUntil   = 0,
    stopBySystem           = false,
    collectCancelled       = false,
    globalActionCounter    = {
        count          = 0,
        lastActionTime = 0,
    },
    connectionState        = {
        connected           = false,
        wasDisconnected     = true,
        readyAfterConnect   = 0,
        lastCheck           = 0,
        profileCheckPending = false,
    },

    -- Прогресс сбора
    currentCollectHouse    = "",
    progressCurrent        = 0,
    progressTotal          = 0,
    progressHouseCurrent   = 0,
    progressHouseTotal     = 0,
    progressSmooth         = {
        outer          = 0,
        outerVelocity  = 0,
        inner          = 0,
        innerVelocity  = 0,
        lastUpdateTime = 0,
    },

    -- Авто-сбор
    pendingCollectAt       = 0,
    pendingCollectLocked   = false,

    -- Уведомления
    notifyWindow           = {
        show            = imgui.new.bool(false),
        mode            = '',
        source          = '',
        btcAmount       = 0,
        ascAmount       = 0,
        countdownTarget = 0,
        autoHideAt      = 0,
        isPreview       = false,
    },

    -- Сбор
    withdraw               = { btc = 0, asc = 0 },
    forImgui               = {
        allGood        = false,
        videocardCount = 0,
        earnings       = { btc = 0, asc = 0 },
        attentionTime  = 0,
    },

    -- PayDay
    isWaitingPayday        = false,
    paydaySkippedAt        = 0,
    skipPayday             = false,

    -- Подтверждения сброса
    logsResetConfirm       = false,
    logsResetTimer         = 0,
    statsResetConfirm      = false,
    statsResetTimer        = 0,
    settingsResetConfirm   = false,
    settingsResetTimer     = 0,

    -- Фильтры списков
    logsPeriodFilter       = 0,
    levelFilterOpenTime    = 0,
    levelFilterItemRect    = nil,
    cityFilterOpenTime     = 0,
    cityFilterItemRect     = nil,
    cityFilterInvert       = false,
}

local utils = (function()
    local self = {}
    function self.addChat(a)
        if cfg.silentMode or not a then return end

        a = type(a) == 'number' and tostring(a) or (type(a) == 'string' and a or nil)
        if not a then return end

        sampAddChatMessage('{ffa500}' .. thisScript().name .. '{ffffff}: ' .. a, -1)
    end

    function self.debugChat(a)
        if not cfg.debug or not a then return end

        a = type(a) == 'number' and tostring(a) or (type(a) == 'string' and a or nil)
        if not a then return end

        sampAddChatMessage('{ffa500}' .. thisScript().name .. ' DEBUG' .. '{ffffff}: ' .. a, -1)
    end

    function self.calculateRemainingHours(percent)
        local consumptionPerHour = 0.48
        return percent / consumptionPerHour
    end

    function self.formatNumber(num)
        if type(num) ~= 'number' then
            if type(num) == 'string' and tonumber(num) then
                num = tonumber(num)
            else
                return 'Error: invalid input'
            end
        end
        local formatted = string.format('%.0f', math.floor(num))
        local reversed = formatted:reverse()
        local with_dots = reversed:gsub('(%d%d%d)', '%1.'):reverse()
        if with_dots:sub(1, 1) == '.' then
            with_dots = with_dots:sub(2)
        end
        return with_dots
    end

    function samp_create_sync_data(sync_type, copy_from_player)
        copy_from_player = copy_from_player or true
        local sync_traits = {
            player = { 'PlayerSyncData', raknet.PACKET.PLAYER_SYNC, sampStorePlayerOnfootData },
            vehicle = { 'VehicleSyncData', raknet.PACKET.VEHICLE_SYNC, sampStorePlayerIncarData },
            passenger = { 'PassengerSyncData', raknet.PACKET.PASSENGER_SYNC, sampStorePlayerPassengerData },
            aim = { 'AimSyncData', raknet.PACKET.AIM_SYNC, sampStorePlayerAimData },
            trailer = { 'TrailerSyncData', raknet.PACKET.TRAILER_SYNC, sampStorePlayerTrailerData },
            unoccupied = { 'UnoccupiedSyncData', raknet.PACKET.UNOCCUPIED_SYNC, nil },
            bullet = { 'BulletSyncData', raknet.PACKET.BULLET_SYNC, nil },
            spectator = { 'SpectatorSyncData', raknet.PACKET.SPECTATOR_SYNC, nil }
        }
        local sync_info = sync_traits[sync_type]
        if not sync_info then return end
        local data_type = 'struct ' .. sync_info[1]
        local data = ffi.new(data_type, {})
        local raw_data_ptr = tonumber(ffi.cast('uintptr_t', ffi.new(data_type .. '*', data)))
        if copy_from_player then
            local copy_func = sync_info[3]
            if copy_func then
                local _, player_id
                if copy_from_player == true then
                    _, player_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
                else
                    player_id = tonumber(copy_from_player)
                end
                copy_func(player_id, raw_data_ptr)
            end
        end
        local func_send = function()
            local bs = raknetNewBitStream()
            raknetBitStreamWriteInt8(bs, sync_info[2])
            raknetBitStreamWriteBuffer(bs, raw_data_ptr, ffi.sizeof(data))
            raknetSendBitStreamEx(bs, sampfuncs.HIGH_PRIORITY, sampfuncs.UNRELIABLE_SEQUENCED, 1)
            raknetDeleteBitStream(bs)
        end
        local mt = {
            __index = function(t, index) return data[index] end,
            __newindex = function(t, index, value) data[index] = value end
        }
        return setmetatable({ send = func_send }, mt)
    end

    function self.pressButton(keysData)
        local sync = samp_create_sync_data('player')
        sync.keysData = keysData
        sync:send()
    end

    return self
end)()

-- DEBUG wrapper for sampSendDialogResponse
local _origSampSendDialogResponse = sampSendDialogResponse
sampSendDialogResponse = function(dialogId, button, listitem, input)
    utils.debugChat(string.format("[DIALOG] sampSendDialogResponse (auto) | id=%d button=%d listitem=%d input=%q", dialogId, button, listitem, tostring(input or "")))
    return _origSampSendDialogResponse(dialogId, button, listitem, input)
end

-- Определяет, что переданный dialogId принадлежит самому скрипту (стойка,
-- полка, флешмайнер, охлаждение). Если активный диалог НЕ входит в этот
-- список во время автосбора — значит, скорее всего, это окно, которое
-- игрок открыл сам (телефон, инвентарь и т.п.), и его нельзя закрывать
-- принудительно, иначе можно оборвать чужое действие игрока.
function isOwnScriptDialogId(id)
    if not id then return false end
    return id == data.dFlashminerId
        or id == dialogIdTable.videoCardDialogId
        or id == dialogIdTable.videoCardAcceptDialogId
        or id == dialogIdTable.coolantDialogId
        or id == dialogIdTable.videoCardSt
        or id == dialogIdTable.houseFlashMinerDialogId
end

-- Ждём, пока игрок сам закроет своё окно (мы не трогаем его силой).
-- Возвращает true, если после ожидания диалог скрипта снова активен
-- (или ни один диалог не активен).
function waitForForeignDialogToClose(maxMs, expectedDialogId)
    local warned = false
    local waited = 0
    while sampIsDialogActive() and not isOwnScriptDialogId(sampGetCurrentDialogId()) do
        if data.stopAction or data.collectCancelled then return false end
        if not warned then
            warned = true
            utils.addChat("{FFE133}Автосбор на паузе: закройте своё открытое окно, чтобы продолжить.")
        end
        wait(200)
        waited = waited + 200
        if maxMs and waited >= maxMs then break end
    end
    if expectedDialogId then
        return sampIsDialogActive() and sampGetCurrentDialogId() == expectedDialogId
    end
    return not sampIsDialogActive() or isOwnScriptDialogId(sampGetCurrentDialogId())
end

function requestRunner()
    return effil.thread(function(httpMethod, url, requestBody)
        local requestLib = require('requests')
        local success, response = pcall(requestLib.request, httpMethod, url, requestBody)
        if success then
            response.json, response.xml = nil
            return true, response
        else
            return false, tostring(response)
        end
    end)
end

function handleAsyncHttpRequestThread(requestThread, successCallback, errorCallback)
    local threadStatus, threadError
    repeat
        threadStatus, threadError = requestThread:status()
        wait(0)
    until threadStatus ~= 'running'
    if not threadError then
        if threadStatus == 'completed' then
            local requestSuccess, response = requestThread:get(0)
            if requestSuccess then successCallback(response) else errorCallback(response) end
            return
        elseif threadStatus == 'canceled' then
            return errorCallback(threadStatus)
        end
    else
        return errorCallback(tostring(threadError))
    end
end

function asyncHttpRequest(httpMethod, url, requestBody, successCallback, errorCallback)
    requestBody         = requestBody or {}
    requestBody.headers = requestBody.headers or {}

    local requestThread = requestRunner()(httpMethod, url, requestBody)
    successCallback     = successCallback or function() end
    errorCallback       = errorCallback or function() end

    return {
        effilRequestThread  = requestThread,
        luaHttpHandleThread = lua_thread.create(
            handleAsyncHttpRequestThread, requestThread, successCallback, errorCallback
        )
    }
end

local updateState = {
    hasUpdate     = false,
    latestVersion = nil,
    updateUrl     = nil,
    changelog     = "",
    showPopup     = imgui.new.bool(false),
    declined      = false,
    checking      = false,
    postponeUntil = 0,
    forceShowPopup = false,
    shownFlash    = false,
    flashOpenAsked = false,
}


function updatePopupShouldShow()
    if not updateState.hasUpdate then return false end
    if updateState.declined then return false end
    if (updateState.postponeUntil or 0) > os.time() then return false end
    return true
end

function updatePopupOpen(force)
    if not force and not updatePopupShouldShow() then return false end
    if not updateState.hasUpdate then return false end
    updateState.showPopup[0] = true
    return true
end
function downloadAndUpdate()
    if not updateState.updateUrl then return end
    utils.addChat("{FFE133}Загружаю обновление...")
    updateState.showPopup[0] = false

    asyncHttpRequest("GET", updateState.updateUrl, {}, function(resp)
        if resp.status_code == 200 or resp.status_code == 201 then
            local oldPath = thisScript().path
            local dir = oldPath:match("(.+)[/\\]")
            local newPath = dir .. "\\Mining Tools.lua"
            local sameFile = (oldPath:lower() == newPath:lower())

            local file = io.open(newPath, "wb")
            if file then
                file:write(resp.text)
                file:close()
                wait(50)

                -- Always write then single reload of THIS script to avoid double load/welcome
                if not sameFile then
                    -- keep one script: unload others with same name after reload target exists
                    wait(50)
                end
                utils.addChat("{BEF781}Update saved. Reloading...")
                wait(100)
                thisScript():reload()
            else
                utils.addChat("{F78181}Не удалось сохранить файл обновления.")
            end
        else
            utils.addChat("{F78181}Ошибка загрузки: HTTP " .. tostring(resp.status_code))
        end
    end, function()
        utils.addChat("{F78181}Ошибка соединения при загрузке обновления.")
    end)
end

function checkForUpdates()
    if not cfg.checkForUpdates or updateState.checking then return end
    if UPDATE_CHECK_URL == nil then return end
    updateState.checking = true
    utils.debugChat("[UPDATE] Проверяю обновления...")

    local checkUrl = UPDATE_CHECK_URL .. ((UPDATE_CHECK_URL:find('?', 1, true) and '&' or '?') .. 't=' .. tostring(os.time()))
    asyncHttpRequest("GET", checkUrl, { headers = { ['User-Agent'] = 'MiningTools-MoonLoader', ['Cache-Control'] = 'no-cache' } }, function(resp)
        updateState.checking = false
        if resp.status_code == 200 or resp.status_code == 304 then
            local json     = require('dkjson')
            local ok, info = pcall(json.decode, resp.text)
            if ok and info and info.latest then
                if info.latest ~= script.this.version then
                    updateState.hasUpdate     = true
                    updateState.latestVersion = info.latest
                    updateState.updateUrl     = info.updateurl
                    updateState.changelog     = u8:decode(info.changelog or "")
                    updateState.showPopup[0]  = false
                    updateState.declined     = false
                    if updateState.forceShowPopup then
                        updateState.showPopup[0] = true
                        updateState.forceShowPopup = false
                    end
                    -- Popup opens only when player opens /flashminer (not on server join)
                    utils.debugChat("[UPDATE] Доступна версия: " .. info.latest)
                else
                    utils.debugChat("[UPDATE] Версия актуальна (" .. info.latest .. ")")
                end
            else
                utils.debugChat("[UPDATE] Не удалось разобрать ответ сервера")
            end
        else
            utils.debugChat("[UPDATE] HTTP ошибка: " .. tostring(resp.status_code))
        end
    end, function(err)
        updateState.checking = false
        utils.debugChat("[UPDATE] Ошибка соединения: " .. tostring(err or "unknown"))
    end)
end

local progressTracker = {
    reset = function()
        data.progressCurrent = 0
        data.progressTotal = 0
        data.progressHouseCurrent = 0
        data.progressHouseTotal = 0
    end,
    setTotal = function(total, houseTotal)
        data.progressTotal = total or 0
        data.progressHouseTotal = houseTotal or 0
    end,
    setHouseTotal = function(houseTotal)
        data.progressHouseTotal = houseTotal or 0
        data.progressHouseCurrent = 0
    end,
    increment = function(isHouse)
        if isHouse then
            data.progressHouseCurrent = data.progressHouseCurrent + 1
        else
            data.progressCurrent = data.progressCurrent + 1
        end
    end
}

local dialogActions = {
    selectHouse = function(sr, houseIndex)
        local selectedFromFlashminer = data.dialogData.flashminer[(tonumber(houseIndex) or -1) + 1]
        if selectedFromFlashminer then
            setPendingHouseNumber(selectedFromFlashminer.house_number)
        end
        sr(dialogIdTable.houseDialogId, 1, houseIndex, "")
    end,
    selectCard = function(sr, cardIndex)
        local dialogId = data.isFlashminer and dialogIdTable.houseFlashMinerDialogId or dialogIdTable.videoCardSt
        sr(dialogId, 1, cardIndex, "")
    end,
    closeDialog = function(sr, dialogId)
        sr(dialogId or dialogIdTable.houseFlashMinerDialogId, 0, 0, "")
    end,
    withdrawBTC = function(sr)
        sr(dialogIdTable.videoCardDialogId, 1, 1, "")
        sr(dialogIdTable.videoCardAcceptDialogId, 1, 0, "")
    end,
    withdrawASC = function(sr)
        sr(dialogIdTable.videoCardDialogId, 1, 2, "")
        sr(dialogIdTable.videoCardAcceptDialogId, 1, 0, "")
    end,
    switchCard = function(sr)
        sr(dialogIdTable.videoCardDialogId, 1, 0, "")
        sr(dialogIdTable.videoCardDialogId, 0, 0, "")
    end,
    refillCoolant = function(sr, fluidType, useSuper, isAsic)
        local coolantIndex
        if data.isRodina then
            coolantIndex = isAsic and 3 or 2
        else
            coolantIndex = isAsic and 4 or 3
        end
        sr(dialogIdTable.videoCardDialogId, 1, coolantIndex, "")
        local fluid_listitem = (fluidType == 1 and (useSuper and 1 or 0)) or
            (fluidType == 2 and (useSuper and 1 or 2))
        if fluid_listitem ~= nil then
            sr(dialogIdTable.coolantDialogId, 1, fluid_listitem, "")
        end
    end
}

-- Склонение русских существительных по числу (1 карта / 2 карты / 5 карт)
local function ruPlural(n, one, few, many)
    n = math.abs(n or 0)
    local mod100 = n % 100
    local mod10  = n % 10
    if mod100 >= 11 and mod100 <= 14 then return many end
    if mod10 == 1 then return one end
    if mod10 >= 2 and mod10 <= 4 then return few end
    return many
end

-- Логи
local logsTool = (function()
    local self                = {}

    -- До фикса лог доходности хранился в одном общем файле на всех серверах/аккаунтов
    -- (в отличие от config.json, который уже был per-profile) — из-за этого после
    -- смены профиля (сервер/ник) в интерфейсе показывалась накопленная статистика
    -- со старого сервера. Теперь logs.json тоже лежит внутри папки профиля.
    -- Legacy-путь остаётся как fallback только на самый первый запуск, пока профиль
    -- ещё не определён (до первого коннекта/ника).
    local _logsPath           = activeProfileKey and getProfileLogsPath(activeProfileKey)
        or (getWorkingDirectory() .. '\\config\\' .. thisScript().name .. '\\logs.json')
    local _logs               = {}
    local _cache              = { collectBtc = 0, collectAsc = 0, sessions = 0 }
    local _statsCache         = { dirty = true, buildDate = "", byPeriod = {} }
    local _lastCoolantLogTime = 0

    local actions             = {
        collect = {
            icon   = fa.COINS,
            label  = "Сбор крипты",
            format = function(e)
                local parts = {}
                if (e.btc or 0) > 0 then table.insert(parts, string.format("%d BTC", e.btc)) end
                if (e.asc or 0) > 0 then table.insert(parts, string.format("%d ASC", e.asc)) end
                if (e.houses or 0) > 1 then table.insert(parts, string.format("%d %s", e.houses, ruPlural(e.houses, "дом", "дома", "домов"))) end
                return table.concat(parts, "  ·  ")
            end,
        },
        switch = {
            iconFn  = function(e) return e.enabled and fa.POWER_OFF or fa.PLUG end,
            labelFn = function(e) return e.enabled and "Включение карт" or "Выключение карт" end,
            format  = function(e)
                local parts = {}
                if (e.count or 0) > 0 then table.insert(parts, string.format("%d %s", e.count, ruPlural(e.count, "карта", "карты", "карт"))) end
                if (e.houses or 0) > 0 then table.insert(parts, string.format("%d %s", e.houses, ruPlural(e.houses, "дом", "дома", "домов"))) end
                return table.concat(parts, "  ·  ")
            end,
        },
        coolant = {
            icon   = fa.DROPLET,
            label  = "Заливка жидкости",
            format = function(e)
                local parts = {}
                if (e.count or 0) > 0 then table.insert(parts, string.format("%d %s", e.count, ruPlural(e.count, "карта", "карты", "карт"))) end
                if (e.bottles or 0) > 0 then
                    table.insert(parts, e.super
                        and string.format("%d супер", e.bottles)
                        or string.format("%d шт.", e.bottles))
                end
                return table.concat(parts, "  ·  ")
            end,
        },
        fix = {
            icon   = fa.WAND_MAGIC_SPARKLES,
            label  = "Авто-обслуживание",
            format = function(e)
                local parts = {}
                if (e.btc or 0) > 0 then table.insert(parts, string.format("%d BTC", e.btc)) end
                if (e.asc or 0) > 0 then table.insert(parts, string.format("%d ASC", e.asc)) end
                if (e.cards or 0) > 0 then table.insert(parts, string.format("%d вкл.", e.cards)) end
                if (e.topup or 0) > 0 then table.insert(parts, string.format("$%s", utils.formatNumber(e.topup))) end
                return table.concat(parts, "  ·  ")
            end,
        },
        topup = {
            icon   = fa.DOLLAR_SIGN,
            label  = "Пополнение баланса",
            format = function(e)
                local parts = {}
                if (e.topup or 0) > 0 then table.insert(parts, string.format("$%s", utils.formatNumber(e.topup))) end
                if (e.houses or 0) > 0 then table.insert(parts, string.format("%d %s", e.houses, ruPlural(e.houses, "дом", "дома", "домов"))) end
                return table.concat(parts, "  ·  ")
            end,
        },
        tax = {
            icon   = fa.FILE_INVOICE_DOLLAR,
            label  = "Оплата налогов",
            format = function(e)
                return (e.amount or 0) > 0
                    and string.format("$%s", utils.formatNumber(e.amount))
                    or ""
            end,
        },
    }


    local function isDateInPeriod(dateStr, period)
        if period == 0 then return true end
        local d, m, y = dateStr:match("(%d+)%.(%d+)%.(%d+)")
        if not d then return false end
        if period == 1 then return dateStr == os.date('%d.%m.%Y') end
        local entryTime = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
        local diff = os.time() - entryTime
        if period == 2 then return diff < 7 * 86400 end
        if period == 3 then return diff < 30 * 86400 end
        return true
    end

    local function rebuildCache()
        _cache.collectBtc = 0
        _cache.collectAsc = 0
        _cache.sessions   = 0
        for _, dayEntries in pairs(_logs) do
            for _, e in ipairs(dayEntries) do
                _cache.sessions = _cache.sessions + 1
                if (e.action or 'collect') == 'collect' then
                    _cache.collectBtc = _cache.collectBtc + (e.btc or 0)
                    _cache.collectAsc = _cache.collectAsc + (e.asc or 0)
                end
            end
        end
    end

    local function rebuildStats()
        local result = {}
        for p = 0, 3 do
            result[p] = {
                btc                    = 0,
                asc                    = 0,
                collectSessions        = 0,
                switchOn               = 0,
                switchOff              = 0,
                coolantCards           = 0,
                coolantBottles         = 0,
                coolantSuper           = 0,
                topup                  = 0,
            }
        end
        for dateStr, dayEntries in pairs(_logs) do
            local inP = {}
            for p = 0, 3 do inP[p] = isDateInPeriod(dateStr, p) end
            for _, e in ipairs(dayEntries) do
                local act = e.action or 'collect'
                for p = 0, 3 do
                    if inP[p] then
                        local s = result[p]
                        if act == 'collect' then
                            s.btc = s.btc + (e.btc or 0)
                            s.asc = s.asc + (e.asc or 0)
                            s.collectSessions = s.collectSessions + 1
                        elseif act == 'switch' then
                            if e.enabled then
                                s.switchOn = s.switchOn + (e.count or 0)
                            else
                                s.switchOff = s.switchOff + (e.count or 0)
                            end
                        elseif act == 'coolant' then
                            s.coolantCards = s.coolantCards + (e.count or 0)
                            if e.super then
                                s.coolantSuper = s.coolantSuper + (e.bottles or 0)
                            else
                                s.coolantBottles = s.coolantBottles + (e.bottles or 0)
                            end
                        elseif act == 'fix' then
                            s.btc = s.btc + (e.btc or 0)
                            s.asc = s.asc + (e.asc or 0)
                            s.switchOn = s.switchOn + (e.cards or 0)
                            s.topup = s.topup + (e.topup or 0)
                        elseif act == 'topup' then
                            s.topup = s.topup + (e.topup or 0)
                        end
                    end
                end
            end
        end
        _statsCache.byPeriod = result
        _statsCache.dirty = false
        _statsCache.buildDate = os.date('%d.%m.%Y')
    end

    function self.load()
        local result = jcfg.load(_logsPath)
        if type(result) == 'table' then _logs = result end
        rebuildCache()
        self.invalidate()
    end

    function self.save()
        jcfg.save(_logs, _logsPath)
    end

    function self.add(action, details)
        local dateStr = os.date('%d.%m.%Y')
        local timeStr = os.date('%H:%M')
        if not _logs[dateStr] then _logs[dateStr] = {} end
        local serverName = isSampAvailable and isSampAvailable() and sampGetCurrentServerName() or nil
        local entry = { time = timeStr, action = action, isVC = data.isViceCity, server = serverName }
        for k, v in pairs(details or {}) do entry[k] = v end
        table.insert(_logs[dateStr], entry)
        _cache.sessions = _cache.sessions + 1
        if action == 'collect' or action == 'fix' then
            _cache.collectBtc = _cache.collectBtc + (details.btc or 0)
            _cache.collectAsc = _cache.collectAsc + (details.asc or 0)
        end
        self.invalidate()
        self.save()
    end

    function self.addCoolant(count, bottles, isSuper)
        local now = os.time()
        if now - _lastCoolantLogTime < 10 then
            local dateStr = os.date('%d.%m.%Y')
            if _logs[dateStr] and #_logs[dateStr] > 0 then
                local last = _logs[dateStr][#_logs[dateStr]]
                if last.action == 'coolant' then
                    last.count   = (last.count or 0) + count
                    last.bottles = (last.bottles or 0) + bottles
                    self.invalidate()
                    self.save()
                    return
                end
            end
        end
        _lastCoolantLogTime = now
        self.add('coolant', { count = count, bottles = bottles, super = isSuper })
    end

    function self.getEntriesByDate(dateStr) return _logs[dateStr] or {} end

    function self.getAllByDate() return _logs end

    function self.getCacheSummary() return _cache end

    function self.getStats(period)
        local today = os.date('%d.%m.%Y')
        if _statsCache.dirty or _statsCache.buildDate ~= today then
            rebuildStats()
        end
        return _statsCache.byPeriod[period] or _statsCache.byPeriod[0]
    end

    function self.getAction(action) return actions[action] end

    function self.format(entry)
        local spec = actions[entry.action or 'collect']
        if not spec then return "", "", "" end
        local icon   = spec.iconFn and spec.iconFn(entry) or spec.icon or ""
        local label  = spec.labelFn and spec.labelFn(entry) or spec.label or ""
        local detail = spec.format and spec.format(entry) or ""
        return icon, label, detail
    end

    -- \xd1\xf0\xe5\xe4\xed\xe8\xe9 \xe4\xee\xf5\xee\xe4 \xe2\xf1\xe5\xf5 \xf4\xe5\xf0\xec:
    -- 1) \xe4\xeb\xff \xea\xe0\xe6\xe4\xfb\xf5 \xf1\xf3\xf2\xee\xea (\xea\xeb\xfe\xf7 _logs \xe8\xec\xe5\xe5\xf2 \xf2\xee\xf7\xed\xee \xf4\xee\xf0\xec\xe0\xf2 %d.%m.%Y, \xf2.\xe5. 00:00-23:59)
    --    \xf1\xf3\xec\xec\xe8\xf0\xf3\xe5\xec \xe2\xe5\xf1\xfc btc/asc, \xf1\xee\xe1\xf0\xe0\xed\xed\xfb\xe9 \xe7\xe0 \xfd\xf2\xe8 \xf1\xf3\xf2\xea\xe8
    -- 2) \xf1\xea\xeb\xe0\xe4\xfb\xe2\xe0\xe5\xec \xf1\xf3\xec\xec\xfb \xe2\xf1\xe5\xf5 \xf1\xf3\xf2\xee\xea \xec\xe5\xe6\xe4\xf3 \xf1\xee\xe1\xee\xe9
    -- 3) \xe4\xe5\xeb\xe8\xec \xee\xe1\xf9\xf3\xfe \xf1\xf3\xec\xec\xf3 \xed\xe0 \xea\xee\xeb\xe8\xf7\xe5\xf1\xf2\xe2\xee \xf1\xf3\xf2\xee\xea \xf1 \xe4\xe0\xed\xed\xfb\xec\xe8
    -- filterVC: nil -- Р±РµР· С„РёР»СЊС‚СЂР° (РІСЃСЏ РёСЃС‚РѕСЂРёСЏ), true -- С‚РѕР»СЊРєРѕ Р·Р°РїРёСЃРё РёР· Р’РЎ, false -- С‚РѕР»СЊРєРѕ РЅРµ РёР· Р’РЎ
    -- filterServer: nil -- Р±РµР· С„РёР»СЊС‚СЂР°, СЃС‚СЂРѕРєР° -- С‚РѕР»СЊРєРѕ Р·Р°РїРёСЃРё СЃ СЌС‚РѕРіРѕ СЃРµСЂРІРµСЂР°
    function self.getAverageDailyIncome(filterVC, filterServer)
        local totalBtc, totalAsc, days = 0, 0, 0

        for dateStr, dayEntries in pairs(_logs) do
            local dayBtc, dayAsc, hasEntries = 0, 0, false

            for _, e in ipairs(dayEntries) do
                local act = e.action or 'collect'
                local matchesVC = filterVC == nil or e.isVC == filterVC
                local matchesServer = filterServer == nil or e.server == filterServer
                if (act == 'collect' or act == 'fix') and matchesVC and matchesServer then
                    dayBtc = dayBtc + (e.btc or 0)
                    dayAsc = dayAsc + (e.asc or 0)
                    hasEntries = true
                end
            end

            if hasEntries then
                totalBtc = totalBtc + dayBtc
                totalAsc = totalAsc + dayAsc
                days = days + 1
            end
        end

        if days == 0 then return 0, 0, 0 end

        return totalBtc / days, totalAsc / days, days
    end

    function self.invalidate() _statsCache.dirty = true end

    function self.clear()
        _logs  = {}
        _cache = { collectBtc = 0, collectAsc = 0, sessions = 0 }
        self.invalidate()
        self.save()
    end

    self.load()

    return self
end)()

logsTool.load()

-- Для парсинга
local flashminerTool = (function()
    local self = {}

    -- Города Arizona/SA-MP часто идут вместе с районом, который дублирует
    -- название города (например "Los Santos East Los Santos" — город
    -- "Los Santos" + район "East Los Santos"). Район не всегда достоверен,
    -- поэтому оставляем только сам город, без района.
    local knownCities = {
        "Vice City", "Los Santos", "San Fierro", "Las Venturas",
        "Bone County", "Tierra Robada", "Whetstone", "Red County"
    }

    local function extractMainCity(rawCity)
        if not rawCity or rawCity == "" then return rawCity end
        for _, cityName in ipairs(knownCities) do
            if rawCity:sub(1, #cityName) == cityName then
                return cityName
            end
        end
        return rawCity
    end

    local function parseList(text)
        data.dialogData.flashminer = {}

        local function parseAmount(str)
            if not str then return 0 end
            str = str:match("^%s*(.-)%s*$")

            local cash = str:match(":CASH:([%d%.]+)")
            if cash then
                return tonumber((cash:gsub("%.", ""))) or 0
            end

            local kk, k = str:match(":KK:%s*([%d%.]+)%s+:K:%s*([%d%.]+)")
            if kk and k then
                return math.floor(tonumber((kk:gsub("%.", ""))) * 1e6 + tonumber((k:gsub("%.", ""))))
            end

            kk = str:match(":KK:%s*([%d%.]+)")
            if kk then
                return math.floor(tonumber((kk:gsub("%.", ""))) * 1e6)
            end

            k = str:match(":K:%s*([%d%.]+)")
            if k then
                return tonumber((k:gsub("%.", ""))) or 0
            end

            return tonumber((str:gsub("[^%d]", ""))) or 0
        end

        data.currentFlashminerHouseNumber = nil
        data.currentFlashminerHouseAt = 0

        for line in text:gmatch("[^\r\n]+") do
            if line:find("Номер дома") or line:find("Город") or line:find("Налог") then
                goto continue
            end

            local cleanLine = tostring(line or ""):gsub("{%w+}", ""):gsub("%[%x%x%x%x%x%x%]", "")
            local is_current = cleanLine:find("%[%s*[XxХх]%s*%]") ~= nil
            cleanLine = cleanLine:gsub("^%s*%[%s*[XxХх]%s*%]%s*", "")

            local list_id, house_num = cleanLine:match("%[(%d+)%]%s+Дом №(%d+)")
            if not (list_id and house_num) then goto continue end

            local after_num = (cleanLine:match("Дом №%d+%s+(.+)") or "")
            local parts = {}
            for w in after_num:gmatch("%S+") do table.insert(parts, w) end

            local city, tax, cycles, balance, max_balance = "", nil, 0, 0, 0
            local cycles_index = nil
            for i, part in ipairs(parts) do
                cycles_index = part == "циклов" and i or cycles_index
                if cycles_index then break end
            end

            if cycles_index then
                cycles = tonumber(parts[cycles_index - 1]) or 0
                tax = tonumber(parts[cycles_index - 2])
                local city_end = tax and (cycles_index - 3) or (cycles_index - 2)
                if city_end >= 1 then
                    city = table.concat({ table.unpack(parts, 1, city_end) }, " ")
                else
                    city = ""
                end
                city = extractMainCity(city)

                local bal_paren = after_num:match("%(([^%)]+)%)")
                if bal_paren then
                    local left_str, right_str = bal_paren:match("^(.-)%s*/%s*(.-)$")
                    balance                   = parseAmount(left_str)
                    max_balance               = parseAmount(right_str)
                end
            end

            local house_data = {
                index        = tonumber(list_id),
                name         = "Дом №" .. house_num,
                house_number = tonumber(house_num),
                city         = city,
                tax          = tax,
                cycles       = cycles,
                balance      = balance,
                max_balance  = max_balance,
                is_current   = is_current,
                raw_line     = line
            }

            utils.debugChat(string.format(
                "[HOUSE] Parse #%d | city=%q tax=%s cycles=%d | raw=%q",
                house_data.house_number, house_data.city, tostring(house_data.tax),
                house_data.cycles, line))

            if is_current then
                data.currentFlashminerHouseNumber = house_data.house_number
                data.currentFlashminerHouseAt = os.clock()
                utils.debugChat(string.format("[HOUSE] Flashminer current mark detected: #%d", house_data.house_number))
            end

            table.insert(data.dialogData.flashminer, house_data)
            if not data.houseStatuses then data.houseStatuses = {} end
            if not data.houseStatuses[house_data.house_number] then
                data.houseStatuses[house_data.house_number] = {
                    status         = balance < 5000000 and "warning" or "good",
                    lastCheck      = 0,
                    needsAttention = false,
                    lastBalance    = balance
                }
            end

            ::continue::
        end
    end

    function self.parseDialogText(text) parseList(text) end

    function self.requestList(timeoutMs, cancelCheckFn)
        timeoutMs = timeoutMs or 5000
        data.dialogData.flashminer = {}
        sampSendChat("/flashminer")
        wait(200)
        local t = 0
        while #data.dialogData.flashminer == 0 and t < timeoutMs do
            wait(200); t = t + 200
            if data.hasFlashminer == false then return false end
            if cancelCheckFn and cancelCheckFn() then return false end
        end
        return #data.dialogData.flashminer > 0
    end

    function self.navigate(direction)
        if data.working then return end
        data.flashminerSwitchId.direction = direction
        data.flashminerSwitchId.id = data.dFlashminerId
        sampSendDialogResponse(data.dFlashminerId, 0, -1, "")
    end

    function self.getHouses() return data.dialogData.flashminer end

    function self.hasIt() return data.hasFlashminer ~= false end

    function self.isOpen() return data.isFlashminer end

    return self
end)()

-- Предикт
local houseFilter = (function()
    local self = {}

    function self.isExcluded(houseNum)
        return cfg.excludedHouses[tostring(houseNum)] == true
    end

    function self.hasNoBasement(houseNum)
        return cfg.housesWithoutBasement
            and cfg.housesWithoutBasement[tostring(houseNum)] == true
    end

    function self.shouldSkip(houseNum)
        return self.isExcluded(houseNum) or self.hasNoBasement(houseNum)
    end

    function self.shouldProcess(house)
        return not self.shouldSkip(house.house_number)
    end

    function self.getDailyIncome(houseNum)
        local houseId = tostring(houseNum)
        local snapshot = cfg.cardSnapshots[houseId]

        if snapshot then
            local dBtc = (snapshot.dailyBtcRate and snapshot.dailyBtcRate > 0) and snapshot.dailyBtcRate or 0
            local dAsc = (snapshot.dailyAscRate and snapshot.dailyAscRate > 0) and snapshot.dailyAscRate or 0

            -- Fallback for old configs / first ASC scan:
            -- if BTC/day is already known and the house currently has ASC too,
            -- estimate ASC/day by the current ASC/BTC balance ratio until real ASC observations appear.
            if dAsc <= 0 and dBtc > 0 then
                local status = data.houseStatuses and data.houseStatuses[tonumber(houseNum)]
                local curBtc = (status and status.earnings and tonumber(status.earnings.btc)) or 0
                local curAsc = (status and status.earnings and tonumber(status.earnings.asc)) or 0

                if curBtc <= 0 then curBtc = tonumber(snapshot.lastBtcTotal or snapshot.prevBtcTotal or 0) or 0 end
                if curAsc <= 0 then curAsc = tonumber(snapshot.lastAscTotal or snapshot.prevAscTotal or 0) or 0 end

                if curBtc > 0 and curAsc > 0 then
                    dAsc = dBtc * (curAsc / curBtc)
                end
            end

            if dBtc > 0 or dAsc > 0 then
                return dBtc, dAsc
            end
        end

        return 0, 0
    end

    return self
end)()

-- Контроль задач
local taskState = (function()
    local self = {}
    local SUPPRESS_TAIL_SEC = 0.5
    function self.refreshSuppressDialogs()
        data.suppressDialogs =
            data.working
            or data.silentWindowOpen
            or (os.clock() < (data.suppressDialogsUntil or 0))
    end

    function self.setWorking(state)
        if data.working and not state then
            data.suppressDialogsUntil = os.clock() + SUPPRESS_TAIL_SEC
        end
        data.working = state
        self.refreshSuppressDialogs()
    end

    function self.setSilent(state)
        if data.silentWindowOpen and not state then
            data.suppressDialogsUntil = os.clock() + SUPPRESS_TAIL_SEC
        end
        data.silentWindowOpen = state
        self.refreshSuppressDialogs()
    end

    function self.ifNotWorking(func)
        if not data.working then return func() end
        utils.addChat("{F78181}Уже выполняется другая операция.")
        return false
    end

    function self.isAutomationAllowed()
        if not cfg.waitForConnection then return true end
        if not data.connectionState.connected then return false end
        if os.time() < data.connectionState.readyAfterConnect then return false end
        return true
    end

    return self
end)()

-- Для заливки и включения карт
local coolantTool = (function()
    local self  = {}
    local state = {
        pending       = false,
        doneForDialog = false,
        outOfSupply   = false,
    }

    local function shouldArm()
        return (cfg.fixCoolantEnabled or cfg.autoEnableCardsOnOpen)
            and not data.isFlashminer
            and not data.working
            and not state.doneForDialog
    end

    local function refillIfNeeded()
        local needsCoolant = false
        for _, card in ipairs(data.dialogData.videocards) do
            if card.coolant < cfg.useCoolantPercent then
                needsCoolant = true
                break
            end
        end

        local willRefill                = cfg.fixCoolantEnabled and needsCoolant and not state.outOfSupply
        local fillAttempted, fillRanOut = false, false

        if willRefill then
            state.doneForDialog = true
            fillAttempted       = true

            local coolantTask   = buildTaskTable('coolant')
            coolantTask:coolant()
            while data.working do wait(200) end
            fillRanOut = data.stopBySystem == true

            if not data.stopAction then
                for _, card in ipairs(data.dialogData.videocards) do
                    if card.coolant < cfg.useCoolantPercent then
                        card.coolant = 100
                    end
                end
            end
            if fillRanOut then state.outOfSupply = true end
            data.stopAction   = false
            data.stopBySystem = false
            wait(300)
        end
        return fillAttempted
    end

    local function enableIfNeeded(fillAttempted)
        local hasEnableable = false
        for _, card in ipairs(data.dialogData.videocards) do
            if not card.working and card.coolant > 0 then
                hasEnableable = true
                break
            end
        end
        local should = (cfg.autoEnableCardsOnOpen and hasEnableable)
            or (cfg.autoEnableCards and fillAttempted and hasEnableable)
        if should and not data.working then
            local switchTask = buildTaskTable('switchCards')
            switchTask:switchCards(true)
            while data.working do wait(200) end
        end
    end

    function self.handleShowDialog(dialogId, style, title, button1, button2, text, placeholder)
        if shouldArm() then state.pending = true end
        return false
    end

    function self.handleDialogClose(dialogId, button, listitem, input)
        if dialogId == dialogIdTable.videoCardSt
            or dialogId == dialogIdTable.videoCardDialogId
            or dialogId == dialogIdTable.houseFlashMinerDialogId then
            state.outOfSupply   = false
            state.doneForDialog = false
            state.pending       = false
        end
    end

    function self.tick()
        if not (state.pending and not data.working) then return end
        state.pending = false
        wait(200)
        if data.working then return end
        local fillAttempted = refillIfNeeded()
        enableIfNeeded(fillAttempted)
        state.doneForDialog = false
    end

    function self.resetSupplyFlag()
        state.outOfSupply = false
    end

    function self.isOutOfSupply() return state.outOfSupply end

    return self
end)()

-- Для оплаты налогов
local taxTool = (function()
    local self  = {}
    local state = {
        capturedAmount = 0,
    }

    function self.handleShowDialog(dialogId, style, title, button1, button2, text, placeholder)
        if (title or ''):find("Оплата всех налогов")
            and (text or ''):find("нет налогов")
            and data.taskTypeNow == 'autoPayTaxes' then
            sampSendDialogResponse(dialogId, 1, 0, "")
            return true
        end
        return false
    end

    function self.handleServerMessage(color, text)
        if not data.working then return false end
        if (text or ''):find("Вы оплатили все налоги на сумму") then
            local amount_str = text:match("%$([%d%.,%s]+)")
            if amount_str then
                local clean = amount_str:gsub("[^%d]", "")
                if clean ~= "" then state.capturedAmount = tonumber(clean) or 0 end
            end
            return true
        end
        return false
    end

    function self.tickTimer(now)
        if data.working then return end
        if not cfg.cheatModeEnabled then return end
        if not (cfg.autoPayTaxesEnabled and cfg.autoPayTaxesByTimer) then return end
        if (cfg.lastTaxPayTime + cfg.autoPayTaxesInterval * 3600) > now then return end
        runSilentTask('autoPayTaxes')
    end

    function self.runWithCollect()
        if not (cfg.cheatModeEnabled
                and cfg.autoPayTaxesEnabled
                and cfg.autoPayTaxesWithCollect) then
            return
        end
        wait(300)
        while data.working do wait(200) end
        local taxTask = buildTaskTable('autoPayTaxes')
        taxTask:run()
        wait(500)
        while data.working do wait(200) end
    end

    function self.resetCapturedAmount() state.capturedAmount = 0 end

    function self.getCapturedAmount() return state.capturedAmount end

    return self
end)()

-- Для пополнения баланса
local autoTopUpTool = (function()
    local self  = {}
    local state = {
        lastThresholdCheckAt = 0,
    }

    function self.tickTimer(now)
        if data.working then return end
        if not cfg.cheatModeEnabled then return end
        if not cfg.autoTopUpEnabled then return end

        if cfg.autoTopUpByTimer
            and (cfg.lastAutoTopUpTime + cfg.autoTopUpTimerInterval * 3600) <= now then
            runSilentTask('autoTopUp')
            return
        end

        if cfg.autoTopUpByThreshold
            and (now - state.lastThresholdCheckAt) >= 300 then
            state.lastThresholdCheckAt = now
            for _, house in ipairs(data.dialogData.flashminer) do
                if houseFilter.shouldProcess(house) and house.balance < cfg.autoTopUpThreshold then
                    runSilentTask('autoTopUp')
                    return
                end
            end
        end
    end

    function self.runWithCollect()
        if not (cfg.cheatModeEnabled
                and cfg.autoTopUpEnabled
                and cfg.autoTopUpWithCollect) then
            return
        end
        wait(300)
        while data.working do wait(200) end
        if flashminerTool.requestList(5000) then
            local topUpTask = buildTaskTable('autoTopUp')
            topUpTask:run()
            wait(500)
            while data.working do wait(200) end
        end
    end

    return self
end)()

-- Для переодического обновления домов
local autoRefreshTool = (function()
    local self  = {}
    local state = {
        postponedUntil = 0,
    }

    function self.runSilent()
        local result = withSilentFlashminer(function()
            local updateTask = buildTaskTable('updateStatuses')
            updateTask:run()
            wait(300)
            while data.working do wait(200) end
        end)
        cfg.lastAutoRefreshTime = os.time()
        save()
        if result then
            utils.debugChat("[REFRESH] Фоновое обновление статусов завершено.")
        end
        return result
    end

    function self.tickTimer(now)
        if not cfg.autoRefreshEnabled then return end
        if (cfg.lastAutoRefreshTime + cfg.autoRefreshInterval * 60) > now then return end
        if now < state.postponedUntil then return end

        if cfg.refreshPostponeOnDialog
            and sampIsDialogActive()
            and not data.silentWindowOpen then
            state.postponedUntil = now + cfg.refreshPostponeMinutes * 60
            utils.debugChat(string.format(
                "[REFRESH] Диалог открыт — обновление отложено на %d мин.",
                cfg.refreshPostponeMinutes))
        else
            self.runSilent()
        end
    end

    function self.getPostponedUntil() return state.postponedUntil end

    return self
end)()

-- Для автосбора
local collectTool = (function()
    local self = {}

    local triggerState = { reminder = {}, scheduled = {}, smart = {} }

    -- FIX: СЂР°РЅСЊС€Рµ Р·РґРµСЃСЊ СЃСѓРјРјРёСЂРѕРІР°Р»РёСЃСЊ "СЃС‹СЂС‹Рµ" st.earnings.btc/asc вЂ” С‚Рѕ РµСЃС‚СЊ
    -- Р·РЅР°С‡РµРЅРёСЏ РЅР° РјРѕРјРµРЅС‚ РџРћРЎР›Р•Р”РќР•Р“Рћ РѕС‚РєСЂС‹С‚РёСЏ РґРёР°Р»РѕРіР° РґРѕРјР°/СЃС‚РѕР№РєРё, Р±РµР· СѓС‡С‘С‚Р°
    -- РІСЂРµРјРµРЅРё, РїСЂРѕС€РµРґС€РµРіРѕ СЃ СЌС‚РѕРіРѕ РјРѕРјРµРЅС‚Р°. Р•СЃР»Рё РґРѕРј РґРѕР»РіРѕ РЅРµ РїСЂРѕРІРµСЂСЏР»СЃСЏ,
    -- st.earnings РѕСЃС‚Р°РІР°Р»СЃСЏ СЃС‚Р°СЂС‹Рј (Р·Р°РЅРёР¶РµРЅРЅС‹Рј), РїРѕСЌС‚РѕРјСѓ "СѓРјРЅС‹Р№ Р°РІС‚РѕСЃР±РѕСЂ"
    -- РґСѓРјР°Р», С‡С‚Рѕ РґРѕ С†РµР»Рё РµС‰С‘ РґР°Р»РµРєРѕ, С…РѕС‚СЏ РїРѕ С„Р°РєС‚Сѓ С†РµР»СЊ СѓР¶Рµ Р±С‹Р»Р° РїСЂРµРІС‹С€РµРЅР°
    -- Р·Р° СЃС‡С‘С‚ СЂРµР°Р»СЊРЅРѕРіРѕ РЅР°РєРѕРїР»РµРЅРёСЏ. РљР°Рє С‚РѕР»СЊРєРѕ РёРіСЂРѕРє РІСЂСѓС‡РЅСѓСЋ РѕС‚РєСЂС‹РІР°Р»
    -- РґРёР°Р»РѕРі СЃС‚РѕР№РєРё/РґРѕРјР°, РґР°РЅРЅС‹Рµ СЂРµР·РєРѕ РѕР±РЅРѕРІР»СЏР»РёСЃСЊ РґРѕ Р°РєС‚СѓР°Р»СЊРЅС‹С…, С‚СЂРёРіРіРµСЂ
    -- С‚СѓС‚ Р¶Рµ РІРёРґРµР» total >= cfg.smartCollectTarget Рё Р·Р°РїСѓСЃРєР°Р» СЃР±РѕСЂ вЂ” РѕС‚СЃСЋРґР°
    -- РѕС‰СѓС‰РµРЅРёРµ "С‚РєРЅСѓР» СЃС‚РѕР№РєСѓ вЂ” Рё РІРЅРµР·Р°РїРЅРѕ РЅР°С‡Р°Р»СЃСЏ СЃР±РѕСЂ", Р° СЃР°Рј СЃР±РѕСЂ СЃРЅРёРјР°Р»
    -- Р±РѕР»СЊС€Рµ С†РµР»Рё Рё РїРѕР·Р¶Рµ, С‡РµРј РґРѕР»Р¶РµРЅ Р±С‹Р» (С†РµР»СЊ Р±С‹Р»Р° РїСЂРѕР№РґРµРЅР° СѓР¶Рµ РґР°РІРЅРѕ,
    -- РїСЂРѕСЃС‚Рѕ СЃРєСЂРёРїС‚ РѕР± СЌС‚РѕРј РЅРµ Р·РЅР°Р»). РўРµРїРµСЂСЊ СЃС‡РёС‚Р°РµРј С‚Р°Рє Р¶Рµ, РєР°Рє РІ
    -- estimateTotalBTC(): known + (РґРЅРµРІРЅРѕР№ РґРѕС…РѕРґ / 24) * С‡Р°СЃРѕРІ СЃ РїСЂРѕРІРµСЂРєРё.
    local function getSmartAggregate()
        local hasData, totalBtc, totalAsc, totalDailyBtc, totalDailyAsc = false, 0, 0, 0, 0
        local now = os.time()
        for _, house in ipairs(data.dialogData.flashminer) do
            if not houseFilter.shouldSkip(house.house_number) then
                local st = data.houseStatuses[house.house_number]
                if st and st.lastCheck > 0 then
                    local dBtc, dAsc = houseFilter.getDailyIncome(house.house_number)
                    local hoursSinceCheck = (now - st.lastCheck) / 3600
                    local knownBtc = (st.earnings and st.earnings.btc) or 0
                    local knownAsc = (st.earnings and st.earnings.asc) or 0
                    local estimatedBtc = ((dBtc or 0) / 24) * hoursSinceCheck
                    local estimatedAsc = ((dAsc or 0) / 24) * hoursSinceCheck
                    hasData       = true
                    totalBtc      = totalBtc + knownBtc + estimatedBtc
                    totalAsc      = totalAsc + knownAsc + estimatedAsc
                    totalDailyBtc = totalDailyBtc + (dBtc or 0)
                    totalDailyAsc = totalDailyAsc + (dAsc or 0)
                end
            end
        end
        return hasData, totalBtc, totalDailyBtc, totalAsc, totalDailyAsc
    end

    -- Триггеры
    local triggers = {
        {
            name = 'reminder',
            kind = 'notify_only',
            enabled = function()
                return cfg.reminderEnabled
                    and not cfg.autoCollectEnabled
                    and not cfg.smartCollectEnabled
                    and data.hasFlashminer ~= false
            end,
            tick = function(state, now)
                local estBTC, hasData, estASC = estimateTotalBTC()
                if hasData and (estBTC + (estASC or 0)) >= cfg.btcThreshold
                    and now - (state.lastShownAt or 0) > cfg.reminderInterval * 60 then
                    state.lastShownAt            = now
                    data.notifyWindow.btcAmount  = estBTC
                    data.notifyWindow.ascAmount  = estASC or 0
                    data.notifyWindow.mode       = 'reminder'
                    data.notifyWindow.autoHideAt = now + cfg.notifyShowDuration
                    data.notifyWindow.isPreview  = false
                    data.notifyWindow.show[0]    = true
                end
            end,
        },
        {
            name            = 'scheduled',
            kind            = 'collect',
            enabled         = function()
                return cfg.autoCollectEnabled and cfg.cheatModeEnabled
            end,
            getSecondsLeft  = function() return self.getTimeUntil() end,
            getCountdownAt  = function() return self.getNextTime() end,
            fireThrottleSec = function() return self.getInterval() - 60 end,
        },
        {
            name                = 'smart',
            kind                = 'collect',
            enabled             = function()
                -- ВАЖНО: раньше здесь было ещё "and not cfg.reminderEnabled".
                -- Триггер 'reminder' сам себя отключает, когда включён умный
                -- сбор (см. выше), так что это условие было лишним и создавало
                -- взаимную блокировку: если у игрока были включены ОБЕ галки
                -- ("Напоминание" и "Умный автосбор"), то реминдер корректно
                -- уступал, а умный сбор из-за этого же самого условия тоже
                -- гасил сам себя — в итоге не работало ни то, ни другое, без
                -- какой-либо ошибки или сообщения.
                return cfg.smartCollectEnabled
                    and not cfg.autoCollectEnabled
                    and cfg.cheatModeEnabled
            end,
            getSecondsLeft      = function()
                local ok, btc, dailyBtc, asc, dailyAsc = getSmartAggregate()
                if not ok then return nil end
                local totalDaily = dailyBtc + (dailyAsc or 0)
                local total = btc + (asc or 0)
                -- Если цель достигнута — возвращаем 0 (сработать)
                if total >= cfg.smartCollectTarget then
                    return 0, total, btc, asc
                end
                -- Пока нет дохода — не срабатываем
                if totalDaily <= 0 then return nil end
                local hoursLeft = (cfg.smartCollectTarget - total) / (totalDaily / 24)
                return math.floor(hoursLeft * 3600), total, btc, asc
            end,
            getCountdownAt      = function(secsLeft) return os.time() + secsLeft end,
            fireThrottleSec     = function() return 30 end,
            instantCollect      = true,
            -- Умный автосбор срабатывает без долгого предупреждения (оценка
            -- часов до цели слишком грубая, чтобы показывать заранее долгий
            -- отсчёт), но перед самим стартом сбора всё равно даём короткую
            -- паузу и предупреждаем в чат, чтобы игрок успел не открывать
            -- окна (телефон, инвентарь и т.п.), которые мешают диалогам скрипта.
            pendingDelaySec     = 30,
            pendingDelayMessage = "{FFE133}Умный автосбор запустится через 30 сек. Пожалуйста, не открывайте телефон, инвентарь и другие окна, пока идёт сбор.",
            -- FIX: total is recomputed fresh every tick from
            -- getSmartAggregate() and can in theory briefly dip below half
            -- of the target (e.g. right when one house's lastCheck just
            -- refreshed and its contribution temporarily reads low), even
            -- though pending was only just set up a moment ago. Previously
            -- this could immediately cancel a pending collect that had
            -- barely started. Now shouldCancelPending gets st (per-trigger
            -- state) and now (tick time) so it can enforce a short grace
            -- period: cancellation is only allowed once pending has been
            -- active for at least pendingCancelGraceSec seconds.
            pendingCancelGraceSec = 5,
            shouldCancelPending = function(total, st, now)
                if not total then return false end
                if st and st.pendingStartedAt and now
                    and (now - st.pendingStartedAt) < 5 then
                    return false
                end
                return total < cfg.smartCollectTarget * 0.5
            end,
        },
    }

    -- Запуск сбора по триггеру
    local function collectNow(st, now)
        cfg.lastCollectTime  = now
        st.countdownNotified = false
        st.pendingNotified   = false
        st.pendingStartedAt  = nil
        save()
        if cfg.notifyAutoCollectEnabled then
            data.notifyWindow.mode       = 'collecting'
            data.notifyWindow.autoHideAt = 0
            data.notifyWindow.isPreview  = false
            data.notifyWindow.show[0]    = true
        end
        local ok = self.runSilent(true)
        if not ok and data.hasFlashminer ~= false then
            -- Could not fetch the house list this time (typically right after
            -- switching servers, before the dialog system is fully ready).
            -- Retry soon instead of waiting for the next full interval.
            data.pendingCollectAt     = now + 120
            data.pendingCollectLocked = true
            st.pendingNotified        = false
            -- FIX: previously the notify window was left in 'collecting' mode
            -- (set above) for the whole 2-minute retry wait, which looked like
            -- the script was stuck. Now it correctly switches back to a
            -- countdown so the extra wait is visible instead of silent.
            if cfg.notifyAutoCollectEnabled then
                data.notifyWindow.countdownTarget = data.pendingCollectAt
                data.notifyWindow.mode            = 'countdown'
                data.notifyWindow.autoHideAt      = 0
                data.notifyWindow.isPreview       = false
                data.notifyWindow.show[0]         = true
            end
            utils.debugChat("[COLLECT] House list fetch failed, retry in 2 min.")
        end
    end

    -- Тик одного триггера
    local function tickTrigger(trig, now)
        if not trig.enabled() then return end
        local st = triggerState[trig.name]

        if trig.kind == 'notify_only' then
            if not data.working then trig.tick(st, now) end
            return
        end

        local secsLeft, extra = trig.getSecondsLeft()
        if not secsLeft then return end

        if secsLeft > cfg.notifyBeforeSec then st.countdownNotified = false end

        if cfg.notifyAutoCollectEnabled and not cfg.randomDelayEnabled and not trig.instantCollect then
            if secsLeft > 0 and secsLeft <= cfg.notifyBeforeSec
                and not st.countdownNotified and not data.pendingCollectLocked then
                st.countdownNotified              = true
                data.notifyWindow.countdownTarget = trig.getCountdownAt(secsLeft)
                data.notifyWindow.mode            = 'countdown'
                data.notifyWindow.source          = trig.name
                data.notifyWindow.autoHideAt      = 0
                data.notifyWindow.isPreview       = false
                data.notifyWindow.show[0]         = true
            end
            if secsLeft <= 0 and data.notifyWindow.mode == 'countdown'
                and not data.pendingCollectLocked then
                data.notifyWindow.mode = 'collecting'
            end
        end

        if secsLeft <= 0 and not data.pendingCollectLocked
            and now - cfg.lastCollectTime > trig.fireThrottleSec() then
            if cfg.refreshPostponeOnDialog and sampIsDialogActive()
                and not data.silentWindowOpen then
                cfg.lastCollectTime = cfg.lastCollectTime + 60
                utils.debugChat(string.format(
                    "[%s] Диалог открыт — автосбор отложен на 1 мин.",
                    trig.name:upper()))
            elseif cfg.randomDelayEnabled and not trig.instantCollect then
                local delay               = math.random(cfg.randomDelayMin * 60, cfg.randomDelayMax * 60)
                data.pendingCollectAt     = now + delay
                data.pendingCollectLocked = true
                st.pendingNotified        = false
                utils.debugChat(string.format("[%s] Рандомная задержка: %d сек.",
                    trig.name:upper(), delay))
            elseif trig.pendingDelaySec then
                -- Триггер с порогом: запускаем сбор через pendingDelaySec
                data.pendingCollectAt     = now + trig.pendingDelaySec
                data.pendingCollectLocked = true
                st.pendingNotified        = false
                st.pendingStartedAt       = now
                if trig.pendingDelayMessage then
                    utils.addChat(trig.pendingDelayMessage)
                end
                if cfg.notifyAutoCollectEnabled then
                    data.notifyWindow.countdownTarget = data.pendingCollectAt
                    data.notifyWindow.mode            = 'countdown'
                    data.notifyWindow.source          = trig.name
                    data.notifyWindow.autoHideAt      = 0
                    data.notifyWindow.isPreview       = false
                    data.notifyWindow.show[0]         = true
                end
            elseif not data.working then
                collectNow(st, now)
            else
                -- Скрипт занят, назначаем сбор через 30 сек
                data.pendingCollectAt     = now + 30
                data.pendingCollectLocked = true
                st.pendingNotified        = false
            end
        end

        if data.pendingCollectLocked then
            if trig.shouldCancelPending and trig.shouldCancelPending(extra, st, now) then
                data.pendingCollectLocked = false
                st.pendingNotified        = false
                st.pendingStartedAt       = nil
                utils.debugChat(string.format("[%s] Условие сброшено, отмена задержки.",
                    trig.name:upper()))
            elseif now >= data.pendingCollectAt and not data.working then
                data.pendingCollectLocked = false
                collectNow(st, now)
            elseif cfg.notifyAutoCollectEnabled then
                local pendLeft = data.pendingCollectAt - now
                if pendLeft > 0 and pendLeft <= cfg.notifyBeforeSec and not st.pendingNotified then
                    st.pendingNotified                = true
                    data.notifyWindow.countdownTarget = data.pendingCollectAt
                    data.notifyWindow.mode            = 'countdown'
                    data.notifyWindow.source          = trig.name
                    data.notifyWindow.autoHideAt      = 0
                    data.notifyWindow.isPreview       = false
                    data.notifyWindow.show[0]         = true
                end
            end
        end
    end

    function self.runSilent(doUpdateStatuses)
        if data.hasFlashminer == false then
            return false
        end
        local restoreHouseControl  = data.showHouseControlWindow[0] == true
        data.silentWindowOpen      = true
        data.showLogsWindow[0]     = false
        data.showSettingsWindow[0] = false

        -- РћР±РЅРѕРІР»СЏРµРј СЃРїРёСЃРѕРє РґРѕРјРѕРІ РїРµСЂРµРґ СЃР±РѕСЂРѕРј (РІСЃРµРіРґР°)
        data.dialogData.flashminer = {}
        local attempts = 0
        while #data.dialogData.flashminer == 0 and attempts < 3 do
            attempts = attempts + 1
            sampSendChat("/flashminer")
            local t = 0
            while #data.dialogData.flashminer == 0 and t < 8000 do
                wait(200); t = t + 200
                if data.collectCancelled then
                    data.collectCancelled = false
                    taskState.setSilent(false)
                    data.silentWindowOpen = false
                    return false
                end
            end
            if #data.dialogData.flashminer == 0 and attempts < 3 then
                utils.debugChat(string.format("[COLLECT] House list empty, retry %d/3", attempts))
                wait(500)
            end
        end
        if #data.dialogData.flashminer == 0 then
            data.silentWindowOpen     = false
            data.notifyWindow.show[0] = false
            return false
        end

        if doUpdateStatuses then
            local needsUpdate = false
            local now2 = os.time()
            for _, house in ipairs(data.dialogData.flashminer) do
                local status = data.houseStatuses[house.house_number]
                -- РћР±РЅРѕРІР»СЏРµРј РµСЃР»Рё РґР°РЅРЅС‹С… РЅРµС‚ РёР»Рё РѕРЅРё СЃС‚Р°СЂС€Рµ 5 РјРёРЅСѓС‚
                if not (status and status.lastCheck > 0 and (now2 - status.lastCheck) < 300) then
                    needsUpdate = true; break
                end
            end
            if needsUpdate then
                local updateTask = buildTaskTable('updateStatuses')
                updateTask:run()
                while data.working do
                    wait(200)
                    if data.collectCancelled then
                        data.collectCancelled = false
                        taskState.setSilent(false)
                        data.stopAction = true
                        data.silentWindowOpen = false
                        return false
                    end
                end
            end
        end

        while data.working do
            wait(200)
            if data.collectCancelled then
                data.collectCancelled = false
                taskState.setSilent(false)
                data.stopAction = true
                data.silentWindowOpen = false
                return false
            end
        end
        local task = buildTaskTable('collectFromAllHouses')
        task:run()
        while data.working do
            wait(200)
            if data.collectCancelled then
                data.collectCancelled = false
                taskState.setSilent(false)
                data.stopAction = true
                data.silentWindowOpen = false
                return false
            end
        end
        if cfg.autoEnableCardsOnCollect then
            wait(300)
            if flashminerTool.requestList(5000) then
                local switchTask = buildTaskTable('massSwitchCards')
                switchTask:run(true)
                while data.working do
                    wait(200)
                    if data.collectCancelled then
                        data.collectCancelled = false
                        taskState.setSilent(false)
                        data.stopAction = true
                        data.silentWindowOpen = false
                        return false
                    end
                end
            end
        end

        taxTool.runWithCollect()
        autoTopUpTool.runWithCollect()

        fixI()
        data.currentCollectHouse       = ""
        data.silentWindowOpen          = false
        data.showHouseControlWindow[0] = restoreHouseControl
        data.notifyWindow.show[0]      = false
        return true
    end

    function self.tickTriggers(now)
        for _, trig in ipairs(triggers) do
            tickTrigger(trig, now)
        end
    end

    function self.getInterval()
        local times = math.max(1, math.min(cfg.collectTimesPerDay, 24))
        return math.floor(86400 / times)
    end

    function self.getNextTime()
        if cfg.lastCollectTime == 0 then return os.time() end
        return cfg.lastCollectTime + self.getInterval()
    end

    function self.getTimeUntil()
        return self.getNextTime() - os.time()
    end

    function self.cancelPending()
        data.pendingCollectLocked = false
        data.pendingCollectAt     = 0
        data.collectCancelled     = true
        data.stopAction           = true
        for _, st in pairs(triggerState) do
            st.countdownNotified = false
            st.pendingNotified   = false
        end
        cfg.lastCollectTime = os.time()
        save()
    end

    function self.postponeCollect(minutes)
        minutes = minutes or 10
        local delaySec = minutes * 60
        data.collectCancelled     = true
        data.stopAction           = true
        for _, st in pairs(triggerState) do
            st.countdownNotified = false
            st.pendingNotified   = false
        end
        data.pendingCollectAt     = os.time() + delaySec
        data.pendingCollectLocked = true
        if cfg.notifyAutoCollectEnabled then
            data.notifyWindow.countdownTarget = data.pendingCollectAt
            data.notifyWindow.mode            = 'countdown'
            data.notifyWindow.autoHideAt      = 0
            data.notifyWindow.isPreview       = false
            data.notifyWindow.show[0]         = true
        end
        imgui.addNotification(u8(string.format("Сбор отложен на %d мин.", minutes)))
    end

    function self.resetPendingDelay()
        data.pendingCollectLocked = false
        data.pendingCollectAt     = 0
        for _, st in pairs(triggerState) do
            st.countdownNotified = false
            st.pendingNotified   = false
        end
    end

    return self
end)()

-- Помощь
local helpTool = (function()
    local self = {}

    local function openWindow(setter)
        setter()
    end

    local function gotoSettings(tab, subTab)
        data.showSettingsWindow[0] = true
        data.settingsTab           = tab
        if subTab ~= nil then data.cheatSubTab = subTab end
    end

    local function actionBtn(icon, label, id, onClick)
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.35, 0.08, 0.08, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.45, 0.10, 0.10, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.55, 0.13, 0.13, 1))
        if imgui.Button(icon .. "  " .. u8(label) .. "##help_" .. id, imgui.ImVec2(-1, 28)) then
            onClick()
        end
        imgui.PopStyleColor(3)
    end

    local function bullet(text)
        imgui.Text(fa.CARET_RIGHT)
        imgui.SameLine(0, 6)
        imgui.TextColoredRGB(text)
    end

    local function example(id, height, text)
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.12, 0.13, 0.09, 1))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.35, 0.32, 0.12, 1))
        imgui.BeginChild("##helpex_" .. id, imgui.ImVec2(0, height), true,
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
        imgui.TextColoredRGB("{FFE133} Пример")
        imgui.TextColoredRGB(text)
        imgui.EndChild()
        imgui.PopStyleColor(2)
    end

    local function section(icon, title)
        imgui.Text(icon)
        imgui.SameLine(0, 6)
        imgui.TextColoredRGB("{87CEFA}" .. title)
        imgui.Spacing()
    end

    local setupPages = {
        {
            title = "Добро пожаловать",
            render = function()
                section(fa.HOUSE, "Первоначальная настройка")
                imgui.TextColoredRGB(
                    "{FFFFFF}Mining Tools — помощник для майнинг-ферм:\n{C0C0C0}сбор крипты, включение карт, пополнение баланса\n{C0C0C0}и статистика.")
                imgui.Spacing()
                imgui.TextColoredRGB(
                    "{FFFFFF}Пройдём пару базовых настроек. Полное описание\n{C0C0C0}всех функций потом будет в Настройки, вкладка «Помощь».")
                imgui.Spacing()
                imgui.TextColoredRGB(
                    "{FF6B6B}ВНИМАНИЕ: автоматизация может быть запрещена\n{FF6B6B}на вашем сервере. Уточните правила и используйте\n{FF6B6B}на свой риск.")
                imgui.Spacing()
                imgui.TextColoredRGB("{87CEFA}Команды: {FFFFFF}/fls {808080}— окно, {FFFFFF}/mnt {808080}— вкл/выкл.")
            end,
        },
        {
            title = "Целевой баланс",
            render = function()
                section(fa.COINS, "Целевой баланс домов")
                imgui.TextColoredRGB(
                    "{FFFFFF}До какой суммы пополнять баланс дома при\n{C0C0C0}пополнении. Чем выше — тем реже пополнять.")
                imgui.Spacing()
                imgui.TextColoredRGB("{87CEFA}Целевой баланс:")
                imgui.PushItemWidth(-1)
                if imgui.SliderInt("##setBal", imcfg.targetHouseBalance, 5000000, 60000000,
                        u8("$" .. utils.formatNumber(imcfg.targetHouseBalance[0]))) then
                    local v = math.floor(imcfg.targetHouseBalance[0] / 100000 + 0.5) * 100000
                    cfg.targetHouseBalance = v; imcfg.targetHouseBalance[0] = v; save()
                end
                imgui.PopItemWidth()
                imgui.Spacing()
                example("setbal", 80,
                    "{C0C0C0}$20.000.000 — баланс каждого дома будет\n{C0C0C0}доводиться до 20 млн при пополнении.")
            end,
        },
        {
            title = "Скорость диалогов",
            render = function()
                section(fa.CLOCK, "Скорость диалогов")
                imgui.TextColoredRGB(
                    "{FFFFFF}Как быстро скрипт взаимодействует с диалогами.\n{C0C0C0}Меньше пауза = быстрее, но при лагах сервера\n{C0C0C0}может кикать.")
                imgui.Spacing()
                imgui.PushItemWidth(-1)
                if imgui.SliderInt("##setPause", imcfg.pause_duration, 150, 300, u8 "%d мс") then
                    cfg.pause_duration = imcfg.pause_duration[0]; save()
                end
                if imgui.SliderInt("##setCount", imcfg.count_action, 1, 20,
                        u8(string.format("пауза каждые %d", imcfg.count_action[0]))) then
                    cfg.count_action = imcfg.count_action[0]; save()
                end
                imgui.PopItemWidth()
                imgui.Spacing()
                example("setspeed", 100,
                    "{C0C0C0}Хороший пинг и фпс — 230 мс. Если начинает\n{C0C0C0}кикать античит — поднимите до 250-300 мс. \n{C0C0C0}Рекомендованные значения 250 - 8.")
            end,
        },
        {
            title = "Автоматизация стойки",
            render = function()
                section(fa.DROPLET, "Автоматизация стойки")
                imgui.TextColoredRGB("{FFFFFF}Что делать, когда вы вручную открываете стойку\n{C0C0C0}видеокарт в доме.")
                imgui.Spacing()
                if imgui.Checkbox(u8 "Авто-заливка жидкости при открытии стойки", imcfg.fixCoolantEnabled) then
                    cfg.fixCoolantEnabled = imcfg.fixCoolantEnabled[0]; save()
                end
                imgui.Hint("Доливать охлаждающую жидкость сразу при открытии стойки.")
                if imgui.Checkbox(u8 "Авто-включение карт при открытии стойки", imcfg.autoEnableCardsOnOpen) then
                    cfg.autoEnableCardsOnOpen = imcfg.autoEnableCardsOnOpen[0]
                    if cfg.autoEnableCardsOnOpen then
                        cfg.autoEnableCards = false; imcfg.autoEnableCards[0] = false
                    end
                    save()
                end
                imgui.Hint("Включать выключенные карты сразу при открытии стойки.")
            end,
        },
        {
            title = "Готово",
            render = function()
                section(fa.CIRCLE_CHECK, "Базовая настройка завершена")
                imgui.TextColoredRGB(
                    "{FFFFFF}Этого достаточно для старта. Остальные функции\n{C0C0C0}(авто-функции, уведомления, фильтры)\n{C0C0C0}настраиваются в любой момент.")
                imgui.Spacing()
                imgui.TextColoredRGB(
                    "{87CEFA}Полное описание всех возможностей — в\n{87CEFA}Настройки, вкладка «Помощь».\n{C0C0C0}Кнопка настроек находится в правом верхнем углу, рядом с кнопкой закрыть.")
                imgui.Spacing()
                actionBtn(fa.CIRCLE_QUESTION, "Открыть полную справку", "tohelp", function()
                    data.helpPage       = 1
                    data.helpWindowMode = 'reference'
                end)
            end,
        },
    }

    local refPages = {
        {
            title = "Обзор",
            render = function()
                section(fa.HOUSE, "Mining Tools")
                imgui.TextColoredRGB("{FFFFFF}Помощник для управления майнинг-фермами.")
                bullet("{C0C0C0}сбор крипты и включение видеокарт")
                bullet("{C0C0C0}пополнение баланса и оплата налогов")
                imgui.Spacing()
                imgui.TextColoredRGB("{87CEFA}Команды:")
                bullet("{FFFFFF}/fls {808080}— открыть/закрыть основное окно")
                bullet("{FFFFFF}/mnt {808080}— включить/выключить скрипт")
                bullet("{FFFFFF}/mntd {808080}— режим отладки")
            end,
        },
        {
            title = "Основное окно",
            render = function()
                section(fa.HOUSE, "Основное окно")
                imgui.TextColoredRGB(
                    "{FFFFFF}Все дома показаны карточками. На карточке видны\n{C0C0C0}статус, баланс, налог, крипта, видеокарты и\n{C0C0C0}минимальный уровень охлаждающей жидкости.")
                imgui.Spacing()
                example("mainwin", 100,
                    "{C0C0C0}Красный баланс = деньги почти кончились, дом\n{C0C0C0}скоро встанет. Жёлтая жидкость = скоро нужна\n{C0C0C0}заливка.")
            end,
        },
        {
            title = "Управление",
            render = function()
                section(fa.ARROW_UP_SHORT_WIDE, "Мышь и клавиатура")
                bullet("{FFFFFF}ЛКМ по дому {808080}— зайти в него")
                bullet("{FFFFFF}ПКМ по дому {808080}— меню (исключить и т.д.)")
                bullet("{FFFFFF}Колесо {808080}— прокрутка списка")
                imgui.Spacing()
                imgui.TextColoredRGB("{87CEFA}Стрелки (когда открыто основное окно):")
                bullet("{FFFFFF}влево / вправо {808080}— выбор соседней карты")
                bullet("{FFFFFF}вверх / вниз {808080}— переход на строку")
                bullet("{FFFFFF}Enter {808080}— зайти в выбранный дом")
                imgui.Spacing()
                example("nav", 80,
                    "{C0C0C0}Выбранный дом подсвечивается и сам\n{C0C0C0}прокручивается в зону видимости.")
            end,
        },
        {
            title = "Действия",
            render = function()
                section(fa.GEAR, "Кнопки действий")
                bullet("{FFD700}Собрать {808080}— снять крипту со всех домов")
                bullet("{87CEFA}Включить {808080}— включить все видеокарты")
                bullet("{FF6B6B}Выключить {808080}— выключить все карты")
                bullet("{FFA500}Обновить {808080}— обновить данные домов")
                bullet("{00E600}Пополнить {808080}— пополнить баланс всех домов до целевого значения. \n{808080}Можно переключить в режим Авто-обслуживания, тогда при нажатии будет выполняться не просто пополнение, а набор действий, который настраивается на вкладке «Фермы».")
                imgui.Spacing()
                imgui.TextColoredRGB(
                    "{C788FF}Авто-обслуживание {808080}— выполняет выбранный\n{808080}набор действий сразу. Что именно — настраивается\n{808080}на вкладке «Фермы».")
                imgui.Spacing()
                actionBtn(fa.GEAR, "Настроить действия обслуживания", "cfgfix", function()
                    gotoSettings(1)
                end)
            end,
        },
        {
            title = "Подсказки",
            render = function()
                section(fa.CIRCLE_QUESTION, "Подсказки")
                imgui.TextColoredRGB(
                    "{FFFFFF}Почти у каждой настройки и кнопки есть подсказка.\n{C0C0C0}Наведите курсор на элемент — появится поясняющий текст.")
                imgui.Spacing()
                example("hint", 60,
                    "{C0C0C0}Наведите на этот текст-пример... у подсказок такой вид.")
                imgui.Hint("Вот так выглядит подсказка при наведении.")
            end,
        },
        {
            title = "Баланс домов",
            render = function()
                section(fa.COINS, "Целевой баланс домов")
                imgui.TextColoredRGB(
                    "{FFFFFF}До какой суммы пополнять баланс дома при\n{C0C0C0}пополнении (кнопкой обслуживания или авто).")
                imgui.Spacing()
                imgui.PushItemWidth(-1)
                if imgui.SliderInt("##refBal", imcfg.targetHouseBalance, 5000000, 60000000,
                        u8("$" .. utils.formatNumber(imcfg.targetHouseBalance[0]))) then
                    local v = math.floor(imcfg.targetHouseBalance[0] / 100000 + 0.5) * 100000
                    cfg.targetHouseBalance = v; imcfg.targetHouseBalance[0] = v; save()
                end
                imgui.PopItemWidth()
                imgui.Spacing()
                example("refbal", 80,
                    "{C0C0C0}$20.000.000 — баланс каждого дома будет\n{C0C0C0}доводиться до 20 млн при пополнении.")
            end,
        },
        {
            title = "Заливка охлаждения",
            render = function()
                section(fa.DROPLET, "Как работает заливка")
                imgui.TextColoredRGB(
                    "{FFFFFF}Скрипт доливает охлаждающую жидкость в карты,\n{C0C0C0}у которых уровень упал ниже заданного порога.\n{C0C0C0}По умолчанию доливает до 100.\n{C0C0C0}Можно включить режим экономии, \n{C0C0C0}про него написано на следующей странице.")
                imgui.Spacing()
                bullet("{C0C0C0}порог заливки задаётся в настройках ферм")
                bullet("{C0C0C0}карты выше порога не трогаются (экономия)")
                imgui.Spacing()
                example("fill", 80,
                    "{C0C0C0}Порог 30: карта на 25 будет долита,\n{C0C0C0}карта на 60 — нет.")
            end,
        },
        {
            title = "Экономный режим",
            render = function()
                section(fa.DROPLET, "Режим экономии жидкости")
                imgui.TextColoredRGB(
                    "{FFFFFF}Экономит охлаждающую жидкость при заливке.\n{C0C0C0}Если после первой жидкости уровень охлаждения\n{C0C0C0}достигает 70 и выше — вторая не расходуется.")
                imgui.Spacing()
                bullet("{C0C0C0}работает только с обычными жидкостями")
                bullet("{C0C0C0}не работает в Вайс-Сити и для суперохлаждающих")
                bullet("{C0C0C0}без режима скрипт всегда заливает до 100%")
                imgui.Spacing()
                example("econ", 80,
                    "{C0C0C0}Одной жидкости хватило до 72 — режим\n{C0C0C0}остановится и не потратит вторую.")
                imgui.Spacing()
                actionBtn(fa.GEAR, "Открыть настройки ферм", "cfgecon", function()
                    gotoSettings(1)
                end)
            end,
        },
        {
            title = "Автоматизация стойки",
            render = function()
                section(fa.DROPLET, "Автоматизация стойки")
                imgui.TextColoredRGB(
                    "{FFFFFF}Что делать автоматически при ручном открытии\n{C0C0C0}стойки. {FF6B6B}Не работает через Флешку Майнера.")
                imgui.Spacing()
                if imgui.Checkbox(u8 "Авто-заливка жидкости при открытии стойки", imcfg.fixCoolantEnabled) then
                    cfg.fixCoolantEnabled = imcfg.fixCoolantEnabled[0]; save()
                end
                imgui.Hint("Доливать жидкость сразу при открытии стойки.")
                if imgui.Checkbox(u8 "Авто-включение карт при открытии стойки", imcfg.autoEnableCardsOnOpen) then
                    cfg.autoEnableCardsOnOpen = imcfg.autoEnableCardsOnOpen[0]
                    if cfg.autoEnableCardsOnOpen then
                        cfg.autoEnableCards = false; imcfg.autoEnableCards[0] = false
                    end
                    save()
                end
                imgui.Hint("Включать выключенные карты сразу при открытии стойки.")
            end,
        },
        {
            title = "Скорость диалогов",
            render = function()
                section(fa.CLOCK, "Скорость диалогов")
                imgui.TextColoredRGB(
                    "{FFFFFF}Как быстро скрипт взаимодействует с диалогами.\n{C0C0C0}Меньше пауза = быстрее, но при лагах сервера\n{C0C0C0}может кикать.")
                imgui.Spacing()
                imgui.PushItemWidth(-1)
                if imgui.SliderInt("##refPause", imcfg.pause_duration, 150, 300, u8 "%d мс") then
                    cfg.pause_duration = imcfg.pause_duration[0]; save()
                end
                if imgui.SliderInt("##refCount", imcfg.count_action, 1, 20,
                        u8(string.format("пауза каждые %d", imcfg.count_action[0]))) then
                    cfg.count_action = imcfg.count_action[0]; save()
                end
                imgui.PopItemWidth()
            end,
        },
        {
            title = "Уведомления",
            render = function()
                section(fa.CIRCLE_EXCLAMATION, "Окно уведомлений")
                imgui.TextColoredRGB(
                    "{FFFFFF}Всплывающее окно (например, перед автосбором).\n{C0C0C0}Длительность настраивается ниже, позицию —\n{C0C0C0}через предпросмотр.")
                imgui.Spacing()
                imgui.PushItemWidth(-1)
                if imgui.SliderInt("##refDur", imcfg.notifyShowDuration, 3, 30,
                        u8(string.format("показывать %d сек.", imcfg.notifyShowDuration[0]))) then
                    cfg.notifyShowDuration = imcfg.notifyShowDuration[0]; save()
                end
                imgui.PopItemWidth()
                imgui.Spacing()
                actionBtn(fa.WAND_MAGIC_SPARKLES, "Предпросмотр (перетащите для позиции)", "prev", function()
                    data.notifyWindow.btcAmount  = 150
                    data.notifyWindow.mode       = 'reminder'
                    data.notifyWindow.autoHideAt = os.time() + cfg.notifyShowDuration
                    data.notifyWindow.isPreview  = true
                    data.notifyWindow.show[0]    = true
                end)
            end,
        },
        {
            title = "Логи",
            render = function()
                section(fa.CLOCK_ROTATE_LEFT, "Логи")
                imgui.TextColoredRGB(
                    "{FFFFFF}Общее — все события; По дням — за день.\n{C0C0C0}Сверху выбирается период.")
                imgui.Spacing()
                actionBtn(fa.CLOCK_ROTATE_LEFT, "Открыть логи", "openlogs", function()
                    openWindow(function() data.showLogsWindow[0] = true end)
                end)
            end,
        },
        {
            title = "Авто-функции",
            render = function()
                section(fa.GEAR, "Авто-функции")
                imgui.TextColoredRGB(
                    "{FFFFFF}Автосбор по расписанию, умный автосбор,\n{C0C0C0}налоги, пополнение баланса, фоновое\n{C0C0C0}обновление и уведомления — на вкладке «Авто».")
                imgui.Spacing()
                imgui.TextColoredRGB(
                    "{FF6B6B}ВНИМАНИЕ: авто-функции могут быть запрещены\n{FF6B6B}на вашем сервере. Используйте на свой риск.")
                imgui.Spacing()
                actionBtn(fa.GEAR, "Открыть настройки авто-функций", "cfgauto", function()
                    gotoSettings(2, 0)
                end)
            end,
        },
        {
            title = "Если что-то не так",
            render = function()
                section(fa.CIRCLE_EXCLAMATION, "Частые ситуации")

                imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.30, 0.08, 0.08, 1))
                imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.55, 0.15, 0.15, 1))
                imgui.BeginChild("##help_access_warning", imgui.ImVec2(0, 100), true)
                imgui.Text(fa.TRIANGLE_EXCLAMATION)
                imgui.SameLine(0, 6)
                imgui.TextColoredRGB("{FF6B6B}Сбор / доход не происходит")
                imgui.Spacing()
                imgui.TextColoredRGB(
                    "{FFFFFF}В первую очередь проверьте права доступа:\n{C0C0C0}1) Вы владелец дома, либо вам выдан доступ (если вы\n{C0C0C0}подселены в дом — хозяин должен открыть доступ к майнингу).\n{C0C0C0}2) Открыт доступ к подвалу дома — без доступа к подвалу\n{C0C0C0}карты не сканируются и сбор невозможен.")
                imgui.EndChild()
                imgui.PopStyleColor(2)
                imgui.Spacing()

                bullet("{FFD700}Не отсканировался подвал / ошибочно «без подвала»")
                imgui.TextColoredRGB(
                    "{C0C0C0}Нажмите «Проверить подвалы» — все дома будут\n{C0C0C0}просканированы заново.")
                imgui.Spacing()
                bullet("{FFD700}Купили новый дом")
                imgui.TextColoredRGB(
                    "{C0C0C0}Откройте основное окно (/fls): новые дома\n{C0C0C0}сканируются автоматически. Если нет —\n{C0C0C0}«Проверить подвалы».")
                imgui.Spacing()
                bullet("{FFD700}При «Обновить» обновились не все дома")
                imgui.TextColoredRGB("{C0C0C0}Просто нажмите «Обновить» ещё раз.")
                imgui.Spacing()
                bullet("{FFD700}Действие зависло / прервалось")
                imgui.TextColoredRGB(
                    "{C0C0C0}Дождитесь конца PayDay или перезапустите действие по новой.\n{C0C0C0}Пауза на PayDay позволяет избежать кика при пролаге сервера.")
                imgui.Spacing()
                actionBtn(fa.BOX_OPEN, "Проверить подвалы (пересканировать всё)", "rescan", function()
                    if not data.working then
                        local task                 = buildTaskTable('scanBasements')
                        data.showHelpWindow[0]     = false
                        data.showSettingsWindow[0] = false
                        runTaskAndReopenDialog(function() task:run(nil) end)
                    else
                        utils.addChat("{F78181}Дождитесь завершения текущей операции.")
                    end
                end)
            end,
        },
    }

    local function pager(pages, pageKey, idPrefix)
        local total = #pages
        if data[pageKey] < 1 then data[pageKey] = 1 end
        if data[pageKey] > total then data[pageKey] = total end
        local page = pages[data[pageKey]]

        imgui.Text(fa.CIRCLE_QUESTION)
        imgui.SameLine(0, 6)
        imgui.TextColoredRGB(string.format("{FFFFFF}%s  {808080}(%d/%d)",
            page.title, data[pageKey], total))
        imgui.Separator()
        imgui.Spacing()

        page.render()

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        local availW  = imgui.GetContentRegionAvail().x
        local gap     = imgui.GetStyle().ItemSpacing.x
        local btnW    = (availW - gap) / 2
        local atStart = data[pageKey] <= 1
        local atEnd   = data[pageKey] >= total

        if atStart then imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.10, 0.10, 0.10, 1)) end
        if imgui.Button(fa.ARROW_LEFT .. "  " .. u8("Назад") .. "##" .. idPrefix .. "Prev", imgui.ImVec2(btnW, 30)) and not atStart then
            data[pageKey] = data[pageKey] - 1
        end
        if atStart then imgui.PopStyleColor() end

        imgui.SameLine(0, gap)

        if atEnd then imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.10, 0.10, 0.10, 1)) end
        if imgui.Button(u8("Далее") .. "  " .. fa.ARROW_RIGHT .. "##" .. idPrefix .. "Next", imgui.ImVec2(btnW, 30)) and not atEnd then
            data[pageKey] = data[pageKey] + 1
        end
        if atEnd then imgui.PopStyleColor() end
    end

    function self.pageCount() return #refPages end

    function self.setupPageCount() return #setupPages end

    function self.renderReference() pager(refPages, 'helpPage', 'helpRef') end

    function self.renderSetup() pager(setupPages, 'setupPage', 'helpSetup') end

    return self
end)()

local houseStatusHelper = {
    colors = {
        bad = imgui.ImVec4(1, 0.2, 0.2, 1),
        warning = imgui.ImVec4(1, 0.88, 0.2, 1),
        good = imgui.ImVec4(0.3, 1, 0.3, 1),
        unknown = imgui.ImVec4(0.5, 0.5, 0.5, 1),
    },

    icons = {
        bad = fa.CIRCLE_EXCLAMATION,
        warning = fa.TRIANGLE_EXCLAMATION,
        good = fa.CIRCLE_CHECK,
        unknown = fa.CIRCLE_QUESTION,
    },

    colorStrings = {
        bad = "{FF3333}",
        warning = "{FFE133}",
        good = "{4DE94C}",
        unknown = "{808080}",
    },

    getColor = function(self, statusType)
        return self.colors[statusType] or self.colors.unknown
    end,

    getIcon = function(self, statusType)
        return self.icons[statusType] or self.icons.unknown
    end,

    getColorString = function(self, statusType)
        return self.colorStrings[statusType] or self.colorStrings.unknown
    end,

    determineStatus = function(self, house, status, isExcluded, isNoBasement)
        if isNoBasement then
            return "no_basement"
        end

        if isExcluded then
            return "good"
        end

        if not (status and status.lastCheck > 0) then
            return "unknown"
        end

        return status.status or "unknown"
    end,

    buildTooltip = function(self, status, house, isNoBasement)
        local lines = {}
        if isNoBasement then
            table.insert(lines, 1, "В доме нет подвала")
            table.insert(lines, 2, "--------------------")
        elseif not (status and status.lastCheck > 0) then
            lines = { "Статус неизвестен (дом не проверялся)" }
        elseif status.issues and #status.issues > 0 then
            for _, issue in ipairs(status.issues) do
                table.insert(lines, "• " .. issue)
            end
        else
            lines = { "Проблем не обнаружено" }
        end

        if house.tax and house.tax > 50000 then
            table.insert(lines, string.format("Высокий налог: $%s", utils.formatNumber(house.tax)))
        end

        return table.concat(lines, "\n")
    end
}

function formatEarnings(btc, asc, includeAsc, separator)
    separator = separator or " {FFFFFF}| "
    local parts = {}
    if btc and btc > 0 then
        table.insert(parts, string.format("{D2691E}%d BTC", btc))
    end
    if asc and asc > 0 and includeAsc then
        table.insert(parts, string.format("{C0392B}%d ASC", asc))
    end
    if #parts == 0 then return "{808080}0", false end
    return table.concat(parts, separator), true
end

-- Возвращает город, захваченный из имени сервера Arizona (например "Los Santos"
-- или "Vice City"), либо nil, если имя не соответствует формату Arizona RP.
function getArizonaCityFromServerName(serverName)
    serverName = serverName or (isSampAvailable() and sampGetCurrentServerName())
    if not serverName then return nil end
    return serverName:match("^Arizona [^|]+ | ([^|]+) |") or serverName:match("^Arizona [^|]+ | ([^|]+)$")
end

function isArizonaServer()
    local serverName = sampGetCurrentServerName()
    local isMatch = getArizonaCityFromServerName(serverName)
    return isMatch ~= nil
end

function estimateTotalBTC()
    local totalBtc = 0
    local totalAsc = 0
    local hasAnyData = false

    for _, house in ipairs(data.dialogData.flashminer) do
        if houseFilter.shouldSkip(house.house_number) then goto skip_house end

        -- Р¤РёР»СЊС‚СЂ РїРѕ С‚РµРєСѓС‰РµРјСѓ СЂРµР¶РёРјСѓ: РІ Vice City СЃС‡РёС‚Р°РµРј С‚РѕР»СЊРєРѕ РґРѕРјР° РІ Vice City,
        -- РІРЅРµ Vice City -- С‚РѕР»СЊРєРѕ РґРѕРјР° РІ РґСЂСѓРіРёС… РіРѕСЂРѕРґР°С…
        local houseIsVC = house.city and house.city:find("Vice City", 1, true) ~= nil
        if data.isViceCity ~= houseIsVC then goto skip_house end

        local status = data.houseStatuses[house.house_number]
        if not (status and status.lastCheck > 0) then goto skip_house end

        hasAnyData = true

        local knownBtc = (status.earnings and status.earnings.btc) or 0
        local knownAsc = (status.earnings and status.earnings.asc) or 0

        local hoursSinceCheck = (os.time() - status.lastCheck) / 3600
        local dailyBtc, dailyAsc = houseFilter.getDailyIncome(house.house_number)

        local estimatedBtc = ((dailyBtc or 0) / 24) * hoursSinceCheck
        local estimatedAsc = ((dailyAsc or 0) / 24) * hoursSinceCheck

        totalBtc = totalBtc + knownBtc + estimatedBtc
        totalAsc = totalAsc + knownAsc + estimatedAsc

        ::skip_house::
    end

    return totalBtc, hasAnyData, totalAsc
end

function formatTimeLeft(seconds)
    if seconds <= 0 then return u8 "уже пора!" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if seconds <= 60 then
        return string.format("%dс", math.floor(seconds))
    elseif h > 0 then
        return string.format("%dч %dм", h, m)
    else
        return string.format("%dм %dс", m, s)
    end
end

function smart_wait(total_duration_ms, start_time_clock)
    if start_time_clock then
        local remaining_time_ms = total_duration_ms - (os.clock() - start_time_clock) * 1000

        if remaining_time_ms > 0 then
            wait(remaining_time_ms)
        else
            wait(0)
        end
    else
        wait(total_duration_ms)
    end
end

function fixI()
    lua_thread.create(function()
        wait(0)
        data.fix = true
        -- FIX: раньше здесь посылалась команда "/mm", которая на Arizona открывает кастомный
        -- чат-панель с вкладками ("Общий/Семья/VIP..."), который не является SAMP-диалогом,
        -- не закрывается через sampCloseCurrentDialogWithButton и после этого остается висеть на экране.
        -- Теперь просто напрямую закрываем собственный диалог скрипта, если он завис.
        if sampIsDialogActive() and isOwnScriptDialogId(sampGetCurrentDialogId()) then
            sampCloseCurrentDialogWithButton(0)
        end
        wait(200)
        data.fix = false
    end)
end

-- Проверяет связку сервер+ник и при необходимости переключает профиль.
-- Используется как при первом старте скрипта (main), так и из поллинг-цикла
-- коннекта — чтобы ловить переподключение между серверами Arizona без
-- полного рестарта MoonLoader/игры (сам процесс лаунчера при этом не
-- перезапускается, поэтому main() второй раз не вызовется сам по себе).
-- Возвращает true, если профиль сменился и скрипт уходит в reload()
-- (в этом случае дальнейший код в вызывающем месте выполнять не нужно).
local function checkAndSwitchProfile(sn, nick)
    sn = sn or (isSampAvailable() and sampGetCurrentServerName())
    if not sn or sn == '' or sn == 'SA-MP' then return false end

    nick = nick or waitForNickname(5000)
    if not nick or nick == '' then return false end

    local profileKey = sanitizeForPath(sn) .. '__' .. sanitizeForPath(nick)

    utils.debugChat("{808080}[DEBUG] profileKey = {FFFFFF}" .. profileKey ..
        " {808080}(активный: {FFFFFF}" .. tostring(activeProfileKey) .. "{808080})")

    if profileKey == activeProfileKey then
        utils.debugChat("{808080}[DEBUG] Профиль подтверждён: {FFFFFF}" .. tostring(activeProfileKey))
        return false
    end

    -- Сменился сервер и/или ник относительно активного профиля (например,
    -- перелёт между Arizona-серверами без рестарта игры). Переключаем
    -- указатель на нужный config.json и перезапускаем скрипт, чтобы все
    -- данные (дома, снапшоты, доходность) читались уже из правильного профиля.
    writePointer(profileKey)
    utils.debugChat("{FFE133}[DEBUG] Новый профиль (сервер/ник изменились): {FFFFFF}" .. profileKey ..
        "{FFE133}. Перезагружаюсь...")
    wait(300)
    thisScript():reload()
    return true
end

function isProperlyConnected()
    if not isSampAvailable() then return false end
    local name = sampGetCurrentServerName()
    if not name or name == '' or name == 'SA-MP' then return false end
    if not sampIsLocalPlayerSpawned() then return false end
    return true
end

local function updateConnectionState()
    local nowConnected = isProperlyConnected()
    local wasConnected = data.connectionState.connected
    data.connectionState.lastCheck = os.time()

    if nowConnected ~= wasConnected then
        if nowConnected then
            data.connectionState.connected = true
            if cfg.waitForConnection and data.connectionState.wasDisconnected then
                data.connectionState.readyAfterConnect =
                    os.time() + cfg.delayAfterConnectMin * 60
                utils.debugChat(string.format(
                    "[CONNECT] Подключение восстановлено. Отложено на %d мин.",
                    cfg.delayAfterConnectMin))
            end
            -- Новое подключение обнаружено поллингом (например, перелёт между
            -- Arizona-серверами без рестарта игры) — нужно перепроверить профиль.
            -- Само переключение (reload()) откладываем до момента, когда не
            -- идёт активная задача/диалог сбора — иначе можно прервать скрипт
            -- посреди открытого диалога с сервером, из-за чего он рассинхронится
            -- с состоянием и перестанет реально собирать крипту.
            data.connectionState.profileCheckPending = true
        else
            data.connectionState.connected = false
            data.connectionState.wasDisconnected = true
            utils.debugChat("[CONNECT] Подключение потеряно. Приостановлено.")
        end
    end

    if data.connectionState.profileCheckPending
        and nowConnected
        and not data.working
        and not data.silentWindowOpen
        and not sampIsDialogActive() then
        data.connectionState.profileCheckPending = false
        -- Если профиль сменился, checkAndSwitchProfile() уйдёт в reload().
        checkAndSwitchProfile()
    end
end

function runTaskAndReopenDialog(taskFunction, ...)
    taskFunction(...)
    lua_thread.create(function()
        while data.working do wait(50) end
        wait(200)
        if sampIsDialogActive() and not isOwnScriptDialogId(sampGetCurrentDialogId()) then
            -- Не своё окно (например, игрок открыл телефон/инвентарь) — не
            -- закрываем силой, просто ждём, пока он закроет его сам.
            waitForForeignDialogToClose(nil)
        end
        if sampIsDialogActive() and isOwnScriptDialogId(sampGetCurrentDialogId()) then
            sampCloseCurrentDialogWithButton(0)
        end
        if data.hasFlashminer == false then return end
        sampSendChat("/flashminer")
    end)
end


function setPendingHouseNumber(houseNumber)
    local n = tonumber(houseNumber)
    if not n then return end
    data.pendingHouseNumber = n
    data.pendingHouseAt = os.clock()
end

function getRecentFlashminerCurrentHouseNumber(maxAge)
    maxAge = maxAge or 120
    local n = tonumber(data.currentFlashminerHouseNumber)
    if not n then return nil end
    if os.clock() - (data.currentFlashminerHouseAt or 0) > maxAge then return nil end
    return n
end

function getCurrentFlashminerHouseIndex()
    local current = getRecentFlashminerCurrentHouseNumber(120)
    if not current then return nil end
    for i, house in ipairs(data.dialogData.flashminer or {}) do
        if tonumber(house.house_number) == current then
            return i, house
        end
    end
    return nil
end

function resolveHouseNumberForCardDialog(title)
    title = title or ''
    local n = tonumber(title:match('дом №(%d+)') or title:match('Дом №(%d+)'))
    if n then return n, 'title' end

    local pending = tonumber(data.pendingHouseNumber)
    if pending and os.clock() - (data.pendingHouseAt or 0) <= 8 then
        data.pendingHouseNumber = nil
        return pending, 'pending'
    end
    data.pendingHouseNumber = nil

    local current = getRecentFlashminerCurrentHouseNumber(120)
    if current then return current, 'flashminer_current_mark' end

    return nil, 'unknown'
end

function main()
    repeat wait(0) until isSampAvailable() and isSampfuncsLoaded()
    while not isSampLoaded() do wait(0) end
    local sn
    while true do
        sn = sampGetCurrentServerName()
        if sn and (sn:find('Arizona') or sn:find('Rodina')) then break end
        wait(0)
    end
    data.isRodina = not isArizonaServer()
    dialogIdTable = data.isRodina and dialogIdTable.rodina or dialogIdTable.arizona

    -- Определяем VC сразу по имени сервера (город зашит в название вида
    -- "Arizona X10 | Vice City | ..."), не дожидаясь сообщения в чате —
    -- оно приходит только при телепорте между городами, а не при заходе
    -- на сервер, если персонаж уже находится в Vice City.
    if not data.isRodina then
        local city = getArizonaCityFromServerName(sn)
        if city then
            data.isViceCity = city:find("Vice City", 1, true) ~= nil
        end
    end

    utils.debugChat("{808080}[DEBUG] raw serverName = {FFFFFF}" .. tostring(sn))
    utils.debugChat("{808080}[DEBUG] isArizonaServer() = {FFFFFF}" .. tostring(isArizonaServer()))
    utils.debugChat("{808080}[DEBUG] data.isRodina = {FFFFFF}" .. tostring(data.isRodina) ..
        " {808080}(dialogIdTable = {FFFFFF}" .. (data.isRodina and "rodina" or "arizona") .. "{808080})")
    utils.debugChat("{808080}[DEBUG] data.isViceCity (по имени сервера) = {FFFFFF}" .. tostring(data.isViceCity))

    -- === Проверка профиля (сервер + ник) ===
    -- Ждём ник локального игрока и считаем ключ профиля для текущей связки сервер+ник.
    local nick = waitForNickname(5000)
    utils.debugChat("{808080}[DEBUG] nickname = {FFFFFF}" .. tostring(nick))

    if checkAndSwitchProfile(sn, nick) then
        -- Профиль сменился — checkAndSwitchProfile() уже запустил reload(),
        -- дальше в этом запуске скрипта делать нечего.
        return
    end

    -- Сообщения о загрузке показываем только после того, как игрок реально
    -- заспавнился (т.е. прошёл авторизацию/логин), а не сразу при коннекте —
    -- иначе они тонут в общем потоке чата от других скриптов ещё на экране
    -- ввода пароля. Не блокируем этим остальную инициализацию main().
    lua_thread.create(function()
        local waited = 0
        while not sampIsLocalPlayerSpawned() and waited < 120000 do
            wait(200)
            waited = waited + 200
        end
        utils.addChat("{FFC0CB}Добро пожаловать в игру, {FFFFFF}" .. tostring(nick) ..
            "{FFC0CB}, на сервер {FFFFFF}" .. tostring(sn) .. "{FFC0CB}! {FFC0CB}<3")
        utils.addChat('Загружен. Команда: {ffc0cb}/mnt{ffffff}.')
    end)

    if cfg.checkForUpdates then
        checkForUpdates()
    end
    if type(cfg.cardSnapshots) == 'table' then
        for k, snap in pairs(cfg.cardSnapshots) do
            if type(snap) == 'table' and snap.isFake then
                cfg.cardSnapshots[k] = nil
            end
        end
    end

    -- РћРґРЅРѕСЂР°Р·РѕРІР°СЏ РјРёРіСЂР°С†РёСЏ РїРѕСЃР»Рµ С„РёРєСЃР° СЂР°СЃС‡С‘С‚Р° РґРѕС…РѕРґР°: СЃС‚Р°СЂС‹Р№ Р°Р»РіРѕСЂРёС‚Рј РјРѕРі
    -- РѕРґРёРЅ СЂР°Р· "Р·Р°С„РёРєСЃРёСЂРѕРІР°С‚СЊ" Р°РЅРѕРјР°Р»СЊРЅСѓСЋ СЃРєРѕСЂРѕСЃС‚СЊ (dailyBtcRate/dailyAscRate)
    -- РµС‰С‘ РґРѕ С‚РѕРіРѕ, РєР°Рє РїРѕСЏРІРёР»РёСЃСЊ С‚РµРєСѓС‰РёРµ РїСЂРѕРІРµСЂРєРё РЅР° РІС‹Р±СЂРѕСЃС‹ Рё СЃРјРµРЅСѓ СЃРѕСЃС‚Р°РІР°
    -- РєР°СЂС‚. РќРѕРІР°СЏ Р»РѕРіРёРєР° Р»РёС€СЊ РѕРіСЂР°Р¶РґР°РµС‚ РѕС‚ РќРћР’Р«РҐ РїР»РѕС…РёС… РЅР°Р±Р»СЋРґРµРЅРёР№, РЅРѕ СЃР°РјР°
    -- РїРѕ СЃРµР±Рµ РЅРµ РїРµСЂРµСЃС‡РёС‚С‹РІР°РµС‚ СѓР¶Рµ СЃРѕС…СЂР°РЅС‘РЅРЅСѓСЋ РІ РєРѕРЅС„РёРіРµ РёСЃРїРѕСЂС‡РµРЅРЅСѓСЋ С†РёС„СЂСѓ -
    -- РїРѕСЌС‚РѕРјСѓ РѕРЅР° РїСЂРѕРґРѕР»Р¶Р°Р»Р° Р±С‹ РїРѕРєР°Р·С‹РІР°С‚СЊСЃСЏ РєР°Рє РµСЃС‚СЊ. РЎР±СЂР°СЃС‹РІР°РµРј С‚РѕР»СЊРєРѕ
    -- РЅР°РєРѕРїР»РµРЅРЅСѓСЋ СЃС‚Р°С‚РёСЃС‚РёРєСѓ СЃРєРѕСЂРѕСЃС‚Рё (РЅРµ СЃР°РјРё РєР°СЂС‚С‹/Р±Р°Р»Р°РЅСЃС‹), С‡С‚РѕР±С‹ РѕРЅР°
    -- Р·Р°РЅРѕРІРѕ РЅР°Р±СЂР°Р»Р°СЃСЊ СЃ РЅСѓР»СЏ РїРѕ РёСЃРїСЂР°РІР»РµРЅРЅС‹Рј РїСЂР°РІРёР»Р°Рј. Р”РµР»Р°РµС‚СЃСЏ РѕРґРёРЅ СЂР°Р·.
    if not cfg.incomeStatsResetV2 and type(cfg.cardSnapshots) == 'table' then
        for _, snap in pairs(cfg.cardSnapshots) do
            if type(snap) == 'table' then
                snap.dailyBtcRate  = nil
                snap.dailyAscRate  = nil
                snap.incomeObs     = nil
                snap.incomeAscObs  = nil
                snap.lastComposition = nil
            end
        end
        cfg.incomeStatsResetV2 = true
        save()
        utils.debugChat("[INCOME] \xd1\xf2\xe0\xf0\xe0\xff \xf1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xe0 \xe4\xee\xf5\xee\xe4\xe0 \xef\xee \xe4\xee\xec\xe0\xec \xf1\xe1\xf0\xee\xf8\xe5\xed\xe0, \xf1\xf7\xb8\xf2\xf7\xe8\xea \xed\xe0\xf7\xed\xb8\xf2 \xed\xe0\xea\xe0\xef\xeb\xe8\xe2\xe0\xf2\xf1\xff \xe7\xe0\xed\xee\xe2\xee.")
    end

    sampRegisterChatCommand('mnt', function()
        cfg.active = not cfg.active
        utils.addChat(cfg.active and "Скрипт {99ff99}включен." or "Скрипт {F78181}отключен.")
        save()
    end)
    sampRegisterChatCommand('mntd', function()
        cfg.debug = not cfg.debug
        utils.addChat(cfg.debug and "Отладка {99ff99}включена." or "Отладка {F78181}отключена.")
        if cfg.debug then
            local snNow = sampGetCurrentServerName and sampGetCurrentServerName() or nil
            utils.addChat("{808080}[DEBUG] raw serverName = {FFFFFF}" .. tostring(snNow))
            utils.addChat("{808080}[DEBUG] isArizonaServer() = {FFFFFF}" .. tostring(isArizonaServer()))
            utils.addChat("{808080}[DEBUG] город из имени сервера = {FFFFFF}" .. tostring(getArizonaCityFromServerName(snNow)))
            utils.addChat("{808080}[DEBUG] data.isRodina = {FFFFFF}" .. tostring(data.isRodina) ..
                " {808080}(dialogIdTable = {FFFFFF}" .. (data.isRodina and "rodina" or "arizona") .. "{808080})")
            utils.addChat("{808080}[DEBUG] data.isViceCity = {FFFFFF}" .. tostring(data.isViceCity))
            utils.addChat("{808080}[DEBUG] активный профиль = {FFFFFF}" .. tostring(activeProfileKey))
        end
        save()
    end)

        sampRegisterChatCommand('mntu', function()
        updateState.declined = false
        updateState.hasUpdate = false
        updateState.checking = false
        updateState.forceShowPopup = true
        updateState.postponeUntil = 0
        checkForUpdates()
    end)
    sampRegisterChatCommand('mntver', function()
        utils.addChat("{808080}version={FFFFFF}" .. tostring(script.this.version) .. "{808080} check={FFFFFF}" .. tostring(cfg.checkForUpdates))
        utils.addChat("{808080}url={FFFFFF}" .. tostring(UPDATE_CHECK_URL))
        utils.addChat("{808080}hasUpdate={FFFFFF}" .. tostring(updateState.hasUpdate) .. " latest={FFFFFF}" .. tostring(updateState.latestVersion))
    end)
sampRegisterChatCommand('fls', function()
        if data.hasFlashminer == false then
            utils.addChat("{F78181}У вас нет флешки майнера.")
            return
        end
        if data.working then
            utils.addChat("{FFE133}Дождитесь завершения текущей задачи.")
            return
        end

        if data.showHouseControlWindow[0] then
            data.showHouseControlWindow[0] = false
            return
        end

        lua_thread.create(function()
            sampSendChat("/flashminer")
        end)
    end)

    if cfg.isReloaded then
        cfg.isReloaded = false
        save()
    end

    local waitingForDialogClose = sampIsDialogActive() and
        sampGetCurrentDialogId() == dialogIdTable.houseFlashMinerDialogId

    if sampIsDialogActive() then
        local id = sampGetCurrentDialogId()
        if id == dialogIdTable.houseFlashMinerDialogId then
            waitingForDialogClose = true
        end
    end

    local escHandlers = {
        {
            cond = function() return data.showHelpWindow[0] end,
            act = function() data.showHelpWindow[0] = false end
        },
        {
            cond = function() return updateState.showPopup[0] end,
            act = function()
                updateState.showPopup[0] = false
                updateState.postponeUntil = os.time() + 30 * 60
                updateState.flashOpenAsked = false
                updateState.declined = false
            end
        },
        {
            cond = function() return data.showSettingsWindow[0] and data.showLogsWindow[0] end,
            act = function()
                data.showSettingsWindow[0] = false; data.showLogsWindow[0] = false
            end
        },
        {
            cond = function() return data.showSettingsWindow[0] end,
            act = function() data.showSettingsWindow[0] = false end
        },
        {
            cond = function() return data.showLogsWindow[0] end,
            act = function() data.showLogsWindow[0] = false end
        },

        {
            cond = function()
                return data.showHouseControlWindow[0]
                    and not data.working
                    and data.lastWindowState.houseControl
            end,
            act = function()
                sampCloseCurrentDialogWithButton(0)
                data.showHouseControlWindow[0] = false
                fixI()
            end
        },

    }
    addEventHandler('onWindowMessage', function(msg, wparam, lparam)
        if sampIsChatInputActive() then return end
        if msg ~= wm.WM_KEYDOWN then return end

        if wparam == 27 then
            for _, h in ipairs(escHandlers) do
                if h.cond() then
                    consumeWindowMessage(true, false)
                    h.act()
                    return
                end
            end
        end

        if data.main[0] and data.isFlashminer and not data.working then
            local direction = nil

            if wparam == 37 then -- Стрелка ВЛЕВО
                consumeWindowMessage(true, false)
                direction = -1
            elseif wparam == 39 then -- Стрелка ВПРАВО
                consumeWindowMessage(true, false)
                direction = 1
            end

            if direction then
                flashminerTool.navigate(direction)
                return
            end
        end
        if #data.dialogData.flashminer > 0 and data.showHouseControlWindow[0] then
            local columns = 2
            local direction = nil

            if wparam == 40 then -- Стрелка ВНИЗ
                consumeWindowMessage(true, false)
                direction = 'down'
            elseif wparam == 38 then -- Стрелка ВВЕРХ
                consumeWindowMessage(true, false)
                direction = 'up'
            elseif wparam == 37 then -- Стрелка ВЛЕВО
                consumeWindowMessage(true, false)
                direction = 'left'
            elseif wparam == 39 then -- Стрелка ВПРАВО
                consumeWindowMessage(true, false)
                direction = 'right'
            end

            if direction then
                local filteredHouses = data.filteredHouses or data.dialogData.flashminer
                local totalFiltered = #filteredHouses
                local currentIndex = nil

                if data.selectedHouseIndex then
                    local selectedHouse = data.dialogData.flashminer[data.selectedHouseIndex]
                    if selectedHouse then
                        for i, house in ipairs(filteredHouses) do
                            if house.house_number == selectedHouse.house_number then
                                currentIndex = i
                                break
                            end
                        end
                    end
                end

                if not currentIndex then currentIndex = 1 end

                local newIndex = currentIndex

                if direction == 'down' then
                    -- Вниз = +2
                    newIndex = currentIndex + columns
                    if newIndex > totalFiltered then
                        newIndex = currentIndex
                    end
                elseif direction == 'up' then
                    -- Вверх = -2
                    newIndex = currentIndex - columns
                    if newIndex < 1 then
                        newIndex = currentIndex
                    end
                elseif direction == 'left' then
                    -- Влево = -1
                    newIndex = currentIndex - 1
                    if newIndex < 1 then
                        newIndex = totalFiltered
                    end
                elseif direction == 'right' then
                    -- Вправо = +1
                    newIndex = currentIndex + 1
                    if newIndex > totalFiltered then
                        newIndex = 1
                    end
                end

                if newIndex ~= currentIndex then
                    local nextHouse = filteredHouses[newIndex]
                    if nextHouse then
                        for origIdx, origHouse in ipairs(data.dialogData.flashminer) do
                            if origHouse.house_number == nextHouse.house_number then
                                data.selectedHouseIndex = origIdx
                                data.lastSelectedHouse = nextHouse.house_number
                                data.scrollToSelection = true
                                break
                            end
                        end
                    end
                end
                return
            end

            if wparam == 13 then -- ENTER
                if not data.lastWindowState.houseControl then
                    consumeWindowMessage(true, false)
                    return
                end
                local selectedHouse = data.dialogData.flashminer[data.selectedHouseIndex]
                if selectedHouse then
                    sampSendDialogResponse(data.dFlashminerId, 1, selectedHouse.index - 1, "")
                    data.showHouseControlWindow[0] = false
        updateState.flashOpenAsked = false
                    data.lastSelectedHouse = selectedHouse.house_number
                end
            end
            return
        end
    end)


    -- для автозаливки и переключения кард
    lua_thread.create(function()
        while true do
            wait(300)
            coolantTool.tick()
        end
    end)

    -- Фоновое обновление домов каждые 5 минут
    lua_thread.create(function()
        local AUTO_REFRESH_INTERVAL = 5 * 60  -- 5 минут
        wait(60000)  -- подождать начальной загрузки
        while true do
            wait(AUTO_REFRESH_INTERVAL * 1000)
            updateConnectionState()
            if not taskState.isAutomationAllowed() then goto continue_refresh end
            if cfg.active and not data.working
                and data.hasFlashminer ~= false
                and not cfg.autoRefreshEnabled  -- не дублировать
                and not (cfg.refreshPostponeOnDialog and sampIsDialogActive() and not data.silentWindowOpen) then
                utils.debugChat("[AUTO-REFRESH] Фоновое обновление (5 мин)")
                autoRefreshTool.runSilent()
            elseif cfg.active and not data.working and data.hasFlashminer ~= false
                and not cfg.autoRefreshEnabled
                and cfg.refreshPostponeOnDialog and sampIsDialogActive() and not data.silentWindowOpen then
                utils.debugChat("[AUTO-REFRESH] Диалог открыт — обновление (5 мин) пропущено, повтор через 5 мин")
            end
            ::continue_refresh::
        end
    end)

    -- Для окна подсказки

    -- для автооплаты налог и пополнения баланса
    lua_thread.create(function()
        while true do
            wait(1000)
            if not cfg.active then goto continue_timer end

            updateConnectionState()
            if not taskState.isAutomationAllowed() then goto continue_timer end

            if data.hasFlashminer == false then goto continue_timer end

            local now = os.time()
            collectTool.tickTriggers(now)

            if not cfg.cheatModeEnabled or data.working then goto continue_timer end

            taxTool.tickTimer(now)

            autoTopUpTool.tickTimer(now)

            autoRefreshTool.tickTimer(now)

            ::continue_timer::
        end
    end)


    while true do
        wait(0)
        data.lastWindowState.main = data.main[0]
        data.lastWindowState.houseControl = data.showHouseControlWindow[0]
        if cfg.active then
            local id = sampGetCurrentDialogId()
            local isVideocardListActive = (id == dialogIdTable.houseFlashMinerDialogId or id == dialogIdTable.videoCardSt) and
                sampIsDialogActive() and not data.showHouseControlWindow[0] and not data.silentWindowOpen
            if waitingForDialogClose and not isVideocardListActive then
                waitingForDialogClose = false
            end
            data.main[0] = (isVideocardListActive and not waitingForDialogClose) or
                (data.main[0] and data.working and not data.showHouseControlWindow[0])
            data.showHouseControlWindow[0] = not cfg.useDialogMode and data.showHouseControlWindow[0]
        end
    end
end

function sendcef(str)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 18)
    raknetBitStreamWriteInt16(bs, #str)
    raknetBitStreamWriteString(bs, str)
    raknetBitStreamWriteInt32(bs, 0)
    raknetSendBitStream(bs)
    raknetDeleteBitStream(bs)
end

addEventHandler('onReceivePacket', function(id, bs)
    if not cfg.active then return end

    if cfg.lastHouseListHash == "" and id == 220 then
        raknetBitStreamIgnoreBits(bs, 8)
        if raknetBitStreamReadInt8(bs) == 17 then
            raknetBitStreamIgnoreBits(bs, 32)
            local length = raknetBitStreamReadInt16(bs)
            local encoded = raknetBitStreamReadInt8(bs)
            local str = (encoded ~= 0) and raknetBitStreamDecodeString(bs, length + encoded) or
                raknetBitStreamReadString(bs, length)

            if str:find("event%.property%.list%.pushItems") then
                local raw = str:match("%[%[(.-)%]%]")
                if raw then
                    local houseData = decodeJson('[' .. raw .. ']')

                    if houseData and houseData[1] then
                        local house = houseData[1]
                        if house.status == "rentedOut" then
                            local houseId = tostring(house.id)
                            cfg.excludedHouses[houseId] = true
                            utils.debugChat("Дом №" .. houseId .. " добавлен в исключения (аренда)")
                        end
                    end
                end
            end
        end
    end
end)

local dialogChecker = {
    titles = {
        "{BFBBBA}Выбор дома",
        "Вывод прибыли видеокарты",
        "Выберите тип жидкости",
        "^Полка №%d+",
        "^Стойка №%d+"
    },
    texts = {
        "Забрать прибыль",
        "Достать видеокарту",
        "Баланс Bitcoin"
    },
    shouldHide = function(self, title, text)
        for _, pattern in ipairs(self.titles) do
            if title:find(pattern) then return true end
        end
        for _, pattern in ipairs(self.texts) do
            if text:find(pattern) then return true end
        end
        return false
    end
}

local massActionTypes = {
    collectFromAllHouses = true,
    massSwitchCards      = true,
    fixAllProblems       = true,
    scanBasements        = true,
    updateStatuses       = true,
    autoPayTaxes         = true,
    autoTopUp            = true,
    coolant              = true,
}

function sampev.onShowDialog(dialogId, style, title, button1, button2, text, placeholder)
    title = title or ""
    text = text or ""
    button1 = button1 or ""
    button2 = button2 or ""
    utils.debugChat(string.format("[DIALOG] onShowDialog | id=%d style=%d | title=%q | btn1=%q btn2=%q | textLen=%d", dialogId, style, title, button1, button2, #(text or "")))
    if not cfg.active then return end

    -- Автозакрытие неигровых информационных попапов (например, награда за
    -- сундук с рулеткой). Пока такое окно открыто на экране (например, вы
    -- AFK и некому нажать "понял"), sampIsDialogActive() держится в true
    -- и ОБА таймера автообновления домов (autoRefreshTool.tickTimer и
    -- фоновый поток "раз в 5 минут") бесконечно откладывают обновление,
    -- потому что видят "диалог открыт". Такие попапы — это одна кнопка-
    -- квитанция без выбора, поэтому безопасно закрыть их самим спустя
    -- небольшую паузу (даём игроку время прочитать, если он не AFK).
    if title:find("ИНФОРМАЦИЯ") and button2 == "" then
        local closeTargetId = dialogId
        lua_thread.create(function()
            wait(3000)
            if sampIsDialogActive() and sampGetCurrentDialogId() == closeTargetId then
                sampSendDialogResponse(closeTargetId, 1, 0, "")
                utils.debugChat("[DIALOG] Информационный попап авто-закрыт (обновление разблокировано).")
            end
        end)
    end

    if title:find("Выбор дома") and text:find("циклов %(") then
        data.isFlashminer = true
    end

    if taxTool.handleShowDialog(dialogId, style, title, button1, button2, text, placeholder) then
        return false
    end

    coolantTool.handleShowDialog(dialogId, style, title, button1, button2, text, placeholder)

    if title:find("Телефоны") and text:find("Мобильное устройство") then
        sampSendDialogResponse(dialogId, 1, 0, "")
        return false
    end
    if title:find("Выберите полку") then
        local currentIndex = 0
        for line in text:gmatch("[^\r\n]+") do
            if line:find("Свободна") then
                sampSendDialogResponse(dialogId, 1, currentIndex, "")
                return false
            end
            currentIndex = currentIndex + 1
        end
        utils.addChat("{F78181}Нет свободных слотов на полке!")
        return false
    end
    if data.fix and title:find("Игровое меню") then
        sampSendDialogResponse(dialogId, 0, 0, "")
        local closeTargetId = dialogId
        lua_thread.create(function()
            wait(0)
            -- Закрываем только если на экране всё ещё именно этот диалог ("Игровое меню"),
            -- а не появившийся поверх него другой диалог (например, выбор видеокарты 25182).
            -- Иначе sampCloseCurrentDialogWithButton закроет не тот диалог, что надо, а тот, который сейчас на экране.
            if sampIsDialogActive() and sampGetCurrentDialogId() == closeTargetId then
                sampCloseCurrentDialogWithButton(0)
            end
        end)
        return false
    end

    taskState.refreshSuppressDialogs()
    local isMassAction = data.suppressDialogs and massActionTypes[data.taskTypeNow] and not cfg.useDialogMode == true
    if title:find("Выбор дома") and text:find("домов для") then
        if not data.noHousesNotified then
            utils.addChat("{F78181}У вас нет доступных домов с майнинг фермой!")
            data.noHousesNotified = true
        else
            utils.debugChat("[HOUSE] Повторный пустой список домов — диалог закрыт молча")
        end
        sampSendDialogResponse(dialogId, 1, 0, "")
        return false
    end

    if title:find("Выбор дома") and not text:find("домов для") then
        if text:match("циклов %(") then
            data.hasFlashminer = true
            data.isFlashminer = true
            data.dFlashminerId = dialogId
            flashminerTool.parseDialogText(text)

            do
                local currentIndex, currentHouse = getCurrentFlashminerHouseIndex()
                if currentIndex and data.flashminerSwitchId.direction == 0 and not data.working then
                    data.selectedHouseIndex = currentIndex
                    data.lastSelectedHouse = currentHouse.house_number
                    data.scrollToSelection = true
                    setPendingHouseNumber(currentHouse.house_number)
                    utils.debugChat(string.format("[HOUSE] Flashminer dialog focused current [X] house #%d", currentHouse.house_number))
                end
            end

            if data.flashminerSwitchId.direction ~= 0 then
                local base_index
                if data.forImgui.dTitle and data.forImgui.dTitle ~= "Неизвестно" then
                    for i, house in ipairs(data.dialogData.flashminer) do
                        if house.name:find(data.forImgui.dTitle) then
                            base_index = i
                            break
                        end
                    end
                end
                if not base_index then
                    base_index = data.flashminerSwitchId.direction == 1 and 0 or #data.dialogData.flashminer + 1
                end
                local next_index = base_index + data.flashminerSwitchId.direction
                if next_index > #data.dialogData.flashminer then next_index = 1 end
                if next_index < 1 then next_index = #data.dialogData.flashminer end

                if data.dialogData.flashminer[next_index] then
                    local next_house = data.dialogData.flashminer[next_index]
                    data.forImgui.dTitle = tostring(next_house.house_number)
                    setPendingHouseNumber(next_house.house_number)
                    sampSendDialogResponse(dialogId, 1, next_house.index - 1, "")
                else
                    data.flashminerSwitchId.direction = 0
                end

                return false
            end
        else
            return
        end

        if cfg.useDialogMode then
            local newText = text .. "\n "
            newText = newText .. "\n{33CC33}» Включить все видеокарты"
            newText = newText .. "\n"
            newText = newText .. "\n{FFFF00}» Собрать криптовалюту со всех домов"
            newText = newText .. "\n"
            newText = newText .. "\n{FF3333}» Выключить все видеокарты"
            return { dialogId, style, title, button1, button2, newText, placeholder }
        else
            if isMassAction then
                return false
            end

            local wasWindowAlreadyVisible = data.showHouseControlWindow[0]
            if not data.silentWindowOpen then
                data.showHouseControlWindow[0] = true
            end
            if not data.silentWindowOpen then
                -- Show update overlay on first flashminer open (and later if not postponed)
                updatePopupOpen(false)
            end
            if not wasWindowAlreadyVisible then
                local foundIndex = 1
                local currentIndex, currentHouse = getCurrentFlashminerHouseIndex()
                if currentIndex then
                    foundIndex = currentIndex
                    data.lastSelectedHouse = currentHouse.house_number
                    setPendingHouseNumber(currentHouse.house_number)
                    utils.debugChat(string.format("[HOUSE] Selected current flashminer house #%d from [X] mark", currentHouse.house_number))
                elseif data.lastSelectedHouse ~= -1 then
                    for i, house in ipairs(data.dialogData.flashminer) do
                        if house.house_number == data.lastSelectedHouse then
                            foundIndex = i
                            break
                        end
                    end
                end
                data.selectedHouseIndex = foundIndex
                data.scrollToSelection = true
            end

            local houseNumbers = {}
            for _, h in ipairs(data.dialogData.flashminer) do
                table.insert(houseNumbers, tostring(h.house_number))
            end
            table.sort(houseNumbers)
            local currentHash = table.concat(houseNumbers, ",")

            if not data.silentWindowOpen and not data.working and cfg.lastHouseListHash ~= currentHash then
                local newHouses = {}
                for _, h in ipairs(data.dialogData.flashminer) do
                    local houseNum = tostring(h.house_number)
                    if not cfg.basementScanned[houseNum] and not cfg.excludedHouses[houseNum] then
                        table.insert(newHouses, h)
                    end
                end

                local currentHouses = {}
                for _, num in ipairs(houseNumbers) do
                    currentHouses[num] = true
                end

                for houseNum in pairs(cfg.housesWithoutBasement) do
                    if not currentHouses[houseNum] then
                        cfg.housesWithoutBasement[houseNum] = nil
                    end
                end
                for houseNum in pairs(cfg.basementScanned) do
                    if not currentHouses[houseNum] then
                        cfg.basementScanned[houseNum] = nil
                    end
                end

                cfg.lastHouseListHash = currentHash
                save()

                if #newHouses > 0 then
                    local task = buildTaskTable('scanBasements')
                    runTaskAndReopenDialog(function() task:run(newHouses) end)
                    data.initialScanCompleted = true
                end
            elseif not data.silentWindowOpen and not data.initialScanCompleted and not data.working then
                cfg.lastHouseListHash = currentHash
                save()
                local task = buildTaskTable('updateStatuses')
                runTaskAndReopenDialog(function() task:run() end)
                data.initialScanCompleted = true
            end

            return false
        end
    end

    if title:find("^{......}Выберите видеокарту") or title:find("^Полка №%d+") or text:find("Баланс Bitcoin") or text:find('Обзор всех видеокарт') then
        data.flashminerSwitchId.direction = 0
        data.isFlashminer = title:find("%(дом №%d+%)") ~= nil
        data.dFlashminerId = dialogId
        local houseNum, houseSource = resolveHouseNumberForCardDialog(title)
        if houseNum then
            -- Продлеваем pending-окно при каждом успешном резолве, а не только
            -- при первом выборе дома из списка. Иначе если скрипт задерживается
            -- в этом доме дольше 8 сек (несколько полок/карт подряд), pending
            -- истекает раньше времени и houseNum перестаёт резолвиться, хотя
            -- мы всё ещё находимся в том же доме.
            setPendingHouseNumber(houseNum)
        end
        data.forImgui = {
            dTitle = houseNum and tostring(houseNum) or "Неизвестно",
            allGood = true,
            videocardCount = 0,
            earnings = { btc = 0, asc = 0 },
            attentionTime = 101,
        }
        data.dialogData.videocards = {}
        local listbox_index = -1
        for line in text:gmatch("[^\n\r]+") do
            listbox_index = listbox_index + 1
            if line:find("{......}Работает") or line:find("{......}На паузе") then
                local hasBtc = line:find("BTC") ~= nil
                local hasAsc = line:find("ASC") ~= nil
                local isRealAsic = line:find("ASIC") ~= nil
                local btcFull = tonumber(line:match("([%d%.]+) BTC")) or 0
                local ascFull = tonumber(line:match("([%d%.]+) ASC")) or 0
                local card = {
                    index = listbox_index,
                    working = line:find("{......}Работает") and true or false,
                    btc_full = btcFull,
                    asc_full = ascFull,
                    btc = math.floor(btcFull),
                    asc = math.floor(ascFull),
                    coolant = tonumber(line:match("(%d+%.%d+)%%?%s*$")) or 0,
                    fluidType = hasBtc and 1 or (hasAsc and 2 or 0),
                    card_type = isRealAsic and "ASIC" or (hasBtc and "BTC" or "ASC"),
                    level = tonumber(line:match("(%d+) уровень")) or 0,
                    id = dialogId
                }
                table.insert(data.dialogData.videocards, card)
                if not card.working or card.coolant < cfg.useCoolantPercent then data.forImgui.allGood = false end
                if card.coolant < data.forImgui.attentionTime then data.forImgui.attentionTime = card.coolant end
                data.forImgui.earnings.btc = data.forImgui.earnings.btc + card.btc
                data.forImgui.earnings.asc = data.forImgui.earnings.asc + card.asc
                data.forImgui.videocardCount = data.forImgui.videocardCount + 1
            end
        end

        if houseNum and not cfg.useDialogMode and not cfg.excludedHouses[tostring(houseNum)] then
            local currentHouseData = nil
            for _, h in ipairs(data.dialogData.flashminer) do
                if h.house_number == tonumber(houseNum) then
                    currentHouseData = h
                    break
                end
            end
            lua_thread.create(function()
                updateHouseStatus(tonumber(houseNum), currentHouseData)
            end)
        end

        if (not data.initialScanCompleted and not cfg.useDialogMode and dialogId ~= dialogIdTable.videoCardSt) or
            (isMassAction and dialogId ~= dialogIdTable.videoCardSt) then
            return false
        end
    end

    if isMassAction then
        if dialogId == dialogIdTable.phoneBankMenuId or
            dialogId == dialogIdTable.topUpBalanceDialogId or
            dialogId == dialogIdTable.payAllTaxesDialogId then
            return false
        end

        -- РЎС‚РѕР№РєР° (videoCardSt) РІРёРґРЅР° РўРћР›Р¬РљРћ РїСЂРё РѕРїРµСЂР°С†РёРё Р·Р°Р»РёРІРєРё Р¶РёРґРєРѕСЃС‚Рё (coolant),
        -- РІРѕ РІСЃРµС… РѕСЃС‚Р°Р»СЊРЅС‹С… РјР°СЃСЃРѕРІС‹С… РґРµР№СЃС‚РІРёСЏС… РµС‘ РЅСѓР¶РЅРѕ СЃРєСЂС‹РІР°С‚СЊ
        if data.taskTypeNow ~= 'coolant' and dialogId == dialogIdTable.videoCardSt then
            return false
        end

        if dialogId == dialogIdTable.videoCardDialogId or
            dialogId == dialogIdTable.videoCardAcceptDialogId or
            dialogId == dialogIdTable.coolantDialogId then
            return false
        end
    end

    -- FIX: СЂР°РЅСЊС€Рµ Р·РґРµСЃСЊ РїСЂРѕРІРµСЂСЏР»СЃСЏ С‚РѕР»СЊРєРѕ data.suppressDialogs (true РІРѕ РІСЂРµРјСЏ
    -- Р›Р®Р‘РћР™ С„РѕРЅРѕРІРѕР№ Р·Р°РґР°С‡Рё + 0.5 СЃРµРє РїРѕСЃР»Рµ РЅРµС‘), РёР·-Р·Р° С‡РµРіРѕ СЃРєСЂРёРїС‚ "СЃСЉРµРґР°Р»"
    -- РґРёР°Р»РѕРіРё, РѕС‚РєСЂС‹С‚С‹Рµ РІСЂСѓС‡РЅСѓСЋ РёРіСЂРѕРєРѕРј, РµСЃР»Рё РёС… С‚РµРєСЃС‚ СЃРѕРІРїР°РґР°Р» СЃ РїР°С‚С‚РµСЂРЅРѕРј
    -- (РґРѕРј/РїСЂРёР±С‹Р»СЊ/Р¶РёРґРєРѕСЃС‚СЊ/РїРѕР»РєР°/СЃС‚РѕР№РєР°). РўРµРїРµСЂСЊ РїСЂСЏС‡РµРј РґРёР°Р»РѕРі, С‚РѕР»СЊРєРѕ РµСЃР»Рё
    -- СЃРµР№С‡Р°СЃ СЂРµР°Р»СЊРЅРѕ РІС‹РїРѕР»РЅСЏРµС‚СЃСЏ РјР°СЃСЃРѕРІР°СЏ Р·Р°РґР°С‡Р° (isMassAction) вЂ” РёРЅР°С‡Рµ
    -- СЃС‡РёС‚Р°РµРј, С‡С‚Рѕ РґРёР°Р»РѕРі РѕС‚РєСЂС‹С‚ РёРіСЂРѕРєРѕРј, Рё РЅРµ С‚СЂРѕРіР°РµРј РµРіРѕ.
    if isMassAction and dialogChecker:shouldHide(title, text) then
        return false
    end

    -- Скрыть диалог видеокарт 1 сек после обновления статусов
    if data.justFinishedUpdateAt and (os.clock() - data.justFinishedUpdateAt) < 1.0 then
        local cardDialogIds = {
            [dialogIdTable.videoCardSt]          = true,
            [dialogIdTable.videoCardDialogId]    = true,
            [dialogIdTable.houseFlashMinerDialogId] = true,
        }
        if cardDialogIds[dialogId] then
            return false
        end
    end
end

function sampev.onDialogClose(dialogId, button, listitem, input)
    utils.debugChat(string.format("[DIALOG] onDialogClose | id=%d button=%d listitem=%d input=%q", dialogId, button or -1, listitem or -1, tostring(input or "")))
    if dialogId == data.dFlashminerId then
        data.showHouseControlWindow[0] = false
    end
    coolantTool.handleDialogClose(dialogId, button, listitem, input)
end

function sampev.onPlayerSpawn()
    -- После релога (без полной перезагрузки скрипта) таблица data и os.clock()
    -- не сбрасываются, поэтому pending/current-mark могут остаться от дома,
    -- открытого ДО релога, и резолвер выдаст неверный номер дома, пока
    -- игрок не откроет /flashminer заново. Сбрасываем это состояние на
    -- каждом спавне, чтобы вместо неверного номера резолвер честно вернул
    -- "неизвестно", пока не появятся свежие данные.
    data.pendingHouseNumber = nil
    data.pendingHouseAt = 0
    data.currentFlashminerHouseNumber = nil
    data.currentFlashminerHouseAt = 0
    data.lastSelectedHouse = -1
end

function sampev.onServerMessage(color, text)
    if not cfg.active then return end

    if taxTool.handleServerMessage(color, text) then
        return false
    end

    if text:find("У вас нет флешки майнера") then
        data.stopAction = true
        data.hasFlashminer = false
        utils.addChat("У вас нет флешки майнера!")
        return false
    end
    if text:find('data_center_kwt') then
        return false
    end
    if text:find("Добро пожаловать в город Vice City!") then
        data.isViceCity = true
        return
    end
    if text:find("Добро пожаловать") and not text:find("Vice City") then
        data.isViceCity = false
        return
    end
    if text:find("^Вы вывели {ffffff}%d+ [BTCASC]+{ffff00}") then
        if text:find("BTC") then
            data.withdraw.btc = data.withdraw.btc + tonumber(text:match("Вы вывели {ffffff}(%d+)"))
        elseif text:find("ASC") then
            data.withdraw.asc = data.withdraw.asc + tonumber(text:match("Вы вывели {ffffff}(%d+)"))
        end
        return false
    elseif text:find("^Вам был добавлен предмет") and (text:find(":item1811:") or text:find(":item5996:") or text:find("BTC") or text:find("ASC")) then
        return false
    elseif text:find("^Добавлено в инвентарь") and text:find("BTC") then
        data.withdraw.btc = data.withdraw.btc + (tonumber(text:match('%((%d+) шт%)')) or 1)
        return false
    elseif text:find("Выводить прибыль можно только целыми частями") then
        return false
    elseif text:find("Выберите дом с майнинг фермой") then
        data.hasFlashminer = true
        return false
    elseif text:find("Не забудьте запустить видеокарту") then
        return false
    elseif text:find("охлаждающей жидкости в видеокарту, состояние системы охлаждения восстановлено") then
        return false
    elseif data.working then
        if text:find("недостаточно денежных") then
            utils.addChat("У вас недостаточно средств!")
            data.topUpLastFailed = true
            data.stopBySystem = true
            data.stopAction = true
            return false
        elseif text:find("нет охлаждающей жидкости") then
            if data.taskTypeNow == 'coolant' and not data.stopAction then
                data.stopAction = true
                data.stopBySystem = true
                utils.addChat("{F78181}Охлаждающая жидкость закончилась!")
            end
            return false
        elseif text:find("необходимо восстановить состояние системы охлаждения") then
            data.cardSwitchFailed = (data.cardSwitchFailed or 0) + 1
            return false
        elseif text:find("В этом доме нет подвала") or text:find("Жильцы дома не могут совершать") then
            data.houseHasNoBasement = true
            return false
        elseif text:find("дом в котором хотите пополнить счёт") then
            return false
        elseif text:find("Вы успешно пополнили счёт дома за") then
            return false
        end
    else
        if text:find("В этом доме нет подвала") or text:find("Жильцы дома не могут совершать") then
            if data.flashminerSwitchId.direction ~= 0 then
                sampSendChat("/flashminer")
                return false
            end
        end
    end

    if text:find("Вы успешно арендовали комнату в доме №(%d+)") then
        local house_id = text:match("доме №(%d+)")
        if house_id then
            cfg.excludedHouses[tostring(house_id)] = true
            save()
            utils.addChat("Дом №" .. house_id .. " добавлен в исключения (Аренда).")
        end
    end
end

function sampev.onSendDialogResponse(dialogId, button, listitem, input)
    utils.debugChat(string.format("[DIALOG] onSendDialogResponse | id=%d button=%d listitem=%d input=%q", dialogId, button, listitem, tostring(input or "")))
    if dialogId == dialogIdTable.houseDialogId and button == 1 then
        local selectedFromFlashminer = data.dialogData.flashminer[(tonumber(listitem) or -1) + 1]
        if selectedFromFlashminer then
            setPendingHouseNumber(selectedFromFlashminer.house_number)
        end
    end
    if dialogId == data.dFlashminerId and button == 1 and cfg.useDialogMode then
        local houseCount = #data.dialogData.flashminer
        if listitem == houseCount + 1 then
            local task = buildTaskTable('massSwitchCards')
            task:run(true)
            return false
        elseif listitem == houseCount + 2 then
            local task = buildTaskTable('collectFromAllHouses')
            task:run()
            return false
        elseif listitem == houseCount + 3 then
            local task = buildTaskTable('massSwitchCards')
            task:run(false)
            return false
        end
    end

    if dialogId == data.dFlashminerId then
        data.showHouseControlWindow[0] = false
    end
    return true
end

-- ==== Robust income-rate estimation helpers ====
-- Fixes: (1) РґРѕС…РѕРґ РІ РґРµРЅСЊ СЃС‡РёС‚Р°Р»СЃСЏ "РЅРµ РІ С‚РµС… РјР°СЃС€С‚Р°Р±Р°С…" РёР·-Р·Р° С‚РѕРіРѕ, С‡С‚Рѕ
--        РѕРґРЅРѕ СЃР»СѓС‡Р°Р№РЅРѕРµ РЅР°Р±Р»СЋРґРµРЅРёРµ СЃ РєРѕСЂРѕС‚РєРёРј РёРЅС‚РµСЂРІР°Р»РѕРј (РІСЃРїР»РµСЃРє/РІС‹РїР»Р°С‚Р° Р·Р°
--        РЅРµСЃРєРѕР»СЊРєРѕ С†РёРєР»РѕРІ СЃСЂР°Р·Сѓ) РїСЂРё СЌРєСЃС‚СЂР°РїРѕР»СЏС†РёРё РЅР° 24С‡ РґР°РІР°Р»Рѕ РѕРіСЂРѕРјРЅРѕРµ С‡РёСЃР»Рѕ
--        Рё РЅР°РґРѕР»РіРѕ Р·Р°СЃС‚СЂРµРІР°Р»Рѕ РІ СЃСЂРµРґРЅРµРј; (2) СЃС‚Р°СЂС‹Рµ РЅР°Р±Р»СЋРґРµРЅРёСЏ (РЅР°РїСЂРёРјРµСЂ, СЃРЅСЏС‚С‹Рµ
--        РґРѕ Р°РїРіСЂРµР№РґР° РєР°СЂС‚) РЅРёРєРѕРіРґР° РЅРµ СѓСЃС‚Р°СЂРµРІР°Р»Рё Рё РїСЂРѕРґРѕР»Р¶Р°Р»Рё РёСЃРєР°Р¶Р°С‚СЊ РѕС†РµРЅРєСѓ.
local INCOME_OBS_MAX_AGE = 3 * 24 * 60 * 60 -- РЅР°Р±Р»СЋРґРµРЅРёСЏ СЃС‚Р°СЂС€Рµ 3 РґРЅРµР№ Р±РѕР»СЊС€Рµ РЅРµ СѓС‡РёС‚С‹РІР°СЋС‚СЃСЏ

-- РќР°СЃРєРѕР»СЊРєРѕ РЅРѕРІРѕРµ РЅР°Р±Р»СЋРґРµРЅРёРµ РјРѕР¶РµС‚ РѕС‚Р»РёС‡Р°С‚СЊСЃСЏ РѕС‚ СѓР¶Рµ РїРѕРґС‚РІРµСЂР¶РґС‘РЅРЅРѕР№ СЃРєРѕСЂРѕСЃС‚Рё,
-- РїСЂРµР¶РґРµ С‡РµРј РѕРЅРѕ Р±СѓРґРµС‚ СЃС‡РёС‚Р°С‚СЊСЃСЏ РІС‹Р±СЂРѕСЃРѕРј (СЃР±РѕР№ РїР°СЂСЃРёРЅРіР°, СЃРјРµРЅР°/Р°РїРіСЂРµР№Рґ РєР°СЂС‚,
-- РїСЂРѕРїСѓС‰РµРЅРЅС‹Р№ СЃР±РѕСЂ Рё С‚.Рї.) Рё РѕС‚Р±СЂРѕС€РµРЅРѕ, Р° РЅРµ РїРѕРґРјРµС€Р°РЅРѕ РІ СЃСЂРµРґРЅРµРµ.
local INCOME_OUTLIER_RATIO = 3

local function pruneExpiredIncomeObs(obsList)
    local now = os.time()
    for i = #obsList, 1, -1 do
        local ts = obsList[i].timestamp or now
        if (now - ts) > INCOME_OBS_MAX_AGE then
            table.remove(obsList, i)
        end
    end
end

local function computeRobustDailyRate(obsList)
    if #obsList == 0 then return 0 end

    if #obsList < 4 then
        -- РњР°Р»Рѕ РґР°РЅРЅС‹С…, С‡С‚РѕР±С‹ С‡РµСЃС‚РЅРѕ РѕС‚Р±СЂР°РєРѕРІС‹РІР°С‚СЊ РІС‹Р±СЂРѕСЃС‹ С‚СЂРёРјРјРёРЅРіРѕРј.
        -- Р Р°РЅСЊС€Рµ Р·РґРµСЃСЊ Р±С‹Р»Рѕ СЃСЂРµРґРЅРµРІР·РІРµС€РµРЅРЅРѕРµ РїРѕ РІСЃРµРј С‚РѕС‡РєР°Рј - РѕРґРЅРѕ СЃР»СѓС‡Р°Р№РЅРѕРµ
        -- Р°РЅРѕРјР°Р»СЊРЅРѕРµ РЅР°Р±Р»СЋРґРµРЅРёРµ (РєРѕСЂРѕС‚РєРёР№ РёРЅС‚РµСЂРІР°Р» + СЃРєР°С‡РѕРє РёР·-Р·Р° СЃРјРµРЅС‹ РєР°СЂС‚,
        -- СЃР±РѕСЏ РїР°СЂСЃРёРЅРіР° РґРёР°Р»РѕРіР° Рё С‚.Рї.) РµРґРёРЅРѕР»РёС‡РЅРѕ РѕРїСЂРµРґРµР»СЏР»Рѕ РёС‚РѕРіРѕРІСѓСЋ С†РёС„СЂСѓ,
        -- РєРѕС‚РѕСЂСѓСЋ РІРёРґРµР» РёРіСЂРѕРє ("РґРѕС…РѕРґ СЃ РїРѕС‚РѕР»РєР°"). РњРµРґРёР°РЅР° СѓСЃС‚РѕР№С‡РёРІР° Рє С‚Р°РєРѕРјСѓ
        -- РѕРґРёРЅРѕС‡РЅРѕРјСѓ РІС‹Р±СЂРѕСЃСѓ РґР°Р¶Рµ РїСЂРё 2-3 РЅР°Р±Р»СЋРґРµРЅРёСЏС….
        local rates = {}
        for _, obs in ipairs(obsList) do table.insert(rates, obs.rate) end
        table.sort(rates)
        local n = #rates
        if n % 2 == 1 then
            return rates[(n + 1) / 2]
        else
            return (rates[n / 2] + rates[n / 2 + 1]) / 2
        end
    end

    -- РћС‚Р±СЂР°СЃС‹РІР°РµРј СЃР°РјРѕРµ РІС‹СЃРѕРєРѕРµ Рё СЃР°РјРѕРµ РЅРёР·РєРѕРµ РЅР°Р±Р»СЋРґРµРЅРёРµ (С‚СЂРёРјРјРµРґ-mean),
    -- С‡С‚РѕР±С‹ РµРґРёРЅРёС‡РЅС‹Р№ РІСЃРїР»РµСЃРє (РЅР°РїСЂРёРјРµСЂ, РµСЃР»Рё РїСЂРѕРІРµСЂРєР° РїРѕРїР°Р»Р° РЅР° РјРѕРјРµРЅС‚ РІС‹РїР»Р°С‚С‹
    -- СЃСЂР°Р·Сѓ Р·Р° РЅРµСЃРєРѕР»СЊРєРѕ С†РёРєР»РѕРІ) РЅРµ Р·Р°РІС‹С€Р°Р» РёС‚РѕРіРѕРІСѓСЋ РѕС†РµРЅРєСѓ РІ СЂР°Р·С‹.
    local sorted = {}
    for i, obs in ipairs(obsList) do sorted[i] = obs end
    table.sort(sorted, function(a, b) return a.rate < b.rate end)

    local weightedSum, totalWeight = 0, 0
    for i = 2, #sorted - 1 do
        local obs = sorted[i]
        local weight = obs.minutes or 1
        weightedSum  = weightedSum + obs.rate * weight
        totalWeight  = totalWeight + weight
    end
    return totalWeight > 0 and (weightedSum / totalWeight) or 0
end

function updateHouseStatus(houseNumber, houseData)
    if not data.houseStatuses[houseNumber] then
        data.houseStatuses[houseNumber] = {
            status = "unknown",
            lastCheck = 0,
            issues = {},
            earnings = { btc = 0, asc = 0 },
            minCoolant = 101,
            cardLevels = {}
        }
    end

    local status = data.houseStatuses[houseNumber]
    status.lastCheck = os.time()
    status.issues = {}
    status.earnings = { btc = 0, asc = 0 }
    status.minCoolant = 101
    status.cardLevels = {}
    status.coolantsNeeded = 0

    local cardsOff = 0
    local cardsLowCoolant = 0
    local totalCards = #data.dialogData.videocards
    local isExcluded = cfg.excludedHouses[tostring(houseNumber)] or false
    local houseId = tostring(houseNumber)

    if not cfg.cardSnapshots[houseId] then
        cfg.cardSnapshots[houseId] = { slots = {}, time = 0 }
    end
    local snapshot = cfg.cardSnapshots[houseId]
    if not snapshot.slots then snapshot.slots = {} end

    local timeDiffMinutes = 0
    if snapshot.time and snapshot.time > 0 then
        timeDiffMinutes = (os.time() - snapshot.time) / 60
    end

    local MIN_INTERVAL = 60 -- Р±С‹Р»Рѕ 30: РјРЅРѕР¶РёС‚РµР»СЊ СЌРєСЃС‚СЂР°РїРѕР»СЏС†РёРё x48 РЅР° 30 РјРёРЅСѓС‚Р°С… РІСЃС‘ РµС‰С‘ СЃР»РёС€РєРѕРј Р»РµРіРєРѕ СЂР°Р·РґСѓРІР°Р» СЃР»СѓС‡Р°Р№РЅС‹Р№ С€СѓРј/СЃРєР°С‡РѕРє РґРѕ Р±РµР·СѓРјРЅРѕР№ С†РёС„СЂС‹ "РІ РґРµРЅСЊ"; РЅР° С‡Р°СЃРµ РјРЅРѕР¶РёС‚РµР»СЊ x24
    local shouldUpdateSnapshot = ((snapshot.time or 0) == 0) or (timeDiffMinutes >= MIN_INTERVAL)

    if totalCards > 0 then
        for _, card in ipairs(data.dialogData.videocards) do
            if not card.working then
                cardsOff = cardsOff + 1
            end

            local cardNeeded = 0
            if card.coolant < cfg.useCoolantPercent then
                local effectiveSuper = cfg.useSuperCoolant or data.isViceCity
                if effectiveSuper then
                    cardNeeded = 1
                elseif cfg.economyMode then
                    if card.coolant < 70 then
                        cardNeeded = (card.coolant < 20) and 2 or 1
                    end
                else
                    if card.coolant < 100 then
                        cardNeeded = (card.coolant < 50) and 2 or 1
                    end
                end
            end
            status.coolantsNeeded = status.coolantsNeeded + cardNeeded

            if card.coolant < cfg.useCoolantPercent then cardsLowCoolant = cardsLowCoolant + 1 end
            if card.coolant < status.minCoolant then status.minCoolant = card.coolant end

            if card.level and card.level > 0 then
                if not status.cardLevels[card.level] then
                    status.cardLevels[card.level] = {
                        total = 0,
                        working = 0,
                        btc = { total = 0, working = 0 },
                        asc = { total = 0, working = 0 }
                    }
                end

                status.cardLevels[card.level].total = status.cardLevels[card.level].total + 1
                if card.working then
                    status.cardLevels[card.level].working = status.cardLevels[card.level].working + 1
                end

                if card.card_type == "ASIC" then
                    status.cardLevels[card.level]["btc"].total = status.cardLevels[card.level]["btc"].total + 1
                    status.cardLevels[card.level]["asc"].total = status.cardLevels[card.level]["asc"].total + 1
                    if card.working then
                        status.cardLevels[card.level]["btc"].working = status.cardLevels[card.level]["btc"].working + 1
                        status.cardLevels[card.level]["asc"].working = status.cardLevels[card.level]["asc"].working + 1
                    end
                else
                    local currency = (card.fluidType == 1) and "btc" or "asc"
                    status.cardLevels[card.level][currency].total = status.cardLevels[card.level][currency].total + 1
                    if card.working then
                        status.cardLevels[card.level][currency].working = status.cardLevels[card.level][currency]
                            .working + 1
                    end
                end
            end

            status.earnings.btc = status.earnings.btc + card.btc
            status.earnings.asc = status.earnings.asc + card.asc
        end

        local currentBtcTotal = 0
        local currentAscTotal = 0
        for _, card in ipairs(data.dialogData.videocards) do
            if card.fluidType == 1 or card.card_type == "ASIC" then
                currentBtcTotal = currentBtcTotal + (card.btc_full or card.btc or 0)
            end
            if card.fluidType == 2 or card.card_type == "ASIC" then
                currentAscTotal = currentAscTotal + (card.asc_full or card.asc or 0)
            end
        end

        snapshot.lastBtcTotal = currentBtcTotal
        snapshot.lastAscTotal = currentAscTotal

        -- РћС‚РїРµС‡Р°С‚РѕРє "СЃРѕСЃС‚Р°РІР°" РІРёРґРµРѕРєР°СЂС‚ (РєРѕР»-РІРѕ + СЃСѓРјРјР° СѓСЂРѕРІРЅРµР№). Р•СЃР»Рё РјРµР¶РґСѓ
        -- РґРІСѓРјСЏ РїСЂРѕРІРµСЂРєР°РјРё РёРіСЂРѕРє РґРѕР±Р°РІРёР» / СЃРЅСЏР» / РїСЂРѕРєР°С‡Р°Р» РєР°СЂС‚Сѓ, СЂР°Р·РЅРёС†Р°
        -- currentBtcTotal-prevBtcTotal - СЌС‚Рѕ РЅРµ РґРѕС…РѕРґ Р·Р° РїСЂРѕС€РµРґС€РµРµ РІСЂРµРјСЏ, Р°
        -- СЃРєР°С‡РѕРє РѕР±С‰РµР№ С‘РјРєРѕСЃС‚Рё. Р Р°РЅСЊС€Рµ С‚Р°РєР°СЏ СЂР°Р·РЅРёС†Р° РІСЃС‘ СЂР°РІРЅРѕ СЌРєСЃС‚СЂР°РїРѕР»РёСЂРѕРІР°Р»Р°СЃСЊ
        -- РЅР° СЃСѓС‚РєРё Рё РґР°РІР°Р»Р° "РґРѕС…РѕРґ СЃ РїРѕС‚РѕР»РєР°"; С‚РµРїРµСЂСЊ С‚Р°РєРѕРµ РЅР°Р±Р»СЋРґРµРЅРёРµ РїСЂРѕСЃС‚Рѕ
        -- РїСЂРѕРїСѓСЃРєР°РµС‚СЃСЏ, Р° РЅРµ РїРѕСЂС‚РёС‚ СЃС‚Р°С‚РёСЃС‚РёРєСѓ.
        local compositionSum = 0
        for _, card in ipairs(data.dialogData.videocards) do
            compositionSum = compositionSum + (card.level or 0)
        end
        local compositionSignature = totalCards .. ":" .. compositionSum
        local compositionChanged = snapshot.lastComposition ~= nil
            and snapshot.lastComposition ~= compositionSignature
        snapshot.lastComposition = compositionSignature

        if not snapshot.incomeObs then snapshot.incomeObs = {} end
        if not snapshot.incomeAscObs then snapshot.incomeAscObs = {} end

        -- Immediate ASC/day bootstrap: real ASC observations still override this later.
        if (snapshot.dailyAscRate or 0) <= 0
            and (snapshot.dailyBtcRate or 0) > 0
            and currentBtcTotal > 0
            and currentAscTotal > 0 then
            snapshot.dailyAscRate = snapshot.dailyBtcRate * (currentAscTotal / currentBtcTotal)
            utils.debugChat(string.format(
                "[INCOME] House #%d: ASC/day bootstrap %.2f from ratio ASC/BTC %.4f",
                houseNumber, snapshot.dailyAscRate, currentAscTotal / currentBtcTotal
            ))
            local t = os.clock()
            if t - _snapshotSaveT > 5.0 then
                _snapshotSaveT = t
                save()
            end
        end

        if (snapshot.time or 0) > 0 and timeDiffMinutes >= MIN_INTERVAL and compositionChanged then
            utils.debugChat(string.format(
                "[INCOME] \xc4\xee\xec \xb9%d: \xf1\xee\xf1\xf2\xe0\xe2 \xe2\xe8\xe4\xe5\xee\xea\xe0\xf0\xf2 \xe8\xe7\xec\xe5\xed\xe8\xeb\xf1\xff (%s -> %s), \xef\xf0\xee\xef\xf3\xf1\xea\xe0\xe5\xec \xe7\xe0\xec\xe5\xf0 \xf1\xea\xee\xf0\xee\xf1\xf2\xe8 \xed\xe0 \xfd\xf2\xee\xec \xf6\xe8\xea\xeb\xe5",
                houseNumber, tostring(snapshot.lastComposition), compositionSignature
            ))
        elseif (snapshot.time or 0) > 0 and timeDiffMinutes >= MIN_INTERVAL then
            -- BTC rate
            local prevBtcTotal = snapshot.prevBtcTotal or 0
            local diff = currentBtcTotal - prevBtcTotal

            if diff > 0 then
                local dailyRate = (diff / timeDiffMinutes) * 60 * 24
                local establishedBtcRate = snapshot.dailyBtcRate or 0
                local isBtcOutlier = establishedBtcRate > 0
                    and (dailyRate > establishedBtcRate * INCOME_OUTLIER_RATIO
                        or dailyRate < establishedBtcRate / INCOME_OUTLIER_RATIO)

                if isBtcOutlier then
                    utils.debugChat(string.format(
                        "[INCOME] \xc4\xee\xec \xb9%d: \xed\xe0\xe1\xeb\xfe\xe4\xe5\xed\xe8\xe5 \xef\xee\xf5\xee\xe6\xe5 \xed\xe0 \xe2\xfb\xe1\xf0\xee\xf1 (%.2f BTC/\xe4\xe5\xed\xfc \xef\xf0\xe8 \xef\xee\xe4\xf2\xe2\xe5\xf0\xe6\xe4\xb8\xed\xed\xfb\xf5 %.2f) - \xed\xe5 \xf3\xf7\xf2\xe5\xed\xee",
                        houseNumber, dailyRate, establishedBtcRate
                    ))
                else
                    table.insert(snapshot.incomeObs, { rate = dailyRate, minutes = timeDiffMinutes, timestamp = os.time() })
                    pruneExpiredIncomeObs(snapshot.incomeObs)
                    while #snapshot.incomeObs > 15 do
                        table.remove(snapshot.incomeObs, 1)
                    end

                    if #snapshot.incomeObs >= 3 then
                        snapshot.dailyBtcRate = computeRobustDailyRate(snapshot.incomeObs)
                        utils.debugChat(string.format(
                            "[INCOME] \xc4\xee\xec \xb9%d: %.2f BTC/\xe4\xe5\xed\xfc (\xed\xe0\xe1\xeb\xfe\xe4: %d, diff: %.3f \xe7\xe0 %.1f \xec\xe8\xed)",
                            houseNumber, snapshot.dailyBtcRate, #snapshot.incomeObs, diff, timeDiffMinutes
                        ))
                    end
                end
            elseif diff == 0 then
                utils.debugChat(string.format(
                    "[INCOME] \xc4\xee\xec \xb9%d: \xe1\xe0\xeb\xe0\xed\xf1 \xed\xe5 \xe8\xe7\xec\xe5\xed\xe8\xeb\xf1\xff (%.3f), \xef\xf0\xee\xef\xf3\xf1\xea\xe0\xe5\xec",
                    houseNumber, currentBtcTotal
                ))
            end

            -- ASC rate
            local prevAscTotal = snapshot.prevAscTotal or 0
            local diffAsc = currentAscTotal - prevAscTotal

            if diffAsc > 0 then
                local dailyAscRate = (diffAsc / timeDiffMinutes) * 60 * 24
                local establishedAscRate = snapshot.dailyAscRate or 0
                local isAscOutlier = establishedAscRate > 0
                    and (dailyAscRate > establishedAscRate * INCOME_OUTLIER_RATIO
                        or dailyAscRate < establishedAscRate / INCOME_OUTLIER_RATIO)

                if isAscOutlier then
                    utils.debugChat(string.format(
                        "[INCOME] \xc4\xee\xec \xb9%d: \xed\xe0\xe1\xeb\xfe\xe4\xe5\xed\xe8\xe5 \xef\xee\xf5\xee\xe6\xe5 \xed\xe0 \xe2\xfb\xe1\xf0\xee\xf1 (%.2f ASC/\xe4\xe5\xed\xfc \xef\xf0\xe8 \xef\xee\xe4\xf2\xe2\xe5\xf0\xe6\xe4\xb8\xed\xed\xfb\xf5 %.2f) - \xed\xe5 \xf3\xf7\xf2\xe5\xed\xee",
                        houseNumber, dailyAscRate, establishedAscRate
                    ))
                else
                    table.insert(snapshot.incomeAscObs, { rate = dailyAscRate, minutes = timeDiffMinutes, timestamp = os.time() })
                    pruneExpiredIncomeObs(snapshot.incomeAscObs)
                    while #snapshot.incomeAscObs > 15 do
                        table.remove(snapshot.incomeAscObs, 1)
                    end

                    if #snapshot.incomeAscObs >= 3 then
                        snapshot.dailyAscRate = computeRobustDailyRate(snapshot.incomeAscObs)
                        utils.debugChat(string.format(
                            "[INCOME] \xc4\xee\xec \xb9%d: %.2f ASC/\xe4\xe5\xed\xfc (\xed\xe0\xe1\xeb\xfe\xe4: %d, diff: %.3f \xe7\xe0 %.1f \xec\xe8\xed)",
                            houseNumber, snapshot.dailyAscRate, #snapshot.incomeAscObs, diffAsc, timeDiffMinutes
                        ))
                    end
                end
            end
        end

        if shouldUpdateSnapshot then
            snapshot.prevBtcTotal = currentBtcTotal
            snapshot.prevAscTotal = currentAscTotal
            snapshot.time = os.time()
            local t = os.clock()
            if t - _snapshotSaveT > 5.0 then
                _snapshotSaveT = t
                save()
            end
        end
    else
        status.minCoolant = 0
    end

    if not isExcluded then
        if cardsOff > 0 then
            table.insert(status.issues, string.format("Выключено видеокарт: %d/%d", cardsOff, totalCards))
        end
        if cardsLowCoolant > 0 then
            table.insert(status.issues, string.format("Мало жидкости: %d/%d", cardsLowCoolant, totalCards))
        end

        local balanceThreshold = cfg.minBalanceWarning or 5000000
        if houseData and houseData.balance < balanceThreshold then
            table.insert(status.issues, string.format("Низкий баланс: $%s", utils.formatNumber(houseData.balance)))
        end

        if houseData and houseData.tax then
            if houseData.tax >= 90000 then
                table.insert(status.issues, string.format("Высокий налог: $%s", utils.formatNumber(houseData.tax)))
            elseif houseData.tax >= 50000 then
                table.insert(status.issues, string.format("Повышенный налог: $%s", utils.formatNumber(houseData.tax)))
            end
        end
    end

    if isExcluded then
        status.status = "good"
    else
        local hasBadIssue = cardsOff > 0 or cardsLowCoolant > 0 or
            (houseData and houseData.tax and houseData.tax >= 90000)
        local hasWarningIssue = houseData and
            (houseData.balance < (cfg.minBalanceWarning or 5000000) or (houseData.tax and houseData.tax >= 50000))
        if hasBadIssue then
            status.status = "bad"
        elseif hasWarningIssue then
            status.status = "warning"
        else
            status.status = "good"
        end
    end
end

function resetIncomeRates()
    for _, snap in pairs(cfg.cardSnapshots) do
        snap.incomeObs    = {}
        snap.incomeAscObs = {}
        snap.dailyBtcRate = nil
        snap.dailyAscRate = nil
        snap.prevBtcTotal = nil
        snap.prevAscTotal = nil
    end
    save()
    utils.addChat("\xc4\xe0\xed\xed\xfb\xe5 \xee \xe4\xee\xf5\xee\xe4\xe0\xf5 \xf1\xe1\xf0\xee\xf8\xe5\xed\xfb.")
end

function buildTaskTable(taskType, ...)
    local function visitHouseCards(sendResponse, house, onCards, skipCount)
        progressTracker.setHouseTotal(0)
        data.dialogData.videocards = {}
        data.houseHasNoBasement = false
        dialogActions.selectHouse(sendResponse, house.index - 1)
        local t = 0
        while #data.dialogData.videocards == 0 and t < 2800 do
            wait(50); t = t + 50
            if data.houseHasNoBasement then break end
        end
        if data.houseHasNoBasement then
            utils.addChat(string.format("{F78181}Дом №%d: нет доступа, пропускаем", house.house_number))
            sampSendChat("/flashminer")
            wait(150)
            if not skipCount then progressTracker.increment() end
            return false, true
        end
        -- Если данные так и не пришли (лаги/задержка сервера) — пробуем переоткрыть
        -- дом ещё раз, прежде чем считать его пустым.
        if #data.dialogData.videocards == 0 then
            wait(80)
            dialogActions.selectHouse(sendResponse, house.index - 1)
            t = 0
            while #data.dialogData.videocards == 0 and t < 1600 do
                wait(50); t = t + 50
                if data.houseHasNoBasement then break end
            end
        end
        wait(40)
        local confirmed = #data.dialogData.videocards > 0
        if not confirmed then wait(80) end
        onCards(data.dialogData.videocards)
        wait(40)
        dialogActions.closeDialog(sendResponse)
        -- FIX (11/9 house-counter bug): this function used to always bump
        -- the house progress counter, even when it was being called a
        -- second time as a retry for a house that was already counted in
        -- the first pass. That made the numerator overtake the denominator
        -- (e.g. showing 11 / 9 домов). The retry pass now passes
        -- skipCount = true so the same house is never counted twice.
        if not skipCount then progressTracker.increment() end
        return true, confirmed
    end

    local function collectCardsFromHouse(sendResponse)
        local cardsToCollect = {}
        for _, card in ipairs(data.dialogData.videocards) do
            if card.btc >= 1 or card.asc >= 1 then
                table.insert(cardsToCollect, card)
            end
        end

        if #cardsToCollect == 0 then return 0, 0 end

        -- FIX (14/12 counter bug): mining keeps running while we collect, so
        -- during retry attempts extra cards can cross the >=1 threshold again
        -- and get counted. The "house total" denominator used to be frozen
        -- before collection started, so the numerator could overtake it
        -- (e.g. showing 14/12). Grow the denominator whenever more cards are
        -- genuinely found than were still expected, so the counter stays
        -- consistent instead of overshooting.
        local remaining = data.progressHouseTotal - data.progressHouseCurrent
        if #cardsToCollect > remaining then
            data.progressHouseTotal = data.progressHouseTotal + (#cardsToCollect - remaining)
        end

        local btcCollected, ascCollected = 0, 0
        for idx, card in ipairs(cardsToCollect) do
            progressTracker.increment(true)

            dialogActions.selectCard(sendResponse, card.index - 1)

            if card.btc >= 1 then
                dialogActions.withdrawBTC(sendResponse)
                btcCollected = btcCollected + card.btc
            end

            if card.asc >= 1 then
                dialogActions.withdrawASC(sendResponse)
                ascCollected = ascCollected + card.asc
            end

            if data.isRodina then
                utils.pressButton(1024)
                wait(1000)
                local waitedBack, backOk = 0, false
                while waitedBack < 8000 do
                    if sampIsDialogActive() and sampGetCurrentDialogId() == data.dFlashminerId then
                        backOk = true
                        break
                    end
                    if data.stopAction or data.collectCancelled then break end
                    wait(50)
                    waitedBack = waitedBack + 50
                end
                if not backOk and not (data.stopAction or data.collectCancelled)
                    and sampIsDialogActive() and not isOwnScriptDialogId(sampGetCurrentDialogId()) then
                    -- Диалог, который сейчас открыт, скрипту не принадлежит —
                    -- скорее всего, это своё окно игрока (телефон, инвентарь
                    -- и т.п.). Раньше здесь диалог закрывался принудительно,
                    -- что могло оборвать действие игрока. Вместо этого просто
                    -- ждём, пока игрок сам его закроет, и продолжаем как обычно.
                    backOk = waitForForeignDialogToClose(nil, data.dFlashminerId)
                end
                if not backOk and not (data.stopAction or data.collectCancelled) then
                    utils.debugChat("[COLLECT] Timeout waiting for flashminer dialog after withdraw, forcing /flashminer")
                    if sampIsDialogActive() and isOwnScriptDialogId(sampGetCurrentDialogId()) then
                        sampCloseCurrentDialogWithButton(0)
                        wait(300)
                    end
                    sampSendChat("/flashminer")
                    local t2 = 0
                    while t2 < 5000 do
                        if sampIsDialogActive() and sampGetCurrentDialogId() == data.dFlashminerId then break end
                        wait(100); t2 = t2 + 100
                    end
                end
            else
                dialogActions.closeDialog(sendResponse, dialogIdTable.videoCardDialogId)
            end
        end

        return btcCollected, ascCollected
    end
    local function switchCardsInHouse(sendResponse, enableCards)
        local cardsToSwitch = {}
        for _, card in ipairs(data.dialogData.videocards) do
            if enableCards and not card.working then
                if card.coolant > 0 then
                    table.insert(cardsToSwitch, card)
                else
                    utils.debugChat(string.format("Пропускаем карту [%d] — жидкость 0%%", card.index))
                end
            elseif not enableCards and card.working then
                table.insert(cardsToSwitch, card)
            end
        end

        if #cardsToSwitch == 0 then return 0 end

        data.cardSwitchFailed = 0
        for idx, card in ipairs(cardsToSwitch) do
            progressTracker.increment(true)
            dialogActions.selectCard(sendResponse, card.index - 1)
            dialogActions.switchCard(sendResponse)
        end
        wait(250)

        local failed = data.cardSwitchFailed or 0
        return math.max(0, #cardsToSwitch - failed)
    end
    local function createProtectedTask(taskFunction, ...)
        local args = { ... }
        return taskState.ifNotWorking(function()
            local action_count = 0
            lua_thread.create(function()
                taskState.setWorking(true)
                data.taskTypeNow = taskType
                data.stopAction = false
                local startTime = os.clock()
                utils.debugChat(string.format("Задача '%s' запущена...", taskType))
                action_count = (os.clock() - data.globalActionCounter.lastActionTime) > 3.0 and 0 or
                    data.globalActionCounter.count

                local function sendResponse(...)
                    if data.stopAction then return end
                    local function isPaydayTime()
                        if data.skipPayday then return false end

                        if data.paydaySkippedAt > 0 and (os.time() - data.paydaySkippedAt) < 120 then
                            return false
                        end

                        local os_time = os.time()
                        local M = tonumber(os.date("%M", os_time))
                        local S = tonumber(os.date("%S", os_time))

                        return ((M == 59 and S >= 50) or (M == 0 and S <= 20) or
                                (M == 29 and S >= 50) or (M == 30 and S <= 20)) and
                            (taskType ~= 'updateStatuses' and taskType ~= 'scanBasements')
                    end

                    if isPaydayTime() and cfg.pauseOnPayday then
                        data.isWaitingPayday = true
                        data.skipPayday = false
                        utils.debugChat("{ffe133}Время PayDay...")

                        while not data.skipPayday do
                            local os_time = os.time()
                            local M = tonumber(os.date("%M", os_time))
                            local S = tonumber(os.date("%S", os_time))
                            local stillPayday = (M == 59 and S >= 50) or (M == 0 and S <= 20) or
                                (M == 29 and S >= 50) or (M == 30 and S <= 20)

                            if not stillPayday then break end

                            wait(500)
                            if data.stopAction then
                                data.isWaitingPayday = false
                                data.skipPayday = false
                                return
                            end
                        end

                        data.paydaySkippedAt = os.time()
                        data.isWaitingPayday = false
                        data.skipPayday = false
                        utils.debugChat("{99ff99}Продолжаем.")
                        wait(1000)
                    end
                    sampSendDialogResponse(...)
                    action_count = action_count + 1
                    -- FIX (anti-kick): раньше пауза срабатывала только каждые count_action действий,
                    -- что позволяло отправлять пакеты совсем без задержки внутри батча и могло
                    -- выглядеть как бот для антифрода сервера. Теперь между любыми двумя пакетами
                    -- есть минимум 40 мс, независимо от настроек и сервера.
                    wait(40)
                    if not data.isRodina and action_count > 0 and action_count % cfg.count_action == 0 then
                        if taskType ~= 'updateStatuses' then
                            wait(cfg.pause_duration)
                        else
                            wait(150)
                        end
                        utils.debugChat(string.format('Пауза на %d действии', action_count))
                    end
                end

                local success, err = pcall(function() taskFunction(sendResponse, unpack(args)) end)

                if not success then
                    utils.addChat("{F78181}Критическая ошибка: " .. tostring(err))
                    print("{F78181}Критическая ошибка: " .. tostring(err))
                    if sampIsDialogActive() then
                        sampCloseCurrentDialogWithButton(0)
                    end
                end
                if data.stopAction and not data.stopBySystem then
                    utils.addChat("{FFE133}Остановлено пользователем.")
                end
                data.stopBySystem = false

                local duration = os.clock() - startTime
                utils.debugChat(string.format("Задача '%s' завершена за %.2f сек.", taskType, duration))
                data.globalActionCounter.count = action_count
                data.globalActionCounter.lastActionTime = os.clock()

                progressTracker.reset()
                wait(100)
                taskState.setWorking(false)
                if taskType == 'updateStatuses' then
                    imgui.addNotification(u8 'Обновлено')
                    data.justFinishedUpdateAt = os.clock()
                end
                data.taskTypeNow = nil
            end)
        end)
    end

    local task = {
        data = {
            mainId = data.dFlashminerId,
            listBoxes = {}
        }
    }

    if taskType == 'coolant' then
        task.coolant = function(self)
            createProtectedTask(function(sendResponse)
                local cardsToProcess = {}
                for _, card in ipairs(data.dialogData.videocards) do
                    if card.coolant < cfg.useCoolantPercent then
                        table.insert(cardsToProcess, card)
                    end
                end

                if #cardsToProcess == 0 then
                    if not cfg.fixCoolantEnabled then
                        utils.addChat("Во всех видеокартах достаточно охлаждающей жидкости.")
                    end
                    return
                end

                local coolantBottles = 0
                local actuallyFilled = 0

                for _, card in ipairs(cardsToProcess) do
                    if data.stopAction then break end

                    local effectiveSuper = cfg.useSuperCoolant or data.isViceCity
                    local refill_count = effectiveSuper and 1 or ((card.coolant < 50.0) and 2 or 1)
                    if not effectiveSuper and cfg.economyMode and (card.coolant + 50) > 70 then
                        refill_count = 1
                    end

                    for i = 1, refill_count do
                        if data.stopAction then break end
                        dialogActions.selectCard(sendResponse, card.index - 1)
                        dialogActions.refillCoolant(sendResponse, card.fluidType, effectiveSuper,
                            card.card_type == "ASIC")
                    end

                    wait(200)

                    if not data.stopAction then
                        actuallyFilled = actuallyFilled + 1
                        coolantBottles = coolantBottles + refill_count
                        card.coolant = 100
                        dialogActions.closeDialog(sendResponse, dialogIdTable.videoCardDialogId)
                    end
                end

                if actuallyFilled > 0 then
                    logsTool.addCoolant(actuallyFilled, coolantBottles, cfg.useSuperCoolant)
                end
            end)
        end
    elseif taskType == 'switchCards' then
        task.switchCards = function(self, enable)
            createProtectedTask(function(sendResponse)
                local totalSwitched = 0
                for attempt = 1, 2 do
                    local count = switchCardsInHouse(sendResponse, enable)
                    totalSwitched = totalSwitched + count
                    if count == 0 then
                        if attempt == 1 then
                            utils.addChat("Видеокарты и так уже " ..
                                (enable and "включены." or "выключены."))
                        end
                        break
                    end
                    if attempt == 1 then wait(300) end
                end
                if totalSwitched > 0 then
                    logsTool.add('switch', { enabled = enable, count = totalSwitched })
                end
            end)
        end
    elseif taskType == 'takeCrypto' then
        task.takeCrypto = function(self)
            createProtectedTask(function(sendResponse)
                data.withdraw = { asc = 0, btc = 0 }

                for attempt = 1, 2 do
                    local btc, asc = collectCardsFromHouse(sendResponse)
                    if btc == 0 and asc == 0 then
                        if attempt == 1 then
                            utils.addChat("Нет криптовалюты для снятия.")
                        end
                        break
                    end

                    if attempt == 1 then wait(300) end
                end
                wait(300)
                local earnings, hasEarnings = formatEarnings(
                    data.withdraw.btc, data.withdraw.asc,
                    not data.isRodina, "{ffffff} и "
                )
                if hasEarnings then
                    utils.addChat("Выведено: " .. earnings .. "{ffffff}.")
                end
                if data.withdraw.btc > 0 or data.withdraw.asc > 0 then
                    logsTool.add('collect', { btc = data.withdraw.btc, asc = data.withdraw.asc, houses = 1 })
                end
            end)
        end
    elseif taskType == 'collectFromAllHouses' then
        task.run = function(self)
            local houses = {}
            for _, h in ipairs(data.dialogData.flashminer) do table.insert(houses, h) end
            if not houses or #houses == 0 then
                utils.addChat("{F78181}Список домов не найден. Повторите попытку.")
                return false
            end
            local housesToProcess = {}
            for _, house in ipairs(houses) do
                if houseFilter.shouldProcess(house) then
                    table.insert(housesToProcess, house)
                end
            end
            data.withdraw = { asc = 0, btc = 0 }

            createProtectedTask(function(sendResponse)
                local actualHousesToProcess = {}
                local unconfirmedHouses = {}
                for _, house in ipairs(housesToProcess) do
                    local status = data.houseStatuses[house.house_number]
                    if status and status.lastCheck > 0 then
                        local btc = (status.earnings and status.earnings.btc) or 0
                        local asc = (status.earnings and status.earnings.asc) or 0
                        local minThreshold = cfg.collectOnlyIfMin or 0
                        local hasBtc = btc >= math.max(1, minThreshold)
                        local hasAsc = asc >= 1
                        if hasBtc or hasAsc then
                            table.insert(actualHousesToProcess, house)
                        end
                    else
                        table.insert(actualHousesToProcess, house)
                    end
                end

                progressTracker.setTotal(#actualHousesToProcess)
                local housesCollectedFrom = 0
                for i, house in ipairs(actualHousesToProcess) do
                    if data.stopAction then break end
                    data.currentCollectHouse = u8(string.format("Дом №%d (%d/%d)",
                        house.house_number, i, #actualHousesToProcess))

                    local status = data.houseStatuses[house.house_number]
                    if status and status.lastCheck > 0 then
                        local hasBtc = status.earnings and status.earnings.btc >= 1
                        local hasAsc = status.earnings and status.earnings.asc >= 1
                        if not hasBtc and not hasAsc then
                            progressTracker.increment()
                            goto continue_loop
                        end
                    end

                    local prevBtc = data.withdraw.btc
                    local prevAsc = data.withdraw.asc
                    local handled, confirmed = visitHouseCards(sendResponse, house, function(cards)
                        local cardsToCollect = {}
                        for _, card in ipairs(cards) do
                            if card.btc >= 1 or card.asc >= 1 then table.insert(cardsToCollect, card) end
                        end
                        progressTracker.setHouseTotal(#cardsToCollect)
                        local maxAttempts = 2
                        for attempt = 1, maxAttempts do
                            local btc, asc = collectCardsFromHouse(sendResponse)
                            if btc == 0 and asc == 0 then break end
                            if attempt < maxAttempts then wait(150) end
                        end
                    end)
                    if handled and not confirmed then
                        table.insert(unconfirmedHouses, house)
                    end
                    if data.withdraw.btc > prevBtc or data.withdraw.asc > prevAsc then
                        housesCollectedFrom = housesCollectedFrom + 1
                    end
                    ::continue_loop::
                end

                -- Some houses may not have been confirmed (dialog didn't load in
                -- time, e.g. because of lag or interference from another open
                -- dialog while the player was busy). Retry them once instead of
                -- silently finishing with only part of the total collected.
                if #unconfirmedHouses > 0 and not data.stopAction then
                    wait(150)
                    utils.debugChat(string.format("[COLLECT] Retry pass for %d unconfirmed house(s)", #unconfirmedHouses))
                    for ri, house in ipairs(unconfirmedHouses) do
                        if data.stopAction then break end
                        local prevBtc2 = data.withdraw.btc
                        local prevAsc2 = data.withdraw.asc
                        visitHouseCards(sendResponse, house, function(cards)
                            local cardsToCollect = {}
                            for _, card in ipairs(cards) do
                                if card.btc >= 1 or card.asc >= 1 then table.insert(cardsToCollect, card) end
                            end
                            progressTracker.setHouseTotal(#cardsToCollect)
                            local maxAttempts = 2
                            for attempt = 1, maxAttempts do
                                local btc, asc = collectCardsFromHouse(sendResponse)
                                if btc == 0 and asc == 0 then break end
                                if attempt < maxAttempts then wait(150) end
                            end
                        end, true)
                        if data.withdraw.btc > prevBtc2 or data.withdraw.asc > prevAsc2 then
                            housesCollectedFrom = housesCollectedFrom + 1
                        end
                    end
                end

                wait(100)
                local earnings, hasEarnings = formatEarnings(
                    data.withdraw.btc, data.withdraw.asc,
                    not data.isRodina, "{ffffff} и "
                )
                if hasEarnings then
                    utils.addChat("Всего собрано: " .. earnings .. "{ffffff}.")
                    logsTool.add('collect',
                        { btc = data.withdraw.btc, asc = data.withdraw.asc, houses = housesCollectedFrom })
                end
            end)
        end
    elseif taskType == 'massSwitchCards' then
        task.run = function(self, enable)
            local houses = {}
            for _, h in ipairs(data.dialogData.flashminer) do table.insert(houses, h) end
            if not houses or #houses == 0 then
                utils.addChat("{F78181}Список домов не найден. Повторите попытку.")
                return false
            end

            local housesToProcess = {}
            for _, house in ipairs(houses) do
                if houseFilter.shouldProcess(house) then
                    table.insert(housesToProcess, house)
                end
            end

            createProtectedTask(function(sendResponse, enable_arg)
                local actualHousesToProcess = {}
                for _, house in ipairs(housesToProcess) do
                    local status = data.houseStatuses[house.house_number]
                    local needsProcessing = true

                    if status and status.lastCheck > 0 and status.cardLevels then
                        local total, working = 0, 0
                        for _, lvl in pairs(status.cardLevels) do
                            total   = total + lvl.total
                            working = working + lvl.working
                        end
                        if enable_arg and total > 0 and total == working then
                            needsProcessing = false
                        elseif not enable_arg and working == 0 then
                            needsProcessing = false
                        end
                    end

                    if needsProcessing then
                        table.insert(actualHousesToProcess, house)
                    end
                end

                local snapshotBefore = {}
                for _, house in ipairs(actualHousesToProcess) do
                    local status = data.houseStatuses[house.house_number]
                    if status and status.cardLevels then
                        local total, working = 0, 0
                        for _, lvl in pairs(status.cardLevels) do
                            total   = total + lvl.total
                            working = working + lvl.working
                        end
                        snapshotBefore[house.house_number] = { total = total, working = working }
                    end
                end

                progressTracker.setTotal(#actualHousesToProcess)

                for i, house in ipairs(actualHousesToProcess) do
                    if data.stopAction then break end
                    visitHouseCards(sendResponse, house, function(cards)
                        local cardsToSwitch = 0
                        for _, card in ipairs(cards) do
                            if (enable_arg and not card.working) or (not enable_arg and card.working) then
                                cardsToSwitch = cardsToSwitch + 1
                            end
                        end
                        progressTracker.setHouseTotal(cardsToSwitch)
                        for attempt = 1, 2 do
                            local switchedCount = switchCardsInHouse(sendResponse, enable_arg)
                            if switchedCount == 0 then break end
                            if attempt == 1 then wait(500) end
                        end
                    end)
                end
                wait(300)

                local totalSwitched = 0
                local housesActuallySwitched = 0
                for _, house in ipairs(actualHousesToProcess) do
                    local before = snapshotBefore[house.house_number]
                    local status = data.houseStatuses[house.house_number]
                    if before and status and status.cardLevels then
                        local total, working = 0, 0
                        for _, lvl in pairs(status.cardLevels) do
                            total   = total + lvl.total
                            working = working + lvl.working
                        end
                        local diff = enable_arg
                            and (working - before.working)
                            or (before.working - working)
                        if diff > 0 then
                            totalSwitched          = totalSwitched + diff
                            housesActuallySwitched = housesActuallySwitched + 1
                        end
                    end
                end

                if totalSwitched > 0 then
                    logsTool.add('switch', {
                        enabled = enable,
                        count   = totalSwitched,
                        houses  = housesActuallySwitched
                    })
                end
            end, enable)
        end
    elseif taskType == 'updateStatuses' then
        task.run = function(self)
            local time = os.clock()
            local houses = {}
            for _, h in ipairs(data.dialogData.flashminer) do table.insert(houses, h) end
            if not houses or #houses == 0 then return false end
            local housesToProcess = {}
            for _, house in ipairs(houses) do
                if houseFilter.shouldProcess(house) then
                    table.insert(housesToProcess, house)
                end
            end

            createProtectedTask(function(sendResponse)
                progressTracker.setTotal(#housesToProcess)

                for i, house in ipairs(housesToProcess) do
                    if data.stopAction then break end
                    data.dialogData.videocards = {}

                    dialogActions.selectHouse(sendResponse, house.index - 1)
                    smart_wait(300, time)
                    dialogActions.closeDialog(sendResponse)

                    progressTracker.increment()
                end

                if not data.initialScanCompleted then
                    data.initialScanCompleted = true
                end
            end)
        end
    elseif taskType == 'scanBasements' then
        task.run = function(self, housesToScan)
            local houses = housesToScan or {}
            if not housesToScan then
                for _, h in ipairs(data.dialogData.flashminer) do
                    table.insert(houses, h)
                end
            end

            if not houses or #houses == 0 then return false end

            createProtectedTask(function(sendResponse)
                progressTracker.setTotal(#houses)

                if not housesToScan then
                    cfg.housesWithoutBasement = {}
                    cfg.basementScanned = {}
                end

                for i, house in ipairs(houses) do
                    if data.stopAction then break end
                    data.houseHasNoBasement = false

                    dialogActions.selectHouse(sendResponse, house.index - 1)

                    local start_time = os.clock()
                    while os.clock() - start_time < 0.5 do
                        wait(100)
                        if data.houseHasNoBasement then break end
                    end

                    if data.houseHasNoBasement then
                        cfg.housesWithoutBasement[tostring(house.house_number)] = true
                        sampSendChat("/flashminer")
                        wait(150)
                    else
                        dialogActions.closeDialog(sendResponse)
                    end
                    cfg.basementScanned[tostring(house.house_number)] = true
                    progressTracker.increment()
                end
                save()
            end)
        end
    elseif taskType == 'fixAllProblems' then
        task.run = function(self)
            local houses = {}
            for _, h in ipairs(data.dialogData.flashminer) do table.insert(houses, h) end
            if not houses or #houses == 0 then
                utils.addChat("{F78181}Список домов не найден. Сначала обновите его.")
                return false
            end
            local housesToProcess = {}
            for _, house in ipairs(houses) do
                if houseFilter.shouldProcess(house) then
                    table.insert(housesToProcess, house)
                end
            end

            createProtectedTask(function(sendResponse)
                if cfg.useSimpleTopUp then
                    -- progress over houses that need top-up, not all houses
                    data.progressCurrent = 0
                    data.progressTotal = 0
                else
                    data.progressTotal = #housesToProcess
                end

                local summary = {
                    btc_collected = 0,
                    asc_collected = 0,
                    cards_switched_on = 0,
                    money_on_balance = 0,
                    taxes_paid = 0,
                    houses_topped_up = 0,
                    houses_to_top_up = {},
                    houses_with_high_tax = {}
                }
                for _, house in ipairs(housesToProcess) do
                    if house.balance < cfg.targetHouseBalance and (cfg.targetHouseBalance - house.balance) > 10000 then
                        table.insert(summary.houses_to_top_up, house)
                    end
                end

                
                if cfg.useSimpleTopUp then
                    progressTracker.setTotal(math.max(#summary.houses_to_top_up, 1))
                end
if not cfg.useSimpleTopUp then
                    for i, house in ipairs(housesToProcess) do
                        if data.stopAction then break end
                        data.progressHouseCurrent = 0
                        data.progressHouseTotal = 0
                        data.dialogData.videocards = {}
                        data.houseHasNoBasement = false
                        sendResponse(dialogIdTable.houseDialogId, 1, house.index - 1, "")

                        local t = 0
                        while #data.dialogData.videocards == 0 and t < 3000 do
                            wait(50); t = t + 50
                            if data.houseHasNoBasement then break end
                        end
                        if #data.dialogData.videocards == 0 and not data.houseHasNoBasement then
                            wait(200)
                            sendResponse(dialogIdTable.houseDialogId, 1, house.index - 1, "")
                            t = 0
                            while #data.dialogData.videocards == 0 and t < 2000 do
                                wait(50); t = t + 50
                                if data.houseHasNoBasement then break end
                            end
                        end

                        if data.houseHasNoBasement then
                            utils.addChat(string.format("{F78181}Дом №%d: нет доступа, пропускаем", house.house_number))
                            sampSendChat("/flashminer")
                            wait(300)
                            data.progressCurrent = data.progressCurrent + 1
                        else
                            if #data.dialogData.videocards == 0 then wait(300) end

                            local cardsToCollect = {}
                            local cardsToSwitchOn = {}
                            for _, cardData in ipairs(data.dialogData.videocards) do
                                if cfg.fixCollectEnabled and (cardData.btc >= 1 or cardData.asc >= 1) then
                                    table.insert(cardsToCollect, cardData)
                                end
                                if cfg.fixSwitchEnabled and not cardData.working and cardData.coolant >= cfg.useCoolantPercent then
                                    table.insert(cardsToSwitchOn, cardData)
                                end
                            end
                            data.progressHouseTotal = #cardsToCollect + #cardsToSwitchOn
                            if #cardsToCollect > 0 or #cardsToSwitchOn > 0 then
                                if cfg.fixCollectEnabled then
                                    local maxAttempts = 2
                                    for attempt = 1, maxAttempts do
                                        local btcCollected, ascCollected = collectCardsFromHouse(sendResponse)
                                        summary.btc_collected = summary.btc_collected + btcCollected
                                        summary.asc_collected = summary.asc_collected + ascCollected
                                        if btcCollected == 0 and ascCollected == 0 then break end
                                        if attempt < maxAttempts then wait(150) end
                                    end
                                end
                                if cfg.fixSwitchEnabled then
                                    local switchedCount = switchCardsInHouse(sendResponse, true)
                                    summary.cards_switched_on = summary.cards_switched_on + switchedCount
                                    if switchedCount > 0 then wait(300) end
                                end
                            end

                            sendResponse(dialogIdTable.houseFlashMinerDialogId, 0, 0, "")
                            data.progressCurrent = data.progressCurrent + 1
                        end
                    end

                    sampCloseCurrentDialogWithButton(0)
                end
                if #summary.houses_to_top_up > 0 and (cfg.fixTopUpEnabled or cfg.useSimpleTopUp) then
                    sampSendChat("/phone")
                    sendcef('launchedApp|24')
                    sampSendChat("/phone")
                    sendResponse(dialogIdTable.phoneBankMenuId, 1, 10, "")
                    wait(500)


                    for i, house in ipairs(summary.houses_to_top_up) do
                        if data.stopAction or not data.working then break end
                        data.currentCollectHouse = u8(string.format("Дом №%d (%d/%d)",
                            house.house_number, i, #summary.houses_to_top_up))

                        local total_amount_needed = math.min(cfg.targetHouseBalance, 60000000 - 1) - house.balance

                        if total_amount_needed < 10000 then
                            goto continue_topup
                        end

                        local remaining_to_add = total_amount_needed
                        local house_was_topped = false

                        while remaining_to_add >= 10000 do
                            if data.stopAction or not data.working then break end

                            local amount_this_transaction = math.min(remaining_to_add, 10000000)
                            local leftover = remaining_to_add - amount_this_transaction
                            if leftover > 0 and leftover < 10000 then
                                amount_this_transaction = amount_this_transaction - 10000
                            end

                            if amount_this_transaction < 10000 then
                                break
                            end

                            data.topUpLastFailed = false
                            sendResponse(dialogIdTable.houseListBankId, 1, house.index - 1, "")
                            sendResponse(dialogIdTable.topUpBalanceDialogId, 1, 0, tostring(amount_this_transaction))

                            local confirmWait = 0
                            while confirmWait < 600 do
                                wait(50)
                                confirmWait = confirmWait + 50
                                if data.topUpLastFailed or data.stopAction then break end
                            end
                            if data.topUpLastFailed or data.stopAction then
                                break
                            end

                            summary.money_on_balance = summary.money_on_balance + amount_this_transaction
                            remaining_to_add = remaining_to_add - amount_this_transaction
                            house_was_topped = true
                        end

                        if house_was_topped then
                            summary.houses_topped_up = summary.houses_topped_up + 1
                        end

                        
                        if cfg.useSimpleTopUp then
                            progressTracker.increment()
                        end
::continue_topup::
                    end

                    if sampIsDialogActive() then
                        local activeId = sampGetCurrentDialogId()
                        sendResponse(activeId, 0, 0, "")
                    end
                    wait(100)
                end
                --sampSendChat("/flashminer")
                wait(300)
                local report = {}
                local earnings, hasEarnings = formatEarnings(summary.btc_collected, summary.asc_collected,
                    not data.isRodina, " и ")
                if hasEarnings then
                    table.insert(report, "Собрано: " .. earnings)
                end
                if summary.cards_switched_on > 0 then
                    table.insert(report, string.format("Включено видеокарт: {99ff99}%d", summary.cards_switched_on))
                end
                if summary.money_on_balance > 0 then
                    table.insert(report,
                        string.format("Пополнено ферм на: {FFD700}$%s", utils.formatNumber(summary.money_on_balance)))
                end
                if summary.taxes_paid > 0 then
                    table.insert(report,
                        string.format("Оплачено налогов на (приблизительно): {F78181}$%s",
                            utils.formatNumber(summary.taxes_paid)))
                end

                if cfg.useSimpleTopUp then
                    if summary.money_on_balance > 0 then
                        logsTool.add('topup', {
                            topup  = summary.money_on_balance,
                            houses = summary.houses_topped_up
                        })
                    end
                else
                    logsTool.add('fix', {
                        btc    = summary.btc_collected,
                        asc    = summary.asc_collected,
                        topup  = summary.money_on_balance,
                        cards  = summary.cards_switched_on,
                        houses = #housesToProcess
                    })
                end
            end)
        end
    elseif taskType == 'autoPayTaxes' then
        task.run = function(self)
            createProtectedTask(function(sendResponse)
                taxTool.resetCapturedAmount()

                sampSendChat("/phone")
                sendcef('launchedApp|24')
                sampSendChat("/phone")
                wait(500)

                sendResponse(dialogIdTable.phoneBankMenuId, 1, 4, "")
                wait(300)

                sendResponse(dialogIdTable.payAllTaxesDialogId, 1, 0, "")
                wait(500)

                if sampIsDialogActive() then
                    local activeId = sampGetCurrentDialogId()
                    sendResponse(activeId, 0, 0, "")
                end

                cfg.lastTaxPayTime = os.time()
                save()

                local paid = taxTool.getCapturedAmount()
                if paid > 0 then
                    utils.addChat(string.format(
                        "{BEF781}Налоги оплачены: {FFD700}$%s",
                        utils.formatNumber(paid)))
                    logsTool.add('tax', { amount = paid })
                end
            end)
        end
    elseif taskType == 'autoTopUp' then
        task.run = function(self, housesToTopUp)
            if not housesToTopUp or #housesToTopUp == 0 then
                housesToTopUp = {}
                for _, house in ipairs(data.dialogData.flashminer) do
                    if houseFilter.shouldProcess(house) then
                        local threshold = cfg.autoTopUpByThreshold
                            and cfg.autoTopUpThreshold
                            or cfg.targetHouseBalance
                        if house.balance < threshold and (threshold - house.balance) > 10000 then
                            table.insert(housesToTopUp, house)
                        end
                    end
                end
            end

            if #housesToTopUp == 0 then
                utils.addChat("{BEF781}Пополнение не требуется - балансы в норме.")
                utils.debugChat("[CHEAT] top-up not needed.")
                return false
            end

            createProtectedTask(function(sendResponse)
                data.topUpLastFailed = false
                local totalTopUp = 0
                local housesCount = 0

                progressTracker.setTotal(#housesToTopUp)

                -- Открываем телефон -> банк -> пополнение
                sampSendChat("/phone")
                sendcef('launchedApp|24')
                sampSendChat("/phone")
                wait(500)

                sendResponse(dialogIdTable.phoneBankMenuId, 1, 10, "")
                wait(500)

                for i, house in ipairs(housesToTopUp) do
                    if data.stopAction then break end

                    data.currentCollectHouse = u8(string.format(
                        "Дом №%d (%d/%d)", house.house_number, i, #housesToTopUp))

                    local targetBalance = math.min(
                        cfg.autoTopUpByThreshold and cfg.targetHouseBalance or cfg.targetHouseBalance,
                        60000000 - 1)
                    local amountNeeded = targetBalance - house.balance

                    if amountNeeded < 10000 then
                        progressTracker.increment()
                        goto continue_topup
                    end

                    local remaining = amountNeeded
                    local houseWasTopped = false

                    while remaining >= 10000 do
                        if data.stopAction then break end

                        local amount = math.min(remaining, 10000000)
                        local leftover = remaining - amount
                        if leftover > 0 and leftover < 10000 then
                            amount = amount - 10000
                        end
                        if amount < 10000 then break end

                        data.topUpLastFailed = false
                        sendResponse(dialogIdTable.houseListBankId, 1, house.index - 1, "")
                        sendResponse(dialogIdTable.topUpBalanceDialogId, 1, 0, tostring(amount))

                        -- Count only after server had time to accept/reject
                        local confirmWait = 0
                        while confirmWait < 600 do
                            wait(50)
                            confirmWait = confirmWait + 50
                            if data.topUpLastFailed or data.stopAction then break end
                        end
                        if data.topUpLastFailed or data.stopAction then
                            break
                        end

                        totalTopUp = totalTopUp + amount
                        remaining = remaining - amount
                        houseWasTopped = true
                    end

                    if houseWasTopped then housesCount = housesCount + 1 end
                    progressTracker.increment()

                    ::continue_topup::
                end

                if sampIsDialogActive() then
                    local activeId = sampGetCurrentDialogId()
                    sendResponse(activeId, 0, 0, "")
                end
                wait(100)

                cfg.lastAutoTopUpTime = os.time()
                save()

                data.currentCollectHouse = ""

                if totalTopUp > 0 then
                    utils.addChat(string.format(
                        "{BEF781}Баланс пополнен: {FFD700}$%s {808080}(%d домов)",
                        utils.formatNumber(totalTopUp), housesCount))
                    logsTool.add('topup', { topup = totalTopUp, houses = housesCount })
                end
            end)
        end
    end
    return task
end

function withSilentFlashminer(callback)
    if data.working then return false end
    if not flashminerTool.hasIt() then return false end
    local restoreHouseControl = data.showHouseControlWindow[0] == true
    taskState.setSilent(true)
    if not flashminerTool.requestList(5000) then
        taskState.setSilent(false)
        return false
    end

    local result = callback()

    wait(300)
    -- FIX: СЂР°РЅСЊС€Рµ Р·РґРµСЃСЊ Р·Р°РєСЂС‹РІР°Р»СЃСЏ Р›Р®Р‘РћР™ РѕС‚РєСЂС‹С‚С‹Р№ РґРёР°Р»РѕРі Р±РµР· СЂР°Р·Р±РѕСЂР°, РёР·-Р·Р°
    -- С‡РµРіРѕ С„РѕРЅРѕРІРѕРµ С‚РёС…РѕРµ РѕР±РЅРѕРІР»РµРЅРёРµ (РєР°Р¶РґС‹Рµ 5 РјРёРЅ / РїРѕ С‚Р°Р№РјРµСЂСѓ РЅР°Р»РѕРіРѕРІ Рё
    -- РїРѕРїРѕР»РЅРµРЅРёСЏ) РјРѕРіР»Рѕ Р·Р°РєСЂС‹С‚СЊ РґРёР°Р»РѕРі, РєРѕС‚РѕСЂС‹Р№ РёРіСЂРѕРє РѕС‚РєСЂС‹Р» СЃР°Рј РІСЂСѓС‡РЅСѓСЋ
    -- (РЅР°РїСЂРёРјРµСЂ, "РњРµР¶РґСѓРЅР°СЂРѕРґРЅС‹Рµ СЂРµР№СЃС‹", С‚РµР»РµС„РѕРЅ Рё С‚.Рї.). РўРµРїРµСЂСЊ Р·Р°РєСЂС‹РІР°РµРј
    -- РїСЂРёРЅСѓРґРёС‚РµР»СЊРЅРѕ С‚РѕР»СЊРєРѕ РґРёР°Р»РѕРі СЃР°РјРѕРіРѕ СЃРєСЂРёРїС‚Р°; С‡СѓР¶РѕР№ РґРёР°Р»РѕРі РЅРµ С‚СЂРѕРіР°РµРј.
    if sampIsDialogActive() and isOwnScriptDialogId(sampGetCurrentDialogId()) then
        sampCloseCurrentDialogWithButton(0)
        wait(300)
    end
    fixI()
    wait(300)
    data.silentWindowOpen          = false
    data.showHouseControlWindow[0] = restoreHouseControl
    return result ~= false
end

function runSilentTask(taskName, arg)
    if data.working then return false end
    return withSilentFlashminer(function()
        local task = buildTaskTable(taskName)
        task:run(arg)
        wait(500)
        while data.working do wait(200) end
    end)
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    imgui.GetIO().MouseDrawCursor = true
    imgui.GetStyle().MouseCursorScale = 1
    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    local iconRanges = imgui.new.ImWchar[3](fa.min_range, fa.max_range, 0)
    imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(fa.get_font_data_base85('solid'), 14, config, iconRanges)
end)

function applyStyle()
    imgui.SwitchContext()
    local style                       = imgui.GetStyle()
    local colors                      = style.Colors
    local Col                         = imgui.Col
    local ImVec4                      = imgui.ImVec4
    local ImVec2                      = imgui.ImVec2

    -- VC MODE: Override accent color with bright pink in Vice City mode
    local originalAccentColor
    if data.isViceCity then
        originalAccentColor = { cfg.accentColor[1], cfg.accentColor[2], cfg.accentColor[3] }
        cfg.accentColor = { 1.0, 0.05, 0.65 }  -- Bright pink/magenta for VC mode
        accentColorBuf[0] = cfg.accentColor[1]
        accentColorBuf[1] = cfg.accentColor[2]
        accentColorBuf[2] = cfg.accentColor[3]
    end

    style.WindowPadding               = ImVec2(12, 12)
    style.FramePadding                = ImVec2(8, 6)
    style.ItemSpacing                 = ImVec2(8, 8)
    style.ItemInnerSpacing            = ImVec2(6, 6)
    style.TouchExtraPadding           = ImVec2(0, 0)
    style.IndentSpacing               = 20.0
    style.ScrollbarSize               = 10.0
    style.GrabMinSize                 = 5.0

    style.WindowBorderSize            = 1
    style.ChildBorderSize             = 1
    style.PopupBorderSize             = 1
    style.FrameBorderSize             = 0
    style.TabBorderSize               = 1
    style.WindowRounding              = 6.0
    style.ChildRounding               = 6.0
    style.FrameRounding               = 4.0
    style.PopupRounding               = 5.0
    style.ScrollbarRounding           = 9.0
    style.GrabRounding                = 3.0
    style.TabRounding                 = 5.0

    style.WindowTitleAlign            = ImVec2(0.5, 0.5)
    style.ButtonTextAlign             = ImVec2(0.5, 0.5)
    style.SelectableTextAlign         = ImVec2(0.5, 0.5)

    colors[Col.Text]                  = ImVec4(0.95, 0.96, 0.98, 1.00)
    colors[Col.TextDisabled]          = ImVec4(0.50, 0.50, 0.50, 1.00)
    colors[Col.WindowBg]              = accentTint(0.06, 0.07, 0.10, 0.22, 1.00)
    colors[Col.ChildBg]               = accentTint(0.09, 0.10, 0.14, 0.22, 1.00)
    colors[Col.PopupBg]               = ImVec4(0.08, 0.08, 0.08, 0.94)
    colors[Col.Border]                = ImVec4(0.20, 0.22, 0.27, 0.50)
    colors[Col.BorderShadow]          = ImVec4(0, 0, 0, 0)
    colors[Col.FrameBg]               = ImVec4(0.13, 0.14, 0.19, 1.00)
    colors[Col.FrameBgHovered]        = ImVec4(0.18, 0.19, 0.25, 1.00)
    colors[Col.FrameBgActive]         = ImVec4(0.22, 0.23, 0.29, 1.00)
    colors[Col.TitleBg]               = accentTint(0.06, 0.07, 0.10, 0.22, 1.00)
    colors[Col.TitleBgActive]         = accentTint(0.06, 0.07, 0.10, 0.22, 1.00)
    colors[Col.TitleBgCollapsed]      = accentTint(0.06, 0.07, 0.10, 0.22, 1.00)
    colors[Col.MenuBarBg]             = accentTint(0.06, 0.07, 0.10, 0.22, 1.00)
    colors[Col.ScrollbarBg]           = accentTint(0.06, 0.07, 0.10, 0.22, 1.00)
    colors[Col.ScrollbarGrab]         = ImVec4(0.16, 0.17, 0.21, 1.00)
    colors[Col.ScrollbarGrabHovered]  = ImVec4(0.20, 0.21, 0.26, 1.00)
    colors[Col.ScrollbarGrabActive]   = ImVec4(0.24, 0.25, 0.30, 1.00)
    colors[Col.CheckMark]             = ImVec4(1.00, 1.00, 1.00, 1.00)
    colors[Col.SliderGrab]            = ImVec4(1.00, 1.00, 1.00, 0.30)
    colors[Col.SliderGrabActive]      = ImVec4(1.00, 1.00, 1.00, 0.30)
    colors[Col.Button]                = ImVec4(0.16, 0.17, 0.21, 1.00)
    colors[Col.ButtonHovered]         = ImVec4(0.20, 0.21, 0.26, 1.00)
    colors[Col.ButtonActive]          = ImVec4(0.24, 0.25, 0.30, 1.00)
    colors[Col.Header]                = ImVec4(0.20, 0.22, 0.27, 1.00)
    colors[Col.HeaderHovered]         = ImVec4(0.25, 0.27, 0.32, 1.00)
    colors[Col.HeaderActive]          = ImVec4(0.28, 0.30, 0.35, 1.00)
    colors[Col.Separator]             = ImVec4(0.20, 0.22, 0.27, 0.50)
    colors[Col.SeparatorHovered]      = ImVec4(0.25, 0.27, 0.32, 1.00)
    colors[Col.SeparatorActive]       = ImVec4(0.28, 0.30, 0.35, 1.00)
    colors[Col.ResizeGrip]            = ImVec4(1.00, 1.00, 1.00, 0.25)
    colors[Col.ResizeGripHovered]     = ImVec4(1.00, 1.00, 1.00, 0.67)
    colors[Col.ResizeGripActive]      = ImVec4(1.00, 1.00, 1.00, 0.95)
    colors[Col.Tab]                   = accentTint(0.16, 0.17, 0.21, 0.20, 1.00)
    colors[Col.TabHovered]            = accentShade(1.35, 1.00)
    colors[Col.TabActive]             = accentShade(1.0, 1.00)
    colors[Col.TabUnfocused]          = accentTint(0.06, 0.07, 0.10, 0.20, 1.00)
    colors[Col.TabUnfocusedActive]    = accentTint(0.16, 0.17, 0.21, 0.20, 1.00)
    colors[Col.PlotLines]             = ImVec4(0.61, 0.61, 0.61, 1.00)
    colors[Col.PlotLinesHovered]      = ImVec4(1.00, 0.43, 0.35, 1.00)
    colors[Col.PlotHistogram]         = ImVec4(1.00, 0.78, 0.00, 1.00)
    colors[Col.PlotHistogramHovered]  = ImVec4(1.00, 0.60, 0.00, 1.00)
    colors[Col.TextSelectedBg]        = ImVec4(1.00, 0.00, 0.00, 0.35)
    colors[Col.DragDropTarget]        = ImVec4(1.00, 1.00, 0.00, 0.90)
    colors[Col.NavHighlight]          = ImVec4(0.26, 0.59, 0.98, 1.00)
    colors[Col.NavWindowingHighlight] = ImVec4(1.00, 1.00, 1.00, 0.70)
    colors[Col.NavWindowingDimBg]     = ImVec4(0.80, 0.80, 0.80, 0.20)
    colors[Col.ModalWindowDimBg]      = ImVec4(0.00, 0.00, 0.00, 0.70)

    -- Restore original accent color after applying styles
    if originalAccentColor then
        cfg.accentColor = originalAccentColor
        accentColorBuf[0] = cfg.accentColor[1]
        accentColorBuf[1] = cfg.accentColor[2]
        accentColorBuf[2] = cfg.accentColor[3]
    end
end

function applyCustomStyle()
    imgui.SwitchContext()
    local style                       = imgui.GetStyle()
    local colors                      = style.Colors
    local Col                         = imgui.Col
    local ImVec4                      = imgui.ImVec4
    local ImVec2                      = imgui.ImVec2

    -- VC MODE: Override accent color with bright pink in Vice City mode
    local originalAccentColor
    if data.isViceCity then
        originalAccentColor = { cfg.accentColor[1], cfg.accentColor[2], cfg.accentColor[3] }
        cfg.accentColor = { 1.0, 0.05, 0.65 }  -- Bright pink/magenta for VC mode
        accentColorBuf[0] = cfg.accentColor[1]
        accentColorBuf[1] = cfg.accentColor[2]
        accentColorBuf[2] = cfg.accentColor[3]
    end

    colors[Col.Text]                  = ImVec4(1, 1, 1, 1)
    colors[Col.TextDisabled]          = ImVec4(0.5, 0.5, 0.5, 1)
    -- FIX: СЂР°РЅСЊС€Рµ Р·РґРµСЃСЊ РІСЃРµ С†РІРµС‚Р° Р±С‹Р»Рё Р¶С‘СЃС‚РєРѕ Р·Р°С€РёС‚С‹ Рё РЅРµ СѓС‡РёС‚С‹РІР°Р»Рё
    -- cfg.accentColor, РёР·-Р·Р° С‡РµРіРѕ РІС‹Р±СЂР°РЅРЅР°СЏ РІ РЅР°СЃС‚СЂРѕР№РєР°С… РїР°Р»РёС‚СЂР° РЅРёРєР°Рє
    -- РЅРµ РІР»РёСЏР»Р° РЅР° СЌС‚Рѕ РѕРєРЅРѕ. РўРµРїРµСЂСЊ С„РѕРЅ/С€Р°РїРєР°/СЃРєСЂРѕР»Р»Р±Р°СЂ/РІРєР»Р°РґРєРё Рё РєРЅРѕРїРєРё
    -- Р±РµСЂСѓС‚ Р°РєС†РµРЅС‚РЅС‹Р№ С†РІРµС‚ С‚Р°Рє Р¶Рµ, РєР°Рє СЌС‚Рѕ СѓР¶Рµ СЃРґРµР»Р°РЅРѕ РІ applyStyle().
    colors[Col.WindowBg]              = accentTint(0.07, 0.07, 0.07, 0.22, 1)
    colors[Col.ChildBg]               = accentTint(0.07, 0.07, 0.07, 0.22, 1)
    colors[Col.PopupBg]               = ImVec4(0.07, 0.07, 0.07, 1)
    colors[Col.Border]                = ImVec4(0.25, 0.25, 0.26, 0.54)
    colors[Col.BorderShadow]          = ImVec4(0, 0, 0, 0)
    colors[Col.FrameBg]               = ImVec4(0.12, 0.12, 0.12, 1)
    colors[Col.FrameBgHovered]        = ImVec4(0.25, 0.25, 0.26, 1)
    colors[Col.FrameBgActive]         = ImVec4(0.25, 0.25, 0.26, 1)
    colors[Col.TitleBg]               = accentTint(0.12, 0.12, 0.12, 0.22, 1)
    colors[Col.TitleBgActive]         = accentTint(0.12, 0.12, 0.12, 0.22, 1)
    colors[Col.TitleBgCollapsed]      = accentTint(0.12, 0.12, 0.12, 0.22, 1)
    colors[Col.MenuBarBg]             = accentTint(0.12, 0.12, 0.12, 0.22, 1)
    colors[Col.ScrollbarBg]           = accentTint(0.12, 0.12, 0.12, 0.22, 1)
    colors[Col.ScrollbarGrab]         = ImVec4(0, 0, 0, 1)
    colors[Col.ScrollbarGrabHovered]  = ImVec4(0.41, 0.41, 0.41, 1)
    colors[Col.ScrollbarGrabActive]   = ImVec4(0.51, 0.51, 0.51, 1)
    colors[Col.CheckMark]             = ImVec4(1, 1, 1, 1)
    colors[Col.SliderGrab]            = ImVec4(1, 1, 1, 0.3)
    colors[Col.SliderGrabActive]      = ImVec4(1, 1, 1, 0.3)
    colors[Col.Button]                = accentTint(0.12, 0.12, 0.12, 0.30, 1)
    colors[Col.ButtonHovered]         = accentShade(1.35, 1)
    colors[Col.ButtonActive]          = accentShade(1.0, 1)
    colors[Col.Header]                = ImVec4(0.12, 0.12, 0.12, 1)
    colors[Col.HeaderHovered]         = ImVec4(0.2, 0.2, 0.2, 1)
    colors[Col.HeaderActive]          = ImVec4(0.47, 0.47, 0.47, 1)
    colors[Col.Separator]             = ImVec4(0.12, 0.12, 0.12, 1)
    colors[Col.SeparatorHovered]      = ImVec4(0.12, 0.12, 0.12, 1)
    colors[Col.SeparatorActive]       = ImVec4(0.12, 0.12, 0.12, 1)
    colors[Col.ResizeGrip]            = ImVec4(1, 1, 1, 0.25)
    colors[Col.ResizeGripHovered]     = ImVec4(1, 1, 1, 0.67)
    colors[Col.ResizeGripActive]      = ImVec4(1, 1, 1, 0.95)
    colors[Col.Tab]                   = accentTint(0.12, 0.12, 0.12, 0.20, 1)
    colors[Col.TabHovered]            = accentShade(1.35, 1)
    colors[Col.TabActive]             = accentShade(1.0, 1)
    colors[Col.TabUnfocused]          = accentTint(0.07, 0.1, 0.15, 0.20, 0.97)
    colors[Col.TabUnfocusedActive]    = accentTint(0.12, 0.12, 0.12, 0.20, 1)
    colors[Col.PlotLines]             = ImVec4(0.61, 0.61, 0.61, 1)
    colors[Col.PlotLinesHovered]      = ImVec4(1, 0.43, 0.35, 1)
    colors[Col.PlotHistogram]         = ImVec4(0.9, 0.7, 0, 1)
    colors[Col.PlotHistogramHovered]  = ImVec4(1, 0.6, 0, 1)
    colors[Col.TextSelectedBg]        = ImVec4(1, 0, 0, 0.35)
    colors[Col.DragDropTarget]        = ImVec4(1, 1, 0, 0.9)
    colors[Col.NavHighlight]          = ImVec4(0.26, 0.59, 0.98, 1)
    colors[Col.NavWindowingHighlight] = ImVec4(1, 1, 1, 0.7)
    colors[Col.NavWindowingDimBg]     = ImVec4(0.8, 0.8, 0.8, 0.2)
    colors[Col.ModalWindowDimBg]      = ImVec4(0, 0, 0, 0.7)

    style.WindowPadding               = ImVec2(5, 5)
    style.FramePadding                = ImVec2(5, 5)
    style.ItemSpacing                 = ImVec2(5, 5)
    style.ItemInnerSpacing            = ImVec2(2, 2)
    style.TouchExtraPadding           = ImVec2(0, 0)
    style.IndentSpacing               = 0
    style.ScrollbarSize               = 10
    style.GrabMinSize                 = 10
    style.WindowBorderSize            = 1
    style.ChildBorderSize             = 1
    style.PopupBorderSize             = 1
    style.FrameBorderSize             = 0
    style.TabBorderSize               = 1
    style.WindowRounding              = 5
    style.ChildRounding               = 5
    style.FrameRounding               = 5
    style.PopupRounding               = 5
    style.ScrollbarRounding           = 5
    style.GrabRounding                = 5
    style.TabRounding                 = 5
    style.WindowTitleAlign            = ImVec2(0.5, 0.5)
    style.ButtonTextAlign             = ImVec2(0.5, 0.5)
    style.SelectableTextAlign         = ImVec2(0.5, 0.5)

    -- Restore original accent color after applying styles
    if originalAccentColor then
        cfg.accentColor = originalAccentColor
        accentColorBuf[0] = cfg.accentColor[1]
        accentColorBuf[1] = cfg.accentColor[2]
        accentColorBuf[2] = cfg.accentColor[3]
    end
end

local _nAlpha, _nAlphaVel, _nLastT, _nSaveT = 0.0, 0.0, 0.0, 0.0

-- окно подсказки
imgui.OnFrame(
    function()
        return data.notifyWindow.show[0] or _nAlpha > 0.005
    end,
    function(self)
        if not cfg.notifyAutoCollectEnabled and
            (data.notifyWindow.mode == 'countdown' or data.notifyWindow.mode == 'collecting') then
            data.notifyWindow.show[0] = false
        end
        if data.notifyWindow.autoHideAt > 0 and os.time() >= data.notifyWindow.autoHideAt then
            data.notifyWindow.show[0] = false
            data.notifyWindow.autoHideAt = 0
            data.notifyWindow.isPreview = false
        end

        local now           = os.clock()
        local dt            = _nLastT > 0 and math.min(now - _nLastT, 0.05) or 0.016
        _nLastT             = now
        local tgt           = data.notifyWindow.show[0] and 1.0 or 0.0
        _nAlpha, _nAlphaVel = smoothDamp(_nAlpha, tgt, _nAlphaVel, dt, 0.22)
        if _nAlpha < 0.005 then return end

        applyStyle()
        local sw, sh       = getScreenResolution()

        local isPreview    = data.notifyWindow.isPreview
        local isActionMode = data.notifyWindow.mode == 'countdown'
            or data.notifyWindow.mode == 'collecting'
        local isChatOpen   = sampIsChatInputActive()

        self.HideCursor    = not (isPreview or isChatOpen)

        if isPreview then
            imgui.SetNextWindowPos(
                imgui.ImVec2(cfg.notifyWindowPosX * sw, cfg.notifyWindowPosY * sh),
                imgui.Cond.Appearing
            )
        else
            imgui.SetNextWindowPos(
                imgui.ImVec2(cfg.notifyWindowPosX * sw, cfg.notifyWindowPosY * sh),
                imgui.Cond.Always
            )
        end

        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.06, 0.07, 0.10, 0.96 * _nAlpha))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.22, 0.24, 0.30, 0.90 * _nAlpha))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.95, 0.96, 0.98, _nAlpha))
        imgui.PushStyleColor(imgui.Col.Separator, imgui.ImVec4(0.20, 0.22, 0.27, 0.50 * _nAlpha))
        imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.13, 0.14, 0.19, _nAlpha))

        local flags = imgui.WindowFlags.NoCollapse
            + imgui.WindowFlags.NoTitleBar
            + imgui.WindowFlags.NoScrollbar
            + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.AlwaysAutoResize
            + 4096
            + (isPreview and 0 or 512)
            + (isPreview and 0 or imgui.WindowFlags.NoMove)

        if imgui.Begin("##mntNotify", data.notifyWindow.show, flags) then
            if isPreview then
                local wp = imgui.GetWindowPos()
                local nx, ny = wp.x / sw, wp.y / sh
                if math.abs(nx - cfg.notifyWindowPosX) > 0.003 or
                    math.abs(ny - cfg.notifyWindowPosY) > 0.003 then
                    cfg.notifyWindowPosX, cfg.notifyWindowPosY = nx, ny
                    local t = os.clock()
                    if t - _nSaveT > 1.5 then
                        _nSaveT = t; save()
                    end
                end
            end

            if isActionMode and isChatOpen then
                local wp = imgui.GetWindowPos()
                local ws = imgui.GetWindowSize()
                local mx = imgui.GetIO().MousePos.x
                local my = imgui.GetIO().MousePos.y
                local inWindow = mx >= wp.x and mx <= wp.x + ws.x
                    and my >= wp.y and my <= wp.y + ws.y

                if inWindow and imgui.GetIO().MouseClicked[1] then
                    if data.notifyWindow.mode == 'countdown' then
                        collectTool.postponeCollect(2)
                    else
                        collectTool.cancelPending()
                        data.notifyWindow.show[0] = false
                    end
                end
            end

            local mode     = data.notifyWindow.mode
            local secsLeft = (mode == 'countdown')
                and (data.notifyWindow.countdownTarget - os.time()) or 0

            imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.COINS)
            imgui.SameLine(0, 6)
            imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), u8 "Mining Tools")
            imgui.Separator()
            imgui.Spacing()

            if mode == 'reminder' then
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.COINS)
                imgui.SameLine(0, 6)
                local btcAmt = math.floor(data.notifyWindow.btcAmount or 0)
                local ascAmt = math.floor(data.notifyWindow.ascAmount or 0)
                local amtText
                if ascAmt > 0 then
                    amtText = string.format("Накопилось ~%d BTC + %d ASC", btcAmt, ascAmt)
                else
                    amtText = string.format("Накопилось ~%d BTC", btcAmt)
                end
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), u8(amtText))
                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.CIRCLE_EXCLAMATION)
                imgui.SameLine(0, 6)
                imgui.TextColored(imgui.ImVec4(0.6, 0.6, 0.6, _nAlpha), u8 "Рекомендуется собрать криптовалюту.")
            elseif mode == 'countdown' then
                if secsLeft <= 0 then
                    if data.notifyWindow.zeroAt == nil then
                        data.notifyWindow.zeroAt = os.time()
                    elseif os.time() - data.notifyWindow.zeroAt > 5 then
                        data.notifyWindow.show[0] = false
                        data.notifyWindow.zeroAt  = nil
                    end
                else
                    data.notifyWindow.zeroAt = nil
                end
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.CLOCK)
                imgui.SameLine(0, 6)
                local cdText = secsLeft <= 0 and u8 "Собираем..."
                    or u8(string.format("Автосбор через: %s", formatTimeLeft(secsLeft)))
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), cdText)
                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.ROTATE)
                imgui.SameLine(0, 6)
                local subText
                if data.notifyWindow.source == 'smart' then
                    subText = u8(string.format("Цель: %d BTC+ASC", cfg.smartCollectTarget))
                else
                    subText = u8(string.format("%d сборов в день", cfg.collectTimesPerDay))
                end
                imgui.TextColored(imgui.ImVec4(0.6, 0.6, 0.6, _nAlpha), subText)
                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(0.45, 0.45, 0.45, _nAlpha * 0.8),
                    isChatOpen and u8 "ПКМ — отложить на 2 минуты" or u8 "T + ПКМ — отложить на 2 минуты")
            elseif mode == 'collecting' then
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.ROTATE)
                imgui.SameLine(0, 6)
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), u8 "Автосбор выполняется...")
                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.HOUSE)
                imgui.SameLine(0, 6)
                local houseText = (data.currentCollectHouse ~= "" and data.currentCollectHouse) or u8 "Подготовка..."
                imgui.TextColored(imgui.ImVec4(0.6, 0.6, 0.6, _nAlpha), houseText)
                imgui.Spacing()
                local prog = data.progressTotal > 0 and (data.progressCurrent / data.progressTotal) or 0
                imgui.PushStyleColor(imgui.Col.PlotHistogram, imgui.ImVec4(0.3, 0.8, 0.3, _nAlpha))
                imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.15, 0.15, 0.15, _nAlpha))
                imgui.ProgressBar(prog, imgui.ImVec2(-1, 14),
                    u8(string.format("%d / %d домов", data.progressCurrent,
                        data.progressTotal > 0 and data.progressTotal or 0)))
                imgui.PopStyleColor(2)
                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(0.45, 0.45, 0.45, _nAlpha * 0.8),
                    isChatOpen and u8 "ПКМ — отменить сбор" or u8 "T + ПКМ — отменить сбор")
            end

            imgui.Spacing()
            imgui.End()
        end

        imgui.PopStyleColor(5)
    end
)

-- окно помощни
imgui.OnFrame(
    function() return data.showHelpWindow[0] end,
    function(self)
        applyStyle()
        local sw, sh = getScreenResolution()
        imgui.SetNextWindowSizeConstraints(imgui.ImVec2(560, 100), imgui.ImVec2(560, sh - 40))
        imgui.SetNextWindowPos(
            imgui.ImVec2(sw / 2, sh / 2),
            imgui.Cond.FirstUseEver,
            imgui.ImVec2(0.5, 0.5)
        )

        if imgui.Begin("##helpWin", data.showHelpWindow,
                imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar +
                imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + 64) then
            local imStyle     = imgui.GetStyle()
            local winW        = imgui.GetWindowWidth()

            local isSetup     = data.helpWindowMode == 'setup'
            local titleIcon   = isSetup and fa.GEAR or fa.CIRCLE_QUESTION
            local titleStr    = isSetup and "Первоначальная настройка" or "Помощь"

            local totalTitleW = imgui.CalcTextSize(titleIcon).x + 8 + imgui.CalcTextSize(u8(titleStr)).x
            imgui.SetCursorPos(imgui.ImVec2((winW - totalTitleW) / 2, imStyle.ItemSpacing.y + 3))
            imgui.Text(titleIcon)
            imgui.SameLine(0, 8)
            imgui.SetCursorPosY(imStyle.ItemSpacing.y + 3)
            imgui.TextColoredRGB("{FFFFFF}" .. titleStr)

            imgui.SetCursorPos(imgui.ImVec2(winW - 50 - imStyle.ItemSpacing.x, imStyle.ItemSpacing.y))
            if imgui.Button(fa.XMARK .. "##helpClose", imgui.ImVec2(40, 22)) then
                data.showHelpWindow[0] = false
            end
            imgui.Hint("Закрыть справку")
            imgui.Separator()
            imgui.Spacing()

            if isSetup then
                helpTool.renderSetup()
            else
                helpTool.renderReference()
            end

            imgui.Spacing()
            if imgui.Button(u8(isSetup and "Завершить настройку" or "Понятно, закрыть"), imgui.ImVec2(-1, 30)) then
                data.showHelpWindow[0] = false
            end

            imgui.End()
        end
    end
)

-- окно настроек
imgui.OnFrame(
    function() return data.showSettingsWindow[0] end,
    function(self)
        applyStyle()
        local sw, sh = getScreenResolution()
        imgui.SetNextWindowSizeConstraints(imgui.ImVec2(420, 50), imgui.ImVec2(420, sh - 40))
        imgui.SetNextWindowPos(
            imgui.ImVec2(sw / 2 + 520, sh / 2),
            imgui.Cond.FirstUseEver,
            imgui.ImVec2(0.5, 0.5)
        )

        if imgui.Begin("##settingsWin", data.showSettingsWindow,
                imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar +
                imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + 64) then
            local imStyle = imgui.GetStyle()
            local winW = imgui.GetWindowWidth()

            imgui.SetCursorPosY(imStyle.ItemSpacing.y)
            local titleIcon = fa.GEAR
            local titleText = u8 "Настройки"
            local totalTitleW = imgui.CalcTextSize(titleIcon).x + 8 + imgui.CalcTextSize(titleText).x
            imgui.SetCursorPos(imgui.ImVec2((winW - totalTitleW) / 2, imStyle.ItemSpacing.y + 3))
            imgui.Text(titleIcon)
            imgui.SameLine(0, 8)
            imgui.SetCursorPosY(imStyle.ItemSpacing.y + 3)
            imgui.TextColoredRGB("{FFFFFF}Настройки")

            imgui.SetCursorPos(imgui.ImVec2(winW - 50 - imStyle.ItemSpacing.x, imStyle.ItemSpacing.y))
            if imgui.Button(fa.XMARK .. "##settClose", imgui.ImVec2(40, 22)) then
                data.showSettingsWindow[0] = false
            end
            imgui.Hint("Закрыть настройки")
            imgui.Separator()

            local tabs = { u8 "Общее", u8 "Фермы", u8 "Авто", u8 "Прочее", u8 "Помощь" }

            local tabCount = #tabs
            local tabW = (winW - imStyle.WindowPadding.x * 2 - imStyle.ItemSpacing.x * (tabCount - 1)) / tabCount

            if data.settingsTab >= tabCount then
                data.settingsTab = 0
            end

            for i, label in ipairs(tabs) do
                if i > 1 then imgui.SameLine(0, imStyle.ItemSpacing.x) end
                local isActiveTab = data.settingsTab == i - 1
                local isLitTab = isActiveTab or _settingsTabHover[i]
                imgui.PushStyleColor(imgui.Col.Button,
                    isActiveTab
                    and accentRGBA(1)
                    or accentTint(0.09, 0.10, 0.14, 0.25, 1))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, accentShade(1.35, 1))
                imgui.PushStyleColor(imgui.Col.ButtonActive, accentShade(1.8, 1))
                imgui.PushStyleColor(imgui.Col.Text,
                    isLitTab and accentContrastVec() or imgui.ImVec4(1, 1, 1, 1))
                if imgui.Button(label, imgui.ImVec2(tabW, 26)) then
                    data.settingsTab = i - 1
                end
                _settingsTabHover[i] = imgui.IsItemHovered()
                imgui.PopStyleColor(4)
            end
            imgui.Separator()
            imgui.Spacing()

            imgui.PushStyleColor(imgui.Col.WindowBg, accentTint(0.07, 0.08, 0.11, 0.25, 1))
            do
                imgui.Scroller("settings_scroll", 30, 300,
                    imgui.HoveredFlags.RectOnly + imgui.HoveredFlags.ChildWindows)

                -- Вкладка 0: Общее
                if data.settingsTab == 0 then
                    if imgui.Checkbox(u8 "Тихий режим", imcfg.silentMode) then
                        cfg.silentMode = imcfg.silentMode[0]; save()
                    end
                    imgui.Hint("Отключает все сообщения скрипта в чат.")

                    if imgui.Checkbox(u8 "Старый вид (диалог SAMP)", imcfg.useDialogMode) then
                        cfg.useDialogMode = imcfg.useDialogMode[0]; save()
                        if cfg.useDialogMode then
                            sampSendChat('/flashminer')
                            data.showLogsWindow[0] = false
                            data.showSettingsWindow[0] = false
                        end
                    end
                    imgui.Hint("Добавляет пункты в стандартный диалог SAMP вместо отдельного окна.")

                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()

                    if UPDATE_CHECK_URL ~= nil then
                        if imgui.Checkbox(u8 "Проверять обновления при запуске", imcfg.checkForUpdates) then
                            cfg.checkForUpdates = imcfg.checkForUpdates[0]; save()
                        end
                        imgui.Hint("Автоматически проверять наличие новых версий скрипта при запуске.\n")

                        if updateState.hasUpdate then
                            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 0.85, 0.2, 1.0))
                            if imgui.Selectable(fa.ARROW_UP_FROM_BRACKET .. u8(string.format("  Установить обновление %s", updateState.latestVersion or "")), false) then
                                updateState.showPopup[0]   = true
                                data.showSettingsWindow[0] = false
                            end
                            imgui.PopStyleColor()
                            imgui.Hint(
                                "{FFE133}Доступна новая версия скрипта!\n\n" ..
                                "{FFFFFF}Нажмите чтобы открыть окно обновления.\n" ..
                                "{808080}Текущая: " .. script.this.version .. "\n" ..
                                "{808080}Новая: " .. (updateState.latestVersion or "?"))
                        end

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()
                    end

                    if imgui.Selectable(u8 "Просмотр логов", false) then
                        data.showLogsWindow[0] = true
                        data.showSettingsWindow[0] = false
                    end
                    if imgui.Selectable(u8 "Сбросить статистику дохода", false) then
                        data.statsResetConfirm = true
                        data.statsResetTimer   = os.clock()
                    end

                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()

                    if imgui.Selectable(u8 "Перезагрузить скрипт", false) then
                        cfg.isReloaded = true; save(); thisScript():reload()
                    end
                    if imgui.Selectable(u8 "Сбросить все настройки", false) then
                        data.settingsResetConfirm = true
                        data.settingsResetTimer   = os.clock()
                    end
                    imgui.Spacing()
                    imgui.TextDisabled(u8("v" .. script.this.version))

                    -- Вкладка 1: Фермы
                elseif data.settingsTab == 1 then
                    if not cfg.useDialogMode and not data.isRodina then
                        imgui.TextColoredRGB("{87CEFA}Баланс дома:")
                        imgui.PushItemWidth(-1)
                        if imgui.SliderInt("##targetBalance", imcfg.targetHouseBalance, 5000000, 60000000,
                                u8("$" .. utils.formatNumber(imcfg.targetHouseBalance[0]))) then
                            local v = math.floor(imcfg.targetHouseBalance[0] / 100000 + 0.5) * 100000
                            cfg.targetHouseBalance = v; imcfg.targetHouseBalance[0] = v; save()
                        end
                        imgui.PopItemWidth()
                        imgui.Hint("Пополнять дом если баланс упадёт ниже этого значения.")

                        if imgui.Checkbox(u8 "Только пополнение баланса", imcfg.useSimpleTopUp) then
                            cfg.useSimpleTopUp = imcfg.useSimpleTopUp[0]; save()
                        end
                        imgui.Hint(
                            "Быстрый режим: кнопка обслуживания только пополнит баланс,\nне заходя в каждую стойку. Действия ниже при этом игнорируются.")

                        imgui.Spacing()
                        imgui.Text(fa.GEAR)
                        imgui.SameLine(0, 6)
                        imgui.TextColoredRGB("{87CEFA}Что делать кнопкой обслуживания")
                        imgui.Hint(
                            "Выберите действия для кнопки «Авто-обслуживание».\nИх можно комбинировать в любом сочетании —\nнапример, только собрать крипту, или\nсобрать и сразу включить видеокарты.")

                        imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.10, 0.11, 0.15, 0.25, 1))
                        imgui.BeginChild("##fixActions", imgui.ImVec2(0, 120), true,
                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                        if cfg.useSimpleTopUp then
                            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.5, 0.5, 0.5, 1))
                            imgui.PushStyleColor(imgui.Col.CheckMark, imgui.ImVec4(0.5, 0.5, 0.5, 1))
                            imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.10, 0.10, 0.10, 1))
                            imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0.10, 0.10, 0.10, 1))
                            imgui.Checkbox(u8 "Собирать крипту", imgui.new.bool(cfg.fixCollectEnabled))
                            imgui.Checkbox(u8 "Включать видеокарты", imgui.new.bool(cfg.fixSwitchEnabled))
                            imgui.Checkbox(u8 "Пополнять баланс", imgui.new.bool(cfg.fixTopUpEnabled))
                            imgui.PopStyleColor(4)
                            imgui.Hint("Недоступно: включён режим «Только пополнение баланса».")
                        else
                            if imgui.Checkbox(u8 "Собирать крипту", imcfg.fixCollectEnabled) then
                                cfg.fixCollectEnabled = imcfg.fixCollectEnabled[0]; save()
                            end
                            imgui.Hint("Снимать криптовалюту со всех домов.")
                            if imgui.Checkbox(u8 "Включать видеокарты", imcfg.fixSwitchEnabled) then
                                cfg.fixSwitchEnabled = imcfg.fixSwitchEnabled[0]; save()
                            end
                            imgui.Hint("Включать выключенные карты.")
                            if imgui.Checkbox(u8 "Пополнять баланс", imcfg.fixTopUpEnabled) then
                                cfg.fixTopUpEnabled = imcfg.fixTopUpEnabled[0]; save()
                            end
                            imgui.Hint("Пополнять баланс домов до целевого значения.")
                        end
                        imgui.EndChild()
                        imgui.PopStyleColor()

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Охлаждение:")
                        imgui.PushItemWidth(-1)
                        if imgui.SliderInt("##coolantPercentSettings", imcfg.useCoolantPercent, 1, 100, u8 "%d%%") then
                            cfg.useCoolantPercent = imcfg.useCoolantPercent[0]; save()
                        end
                        imgui.PopItemWidth()
                        imgui.Hint("Заливать если уровень ниже этого порога.")

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Автоматизация стойки:")

                        if imgui.Checkbox(u8 "Авто-заливка при открытии стойки", imcfg.fixCoolantEnabled) then
                            cfg.fixCoolantEnabled = imcfg.fixCoolantEnabled[0]; save()
                        end
                        imgui.Hint(
                            "Автоматически заливать жидкость при открытии стойки видеокарт.\nНе работает через Флешку Майнера.")

                        if imgui.Checkbox(u8 "Авто-включение карт после заливки", imcfg.autoEnableCards) then
                            cfg.autoEnableCards = imcfg.autoEnableCards[0]
                            if cfg.autoEnableCards then
                                cfg.autoEnableCardsOnOpen = false; imcfg.autoEnableCardsOnOpen[0] = false
                            end
                            save()
                        end
                        imgui.Hint(
                            "После заливки жидкости автоматически включать выключенные карты.\nНе совместимо с 'Авто-включение при открытии стойки'.")

                        if imgui.Checkbox(u8 "Авто-включение карт при открытии стойки", imcfg.autoEnableCardsOnOpen) then
                            cfg.autoEnableCardsOnOpen = imcfg.autoEnableCardsOnOpen[0]
                            if cfg.autoEnableCardsOnOpen then
                                cfg.autoEnableCards = false; imcfg.autoEnableCards[0] = false
                            end
                            save()
                        end
                        imgui.Hint(
                            "Включать выключенные карты при открытии стойки,\n" ..
                            "независимо от заливки жидкости.\n" ..
                            "Не совместимо с 'Авто-включение после заливки'.\n")

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Предупреждения:")
                        imgui.Text(u8 "Порог баланса (предупреждение):")
                        imgui.PushItemWidth(-1)
                        if imgui.SliderInt("##minBalanceWarning", imcfg.minBalanceWarning, 1000000, 15000000,
                                u8("$" .. utils.formatNumber(imcfg.minBalanceWarning[0]))) then
                            local v = math.floor(imcfg.minBalanceWarning[0] / 500000 + 0.5) * 500000
                            cfg.minBalanceWarning = v; imcfg.minBalanceWarning[0] = v; save()
                        end
                        imgui.PopItemWidth()
                        imgui.Hint("Карточка дома станет жёлтой если баланс ниже этого значения.")

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Сбор крипты:")
                        imgui.Text(u8 "Собирать если накопилось не менее:")
                        imgui.PushItemWidth(-1)
                        if imgui.SliderInt("##collectOnlyIfMin", imcfg.collectOnlyIfMin, 0, 180,
                                imcfg.collectOnlyIfMin[0] == 0
                                and u8 "Любое кол-во"
                                or u8(string.format("от %d BTC", imcfg.collectOnlyIfMin[0]))) then
                            cfg.collectOnlyIfMin = imcfg.collectOnlyIfMin[0]; save()
                        end
                        imgui.PopItemWidth()
                        imgui.Hint(
                            "0 = собирать всегда (от 1 BTC).\nПри сборе пропускать дома где меньше N BTC.\n" ..
                            "Учтите, что если на ферме будет например 5 карт,\n" ..
                            "а значение стоит на 180, то этот дом никогда не будет собираться.")

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        if imgui.Selectable(u8 "Проверить подвалы", false) then
                            if not data.working then
                                local task = buildTaskTable('scanBasements')
                                runTaskAndReopenDialog(function() task:run(nil) end)
                                data.showSettingsWindow[0] = false
                            else
                                utils.addChat("{F78181}Дождитесь завершения текущей операции.")
                            end
                        end
                        imgui.Hint("Сканирование домов на наличие подвала.")
                    else
                        imgui.Spacing()
                        imgui.TextColoredRGB("{808080}Недоступно в текущем режиме.")
                    end

                    -- Вкладка 2: Автосбор + Уведомления
                elseif data.settingsTab == 2 then
                    if not cfg.useDialogMode and not data.isRodina then
                        imgui.TextColoredRGB("{FF6B6B}Авто")

                        if imgui.Checkbox(u8 "Включить авто-функции", imcfg.cheatModeEnabled) then
                            cfg.cheatModeEnabled = imcfg.cheatModeEnabled[0]
                            if not cfg.cheatModeEnabled then
                                cfg.autoCollectEnabled = false; imcfg.autoCollectEnabled[0] = false
                                cfg.smartCollectEnabled = false; imcfg.smartCollectEnabled[0] = false
                                cfg.autoPayTaxesEnabled = false; imcfg.autoPayTaxesEnabled[0] = false
                                cfg.autoTopUpEnabled = false; imcfg.autoTopUpEnabled[0] = false
                            end
                            save()
                        end
                        imgui.Hint(
                            "{FF6B6B} ВНИМАНИЕ!\n" ..
                            "Эти функции могут быть запрещены на вашем сервере!\n" ..
                            "Перед использованием уточните у администрации,\n" ..
                            "не нарушает ли это правила сервера.\n\n" ..
                            "Используйте на свой страх и риск.\n" ..
                            "Автор не несёт ответственности за блокировки\n" ..
                            "или иные проблемы, связанные с их использованием.\n\n")

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        do
                            local subTabs = { u8 "Автосбор", u8 "Финансы", u8 "Уведомления" }
                            local subTabCount = #subTabs
                            local subTabW = (winW - imStyle.WindowPadding.x * 2 - imStyle.ItemSpacing.x * (subTabCount - 1)) /
                                subTabCount

                            for si, slabel in ipairs(subTabs) do
                                if si > 1 then imgui.SameLine(0, imStyle.ItemSpacing.x) end
                                imgui.PushStyleColor(imgui.Col.Button,
                                    data.cheatSubTab == si - 1
                                    and imgui.ImVec4(0.18, 0.28, 0.45, 1)
                                    or imgui.ImVec4(0.11, 0.12, 0.16, 1))
                                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.30, 0.48, 1))
                                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.22, 0.32, 0.50, 1))
                                if imgui.Button(slabel .. "##cheatSub", imgui.ImVec2(subTabW, 30)) then
                                    data.cheatSubTab = si - 1
                                end
                                imgui.PopStyleColor(3)
                            end
                            imgui.Spacing()

                            if data.cheatSubTab == 0 then
                                if not cfg.cheatModeEnabled then
                                    imgui.Spacing()
                                    imgui.TextColoredRGB(
                                        "{808080}Недоступно. Включите авто-функции выше.")
                                else
                                    imgui.TextColoredRGB("{87CEFA}Автосбор по расписанию")

                                    if imgui.Checkbox(u8 "Включить автосбор по расписанию", imcfg.autoCollectEnabled) then
                                        cfg.autoCollectEnabled = imcfg.autoCollectEnabled[0]
                                        if cfg.autoCollectEnabled then
                                            cfg.smartCollectEnabled = false; imcfg.smartCollectEnabled[0] = false
                                            cfg.reminderEnabled = false; imcfg.reminderEnabled[0] = false
                                        end
                                        save()
                                    end
                                    imgui.Hint("Собирать крипту через равные промежутки времени.")

                                    if cfg.autoCollectEnabled then
                                        imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.10, 0.11, 0.15, 0.25, 1))
                                        imgui.BeginChild("##autoCSub", imgui.ImVec2(0, 100), true,
                                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                                        imgui.PushItemWidth(-1)
                                        if imgui.SliderInt("##cTimes", imcfg.collectTimesPerDay, 1, 8,
                                                u8(string.format("%d/день (~%s)", imcfg.collectTimesPerDay[0],
                                                    formatTimeLeft(math.floor(86400 / math.max(1, imcfg.collectTimesPerDay[0])))))) then
                                            cfg.collectTimesPerDay = imcfg.collectTimesPerDay[0]
                                            collectTool.resetPendingDelay()
                                            save()
                                        end
                                        imgui.PopItemWidth()
                                        local tL = collectTool.getTimeUntil()
                                        if data.pendingCollectLocked then
                                            local pLeft = data.pendingCollectAt - os.time()
                                            if pLeft > 0 then
                                                local pLabel = cfg.randomDelayEnabled
                                                    and "Рандомная задержка"
                                                    or "Автосбор через"
                                                imgui.TextColoredRGB(string.format(
                                                    "{FFE133}%s: %s", pLabel,
                                                    formatTimeLeft(pLeft)))
                                            end
                                        end
                                        if tL > 0 then
                                            imgui.TextColoredRGB(string.format("{808080}До сбора: {FFFFFF}%s",
                                                formatTimeLeft(tL)))
                                        end
                                        if imgui.Selectable(u8 "Сбросить таймер", false) then
                                            cfg.lastCollectTime = os.time()
                                            collectTool.resetPendingDelay()
                                            save()
                                        end
                                        imgui.EndChild()
                                        imgui.PopStyleColor()
                                    end

                                    imgui.Spacing()

                                    imgui.TextColoredRGB("{87CEFA}Умный автосбор")

                                    if imgui.Checkbox(u8 "Включить умный автосбор", imcfg.smartCollectEnabled) then
                                        cfg.smartCollectEnabled = imcfg.smartCollectEnabled[0]
                                        if cfg.smartCollectEnabled then
                                            cfg.autoCollectEnabled = false; imcfg.autoCollectEnabled[0] = false
                                            cfg.reminderEnabled = false; imcfg.reminderEnabled[0] = false
                                        end
                                        save()
                                    end
                                    imgui.Hint("Собирать когда накопится заданное кол-во BTC+ASC.")

                                    if cfg.smartCollectEnabled then
                                        imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.10, 0.11, 0.15, 0.25, 1))
                                        imgui.BeginChild("##smartCSub", imgui.ImVec2(0, 110), true,
                                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                                        local sMin, sMax = 160, 5000
                                        if imcfg.smartCollectTarget[0] < sMin then
                                            imcfg.smartCollectTarget[0] = sMin; cfg.smartCollectTarget = sMin
                                        elseif imcfg.smartCollectTarget[0] > sMax then
                                            imcfg.smartCollectTarget[0] = sMax; cfg.smartCollectTarget = sMax
                                        end
                                        imgui.PushItemWidth(-1)
                                        if imgui.SliderInt("##sTgt", imcfg.smartCollectTarget, sMin, sMax,
                                                u8(string.format("при %d BTC+ASC", imcfg.smartCollectTarget[0]))) then
                                            cfg.smartCollectTarget = imcfg.smartCollectTarget[0]
                                            collectTool.resetPendingDelay()
                                            save()
                                        end
                                        imgui.PopItemWidth()
                                        local sB, sA, sDB, sDA, sOk = 0, 0, 0, 0, false
                                        for _, h in ipairs(data.dialogData.flashminer) do
                                            if not houseFilter.shouldSkip(h.house_number) then
                                                local st = data.houseStatuses[h.house_number]
                                                if st and st.lastCheck > 0 then
                                                    sOk = true
                                                    local dBtc, dAsc = houseFilter.getDailyIncome(h.house_number)
                                                    sB   = sB + (st.earnings and st.earnings.btc or 0)
                                                    sA   = sA + (st.earnings and st.earnings.asc or 0)
                                                    sDB  = sDB + dBtc
                                                    sDA  = sDA + dAsc
                                                end
                                            end
                                        end
                                        local sTotalDaily = sDB + sDA
                                        if sOk then
                                            local sTotal = sB + sA
                                            local accText = string.format(
                                                "{808080}\xcd\xe0\xea\xee\xef\xeb\xe5\xed\xee: {BEF781}%d BTC+ASC {808080}/ {FFFFFF}%d BTC+ASC",
                                                math.floor(sTotal), cfg.smartCollectTarget)
                                            imgui.TextColoredRGB(accText)

                                            if sA > 0 then
                                                imgui.TextColoredRGB(string.format(
                                                    "{808080}\xc8\xe7 \xed\xe8\xf5: {D2691E}%d BTC {808080}+ {C0392B}%d ASC",
                                                    math.floor(sB), math.floor(sA)))
                                            end

                                            if data.pendingCollectLocked then
                                                local pLeft = data.pendingCollectAt - os.time()
                                                if pLeft > 0 then
                                                    local sLabel = cfg.randomDelayEnabled
                                                        and "\xd0\xe0\xed\xe4\xee\xec\xed\xe0\xff \xe7\xe0\xe4\xe5\xf0\xe6\xea\xe0"
                                                        or "\xd3\xec\xed\xfb\xe9 \xf1\xe1\xee\xf0 \xf7\xe5\xf0\xe5\xe7"
                                                    imgui.TextColoredRGB(string.format(
                                                        "{FFE133}%s: %s", sLabel,
                                                        formatTimeLeft(pLeft)))
                                                end
                                            end
                                        else
                                            imgui.TextColoredRGB("{808080}Откройте /flashminer.")
                                        end
                                        imgui.EndChild()
                                        imgui.PopStyleColor()
                                    end

                                    imgui.Spacing()

                                    if cfg.autoCollectEnabled or cfg.smartCollectEnabled then
                                        if imgui.Checkbox(u8 "Включать карты после автосбора", imcfg.autoEnableCardsOnCollect) then
                                            cfg.autoEnableCardsOnCollect = imcfg.autoEnableCardsOnCollect[0]; save()
                                        end
                                        imgui.Hint("Включать выключенные карты сразу после сбора крипты.")
                                    end

                                    imgui.Spacing()
                                    imgui.Separator()
                                    imgui.Spacing()

                                    imgui.TextColoredRGB("{87CEFA}Рандомная задержка")

                                    if imgui.Checkbox(u8 "Добавлять рандомную задержку", imcfg.randomDelayEnabled) then
                                        cfg.randomDelayEnabled = imcfg.randomDelayEnabled[0]
                                        if not cfg.randomDelayEnabled then
                                            data.pendingCollectLocked = false
                                            data.pendingCollectAt = 0
                                        end
                                        save()
                                    end
                                    imgui.Hint(
                                        "Добавляет случайную задержку перед автосбором.")

                                    if cfg.randomDelayEnabled then
                                        imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.10, 0.11, 0.15, 0.25, 1))
                                        imgui.BeginChild("##rndDelaySub", imgui.ImVec2(0, 80), true,
                                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                                        imgui.PushItemWidth(-1)
                                        if imgui.SliderInt("##rndMin", imcfg.randomDelayMin, 1, imcfg.randomDelayMax[0],
                                                u8(string.format("от %d мин.", imcfg.randomDelayMin[0]))) then
                                            cfg.randomDelayMin = imcfg.randomDelayMin[0]
                                            if cfg.randomDelayMin > cfg.randomDelayMax then
                                                cfg.randomDelayMax = cfg.randomDelayMin
                                                imcfg.randomDelayMax[0] = cfg.randomDelayMax
                                            end
                                            collectTool.resetPendingDelay()
                                            save()
                                        end
                                        if imgui.SliderInt("##rndMax", imcfg.randomDelayMax, imcfg.randomDelayMin[0], 180,
                                                u8(string.format("до %d мин.", imcfg.randomDelayMax[0]))) then
                                            cfg.randomDelayMax = imcfg.randomDelayMax[0]
                                            if cfg.randomDelayMax < cfg.randomDelayMin then
                                                cfg.randomDelayMin = cfg.randomDelayMax
                                                imcfg.randomDelayMin[0] = cfg.randomDelayMin
                                            end
                                            collectTool.resetPendingDelay()
                                            save()
                                        end
                                        imgui.PopItemWidth()
                                        if data.pendingCollectLocked then
                                            local pLeft = data.pendingCollectAt - os.time()
                                            if pLeft > 0 then
                                                imgui.TextColoredRGB(string.format("{FFE133}Задержка: %s",
                                                    formatTimeLeft(pLeft)))
                                            end
                                        end
                                        imgui.EndChild()
                                        imgui.PopStyleColor()
                                    end

                                    imgui.Spacing()
                                    imgui.Separator()
                                    imgui.Spacing()

                                    imgui.TextColoredRGB("{87CEFA}Фоновое обновление статусов")

                                    if imgui.Checkbox(u8 "Периодически обновлять данные домов", imcfg.autoRefreshEnabled) then
                                        cfg.autoRefreshEnabled = imcfg.autoRefreshEnabled[0]; save()
                                    end
                                    imgui.Hint(
                                        "Автоматически обновлять статусы домов в фоне.\n" ..
                                        "Необходимо для корректной работы умного автосбора\n" ..
                                        "и автосбора без ручного открытия /flashminer.\n\n" ..
                                        "{808080}Вызывает /flashminer и обновляет данные.\n\n" ..
                                        "{FFE133}Если выключено, скрипт всё равно будет тихо\n" ..
                                        "обновлять данные раз в 5 минут (без настроек ниже) —\n" ..
                                        "чтобы доходность не устаревала для других функций.")

                                    if cfg.autoRefreshEnabled then
                                        local refreshChildH = 100
                                        if cfg.refreshPostponeOnDialog then refreshChildH = 140 end

                                        imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.10, 0.11, 0.15, 0.25, 1))
                                        imgui.BeginChild("##refreshSub", imgui.ImVec2(0, refreshChildH), true,
                                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                                        imgui.PushItemWidth(-1)
                                        if imgui.SliderInt("##refreshInt", imcfg.autoRefreshInterval, 5, 120,
                                                u8(string.format("каждые %d мин.", imcfg.autoRefreshInterval[0]))) then
                                            cfg.autoRefreshInterval = imcfg.autoRefreshInterval[0]; save()
                                        end

                                        local refLeft = (cfg.lastAutoRefreshTime + cfg.autoRefreshInterval * 60) -
                                            os.time()
                                        imgui.TextColoredRGB(refLeft > 0
                                            and string.format("{808080}До обновления: {FFFFFF}%s",
                                                formatTimeLeft(refLeft))
                                            or "{BEF781}При следующей проверке!")

                                        imgui.PopItemWidth()

                                        if imgui.Checkbox(u8 "Не прерывать открытый диалог",
                                                imcfg.refreshPostponeOnDialog) then
                                            cfg.refreshPostponeOnDialog = imcfg.refreshPostponeOnDialog[0]; save()
                                        end
                                        imgui.Hint(
                                            "Если у вас открыт любой диалог в момент обновления —\n" ..
                                            "отложить обновление, чтобы не сбить ваше взаимодействие.\n")

                                        if cfg.refreshPostponeOnDialog then
                                            imgui.PushItemWidth(-1)
                                            if imgui.SliderInt("##refreshPostpone", imcfg.refreshPostponeMinutes, 1, 5,
                                                    u8(string.format("отложить на %d мин.", imcfg.refreshPostponeMinutes[0]))) then
                                                cfg.refreshPostponeMinutes = imcfg.refreshPostponeMinutes[0]; save()
                                            end
                                            imgui.PopItemWidth()
                                        end

                                        local postponed = autoRefreshTool.getPostponedUntil()
                                        if postponed > os.time() then
                                            imgui.TextColoredRGB(string.format(
                                                "{FFE133}Отложено: {FFFFFF}%s",
                                                formatTimeLeft(postponed - os.time())))
                                        end

                                        imgui.EndChild()
                                        imgui.PopStyleColor()
                                    end
                                end -- end else cheatModeEnabled (subtab 0)
                            elseif data.cheatSubTab == 1 then
                                if not cfg.cheatModeEnabled then
                                    imgui.Spacing()
                                    imgui.TextColoredRGB(
                                        "{808080}Недоступно. Включите авто-функции выше.")
                                else
                                    imgui.TextColoredRGB("{87CEFA}Автооплата налогов")

                                    if imgui.Checkbox(u8 "Включить автооплату налогов", imcfg.autoPayTaxesEnabled) then
                                        cfg.autoPayTaxesEnabled = imcfg.autoPayTaxesEnabled[0]; save()
                                    end
                                    imgui.Hint(
                                        "Автоматическая оплата всех налогов.\n" ..
                                        "{FFE133}Требуется ADD VIP.")

                                    if cfg.autoPayTaxesEnabled then
                                        local taxChildH = 85
                                        if cfg.autoPayTaxesByTimer then taxChildH = 135 end

                                        imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.10, 0.11, 0.15, 0.25, 1))
                                        imgui.BeginChild("##taxSub", imgui.ImVec2(0, taxChildH), true,
                                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

                                        if imgui.Checkbox(u8 "Вместе с автосбором", imcfg.autoPayTaxesWithCollect) then
                                            cfg.autoPayTaxesWithCollect = imcfg.autoPayTaxesWithCollect[0]
                                            if cfg.autoPayTaxesWithCollect then
                                                cfg.autoPayTaxesByTimer = false; imcfg.autoPayTaxesByTimer[0] = false
                                            end
                                            save()
                                        end
                                        imgui.Hint("Оплачивать налоги после каждого автосбора крипты.")

                                        if imgui.Checkbox(u8 "По таймеру", imcfg.autoPayTaxesByTimer) then
                                            cfg.autoPayTaxesByTimer = imcfg.autoPayTaxesByTimer[0]
                                            if cfg.autoPayTaxesByTimer then
                                                cfg.autoPayTaxesWithCollect = false; imcfg.autoPayTaxesWithCollect[0] = false
                                            end
                                            save()
                                        end
                                        imgui.Hint("Оплачивать налоги через заданный интервал.")

                                        if cfg.autoPayTaxesByTimer then
                                            imgui.PushItemWidth(-1)
                                            if imgui.SliderInt("##taxInt", imcfg.autoPayTaxesInterval, 1, 48,
                                                    u8(string.format("каждые %d ч.", imcfg.autoPayTaxesInterval[0]))) then
                                                cfg.autoPayTaxesInterval = imcfg.autoPayTaxesInterval[0]; save()
                                            end
                                            imgui.PopItemWidth()
                                            local taxLeft = (cfg.lastTaxPayTime + cfg.autoPayTaxesInterval * 3600) -
                                                os.time()
                                            imgui.TextColoredRGB(taxLeft > 0
                                                and string.format("{808080}До оплаты: {FFFFFF}%s",
                                                    formatTimeLeft(taxLeft))
                                                or "{BEF781}Оплата при следующей проверке!")
                                        end

                                        imgui.EndChild()
                                        imgui.PopStyleColor()
                                    end

                                    imgui.Spacing()
                                    imgui.Separator()
                                    imgui.Spacing()

                                    imgui.TextColoredRGB("{87CEFA}Автопополнение баланса")

                                    if imgui.Checkbox(u8 "Включить автопополнение", imcfg.autoTopUpEnabled) then
                                        cfg.autoTopUpEnabled = imcfg.autoTopUpEnabled[0]; save()
                                    end
                                    imgui.Hint(
                                        "Пополнять баланс домов до целевого значения.\n" ..
                                        "{808080}Целевой баланс — на вкладке 'Фермы'.")

                                    if cfg.autoTopUpEnabled then
                                        local topUpChildH = 150
                                        if cfg.autoTopUpByThreshold then topUpChildH = topUpChildH + 28 end
                                        if cfg.autoTopUpByTimer then topUpChildH = topUpChildH + 48 end

                                        imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.10, 0.11, 0.15, 0.25, 1))
                                        imgui.BeginChild("##topUpSub", imgui.ImVec2(0, topUpChildH), true,
                                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

                                        imgui.TextColoredRGB(string.format("{808080}Цель: {FFD700}$%s",
                                            utils.formatNumber(cfg.targetHouseBalance)))
                                        imgui.Spacing()

                                        if imgui.Checkbox(u8 "Вместе с автосбором", imcfg.autoTopUpWithCollect) then
                                            cfg.autoTopUpWithCollect = imcfg.autoTopUpWithCollect[0]
                                            if cfg.autoTopUpWithCollect then
                                                cfg.autoTopUpByTimer = false; imcfg.autoTopUpByTimer[0] = false
                                                cfg.autoTopUpByThreshold = false; imcfg.autoTopUpByThreshold[0] = false
                                            end
                                            save()
                                        end
                                        imgui.Hint("Пополнять после каждого автосбора крипты.")

                                        if imgui.Checkbox(u8 "При низком балансе", imcfg.autoTopUpByThreshold) then
                                            cfg.autoTopUpByThreshold = imcfg.autoTopUpByThreshold[0]
                                            if cfg.autoTopUpByThreshold then
                                                cfg.autoTopUpWithCollect = false; imcfg.autoTopUpWithCollect[0] = false
                                                cfg.autoTopUpByTimer = false; imcfg.autoTopUpByTimer[0] = false
                                            end
                                            save()
                                        end
                                        imgui.Hint("Пополнять когда баланс любого дома упадёт ниже порога.")

                                        if cfg.autoTopUpByThreshold then
                                            imgui.PushItemWidth(-1)
                                            if imgui.SliderInt("##topUpThr", imcfg.autoTopUpThreshold, 500000, 20000000,
                                                    u8("$" .. utils.formatNumber(imcfg.autoTopUpThreshold[0]))) then
                                                local v = math.floor(imcfg.autoTopUpThreshold[0] / 100000 + 0.5) * 100000
                                                cfg.autoTopUpThreshold = v; imcfg.autoTopUpThreshold[0] = v; save()
                                            end
                                            imgui.PopItemWidth()
                                        end

                                        if imgui.Checkbox(u8 "По таймеру", imcfg.autoTopUpByTimer) then
                                            cfg.autoTopUpByTimer = imcfg.autoTopUpByTimer[0]
                                            if cfg.autoTopUpByTimer then
                                                cfg.autoTopUpWithCollect = false; imcfg.autoTopUpWithCollect[0] = false
                                                cfg.autoTopUpByThreshold = false; imcfg.autoTopUpByThreshold[0] = false
                                            end
                                            save()
                                        end
                                        imgui.Hint("Пополнять баланс через заданный интервал.")

                                        if cfg.autoTopUpByTimer then
                                            imgui.PushItemWidth(-1)
                                            if imgui.SliderInt("##topUpInt", imcfg.autoTopUpTimerInterval, 1, 48,
                                                    u8(string.format("каждые %d ч.", imcfg.autoTopUpTimerInterval[0]))) then
                                                cfg.autoTopUpTimerInterval = imcfg.autoTopUpTimerInterval[0]; save()
                                            end
                                            imgui.PopItemWidth()
                                            local tuLeft = (cfg.lastAutoTopUpTime + cfg.autoTopUpTimerInterval * 3600) -
                                                os.time()
                                            imgui.TextColoredRGB(tuLeft > 0
                                                and string.format("{808080}До пополнения: {FFFFFF}%s",
                                                    formatTimeLeft(tuLeft))
                                                or "{BEF781}При следующей проверке!")
                                        end

                                        imgui.EndChild()
                                        imgui.PopStyleColor()
                                    end
                                end -- end else cheatModeEnabled (subtab 1)
                            elseif data.cheatSubTab == 2 then
                                imgui.TextColoredRGB("{87CEFA}Напоминания")

                                local blockReminder = cfg.cheatModeEnabled
                                    and (cfg.autoCollectEnabled or cfg.smartCollectEnabled)

                                if blockReminder then
                                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.5, 0.5, 0.5, 1))
                                    imgui.PushStyleColor(imgui.Col.CheckMark, imgui.ImVec4(0.5, 0.5, 0.5, 1))
                                    imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.10, 0.10, 0.10, 1))
                                    imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0.10, 0.10, 0.10, 1))
                                    local dummy = imgui.new.bool(false)
                                    imgui.Checkbox(u8 "Напоминание о BTC+ASC", dummy)
                                    imgui.PopStyleColor(4)
                                    imgui.Hint(
                                        "Недоступно пока включён автосбор\nили умный автосбор.")
                                else
                                    if imgui.Checkbox(u8 "Напоминание о BTC+ASC", imcfg.reminderEnabled) then
                                        cfg.reminderEnabled = imcfg.reminderEnabled[0]; save()
                                    end
                                    imgui.Hint(
                                        "Показывать окно при достижении порога BTC+ASC.")
                                end

                                if cfg.reminderEnabled and not blockReminder then
                                    imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.10, 0.11, 0.15, 0.25, 1))
                                    imgui.BeginChild("##remSub", imgui.ImVec2(0, 140), true,
                                        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                                    local estBtc, hasData, estAsc = estimateTotalBTC()
                                    if hasData then
                                        local estTotal = estBtc + (estAsc or 0)
                                        local fr = math.min(estTotal / math.max(cfg.btcThreshold, 1), 1.0)
                                        local c = fr >= 1.0 and "{BEF781}" or (fr >= 0.7 and "{FFE133}" or "{FF6B6B}")
                                        imgui.TextColoredRGB(string.format(
                                            "{808080}Сейчас: %s%d {808080}/ {FFFFFF}%d BTC+ASC",
                                            c, math.floor(estTotal), cfg.btcThreshold))
                                    end
                                    imgui.PushItemWidth(-1)
                                    if imgui.SliderInt("##btcThr", imcfg.btcThreshold, 10, 2000,
                                            u8(string.format("порог: %d BTC+ASC", imcfg.btcThreshold[0]))) then
                                        cfg.btcThreshold = imcfg.btcThreshold[0]; save()
                                    end
                                    if imgui.SliderInt("##remInt", imcfg.reminderInterval, 1, 60,
                                            u8(string.format("каждые %d мин.", imcfg.reminderInterval[0]))) then
                                        cfg.reminderInterval = imcfg.reminderInterval[0]; save()
                                    end
                                    if imgui.SliderInt("##nDur", imcfg.notifyShowDuration, 3, 30,
                                            u8(string.format("показывать %d сек.", imcfg.notifyShowDuration[0]))) then
                                        cfg.notifyShowDuration = imcfg.notifyShowDuration[0]; save()
                                    end
                                    imgui.Hint("Как долго показывать всплывающее\nуведомление.")
                                    imgui.PopItemWidth()
                                    imgui.EndChild()
                                    imgui.PopStyleColor()
                                end

                                if cfg.cheatModeEnabled then
                                    imgui.Spacing()
                                    imgui.Separator()
                                    imgui.Spacing()

                                    imgui.TextColoredRGB("{87CEFA}Окно уведомлений:")
                                    if imgui.Checkbox(u8 "Уведомления автосбора", imcfg.notifyAutoCollectEnabled) then
                                        cfg.notifyAutoCollectEnabled = imcfg.notifyAutoCollectEnabled[0]; save()
                                    end
                                    imgui.Hint(
                                        "Показывать окно уведомлений для автосбора\nи умного автосбора (обратный отсчёт, статус сбора).")

                                    if cfg.autoCollectEnabled then
                                        imgui.PushItemWidth(-1)
                                        if imgui.SliderInt("##nBefore", imcfg.notifyBeforeSec, 30, 600,
                                                u8(string.format("за %d сек.", imcfg.notifyBeforeSec[0]))) then
                                            cfg.notifyBeforeSec = imcfg.notifyBeforeSec[0]; save()
                                        end
                                        imgui.Hint("За сколько секунд до автосбора показывать\nокно с обратным отсчётом (только для сбора по расписанию).")
                                        imgui.PopItemWidth()
                                    else
                                        imgui.TextColoredRGB("{808080}Умный автосбор срабатывает мгновенно, без предупреждения.")
                                    end
                                    imgui.Spacing()
                                    imgui.Separator()
                                    imgui.TextColoredRGB("{87CEFA}Предпросмотр")
                                    if imgui.Selectable(u8 "Предпросмотр окна", false) then
                                        data.notifyWindow.btcAmount  = 150
                                        data.notifyWindow.mode       = 'reminder'
                                        data.notifyWindow.autoHideAt = os.time() + cfg.notifyShowDuration
                                        data.notifyWindow.isPreview  = true
                                        data.notifyWindow.show[0]    = true
                                    end
                                    imgui.Hint(
                                        "Показать пример окна уведомления.\nПеретащите его мышью — позиция\nавтоматически сохранится.\nСпустя несколько секунд окно пропадёт.")
                                end
                            end
                        end
                    else
                        imgui.Spacing()
                        imgui.TextColoredRGB("{808080}Недоступно в текущем режиме.")
                    end
                elseif data.settingsTab == 3 then
                    imgui.TextColoredRGB("{87CEFA}Пауза на PayDay")
                    if imgui.Checkbox(u8 "Приостанавливать действия на PayDay", imcfg.pauseOnPayday) then
                        cfg.pauseOnPayday = imcfg.pauseOnPayday[0]; save()
                    end
                    imgui.Hint("Делать паузу во время PayDay.")

                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()

                    imgui.TextColoredRGB("{87CEFA}Ожидание подключения:")

                    if imgui.Checkbox(u8 "Ждать подключения к серверу", imcfg.waitForConnection) then
                        cfg.waitForConnection = imcfg.waitForConnection[0]; save()
                    end
                    imgui.Hint(
                        "Если вы не подключены к серверу — все автодействия\n" ..
                        "приостанавливаются до момента подключения.\n\n" ..
                        "После подключения ждём указанное ниже время,\n" ..
                        "прежде чем возобновить автодействия.")

                    if cfg.waitForConnection then
                        imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.10, 0.11, 0.15, 0.25, 1))
                        imgui.BeginChild("##connSub", imgui.ImVec2(0, 70), true,
                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                        imgui.PushItemWidth(-1)
                        if imgui.SliderInt("##delayAfterConnect", imcfg.delayAfterConnectMin, 5, 20,
                                u8(string.format("задержка %d мин. после подключения",
                                    imcfg.delayAfterConnectMin[0]))) then
                            cfg.delayAfterConnectMin = imcfg.delayAfterConnectMin[0]; save()
                        end
                        imgui.PopItemWidth()

                        if data.connectionState.connected then
                            local waitLeft = data.connectionState.readyAfterConnect - os.time()
                            if waitLeft > 0 then
                                imgui.TextColoredRGB(string.format(
                                    "{FFE133}Активация через: {FFFFFF}%s", formatTimeLeft(waitLeft)))
                            else
                                imgui.TextColoredRGB("{BEF781}Статус: подключён")
                            end
                        else
                            imgui.TextColoredRGB("{FF6B6B}Статус: не в игре")
                        end

                        imgui.EndChild()
                        imgui.PopStyleColor()
                    end

                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()

                    imgui.TextColoredRGB("{87CEFA}Скорость диалогов:")
                    imgui.PushItemWidth(-1)
                    if imgui.SliderInt("##pause", imcfg.pause_duration, 150, 300, u8 "%d мс") then
                        cfg.pause_duration = imcfg.pause_duration[0]; save()
                    end
                    imgui.Hint("Пауза между диалогами.")
                    if imgui.SliderInt("##count", imcfg.count_action, 1, 20,
                            u8(string.format("пауза каждые %d", imcfg.count_action[0]))) then
                        cfg.count_action = imcfg.count_action[0]; save()
                    end
                    imgui.Hint("Количество взаимодействий с диалогами до паузы.")
                    imgui.PopItemWidth()

                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()

                    imgui.TextColoredRGB("{87CEFA}Оформление:")
                    imgui.Text(u8 "Акцентный цвет интерфейса")
                    imgui.SameLine()
                    if imgui.ColorEdit3("##accentColorPicker", accentColorBuf) then
                        saveAccentColor()
                    end
                    imgui.Hint(
                        "Определяет оттенок всего интерфейса: фон главного окна,\nвкладки, плашки сверху («Всего домов», «Доступно» и т.д.),\nкарточки домов в списке, кнопки в окне логов\nи выделение выбранного дня в разделе «По дням».")

                    imgui.Spacing()
                    imgui.Text(u8 "Готовые палитры:")
                    local accentPresets = {
                        { name = "Синяя",       r = 0.16, g = 0.38, b = 0.62 },
                        { name = "Зелёная",     r = 0.16, g = 0.50, b = 0.28 },
                        { name = "Фиолетовая",  r = 0.42, g = 0.20, b = 0.62 },
                        { name = "Красная",     r = 0.62, g = 0.16, b = 0.16 },
                        { name = "Оранжевая",   r = 0.70, g = 0.42, b = 0.10 },
                        { name = "Бирюзовая",   r = 0.10, g = 0.52, b = 0.52 },
                    }
                    for presetIdx, preset in ipairs(accentPresets) do
                        if presetIdx > 1 then imgui.SameLine(0, 6) end
                        local swatchColor = imgui.ImVec4(preset.r, preset.g, preset.b, 1)
                        imgui.PushStyleColor(imgui.Col.Button, swatchColor)
                        imgui.PushStyleColor(imgui.Col.ButtonHovered,
                            imgui.ImVec4(math.min(preset.r * 1.15, 1), math.min(preset.g * 1.15, 1),
                                math.min(preset.b * 1.15, 1), 1))
                        imgui.PushStyleColor(imgui.Col.ButtonActive,
                            imgui.ImVec4(preset.r * 0.85, preset.g * 0.85, preset.b * 0.85, 1))
                        if imgui.Button(u8("##accentPreset" .. presetIdx), imgui.ImVec2(28, 28)) then
                            accentColorBuf[0] = preset.r
                            accentColorBuf[1] = preset.g
                            accentColorBuf[2] = preset.b
                            saveAccentColor()
                        end
                        imgui.PopStyleColor(3)
                        imgui.Hint(preset.name)
                    end

                    -- Вкладка 4: Помощь
                elseif data.settingsTab == 4 then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.28, 0.45, 1))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.30, 0.48, 1))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.22, 0.32, 0.50, 1))
                    if imgui.Button(fa.ARROW_UP_FROM_BRACKET .. "  " .. u8("Открыть в отдельном окне"),
                            imgui.ImVec2(-1, 28)) then
                        data.helpPage              = 1
                        data.helpWindowMode        = 'reference'
                        data.showSettingsWindow[0] = false
                        data.showHelpWindow[0]     = true
                    end
                    imgui.PopStyleColor(3)
                    imgui.Hint("Показать справку в отдельном перемещаемом окне.")
                    imgui.Spacing()
                    helpTool.renderReference()

                end
            end
            imgui.PopStyleColor()

            imgui.End()
        end
        if data.statsResetConfirm then
            renderResetConfirm(
                "statsResetConfirm",
                data.statsResetTimer,
                "Сбросить статистику дохода?",
                "Накопленные данные о доходах будут стёрты безвозвратно.",
                function()
                    resetIncomeRates()
                    data.statsResetConfirm = false
                end,
                function() data.statsResetConfirm = false end)
        end

        if data.settingsResetConfirm then
            renderResetConfirm(
                "settingsResetConfirm",
                data.settingsResetTimer,
                "Сбросить все настройки?",
                "Все ползунки и галочки вернутся к значениям по умолчанию.",
                function()
                    resetDefaultCfg()
                    data.settingsResetConfirm = false
                end,
                function() data.settingsResetConfirm = false end)
        end
    end
)

-- окно обновления
imgui.OnFrame(
    function() return updateState.showPopup[0] end,
    function(self)
        applyStyle()
        local sw, sh = getScreenResolution()
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2),
            imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(560, 0), imgui.Cond.Always)
        imgui.SetNextWindowFocus()

        if imgui.Begin("##updateWin", updateState.showPopup,
                imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar +
                imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove +
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.AlwaysAutoResize +
                imgui.WindowFlags.NoScrollWithMouse) then
            local winW  = imgui.GetWindowWidth()
            local style = imgui.GetStyle()

            imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.13, 0.16, 0.22, 0.25, 1))
            imgui.BeginChild("##updHeader", imgui.ImVec2(-1, 50), true,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

            local headerW = imgui.GetWindowWidth()
            local titleIcon = fa.ARROW_UP_FROM_BRACKET
            local titleText = u8 "Доступно обновление"

            local rowW = imgui.CalcTextSize(titleIcon).x
                + 12
                + imgui.CalcTextSize(titleText).x
            imgui.SetCursorPos(imgui.ImVec2((headerW - rowW) / 2, 14))
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 0.78, 0.20, 1.0))
            imgui.Text(titleIcon)
            imgui.PopStyleColor()
            imgui.SameLine(0, 12)
            imgui.TextColoredRGB("{FFFFFF}Доступно обновление")

            imgui.EndChild()
            imgui.PopStyleColor()

            imgui.Spacing()

            local cur     = tostring(script.this.version or "?")
            local new     = tostring(updateState.latestVersion or "?")

            local sLabelL = u8 "Текущая"
            local sLabelR = u8 "Новая"
            local arrow   = fa.ARROW_RIGHT
            local wLabelL = imgui.CalcTextSize(sLabelL).x
            local wLabelR = imgui.CalcTextSize(sLabelR).x
            local wArrow  = imgui.CalcTextSize(arrow).x
            local wCur    = imgui.CalcTextSize(cur).x
            local wNew    = imgui.CalcTextSize(new).x
            local rowW    = wLabelL + 8 + wCur + 18 + wArrow + 18 + wLabelR + 8 + wNew

            imgui.SetCursorPosX((winW - rowW) / 2)
            imgui.TextColoredRGB("{808080}" .. "Текущая")
            imgui.SameLine(0, 8)
            imgui.TextColoredRGB("{B0B0B0}" .. cur)
            imgui.SameLine(0, 18)
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 0.78, 0.20, 1.0))
            imgui.Text(arrow)
            imgui.PopStyleColor()
            imgui.SameLine(0, 18)
            imgui.TextColoredRGB("{BEF781}" .. "Новая")
            imgui.SameLine(0, 8)
            imgui.TextColoredRGB("{FFFFFF}" .. new)

            imgui.Spacing()
            imgui.Spacing()

            if updateState.changelog ~= "" then
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 0.65, 0.20, 1.0))
                imgui.Text(fa.CLOCK_ROTATE_LEFT)
                imgui.PopStyleColor()
                imgui.SameLine(0, 6)
                imgui.TextColoredRGB("{FFA500}Что нового")
                imgui.SameLine(0, 8)
                imgui.TextColoredRGB("{606060}— список изменений в новой версии")
                imgui.Spacing()

                imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.09, 0.10, 0.14, 0.25, 1))
                imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.20, 0.22, 0.28, 1))
                imgui.BeginChild("##updateChangelog", imgui.ImVec2(0, 150), true,
                    imgui.WindowFlags.NoScrollWithMouse)
                imgui.Scroller("update_changelog", 20, 300,
                    imgui.HoveredFlags.RectOnly + imgui.HoveredFlags.ChildWindows)
                imgui.TextColoredRGB(updateState.changelog)
                imgui.EndChild()
                imgui.PopStyleColor(2)

                imgui.Spacing()
            end

            local halfW = (winW - style.WindowPadding.x * 2 - style.ItemSpacing.x) / 2

            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.55, 0.22, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.25, 0.70, 0.28, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.12, 0.40, 0.15, 1))
            if imgui.Button(fa.DOWNLOAD .. u8 "  Обновить сейчас", imgui.ImVec2(halfW, 36)) then
                downloadAndUpdate()
            end
            imgui.PopStyleColor(3)
            imgui.Hint("Скачать и установить новую версию автоматически.\nСкрипт будет перезагружен.")

            imgui.SameLine()

            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.18, 0.22, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.26, 0.26, 0.30, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.13, 0.13, 0.16, 1))
            if imgui.Button(fa.CLOCK .. u8 "  Напомнить позже", imgui.ImVec2(halfW, 36)) then
                updateState.showPopup[0] = false
                updateState.postponeUntil = os.time() + 30 * 60
                updateState.flashOpenAsked = false
                updateState.declined     = false
                utils.addChat("{808080}Обновление отложено на 30 минут.")
            end
            imgui.PopStyleColor(3)
            imgui.Hint("Закрыть окно. Обновление можно будет установить позже из настроек.")

            imgui.Spacing()
            imgui.End()
        end
    end
)
-- окно логов
local _logsSaveT       = 0
local _logsActiveTab   = 0
local _logsPrevTab     = 0
local _logsTabHover    = {}
local _logsFlatRows    = nil
local _logsFlatSig     = nil

imgui.OnFrame(
    function() return data.showLogsWindow[0] end,
    function(self)
        applyStyle()
        local sw, sh = getScreenResolution()
        local desiredH = 645
        if _logsActiveTab ~= _logsPrevTab then
            imgui.SetNextWindowSize(imgui.ImVec2(720, desiredH), imgui.Cond.Always)
            _logsPrevTab = _logsActiveTab
        else
            imgui.SetNextWindowSize(imgui.ImVec2(720, desiredH), imgui.Cond.FirstUseEver)
        end
        imgui.SetNextWindowPos(
            imgui.ImVec2(cfg.logsWindowPosX * sw, cfg.logsWindowPosY * sh),
            imgui.Cond.FirstUseEver
        )

        local function renderLogEntry(entry, childPrefix, h)
            local eIcon, eLabel, eDetail = logsTool.format(entry)
            imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.09, 0.10, 0.14, 0.25, 1))
            imgui.BeginChild(childPrefix, imgui.ImVec2(0, h), true,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
            local ew   = imgui.GetWindowWidth()
            local posY = (h - imgui.GetTextLineHeight()) / 2
            imgui.SetCursorPos(imgui.ImVec2(8, posY))
            imgui.Text(fa.CLOCK)
            imgui.SameLine(0, 4)
            imgui.TextColoredRGB("{808080}" .. entry.time)
            imgui.SameLine(0, 8)
            imgui.Text(eIcon)
            imgui.SameLine(0, 4)
            imgui.TextColoredRGB("{FFFFFF}" .. eLabel)
            if eDetail ~= "" then
                local dw = imgui.CalcTextSize(u8(eDetail)).x
                if ew - dw - 10 > imgui.GetCursorPosX() + 5 then
                    imgui.SetCursorPos(imgui.ImVec2(ew - dw - 10, posY))
                    imgui.TextColoredRGB("{87CEFA}" .. eDetail)
                end
            end
            imgui.EndChild()
            imgui.PopStyleColor()
        end

        local function renderEmptyLogs()
            local availH = imgui.GetContentRegionAvail().y
            local lineH  = imgui.GetTextLineHeight()
            imgui.SetCursorPosY(imgui.GetCursorPosY() + availH / 2 - lineH * 2)
            local cW = imgui.GetWindowWidth()
            local iW = imgui.CalcTextSize(fa.BOX_OPEN).x
            imgui.SetCursorPosX((cW - iW) / 2)
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.25, 0.27, 0.32, 1))
            imgui.Text(fa.BOX_OPEN)
            imgui.PopStyleColor()
            imgui.Spacing()
            local lines = {
                { "{CCCCCC}", "Действий ещё не записано" },
                { "{808080}", "История появится после первого использования" },
            }
            for _, l in ipairs(lines) do
                imgui.SetCursorPosX(cW / 2 - imgui.CalcTextSize(u8(l[2])).x / 2)
                imgui.TextColoredRGB(l[1] .. l[2])
            end
        end

        if imgui.Begin("##logsWin", data.showLogsWindow,
                imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize +
                imgui.WindowFlags.NoTitleBar) then
            local wp = imgui.GetWindowPos()
            local nx, ny = wp.x / sw, wp.y / sh
            if math.abs(nx - cfg.logsWindowPosX) > 0.003 or math.abs(ny - cfg.logsWindowPosY) > 0.003 then
                cfg.logsWindowPosX, cfg.logsWindowPosY = nx, ny
                local t = os.clock()
                if t - _logsSaveT > 1.5 then
                    _logsSaveT = t; save()
                end
            end

            local imStyle = imgui.GetStyle()
            local winW = imgui.GetWindowWidth()

            imgui.SetCursorPosY(imStyle.ItemSpacing.y)
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.35, 0.10, 0.10, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.55, 0.15, 0.15, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.25, 0.07, 0.07, 1))
            if imgui.Button(fa.TRASH .. "##logsReset", imgui.ImVec2(40, 22)) then
                data.logsResetConfirm = true
                data.logsResetTimer   = os.clock()
            end
            imgui.PopStyleColor(3)
            imgui.Hint("Очистить все логи действий")

            local titleIcon = fa.CLOCK_ROTATE_LEFT
            local titleText = u8 "Логи"
            local iconW2 = imgui.CalcTextSize(titleIcon).x
            local textW2 = imgui.CalcTextSize(titleText).x
            local totalW2 = iconW2 + 8 + textW2
            imgui.SetCursorPos(imgui.ImVec2((winW - totalW2) / 2, imStyle.ItemSpacing.y + 3))
            imgui.Text(titleIcon)
            imgui.SameLine(0, 8)
            imgui.SetCursorPosY(imStyle.ItemSpacing.y + 3)
            imgui.TextColoredRGB("{FFFFFF}Логи")

            imgui.SetCursorPos(imgui.ImVec2(winW - 50 - imStyle.ItemSpacing.x, imStyle.ItemSpacing.y))
            if imgui.Button(fa.XMARK .. "##logsClose", imgui.ImVec2(40, 22)) then
                data.showLogsWindow[0] = false
            end
            imgui.Hint("Закрыть окно логов")
            imgui.Separator()

            local dates = {}
            for d in pairs(logsTool.getAllByDate()) do table.insert(dates, d) end
            table.sort(dates, function(a, b)
                local function key(s)
                    local d2, m2, y2 = s:match("(%d+)%.(%d+)%.(%d+)")
                    return string.format("%s%s%s", y2, m2, d2)
                end
                return key(a) > key(b)
            end)

            local cache         = logsTool.getCacheSummary()
            local totalSessions = cache.sessions
            local dailySums     = {}
            for _, dateStr in ipairs(dates) do
                local db, da, collectCount = 0, 0, 0
                for _, e in ipairs(logsTool.getEntriesByDate(dateStr)) do
                    db = db + (e.btc or 0)
                    da = da + (e.asc or 0)
                    local act = e.action or 'collect'
                    if act == 'collect' or act == 'fix' then collectCount = collectCount + 1 end
                end
                dailySums[dateStr] = {
                    btc = db,
                    asc = da,
                    count = #logsTool.getEntriesByDate(dateStr),
                    collectCount =
                        collectCount
                }
            end

            local tabW = (winW - imgui.GetStyle().WindowPadding.x * 2 - imgui.GetStyle().ItemSpacing.x * 1) / 2
            imgui.PushStyleColor(imgui.Col.Button,
                _logsActiveTab == 0 and accentRGBA(1) or accentTint(0.09, 0.10, 0.14, 0.25, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, accentShade(1.22, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, accentShade(1.45, 1))
            imgui.PushStyleColor(imgui.Col.Text,
                (_logsActiveTab == 0 or _logsTabHover[0]) and accentContrastVec() or imgui.ImVec4(1, 1, 1, 1))
            if imgui.Button(u8 "Общее", imgui.ImVec2(tabW, 28)) then _logsActiveTab = 0 end
            _logsTabHover[0] = imgui.IsItemHovered()
            imgui.PopStyleColor(4)
            imgui.SameLine()
            imgui.PushStyleColor(imgui.Col.Button,
                _logsActiveTab == 1 and accentRGBA(1) or accentTint(0.09, 0.10, 0.14, 0.25, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, accentShade(1.22, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, accentShade(1.45, 1))
            imgui.PushStyleColor(imgui.Col.Text,
                (_logsActiveTab == 1 or _logsTabHover[1]) and accentContrastVec() or imgui.ImVec4(1, 1, 1, 1))
            if imgui.Button(u8 "По дням", imgui.ImVec2(tabW, 28)) then _logsActiveTab = 1 end
            _logsTabHover[1] = imgui.IsItemHovered()
            imgui.PopStyleColor(4)
            imgui.Separator()
            if _logsActiveTab == 0 then
                imgui.Spacing()
                local colW = math.floor((winW - imgui.GetStyle().WindowPadding.x * 2 - imgui.GetStyle().ItemSpacing.x) *
                    0.38)

                -- Левая колонка: общая статистика
                imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.07, 0.08, 0.11, 0.25, 1))
                if imgui.BeginChild("##logsRightCol", imgui.ImVec2(colW, 0), true,
                        imgui.WindowFlags.NoScrollWithMouse) then
                    local periodLabels = { u8 "Всё время", u8 "Сегодня", u8 "Неделя", u8 "Месяц" }
                    imgui.PushItemWidth(-1)
                    if imgui.BeginCombo("##logsPeriod", periodLabels[data.logsPeriodFilter + 1]) then
                        for pi = 1, #periodLabels do
                            local pSel = data.logsPeriodFilter == pi - 1
                            if imgui.Selectable(periodLabels[pi], pSel) then
                                data.logsPeriodFilter = pi - 1
                            end
                        end
                        imgui.EndCombo()
                    end
                    imgui.PopItemWidth()
                    imgui.Spacing()
                    imgui.Separator()

                    local stats = logsTool.getStats(data.logsPeriodFilter)

                    local function StatRow(icon, label, value, color, hint)
                        imgui.BeginGroup()
                        imgui.Text(icon)
                        imgui.SameLine(0, 6)
                        imgui.TextColoredRGB("{808080}" .. label)
                        imgui.SameLine(0, 4)
                        imgui.TextColoredRGB((color or "{FFFFFF}") .. value)
                        imgui.EndGroup()
                        if hint then imgui.Hint(hint) end
                    end

                    imgui.TextColoredRGB("{87CEFA}Криптовалюта:")
                    StatRow(fa.COINS, "Получено BTC:", tostring(stats.btc), "{D2691E}",
                        "Суммарное количество BTC собранного со всех ферм")
                    StatRow(fa.COINS, "Получено ASC:", tostring(stats.asc), "{C0392B}",
                        "Суммарное количество ASC собранного со всех ферм")
                    StatRow(fa.ROTATE, "Сессий сбора:", tostring(stats.collectSessions), "{FFFFFF}",
                        "Количество запусков сбора криптовалюты")
                    imgui.Spacing()

                    imgui.TextColoredRGB("{87CEFA}Видеокарты:")
                    StatRow(fa.POWER_OFF, "Включено карт:", tostring(stats.switchOn), "{BEF781}",
                        "Суммарное количество включённых видеокарт за всё время")
                    StatRow(fa.PLUG, "Выключено карт:", tostring(stats.switchOff), "{F78181}",
                        "Суммарное количество выключённых видеокарт за всё время")
                    imgui.Spacing()

                    imgui.TextColoredRGB("{87CEFA}Охлаждение:")
                    StatRow(fa.DROPLET, "Карт залито:", tostring(stats.coolantCards), "{FFFFFF}",
                        "Количество видеокарт которым заливалась жидкость")

                    StatRow(fa.DROPLET, "Обычной:", stats.coolantBottles .. " шт.", "{87CEFA}",
                        "Количество флаконов обычной охлаждающей жидкости")

                    StatRow(fa.DROPLET, "Супер:", stats.coolantSuper .. " шт.", "{FFE133}",
                        "Количество флаконов супер охлаждающей жидкости")
                    imgui.Spacing()

                    imgui.TextColoredRGB("{87CEFA}Обслуживание:")

                    StatRow(fa.DOLLAR_SIGN, "Ферм пополнено на:", "$" .. utils.formatNumber(stats.topup), "{FFD700}",
                        "Общая сумма пополнений баланса домов")
                    imgui.Spacing()

                    imgui.TextColoredRGB("{87CEFA}Всего:")
                    StatRow(fa.CALENDAR_DAYS, "Дней активности:", string.format("%d", #dates), "{FFFFFF}",
                        "Количество дней в которые были зафиксированы действия")
                    StatRow(fa.CLOCK_ROTATE_LEFT, "Записей:", string.format("%d", totalSessions), "{FFFFFF}",
                        "Общее количество записей в логах")

                    imgui.EndChild()
                end
                imgui.PopStyleColor()

                imgui.SameLine()

                -- Правая колонка: лог по дням
                imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.07, 0.08, 0.11, 0.25, 1))
                if imgui.BeginChild("##logsLeftCol", imgui.ImVec2(0, 0), true, imgui.WindowFlags.NoScrollWithMouse) then
                    if #dates == 0 then
                        renderEmptyLogs()
                    else
                        imgui.Scroller("logs_main", 30, 400,
                            imgui.HoveredFlags.RectOnly + imgui.HoveredFlags.ChildWindows)
                        local sig = tostring(totalSessions) .. "|" .. tostring(#dates)
                        if _logsFlatSig ~= sig then
                            _logsFlatRows = {}
                            local rows = _logsFlatRows
                            for _, dateStr in ipairs(dates) do
                                local ds = dailySums[dateStr]
                                rows[#rows + 1] = { kind = 'header', date = dateStr, count = ds.count }
                                local dayEntries = logsTool.getEntriesByDate(dateStr)
                                for j = #dayEntries, 1, -1 do
                                    rows[#rows + 1] = {
                                        kind   = 'entry',
                                        entry  = dayEntries[j],
                                        prefix = "allentry_" .. dateStr .. "_" .. j,
                                    }
                                end
                            end
                            _logsFlatSig = sig
                        end

                        local rows = _logsFlatRows
                        local clipper = imgui.ImGuiListClipper()
                        clipper:Begin(#rows)
                        while clipper:Step() do
                            for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                                local r = rows[i]
                                if r.kind == 'header' then
                                    imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.11, 0.13, 0.18, 0.25, 1))
                                    imgui.BeginChild("dayhead_" .. r.date, imgui.ImVec2(0, 30), true,
                                        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                                    imgui.SetCursorPos(imgui.ImVec2(8, (30 - imgui.GetTextLineHeight()) / 2))
                                    imgui.Text(fa.CALENDAR_DAYS)
                                    imgui.SameLine(0, 6)
                                    imgui.TextColoredRGB("{FFFFFF}" .. r.date)
                                    imgui.SameLine(0, 10)
                                    imgui.TextColoredRGB(string.format("{808080}%d %s", r.count, ruPlural(r.count, "запись", "записи", "записей")))
                                    imgui.EndChild()
                                    imgui.PopStyleColor()
                                else
                                    renderLogEntry(r.entry, r.prefix, 30)
                                end
                            end
                        end
                    end
                    imgui.EndChild()
                end
                imgui.PopStyleColor()
            elseif _logsActiveTab == 1 then
                imgui.Spacing()
                if #dates == 0 then
                    renderEmptyLogs()
                else
                    -- Левая панель: список дат
                    imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.09, 0.10, 0.14, 0.25, 1))
                    if imgui.BeginChild("##daysLeft", imgui.ImVec2(190, 0), true,
                            imgui.WindowFlags.NoScrollWithMouse) then
                        imgui.Scroller("logs_days_left", 54, 300,
                            imgui.HoveredFlags.RectOnly + imgui.HoveredFlags.ChildWindows)
                        for i, dateStr in ipairs(dates) do
                            local isSelected = (data.logsTab[0] == i - 1)
                            local ds = dailySums[dateStr]

                            -- независимый прозрачный цвет выделения дня (не связан с акцентным цветом, чтобы не менялся вместе с другими вкладками)
                            imgui.PushStyleColor(imgui.Col.Header, imgui.ImVec4(0.55, 0.13, 0.13, 0.45))
                            imgui.PushStyleColor(imgui.Col.HeaderHovered,
                                imgui.ImVec4(0.68, 0.18, 0.18, 0.55))

                            if imgui.Selectable("##sel_" .. dateStr, isSelected,
                                    0, imgui.ImVec2(0, 50)) then
                                data.logsTab[0] = i - 1
                            end
                            imgui.PopStyleColor(2)

                            local cp = imgui.GetItemRectMin()
                            local dl2 = imgui.GetWindowDrawList()
                            if isSelected then
                                dl2:AddRectFilled(
                                    cp,
                                    imgui.ImVec2(cp.x + 3, cp.y + 50),
                                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.85, 0.22, 0.22, 1.0))
                                )
                            end

                            imgui.SetCursorScreenPos(
                                imgui.ImVec2(cp.x + 8, cp.y + 4))
                            imgui.TextColoredRGB(
                                (isSelected and "{FFFFFF}" or "{DDDDDD}") .. dateStr)
                            imgui.SetCursorScreenPos(
                                imgui.ImVec2(cp.x + 8, cp.y + 21))
                            local dayListAsc = ""
                            if ds.asc > 0 then
                                dayListAsc = string.format(" %s| {C0392B}%d ASC",
                                    isSelected and "{FFFFFF}" or "{FFFFFF}", ds.asc)
                            end
                            imgui.TextColoredRGB(
                                string.format("{D2691E}%d BTC", ds.btc) .. dayListAsc)
                            imgui.SetCursorScreenPos(
                                imgui.ImVec2(cp.x + 8, cp.y + 36))
                            imgui.TextColoredRGB(
                                string.format("{808080}%d %s", ds.count, ruPlural(ds.count, "запись", "записи", "записей")))
                        end
                        imgui.EndChild()
                    end
                    imgui.PopStyleColor()

                    imgui.SameLine(0, 8)

                    -- Правая панель: записи выбранного дня
                    local selDate = dates[data.logsTab[0] + 1]
                    local selEntries = selDate and logsTool.getEntriesByDate(selDate) or {}
                    if selDate and #selEntries > 0 then
                        local ds = dailySums[selDate]
                        if imgui.BeginChild("##daysRight", imgui.ImVec2(0, 0), false) then
                            -- Шапка дня
                            imgui.PushStyleColor(imgui.Col.ChildBg,
                                accentTint(0.09, 0.10, 0.14, 0.25, 1))
                            imgui.BeginChild("##dayHeader", imgui.ImVec2(0, 44), true,
                                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                            local _lineH = imgui.GetTextLineHeight()
                            local _row1Y = math.floor((44 - _lineH * 2 - 4) / 2)
                            local _row2Y = _row1Y + _lineH + 4
                            imgui.SetCursorPos(imgui.ImVec2(10, _row1Y))
                            imgui.Text(fa.CALENDAR_DAYS)
                            imgui.SameLine(0, 6)
                            imgui.TextColoredRGB("{FFFFFF}" .. selDate)
                            imgui.SetCursorPos(imgui.ImVec2(10, _row2Y))
                            local dayHeaderAsc = ""
                            if ds.asc > 0 then
                                dayHeaderAsc = string.format(" {FFFFFF}| {C0392B}%d ASC", ds.asc)
                            end
                            imgui.TextColoredRGB(
                                string.format("{D2691E}%d BTC", ds.btc) .. dayHeaderAsc ..
                                string.format("  {808080}·  {FFFFFF}%d сборов  {808080}·  {FFFFFF}%d записей",
                                    ds.collectCount, ds.count))
                            imgui.EndChild()
                            imgui.PopStyleColor()

                            imgui.Spacing()

                            -- Список записей
                            if imgui.BeginChild("##dayEntries", imgui.ImVec2(0, 0), false, imgui.WindowFlags.NoScrollWithMouse) then
                                imgui.Scroller("logs_day_entries", 34, 400,
                                    imgui.HoveredFlags.RectOnly + imgui.HoveredFlags.ChildWindows)
                                local nEnt    = #selEntries
                                local clipper = imgui.ImGuiListClipper()
                                clipper:Begin(nEnt)
                                while clipper:Step() do
                                    for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                                        local j = nEnt - i + 1
                                        renderLogEntry(selEntries[j], "entry_" .. selDate .. "_" .. j, 34)
                                    end
                                end
                                imgui.EndChild()
                            end
                            imgui.EndChild()
                        end
                    end
                end
            end
            if data.logsResetConfirm then
                renderResetConfirm(
                    "logsResetConfirm",
                    data.logsResetTimer,
                    "Удалить все логи действий?",
                    "Это действие необратимо.",
                    function()
                        logsTool.clear()
                        utils.addChat("{F78181}Логи очищены.")
                        data.logsResetConfirm = false
                    end,
                    function() data.logsResetConfirm = false end)
            end
            imgui.End()
        end
    end
)

-- при заходе на ферму
-- Управление курсором ImGui: рисовать только когда открыто хотя бы одно окно скрипта,
-- чтобы избежать мерцания/двоения курсора с курсором SAMP/игры.
imgui.OnFrame(function() return data.main[0] end, function(self)
    applyCustomStyle()
    local w, h = getScreenResolution()
    local windowSize = imgui.ImVec2(480.0, 323.0)
    local margin_right = 0.0
    local y_percent_top = 0.40

    local posX = w - windowSize.x - margin_right
    local posY = h * y_percent_top

    posX = math.max(0, math.min(posX, w - windowSize.x))
    posY = math.max(0, math.min(posY, h - windowSize.y))

    imgui.SetNextWindowSize(windowSize, imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(posX, posY), imgui.Cond.Always)

    if imgui.Begin("##main_windos", data.main, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar +
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar +
            imgui.WindowFlags.NoMove) then
        imgui.customTitleBar(data.main, resetDefaultCfg, imgui.GetWindowWidth())

        __i__main()
        imgui.showNotifications(2)
        imgui.End()
    end
end)

function __i__main()
    imgui.BeginChild('##top_panel_unified', imgui.ImVec2(0, 104), true, imgui.WindowFlags.NoScrollbar)
    imgui.Columns(2, "##main_columns_unified", false, imgui.WindowFlags.NoScrollbar)
    imgui.SetColumnWidth(0, 255)
    -- Левая колонка с информацией
    __i__infoPanel()
    imgui.NextColumn()
    -- Правая колонка с кнопками управления
    __i__controlPanel()

    imgui.Columns(1)
    imgui.EndChild()

    -- Нижняя панель
    __i__bottomPanel()
end

function __i__infoPanel()
    imgui.BeginChild('##info_panel_child', imgui.ImVec2(0, -1), false, imgui.WindowFlags.NoScrollbar)
    local title_text = data.forImgui.dTitle or "Ожидание..."
    -- imgui.TextColoredRGB('{ffffff}Дом: {ffa500}№ ' .. title_text)
    imgui.TextColoredRGB('{ffffff}Статус фермы: ' ..
        (data.forImgui.allGood and '{BEF781}Всё хорошо.' or '{F78181}Требует внимания.'))
    imgui.TextColoredRGB('{ffffff}Количество видеокарт: {99ff99}' .. data.forImgui.videocardCount)
    imgui.TextColoredRGB('{ffffff}Можно снять: {D2691E}' ..
        data.forImgui.earnings.btc .. ' BTC' ..
        (not data.isRodina and ' {ffffff}|| {c0392b}' .. data.forImgui.earnings.asc .. ' ASC' or ''))
    imgui.EndChild()
end

function __i__controlPanel()
    local availableWidth = imgui.GetContentRegionAvail().x
    local buttonSide = ((availableWidth - imgui.GetStyle().ItemSpacing.x) / 2) - 2
    local buttonSize = imgui.ImVec2(buttonSide, buttonSide - 5)

    if data.isFlashminer then
        if ButtonWithHint(fa.ARROW_LEFT .. "##left", "Переключиться на предыдущую ферму.",
                not data.working, buttonSize) then
            flashminerTool.navigate(-1)
        end

        imgui.SameLine(0, imgui.GetStyle().ItemSpacing.x + 5)

        if ButtonWithHint(fa.ARROW_RIGHT .. "##right", "Переключиться на следующую ферму.",
                not data.working, buttonSize) then
            flashminerTool.navigate(1)
        end
    else
        ButtonWithHint(fa.ARROW_LEFT .. "##left_disabled", "Доступно только в Флешке Майнера.",
            false, buttonSize)
        imgui.SameLine(0, imgui.GetStyle().ItemSpacing.x + 5)
        ButtonWithHint(fa.ARROW_RIGHT .. "##right_disabled", "Доступно только в Флешке Майнера.",
            false, buttonSize)
    end
end

function __i__bottomPanel()
    imgui.BeginChild('##bottom_panel_child', imgui.ImVec2(0, 0), false, imgui.WindowFlags.NoScrollbar)

    local style = imgui.GetStyle()
    local textLineHeight = imgui.GetTextLineHeight()
    local sliderHeight = textLineHeight + style.FramePadding.y * 2
    local staticContentHeight = (textLineHeight * 2) + sliderHeight + (style.ItemSpacing.y * 2)

    local availableHeight = imgui.GetContentRegionAvail().y
    local dynamicHeight = availableHeight - staticContentHeight
    local elementHeight = (dynamicHeight - (style.ItemSpacing.y * 3)) / 4 - 1

    if elementHeight < 20 then elementHeight = 20 end

    -- Ряд 1: Кнопка "Снять криптовалюту"
    local canWithdraw = data.forImgui.earnings.btc >= 1 or data.forImgui.earnings.asc >= 1
    local withdrawHint = canWithdraw and "Снять всю доступную криптовалюту" or "Нет криптовалюты для снятия"
    if data.working then withdrawHint = "Дождитесь завершения текущей операции" end

    if ButtonWithHint(u8 "Снять криптовалюту", withdrawHint,
            canWithdraw and not data.working, imgui.ImVec2(-1, elementHeight)) then
        coolantTool.resetSupplyFlag()
        local task = buildTaskTable('takeCrypto')
        task:takeCrypto()
    end

    -- Ряд 2: Кнопки "Включить/Выключить"
    local halfButtonWidth = (imgui.GetContentRegionAvail().x - style.ItemSpacing.x) / 2

    local switchOnHint = data.working and "Дождитесь завершения текущей операции" or "Включить все видеокарты"
    if ButtonWithHint(u8 "Включить видеокарты", switchOnHint, not data.working,
            imgui.ImVec2(halfButtonWidth, elementHeight)) then
        local task = buildTaskTable('switchCards')
        task:switchCards(true)
    end

    imgui.SameLine()

    local switchOffHint = data.working and "Дождитесь завершения текущей операции" or "Выключить все видеокарты"
    if ButtonWithHint(u8 "Выключить видеокарты", switchOffHint, not data.working,
            imgui.ImVec2(halfButtonWidth, elementHeight)) then
        local task = buildTaskTable('switchCards')
        task:switchCards(false)
    end

    -- Ряд 3: Кнопка "Залить жидкость"
    local canRefill = not data.isFlashminer and not data.working
    local coolantHint
    if data.isFlashminer then
        coolantHint = "Недоступно в флешке майнера"
    elseif data.working then
        coolantHint = "Дождитесь завершения текущей операции"
    else
        coolantHint = "Залить охлаждающую жидкость во все видеокарты"
    end


    if ButtonWithHint(u8 "Залить жидкость", coolantHint, canRefill, imgui.ImVec2(-1, elementHeight)) then
        local task = buildTaskTable('coolant')
        task:coolant()
    end

    -- Ряд 4: Чекбоксы.
    local cursorY_before = imgui.GetCursorPosY()
    imgui.Dummy(imgui.ImVec2(-1, elementHeight))
    local cursorY_after = imgui.GetCursorPosY()

    local checkboxHeight = textLineHeight + style.FramePadding.y * 2
    imgui.SetCursorPosY(cursorY_before + (elementHeight - checkboxHeight) / 2)

    if imgui.Checkbox(u8 "Использовать Супер Охлаждающую Жидкость", imcfg.useSuperCoolant) then
        cfg.useSuperCoolant = imcfg.useSuperCoolant[0]; save()
    end
    imgui.Hint("Использовать Супер Охлаждающую Жидкость вместо обычной.\n(Для  BTC карт и Asic Miner)")
    imgui.SameLine()
    if imgui.Checkbox(u8 "Режим Экономии##econom", imcfg.economyMode) then
        cfg.economyMode = imcfg.economyMode[0]; save()
    end
    imgui.Hint(
        "Включает экономию охлаждающей жидкости.\nРаботает только с обычными жидкостями и вне Вайс-Сити (и не для суперохлаждающих).\nКак это работает: если посли заливки одной жидкости уровень охлаждения достигает 70 и выше, то вторая жидкость не расходуется.\nБез этого режима скрипт всегда заполняет охлаждение до 100%.")

    imgui.SetCursorPosY(cursorY_after)

    imgui.Text(u8 "Порог срабатывания заливки:")
    imgui.TextDisabled(u8 "Если процент охлаждающей жидкости < настроенной ниже, то заливаем.")
    imgui.PushItemWidth(-1)
    if imgui.SliderInt("##coolantPercent", imcfg.useCoolantPercent, 1, 100, u8 "%d%%") then
        cfg.useCoolantPercent = imcfg.useCoolantPercent[0]; save()
    end
    imgui.PopItemWidth()

    imgui.EndChild()
end

-- при флешке майнера
local _fashFrame      = 0
local _fashMemoFrame  = -1
local _fashMemoHouses = nil
local _fashMemoLevels = nil
local _fashMemoCities = nil

local function filterAndSortHouses(houses)
    if _fashMemoFrame == _fashFrame and _fashMemoHouses ~= nil then
        return _fashMemoHouses, _fashMemoLevels, _fashMemoCities
    end
    local searchText = ffi.string(searchBuffer):lower()
    local filtered = {}

    local availableLevels = {}
    local levelsSet = {}
    for _, house in ipairs(houses) do
        local status = data.houseStatuses[house.house_number]
        if status and status.cardLevels then
            for lvl in pairs(status.cardLevels) do
                if not levelsSet[lvl] then
                    levelsSet[lvl] = true
                    table.insert(availableLevels, lvl)
                end
            end
        end
    end
    table.sort(availableLevels)

    local availableCities = {}
    local citiesSet = {}
    for _, house in ipairs(houses) do
        local city = (house.city and house.city ~= "") and house.city or "Неизвестно"
        if not citiesSet[city] then
            citiesSet[city] = true
            table.insert(availableCities, city)
        end
    end
    table.sort(availableCities)

    for _, house in ipairs(houses) do
        local status = data.houseStatuses[house.house_number]
        local isKnownNoBasement = houseFilter.hasNoBasement(house.house_number)
        local isExcluded = houseFilter.isExcluded(house.house_number)

        if not imcfg.showExcludedHouses[0] and isExcluded then
            goto continue
        end

        local matchSearch = searchText == "" or
            tostring(house.house_number):find(searchText, 1, true) or
            (house.city and house.city:lower():find(searchText, 1, true))
        if not matchSearch then goto continue end

        if currentStatusFilter[0] > 0 then
            local statusType = houseStatusHelper:determineStatus(house, status,
                cfg.excludedHouses[tostring(house.house_number)] or false, isKnownNoBasement)
            if currentStatusFilter[0] == 1 and statusType ~= 'good' then goto continue end
            if currentStatusFilter[0] == 2 and statusType ~= 'warning' then goto continue end
            if currentStatusFilter[0] == 3 and statusType ~= 'bad' then goto continue end
            if currentStatusFilter[0] == 4 and not isKnownNoBasement then goto continue end
        end

        local hasAnySelected = next(selectedCardLevels) ~= nil
        if hasAnySelected then
            local matchesAny = false
            for lvl, sel in pairs(selectedCardLevels) do
                if sel and status and status.cardLevels and status.cardLevels[lvl] then
                    matchesAny = true; break
                end
            end
            if not matchesAny then goto continue end
        end

        if next(selectedCities) ~= nil then
            local houseCity = (house.city and house.city ~= "") and house.city or "Неизвестно"
            local isCityToggled = selectedCities[houseCity] == true
            if data.cityFilterInvert then
                if not isCityToggled then goto continue end
            else
                if isCityToggled then goto continue end
            end
        end

        table.insert(filtered, house)
        ::continue::
    end

    -- Сортировка
    local sortIdx = imcfg.currentSort[0]
    if sortIdx == 0 then
        table.sort(filtered, function(a, b)
            if a.house_number == b.house_number then return false end
            if cfg.sortAscending then return a.house_number < b.house_number end
            return a.house_number > b.house_number
        end)
    elseif sortIdx == 1 then
        table.sort(filtered, function(a, b)
            local va, vb = a.balance or 0, b.balance or 0
            if va == vb then return a.house_number < b.house_number end
            if cfg.sortAscending then return va < vb end
            return va > vb
        end)
    elseif sortIdx == 2 then
        -- Циклы
        table.sort(filtered, function(a, b)
            local va, vb = a.cycles or 0, b.cycles or 0
            if va == vb then return a.house_number < b.house_number end
            if cfg.sortAscending then return va < vb end
            return va > vb
        end)
    elseif sortIdx == 3 then
        -- Жидкость
        table.sort(filtered, function(a, b)
            local sA = data.houseStatuses[a.house_number]
            local sB = data.houseStatuses[b.house_number]
            local va = (sA and sA.minCoolant) or 101
            local vb = (sB and sB.minCoolant) or 101
            if va == vb then return a.house_number < b.house_number end
            if cfg.sortAscending then return va < vb end
            return va > vb
        end)
    elseif sortIdx == 4 then
        -- Видеокарты
        table.sort(filtered, function(a, b)
            local sA = data.houseStatuses[a.house_number]
            local sB = data.houseStatuses[b.house_number]
            local countA, countB = 0, 0
            local hasSelected = next(selectedCardLevels) ~= nil
            if hasSelected then
                for lvl, sel in pairs(selectedCardLevels) do
                    if sel then
                        countA = countA +
                            ((sA and sA.cardLevels and sA.cardLevels[lvl] and sA.cardLevels[lvl].total) or 0)
                        countB = countB +
                            ((sB and sB.cardLevels and sB.cardLevels[lvl] and sB.cardLevels[lvl].total) or 0)
                    end
                end
            else
                if sA and sA.cardLevels then for _, v in pairs(sA.cardLevels) do countA = countA + v.total end end
                if sB and sB.cardLevels then for _, v in pairs(sB.cardLevels) do countB = countB + v.total end end
            end
            if countA == countB then return a.house_number < b.house_number end
            if cfg.sortAscending then return countA < countB end
            return countA > countB
        end)
    elseif sortIdx == 5 then
        -- Город
        table.sort(filtered, function(a, b)
            local va, vb = a.city or "", b.city or ""
            if va == vb then return a.house_number < b.house_number end
            if cfg.sortAscending then return va < vb end
            return va > vb
        end)
    end
    _fashMemoFrame  = _fashFrame
    _fashMemoHouses = filtered
    _fashMemoLevels = availableLevels
    _fashMemoCities = availableCities
    return filtered, availableLevels, availableCities
end

-- флешка майнера
imgui.OnFrame(function() return data.showHouseControlWindow[0] end, function(player)
    _fashFrame = _fashFrame + 1
    if not cfg.helpShown and not cfg.useDialogMode then
        data.setupPage         = 1
        data.helpWindowMode    = 'setup'
        data.showHelpWindow[0] = true
        cfg.helpShown          = true
        save()
    end
    applyStyle()
    if updatePopupShouldShow() and not updateState.flashOpenAsked then
        updateState.flashOpenAsked = true
        updatePopupOpen(false)
    end
    local sw, sh = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(1000, 680), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))

    if imgui.Begin(u8 "Mining Tools##MainWin", data.showHouseControlWindow,
            imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize) then
        imgui.customTitleBar(data.showHouseControlWindow, resetDefaultCfg, imgui.GetWindowWidth())

        local filteredHouses, availableLevels, availableCities = filterAndSortHouses(data.dialogData.flashminer)
        data.filteredHouses = filteredHouses
        -- Подсчет статистики
        local totalHouses = #data.dialogData.flashminer
        local housesGood, housesWarning, housesBad = 0, 0, 0
        local totalBalance, totalBTC, totalASC = 0, 0, 0
        local badHousesIssues = {}
        local warningHousesIssues = {}
        local totalCoolantsAll = 0

        for _, house in ipairs(data.dialogData.flashminer) do
            local status = data.houseStatuses[house.house_number]
            totalBalance = totalBalance + (house.balance or 0)

            if status then
                totalCoolantsAll = totalCoolantsAll + (status.coolantsNeeded or 0)
            end

            if not (status and status.lastCheck > 0) then goto continue end

            local earnings = status.earnings or {}
            local houseIsVC = house.city and house.city:find("Vice City", 1, true) ~= nil
            if data.isViceCity == houseIsVC then
                totalBTC = totalBTC + (earnings.btc or 0)
                totalASC = totalASC + (earnings.asc or 0)
            end

            local counters = { good = housesGood, warning = housesWarning, bad = housesBad }
            local issuesTables = { warning = warningHousesIssues, bad = badHousesIssues }

            if counters[status.status] then
                counters[status.status] = counters[status.status] + 1

                if issuesTables[status.status] and status.issues and #status.issues > 0 then
                    issuesTables[status.status][house.house_number] = status.issues
                end
            end

            housesGood, housesWarning, housesBad = counters.good, counters.warning, counters.bad

            ::continue::
        end

        local nearestMaintenanceHours = nil
        local nearestMaintenanceHouse = nil
        for _, house in ipairs(data.dialogData.flashminer) do
            if houseFilter.shouldProcess(house) then
                local status = data.houseStatuses[house.house_number]
                if status and status.lastCheck > 0 and status.minCoolant and status.minCoolant <= 100 then
                    local hours = utils.calculateRemainingHours(status.minCoolant)
                    if not nearestMaintenanceHours or hours < nearestMaintenanceHours then
                        nearestMaintenanceHours = hours
                        nearestMaintenanceHouse = house.house_number
                    end
                end
            end
        end

        -- Расчет общего дохода
        local allBtc, allAsc, incomeDays = logsTool.getAverageDailyIncome(data.isViceCity)
        if incomeDays == 0 then
            allBtc, allAsc = 0, 0
            for _, h in ipairs(data.dialogData.flashminer) do
                local hIsVC = h.city and h.city:find("Vice City", 1, true) ~= nil
                if data.isViceCity == hIsVC then
                    local b, a = houseFilter.getDailyIncome(h.house_number)
                    allBtc = allBtc + b
                    allAsc = allAsc + a
                end
            end
        end

        -- Плитки статистики
        local availWidth = imgui.GetContentRegionAvail().x
        local statCardWidth = (availWidth - 24) / 4

        local function DrawStatTile(childId, icon, label, value, valColor, hintText)
            imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.09, 0.10, 0.14, 0.25, 1.00))
            imgui.BeginChild("stat_" .. childId, imgui.ImVec2(statCardWidth, 36), true)

            local iconSize = imgui.CalcTextSize(icon)
            local labelParsed = label:gsub("{.-}", "")
            local labelSize = imgui.CalcTextSize(u8(labelParsed))
            local valueParsed = value:gsub("{.-}", "")
            local valueSize = imgui.CalcTextSize(u8(valueParsed))
            local totalWidth = iconSize.x + labelSize.x + valueSize.x + 10

            local startX = (statCardWidth - totalWidth) / 2
            local lineH = imgui.GetTextLineHeight()
            local startY = (36 - lineH) / 2

            imgui.SetCursorPos(imgui.ImVec2(startX, startY))

            imgui.BeginGroup()
            imgui.Text(icon)
            imgui.SameLine()
            imgui.TextColoredRGB(label)
            imgui.SameLine()
            imgui.TextColoredRGB(valColor .. value)
            imgui.EndGroup()

            if hintText then
                imgui.Hint(hintText)
            end

            imgui.EndChild()
            imgui.PopStyleColor()
        end


        -- Колонка 1: Общая информация
        DrawStatTile("houses", fa.HOUSE, "{87CEFA}Всего домов:", tostring(totalHouses), "{FFFFFF}",
            "Общее количество домов")
        imgui.SameLine()

        -- Колонка 2: Криптовалюта
        local cryptoText = formatEarnings(totalBTC, totalASC, not data.isRodina)
        local totalHint = string.format(
            "{FFFFFF}Общее количество криптовалюты для снятия.\n\n{BEF781}Общий доход всех ферм:\n{D2691E}%.3f BTC / день\n{C0392B}%.3f ASC / день",
            allBtc, allAsc)

        DrawStatTile("crypto", fa.COINS, "{BEF781}Доступно:", cryptoText, "{FFFFFF}", totalHint)
        imgui.SameLine()

        -- Колонка 3: Общий баланс
        DrawStatTile("balance", fa.DOLLAR_SIGN, "{FFD700}Баланс:", "$" .. utils.formatNumber(totalBalance),
            "{FFFFFF}",
            "Общий баланс всех домов")
        imgui.SameLine()

        -- Колонка 4: Статусы домов
        local parts = {}
        if housesGood > 0 then table.insert(parts, string.format("{4DE94C}%d", housesGood)) end
        if housesWarning > 0 then table.insert(parts, string.format("{FFE133}%d", housesWarning)) end
        if housesBad > 0 then table.insert(parts, string.format("{FF3333}%d", housesBad)) end

        local statusText = #parts > 0 and table.concat(parts, " {FFFFFF}/ ") or "{808080}Не проверено"

        local hintLines = {
            "{FFFFFF}Сводка по состоянию домов:",
            "--------------------",
        }

        local function appendIssues(title, issuesMap)
            table.insert(hintLines, title)
            for houseNum, issues in pairs(issuesMap) do
                table.insert(hintLines, "  {FFA500}Дом №" .. houseNum .. ":")
                for _, issue in ipairs(issues) do
                    table.insert(hintLines, "    • " .. issue)
                end
            end
            table.insert(hintLines, "")
        end

        local hasIssues = false
        if next(badHousesIssues) ~= nil then
            hasIssues = true
            appendIssues(fa.CIRCLE_EXCLAMATION .. " {FF3333}Критические проблемы:", badHousesIssues)
        end
        if next(warningHousesIssues) ~= nil then
            hasIssues = true
            appendIssues(fa.TRIANGLE_EXCLAMATION .. " {FFE133}Требуют внимания:", warningHousesIssues)
        end
        if not hasIssues then
            table.insert(hintLines, fa.CIRCLE_CHECK .. " {4DE94C}Проблем не обнаружено.")
            table.insert(hintLines, "")
        end

        table.insert(hintLines, "--------------------")
        table.insert(hintLines, string.format(
            "{87CEFA}Всего требуется охлаждаек: {FFFFFF}%d шт.", totalCoolantsAll))


        local statusHint = table.concat(hintLines, "\n")

        DrawStatTile("status", fa.CHART_PIE, "{87CEFA}Состояние:", statusText, "{FFFFFF}", statusHint)


        local cache            = logsTool.getCacheSummary()
        local logTotalBtc      = cache.collectBtc
        local logTotalAsc      = cache.collectAsc
        local logTotalSessions = cache.sessions

        imgui.Spacing()

        local barH = 30
        local isLogsHovered = false

        imgui.PushStyleColor(imgui.Col.ChildBg,
            data.showLogsWindow[0]
            and accentShade(1.3, 1.00)
            or accentTint(0.09, 0.10, 0.14, 0.25, 1.00))
        imgui.BeginChild("##logsSummaryBar", imgui.ImVec2(0, barH), true,
            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

        local ww = imgui.GetWindowWidth()

        imgui.SetCursorPos(imgui.ImVec2(12, (barH - imgui.GetTextLineHeight()) / 2))
        imgui.BeginGroup()
        imgui.Text(fa.CLOCK_ROTATE_LEFT)
        imgui.SameLine(0, 6)

        local summaryStr
        if logTotalSessions == 0 then
            summaryStr = u8 "Нет записей"
        else
            summaryStr = u8(string.format("Собрано за всё время: %d BTC", logTotalBtc))
            if logTotalAsc > 0 then
                summaryStr = summaryStr .. u8(string.format("  /  %d ASC", logTotalAsc))
            end
            summaryStr = summaryStr .. u8(string.format("   ·   %d записей", logTotalSessions))
        end
        imgui.Text(summaryStr)
        imgui.EndGroup()

        local arrowIcon = data.showLogsWindow[0] and fa.CHEVRON_UP or fa.CHEVRON_DOWN
        local arrowW = imgui.CalcTextSize(arrowIcon).x
        imgui.SetCursorPos(imgui.ImVec2(ww - arrowW - 14, (barH - imgui.GetTextLineHeight()) / 2))
        imgui.TextDisabled(arrowIcon)

        imgui.SetCursorPos(imgui.ImVec2(0, 0))
        if imgui.InvisibleButton("##logsBarBtn", imgui.ImVec2(ww, barH)) then
            data.showLogsWindow[0] = not data.showLogsWindow[0]
        end
        isLogsHovered = imgui.IsItemHovered()
        if isLogsHovered then
            imgui.SetTooltip(u8(data.showLogsWindow[0] and "Закрыть историю" or "Открыть историю"))
        end

        imgui.EndChild()
        imgui.PopStyleColor()
        imgui.Spacing()

        imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.09, 0.10, 0.14, 0.25, 1.00))
        imgui.BeginChild("##action_panel", imgui.ImVec2(0, 60), true)
        imgui.showNotifications(2)

        local btnWidth = (availWidth - 55) / 5
        local btnHeight = 35

        local function DrawActionBtn(label, icon, colorVec, taskName, arg)
            imgui.PushStyleColor(imgui.Col.Button, colorVec)
            imgui.PushStyleColor(imgui.Col.ButtonHovered,
                imgui.ImVec4(colorVec.x * 1.2, colorVec.y * 1.2, colorVec.z * 1.2, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,
                imgui.ImVec4(colorVec.x * 0.8, colorVec.y * 0.8, colorVec.z * 0.8, 1.0))

            local pressed = imgui.Button(icon .. " " .. u8(label), imgui.ImVec2(btnWidth, btnHeight))
            imgui.PopStyleColor(3)

            if pressed then
                if data.selectedHouseIndex and data.dialogData.flashminer[data.selectedHouseIndex] then
                    data.lastSelectedHouse = data.dialogData.flashminer[data.selectedHouseIndex].house_number
                end

                local task = buildTaskTable(taskName)
                runTaskAndReopenDialog(function() task:run(arg) end)
            end

            return pressed
        end

        DrawActionBtn("Собрать", fa.DOLLAR_SIGN, imgui.ImVec4(0.3, 0.8, 0.3, 1), "collectFromAllHouses")
        imgui.Hint("Собрать криптовалюту со всех домов")

        imgui.SameLine()
        DrawActionBtn("Включить", fa.POWER_OFF, imgui.ImVec4(0.2, 0.6, 1, 1), "massSwitchCards", true)
        imgui.Hint("Включить все видеокарты во всех домах")

        imgui.SameLine()
        DrawActionBtn("Выключить", fa.PLUG, imgui.ImVec4(1, 0.3, 0.3, 1), "massSwitchCards", false)
        imgui.Hint("Выключить все видеокарты во всех домах")

        imgui.SameLine()
        DrawActionBtn("Обновить", fa.ROTATE, imgui.ImVec4(0.8, 0.6, 0.2, 1), "updateStatuses")
        imgui.Hint("Обновить статусы всех домов.\nНе проверяет наличие подвалов.")

        imgui.SameLine()
        local fixLabel, fixIcon, fixColor, fixHint
        if cfg.useSimpleTopUp then
            fixLabel = "Пополнить баланс"
            fixIcon  = fa.DOLLAR_SIGN
            fixColor = imgui.ImVec4(0.4, 0.7, 0.4, 1)
            fixHint  = "Пополнить баланс ферм до целевого значения"
        else
            fixLabel    = "Авто-обслуживание"
            fixIcon     = fa.GEAR
            fixColor    = imgui.ImVec4(0.6, 0.4, 0.9, 1)
            local parts = {}
            if cfg.fixCollectEnabled then table.insert(parts, "Собрать криптовалюту") end
            if cfg.fixSwitchEnabled then table.insert(parts, "Включить видеокарты") end
            if cfg.fixTopUpEnabled then table.insert(parts, "Пополнить баланс ферм") end
            if #parts == 0 then
                fixHint = "{F78181}Не выбрано ни одного действия.\n{808080}Включите их в настройках в вкладке «Фермы»."
            else
                fixHint = table.concat(parts, "\n")
            end
        end
        local fixTaskName = cfg.useSimpleTopUp and "autoTopUp" or "fixAllProblems"
        DrawActionBtn(fixLabel, fixIcon, fixColor, fixTaskName)
        imgui.Hint(fixHint)

        imgui.EndChild()
        imgui.PopStyleColor()

        imgui.Text(u8(string.format("Список домов (%d из %d)", #filteredHouses, totalHouses)))
        imgui.SameLine()
        imgui.SetCursorPosX(imgui.GetWindowWidth() - 220)
        if imgui.Checkbox(u8 "Режим исключённых", imcfg.showExcludedHouses) then
            cfg.showExcludedHouses = imcfg.showExcludedHouses[0]
            _fashFrame = _fashFrame + 1
            save()
        end
        imgui.Hint("Режим исключённых: ПКМ на доме, чтобы убрать исключение")
        imgui.Spacing()
        if data.working then
            __i__progressPanel()
        else
            if imgui.BeginChild("##scrollArea", imgui.ImVec2(0, 0), false, imgui.WindowFlags.NoScrollWithMouse) then
                local itemHeight = 130
                imgui.Scroller("house_list", itemHeight, 400,
                    imgui.HoveredFlags.RectOnly + imgui.HoveredFlags.ChildWindows)

                if data.scrollToSelection then
                    local targetIndex = nil
                    for i, house in ipairs(filteredHouses) do
                        if data.selectedHouseIndex then
                            local selectedHouse = data.dialogData.flashminer[data.selectedHouseIndex]
                            if selectedHouse and house.house_number == selectedHouse.house_number then
                                targetIndex = i
                                break
                            end
                        end
                    end

                    if targetIndex then
                        local columns = 2
                        local rowIndex = math.ceil(targetIndex / columns)
                        local targetScroll = (rowIndex - 1) * itemHeight
                        local scrollMax = imgui.GetScrollMaxY()

                        if targetScroll < 0 then targetScroll = 0 end
                        if targetScroll > scrollMax then targetScroll = scrollMax end

                        imgui.ScrollToPosition("house_list", targetScroll, 400)
                    end

                    data.scrollToSelection = false
                end

                local columns = 2
                local spacing = 10
                local regionW = imgui.GetContentRegionAvail().x
                local cardW = (regionW - spacing * (columns - 1)) / columns
                local cardH = 136

                for i, house in ipairs(filteredHouses) do
                    local status = data.houseStatuses[house.house_number]
                    local isKnownNoBasement = houseFilter.hasNoBasement(house.house_number)
                    local isExcluded = houseFilter.isExcluded(house.house_number)

                    local statusType
                    if isExcluded then
                        statusType = 'excluded'
                    else
                        statusType = houseStatusHelper:determineStatus(house, status, isExcluded, isKnownNoBasement)
                    end

                    local statusColor
                    local statusIcon
                    if isKnownNoBasement then
                        statusColor = imgui.ImVec4(0.5, 0.5, 0.5, 1.0)
                        statusIcon = fa.XMARK
                    elseif statusType == 'excluded' then
                        statusColor = imgui.ImVec4(0.38, 0.42, 0.60, 1.0)
                        statusIcon = fa.BAN
                    else
                        statusColor = houseStatusHelper:getColor(statusType)
                        statusIcon = houseStatusHelper:getIcon(statusType)
                    end

                    local tooltipText = houseStatusHelper:buildTooltip(status, house, isKnownNoBasement)
                    local stripeColor = statusColor

                    local statusText = ""
                    if isKnownNoBasement then
                        statusText = "{808080}Нет подвала"
                    elseif isExcluded then
                        statusText = "{808080}Пропускается"
                    elseif statusType == 'good' then
                        statusText = "{4DE94C}Работает"
                    elseif statusType == 'warning' then
                        statusText = "{FFE133}Внимание"
                    elseif statusType == 'bad' then
                        statusText = "{FF3333}Проблема"
                    else
                        statusText = "{808080}Не проверено"
                    end

                    if (i - 1) % columns ~= 0 then imgui.SameLine(0, spacing) end

                    imgui.PushStyleColor(imgui.Col.ChildBg, accentTint(0.12, 0.13, 0.17, 0.25, 1.00))
                    imgui.BeginChild("house_card_" .. i, imgui.ImVec2(cardW, cardH), false)
                    local barW = 140
                    local rightColX = cardW - barW - 10
                    local p = imgui.GetCursorScreenPos()
                    local dl = imgui.GetWindowDrawList()

                    local maxGlowWidth = 30
                    local glowSteps = 25

                    for step = glowSteps, 1, -1 do
                        local progress = step / glowSteps
                        local width = 4 + (maxGlowWidth * progress)
                        local alpha = 0.25 * (1 - progress) * progress * 2

                        local layerColor = imgui.ImVec4(
                            stripeColor.x,
                            stripeColor.y,
                            stripeColor.z,
                            alpha
                        )

                        dl:AddRectFilled(
                            imgui.ImVec2(p.x, p.y),
                            imgui.ImVec2(p.x + width, p.y + cardH),
                            imgui.ColorConvertFloat4ToU32(layerColor),
                            6.0,
                            5
                        )
                    end
                    dl:AddRectFilled(
                        imgui.ImVec2(p.x, p.y),
                        imgui.ImVec2(p.x + 4, p.y + cardH),
                        imgui.ColorConvertFloat4ToU32(stripeColor),
                        6.0,
                        5
                    )

                    -- Контент карточки
                    imgui.SetCursorPos(imgui.ImVec2(16, 8))

                    -- Строка 1: Дом и Город
                    imgui.BeginGroup()
                    imgui.Text(fa.HOUSE)
                    imgui.SameLine()
                    imgui.TextColoredRGB(string.format("{FFFFFF}Дом {FFA500}№%d {FFFFFF}- %s", house.house_number,
                        house.city or "Неизвестно"))
                    imgui.EndGroup()
                    imgui.Hint("ПКМ для дополнительных действий")

                    imgui.SameLine()
                    -- Циклы справа
                    if not isKnownNoBasement and house.cycles then
                        imgui.BeginGroup()
                        local cyclesColor = house.cycles > 100 and "{4DE94C}" or "{FFE133}"
                        local cyclesStr = string.format("%s%d {808080}цикл.", cyclesColor, house.cycles)
                        imgui.SetCursorPosX(rightColX)
                        imgui.Text(fa.ROTATE)
                        imgui.SameLine(0, 3)
                        imgui.TextColoredRGB(cyclesStr)
                        imgui.EndGroup()
                        imgui.Hint("Количество оплаченных циклов")
                    end

                    -- Строка 2: Статус и Баланс

                    imgui.SetCursorPos(imgui.ImVec2(16, 32))
                    imgui.BeginGroup()
                    imgui.Text(statusIcon)
                    imgui.SameLine()
                    imgui.TextColoredRGB(statusText)
                    imgui.EndGroup()
                    imgui.Hint(tooltipText)

                    imgui.SameLine()
                    local balStr = string.format("{FFFFFF}$%s", utils.formatNumber(house.balance or 0))
                    imgui.SetCursorPosX(rightColX)
                    imgui.BeginGroup()
                    imgui.TextColored(imgui.ImVec4(1.0, 0.84, 0.0, 1.0), fa.DOLLAR_SIGN)
                    imgui.SameLine(0, 3)
                    imgui.TextColoredRGB(balStr)
                    imgui.EndGroup()
                    imgui.Hint(string.format("Баланс дома: $%s / $%s",
                        utils.formatNumber(house.balance or 0),
                        utils.formatNumber(house.max_balance or 0)))

                    -- Строка 3: Криптовалюта и Налог

                    imgui.SetCursorPos(imgui.ImVec2(16, 52))
                    imgui.BeginGroup()
                    imgui.TextColored(imgui.ImVec4(0.75, 0.97, 0.51, 1.0), fa.COINS)
                    imgui.SameLine()
                    imgui.Text(u8 "Крипта:")
                    imgui.SameLine()

                    if not isKnownNoBasement then
                        if status and status.lastCheck > 0 and status.earnings then
                            local earnings = formatEarnings(
                                status.earnings.btc >= 1 and status.earnings.btc or 0,
                                status.earnings.asc >= 1 and status.earnings.asc or 0,
                                not data.isRodina
                            )
                            if earnings == "{808080}0" then
                                earnings = "{808080}Нет"
                            end
                            imgui.TextColoredRGB(earnings)
                            imgui.EndGroup()
                        else
                            imgui.TextColoredRGB("{808080}Не проверено")
                            imgui.EndGroup()
                        end
                    else
                        imgui.TextColoredRGB("{808080}Нет данных")
                        imgui.EndGroup()
                    end


                    -- Налог
                    imgui.SameLine()
                    imgui.SetCursorPosX(rightColX)
                    imgui.BeginGroup()

                    imgui.Text(fa.FILE_INVOICE_DOLLAR)
                    imgui.SameLine()
                    imgui.Text(u8 "Налог:")
                    imgui.SameLine()
                    if house.tax then
                        local taxColor = house.tax >= 90000 and "{FF3333}" or
                            (house.tax >= 50000 and "{FFE133}" or "{FFFFFF}")
                        imgui.TextColoredRGB(taxColor .. "$" .. utils.formatNumber(house.tax))
                    else
                        imgui.TextColoredRGB("{808080}Н/Д")
                    end
                    imgui.EndGroup()
                    imgui.Hint("Текущий налог на дом")

                    -- Строка 4: Видеокарты и Жидкость
                    imgui.SetCursorPos(imgui.ImVec2(16, 72))
                    imgui.BeginGroup()
                    -- Видеокарты
                    local totalCards, workingCards = 0, 0
                    local hasCardData = status and status.lastCheck > 0 and status.cardLevels and
                        next(status.cardLevels)

                    if hasCardData then
                        for _, counts in pairs(status.cardLevels) do
                            totalCards = totalCards + counts.total
                            workingCards = workingCards + counts.working
                        end
                    end

                    if hasCardData and totalCards > 0 then
                        local cardColor = (workingCards == totalCards) and "{BEF781}" or "{FFE133}"
                        local cardText = string.format('{ffffff}Карты: %s%d/%d', cardColor, totalCards, 20)

                        local tooltipLines = {}
                        table.insert(tooltipLines, string.format("Работают: %d из %d", workingCards, totalCards))
                        table.insert(tooltipLines, "--------------------")

                        local levelParts = {}
                        local sortedLevels = {}
                        for level in pairs(status.cardLevels) do table.insert(sortedLevels, level) end
                        table.sort(sortedLevels)

                        for _, level in ipairs(sortedLevels) do
                            table.insert(levelParts,
                                string.format("• %d уровень: %d шт.", level, status.cardLevels[level].total))
                        end

                        if #levelParts > 0 then
                            table.insert(tooltipLines, "Уровни установленных карт:")
                            for _, part in ipairs(levelParts) do
                                table.insert(tooltipLines, part)
                            end
                        else
                            table.insert(tooltipLines, "Нет данных об уровнях карт.")
                        end

                        local cardTooltip = table.concat(tooltipLines, "\n")
                        imgui.Text(fa.MICROCHIP)
                        imgui.SameLine()
                        imgui.TextColoredRGB(cardText)
                        imgui.EndGroup()
                        imgui.Hint(cardTooltip)
                    else
                        imgui.Text(fa.MICROCHIP)
                        imgui.SameLine()
                        imgui.TextColoredRGB("{808080}Карты: нет данных")
                        imgui.EndGroup()
                    end

                    imgui.SameLine()
                    local barW = 140
                    imgui.SetCursorPosX(rightColX)
                    imgui.SetCursorPosY(imgui.GetCursorPosY() + 2)

                    if not isKnownNoBasement then
                        if status and status.lastCheck > 0 and status.minCoolant <= 100 then
                            local coolantFraction = status.minCoolant / 100.0
                            local barColor
                            local threshold = cfg.useCoolantPercent / 100.0
                            local midpoint = threshold + (1.0 - threshold) / 2.0
                            if coolantFraction < threshold then
                                barColor = imgui.ImVec4(1, 0.2, 0.2, 1)
                            elseif coolantFraction < midpoint then
                                barColor = imgui.ImVec4(1, 0.88, 0.2, 1)
                            else
                                barColor = imgui.ImVec4(0.3, 0.8, 1, 1)
                            end

                            local needed = status.coolantsNeeded or 0
                            local barLabel = u8(string.format("%.1f%%", status.minCoolant))
                            imgui.PushStyleColor(imgui.Col.PlotHistogram, barColor)
                            imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.2, 0.2, 0.2, 1.0))
                            imgui.ProgressBar(coolantFraction, imgui.ImVec2(barW, 15), barLabel)
                            imgui.PopStyleColor(2)

                            if needed > 0 then
                                imgui.SetCursorPosX(rightColX)
                                imgui.TextColoredRGB(string.format(
                                    "{FF6B6B}Долить: %d шт.", needed))
                            end

                            local currentNeeded = status.coolantsNeeded or 0
                            local targetText = cfg.economyMode and "до 70%" or "до 100%"

                            local hasAsic = false
                            if status.cardLevels then
                                for _, lvl in pairs(status.cardLevels) do
                                    if (lvl.btc and lvl.btc.total > 0) and (lvl.asc and lvl.asc.total > 0) then
                                        hasAsic = true; break
                                    end
                                end
                            end

                            local coolantHint = string.format(
                                "{FFFFFF}Минимальный уровень жидкости: {ffa500}%.2f%%\n" ..
                                "{FFFFFF}Порог заливки: {ffa500}%d%%\n" ..
                                "{FFFFFF}Цель заливки: {ffa500}%s\n\n",
                                status.minCoolant, cfg.useCoolantPercent, targetText
                            )

                            if currentNeeded > 0 then
                                coolantHint = coolantHint ..
                                    string.format("{BEF781}Требуется охл. жидкости: {FFFFFF}%d шт.", currentNeeded)
                            else
                                coolantHint = coolantHint .. "{808080}Заливка не требуется (выше порога)."
                            end

                            if hasAsic then
                                coolantHint = coolantHint .. "\n{FFA500}Есть ASIC карты (BTC+ASC)"
                            end

                            imgui.Hint(coolantHint)
                        else
                            imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.2, 0.2, 0.2, 1.0))
                            imgui.ProgressBar(0, imgui.ImVec2(barW, 15), u8 "Нет данных")
                            imgui.PopStyleColor()
                        end
                    else
                        imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.2, 0.2, 0.2, 1.0))
                        imgui.ProgressBar(0, imgui.ImVec2(barW, 15), u8 "Нет подвала")
                        imgui.PopStyleColor()
                    end

                    -- Строка 5: Время работы
                    imgui.SetCursorPos(imgui.ImVec2(16, 110))
                    imgui.BeginGroup()
                    imgui.EndGroup()

                    if isExcluded then
                        imgui.SameLine()
                        imgui.SetCursorPosX(cardW - 140)
                        imgui.BeginGroup()
                        imgui.TextColored(imgui.ImVec4(1.0, 0.42, 0.42, 1.0), fa.BAN)
                        imgui.SameLine()
                        imgui.TextColoredRGB("{FF6B6B}Пропускается")
                        imgui.EndGroup()
                        imgui.Hint("Дом будет пропущен во всех массовых действиях")
                    end

                    local isSelected = false
                    local isHovered = false

                    if data.selectedHouseIndex then
                        local selectedHouse = data.dialogData.flashminer[data.selectedHouseIndex]
                        if selectedHouse and selectedHouse.house_number == house.house_number then
                            isSelected = true
                        end
                    end

                    imgui.SetCursorPos(imgui.ImVec2(0, 0))
                    local isClickable = not isKnownNoBasement
                    if isClickable then
                        if imgui.InvisibleButton("btn_house_" .. i, imgui.ImVec2(cardW, cardH)) then
                            for origIdx, origHouse in ipairs(data.dialogData.flashminer) do
                                if origHouse.house_number == house.house_number then
                                    data.selectedHouseIndex = origIdx
                                    data.lastSelectedHouse = house.house_number
                                    setPendingHouseNumber(house.house_number)
                                    sampSendDialogResponse(data.dFlashminerId, 1, origHouse.index - 1, "")
                                    data.showHouseControlWindow[0] = false
                                    break
                                end
                            end
                        end

                        if imgui.IsItemHovered() then
                            for origIdx, origHouse in ipairs(data.dialogData.flashminer) do
                                if origHouse.house_number == house.house_number then
                                    data.selectedHouseIndex = origIdx
                                    data.lastSelectedHouse = house.house_number
                                    break
                                end
                            end
                        end
                    else
                        imgui.InvisibleButton("btn_placeholder_" .. i, imgui.ImVec2(cardW, cardH))
                    end

                    if isSelected or isHovered then
                        local cardPos = imgui.GetItemRectMin()
                        local dl = imgui.GetWindowDrawList()
                        dl:AddRectFilled(
                            cardPos,
                            imgui.ImVec2(cardPos.x + cardW, cardPos.y + cardH),
                            imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.2, 0.6, 1.0, 0.15)),
                            6.0
                        )
                    end

                    if imgui.IsItemHovered() then
                        if imgui.IsMouseClicked(1) then
                            imgui.OpenPopup("house_context_menu_" .. house.house_number)
                        end
                    end

                    if imgui.BeginPopup("house_context_menu_" .. house.house_number) then
                        imgui.TextColoredRGB(string.format("{FFA500}Дом №%d {808080}— %s",
                            house.house_number, house.city or "Неизвестно"))
                        imgui.Separator()

                        local excluded = houseFilter.isExcluded(house.house_number)
                        local houseStr = tostring(house.house_number)

                        if imgui.MenuItemBool(u8(excluded and "Снять метку 'Пропускать'" or "Пропускать дом"), nil, excluded) then
                            cfg.excludedHouses[houseStr] = not excluded and true or nil
                            save()
                        end

                        if imgui.MenuItemBool(u8 "Найти дом (/findihouse)") then
                            sampSendChat(string.format("/findihouse %d", house.house_number))
                        end

                        if not data.working then
                            imgui.Separator()
                            if imgui.MenuItemBool(u8 "Обновить статус этого дома") then
                                lua_thread.create(function()
                                    taskState.setWorking(true); data.taskTypeNow = 'updateStatuses'
                                    local sr = function(...) sampSendDialogResponse(...) end
                                    data.dialogData.videocards = {}
                                    dialogActions.selectHouse(sr, house.index - 1)
                                    wait(400)
                                    dialogActions.closeDialog(sr)
                                    wait(200)
                                    taskState.setWorking(false); data.taskTypeNow = nil
                                    imgui.addNotification(u8(string.format("Дом №%d обновлён", house.house_number)))
                                end)
                            end
                            if not houseFilter.isExcluded(house.house_number) and not houseFilter.hasNoBasement(house.house_number) then
                                if imgui.MenuItemBool(u8 "Зайти в дом") then
                                    sampSendDialogResponse(data.dFlashminerId, 1, house.index - 1, "")
                                    data.showHouseControlWindow[0] = false
                                end
                            end
                        end
                        imgui.EndPopup()
                    end

                    imgui.EndChild()
                    imgui.PopStyleColor()
                end
                imgui.EndChild()
            end

            imgui.End()
        end

        imgui.End()
    end
end)

function __i__progressPanel()
    imgui.BeginChild("##progress_panel", imgui.ImVec2(0, 0), true)

    local availWidth = imgui.GetContentRegionAvail().x
    local availHeight = imgui.GetContentRegionAvail().y
    local centerX = availWidth / 2
    local centerY = availHeight / 2

    local targetOuter = data.progressTotal > 0 and (data.progressCurrent / data.progressTotal) or 0
    targetOuter = math.min(math.max(targetOuter, 0), 1)
    local targetInner = data.progressHouseTotal > 0 and (data.progressHouseCurrent / data.progressHouseTotal) or 0
    targetInner = math.min(math.max(targetInner, 0), 1)

    local currentTime = os.clock()
    local deltaTime = math.min(currentTime - (data.progressSmooth.lastUpdateTime or currentTime), 0.1)
    data.progressSmooth.lastUpdateTime = currentTime

    local newOuter, newOuterVel = smoothDamp(data.progressSmooth.outer, targetOuter, data.progressSmooth.outerVelocity,
        deltaTime, 0.15)
    local newInner, newInnerVel = smoothDamp(data.progressSmooth.inner, targetInner, data.progressSmooth.innerVelocity,
        deltaTime, 0.12)
    data.progressSmooth.outer = newOuter
    data.progressSmooth.outerVelocity = newOuterVel
    data.progressSmooth.inner = newInner
    data.progressSmooth.innerVelocity = newInnerVel

    local drawList = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local absCenter = imgui.ImVec2(p.x + centerX, p.y + centerY - 60)

    DrawDoubleProgressCircle(absCenter, 55, 40, 10, data.progressSmooth.outer, data.progressSmooth.inner)

    local percentText = string.format("%.0f%%", data.progressSmooth.outer * 100)
    local percentSize = imgui.CalcTextSize(percentText)
    drawList:AddText(
        imgui.ImVec2(absCenter.x - percentSize.x / 2, absCenter.y - percentSize.y / 2),
        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.95, 0.96, 0.98, 1.0)), percentText)

    local descriptions = {
        scanBasements = "Сканирование подвалов...",
        updateStatuses = "Обновление данных...",
        collectFromAllHouses = "Массовый сбор...",
        fixAllProblems = "Авто-обслуживание...",
        massSwitchCards = "Переключение карт...",
        autoTopUp = "Пополнение балансов...",
        coolant = "Заливка жидкостей..."
    }
    local taskText = u8(descriptions[data.taskTypeNow] or "Выполнение...")
    if data.taskTypeNow == 'autoTopUp' or (data.taskTypeNow == 'fixAllProblems' and cfg.useSimpleTopUp) then
        taskText = u8 "Пополнение балансов..."
    end
    local taskTextSize = imgui.CalcTextSize(taskText)
    local taskTextY = absCenter.y + 55 + 15
    drawList:AddText(imgui.ImVec2(p.x + centerX - taskTextSize.x / 2, taskTextY),
        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.7, 0.7, 0.7, 1.0)), taskText)

    local counterText = u8(string.format("Дом: %d / %d", data.progressCurrent,
        data.progressTotal > 0 and data.progressTotal or 0))
    local counterSize = imgui.CalcTextSize(counterText)
    local counterY = taskTextY + taskTextSize.y + 8
    drawList:AddText(imgui.ImVec2(p.x + centerX - counterSize.x / 2, counterY),
        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.5, 0.5, 0.5, 1.0)), counterText)

    if data.progressHouseTotal > 0 then
        local houseText = u8(string.format("Карта: %d / %d", data.progressHouseCurrent, data.progressHouseTotal))
        local houseSize = imgui.CalcTextSize(houseText)
        local houseY = counterY + counterSize.y + 6
        drawList:AddText(imgui.ImVec2(p.x + centerX - houseSize.x / 2, houseY),
            imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.3, 0.8, 0.3, 1.0)), houseText)
    end

    local btnOffsetY = data.isWaitingPayday and (centerY + 85) or (centerY + 60)
    imgui.SetCursorPos(imgui.ImVec2(centerX - 100, btnOffsetY))

    if data.isWaitingPayday then
        local lastCounterY = counterY + counterSize.y + 6
        if data.progressHouseTotal > 0 then
            local houseLineH = imgui.GetTextLineHeight()
            lastCounterY = lastCounterY + houseLineH + 6
        end

        if data.isWaitingPayday then
            local pdText = u8 "Ожидание PayDay..."
            local pdSize = imgui.CalcTextSize(pdText)
            drawList:AddText(
                imgui.ImVec2(p.x + centerX - pdSize.x / 2, lastCounterY + 6),
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 0.88, 0.2, 1.0)),
                pdText
            )
        end
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.8, 0.2, 0.2, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1.0, 0.3, 0.3, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.6, 0.1, 0.1, 1.0))
        if imgui.Button(fa.STOP .. u8 " Остановить", imgui.ImVec2(95, 40)) then
            data.stopAction = true
            data.skipPayday = true
        end
        imgui.PopStyleColor(3)

        imgui.SameLine(0, 8)

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.7, 0.55, 0.1, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.9, 0.7, 0.15, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.5, 0.4, 0.08, 1.0))
        if imgui.Button(fa.FORWARD_STEP .. u8 " Пропустить", imgui.ImVec2(95, 40)) then
            data.skipPayday = true
            data.paydaySkippedAt = os.time()
        end
        imgui.PopStyleColor(3)
    else
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.8, 0.2, 0.2, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1.0, 0.3, 0.3, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.6, 0.1, 0.1, 1.0))
        if imgui.Button(fa.STOP .. u8 " Остановить", imgui.ImVec2(200, 40)) then
            data.stopAction = true
        end
        imgui.PopStyleColor(3)
    end

    imgui.EndChild()
end

function imgui.customTitleBar(param, resetFunc, windowWidth)
    local imStyle = imgui.GetStyle()

    imgui.SetCursorPosY(imStyle.ItemSpacing.y + 5)
    imgui.SameLine()
    -- РџСЂР°РІР°СЏ СЃС‚РѕСЂРѕРЅР° Р·Р°РЅСЏС‚Р°: СЃСЃС‹Р»РєР° (280px) + РєРЅРѕРїРєР° РјРµРЅСЋ (50px) + РєРЅРѕРїРєР° Р·Р°РєСЂС‹С‚СЊ (50px) + РѕС‚СЃС‚СѓРїС‹
    -- Р›РµРІР°СЏ СЃС‚РѕСЂРѕРЅР° РїСѓСЃС‚Р°СЏ, РїРѕСЌС‚РѕРјСѓ С†РµРЅС‚СЂРёСЂСѓРµРј РѕС‚РЅРѕСЃРёС‚РµР»СЊРЅРѕ РІСЃРµРіРѕ РѕРєРЅР°
    local rightReserved = 30 + 50 + 50 + imStyle.ItemSpacing.x * 4
    local leftReserved = imStyle.WindowPadding.x
    local centerZone = windowWidth - leftReserved - rightReserved
    local titleX = leftReserved + math.max(0, centerZone / 2 - imgui.CalcTextSize(script.this.name).x / 2)
    if data.isViceCity then
        titleX = titleX - 20
    end
    imgui.SetCursorPosX(titleX)
    imgui.TextColoredRGB(script.this.name)
    if data.isViceCity then
        imgui.SameLine(0, 6)
        imgui.SetCursorPosY(imStyle.ItemSpacing.y + 5)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.4, 0.8, 1.0, 1.0))
        imgui.Text("VC")
        imgui.PopStyleColor()
        imgui.Hint("Вы находитесь в Vice City.\nОбычная охлаждающая жидкость работает как супер (100%).")
    end

    imgui.SameLine()

    imgui.SetCursorPosX(windowWidth - 168 - imStyle.ItemSpacing.x)
    imgui.SetCursorPosY(imStyle.ItemSpacing.y)
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.2, 0.2, 0.3, 0.5))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.25, 0.25, 0.35, 0.7))
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.90, 0.20, 0.20, 1.0))
    if imgui.Button(fa('HEART') .. '##bounteiro_link', imgui.ImVec2(30, 25)) then
        imgui.SetClipboardText("https://t.me/b0unteiro")
        imgui.addNotification("t.me/b0unteiro copied!")
    end
    imgui.PopStyleColor(4)
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.TextColored(imgui.ImVec4(0.90, 0.20, 0.20, 1.0), fa("HEART") .. " Fixed by bounteiro")
        imgui.TextColored(imgui.ImVec4(0.6, 0.6, 0.6, 1.0), "t.me/b0unteiro")
        imgui.TextColored(imgui.ImVec4(0.5, 0.5, 0.5, 1.0), "Click to copy link")
        imgui.EndTooltip()
    end
    imgui.SameLine()

    imgui.SetCursorPosX(windowWidth - 110 - imStyle.ItemSpacing.x)
    imgui.SetCursorPosY(imStyle.ItemSpacing.y)
    if imgui.Button(fa("BARS") .. "##settings_button", imgui.ImVec2(50, 25)) then
        data.showSettingsWindow[0] = not data.showSettingsWindow[0]
    end

    imgui.SameLine()

    imgui.SetCursorPosX(windowWidth - 50 - imStyle.ItemSpacing.x)
    imgui.SetCursorPosY(imStyle.ItemSpacing.y)
    if imgui.ButtonClickable("Подождите...", not data.working, fa("XMARK") .. "##close_button", imgui.ImVec2(50, 25)) then
        fixI()
        param[0] = false
        data.showSettingsWindow[0] = false
    end

    if imgui.BeginPopup("donationPopupMenu") then
        imgui.Text(u8("Fixed by bounteiro"), 0xFF3333E6, 0xFF2222CC)
        if imgui.Link("t.me/b0unteiro", u8 "Нажми чтобы скопировать") then
            imgui.SetClipboardText("https://t.me/b0unteiro")
            imgui.addNotification(u8 "Ссылка скопирована!")
        end
        imgui.EndPopup()
    end
end

local notifications = {}

function imgui.addNotification(text)
    table.insert(notifications, {
        text = text,
        startTime = os.clock()
    })
end

function imgui.showNotifications(duration)
    local currentTime = os.clock()
    local activeNotifications = #notifications

    -- Начинаем отображение подсказок, если есть активные уведомления
    if activeNotifications ~= 0 then
        imgui.BeginTooltip()
    end
    for i = #notifications, 1, -1 do
        local notification = notifications[i]
        -- Проверяем, прошло ли время показа
        if currentTime - notification.startTime < duration then
            imgui.Text(notification.text)
            activeNotifications = activeNotifications + 1
            -- Если это не последнее уведомление, добавляем разделитель
            if i > 1 then
                imgui.Separator()
            end
        else
            table.remove(notifications, i)
        end
    end

    if activeNotifications ~= 0 then
        imgui.EndTooltip()
    end
end

imgui.Scroller = {
    _ids = {},
}

setmetatable(imgui.Scroller, {
    __call = function(self, id, step, duration, HoveredFlags)
        if not HoveredFlags then
            HoveredFlags = imgui.HoveredFlags.RectOnly
        end

        if not imgui.Scroller._ids[id] then
            imgui.Scroller._ids[id] = {}
        end

        local current_position = imgui.GetScrollY()

        if (imgui.IsWindowHovered(HoveredFlags) and imgui.IsMouseDown(0)) then
            imgui.Scroller._ids[id].start_clock = nil
        end

        if imgui.Scroller._ids[id].start_clock then
            local elapsed = (os.clock() - imgui.Scroller._ids[id].start_clock) * 1000

            if elapsed <= duration then
                local progress = elapsed / duration
                local fading_progress = progress * (2 - progress)
                local distance = imgui.Scroller._ids[id].target_position - imgui.Scroller._ids[id].start_position
                local new_position = imgui.Scroller._ids[id].start_position + distance * fading_progress

                if new_position < 0 then
                    new_position = 0
                    imgui.Scroller._ids[id].start_clock = nil
                elseif new_position > imgui.GetScrollMaxY() then
                    new_position = imgui.GetScrollMaxY()
                    imgui.Scroller._ids[id].start_clock = nil
                end

                imgui.SetScrollY(math.floor(new_position))
            else
                imgui.Scroller._ids[id].start_clock = nil
                imgui.SetScrollY(imgui.Scroller._ids[id].target_position)
            end
        end

        local wheel_delta = imgui.GetIO().MouseWheel

        if wheel_delta ~= 0 and imgui.IsWindowHovered(HoveredFlags) then
            local offset = -wheel_delta * step

            if not imgui.Scroller._ids[id].start_clock then
                imgui.Scroller._ids[id].start_clock = os.clock()
                imgui.Scroller._ids[id].start_position = current_position
                imgui.Scroller._ids[id].target_position = current_position + offset
            else
                imgui.Scroller._ids[id].start_clock = os.clock()
                imgui.Scroller._ids[id].start_position = current_position

                if imgui.Scroller._ids[id].start_position < imgui.Scroller._ids[id].target_position and offset > 0 then
                    imgui.Scroller._ids[id].target_position = imgui.Scroller._ids[id].target_position + offset
                elseif imgui.Scroller._ids[id].start_position > imgui.Scroller._ids[id].target_position and offset < 0 then
                    imgui.Scroller._ids[id].target_position = imgui.Scroller._ids[id].target_position + offset
                else
                    imgui.Scroller._ids[id].target_position = current_position + offset
                end
            end
        end
    end
})

function imgui.ScrollToPosition(id, targetPosition, duration)
    if not imgui.Scroller._ids[id] then
        imgui.Scroller._ids[id] = {}
    end

    local current_position = imgui.GetScrollY()
    imgui.Scroller._ids[id].start_clock = os.clock()
    imgui.Scroller._ids[id].start_position = current_position
    imgui.Scroller._ids[id].target_position = targetPosition
end

function imgui.TextColoredRGB(text)
    local style = imgui.GetStyle()
    local colors = style.Colors
    local ImVec4 = imgui.ImVec4

    local explode_argb = function(argb)
        local a = bit.band(bit.rshift(argb, 24), 0xFF)
        local r = bit.band(bit.rshift(argb, 16), 0xFF)
        local g = bit.band(bit.rshift(argb, 8), 0xFF)
        local b = bit.band(argb, 0xFF)
        return a, r, g, b
    end

    local getcolor = function(color)
        if color:sub(1, 6):upper() == 'SSSSSS' then
            local r, g, b = colors[1].x, colors[1].y, colors[1].z
            local a = tonumber(color:sub(7, 8), 16) or colors[1].w * 255
            return ImVec4(r, g, b, a / 255)
        end
        local color = type(color) == 'string' and tonumber(color, 16) or color
        if type(color) ~= 'number' then return end
        local r, g, b, a = explode_argb(color)
        return imgui.ImVec4(r / 255, g / 255, b / 255, a / 255)
    end

    local render_text = function(text_)
        local function startsWithFA(str)
            if not str or #str < 3 then return false end
            local b1, b2 = string.byte(str, 1), string.byte(str, 2)
            return b1 == 0xEF and b2 >= 0x80 and b2 <= 0xA3
        end

        for w in text_:gmatch('[^\r\n]+') do
            w = w:gsub('{(......)}', '{%1FF}')

            local lineIcon = nil
            local lineText = w

            if startsWithFA(w) then
                lineIcon = w:sub(1, 3)
                lineText = w:sub(4)
            end

            if lineIcon then
                imgui.Text(lineIcon)
                imgui.SameLine(0, 5)
            end

            local text, colors_, m = {}, {}, 1
            lineText = lineText:gsub('{(......)}', '{%1FF}')
            while lineText:find('{........}') do
                local n, k = lineText:find('{........}')
                local color = getcolor(lineText:sub(n + 1, k - 1))
                if color then
                    text[#text], text[#text + 1] = lineText:sub(m, n - 1), lineText:sub(k + 1, #lineText)
                    colors_[#colors_ + 1] = color
                    m = n
                end
                lineText = lineText:sub(1, n - 1) .. lineText:sub(k + 1, #lineText)
            end

            if text[0] then
                for i = 0, #text do
                    imgui.TextColored(colors_[i] or colors[1], u8(text[i]))
                    imgui.SameLine(nil, 0)
                end
                imgui.NewLine()
            else
                imgui.Text(u8(lineText))
            end
        end
    end

    render_text(text)
end

function imgui.ButtonClickable(hint, clickable, ...)
    if clickable then
        return imgui.Button(...)
    else
        local r, g, b, a = imgui.GetStyle().Colors[imgui.Col.Button].x, imgui.GetStyle().Colors[imgui.Col.Button].y,
            imgui.GetStyle().Colors[imgui.Col.Button].z, imgui.GetStyle().Colors[imgui.Col.Button].w
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(r, g, b, a / 2))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(r, g, b, a / 2))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(r, g, b, a / 2))
        imgui.PushStyleColor(imgui.Col.Text, imgui.GetStyle().Colors[imgui.Col.TextDisabled])
        imgui.Button(...)
        imgui.PopStyleColor()
        imgui.PopStyleColor()
        imgui.PopStyleColor()
        imgui.PopStyleColor()
        if hint then
            if imgui.IsItemHovered() then
                imgui.SetTooltip(u8(hint))
            end
        end
    end
end

function imgui.Hint(text, icon, active)
    if type(icon) == "boolean" then
        active = icon
        icon = nil
    end

    if not active then
        active = not imgui.IsItemActive()
    end

    if imgui.IsItemHovered() and active then
        imgui.BeginTooltip()

        if icon and icon ~= "" then
            imgui.Text(icon)
            imgui.SameLine(0, 5)
        end

        imgui.TextColoredRGB(text)

        imgui.EndTooltip()
    end
end

function imgui.Link(label, description)
    local size, p, p2 = imgui.CalcTextSize(label), imgui.GetCursorScreenPos(), imgui.GetCursorPos()
    local result = imgui.InvisibleButton(label, size)
    imgui.SetCursorPos(p2)

    if imgui.IsItemHovered() then
        if description then
            imgui.BeginTooltip()
            imgui.PushTextWrapPos(600)
            imgui.TextUnformatted(description)
            imgui.PopTextWrapPos()
            imgui.EndTooltip()
        end
        imgui.TextColored(imgui.ImVec4(0.27, 0.53, 0.87, 1.00), label)
        imgui.GetWindowDrawList():AddLine(imgui.ImVec2(p.x, p.y + size.y), imgui.ImVec2(p.x + size.x, p.y + size.y),
            imgui.GetColorU32(imgui.Col.CheckMark))
    else
        imgui.TextColored(imgui.ImVec4(0.27, 0.53, 0.87, 1.00), label)
    end

    return result
end

function DrawDoubleProgressCircle(centerPos, outerRadius, innerRadius, thickness, outerProgress, innerProgress)
    local drawList = imgui.GetWindowDrawList()
    local num_segments = 100

    -- Цвета
    local colorBg = imgui.ImVec4(0.15, 0.16, 0.20, 1.0)
    local colorOuter = imgui.ImVec4(0.2, 0.6, 1.0, 1.0)
    local colorInner = imgui.ImVec4(0.3, 0.8, 0.3, 1.0)

    -- Внешний круг
    drawList:AddCircle(centerPos, outerRadius,
        imgui.ColorConvertFloat4ToU32(colorBg), num_segments, thickness)

    if outerProgress > 0.001 then
        local start_angle = -math.pi / 2
        local end_angle = start_angle + (2 * math.pi * outerProgress)

        drawList:PathClear()
        drawList:PathArcTo(centerPos, outerRadius, start_angle, end_angle, num_segments)
        drawList:PathStroke(imgui.ColorConvertFloat4ToU32(colorOuter), false, thickness)
    end

    -- Внутренний круг
    if innerRadius > 0 then
        drawList:AddCircle(centerPos, innerRadius,
            imgui.ColorConvertFloat4ToU32(colorBg), num_segments, thickness - 2)

        if innerProgress > 0.001 then
            local start_angle = -math.pi / 2
            local end_angle = start_angle + (2 * math.pi * innerProgress)

            drawList:PathClear()
            drawList:PathArcTo(centerPos, innerRadius, start_angle, end_angle, num_segments)
            drawList:PathStroke(imgui.ColorConvertFloat4ToU32(colorInner), false, thickness - 2)
        end
    end
end

function smoothDamp(current, target, velocity, deltaTime, smoothTime)
    smoothTime = math.max(0.0001, smoothTime)

    local omega = 2 / smoothTime
    local x = omega * deltaTime
    local exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)

    local change = current - target
    local temp = (velocity + omega * change) * deltaTime

    velocity = (velocity - omega * temp) * exp
    local newValue = target + (change + temp) * exp

    if (target - current > 0) == (newValue > target) then
        newValue = target
        velocity = 0
    end

    return newValue, velocity
end

function ButtonWithHint(label, hint, clickable, size)
    if clickable == nil then clickable = not data.working end

    local pressed = imgui.ButtonClickable(hint, clickable, label, size or imgui.ImVec2(-1, 0))

    if clickable and hint and imgui.IsItemHovered() then
        imgui.SetTooltip(u8(hint))
    end

    return pressed
end

function renderResetConfirm(idSuffix, timerStartedAt, title, subtitle, onConfirm, onCancel)
    local sw2, sh2 = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(sw2 / 2, sh2 / 2),
        imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(380, 150), imgui.Cond.FirstUseEver)
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.08, 0.08, 0.10, 0.98))
    if imgui.Begin("##" .. idSuffix, nil,
            imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar +
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove) then
        imgui.SetCursorPosY(20)
        imgui.TextColored(imgui.ImVec4(0.97, 0.51, 0.51, 1), fa.TRIANGLE_EXCLAMATION)
        imgui.SameLine(0, 8)
        imgui.TextColoredRGB("{FFFFFF}" .. title)
        imgui.Spacing()
        imgui.TextColoredRGB("{808080}" .. subtitle)
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        local elapsed    = os.clock() - (timerStartedAt or 0)
        local remaining  = math.ceil(5 - elapsed)
        local canConfirm = elapsed >= 5.0
        local halfW      = (imgui.GetContentRegionAvail().x - imgui.GetStyle().ItemSpacing.x) / 2

        if canConfirm then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.6, 0.1, 0.1, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.8, 0.15, 0.15, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.4, 0.07, 0.07, 1))
            if imgui.Button(u8 "Сбросить", imgui.ImVec2(halfW, 28)) then onConfirm() end
            imgui.PopStyleColor(3)
        else
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.2, 0.1, 0.1, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.2, 0.1, 0.1, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.2, 0.1, 0.1, 1))
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.5, 0.5, 0.5, 1))
            imgui.Button(u8(string.format("Сбросить (%dс)", remaining)), imgui.ImVec2(halfW, 28))
            imgui.PopStyleColor(4)
        end
        imgui.SameLine()
        if imgui.Button(u8 "Отмена", imgui.ImVec2(halfW, 28)) then onCancel() end

        imgui.End()
    end
    imgui.PopStyleColor()
end
