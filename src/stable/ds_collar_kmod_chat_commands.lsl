/* =============================================================================
   MODULE: ds_collar_kmod_chat_commands.lsl (v1.0)

   ROLE: Chat command listener and routing system

   PURPOSE: Provides an accessibility layer allowing users to control collar
            functions via chat commands instead of menus. Listens on channels
            0 (public) and 1 (private) for commands in format:
            <prefix> <command> <args>

   CHANNELS:
   - 500 (KERNEL_LIFECYCLE): Registration and lifecycle
   - 700 (AUTH_BUS): ACL queries for command speakers
   - 800 (SETTINGS_BUS): Settings sync/delta consumption
   - 900 (UI_BUS): Command registration and routing

   COMMAND FORMAT:
   - <prefix> <command> [args]
   - Example: "ab pose sit" or "! bell ring"

   PREFIX RULES:
   - Lowercase letters only (a-z)
   - 2-7 characters
   - Auto-generated on first boot from wearer's first name (first 2 letters)

   INITIALIZATION:
   - Automatic mode: Prefix auto-generated, listeners immediately active
   - Prefix can be changed by ACL 2+ via plugin UI
   - Channel 0/1 can be toggled independently

   ACCESSIBILITY FEATURES:
   - ALL users can use chat commands (including wearer)
   - No command echo (silent execution)
   - Private error messages via llRegionSayTo()
   - Rate limiting prevents spam without blocking legitimate sequences

   RATE LIMITING:
   - Per-speaker per-full-command (command + args)
   - 2-second cooldown for exact duplicate commands
   - Allows rapid sequences of different commands
   ============================================================================= */

integer DEBUG = FALSE;
integer PRODUCTION = TRUE;  // Set FALSE for development builds

/* ═══════════════════════════════════════════════════════════
   CONSOLIDATED ABI
   ═══════════════════════════════════════════════════════════ */
integer KERNEL_LIFECYCLE = 500;
integer AUTH_BUS = 700;
integer SETTINGS_BUS = 800;
integer UI_BUS = 900;  // Used for command registration and routing

/* ═══════════════════════════════════════════════════════════
   SETTINGS KEYS
   ═══════════════════════════════════════════════════════════ */
string KEY_CMD_PREFIX = "cmd_prefix";
string KEY_CMD_ENABLED = "cmd_enabled";
string KEY_CMD_INITIALIZED = "cmd_initialized";
string KEY_CMD_AUTO_MODE = "cmd_auto_mode";
string KEY_CMD_CH0_ENABLED = "cmd_ch0_enabled";
string KEY_CMD_CH1_ENABLED = "cmd_ch1_enabled";
string KEY_CMD_REGISTRY = "cmd_registry";  // JSON: {"plugin": ["cmd1", "cmd2"]}

/* ═══════════════════════════════════════════════════════════
   STATE
   ═══════════════════════════════════════════════════════════ */
string CommandPrefix = "";
integer ListenerEnabled = FALSE;
integer Initialized = FALSE;
integer AutoMode = FALSE;
integer Ch0Enabled = FALSE;
integer Ch1Enabled = FALSE;

integer Ch0ListenHandle = 0;
integer Ch1ListenHandle = 0;

// Command registry: JSON object {"plugin_context": ["cmd1", "cmd2"], ...}
string CommandRegistry = "{}";

// Pending ACL checks: [speaker, plugin, command, full_msg, channel, speaker, ...]
list PendingCommands = [];
integer PENDING_STRIDE = 5;

// Rate limiting: [speaker, full_command, timestamp, speaker, full_command, timestamp, ...]
list RateLimitTimestamps = [];
integer RATE_LIMIT_STRIDE = 3;
float COMMAND_COOLDOWN = 2.0;  // 2 seconds

integer SettingsReady = FALSE;
key LastOwner = NULL_KEY;

/* ═══════════════════════════════════════════════════════════
   HELPERS
   ═══════════════════════════════════════════════════════════ */
integer logd(string msg) {
    if (DEBUG && !PRODUCTION) llOwnerSay("[CMD] " + msg);
    return FALSE;
}

