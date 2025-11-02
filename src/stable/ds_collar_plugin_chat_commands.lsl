/* =============================================================================
   PLUGIN: ds_collar_plugin_chat_commands.lsl (v1.0)

   PURPOSE: Configuration UI for chat command system

   FEATURES:
   - View current chat command configuration
   - Change command prefix (ACL 2+)
   - Toggle channel 0/1 listeners (ACL 2+)
   - Advanced settings: Enable/disable listener, reset (ACL 3+)
   - Text input for prefix changes with validation

   ACL REQUIREMENTS:
   - Minimum ACL 2 (Owned wearer) to access plugin
   - ACL 3+ (Trustee/Owner) required for Advanced menu

   PREFIX VALIDATION:
   - Lowercase letters only (a-z)
   - 2-7 characters
   ============================================================================= */

integer DEBUG = FALSE;

/* ═══════════════════════════════════════════════════════════
   CONSOLIDATED ABI
   ═══════════════════════════════════════════════════════════ */
integer KERNEL_LIFECYCLE = 500;
integer AUTH_BUS = 700;
integer SETTINGS_BUS = 800;
integer UI_BUS = 900;
integer DIALOG_BUS = 950;
integer COMMANDS_BUS = 1000;

/* ═══════════════════════════════════════════════════════════
   PLUGIN IDENTITY
   ═══════════════════════════════════════════════════════════ */
string PLUGIN_CONTEXT = "chat_commands";
string PLUGIN_LABEL = "Chat Cmds";
integer PLUGIN_MIN_ACL = 2;  // Owned wearer minimum

/* ═══════════════════════════════════════════════════════════
   SETTINGS KEYS
   ═══════════════════════════════════════════════════════════ */
string KEY_CMD_PREFIX = "cmd_prefix";
string KEY_CMD_ENABLED = "cmd_enabled";
string KEY_CMD_INITIALIZED = "cmd_initialized";
string KEY_CMD_AUTO_MODE = "cmd_auto_mode";
string KEY_CMD_CH0_ENABLED = "cmd_ch0_enabled";
string KEY_CMD_CH1_ENABLED = "cmd_ch1_enabled";

/* ═══════════════════════════════════════════════════════════
   STATE
   ═══════════════════════════════════════════════════════════ */
string CommandPrefix = "";
integer ListenerEnabled = FALSE;
integer Initialized = FALSE;
integer AutoMode = FALSE;
integer Ch0Enabled = FALSE;
integer Ch1Enabled = FALSE;

// Session state
key CurrentUser = NULL_KEY;
integer UserAcl = -999;
string SessionId = "";
string MenuContext = "";
integer TextChannelHandle = 0;
integer TextChannel = 0;

/* ═══════════════════════════════════════════════════════════
   HELPERS
   ═══════════════════════════════════════════════════════════ */
integer logd(string msg) {
    if (DEBUG) llOwnerSay("[CHATCMD-UI] " + msg);
    return FALSE;
}

integer json_has(string j, list path) {
    return (llJsonGetValue(j, path) != JSON_INVALID);
}

string generate_session_id() {
    return PLUGIN_CONTEXT + "_" + (string)llGetUnixTime();
}

integer is_valid_prefix(string prefix) {
    integer len = llStringLength(prefix);
    if (len < 2 || len > 7) return FALSE;

    // Check all lowercase letters
    integer i;
    for (i = 0; i < len; i++) {
        string char = llGetSubString(prefix, i, i);
        if (char < "a" || char > "z") return FALSE;
    }

    return TRUE;
}

/* ═══════════════════════════════════════════════════════════
   LIFECYCLE MANAGEMENT
   ═══════════════════════════════════════════════════════════ */

