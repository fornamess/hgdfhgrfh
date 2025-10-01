--[[
    AutoTrade System для Plants vs Brainrots
    Автоматическая система трейдов с Discord уведомлениями
    Автор: AI Assistant
]]

local AutoTrade = {}

-- ========== КОНФИГУРАЦИЯ ==========
-- Инициализация конфигурации в getgenv
if not getgenv().AutoTradeConfig then
    getgenv().AutoTradeConfig = {
        -- Основные настройки
        ENABLED = true,                    -- Включить авто трейд
        TARGET_PLAYER = "dancray228ps",    -- Имя игрока для трейдов
        MIN_RARITY = "Rare",               -- Минимальная редкость для трейда (Rare, Epic, Legendary, Mythic, Godly, Secret, Limited)
        MIN_MONEY_PER_SECOND = 0,          -- Минимальные деньги в секунду для трейда
        
        -- Discord настройки
        DISCORD_WEBHOOK_URL = "",          -- URL Discord webhook для уведомлений
        DISCORD_ENABLED = false,           -- Включить Discord уведомления
        
        -- Настройки трейдов
        AUTO_ACCEPT_TRADES = true,         -- Автоматически принимать трейды
        TRADE_DELAY = 1,                   -- Задержка между трейдами (секунды)
        MAX_TRADES_PER_SESSION = 10,       -- Максимум трейдов за сессию
        
        -- Фильтры
        EXCLUDE_PETS = {},                 -- Список исключенных пета (по имени)
        ONLY_SPECIFIC_PETS = false,        -- Торговать только определенными петами
        SPECIFIC_PETS = {},                -- Список разрешенных пета (по имени)
        
        -- Уведомления
        NOTIFY_ON_TRADE = true,            -- Уведомлять о трейдах в игре
        NOTIFY_ON_PET_FOUND = true,        -- Уведомлять о найденных петах
        
        -- Серверные настройки (теперь основные)
        USE_SERVER_SYSTEM = true,          -- Использовать серверную систему для всех операций
        SERVER_URL = "http://localhost:8888/api", -- URL сервера
        API_KEY = "pk_ad7a094d4a9a92afb534b401186d39f8_1759295804",                      -- API ключ для доступа к серверу (получить в веб-интерфейсе)
        AUTO_JOIN_SERVERS = true,          -- Автоматически присоединяться к серверам
        AUTO_ACCEPT_SERVER_TRADES = true,  -- Автоматически принимать трейды с сервера
        SERVER_UPDATE_INTERVAL = 5,        -- Интервал обновления с сервера (секунды)
        REJOIN_DELAY = 3,                  -- Задержка перед реджойном (секунды)
        
        -- Настройки прогресса
        UPDATE_PROGRESS_INTERVAL = 30,     -- Интервал обновления прогресса на сервере (секунды)
        SAVE_PROGRESS_ON_TRADE = true,     -- Сохранять прогресс при каждом трейде
    }
end

-- Создаем локальную ссылку для удобства
local CONFIG = getgenv().AutoTradeConfig

-- ========== ПЕРЕМЕННЫЕ ==========
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Кэш для изображений пета
local imageCache = {}
local imageQueue = {}
local activeImageRequests = 0
local maxConcurrentImageRequests = 5

local LocalPlayer = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerData = require(ReplicatedStorage:WaitForChild("PlayerData")):GetData()

-- Статистика
local stats = {
    tradesSent = 0,
    tradesAccepted = 0,
    petsFound = 0,
    lastTradeTime = 0,
    serverTradesSent = 0,
    serverTradesReceived = 0,
    serversJoined = 0,
    totalMoneyEarned = 0,
    bestPetRarity = "Rare",
    bestPetName = "",
    bestPetMoneyPerSecond = 0,
    dailyTrades = 0,
    dailyPetsTraded = 0,
    dailyMoneyEarned = 0
}

-- Кэш игроков и серверные данные
local playerCache = {}
local targetPlayerInServer = false
local serverData = {
    lastUpdate = 0,
    pendingTrades = {},
    joinCommands = {},
    isOnline = false
}

-- Система логирования
local logHistory = {}
local maxLogEntries = 1000 -- Максимум записей в истории логов

-- ========== УТИЛИТЫ ==========
local function log(message)
    local timestamp = os.date("%H:%M:%S")
    local logEntry = "[" .. timestamp .. "] [AutoTrade] " .. message
    
    -- Выводим в консоль
    print(logEntry)
    
    -- Сохраняем в историю
    table.insert(logHistory, logEntry)
    
    -- Ограничиваем размер истории
    if #logHistory > maxLogEntries then
        table.remove(logHistory, 1)
    end
end