integer json_has(string j, list path) {
    return (llJsonGetValue(j, path) != JSON_INVALID);
}

integer now() {
    return llGetUnixTime();
}

/* ══════════════════════════════════════════════════════════════════════════════
   PREFIX VALIDATION
   ══════════════════════════════════════════════════════════════════════════════ */

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

string generate_auto_prefix() {
    // Get wearer's username (firstname.lastname)
    string username = llToLower(llGetUsername());

    // Extract first 2 letters of first name
    string prefix = llGetSubString(username, 0, 1);

    logd("Auto-generated prefix: " + prefix + " from username: " + username);
    return prefix;
}

/* ══════════════════════════════════════════════════════════════════════════════
   LISTENER MANAGEMENT
   ══════════════════════════════════════════════════════════════════════════════ */

start_listeners() {
    if (Ch0Enabled && Ch0ListenHandle == 0) {
        Ch0ListenHandle = llListen(0, "", NULL_KEY, "");
        logd("Started channel 0 listener");
    }
    if (Ch1Enabled && Ch1ListenHandle == 0) {
        Ch1ListenHandle = llListen(1, "", NULL_KEY, "");
        logd("Started channel 1 listener");
    }
}

stop_listeners() {
    if (Ch0ListenHandle != 0) {
        llListenRemove(Ch0ListenHandle);
        Ch0ListenHandle = 0;
        logd("Stopped channel 0 listener");
    }
    if (Ch1ListenHandle != 0) {
        llListenRemove(Ch1ListenHandle);
        Ch1ListenHandle = 0;
        logd("Stopped channel 1 listener");
    }
}

update_listeners() {
    stop_listeners();
    if (ListenerEnabled && Initialized) {
        start_listeners();
    }
}

/* ══════════════════════════════════════════════════════════════════════════════
   RATE LIMITING
   ══════════════════════════════════════════════════════════════════════════════ */

integer check_rate_limit(key speaker, string full_command) {
    integer now_time = now();

    // Find this speaker's last use of this exact command
    integer idx = 0;
    integer len = llGetListLength(RateLimitTimestamps);
    while (idx < len) {
        if (llList2Key(RateLimitTimestamps, idx) == speaker &&
            llList2String(RateLimitTimestamps, idx + 1) == full_command) {

            integer last_use = llList2Integer(RateLimitTimestamps, idx + 2);
            if ((now_time - last_use) < COMMAND_COOLDOWN) {
                logd("Rate limited: " + llKey2Name(speaker) + " - " + full_command);
                return FALSE;
            }

            // Update timestamp
            RateLimitTimestamps = llListReplaceList(RateLimitTimestamps, [now_time], idx + 2, idx + 2);
            return TRUE;
        }
        idx += RATE_LIMIT_STRIDE;
    }

    // First use of this command by this speaker
    RateLimitTimestamps += [speaker, full_command, now_time];

    // Prune if list gets large (keep last 60 entries = 180 elements)
    if (llGetListLength(RateLimitTimestamps) > 180) {
        RateLimitTimestamps = llList2List(RateLimitTimestamps, -180, -1);
    }

    return TRUE;
}

/* ══════════════════════════════════════════════════════════════════════════════
   COMMAND REGISTRY
   ══════════════════════════════════════════════════════════════════════════════ */

// Plugin tracking list: [plugin1, plugin2, ...]
list RegisteredPlugins = [];

string find_plugin_for_command(string cmd) {
    // Iterate through all registered plugins and check their command arrays
    integer i;
    integer len = llGetListLength(RegisteredPlugins);

    for (i = 0; i < len; i++) {
        string plugin = llList2String(RegisteredPlugins, i);

        // Get this plugin's command array from registry
        string cmd_array = llJsonGetValue(CommandRegistry, [plugin]);
        if (cmd_array == JSON_INVALID) jump continue_loop;

        // Check if cmd is in this array
        integer j;
        for (j = 0; j < 100; j++) {  // Max 100 commands per plugin
            string registered_cmd = llJsonGetValue(cmd_array, [j]);
            if (registered_cmd == JSON_INVALID) jump continue_loop;
            if (registered_cmd == cmd) return plugin;
        }

        @continue_loop;
    }

    return "";
}

