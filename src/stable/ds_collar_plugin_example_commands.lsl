/* =============================================================================
   PLUGIN: ds_collar_plugin_example_commands.lsl (v1.0)

   PURPOSE: Example plugin demonstrating chat command registration and handling

   COMMANDS:
   - hello       - Greets the speaker
   - echo <text> - Echoes back the provided text
   - whoami      - Reports speaker's ACL level
   - time        - Reports current SLT time

   ACL REQUIREMENTS:
   - hello: Public (ACL 1+)
   - echo: Public (ACL 1+)
   - whoami: Public (ACL 1+)
   - time: Owned wearer (ACL 2+)

   DEMONSTRATES:
   1. Command registration on startup
   2. Receiving cmd_execute messages
   3. Per-command ACL validation
   4. Private responses via llRegionSayTo()
   5. Argument parsing

   NOTE: This is a teaching example. Real plugins should integrate
         with their actual functionality (poses, bell, leash, etc.)
   ============================================================================= */

integer DEBUG = FALSE;

/* ═══════════════════════════════════════════════════════════
   CONSOLIDATED ABI
   ═══════════════════════════════════════════════════════════ */
integer KERNEL_LIFECYCLE = 500;
integer SETTINGS_BUS = 800;
integer COMMANDS_BUS = 1000;

/* ═══════════════════════════════════════════════════════════
   PLUGIN IDENTITY
   ═══════════════════════════════════════════════════════════ */
string PLUGIN_CONTEXT = "example_commands";
string PLUGIN_LABEL = "Example";
integer PLUGIN_MIN_ACL = 1;  // Public access for menu

/* ═══════════════════════════════════════════════════════════
   COMMAND REGISTRATION
   ═══════════════════════════════════════════════════════════ */
list REGISTERED_COMMANDS = ["hello", "echo", "whoami", "time"];

/* ═══════════════════════════════════════════════════════════
   HELPERS
   ═══════════════════════════════════════════════════════════ */
integer logd(string msg) {
    if (DEBUG) llOwnerSay("[EXAMPLE-CMD] " + msg);
    return FALSE;
}

integer json_has(string j, list path) {
    return (llJsonGetValue(j, path) != JSON_INVALID);
}

string get_slt_time() {
    string timestamp = llGetTimestamp();
    // Extract time portion (HH:MM:SS)
    string time_part = llGetSubString(timestamp, 11, 18);
    return time_part + " SLT";
}

/* ═══════════════════════════════════════════════════════════
   LIFECYCLE MANAGEMENT
   ═══════════════════════════════════════════════════════════ */

register_self() {
    // Register as a plugin
    string msg = llList2Json(JSON_OBJECT, [
        "type", "register",
        "context", PLUGIN_CONTEXT,
        "label", PLUGIN_LABEL,
        "min_acl", PLUGIN_MIN_ACL,
        "script", llGetScriptName()
    ]);
    llMessageLinked(LINK_SET, KERNEL_LIFECYCLE, msg, NULL_KEY);
    logd("Registered with kernel");
}

send_pong() {
    string msg = llList2Json(JSON_OBJECT, [
        "type", "pong",
        "context", PLUGIN_CONTEXT
    ]);
    llMessageLinked(LINK_SET, KERNEL_LIFECYCLE, msg, NULL_KEY);
}

register_commands() {
    // Register our commands with the chat commands module
    string msg = llList2Json(JSON_OBJECT, [
        "type", "cmd_register",
        "context", PLUGIN_CONTEXT,
        "commands", llList2Json(JSON_ARRAY, REGISTERED_COMMANDS)
    ]);
    llMessageLinked(LINK_SET, COMMANDS_BUS, msg, NULL_KEY);
    logd("Registered commands: " + llDumpList2String(REGISTERED_COMMANDS, ", "));
}

unregister_commands() {
    // Unregister on shutdown
    string msg = llList2Json(JSON_OBJECT, [
        "type", "cmd_unregister",
        "context", PLUGIN_CONTEXT
    ]);
    llMessageLinked(LINK_SET, COMMANDS_BUS, msg, NULL_KEY);
    logd("Unregistered commands");
}

/* ═══════════════════════════════════════════════════════════
   COMMAND EXECUTION
   ═══════════════════════════════════════════════════════════ */

execute_command(string command, string args, key speaker, integer speaker_acl, integer channel) {
    logd("Executing: " + command + " (args: " + args + ") by " + llKey2Name(speaker) + " (ACL " + (string)speaker_acl + ")");

    // Route to specific command handler
    if (command == "hello") {
        cmd_hello(speaker, speaker_acl);
    }
    else if (command == "echo") {
        cmd_echo(speaker, args, speaker_acl);
    }
    else if (command == "whoami") {
        cmd_whoami(speaker, speaker_acl);
    }
    else if (command == "time") {
        cmd_time(speaker, speaker_acl);
    }
    else {
        // Unknown command (shouldn't happen if registry is correct)
        llRegionSayTo(speaker, 0, "Unknown command: " + command);
    }
}

