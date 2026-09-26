/// Messages API event streams in the documented wire shape
enum SSEFixtures {
    static let messageStart = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":25,"output_tokens":1}}}


        """

    static let ping = """
        event: ping
        data: {"type": "ping"}


        """

    static let messageStop = """
        event: message_stop
        data: {"type":"message_stop"}


        """

    static func messageDelta(stopReason: String, outputTokens: Int) -> String {
        """
        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"\(stopReason)","stop_sequence":null},"usage":{"output_tokens":\(outputTokens)}}


        """
    }

    static let textOnly =
        messageStart + """
            event: content_block_start
            data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

            """ + ping + """
            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}

            event: content_block_stop
            data: {"type":"content_block_stop","index":0}


            """ + messageDelta(stopReason: "end_turn", outputTokens: 12) + messageStop

    static let thinkingThenText =
        messageStart + """
            event: content_block_start
            data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"A cube"}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig-1"}}

            event: content_block_stop
            data: {"type":"content_block_stop","index":0}

            event: content_block_start
            data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Done."}}

            event: content_block_stop
            data: {"type":"content_block_stop","index":1}


            """ + messageDelta(stopReason: "end_turn", outputTokens: 40) + messageStop

    static let splitToolUse =
        messageStart + """
            event: content_block_start
            data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"create_primitive","input":{}}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":""}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"type\\": \\"bo"}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"x\\", \\"size\\": 2}"}}

            event: content_block_stop
            data: {"type":"content_block_stop","index":0}


            """ + messageDelta(stopReason: "tool_use", outputTokens: 30) + messageStop

    static let multipleBlocks =
        messageStart + """
            event: content_block_start
            data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig-2"}}

            event: content_block_stop
            data: {"type":"content_block_stop","index":0}

            event: content_block_start
            data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Two parts."}}

            event: content_block_stop
            data: {"type":"content_block_stop","index":1}

            event: content_block_start
            data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_a","name":"create_primitive","input":{}}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\\"type\\": \\"box\\"}"}}

            event: content_block_stop
            data: {"type":"content_block_stop","index":2}

            event: content_block_start
            data: {"type":"content_block_start","index":3,"content_block":{"type":"tool_use","id":"toolu_b","name":"create_primitive","input":{}}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":3,"delta":{"type":"input_json_delta","partial_json":"{\\"type\\": \\"sphere\\"}"}}

            event: content_block_stop
            data: {"type":"content_block_stop","index":3}


            """ + messageDelta(stopReason: "tool_use", outputTokens: 60) + messageStop

    static let partialText =
        messageStart + """
            event: content_block_start
            data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Working"}}


            """

    static let overloadedError = """
        event: error
        data: {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}


        """
}