register_plugin_commands(string plugin_context, list commands) {
    // Check for collisions
    integer i;
    for (i = 0; i < llGetListLength(commands); i++) {
        string cmd = llList2String(commands, i);
        string existing = find_plugin_for_command(cmd);
        if (existing != "" && existing != plugin_context) {
            // Collision detected
            logd("COLLISION: " + plugin_context + " tried to register '" + cmd + "' already owned by " + existing);
            send_error_to_plugin(plugin_context, "Command collision: '" + cmd + "' already registered by " + existing);
            return;
        }
    }

    // Add/update plugin's commands in registry
    string cmd_array = llList2Json(JSON_ARRAY, commands);
    CommandRegistry = llJsonSetValue(CommandRegistry, [plugin_context], cmd_array);

    // Track this plugin if not already tracked
    if (llListFindList(RegisteredPlugins, [plugin_context]) == -1) {
        RegisteredPlugins += [plugin_context];
    }

    // Persist to settings
    persist_registry();

    logd("Registered commands for " + plugin_context + ": " + llDumpList2String(commands, ", "));
}

unregister_plugin_commands(string plugin_context) {
    // Remove plugin from registry
    CommandRegistry = llJsonSetValue(CommandRegistry, [plugin_context], JSON_DELETE);

    // Remove from tracking list
    integer idx = llListFindList(RegisteredPlugins, [plugin_context]);
    if (idx != -1) {
        RegisteredPlugins = llDeleteSubList(RegisteredPlugins, idx, idx);
    }

    persist_registry();
    logd("Unregistered commands for " + plugin_context);
}

persist_registry() {
    string msg = llList2Json(JSON_OBJECT, [
        "type", "settings_set",
        "key", KEY_CMD_REGISTRY,
        "value", CommandRegistry
    ]);
    llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);
}

send_error_to_plugin(string plugin_context, string error_msg) {
    string msg = llList2Json(JSON_OBJECT, [
        "type", "cmd_error",
        "error", error_msg
    ]);
    llMessageLinked(LINK_SET, UI_BUS, msg, NULL_KEY);
}

/* ══════════════════════════════════════════════════════════════════════════════
   COMMAND PARSING
   ══════════════════════════════════════════════════════════════════════════════ */

parse_chat_command(key speaker, string message, integer channel) {
    // Check if message starts with CommandPrefix
    integer prefix_len = llStringLength(CommandPrefix);
    if (llGetSubString(message, 0, prefix_len - 1) != CommandPrefix) {
        return;  // Not a command
    }

    // Extract command and args
    string rest = llStringTrim(llGetSubString(message, prefix_len, -1), STRING_TRIM);
    if (rest == "") return;  // Just prefix, no command

    list parts = llParseString2List(rest, [" "], []);
    if (llGetListLength(parts) == 0) return;

    string command = llToLower(llList2String(parts, 0));
    string args = llDumpList2String(llDeleteSubList(parts, 0, 0), " ");

    // Build full command for rate limiting
    string full_command = command;
    if (args != "") full_command += " " + args;

    // Rate limit check
    if (!check_rate_limit(speaker, full_command)) {
        // Silently ignore (rate limited)
        return;
    }

    // Built-in help command
    if (command == "help") {
        send_help(speaker);
        return;
    }

    // Find which plugin handles this command
    string plugin = find_plugin_for_command(command);
    if (plugin == "") {
        llRegionSayTo(speaker, 0, "Unknown command: " + command);
        logd("Unknown command from " + llKey2Name(speaker) + ": " + command);
        return;
    }

    // Queue for ACL check
    PendingCommands += [speaker, plugin, command, args, channel];
    request_acl(speaker);
}

