# Chat Commands - User Guide

## What Are Chat Commands?

Chat Commands is an accessibility feature that allows you to control your collar using chat messages instead of menus. This is helpful for:

- Users with screen readers or other assistive technology
- Quick control without opening menus
- Remote control from nearby alts
- Role-play scenarios where menus break immersion
- Mobile users who find chat easier than menus

---

## Quick Start

### Using Chat Commands

Simply type commands in local chat using this format:

```
<prefix> <command> [arguments]
```

**Example:** If your prefix is `ab`, you would type:

```
ab pose sit
ab bell ring
ab help
```

---

## Finding Your Prefix

Your command prefix is automatically generated when the system first starts:

1. Touch your collar
2. Select **"Chat Cmds"** from the menu
3. Your prefix is shown at the top (e.g., "Prefix: ab")

**Default:** First two letters of your first name (lowercase)
- "Anne Skydancer" → `ab`
- "John Smith" → `jo`
- "Belle Rose" → `be`

---

## Changing Your Prefix

To change your command prefix:

1. Touch collar → **Chat Cmds**
2. Click **"Chg Pfx"**
3. Enter your desired prefix in the text box

**Requirements:**
- 2-7 characters
- Lowercase letters only (a-z)
- No numbers, spaces, or special characters

**Examples of valid prefixes:**
- `cmd`
- `belle`
- `collar`
- `mycmd`

**Examples of invalid prefixes:**
- `Cmd` (uppercase not allowed)
- `c` (too short)
- `!` (special characters not allowed)
- `cmd2` (numbers not allowed)

---

## Channels

### Channel 0 (Public Chat)

Type commands in regular local chat (the default chat you use normally).

- **Visibility:** Everyone nearby sees your commands
- **Use:** Public demonstrations, RP scenarios
- **Enable/Disable:** Touch collar → Chat Cmds → Ch0: ON/OFF

**Example:**
```
You: ab pose sit
(Everyone nearby sees this)
```

### Channel 1 (Private Chat)

Type commands on channel 1 for privacy.

- **Visibility:** Only your collar sees the commands
- **Use:** Discreet control, private sessions
- **Enable/Disable:** Touch collar → Chat Cmds → Ch1: ON/OFF

**How to use channel 1:**
```
/1 ab pose sit
```

(The `/1` prefix sends the message on channel 1)

---

## Available Commands

Type `<prefix> help` to see all available commands. For example:

```
ab help
```

The collar will respond with a list of all registered commands.

**Common commands may include:**
- `help` - Shows available commands
- `pose <name>` - Start an animation
- `stop` - Stop current animation
- `bell ring` - Ring the bell
- `lock on/off` - Toggle lock

(Available commands depend on installed plugins)

---

## Configuration Menu

Touch your collar and select **"Chat Cmds"** to access settings.

### Main Menu

Shows:
- Current prefix
- Status (Active/Inactive)
- Channel 0 and 1 states

**Buttons:**
- **Chg Pfx** - Change command prefix
- **Ch0: ON/OFF** - Toggle channel 0 listener
- **Ch1: ON/OFF** - Toggle channel 1 listener
- **Advanced** - Advanced settings (Trustee/Owner only)

---

### Advanced Menu (Trustee/Owner Only)

Additional settings for trusted users:

- **Enable/Disable** - Turn entire listener on/off
- **Reset** - Reset chat command system to defaults

**Warning:** Disabling the listener stops ALL chat commands on both channels.

---

## Access Control

### Who Can Use Commands?

- **Your commands:** You can always use chat commands on your own collar
- **Others' commands:** Depends on their access level:
  - Owners: Full access
  - Trustees: Most commands
  - Public users: Limited commands (if public mode enabled)
  - Blacklisted: No access

### Who Can Change Settings?

- **Change prefix:** Owned wearer (ACL 2+), Trustees, Owners
- **Toggle channels:** Owned wearer (ACL 2+), Trustees, Owners
- **Advanced settings:** Trustees and Owners only (ACL 3+)

---

## Rate Limiting

To prevent spam, the system limits how fast you can send the same command:

- **Cooldown:** 2 seconds per command
- **Scope:** Only exact duplicates are blocked