/* ═══════════════════════════════════════════════════════════
   COMMAND HANDLERS
   ═══════════════════════════════════════════════════════════ */

cmd_hello(key speaker, integer acl) {
    // ACL check: Public (1+)
    if (acl < 1) {
        llRegionSayTo(speaker, 0, "Access denied.");
        return;
    }

    // Respond with greeting
    string name = llKey2Name(speaker);
    llRegionSayTo(speaker, 0, "Hello, " + name + "!");
}

cmd_echo(key speaker, string text, integer acl) {
    // ACL check: Public (1+)
    if (acl < 1) {
        llRegionSayTo(speaker, 0, "Access denied.");
        return;
    }

    // Check if text provided
    if (text == "") {
        llRegionSayTo(speaker, 0, "Usage: echo <text>");
        return;
    }

    // Echo back
    llRegionSayTo(speaker, 0, "Echo: " + text);
}

cmd_whoami(key speaker, integer acl) {
    // ACL check: Public (1+)
    if (acl < 1) {
        llRegionSayTo(speaker, 0, "Access denied.");
        return;
    }

    // Report ACL level with description
    string acl_desc;
    if (acl == -1) acl_desc = "Blacklisted";
    else if (acl == 0) acl_desc = "No Access";
    else if (acl == 1) acl_desc = "Public";
    else if (acl == 2) acl_desc = "Owned Wearer";
    else if (acl == 3) acl_desc = "Trustee";
    else if (acl == 4) acl_desc = "Unowned Wearer";
    else if (acl == 5) acl_desc = "Primary Owner";
    else acl_desc = "Unknown";

    llRegionSayTo(speaker, 0, "Your ACL: " + (string)acl + " (" + acl_desc + ")");
}

cmd_time(key speaker, integer acl) {
    // ACL check: Owned wearer (2+)
    if (acl < 2) {
        llRegionSayTo(speaker, 0, "Access denied. Requires ACL 2+ (Owned Wearer).");
        return;
    }

    // Report time
    llRegionSayTo(speaker, 0, "Current time: " + get_slt_time());
}

/* ═══════════════════════════════════════════════════════════
   EVENTS
   ═══════════════════════════════════════════════════════════ */

default {
    state_entry() {
        register_self();

        // Request settings (even though we don't use any)
        string msg = llList2Json(JSON_OBJECT, [
            "type", "settings_get"
        ]);
        llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);

        // Register commands (do this after brief delay to ensure commands module is ready)
        llSetTimerEvent(1.0);  // Register commands after 1 second

        logd("Ready");
    }

    timer() {
        llSetTimerEvent(0.0);  // One-shot timer
        register_commands();
    }

    on_rez(integer start_param) {
        llResetScript();
    }

    changed(integer change) {
        if (change & CHANGED_OWNER) {
            llResetScript();
        }
    }

    link_message(integer sender, integer num, string msg, key id) {
        // ===== KERNEL LIFECYCLE =====
        if (num == KERNEL_LIFECYCLE) {
            if (!json_has(msg, ["type"])) return;
            string msg_type = llJsonGetValue(msg, ["type"]);

            if (msg_type == "register_now") {
                register_self();
                return;
            }

            if (msg_type == "ping") {
                send_pong();
                return;
            }

            if (msg_type == "soft_reset" || msg_type == "soft_reset_all") {
                if (json_has(msg, ["context"])) {
                    string target_context = llJsonGetValue(msg, ["context"]);
                    if (target_context != "" && target_context != PLUGIN_CONTEXT) {
                        return;
                    }
                }
                unregister_commands();  // Clean up before reset
                llResetScript();
            }

            return;
        }

        // ===== SETTINGS (we don't use any, but handle for completeness) =====
        if (num == SETTINGS_BUS) {
            // Ignore settings messages
            return;
        }

        // ===== COMMAND EXECUTION =====
        if (num == COMMANDS_BUS) {
            if (!json_has(msg, ["type"])) return;
            string msg_type = llJsonGetValue(msg, ["type"]);

            if (msg_type == "cmd_execute") {
                // Extract command details
                if (!json_has(msg, ["command"])) return;
                if (!json_has(msg, ["speaker"])) return;
                if (!json_has(msg, ["speaker_acl"])) return;

                string command = llJsonGetValue(msg, ["command"]);
                key speaker = (key)llJsonGetValue(msg, ["speaker"]);
                integer speaker_acl = (integer)llJsonGetValue(msg, ["speaker_acl"]);

                string args = "";
                if (json_has(msg, ["args"])) {
                    args = llJsonGetValue(msg, ["args"]);
                }

                integer channel = 0;
                if (json_has(msg, ["channel"])) {
                    channel = (integer)llJsonGetValue(msg, ["channel"]);
                }

                // Execute the command
                execute_command(command, args, speaker, speaker_acl, channel);
                return;
            }

            if (msg_type == "cmd_error") {
                // Handle registration errors
                if (json_has(msg, ["error"])) {
                    string error = llJsonGetValue(msg, ["error"]);
                    llOwnerSay("[EXAMPLE-CMD] Registration error: " + error);
                }
                return;
            }

            return;
        }
    }
}