send_help(key speaker) {
    // Build help message from registry
    string help = "Available commands (prefix: " + CommandPrefix + "):\n";
    help += "  help - Show this help\n";

    // List all registered commands by plugin
    integer i;
    integer len = llGetListLength(RegisteredPlugins);
    for (i = 0; i < len; i++) {
        string plugin = llList2String(RegisteredPlugins, i);
        string cmd_array = llJsonGetValue(CommandRegistry, [plugin]);
        if (cmd_array == JSON_INVALID) jump continue_help;

        // List commands for this plugin
        integer j;
        for (j = 0; j < 100; j++) {
            string cmd = llJsonGetValue(cmd_array, [j]);
            if (cmd == JSON_INVALID) jump continue_help;
            help += "  " + cmd + " (" + plugin + ")\n";
        }

        @continue_help;
    }

    llRegionSayTo(speaker, 0, help);
}

/* ══════════════════════════════════════════════════════════════════════════════
   ACL HANDLING
   ══════════════════════════════════════════════════════════════════════════════ */

request_acl(key speaker) {
    string msg = llList2Json(JSON_OBJECT, [
        "type", "acl_query",
        "avatar", (string)speaker
    ]);
    llMessageLinked(LINK_SET, AUTH_BUS, msg, speaker);
    logd("Requested ACL for " + llKey2Name(speaker));
}

handle_acl_result(key speaker, integer level) {
    // Find pending command for this speaker
    integer idx = llListFindList(PendingCommands, [speaker]);
    if (idx == -1 || (idx % PENDING_STRIDE) != 0) {
        logd("No pending command found for " + llKey2Name(speaker));
        return;
    }

    string plugin = llList2String(PendingCommands, idx + 1);
    string command = llList2String(PendingCommands, idx + 2);
    string args = llList2String(PendingCommands, idx + 3);
    integer channel = llList2Integer(PendingCommands, idx + 4);

    // Remove from pending
    PendingCommands = llDeleteSubList(PendingCommands, idx, idx + PENDING_STRIDE - 1);

    // Route command to plugin
    route_command(plugin, command, args, speaker, level, channel);
}

route_command(string plugin, string cmd, string args, key speaker, integer acl, integer channel) {
    string msg = llList2Json(JSON_OBJECT, [
        "type", "cmd_execute",
        "command", cmd,
        "args", args,
        "speaker", (string)speaker,
        "speaker_acl", acl,
        "channel", channel
    ]);
    llMessageLinked(LINK_SET, UI_BUS, msg, speaker);
    logd("Routed command '" + cmd + "' to " + plugin + " (ACL " + (string)acl + ")");
}

/* ══════════════════════════════════════════════════════════════════════════════
   INITIALIZATION
   ══════════════════════════════════════════════════════════════════════════════ */

initialize_auto_mode() {
    CommandPrefix = generate_auto_prefix();
    AutoMode = TRUE;
    Initialized = TRUE;
    ListenerEnabled = TRUE;
    Ch0Enabled = TRUE;
    Ch1Enabled = TRUE;

    // Persist to settings
    persist_state();

    // Start listeners
    update_listeners();

    logd("Initialized in AUTO mode with prefix: " + CommandPrefix);
}

persist_state() {
    // Send multiple settings updates
    string msg;

    msg = llList2Json(JSON_OBJECT, [
        "type", "settings_set",
        "key", KEY_CMD_PREFIX,
        "value", CommandPrefix
    ]);
    llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);

    msg = llList2Json(JSON_OBJECT, [
        "type", "settings_set",
        "key", KEY_CMD_ENABLED,
        "value", (string)ListenerEnabled
    ]);
    llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);

    msg = llList2Json(JSON_OBJECT, [
        "type", "settings_set",
        "key", KEY_CMD_INITIALIZED,
        "value", (string)Initialized
    ]);
    llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);

    msg = llList2Json(JSON_OBJECT, [
        "type", "settings_set",
        "key", KEY_CMD_AUTO_MODE,
        "value", (string)AutoMode
    ]);
    llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);

    msg = llList2Json(JSON_OBJECT, [
        "type", "settings_set",
        "key", KEY_CMD_CH0_ENABLED,
        "value", (string)Ch0Enabled
    ]);
    llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);

    msg = llList2Json(JSON_OBJECT, [
        "type", "settings_set",
        "key", KEY_CMD_CH1_ENABLED,
        "value", (string)Ch1Enabled
    ]);
    llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);
}

