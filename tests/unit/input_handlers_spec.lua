-- ************************************************
-- Unit tests for input_handlers module (FEAT-019)
-- ************************************************

local input_handlers = require("bravo++.input.handlers")

describe("input_handlers module", function()
    local mock_dispatch
    local mock_decoder_fn
    local mock_selector_fn

    before_each(function()
        mock_dispatch = {
            trim_nose_up_called = false,
            trim_nose_down_called = false,
            knob_increase_called = false,
            knob_decrease_called = false,
            selector_index = nil,
        }
        mock_dispatch.trim_nose_up = function() mock_dispatch.trim_nose_up_called = true end
        mock_dispatch.trim_nose_down = function() mock_dispatch.trim_nose_down_called = true end
        mock_dispatch.knob_increase = function() mock_dispatch.knob_increase_called = true end
        mock_dispatch.knob_decrease = function() mock_dispatch.knob_decrease_called = true end
        mock_dispatch.set_selector_index = function(idx) mock_dispatch.selector_index = idx end

        mock_decoder_fn = function(handlers)
            mock_dispatch.handlers = handlers
        end
        mock_selector_fn = function(value)
            mock_dispatch.selector_index = value
        end

        input_handlers.init({
            dispatch_module = mock_dispatch,
            decoder_handler_fn = mock_decoder_fn,
            selector_handler_fn = mock_selector_fn,
        })
    end)

    describe("init", function()
        it("should accept dispatch_module and decoder_handler_fn", function()
            input_handlers.init({
                dispatch_module = mock_dispatch,
                decoder_handler_fn = mock_decoder_fn,
            })
            -- init should not error
        end)

        it("should handle nil options", function()
            input_handlers.init(nil) -- should not error
        end)

        it("should handle missing dispatch_module", function()
            input_handlers.init({})
            -- Should not error
        end)
    end)

    describe("handle_trim", function()
        it("should call trim_nose_up for up direction", function()
            input_handlers.handle_trim("up")
            assert.is_true(mock_dispatch.trim_nose_up_called)
        end)

        it("should call trim_nose_down for down direction", function()
            input_handlers.handle_trim("down")
            assert.is_true(mock_dispatch.trim_nose_down_called)
        end)

        it("should not call trim for unknown direction", function()
            input_handlers.handle_trim("unknown")
            assert.is_false(mock_dispatch.trim_nose_up_called)
            assert.is_false(mock_dispatch.trim_nose_down_called)
        end)

        it("should warn when dispatch_module not initialized", function()
            input_handlers.init({})
            input_handlers.handle_trim("up") -- should not error
        end)
    end)

    describe("handle_twist", function()
        it("should call knob_increase for increase direction", function()
            input_handlers.handle_twist("increase")
            assert.is_true(mock_dispatch.knob_increase_called)
        end)

        it("should call knob_decrease for decrease direction", function()
            input_handlers.handle_twist("decrease")
            assert.is_true(mock_dispatch.knob_decrease_called)
        end)

        it("should not call twist for unknown direction", function()
            input_handlers.handle_twist("unknown")
            assert.is_false(mock_dispatch.knob_increase_called)
            assert.is_false(mock_dispatch.knob_decrease_called)
        end)

        it("should warn when dispatch_module not initialized", function()
            input_handlers.init({})
            input_handlers.handle_twist("increase") -- should not error
        end)
    end)

    describe("handle_decoder_event", function()
        it("should handle rotary_cw as twist increase", function()
            input_handlers.handle_decoder_event("rotary_cw", nil)
            assert.is_true(mock_dispatch.knob_increase_called)
        end)

        it("should handle rotary_ccw as twist decrease", function()
            input_handlers.handle_decoder_event("rotary_ccw", nil)
            assert.is_true(mock_dispatch.knob_decrease_called)
        end)

        it("should handle trim up event", function()
            input_handlers.handle_decoder_event("trim", "up")
            assert.is_true(mock_dispatch.trim_nose_up_called)
        end)

        it("should handle trim down event", function()
            input_handlers.handle_decoder_event("trim", "down")
            assert.is_true(mock_dispatch.trim_nose_down_called)
        end)

        it("should handle selector event", function()
            input_handlers.handle_decoder_event("selector", 3)
            assert.equals(3, mock_dispatch.selector_index)
        end)

        it("should not error on unknown event type", function()
            input_handlers.handle_decoder_event("unknown", nil)
        end)
    end)

    describe("register_decoder_handlers", function()
        it("should register handlers with decoder_handler_fn", function()
            input_handlers.register_decoder_handlers()
            assert.is_table(mock_dispatch.handlers)
            assert.is_function(mock_dispatch.handlers.on_selector_changed)
            assert.is_function(mock_dispatch.handlers.on_rotary_cw)
            assert.is_function(mock_dispatch.handlers.on_rotary_ccw)
            assert.is_function(mock_dispatch.handlers.on_trim_changed)
        end)

        it("should warn when decoder_handler_fn not set", function()
            input_handlers.init({ dispatch_module = mock_dispatch })
            input_handlers.register_decoder_handlers() -- should not error
        end)

        it("should invoke rotary_cw handler correctly", function()
            input_handlers.register_decoder_handlers()
            mock_dispatch.handlers.on_rotary_cw()
            assert.is_true(mock_dispatch.knob_increase_called)
        end)

        it("should invoke rotary_ccw handler correctly", function()
            input_handlers.register_decoder_handlers()
            mock_dispatch.handlers.on_rotary_ccw()
            assert.is_true(mock_dispatch.knob_decrease_called)
        end)

        it("should invoke trim_changed handler for up", function()
            input_handlers.register_decoder_handlers()
            mock_dispatch.handlers.on_trim_changed("up")
            assert.is_true(mock_dispatch.trim_nose_up_called)
        end)

        it("should invoke trim_changed handler for down", function()
            input_handlers.register_decoder_handlers()
            mock_dispatch.handlers.on_trim_changed("down")
            assert.is_true(mock_dispatch.trim_nose_down_called)
        end)

        it("should invoke selector_changed handler", function()
            input_handlers.register_decoder_handlers()
            mock_dispatch.handlers.on_selector_changed(2)
            assert.equals(2, mock_dispatch.selector_index)
        end)
    end)
end)