register_self() {
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

/* ═══════════════════════════════════════════════════════════
   SETTINGS CONSUMPTION
   ═══════════════════════════════════════════════════════════ */

apply_settings_sync(string msg) {
    if (!json_has(msg, ["kv"])) return;

    string kv_json = llJsonGetValue(msg, ["kv"]);

    if (json_has(kv_json, [KEY_CMD_PREFIX])) {
        CommandPrefix = llJsonGetValue(kv_json, [KEY_CMD_PREFIX]);
    }
    if (json_has(kv_json, [KEY_CMD_ENABLED])) {
        ListenerEnabled = (integer)llJsonGetValue(kv_json, [KEY_CMD_ENABLED]);
    }
    if (json_has(kv_json, [KEY_CMD_INITIALIZED])) {
        Initialized = (integer)llJsonGetValue(kv_json, [KEY_CMD_INITIALIZED]);
    }
    if (json_has(kv_json, [KEY_CMD_AUTO_MODE])) {
        AutoMode = (integer)llJsonGetValue(kv_json, [KEY_CMD_AUTO_MODE]);
    }
    if (json_has(kv_json, [KEY_CMD_CH0_ENABLED])) {
        Ch0Enabled = (integer)llJsonGetValue(kv_json, [KEY_CMD_CH0_ENABLED]);
    }
    if (json_has(kv_json, [KEY_CMD_CH1_ENABLED])) {
        Ch1Enabled = (integer)llJsonGetValue(kv_json, [KEY_CMD_CH1_ENABLED]);
    }

    logd("Settings sync complete");
}

apply_settings_delta(string msg) {
    if (!json_has(msg, ["op"])) return;

    string op = llJsonGetValue(msg, ["op"]);

    if (op == "set") {
        if (!json_has(msg, ["changes"])) return;
        string changes = llJsonGetValue(msg, ["changes"]);

        if (json_has(changes, [KEY_CMD_PREFIX])) {
            CommandPrefix = llJsonGetValue(changes, [KEY_CMD_PREFIX]);
            logd("Prefix updated: " + CommandPrefix);
        }
        if (json_has(changes, [KEY_CMD_ENABLED])) {
            ListenerEnabled = (integer)llJsonGetValue(changes, [KEY_CMD_ENABLED]);
        }
        if (json_has(changes, [KEY_CMD_CH0_ENABLED])) {
            Ch0Enabled = (integer)llJsonGetValue(changes, [KEY_CMD_CH0_ENABLED]);
        }
        if (json_has(changes, [KEY_CMD_CH1_ENABLED])) {
            Ch1Enabled = (integer)llJsonGetValue(changes, [KEY_CMD_CH1_ENABLED]);
        }
    }
}

/* ═══════════════════════════════════════════════════════════
   MENU SYSTEM
   ═══════════════════════════════════════════════════════════ */

show_menu(string context, string title, string body, list buttons) {
    SessionId = generate_session_id();
    MenuContext = context;

    string msg = llList2Json(JSON_OBJECT, [
        "type", "dialog_open",
        "session_id", SessionId,
        "user", (string)CurrentUser,
        "title", title,
        "body", body,
        "buttons", llList2Json(JSON_ARRAY, buttons),
        "timeout", 60
    ]);
    llMessageLinked(LINK_SET, DIALOG_BUS, msg, NULL_KEY);
}

show_main_menu() {
    string body = "Chat Commands\n\n";
    body += "Prefix: " + CommandPrefix + "\n";
    body += "Status: " + (ListenerEnabled ? "Active" : "Inactive") + "\n";
    body += "Ch0: " + (Ch0Enabled ? "ON" : "OFF") + "  ";
    body += "Ch1: " + (Ch1Enabled ? "ON" : "OFF");

    // Button layout (bottom-left to top-right):
    // [Chg Pfx][Advanced][       ]
    // [Back   ][Ch0: XX ][Ch1: XX]

    string ch0_label = Ch0Enabled ? "Ch0: ON" : "Ch0: OFF";
    string ch1_label = Ch1Enabled ? "Ch1: ON" : "Ch1: OFF";

    list buttons = [
        "Back",
        ch0_label,
        ch1_label,
        "Chg Pfx"
    ];

    // Add Advanced button only for ACL 3+
    if (UserAcl >= 3) {
        buttons += ["Advanced"];
    }

    show_menu("main", "Chat Commands", body, buttons);
}

show_advanced_menu() {
    string body = "Advanced Settings\n\n";
    body += "Listener: " + (ListenerEnabled ? "ENABLED" : "DISABLED") + "\n\n";
    body += "Warning: Disabling listener\n";
    body += "stops all chat commands.";

    // Button layout:
    // [       ][       ][       ]
    // [       ][       ][       ]
    // [Back   ][Toggle ][Reset  ]

    string toggle_label = ListenerEnabled ? "Disable" : "Enable";

    list buttons = [
        "Back",
        toggle_label,
        "Reset"
    ];

    show_menu("advanced", "Advanced", body, buttons);
}

/* ═══════════════════════════════════════════════════════════
   TEXT INPUT
   ═══════════════════════════════════════════════════════════ */

request_prefix_input() {
    // Generate random channel for text input
    TextChannel = (integer)(llFrand(900000.0) + 100000);

    // Close any existing listen
    if (TextChannelHandle != 0) {
        llListenRemove(TextChannelHandle);
    }

    // Open new listen
    TextChannelHandle = llListen(TextChannel, "", CurrentUser, "");

    // Show text box
    llTextBox(CurrentUser,
        "Enter new command prefix:\n" +
        "- Lowercase letters only (a-z)\n" +
        "- 2-7 characters\n" +
        "Examples: cmd, belle, mycmd",
        TextChannel);

    MenuContext = "awaiting_prefix";
    logd("Requested prefix input on channel " + (string)TextChannel);
}

handle_prefix_input(string text) {
    // Close listen
    if (TextChannelHandle != 0) {
        llListenRemove(TextChannelHandle);
        TextChannelHandle = 0;
    }

    // Validate
    if (!is_valid_prefix(text)) {
        llRegionSayTo(CurrentUser, 0, "Invalid prefix. Must be 2-7 lowercase letters.");
        show_main_menu();
        return;
    }

    // Send to commands module
    string msg = llList2Json(JSON_OBJECT, [
        "type", "cmd_set_prefix",
        "prefix", text
    ]);
    llMessageLinked(LINK_SET, COMMANDS_BUS, msg, NULL_KEY);

    llRegionSayTo(CurrentUser, 0, "Prefix changed to: " + text);
    CommandPrefix = text;  // Update local cache
    show_main_menu();
}

/* ═══════════════════════════════════════════════════════════
   BUTTON HANDLER
   ═══════════════════════════════════════════════════════════ */

handle_button_click(string button) {
    logd("Button: " + button + " in context: " + MenuContext);

    if (MenuContext == "main") {
        if (button == "Back") {
            return_to_root();
        }
        else if (button == "Chg Pfx") {
            request_prefix_input();
        }
        else if (button == "Ch0: ON" || button == "Ch0: OFF") {
            toggle_channel_0();
        }
        else if (button == "Ch1: ON" || button == "Ch1: OFF") {
            toggle_channel_1();
        }
        else if (button == "Advanced") {
            if (UserAcl >= 3) {
                show_advanced_menu();
            } else {
                llRegionSayTo(CurrentUser, 0, "Access denied. Trustee or higher required.");
                show_main_menu();
            }
        }
    }
    else if (MenuContext == "advanced") {
        if (button == "Back") {
            show_main_menu();
        }
        else if (button == "Enable" || button == "Disable") {
            toggle_listener();
        }
        else if (button == "Reset") {
            reset_system();
        }
    }
}

/* ═══════════════════════════════════════════════════════════
   SETTINGS MODIFICATION
   ═══════════════════════════════════════════════════════════ */

toggle_channel_0() {
    Ch0Enabled = !Ch0Enabled;

    string msg = llList2Json(JSON_OBJECT, [
        "type", "set",
        "key", KEY_CMD_CH0_ENABLED,
        "value", (string)Ch0Enabled
    ]);
    llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);

    llRegionSayTo(CurrentUser, 0, "Channel 0: " + (Ch0Enabled ? "ON" : "OFF"));
    show_main_menu();
}