/* ══════════════════════════════════════════════════════════════════════════════
   SETTINGS SYNC
   ══════════════════════════════════════════════════════════════════════════════ */

apply_settings_sync(string kv) {
    if (json_has(kv, [KEY_CMD_PREFIX])) {
        CommandPrefix = llJsonGetValue(kv, [KEY_CMD_PREFIX]);
    }
    if (json_has(kv, [KEY_CMD_ENABLED])) {
        ListenerEnabled = (integer)llJsonGetValue(kv, [KEY_CMD_ENABLED]);
    }
    if (json_has(kv, [KEY_CMD_INITIALIZED])) {
        Initialized = (integer)llJsonGetValue(kv, [KEY_CMD_INITIALIZED]);
    }
    if (json_has(kv, [KEY_CMD_AUTO_MODE])) {
        AutoMode = (integer)llJsonGetValue(kv, [KEY_CMD_AUTO_MODE]);
    }
    if (json_has(kv, [KEY_CMD_CH0_ENABLED])) {
        Ch0Enabled = (integer)llJsonGetValue(kv, [KEY_CMD_CH0_ENABLED]);
    }
    if (json_has(kv, [KEY_CMD_CH1_ENABLED])) {
        Ch1Enabled = (integer)llJsonGetValue(kv, [KEY_CMD_CH1_ENABLED]);
    }
    if (json_has(kv, [KEY_CMD_REGISTRY])) {
        CommandRegistry = llJsonGetValue(kv, [KEY_CMD_REGISTRY]);
    }

    SettingsReady = TRUE;

    // If not initialized, do auto-init
    if (!Initialized) {
        initialize_auto_mode();
    } else {
        update_listeners();
    }

    logd("Settings synced. Initialized=" + (string)Initialized + " Prefix=" + CommandPrefix);
}

apply_settings_delta(string payload) {
    if (!json_has(payload, ["op"])) return;

    string op = llJsonGetValue(payload, ["op"]);

    if (op == "set") {
        if (!json_has(payload, ["key"]) || !json_has(payload, ["value"])) return;

        string key = llJsonGetValue(payload, ["key"]);
        string value = llJsonGetValue(payload, ["value"]);

        if (key == KEY_CMD_PREFIX) {
            CommandPrefix = value;
            logd("Prefix changed to: " + CommandPrefix);
        }
        else if (key == KEY_CMD_ENABLED) {
            ListenerEnabled = (integer)value;
            update_listeners();
            logd("Listener enabled: " + value);
        }
        else if (key == KEY_CMD_INITIALIZED) {
            Initialized = (integer)value;
        }
        else if (key == KEY_CMD_AUTO_MODE) {
            AutoMode = (integer)value;
        }
        else if (key == KEY_CMD_CH0_ENABLED) {
            Ch0Enabled = (integer)value;
            update_listeners();
            logd("Ch0 enabled: " + value);
        }
        else if (key == KEY_CMD_CH1_ENABLED) {
            Ch1Enabled = (integer)value;
            update_listeners();
            logd("Ch1 enabled: " + value);
        }
        else if (key == KEY_CMD_REGISTRY) {
            CommandRegistry = value;
            logd("Registry updated");
        }
    }
}

/* ══════════════════════════════════════════════════════════════════════════════
   KERNEL LIFECYCLE
   ══════════════════════════════════════════════════════════════════════════════ */

handle_kernel_lifecycle(string payload) {
    if (!json_has(payload, ["type"])) return;

    string msg_type = llJsonGetValue(payload, ["type"]);

    if (msg_type == "ping") {
        send_pong();
    }
    else if (msg_type == "soft_reset") {
        // Reset state but keep settings
        logd("Soft reset requested");
        stop_listeners();
        PendingCommands = [];
        RateLimitTimestamps = [];
        if (SettingsReady) {
            update_listeners();
        }
    }
}

send_pong() {
    string msg = llList2Json(JSON_OBJECT, [
        "type", "pong",
        "script", llGetScriptName()
    ]);
    llMessageLinked(LINK_SET, KERNEL_LIFECYCLE, msg, NULL_KEY);
}