**Example:**
```
ab pose sit     ✅ Executes
(1 second later)
ab pose stand   ✅ Executes (different command)
ab pose sit     ❌ Ignored (duplicate within 2 seconds)
(wait 2 seconds from first command)
ab pose sit     ✅ Executes
```

---

## Privacy & Responses

### No Echo

The collar does NOT echo your commands back to you. This prevents chat spam.

**You won't see:**
```
Collar: Executing pose sit...
Collar: Pose changed to sit
```

**You will see:**
```
Collar: Pose: sit
```
(Minimal confirmation only)

### Private Messages

All responses from the collar are sent **privately to you only** using `llRegionSayTo()`. Others cannot see the collar's responses.

---

## Troubleshooting

### "Unknown command"

- Check spelling (commands are case-sensitive)
- Type `<prefix> help` to see available commands
- Ensure the plugin is installed and loaded

### No response at all

1. **Check listener status:** Touch collar → Chat Cmds
   - Is status "Active"?
   - Is the channel enabled?

2. **Check prefix:** Are you using the correct prefix?

3. **Check rate limiting:** Did you send the same command twice quickly?

4. **Check channel:** On channel 1, remember to use `/1` prefix

### "Access denied"

- You don't have sufficient permissions for that command
- Contact collar owner or trustee

### Commands work on Ch0 but not Ch1

- Check if Ch1 is enabled: Touch collar → Chat Cmds → Ch1 should be ON
- Ensure you're using `/1` prefix: `/1 ab command`

### Prefix changed accidentally

- Use the menu: Touch collar → Chat Cmds → Chg Pfx
- Or ask owner/trustee to change it

---

## Examples

### Basic Usage

```
# Using default prefix "ab"
ab help
ab pose sit
ab pose stand
ab bell ring
ab lock on
```

### Private Commands (Channel 1)

```
/1 ab pose kneel
/1 ab bell mute
/1 ab lock off
```

### Custom Prefix

```
# After changing prefix to "cmd"
cmd pose sit
cmd help
cmd bell ring
```

---

## Tips & Best Practices

### For Collar Wearers

1. **Choose a memorable prefix** - Something short and unique
2. **Use Channel 1 for private control** - Avoid broadcasting commands
3. **Check help regularly** - New commands may be added as plugins update
4. **Test in private first** - Make sure commands work before public use

### For Owners/Controllers

1. **Respect rate limits** - Don't spam commands
2. **Use appropriate ACL** - Don't abuse access levels
3. **Combine with menus** - Use both interfaces as appropriate
4. **Communicate prefix** - Ensure authorized users know the prefix

---

## Accessibility Features

The chat command system is specifically designed for accessibility:

### Screen Reader Friendly
- Text-based interface
- No visual-only feedback
- Compatible with text-to-speech

### Keyboard-Only Control
- No mouse required
- Fast for keyboard users
- Customizable prefix for easy typing

### Mobile Friendly
- Easier than menus on mobile viewers
- Quick access to common functions
- Works with mobile keyboards

---

## Frequently Asked Questions

### Can I use both menus and chat commands?

Yes! They work simultaneously. Use whichever is more convenient.

### Do chat commands work from my HUD?

No, chat commands are for local chat only. Use the official control HUD for remote menu access.

### Can I see other people's commands?

You see their commands on **channel 0** (public chat), but you **don't see** the collar's responses (those are private).

### What happens if someone else has the same prefix?

Prefixes are per-collar. Each collar has its own prefix and only responds to its own commands.

### Can I turn off chat commands entirely?

Yes:
- Option 1: Disable both Ch0 and Ch1
- Option 2: Advanced menu → Disable listener (ACL 3+ required)

### Does the prefix appear in the help command?

Yes, `<prefix> help` shows your current prefix at the top.

---

## Support

If you encounter issues:

1. Check this guide first
2. Try resetting: Touch collar → Chat Cmds → Advanced → Reset
3. Consult the main collar documentation
4. Contact the collar developer

---

## Version

Chat Commands v1.0 (2025-11-02)

---

## Related Documentation

- **CHAT_COMMANDS_API.md** - For plugin developers
- **README.md** - Main collar documentation
- **agents.md** - System architecture