toggle_channel_1() {
    Ch1Enabled = !Ch1Enabled;

    string msg = llList2Json(JSON_OBJECT, [
        "type", "set",
        "key", KEY_CMD_CH1_ENABLED,
        "value", (string)Ch1Enabled
    ]);
    llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);

    llRegionSayTo(CurrentUser, 0, "Channel 1: " + (Ch1Enabled ? "ON" : "OFF"));
    show_main_menu();
}

toggle_listener() {
    ListenerEnabled = !ListenerEnabled;

    string msg = llList2Json(JSON_OBJECT, [
        "type", "set",
        "key", KEY_CMD_ENABLED,
        "value", (string)ListenerEnabled
    ]);
    llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);

    llRegionSayTo(CurrentUser, 0, "Listener: " + (ListenerEnabled ? "ENABLED" : "DISABLED"));
    show_advanced_menu();
}

reset_system() {
    llRegionSayTo(CurrentUser, 0, "Resetting chat command system...");

    // Reset to defaults
    string msg = llList2Json(JSON_OBJECT, [
        "type", "set",
        "key", KEY_CMD_INITIALIZED,
        "value", "0"
    ]);
    llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);

    // Will trigger auto-init on next boot
    llRegionSayTo(CurrentUser, 0, "System will reinitialize on next reset.");
    return_to_root();
}