/* ══════════════════════════════════════════════════════════════════════════════
   COMMAND MESSAGES (via UI_BUS)
   ══════════════════════════════════════════════════════════════════════════════ */

handle_command_messages(string payload, key id) {
    if (!json_has(payload, ["type"])) return;

    string msg_type = llJsonGetValue(payload, ["type"]);

    if (msg_type == "cmd_register") {
        // Plugin registering commands
        if (!json_has(payload, ["context"]) || !json_has(payload, ["commands"])) {
            logd("Invalid cmd_register message");
            return;
        }

        string plugin_context = llJsonGetValue(payload, ["context"]);
        string commands_json = llJsonGetValue(payload, ["commands"]);

        // Parse JSON array of commands
        list commands = [];
        integer i;
        for (i = 0; i < 100; i++) {  // Max 100 commands per plugin
            string cmd = llJsonGetValue(commands_json, [i]);
            if (cmd == JSON_INVALID) jump done_parsing;
            commands += [cmd];
        }
        @done_parsing;

        register_plugin_commands(plugin_context, commands);
    }
    else if (msg_type == "cmd_unregister") {
        if (!json_has(payload, ["context"])) return;

        string plugin_context = llJsonGetValue(payload, ["context"]);
        unregister_plugin_commands(plugin_context);
    }
    else if (msg_type == "cmd_set_prefix") {
        // Request to change prefix (from UI plugin)
        if (!json_has(payload, ["prefix"])) return;

        string new_prefix = llJsonGetValue(payload, ["prefix"]);

        if (!is_valid_prefix(new_prefix)) {
            logd("Invalid prefix rejected: " + new_prefix);
            return;
        }

        CommandPrefix = new_prefix;
        persist_state();
        logd("Prefix changed to: " + new_prefix);
    }
}

/* ══════════════════════════════════════════════════════════════════════════════
   EVENT HANDLERS
   ══════════════════════════════════════════════════════════════════════════════ */

default {
    state_entry() {
        logd("Starting chat commands module v1.0");

        // Request settings
        string msg = llList2Json(JSON_OBJECT, [
            "type", "settings_get"
        ]);
        llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);

        LastOwner = llGetOwner();
    }

    listen(integer channel, string name, key id, string message) {
        // Only process if listener enabled and initialized
        if (!ListenerEnabled || !Initialized) return;

        // Check channel enablement
        if (channel == 0 && !Ch0Enabled) return;
        if (channel == 1 && !Ch1Enabled) return;

        // Parse and process command
        parse_chat_command(id, message, channel);
    }

    link_message(integer sender_num, integer num, string msg, key id) {
        if (num == KERNEL_LIFECYCLE) {
            handle_kernel_lifecycle(msg);
        }
        else if (num == SETTINGS_BUS) {
            if (!json_has(msg, ["type"])) return;

            string msg_type = llJsonGetValue(msg, ["type"]);

            if (msg_type == "settings_sync") {
                if (json_has(msg, ["kv"])) {
                    apply_settings_sync(llJsonGetValue(msg, ["kv"]));
                }
            }
            else if (msg_type == "settings_delta") {
                apply_settings_delta(msg);
            }
        }
        else if (num == AUTH_BUS) {
            if (!json_has(msg, ["type"])) return;

            string msg_type = llJsonGetValue(msg, ["type"]);

            if (msg_type == "acl_result") {
                if (json_has(msg, ["avatar"]) && json_has(msg, ["level"])) {
                    key avatar = (key)llJsonGetValue(msg, ["avatar"]);
                    integer level = (integer)llJsonGetValue(msg, ["level"]);
                    handle_acl_result(avatar, level);
                }
            }
        }
        else if (num == UI_BUS) {
            handle_command_messages(msg, id);
        }
    }

    on_rez(integer param) {
        llResetScript();
    }

    changed(integer change) {
        if (change & CHANGED_OWNER) {
            if (llGetOwner() != LastOwner) {
                llResetScript();
            }
        }
        else if (change & CHANGED_INVENTORY) {
            // Notecard might have changed, but we don't use it directly
        }
    }
}
