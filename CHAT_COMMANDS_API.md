# Chat Commands API - Developer Guide

## Overview

The Chat Commands system provides an accessibility layer allowing users to control collar functions via chat instead of menus. This guide explains how to integrate chat commands into your plugins.

## System Architecture

### Components

1. **Kernel Module** (`ds_collar_kmod_chat_commands.lsl`)
   - Listens on channels 0 (public) and 1 (private)
   - Maintains command registry
   - Routes commands to plugins
   - Handles ACL checks and rate limiting

2. **Configuration Plugin** (`ds_collar_plugin_chat_commands.lsl`)
   - UI for prefix configuration
   - Channel toggles
   - Advanced settings

3. **Your Plugin** (implements commands)
   - Registers commands on startup
   - Receives and executes commands
   - Returns responses via llRegionSayTo()

---

## Command Format

Users type commands in chat with this format:

```
<prefix> <command> [arguments]
```

**Examples:**
```
ab pose sit
! bell ring
cmd lock on
```

**Prefix Rules:**
- Lowercase letters only (a-z)
- 2-7 characters
- Auto-generated on first boot (first 2 letters of wearer's name)
- Can be changed by ACL 2+ users

---

## Integration Steps

### Step 1: Add UI_BUS Constant

Add to your plugin's ABI section (if not already present):

```lsl
integer UI_BUS = 900;
```

**Note:** UI_BUS is already part of the standard ABI, so most plugins will already have this constant defined.

### Step 2: Define Your Commands

Create a list of command names your plugin will handle:

```lsl
list REGISTERED_COMMANDS = ["pose", "stop", "list"];
```

**Command naming guidelines:**
- Use lowercase
- Short and memorable
- No spaces or special characters
- Avoid collisions with other plugins

### Step 3: Register Commands on Startup

Register after your plugin receives settings:

```lsl
default {
    state_entry() {
        // Register with kernel
        register_self();

        // Request settings
        string msg = llList2Json(JSON_OBJECT, [
            "type", "settings_get"
        ]);
        llMessageLinked(LINK_SET, SETTINGS_BUS, msg, NULL_KEY);

        // Register commands (use timer to ensure commands module is ready)
        llSetTimerEvent(1.0);
    }

    timer() {
        llSetTimerEvent(0.0);  // One-shot
        register_commands();
    }
}
```

**Registration function:**

```lsl
register_commands() {
    string msg = llList2Json(JSON_OBJECT, [
        "type", "cmd_register",
        "context", PLUGIN_CONTEXT,
        "commands", llList2Json(JSON_ARRAY, REGISTERED_COMMANDS)
    ]);
    llMessageLinked(LINK_SET, UI_BUS, msg, NULL_KEY);

    logd("Registered commands: " + llDumpList2String(REGISTERED_COMMANDS, ", "));
}
```

### Step 4: Handle Command Execution

Add to your `link_message` event:

```lsl
link_message(integer sender, integer num, string msg, key id) {
    // ... existing handlers ...

    // ===== COMMAND EXECUTION (via UI_BUS) =====
    if (num == UI_BUS) {
        if (!json_has(msg, ["type"])) return;
        string msg_type = llJsonGetValue(msg, ["type"]);

        if (msg_type == "cmd_execute") {
            handle_command_execute(msg);
            return;
        }

        if (msg_type == "cmd_error") {
            // Optional: Handle registration errors
            if (json_has(msg, ["error"])) {
                string error = llJsonGetValue(msg, ["error"]);
                llOwnerSay("[" + PLUGIN_CONTEXT + "] Error: " + error);
            }
            return;
        }

        return;
    }
}
```

### Step 5: Implement Command Handler

```lsl
handle_command_execute(string msg) {
    // Extract required fields
    if (!json_has(msg, ["command"])) return;
    if (!json_has(msg, ["speaker"])) return;
    if (!json_has(msg, ["speaker_acl"])) return;

    string command = llJsonGetValue(msg, ["command"]);
    key speaker = (key)llJsonGetValue(msg, ["speaker"]);
    integer speaker_acl = (integer)llJsonGetValue(msg, ["speaker_acl"]);

    // Extract optional fields
    string args = "";
    if (json_has(msg, ["args"])) {
        args = llJsonGetValue(msg, ["args"]);
    }

    integer channel = 0;
    if (json_has(msg, ["channel"])) {
        channel = (integer)llJsonGetValue(msg, ["channel"]);
    }

    // Route to specific command
    if (command == "pose") {
        cmd_pose(speaker, args, speaker_acl);
    }
    else if (command == "stop") {
        cmd_stop(speaker, speaker_acl);
    }
    else if (command == "list") {
        cmd_list(speaker, speaker_acl);
    }
}
```

### Step 6: Implement Individual Command Functions

```lsl
cmd_pose(key speaker, string pose_name, integer acl) {
    // Check ACL
    if (acl < 2) {  // Require owned wearer or higher
        llRegionSayTo(speaker, 0, "Access denied. Owned wearer required.");
        return;
    }

    // Validate arguments
    if (pose_name == "") {
        llRegionSayTo(speaker, 0, "Usage: pose <name>");
        return;
    }

    // Execute command
    start_animation(pose_name);

    // Send private response (NO ECHO - see guidelines below)
    llRegionSayTo(speaker, 0, "Pose: " + pose_name);
}

cmd_stop(key speaker, integer acl) {
    // Check ACL
    if (acl < 2) {
        llRegionSayTo(speaker, 0, "Access denied.");
        return;
    }

    // Execute
    stop_all_animations();

    // Response
    llRegionSayTo(speaker, 0, "All poses stopped.");
}

cmd_list(key speaker, integer acl) {
    // Public command (ACL 1+)
    if (acl < 1) {
        llRegionSayTo(speaker, 0, "Access denied.");
        return;
    }

    // Send list
    llRegionSayTo(speaker, 0, "Available poses: sit, stand, kneel");
}
```

### Step 7: Cleanup on Shutdown (Optional but Recommended)

```lsl
unregister_commands() {
    string msg = llList2Json(JSON_OBJECT, [
        "type", "cmd_unregister",
        "context", PLUGIN_CONTEXT
    ]);
    llMessageLinked(LINK_SET, UI_BUS, msg, NULL_KEY);
}

// In soft_reset handler:
if (msg_type == "soft_reset" || msg_type == "soft_reset_all") {
    unregister_commands();
    llResetScript();
}
```

---

## Message Specifications

### Command Registration (Plugin → Commands Module)

```json
{
  "type": "cmd_register",
  "context": "your_plugin_context",
  "commands": ["cmd1", "cmd2", "cmd3"]
}
```

**Fields:**
- `type`: Must be `"cmd_register"`
- `context`: Your plugin's unique context (e.g., "animate", "bell")
- `commands`: JSON array of command names (lowercase, no spaces)

**Response:** None (unless error occurs)

---

### Command Execution (Commands Module → Your Plugin)

```json
{
  "type": "cmd_execute",
  "command": "pose",
  "args": "sit",
  "speaker": "avatar-uuid",
  "speaker_acl": 3,
  "channel": 0
}
```

**Fields:**
- `type`: Always `"cmd_execute"`
- `command`: The command name (lowercase)
- `args`: Arguments as string (may be empty)
- `speaker`: UUID of the user who issued the command
- `speaker_acl`: ACL level of speaker (-1 to 5)
- `channel`: Channel command was issued on (0 or 1)

**Correlation Key:** The `id` parameter in link_message contains the speaker UUID

---

### Command Unregistration (Plugin → Commands Module)

```json
{
  "type": "cmd_unregister",
  "context": "your_plugin_context"
}
```

---

### Error Notification (Commands Module → Your Plugin)

```json
{
  "type": "cmd_error",
  "error": "Command collision: 'pose' already registered by animate"
}
```

**When errors occur:**
- Command collision (another plugin already registered that command)
- Invalid registration format

---

## ACL Levels Reference

When checking `speaker_acl`, use these levels:

| Level | Name | Description |
|-------|------|-------------|
| -1 | BLACKLIST | Explicitly denied access |
| 0 | NOACCESS | No permissions |
| 1 | PUBLIC | Public mode enabled |
| 2 | OWNED | Wearer when owner is set |
| 3 | TRUSTEE | Trusted user |
| 4 | UNOWNED | Wearer when no owner |
| 5 | PRIMARY_OWNER | Owner (full access) |

**Example ACL checks:**

```lsl
// Allow public and above
if (acl < 1) {
    llRegionSayTo(speaker, 0, "Access denied.");
    return;
}

// Allow owned wearer and above
if (acl < 2) {
    llRegionSayTo(speaker, 0, "Access denied. Owned wearer required.");
    return;
}

// Allow trustees and owners only
if (acl < 3) {
    llRegionSayTo(speaker, 0, "Access denied. Trustee or owner required.");
    return;
}
```

---

## Best Practices

### 1. No Command Echo

**❌ DON'T:**
```lsl
llRegionSayTo(speaker, 0, "Executing: pose sit");
llRegionSayTo(speaker, 0, "Pose changed to: sit");
```

**✅ DO:**
```lsl
// Silent execution, or minimal feedback only if needed
llRegionSayTo(speaker, 0, "Pose: sit");
```

**Rationale:** Users already typed the command - they know what they asked for.

---

### 2. Private Responses

**Always use `llRegionSayTo()` for responses:**

```lsl
llRegionSayTo(speaker, 0, "Message here");
```

**Never use:**
- `llSay()` - visible to everyone
- `llOwnerSay()` - only to collar wearer
- `llShout()` - too public

---

### 3. Argument Validation

Always validate arguments before execution:

```lsl
cmd_volume(key speaker, string level_str, integer acl) {
    if (level_str == "") {
        llRegionSayTo(speaker, 0, "Usage: volume <0-10>");
        return;
    }

    integer level = (integer)level_str;
    if (level < 0 || level > 10) {
        llRegionSayTo(speaker, 0, "Volume must be 0-10.");
        return;
    }

    // Proceed...
}
```

---

### 4. ACL Consistency

Ensure chat command ACL requirements match your menu ACL requirements:

```lsl
// If your plugin has PLUGIN_MIN_ACL = 2
// Your commands should also require ACL 2+ (unless intentionally more permissive)

if (acl < PLUGIN_MIN_ACL) {
    llRegionSayTo(speaker, 0, "Access denied.");
    return;
}
```

---

### 5. Command Naming

**Good command names:**
- `pose` (single word, clear)
- `stop` (action verb)
- `list` (function)
- `on` / `off` (toggle states)

**Avoid:**
- `pose_start` (use `pose` instead)
- `stopAnimation` (camelCase, too long)
- `p` (too cryptic)
- `bell-ring` (special characters)

---

### 6. Help Integration

Consider adding a `help` or `?` command:

```lsl
cmd_help(key speaker, integer acl) {
    if (acl < 1) return;

    string help = "Pose Commands:\n";
    help += "  pose <name> - Start pose\n";
    help += "  stop - Stop all poses\n";
    help += "  list - List available poses";

    llRegionSayTo(speaker, 0, help);
}
```

---

## Rate Limiting

The commands module implements per-speaker per-command rate limiting:

- **Cooldown:** 2 seconds
- **Scope:** Exact command + args
- **Behavior:** Silently ignores duplicates within cooldown

**Example:**
```
T=0s:   "ab pose sit"    ✅ Executes
T=1s:   "ab pose stand"  ✅ Executes (different command)
T=1.5s: "ab pose sit"    ❌ Blocked (duplicate within 2s)
T=2.5s: "ab pose sit"    ✅ Executes (cooldown expired)
```

**Your plugin doesn't need to implement rate limiting** - it's handled automatically.

---

## Troubleshooting

### Commands Not Registering

1. **Check timing:** Use timer to delay registration:
   ```lsl
   llSetTimerEvent(1.0);  // Register after 1 second
   ```

2. **Check JSON format:**
   ```lsl
   llList2Json(JSON_ARRAY, REGISTERED_COMMANDS)
   ```

3. **Check for collisions:** Look for error messages

### Commands Not Executing

1. **Verify registration:** Check debug logs
2. **Check ACL:** Ensure speaker has sufficient permissions
3. **Check command name:** Must match exactly (case-sensitive)
4. **Check listener state:** User may have disabled listeners

### No Response to User

1. **Use llRegionSayTo():** Not llSay() or llOwnerSay()
2. **Check speaker key:** Ensure using correct UUID
3. **Check channel:** Always use channel 0 for responses

---

## Complete Example

See `ds_collar_plugin_example_commands.lsl` for a full working example with:
- Multiple commands
- Argument handling
- ACL validation
- Proper registration/unregistration
- Error handling

---

## Built-in Help Command

The commands module provides a built-in `help` command that lists all registered commands:

```
User: ab help
Collar: Available commands (prefix: ab):
  help - Show this help
  hello (example_commands)
  echo (example_commands)
  whoami (example_commands)
  time (example_commands)
  pose (animate)
  stop (animate)
```

---

## Channel Behavior

### Channel 0 (Public Chat)
- **Visibility:** All nearby avatars see the command
- **Privacy:** Low - commands are public
- **Use case:** Public demonstrations, role-play scenarios

### Channel 1 (Private Chat)
- **Visibility:** Only collar sees the command
- **Privacy:** High - commands are private
- **Use case:** Discreet control, private sessions

**Both channels have identical ACL requirements and functionality.**

---

## Security Considerations

1. **ACL Enforcement:** Always validate `speaker_acl` in your command handlers
2. **Input Validation:** Sanitize arguments before use
3. **Sensitive Operations:** Require higher ACL for destructive commands
4. **Information Disclosure:** Don't reveal sensitive info via error messages

---

## Migration Guide (Adding Commands to Existing Plugins)

If you have an existing plugin and want to add chat commands:

1. Ensure `integer UI_BUS = 900;` is defined (usually already present)
2. Define `list REGISTERED_COMMANDS = [...];`
3. Add `register_commands()` function
4. Call registration in timer (1 second delay)
5. Add command message handlers to UI_BUS section of link_message
6. Implement command handlers that call your existing functions

**Example:**

```lsl
// Existing function
start_pose(string pose_name) {
    // Your pose logic here
}

// New command handler
cmd_pose(key speaker, string pose_name, integer acl) {
    if (acl < 2) {
        llRegionSayTo(speaker, 0, "Access denied.");
        return;
    }

    // Call existing function
    start_pose(pose_name);

    llRegionSayTo(speaker, 0, "Pose: " + pose_name);
}
```

---

## Support & Questions

- Check `ds_collar_plugin_example_commands.lsl` for reference implementation
- Review this documentation for API specifications
- Test with the example plugin first before modifying production code

---

## Version History

- v1.0 (2025-11-02): Initial release
  - Command registration API
  - Execution message format
  - ACL integration
  - Rate limiting
  - Auto-generated prefix support
