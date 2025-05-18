local log = {}

log.LOG_DEBUG = 4
log.LOG_INFO = 3
log.LOG_WARNING = 2
log.LOG_ERROR = 1
log.NO_LOG = 0

log.LOG_LEVEL = log.LOG_DEBUG

function log.debug(message)
    if log.LOG_LEVEL >= log.LOG_DEBUG then
        logMsg("[DEBUG]: " .. message)
    end    
end

function log.info(message)
    if log.LOG_LEVEL >= log.LOG_INFO then
        logMsg("[INFO]: " .. message)
    end    
end

function log.warning(message)
    if log.LOG_LEVEL >= log.LOG_WARNING then
        logMsg("[WARN]: " .. message)
    end    
end

function log.error(message)
    if log.LOG_LEVEL >= log.LOG_ERROR then
        logMsg("[ERROR]: " .. message)
    end    
end

return log