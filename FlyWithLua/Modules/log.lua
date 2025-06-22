local log = {}

log.LOG_DEBUG = 4
log.LOG_INFO = 3
log.LOG_WARNING = 2
log.LOG_ERROR = 1
log.NO_LOG = 0

log.LOG_LEVEL = log.LOG_DEBUG

function log.debug(message)
    if log.LOG_LEVEL >= log.LOG_DEBUG then
        logMsg(get_formatted_message("DEBUG", message))
    end    
end

function log.info(message)
    if log.LOG_LEVEL >= log.LOG_INFO then
        logMsg(get_formatted_message("INFO", message))
    end    
end

function log.warning(message)
    if log.LOG_LEVEL >= log.LOG_WARNING then
        logMsg(get_formatted_message("WARN", message))
    end    
end

function log.error(message)
    if log.LOG_LEVEL >= log.LOG_ERROR then
        logMsg(get_formatted_message("ERROR", message))
    end    
end

function get_formatted_message(level, message)
    return string.format("%.3f [BRAVO++ %s]: %s", os.clock(), level, message)
end

return log