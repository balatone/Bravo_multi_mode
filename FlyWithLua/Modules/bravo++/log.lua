local log = {}
local logMsg = logMsg

local constants = require("bravo++.config.constants")
log.LOG_DEBUG = constants.LOG_DEBUG
log.LOG_INFO = constants.LOG_INFO
log.LOG_WARNING = constants.LOG_WARNING
log.LOG_ERROR = constants.LOG_ERROR
log.NO_LOG = constants.NO_LOG

log.LOG_LEVEL = log.LOG_DEBUG

function log.debug(message)
    if log.LOG_LEVEL >= log.LOG_DEBUG then
        logMsg(string.format("%.3f [BRAVO++ %s]: %s", os.clock(), "DEBUG", message))
    end
end

function log.info(message)
    if log.LOG_LEVEL >= log.LOG_INFO then
        logMsg(string.format("%.3f [BRAVO++ %s]: %s", os.clock(), "INFO", message))
    end
end

function log.warning(message)
    if log.LOG_LEVEL >= log.LOG_WARNING then
        logMsg(string.format("%.3f [BRAVO++ %s]: %s", os.clock(), "WARN", message))
    end
end

function log.error(message)
    if log.LOG_LEVEL >= log.LOG_ERROR then
        logMsg(string.format("%.3f [BRAVO++ %s]: %s", os.clock(), "ERROR", message))
    end
end

return log