-- Функция копирования всех логов в буфер обмена
local function copyLogsToClipboard()
    if #logHistory == 0 then
        log("Нет логов для копирования")
        return
    end
    
    local logsText = table.concat(logHistory, "\n")
    
    -- Добавляем заголовок
    local header = "=== AutoTrade Logs ===\n"
    header = header .. "Игрок: " .. LocalPlayer.Name .. "\n"
    header = header .. "Сервер: " .. game.JobId .. "\n"
    header = header .. "Время: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    header = header .. "Всего записей: " .. #logHistory .. "\n"
    header = header .. "========================\n\n"
    
    local fullText = header .. logsText
    
    -- Пытаемся скопировать в буфер обмена
    local success = pcall(function()
        if setclipboard then
            setclipboard(fullText)
            log("Логи скопированы в буфер обмена! (" .. #logHistory .. " записей)")
        elseif writeclipboard then
            writeclipboard(fullText)
            log("Логи скопированы в буфер обмена! (" .. #logHistory .. " записей)")
        else
            -- Если нет функции копирования, выводим в консоль
            log("Функция копирования недоступна. Выводим логи в консоль:")
            print("\n" .. fullText)
        end
    end)
    
    if not success then
        log("Ошибка копирования логов. Выводим в консоль:")
        print("\n" .. fullText)
    end
end

-- Обработчик клавиш
local function onInputBegan(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.F4 then
        copyLogsToClipboard()
    end
end

-- ========== ФУНКЦИИ ДЛЯ ИЗОБРАЖЕНИЙ ==========
-- Универсальная функция для HTTP запросов (перемещена выше)
local function MakeHttpRequest(url, method, data, headers)
    local requestFn = http_request or (syn and syn.request) or request

    if http_request then
    elseif syn and syn.request then
    elseif requestFn then
    elseif HttpService.RequestAsync then
    else
        return nil
    end

    if requestFn then
        local success, result = pcall(function()
            return requestFn({
                Url = url,
                Method = method,
                Headers = headers or {
                    ["Content-Type"] = "application/json"
                },
                Body = data
            })
        end)
        
        if success then
            return result
        else
            return nil
        end
    elseif HttpService.RequestAsync then
        local success, result = pcall(function()
            return HttpService:RequestAsync({
                Url = url,
                Method = method,
                Headers = headers or {
                    ["Content-Type"] = "application/json"
                },
                Body = data
            })
        end)
        
        if success then
            return result
        else
            warn("[AutoTrade] Ошибка в HttpService.RequestAsync: " .. tostring(result))
            return nil
        end
    end

    warn("[AutoTrade] Нет доступных HTTP методов")
    return nil
end

-- Функция для обработки очереди запросов изображений
local function processImageQueue()
    if activeImageRequests >= maxConcurrentImageRequests or #imageQueue == 0 then
        return
    end
    
    local request = table.remove(imageQueue, 1)
    activeImageRequests = activeImageRequests + 1
    
    spawn(function()
        local result = MakeHttpRequest(request.url, "GET", nil, nil)
        activeImageRequests = activeImageRequests - 1
        
        if result and result.StatusCode == 200 then
            request.callback(result.Body)
        else
            request.callback(nil)
        end
        
        -- Обрабатываем следующий запрос
        processImageQueue()
    end)
end

-- Функция для получения изображения пета
local function getPetImage(assetId, callback)
    if not assetId or assetId == '' then
        if callback then callback(nil) end
        return
    end
    
    local id = assetId:match("rbxassetid://(%d+)")
    if not id then 
        id = assetId:match("(%d+)")
        if not id then
            if callback then callback(nil) end
            return
        end
    end
    
    -- Проверяем кэш
    if imageCache[id] then
        if callback then callback(imageCache[id]) end
        return
    end
    
    -- Добавляем в очередь
    table.insert(imageQueue, {
        url = "https://thumbnails.roblox.com/v1/assets?assetIds=" .. id .. "&size=420x420&format=png&isCircular=false",
        callback = function(body)
            if body then
                local success, data = pcall(function()
                    return HttpService:JSONDecode(body)
                end)
                
                if success and data and data.data and data.data[1] and data.data[1].imageUrl then
                    local imageUrl = data.data[1].imageUrl
                    imageCache[id] = imageUrl
                    log("Изображение пета загружено: " .. imageUrl)
                    if callback then callback(imageUrl) end
                else
                    log("Ошибка загрузки изображения пета: " .. tostring(data))
                    if callback then callback(nil) end
                end
            else
                log("Ошибка HTTP запроса для изображения пета")
                if callback then callback(nil) end
            end
        end
    })
    
    processImageQueue()
end

-- Функция для поиска иконки в модели пета
local function findPetIcon(pet)
    if not pet then return nil end
    
    -- Ищем Decal/Texture объекты
    for _, child in pairs(pet:GetDescendants()) do
        if child:IsA("Decal") or child:IsA("Texture") then
            local textureId = child.Texture
            if textureId and textureId ~= "" then
                return textureId
            end
        end
    end
    
    -- Ищем атрибуты Icon, Image, Texture
    local iconAttributes = {"Icon", "Image", "Texture", "icon", "image", "texture"}
    for _, attrName in pairs(iconAttributes) do
        local attrValue = pet:GetAttribute(attrName)
        if attrValue and attrValue ~= "" then
            return tostring(attrValue)
        end
    end
    
    return nil
end

-- ========== СЕРВЕРНЫЕ ФУНКЦИИ ==========

-- Проверка игрока на сервере
local function checkPlayerInServer(playerName)
    log("=== ФУНКЦИЯ checkPlayerInServer ВЫЗВАНА ===")
    log("Ищем игрока: " .. tostring(playerName))
    log("Всего игроков на сервере: " .. #Players:GetPlayers())
    
    for i, player in pairs(Players:GetPlayers()) do
        log("Игрок " .. i .. ": " .. player.Name)
        if player.Name == playerName then
            log("✅ ИГРОК НАЙДЕН: " .. player.Name)
            return true
        end
    end
    
    log("❌ ИГРОК НЕ НАЙДЕН: " .. playerName)
    return false
end

-- Определение роли игрока (простая логика по имени)
local function determineRole()
    local isReceiver = (LocalPlayer.Name == CONFIG.TARGET_PLAYER)
    return isReceiver
end

-- Отправка данных на сервер
local function sendToServer(data)
    if not CONFIG.USE_SERVER_SYSTEM then
        return false
    end
    
    if CONFIG.API_KEY == "" then
        log("API ключ не установлен! Получите ключ в веб-интерфейсе: http://localhost:8888")
        return false
    end
    
    local jsonData = HttpService:JSONEncode(data)
    local headers = {
        ["Content-Type"] = "application/json",
        ["X-API-Key"] = CONFIG.API_KEY
    }
    
    log("Отправляем HTTP запрос на: " .. CONFIG.SERVER_URL .. "/trade")
    log("Данные: " .. jsonData)
    
    local result = MakeHttpRequest(CONFIG.SERVER_URL .. "/trade", "POST", jsonData, headers)
    
    if result and result.StatusCode == 200 then
        log("Данные отправлены на сервер успешно")
        serverData.isOnline = true
        return true
    else
        log("Ошибка отправки на сервер: " .. (result and result.StatusCode or "Нет ответа"))
        if result and result.Body then
            log("Ответ сервера: " .. result.Body)
        end
        serverData.isOnline = false
        return false
    end
end

-- Получение данных с сервера
local function getFromServer()
    if not CONFIG.USE_SERVER_SYSTEM then
        return nil
    end
    
    if CONFIG.API_KEY == "" then
        log("API ключ не установлен! Получите ключ в веб-интерфейсе: http://localhost:8888")
        return nil
    end
    
    local headers = {
        ["X-API-Key"] = CONFIG.API_KEY
    }
    
    local result = MakeHttpRequest(CONFIG.SERVER_URL .. "/trades/" .. LocalPlayer.Name, "GET", nil, headers)
    
    if result and result.StatusCode == 200 then
        serverData.isOnline = true
        local success, decoded = pcall(function()
            return HttpService:JSONDecode(result.Body)
        end)
        
        if success then
            log("Получен ответ от сервера: " .. (decoded.joinServer and "есть команда присоединения" or "нет команды присоединения"))
            return decoded
        else
            log("Ошибка декодирования ответа сервера")
            return nil
        end
    else
        log("Ошибка получения с сервера: " .. (result and result.StatusCode or "Нет ответа"))
        serverData.isOnline = false
        return nil
    end
end

-- Обновление информации об игроке на сервере
local function updatePlayerOnServer()
    if not CONFIG.USE_SERVER_SYSTEM then
        return
    end
    
    -- Получаем количество игроков на сервере
    local playersCount = #Players:GetPlayers()
    local isFullServer = playersCount >= 5
    
    local playerData = {
        playerName = LocalPlayer.Name,
        serverId = game.JobId,
        placeId = game.PlaceId,
        status = "online",
        playersCount = playersCount,
        isFullServer = isFullServer,
        timestamp = os.time()
    }
    
    local updateData = {
        type = "player_update",
        playerName = playerData.playerName,
        serverId = playerData.serverId,
        placeId = playerData.placeId,
        status = playerData.status,
        playersCount = playerData.playersCount,
        isFullServer = playerData.isFullServer,
        timestamp = playerData.timestamp
    }
    
    -- Отправляем через правильный API endpoint
    local jsonData = HttpService:JSONEncode(updateData)
    local headers = {
        ["Content-Type"] = "application/json",
        ["X-API-Key"] = CONFIG.API_KEY
    }
    
    local result = MakeHttpRequest(CONFIG.SERVER_URL .. "/player/update", "POST", jsonData, headers)
    
    if result and result.StatusCode == 200 then
        log("Информация об игроке обновлена на сервере (игроков: " .. playersCount .. ", полный: " .. tostring(isFullServer) .. ")")
    else
        log("Ошибка обновления информации об игроке: " .. (result and result.StatusCode or "Нет ответа"))
    end
end

-- Отправка прогресса пользователя на сервер
local function updateProgressOnServer()
    if not CONFIG.USE_SERVER_SYSTEM or CONFIG.API_KEY == "" then
        return
    end
    
    local progressData = {
        type = "progress_update",
        totalTrades = stats.tradesSent,
        totalPetsTraded = stats.tradesSent, -- В этой системе трейды = пета
        totalMoneyEarned = stats.totalMoneyEarned,
        bestPetRarity = stats.bestPetRarity,
        bestPetName = stats.bestPetName,
        bestPetMoneyPerSecond = stats.bestPetMoneyPerSecond,
        dailyTrades = stats.dailyTrades,
        dailyPetsTraded = stats.dailyPetsTraded,
        dailyMoneyEarned = stats.dailyMoneyEarned,
        timestamp = os.time()
    }
    
    local jsonData = HttpService:JSONEncode(progressData)
    local headers = {
        ["Content-Type"] = "application/json",
        ["X-API-Key"] = CONFIG.API_KEY
    }
    
    local result = MakeHttpRequest(CONFIG.SERVER_URL .. "/user/update-progress", "POST", jsonData, headers)
    
    if result and result.StatusCode == 200 then
        log("Прогресс обновлен на сервере")
    else
        log("Ошибка обновления прогресса: " .. (result and result.StatusCode or "Нет ответа"))
    end
end

-- Обновление статистики при трейде
local function updateStatsOnTrade(petInfo)
    stats.totalMoneyEarned = stats.totalMoneyEarned + petInfo.moneyPerSecond
    stats.dailyTrades = stats.dailyTrades + 1
    stats.dailyPetsTraded = stats.dailyPetsTraded + 1
    stats.dailyMoneyEarned = stats.dailyMoneyEarned + petInfo.moneyPerSecond
    
    -- Обновляем лучшего пета
    if petInfo.moneyPerSecond > stats.bestPetMoneyPerSecond then
        stats.bestPetMoneyPerSecond = petInfo.moneyPerSecond
        stats.bestPetName = petInfo.name
        stats.bestPetRarity = petInfo.rarity
    end
    
    -- Отправляем прогресс на сервер если включено
    if CONFIG.SAVE_PROGRESS_ON_TRADE then
        updateProgressOnServer()
    end
end


local function notify(message, color)
    if CONFIG.NOTIFY_ON_TRADE then
        -- Используем систему уведомлений игры
        local Notification = require(ReplicatedStorage.Modules.Utility.Notification)
        Notification:Notify(message, color or Color3.fromRGB(0, 255, 0))
    end
end

-- Автоматическое присоединение к серверу (только для отправителей)
local function autoJoinServer(serverData)
    if not CONFIG.AUTO_JOIN_SERVERS then
        return
    end
    
    -- Проверяем роль - только отправители присоединяются к серверам получателей
    local isReceiver = determineRole()
    
    if isReceiver then
        log("Я получатель - остаюсь на своем сервере и жду отправителей")
        return
    end
    
    -- Проверяем, не полный ли сервер
    if serverData.isFullServer then
        log("❌ Сервер получателя полный (" .. (serverData.playersCount or 0) .. " игроков) - не присоединяемся")
        notify("Сервер получателя полный! Ждем освобождения...", Color3.fromRGB(255, 165, 0))
        return
    end
    
    local success, error = pcall(function()
        local TeleportService = game:GetService("TeleportService")
        local serverId = serverData.serverId
        local placeId = serverData.placeId or game.PlaceId
        local playersCount = serverData.playersCount or 0
        
        log("Присоединяемся к серверу получателя: " .. serverId .. " (игроков: " .. playersCount .. ")")
        stats.serversJoined = stats.serversJoined + 1
        
        -- Ждем немного перед переходом
        wait(CONFIG.REJOIN_DELAY)
        
        -- Переходим на сервер
        TeleportService:TeleportToPlaceInstance(placeId, serverId)
    end)
    
    if not success then
        log("Ошибка присоединения к серверу: " .. tostring(error))
    end
end

-- Обработка входящих трейдов с сервера
local function handleServerTrade(tradeData)
    if not CONFIG.AUTO_ACCEPT_SERVER_TRADES then
        return
    end
    
    local success, error = pcall(function()
        -- Принимаем трейд
        local args = {
            {
                ID = tradeData.tradeId
            }
        }
        Remotes.AcceptGift:FireServer(unpack(args))
        
        log("Трейд принят с сервера: " .. tradeData.senderName)
        stats.serverTradesReceived = stats.serverTradesReceived + 1
        
        -- Уведомляем сервер о принятии
        sendToServer({
            type = "trade_accepted",
            tradeId = tradeData.tradeId,
            receiver = LocalPlayer.Name,
            timestamp = os.time()
        })
    end)
    
    if not success then
        log("Ошибка принятия трейда: " .. tostring(error))
    end
end

local function getRarityValue(rarity)
    local rarityValues = {
        Rare = 1,
        Epic = 2,
        Legendary = 3,
        Mythic = 4,
        Godly = 5,
        Secret = 6,
        Limited = 7
    }
    -- Сравниваем без учета регистра, но возвращаем правильное значение
    local rarityKey = rarity
    for key, value in pairs(rarityValues) do
        if key:lower() == rarity:lower() then
            return value
        end
    end
    return 0
end

-- Получение информации о пете (как в AutoPetSeller)
-- Функция для получения веса пета из названия (из AutoPetSeller.lua)
local function getPetWeight(petName)
    local weight = petName:match("%[(%d+%.?%d*)%s*kg%]")
    return weight and tonumber(weight) or 0
end

local function getPetInfo(pet)
    local success, result = pcall(function()
        if not pet then
            return {
                name = "Unknown",
                weight = 0,
                rarity = "Rare",
                worth = 0,
                size = 1,
                offset = 0,
                moneyPerSecond = 0
            }
        end
        
        local petData = pet:FindFirstChild(pet.Name)
        if not petData then
            -- Убираем мутации и вес из названия для поиска
            local cleanName = pet.Name:gsub("%[.*%]%s*", "")
            petData = pet:FindFirstChild(cleanName)
        end
        
        if not petData then
            -- Ищем по частичному совпадению (для пета с мутациями)
            for _, child in pairs(pet:GetChildren()) do
                if child:GetAttribute("Rarity") then
                    petData = child
                    break
                end
            end
        end
        
        -- Если все еще не найдено, ищем по любому дочернему объекту с атрибутом Rarity
        if not petData then
            for _, child in pairs(pet:GetChildren()) do
                if child:GetAttribute("Rarity") then
                    petData = child
                    break
                end
            end
        end
        
        -- Получаем MoneyPerSecond из UI (точно как в AutoPetSeller.lua)
        local moneyPerSecond = 0
        if petData then
            local rootPart = petData:FindFirstChild("RootPart")
            if rootPart then
                local brainrotToolUI = rootPart:FindFirstChild("BrainrotToolUI")
                if brainrotToolUI then
                    local moneyLabel = brainrotToolUI:FindFirstChild("Money")
                    if moneyLabel then
                        -- Парсим MoneyPerSecond из текста типа "$1,234/s"
                        local moneyText = moneyLabel.Text
                        local moneyValue = moneyText:match("%$(%d+,?%d*)/s")
                        if moneyValue then
                            -- Убираем запятые и конвертируем в число
                            local cleanValue = moneyValue:gsub(",", "")
                            moneyPerSecond = tonumber(cleanValue) or 0
                        end
                    end
                end
            end
        end
        
        if petData then
            return {
                name = pet.Name,
                weight = getPetWeight(pet.Name),
                rarity = petData:GetAttribute("Rarity") or "Rare",
                worth = petData:GetAttribute("Worth") or 0,
                size = petData:GetAttribute("Size") or 1,
                offset = petData:GetAttribute("Offset") or 0,
                moneyPerSecond = moneyPerSecond
            }
        end
        
        return {
            name = pet.Name,
            weight = getPetWeight(pet.Name),
            rarity = "Rare",
            worth = 0,
            size = 1,
            offset = 0,
            moneyPerSecond = moneyPerSecond
        }
    end)
    
    if not success then
        log("Ошибка в getPetInfo для пета " .. (pet and pet.Name or "nil") .. ": " .. tostring(result))
        return {
            name = pet and pet.Name or "Unknown",
            weight = pet and getPetWeight(pet.Name) or 0,
            rarity = "Rare",
            worth = 0,
            size = 1,
            offset = 0,
            moneyPerSecond = 0
        }
    end
    
    return result
end

local function shouldTradePet(pet)
    local success, result = pcall(function()
        if not pet or not pet:IsA("Tool") then
            return false
        end
        
        -- Проверяем, что это пет (имеет вес в названии или мутацию)
        if not pet.Name:match("%[%d+%.?%d*%s*kg%]") and not pet.Name:match("%[.*%]") then
            return false
        end
        
        -- Исключаем растения (проверяем по названию)
        local plantNames = {"Seed", "Plant", "Flower", "Tree", "Grass", "Bush", "Cactus", "Sunflower", "Pumpkin", "Watermelon", "Grape", "Dragon Fruit", "Eggplant", "Strawberry", "Cocotank", "Carnivorous", "Carrot", "Tomatrio", "Shroombino"}
        for _, plantName in pairs(plantNames) do
            if pet.Name:find(plantName) then
                return false
            end
        end
        
        -- Получаем информацию о пете
        local petInfo = getPetInfo(pet)
        if not petInfo then
            log("Ошибка: не удалось получить информацию о пете " .. pet.Name)
            return false
        end
        
        local rarity = petInfo.rarity
        local moneyPerSecond = petInfo.moneyPerSecond
        local petName = petInfo.name
        
        -- Отладочная информация для пета с мутацией Rainbow
        if pet.Name:find("Rainbow") then
            log("Найден пет с мутацией Rainbow: " .. pet.Name)
            log("Редкость: " .. rarity .. " (значение: " .. getRarityValue(rarity) .. ")")
            log("Минимальная редкость: " .. CONFIG.MIN_RARITY .. " (значение: " .. getRarityValue(CONFIG.MIN_RARITY) .. ")")
            log("MoneyPerSecond: " .. moneyPerSecond)
        end
        
        -- Проверка минимальной редкости
        if getRarityValue(rarity) < getRarityValue(CONFIG.MIN_RARITY) then
            return false
        end
        
        -- Проверка минимальных денег в секунду
        if moneyPerSecond < CONFIG.MIN_MONEY_PER_SECOND then
            return false
        end
        
        -- Проверка исключенных пета
        for _, excludedPet in pairs(CONFIG.EXCLUDE_PETS) do
            if string.find(petName:lower(), excludedPet:lower()) then
                return false
            end
        end
        
        -- Проверка разрешенных пета (если включен режим только определенных)
        if CONFIG.ONLY_SPECIFIC_PETS then
            local found = false
            for _, allowedPet in pairs(CONFIG.SPECIFIC_PETS) do
                if string.find(petName:lower(), allowedPet:lower()) then
                    found = true
                    break
                end
            end
            if not found then
                return false
            end
        end
        
        return true
    end)
    
    if not success then
        log("Ошибка в shouldTradePet для пета " .. (pet and pet.Name or "nil") .. ": " .. tostring(result))
        return false
    end
    
    return result
end


local function equipPet(pet)
    if not pet or not pet.Parent then
        return false
    end
    
    -- Проверяем, не экипирован ли уже пет
    if pet.Parent == LocalPlayer.Character then
        return true
    end
    
    -- Экипируем пета
    local success = pcall(function()
        LocalPlayer.Character:FindFirstChild("Humanoid"):EquipTool(pet)
    end)
    
    if success then
        log("Пет " .. pet.Name .. " экипирован")
        return true
    else
        log("Ошибка экипировки пета " .. pet.Name)
        return false
    end
end

local function sendDiscordNotification(title, description, color)
    if not CONFIG.DISCORD_ENABLED or CONFIG.DISCORD_WEBHOOK_URL == "" then
        return
    end
    
    local data = {
        embeds = {{
            title = title,
            description = description,
            color = color or 65280, -- Зеленый цвет
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            fields = {
                {
                    name = "Сервер",
                    value = game.JobId,
                    inline = true
                },
                {
                    name = "Игрок",
                    value = LocalPlayer.Name,
                    inline = true
                }
            }
        }}
    }
    
    local jsonData = HttpService:JSONEncode(data)
    local headers = {
        ["Content-Type"] = "application/json"
    }
    
    local result = MakeHttpRequest(CONFIG.DISCORD_WEBHOOK_URL, "POST", jsonData, headers)
    
    if not result or result.StatusCode ~= 204 then
        log("Ошибка отправки Discord уведомления: " .. (result and result.StatusCode or "Нет ответа"))
    end
end

local function sendTrade(pet, targetPlayer)
    log("=== ФУНКЦИЯ sendTrade ВЫЗВАНА ===")
    log("pet: " .. tostring(pet and pet.Name or "nil"))
    log("targetPlayer: " .. tostring(targetPlayer))
    log("LocalPlayer.Name: " .. tostring(LocalPlayer.Name))
    
    if not pet or not targetPlayer then
        log("❌ ОШИБКА: pet или targetPlayer не заданы")
        return false
    end
    
    -- Проверяем, что не торгуемся сами с собой
    if targetPlayer == LocalPlayer.Name then
        log("❌ ОШИБКА: Попытка торговать сам с собой!")
        log("targetPlayer: " .. targetPlayer)
        log("LocalPlayer.Name: " .. LocalPlayer.Name)
        log("Это означает, что мы получатели - не должны отправлять трейды!")
        return false
    end
    
    -- Проверяем задержку между трейдами
    local currentTime = tick()
    if currentTime - stats.lastTradeTime < CONFIG.TRADE_DELAY then
        return false
    end
    
    -- Проверяем лимит трейдов (увеличиваем лимит для серверной системы)
    local maxTrades = CONFIG.USE_SERVER_SYSTEM and 100 or CONFIG.MAX_TRADES_PER_SESSION
    if stats.tradesSent >= maxTrades then
        log("Достигнут лимит трейдов за сессию: " .. stats.tradesSent .. "/" .. maxTrades)
        return false
    end
    
    -- Экипируем пета перед отправкой трейда
    if not equipPet(pet) then
        return false
    end
    
    -- Ждем немного для экипировки
    wait(0.5)
    
    -- Отправляем трейд
    local success = pcall(function()
        local args = {
            {
                Item = pet,
                ToGift = targetPlayer
            }
        }
        Remotes.GiftItem:FireServer(unpack(args))
    end)
    
    if success then
        stats.tradesSent = stats.tradesSent + 1
        stats.lastTradeTime = currentTime
        
        local message = "Трейд отправлен: " .. pet.Name .. " -> " .. targetPlayer
        log(message)
        notify(message)
        
        -- Discord уведомление о трейде
        local petInfo = getPetInfo(pet)
        sendDiscordNotification(
            "Трейд отправлен",
            "**Пет:** " .. petInfo.name .. "\n**Редкость:** " .. petInfo.rarity .. "\n**Деньги/сек:** " .. petInfo.moneyPerSecond .. "$\n**Получатель:** " .. targetPlayer,
            16776960 -- Желтый цвет
        )
        
        -- Обновляем статистику
        updateStatsOnTrade(petInfo)
        
        -- Если используется серверная система, отправляем данные на сервер
        if CONFIG.USE_SERVER_SYSTEM then
            log("Отправляем трейд на сервер...")
            -- Получаем иконку пета
            local petIcon = findPetIcon(pet)
            
            -- Асинхронно получаем изображение пета
            if petIcon then
                log("Найдена иконка пета: " .. petIcon)
                getPetImage(petIcon, function(imageUrl)
                    local serverTradeData = {
                        type = "trade_sent",
                        sender = LocalPlayer.Name,
                        receiver = targetPlayer,
                        petName = petInfo.name,
                        petRarity = petInfo.rarity,
                        petMoneyPerSecond = petInfo.moneyPerSecond,
                        petIconUrl = petIcon,
                        petImageUrl = imageUrl,
                        serverId = game.JobId,
                        placeId = game.PlaceId,
                        timestamp = os.time()
                    }
                    
                    log("Отправляем данные трейда на сервер: " .. LocalPlayer.Name .. " -> " .. targetPlayer)
                    if sendToServer(serverTradeData) then
                        stats.serverTradesSent = stats.serverTradesSent + 1
                        log("Трейд отправлен через сервер с изображением")
                    else
                        log("ОШИБКА: Не удалось отправить трейд на сервер")
                    end
                end)
            else
                log("Иконка пета не найдена, отправляем без изображения")
                -- Отправляем без изображения
                local serverTradeData = {
                    type = "trade_sent",
                    sender = LocalPlayer.Name,
                    receiver = targetPlayer,
                    petName = petInfo.name,
                    petRarity = petInfo.rarity,
                    petMoneyPerSecond = petInfo.moneyPerSecond,
                    petIconUrl = "",
                    petImageUrl = "",
                    serverId = game.JobId,
                    placeId = game.PlaceId,
                    timestamp = os.time()
                }
                
                log("Отправляем данные трейда на сервер: " .. LocalPlayer.Name .. " -> " .. targetPlayer)
                if sendToServer(serverTradeData) then
                    stats.serverTradesSent = stats.serverTradesSent + 1
                    log("Трейд отправлен через сервер без изображения")
                else
                    log("ОШИБКА: Не удалось отправить трейд на сервер")
                end
            end
        else
            log("Серверная система отключена - трейд не отправляется на сервер")
        end
        
        return true
    else
        log("Ошибка отправки трейда")
        return false
    end
end

-- Функция для проверки наличия пета в инвентаре
local function hasPetsInInventory()
    local petCount = 0
    
    -- Проверяем инвентарь
    for _, pet in pairs(LocalPlayer.Backpack:GetChildren()) do
        if pet:IsA("Tool") and (pet.Name:match("%[%d+%.?%d*%s*kg%]") or pet.Name:match("%[.*%]")) then
            if shouldTradePet(pet) then
                petCount = petCount + 1
            end
        end
    end
    
    -- Проверяем экипированные инструменты
    if LocalPlayer.Character then
        for _, pet in pairs(LocalPlayer.Character:GetChildren()) do
            if pet:IsA("Tool") and (pet.Name:match("%[%d+%.?%d*%s*kg%]") or pet.Name:match("%[.*%]")) then
                if shouldTradePet(pet) then
                    petCount = petCount + 1
                end
            end
        end
    end
    
    return petCount
end

local function findBestPetToTrade()
    local bestPet = nil
    local bestValue = 0
    local allPets = {}
    local totalPets = 0
    local totalTools = 0
    
    log("=== ПОИСК ПЕТА ДЛЯ ТРЕЙДА ===")
    log("Игрок: " .. LocalPlayer.Name)
    log("Целевой игрок: " .. CONFIG.TARGET_PLAYER)
    log("Минимальная редкость: " .. CONFIG.MIN_RARITY)
    
    -- Собираем всех подходящих пета
    -- Ищем в инвентаре
    log("Проверяем инвентарь...")
    local success, error = pcall(function()
        for _, pet in pairs(LocalPlayer.Backpack:GetChildren()) do
            totalTools = totalTools + 1
            if pet:IsA("Tool") then
                totalPets = totalPets + 1
                log("Найден инструмент в инвентаре: " .. pet.Name .. " (тип: " .. pet.ClassName .. ")")
                
                -- Проверяем, является ли это петом
                if pet.Name:match("%[%d+%.?%d*%s*kg%]") or pet.Name:match("%[.*%]") then
                    log("  -> Это пет: " .. pet.Name)
                    
                    local shouldTrade = false
                    local tradeError = ""
                    local success2, error2 = pcall(function()
                        shouldTrade = shouldTradePet(pet)
                    end)
                    
                    if not success2 then
                        tradeError = " (ошибка проверки: " .. tostring(error2) .. ")"
                    end
                    
                    if shouldTrade then
                        local petInfo = nil
                        local success3, error3 = pcall(function()
                            petInfo = getPetInfo(pet)
                        end)
                        
                        if success3 and petInfo then
                            local rarity = petInfo.rarity
                            local moneyPerSecond = petInfo.moneyPerSecond
                            local value = getRarityValue(rarity) * 1000 + moneyPerSecond
                            
                            log("  -> Пет подходит для трейда: " .. petInfo.name .. " (" .. rarity .. ") - " .. moneyPerSecond .. "$/сек")
                            table.insert(allPets, {pet = pet, value = value, info = petInfo})
                            
                            if value > bestValue then
                                bestValue = value
                                bestPet = pet
                            end
                        else
                            log("  -> Ошибка получения информации о пете: " .. tostring(error3))
                        end
                    else
                        log("  -> Пет не подходит для трейда" .. tradeError)
                    end
                else
                    log("  -> Это не пет (нет веса или мутации в названии)")
                end
            else
                log("Найден объект в инвентаре: " .. pet.Name .. " (тип: " .. pet.ClassName .. ")")
            end
        end
    end)
    
    if not success then
        log("Ошибка при проверке инвентаря: " .. tostring(error))
    end
    
    -- Ищем в экипированных инструментах
    log("Проверяем экипированные инструменты...")
    local success2, error2 = pcall(function()
        if LocalPlayer.Character then
            for _, pet in pairs(LocalPlayer.Character:GetChildren()) do
                if pet:IsA("Tool") then
                    totalTools = totalTools + 1
                    totalPets = totalPets + 1
                    log("Найден экипированный инструмент: " .. pet.Name .. " (тип: " .. pet.ClassName .. ")")
                    
                    if pet.Name:match("%[%d+%.?%d*%s*kg%]") or pet.Name:match("%[.*%]") then
                        log("  -> Это экипированный пет: " .. pet.Name)
                        
                        local shouldTrade = false
                        local tradeError = ""
                        local success3, error3 = pcall(function()
                            shouldTrade = shouldTradePet(pet)
                        end)
                        
                        if not success3 then
                            tradeError = " (ошибка проверки: " .. tostring(error3) .. ")"
                        end
                        
                        if shouldTrade then
                            local petInfo = nil
                            local success4, error4 = pcall(function()
                                petInfo = getPetInfo(pet)
                            end)
                            
                            if success4 and petInfo then
                                local rarity = petInfo.rarity
                                local moneyPerSecond = petInfo.moneyPerSecond
                                local value = getRarityValue(rarity) * 1000 + moneyPerSecond
                                
                                log("  -> Экипированный пет подходит для трейда: " .. petInfo.name .. " (" .. rarity .. ") - " .. moneyPerSecond .. "$/сек")
                                table.insert(allPets, {pet = pet, value = value, info = petInfo})
                                
                                if value > bestValue then
                                    bestValue = value
                                    bestPet = pet
                                end
                            else
                                log("  -> Ошибка получения информации об экипированном пете: " .. tostring(error4))
                            end
                        else
                            log("  -> Экипированный пет не подходит для трейда" .. tradeError)
                        end
                    else
                        log("  -> Это не пет (нет веса или мутации в названии)")
                    end
                end
            end
        else
            log("Персонаж не найден")
        end
    end)
    
    if not success2 then
        log("Ошибка при проверке экипированных инструментов: " .. tostring(error2))
    end
    
    -- Логируем найденных пета
    log("=== РЕЗУЛЬТАТЫ ПОИСКА ===")
    log("Всего инструментов найдено: " .. totalTools)
    log("Всего пета найдено: " .. totalPets)
    log("Подходящих пета для трейда: " .. #allPets)
    
    if #allPets > 0 then
        log("Список подходящих пета:")
        for i, petData in ipairs(allPets) do
            log("  " .. i .. ". " .. petData.info.name .. " (" .. petData.info.rarity .. ") - " .. petData.info.moneyPerSecond .. "$/сек (ценность: " .. petData.value .. ")")
        end
        
        if bestPet then
            local bestInfo = getPetInfo(bestPet)
            log("Выбран лучший пет для трейда: " .. bestInfo.name .. " (" .. bestInfo.rarity .. ") - " .. bestInfo.moneyPerSecond .. "$/сек")
        end
    else
        log("Не найдено подходящих пета для трейда")
        log("Проверьте, что у вас есть пета с редкостью " .. CONFIG.MIN_RARITY .. " или выше")
        log("Возможные причины:")
        log("  1. Нет пета в инвентаре")
        log("  2. Все пета ниже минимальной редкости")
        log("  3. Все пета исключены фильтрами")
        log("  4. Ошибка в парсинге информации о петах")
    end
    
    log("=== КОНЕЦ ПОИСКА ПЕТА ===")
    return bestPet
end

-- ========== ОСНОВНАЯ ЛОГИКА ==========
local function onPlayerAdded(player)
    log("=== ФУНКЦИЯ onPlayerAdded ВЫЗВАНА ===")
    log("player.Name: " .. tostring(player.Name))
    log("CONFIG.TARGET_PLAYER: " .. tostring(CONFIG.TARGET_PLAYER))
    log("LocalPlayer.Name: " .. tostring(LocalPlayer.Name))
    
    if player.Name == CONFIG.TARGET_PLAYER then
        log("✅ ЦЕЛЕВОЙ ИГРОК НАЙДЕН!")
        targetPlayerInServer = true
        log("targetPlayerInServer установлен в true")
        log("Целевой игрок " .. CONFIG.TARGET_PLAYER .. " зашел на сервер!")
        
        if CONFIG.NOTIFY_ON_TRADE then
            notify("Целевой игрок в сервере! Начинаю трейды...", Color3.fromRGB(0, 255, 0))
        end
        
        -- Ждем немного и начинаем трейды
        log("Ждем 2 секунды перед началом трейдов...")
        wait(2)
        
        log("CONFIG.ENABLED: " .. tostring(CONFIG.ENABLED))
        if CONFIG.ENABLED then
            log("=== ОПРЕДЕЛЯЕМ РОЛЬ ИГРОКА ===")
            local isReceiver = determineRole()
            
            if isReceiver then
                log("✅ Я ПОЛУЧАТЕЛЬ - публикую информацию о сервере и жду отправителей")
                -- Получатель публикует информацию о своем сервере
                updatePlayerOnServer()
                
                local playersCount = #Players:GetPlayers()
                local isFullServer = playersCount >= 5
                
                if isFullServer then
                    log("⚠️ ВНИМАНИЕ: Мой сервер полный (" .. playersCount .. " игроков) - отправители не смогут присоединиться!")
                    if CONFIG.NOTIFY_ON_TRADE then
                        notify("Сервер полный! Отправители не смогут присоединиться", Color3.fromRGB(255, 165, 0))
                    end
                else
                    log("✅ Сервер не полный (" .. playersCount .. " игроков) - отправители могут присоединиться")
                    if CONFIG.NOTIFY_ON_TRADE then
                        notify("Я получатель! Жду отправителей...", Color3.fromRGB(0, 255, 255))
                    end
                end
            else
                log("✅ Я ОТПРАВИТЕЛЬ - начинаю торговлю с " .. CONFIG.TARGET_PLAYER)
                
                -- Запускаем цикл отправки трейдов (только для отправителей)
                spawn(function()
                    local allPetsTraded = false
                    
                    while CONFIG.ENABLED and targetPlayerInServer and not allPetsTraded do
                        -- Проверяем, есть ли еще пета для трейда
                        local petsInInventory = hasPetsInInventory()
                        log("Пета в инвентаре для трейда: " .. petsInInventory)
                        
                        if petsInInventory > 0 then
                            local pet = findBestPetToTrade()
                            if pet then
                                if sendTrade(pet, CONFIG.TARGET_PLAYER) then
                                    log("Трейд отправлен успешно, проверяем инвентарь...")
                                    wait(CONFIG.TRADE_DELAY) -- Ждем перед следующим трейдом
                                else
                                    log("Ошибка отправки трейда, ждем...")
                                    wait(2)
                                end
                            else
                                log("Ошибка: пета есть в инвентаре, но findBestPetToTrade не нашел их")
                                wait(2)
                            end
                        else
                            log("✅ Подтверждено: все пета затрейдены! Уведомляем получателя о завершении...")
                            allPetsTraded = true
                                
                                -- Отправляем уведомление на сервер о завершении трейдов
                                if CONFIG.USE_SERVER_SYSTEM then
                                    local completionData = {
                                        type = "trading_completed",
                                        sender = LocalPlayer.Name,
                                        receiver = CONFIG.TARGET_PLAYER,
                                        totalTrades = stats.tradesSent,
                                        timestamp = os.time()
                                    }
                                    
                                    local jsonData = HttpService:JSONEncode(completionData)
                                    local headers = {
                                        ["Content-Type"] = "application/json",
                                        ["X-API-Key"] = CONFIG.API_KEY
                                    }
                                    
                                    local result = MakeHttpRequest(CONFIG.SERVER_URL .. "/trading/completed", "POST", jsonData, headers)
                                    
                                    if result and result.StatusCode == 200 then
                                        log("✅ Уведомление о завершении трейдов отправлено на сервер")
                                    else
                                        log("Ошибка отправки уведомления о завершении: " .. (result and result.StatusCode or "Нет ответа"))
                                    end
                                end
                                
                                log("✅ Все трейды завершены - остаюсь на сервере как отправитель")
                                notify("Все трейды завершены! Остаюсь на сервере.", Color3.fromRGB(0, 255, 0))
                                break
                        end
                    end
                end)
            end
        end
    end
end

-- Основной цикл серверной системы
local function serverLoop()
    spawn(function()
        local lastProgressUpdate = 0
        local tradeLoopStarted = false
        
        while CONFIG.USE_SERVER_SYSTEM do
            wait(CONFIG.SERVER_UPDATE_INTERVAL)
            
            -- Обновляем информацию об игроке
            updatePlayerOnServer()
            
            -- Периодически обновляем прогресс
            local currentTime = os.time()
            if currentTime - lastProgressUpdate >= CONFIG.UPDATE_PROGRESS_INTERVAL then
                updateProgressOnServer()
                lastProgressUpdate = currentTime
            end
            
            -- Получаем данные с сервера
            local serverResponse = getFromServer()
            if serverResponse then
                -- Обрабатываем входящие трейды
                if serverResponse.trades then
                    for _, trade in pairs(serverResponse.trades) do
                        handleServerTrade(trade)
                    end
                end
                
                -- Обрабатываем команды присоединения к серверам
                if serverResponse.joinServer then
                    log("Получена команда присоединения к серверу: " .. serverResponse.joinServer.serverId)
                    log("Отправитель: " .. (serverResponse.joinServer.senderName or "неизвестен"))
                    log("Игроков на сервере: " .. (serverResponse.joinServer.playersCount or 0))
                    log("Полный сервер: " .. tostring(serverResponse.joinServer.isFullServer or false))
                    
                    -- Проверяем роль - только отправители присоединяются к серверам
                    local isReceiver = determineRole()
                    if isReceiver then
                        log("Я получатель - игнорирую команду присоединения, остаюсь на своем сервере")
                    else
                        log("Я отправитель - проверяю возможность присоединения к серверу получателя")
                        autoJoinServer(serverResponse.joinServer)
                    end
                else
                    log("Команды присоединения не получены")
                end
                
                -- Проверяем, есть ли целевой игрок на сервере
                if not targetPlayerInServer then
                    targetPlayerInServer = checkPlayerInServer(CONFIG.TARGET_PLAYER)
                    if targetPlayerInServer then
                        log("Целевой игрок " .. CONFIG.TARGET_PLAYER .. " обнаружен на сервере!")
                    end
                end
                
                -- Проверяем, нужно ли запустить трейды (только один раз)
                log("=== ПРОВЕРКА УСЛОВИЙ ДЛЯ ЗАПУСКА ТРЕЙДОВ ===")
                log("tradeLoopStarted: " .. tostring(tradeLoopStarted))
                log("CONFIG.ENABLED: " .. tostring(CONFIG.ENABLED))
                log("targetPlayerInServer: " .. tostring(targetPlayerInServer))
                log("CONFIG.TARGET_PLAYER: " .. tostring(CONFIG.TARGET_PLAYER))
                log("LocalPlayer.Name: " .. tostring(LocalPlayer.Name))
                
                if not tradeLoopStarted and CONFIG.ENABLED and targetPlayerInServer then
                    log("=== ВСЕ УСЛОВИЯ ВЫПОЛНЕНЫ - ОПРЕДЕЛЯЕМ РОЛЬ ===")
                    local isReceiver = determineRole()
                    
                    log("determineRole(): " .. tostring(isReceiver))
                    
                    if not isReceiver then
                        -- Только отправители запускают цикл трейдов
                        tradeLoopStarted = true
                        log("=== ЗАПУСКАЕМ ЦИКЛ ТРЕЙДОВ (ОТПРАВИТЕЛЬ) ===")
                        
                        -- Запускаем цикл отправки трейдов
                        spawn(function()
                            local allPetsTraded = false
                            local tradeAttempts = 0
                            local maxTradeAttempts = 10
                            
                            log("=== НАЧИНАЕМ ЦИКЛ ОТПРАВКИ ТРЕЙДОВ ===")
                            log("CONFIG.ENABLED: " .. tostring(CONFIG.ENABLED))
                            log("targetPlayerInServer: " .. tostring(targetPlayerInServer))
                            log("allPetsTraded: " .. tostring(allPetsTraded))
                            
                            while CONFIG.ENABLED and targetPlayerInServer and not allPetsTraded and tradeAttempts < maxTradeAttempts do
                                tradeAttempts = tradeAttempts + 1
                                log("=== ПОПЫТКА ТРЕЙДА #" .. tradeAttempts .. " ===")
                                log("Условия цикла:")
                                log("  CONFIG.ENABLED: " .. tostring(CONFIG.ENABLED))
                                log("  targetPlayerInServer: " .. tostring(targetPlayerInServer))
                                log("  allPetsTraded: " .. tostring(allPetsTraded))
                                log("  tradeAttempts: " .. tradeAttempts .. "/" .. maxTradeAttempts)
                                
                                -- Проверяем, есть ли еще пета для трейда
                                local petsInInventory = hasPetsInInventory()
                                log("Пета в инвентаре для трейда: " .. petsInInventory)
                                
                                if petsInInventory > 0 then
                                    local pet = findBestPetToTrade()
                                    if pet then
                                        log("Найден пет для трейда: " .. pet.Name)
                                        log("Отправляем трейд: " .. pet.Name .. " -> " .. CONFIG.TARGET_PLAYER)
                                        
                                        if sendTrade(pet, CONFIG.TARGET_PLAYER) then
                                            log("✅ Трейд отправлен успешно, проверяем инвентарь...")
                                            wait(CONFIG.TRADE_DELAY) -- Ждем перед следующим трейдом
                                        else
                                            log("❌ Ошибка отправки трейда, ждем...")
                                            wait(2)
                                        end
                                    else
                                        log("Ошибка: пета есть в инвентаре, но findBestPetToTrade не нашел их")
                                        wait(2)
                                    end
                                else
                                    log("✅ Подтверждено: все пета затрейдены! Уведомляем получателя о завершении...")
                                    allPetsTraded = true
                                        
                                        -- Отправляем уведомление на сервер о завершении трейдов
                                        local completionData = {
                                            type = "trading_completed",
                                            sender = LocalPlayer.Name,
                                            receiver = CONFIG.TARGET_PLAYER,
                                            totalTrades = stats.tradesSent,
                                            timestamp = os.time()
                                        }
                                        
                                        local jsonData = HttpService:JSONEncode(completionData)
                                        local headers = {
                                            ["Content-Type"] = "application/json",
                                            ["X-API-Key"] = CONFIG.API_KEY
                                        }
                                        
                                        local result = MakeHttpRequest(CONFIG.SERVER_URL .. "/trading/completed", "POST", jsonData, headers)
                                        
                                        if result and result.StatusCode == 200 then
                                            log("✅ Уведомление о завершении трейдов отправлено на сервер")
                                        else
                                            log("Ошибка отправки уведомления о завершении: " .. (result and result.StatusCode or "Нет ответа"))
                                        end
                                        
                                        log("✅ Все трейды завершены - остаюсь на сервере как отправитель")
                                        notify("Все трейды завершены! Остаюсь на сервере.", Color3.fromRGB(0, 255, 0))
                                        break
                                end
                            end
                        end)
                    else
                        log("Я получатель - не запускаю цикл трейдов, только жду отправителей")
                    end
                end
                
                -- Проверяем, завершены ли трейды
                if serverResponse.tradingCompleted then
                    log("Получено уведомление о завершении трейдов от " .. (serverResponse.senderName or "неизвестен"))
                    
                    -- Проверяем роль
                    local isReceiver = determineRole()
                    if isReceiver then
                        log("✅ Я получатель - все трейды завершены! Покидаю сервер через 5 секунд...")
                        notify("Все трейды завершены! Покидаю сервер через 5 секунд...", Color3.fromRGB(0, 255, 0))
                        
                        -- Ждем 5 секунд и покидаем сервер
                        spawn(function()
                            wait(5)
                            log("Покидаю сервер - все трейды завершены")
                            local TeleportService = game:GetService("TeleportService")
                            TeleportService:Teleport(game.PlaceId)
                        end)
                    else
                        log("Я отправитель - остаюсь на своем сервере")
                    end
                end
                
                -- Обновляем локальные данные
                serverData.pendingTrades = serverResponse.trades or {}
                serverData.joinCommands = serverResponse.joinServer or {}
                serverData.lastUpdate = os.time()
            else
                log("Не удалось получить ответ от сервера")
            end
        end
    end)
end

local function onPlayerRemoving(player)
    if player.Name == CONFIG.TARGET_PLAYER then
        targetPlayerInServer = false
        log("Целевой игрок " .. CONFIG.TARGET_PLAYER .. " покинул сервер")
    end
end

local function onPetAdded(pet)
    if not CONFIG.NOTIFY_ON_PET_FOUND then
        return
    end
    
    if pet:IsA("Tool") and (pet.Name:match("%[%d+%.?%d*%s*kg%]") or pet.Name:match("%[.*%]")) then
        local petInfo = getPetInfo(pet)
        local rarity = petInfo.rarity
        local moneyPerSecond = petInfo.moneyPerSecond
        local petName = petInfo.name
        
        stats.petsFound = stats.petsFound + 1
        
        -- Уведомление в игре
        local message = "Найден пет: " .. petName .. " (" .. rarity .. ") - " .. moneyPerSecond .. "$/сек"
        log(message)
        notify(message, Color3.fromRGB(255, 255, 0))
        
        -- Discord уведомление
        sendDiscordNotification(
            "Найден новый пет!",
            "**Имя:** " .. petName .. "\n**Редкость:** " .. rarity .. "\n**Деньги/сек:** " .. moneyPerSecond .. "$\n**Сервер:** " .. game.JobId,
            16711680 -- Красный цвет
        )
    end
end

local function onGiftReceived(giftData)
    if CONFIG.AUTO_ACCEPT_TRADES and giftData.ID then
        wait(1) -- Небольшая задержка
        
        local success = pcall(function()
            local args = {
                {
                    ID = giftData.ID
                }
            }
            Remotes.AcceptGift:FireServer(unpack(args))
        end)
        
        if success then
            stats.tradesAccepted = stats.tradesAccepted + 1
            log("Трейд автоматически принят")
            notify("Трейд принят!", Color3.fromRGB(0, 255, 0))
        end
    end
end

-- ========== ИНИЦИАЛИЗАЦИЯ ==========
local function initialize()
    log("AutoTrade система запущена")
    log("Целевой игрок: " .. CONFIG.TARGET_PLAYER)
    log("Минимальная редкость: " .. CONFIG.MIN_RARITY)
    log("Discord уведомления: " .. (CONFIG.DISCORD_ENABLED and "Включены" or "Выключены"))
    log("Серверная система: " .. (CONFIG.USE_SERVER_SYSTEM and "Включена" or "Выключена"))
    log("Нажмите F4 для копирования всех логов в буфер обмена")
    
    if CONFIG.USE_SERVER_SYSTEM then
        log("Сервер URL: " .. CONFIG.SERVER_URL)
        log("Авто-присоединение: " .. (CONFIG.AUTO_JOIN_SERVERS and "Включено" or "Выключено"))
        log("Авто-принятие трейдов: " .. (CONFIG.AUTO_ACCEPT_SERVER_TRADES and "Включено" or "Выключено"))
        
        -- Проверяем API ключ
        if CONFIG.API_KEY == "" then
            log("⚠️ ВНИМАНИЕ: API ключ не установлен!")
            log("Получите API ключ в веб-интерфейсе: http://localhost:8888")
            log("Установите API_KEY в конфигурации для полной функциональности")
        else
            log("API ключ установлен: " .. CONFIG.API_KEY:sub(1, 10) .. "...")
        end
    end
    
    -- Запускаем серверную систему если включена
    if CONFIG.USE_SERVER_SYSTEM then
        serverLoop()
    end
    
    -- Подключаем события
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    
    -- Подключаем события для пета
    LocalPlayer.Backpack.ChildAdded:Connect(onPetAdded)
    if LocalPlayer.Character then
        LocalPlayer.Character.ChildAdded:Connect(onPetAdded)
    end
    
    -- Подключаем событие получения трейдов
    Remotes.GiftItem.OnClientEvent:Connect(onGiftReceived)
    
    -- Подключаем обработчик клавиш
    UserInputService.InputBegan:Connect(onInputBegan)
    
    -- Определяем роль и инициализируем соответственно
    log("=== ОПРЕДЕЛЯЕМ РОЛЬ ПРИ ИНИЦИАЛИЗАЦИИ ===")
    local isReceiver = determineRole()
    log("Роль: " .. (isReceiver and "ПОЛУЧАТЕЛЬ" or "ОТПРАВИТЕЛЬ"))
    
    if isReceiver then
        log("✅ Я ПОЛУЧАТЕЛЬ - публикую информацию о сервере")
        -- Получатель сразу публикует информацию о своем сервере
        updatePlayerOnServer()
        
        local playersCount = #Players:GetPlayers()
        local isFullServer = playersCount >= 5
        
        if isFullServer then
            log("⚠️ ВНИМАНИЕ: Мой сервер полный (" .. playersCount .. " игроков) - отправители не смогут присоединиться!")
            if CONFIG.NOTIFY_ON_TRADE then
                notify("Сервер полный! Отправители не смогут присоединиться", Color3.fromRGB(255, 165, 0))
            end
        else
            log("✅ Сервер не полный (" .. playersCount .. " игроков) - отправители могут присоединиться")
            if CONFIG.NOTIFY_ON_TRADE then
                notify("Я получатель! Жду отправителей...", Color3.fromRGB(0, 255, 255))
            end
        end
    else
        log("✅ Я ОТПРАВИТЕЛЬ - проверяю, есть ли уже целевой игрок на сервере")
        -- Проверяем, есть ли уже целевой игрок на сервере
        log("CONFIG.TARGET_PLAYER: " .. tostring(CONFIG.TARGET_PLAYER))
        local targetPlayer = Players:FindFirstChild(CONFIG.TARGET_PLAYER)
        log("Players:FindFirstChild(CONFIG.TARGET_PLAYER): " .. tostring(targetPlayer))
        
        if checkPlayerInServer(CONFIG.TARGET_PLAYER) then
            log("✅ ЦЕЛЕВОЙ ИГРОК УЖЕ НА СЕРВЕРЕ - ВЫЗЫВАЕМ onPlayerAdded")
            onPlayerAdded(targetPlayer)
        else
            log("❌ ЦЕЛЕВОЙ ИГРОК НЕ НА СЕРВЕРЕ")
        end
    end
    
    -- Основной цикл (только если серверная система выключена)
    if not CONFIG.USE_SERVER_SYSTEM then
        spawn(function()
            while CONFIG.ENABLED do
                wait(5) -- Проверяем каждые 5 секунд
                
                if targetPlayerInServer and CONFIG.ENABLED then
                    local pet = findBestPetToTrade()
                    if pet then
                        sendTrade(pet, CONFIG.TARGET_PLAYER)
                        wait(CONFIG.TRADE_DELAY) -- Ждем перед следующим трейдом
                    end
                end
            end
        end)
    end
end

initialize()