/* ═══════════════════════════════════════════════════════════
   NAVIGATION
   ═══════════════════════════════════════════════════════════ */

return_to_root() {
    string msg = llList2Json(JSON_OBJECT, [
        "type", "return",
        "user", (string)CurrentUser
    ]);
    llMessageLinked(LINK_SET, UI_BUS, msg, NULL_KEY);
    cleanup_session();
}

cleanup_session() {
    // Close any text listeners
    if (TextChannelHandle != 0) {
        llListenRemove(TextChannelHandle);
        TextChannelHandle = 0;
    }

    CurrentUser = NULL_KEY;
    UserAcl = -999;
    SessionId = "";
    MenuContext = "";
    logd("Session cleaned up");
}

/* ═══════════════════════════════════════════════════════════
   ACL HANDLING
   ═══════════════════════════════════════════════════════════ */

request_acl(key user) {
    string msg = llList2Json(JSON_OBJECT, [
        "type", "acl_query",
        "avatar", (string)user
    ]);
    llMessageLinked(LINK_SET, AUTH_BUS, msg, user);
    logd("ACL query sent for " + llKey2Name(user));
}

handle_acl_result(key avatar, integer level) {
    if (avatar != CurrentUser) return;

    UserAcl = level;
    logd("ACL result: " + (string)level);

    // Check minimum ACL
    if (level < PLUGIN_MIN_ACL) {
        llRegionSayTo(avatar, 0, "Access denied.");
        cleanup_session();
        return;
    }

    // Show main menu
    show_main_menu();
}

/* ═══════════════════════════════════════════════════════════
   EVENTS
   ═══════════════════════════════════════════════════════════ */

default {
    state_entry() {
        register_self();

        // Request settings
        string msg = llList2Json(JSON_OBJECT, [
            "type", "settings_get"
        ]);
        llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);

        logd("Ready");
    }

    listen(integer channel, string name, key id, string message) {
        // Text input for prefix change
        if (id == CurrentUser && channel == TextChannel && MenuContext == "awaiting_prefix") {
            handle_prefix_input(message);
        }
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
                llResetScript();
            }

            return;
        }

        // ===== SETTINGS SYNC/DELTA =====
        if (num == SETTINGS_BUS) {
            if (!json_has(msg, ["type"])) return;
            string msg_type = llJsonGetValue(msg, ["type"]);

            if (msg_type == "settings_sync") {
                apply_settings_sync(msg);
                return;
            }

            if (msg_type == "settings_delta") {
                apply_settings_delta(msg);
                return;
            }

            return;
        }

        // ===== UI START =====
        if (num == UI_BUS) {
            if (!json_has(msg, ["type"])) return;
            string msg_type = llJsonGetValue(msg, ["type"]);

            if (msg_type == "start") {
                if (!json_has(msg, ["context"])) return;
                if (llJsonGetValue(msg, ["context"]) != PLUGIN_CONTEXT) return;

                if (id == NULL_KEY) return;

                CurrentUser = id;
                request_acl(id);
                return;
            }

            return;
        }

        // ===== DIALOG RESPONSES =====
        if (num == DIALOG_BUS) {
            if (!json_has(msg, ["type"])) return;
            string msg_type = llJsonGetValue(msg, ["type"]);

            if (msg_type == "dialog_response") {
                if (!json_has(msg, ["session_id"])) return;
                string session = llJsonGetValue(msg, ["session_id"]);

                if (session == SessionId) {
                    if (json_has(msg, ["button"])) {
                        string button = llJsonGetValue(msg, ["button"]);
                        handle_button_click(button);
                    } else {
                        // Timeout
                        cleanup_session();
                    }
                }
                return;
            }

            return;
        }

        // ===== ACL RESULTS =====
        if (num == AUTH_BUS) {
            if (!json_has(msg, ["type"])) return;
            string msg_type = llJsonGetValue(msg, ["type"]);

            if (msg_type == "acl_result") {
                if (json_has(msg, ["avatar"]) && json_has(msg, ["level"])) {
                    key avatar = (key)llJsonGetValue(msg, ["avatar"]);
                    integer level = (integer)llJsonGetValue(msg, ["level"]);
                    handle_acl_result(avatar, level);
                }
                return;
            }

            return;
        }
    }
}
