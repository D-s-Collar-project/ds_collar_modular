/* =============================================================
   MODULE: ds_collar_kernel.lsl
   ROLE  : Base kernel for DS Collar modular system.
           - Maintains plugin registry and serializes register/deregister flows.
           - Supervises heartbeat/liveness using ping/pong and inventory presence.
           - Broadcasts plugin list snapshots and re-solicits registrations on resets.
           - Guards inbound payloads and fails closed on malformed inputs.
   ============================================================= */

integer DEBUG = FALSE;

/* ---------- Message Types ---------- */
string MSG_REGISTER        = "register";
string MSG_REGISTER_NOW    = "register_now";
string MSG_DEREGISTER      = "deregister";
string MSG_PLUGIN_LIST     = "plugin_list";
string MSG_PLUGIN_START    = "plugin_start";
string MSG_PLUGIN_RETURN   = "plugin_return";
string MSG_KERNEL_SOFT_RST = "kernel_soft_reset";
string MSG_SOFT_RESET      = "plugin_soft_reset";
string MSG_PING            = "plugin_ping";
string MSG_PONG            = "plugin_pong";
string MSG_SETTINGS_GET    = "settings_get";
string MSG_SETTINGS_SYNC   = "settings_sync";
string MSG_AUTH_QUERY      = "acl_query";
string MSG_AUTH_RESULT     = "acl_result";

/* ---------- Link Numbers ---------- */
integer K_PLUGIN_REG_QUERY     = 500;
integer K_PLUGIN_REG_REPLY     = 501;
integer K_PLUGIN_DEREG         = 502;
integer K_SOFT_RESET           = 503;
integer K_PLUGIN_SOFT_RESET    = 504;
integer K_PLUGIN_LIST          = 600;
integer K_PLUGIN_LIST_REQUEST  = 601;
integer K_PLUGIN_START         = 900;
integer K_PLUGIN_RETURN        = 901;
integer K_PLUGIN_PING          = 650;
integer K_PLUGIN_PONG          = 651;

/* ---------- Settings & Auth ---------- */
integer SETTINGS_QUERY_NUM     = 800;
integer SETTINGS_SYNC_NUM      = 870;
integer AUTH_QUERY_NUM         = 700;
integer AUTH_RESULT_NUM        = 710;

/* ---------- Heartbeat Timing ---------- */
float   TIMER_TICK_SEC   = 0.25;
float   PING_INTERVAL    = 5.0;
integer PING_TIMEOUT_SEC = 15;
float   INV_SWEEP_SEC    = 3.0;

/* ---------- Registry bookkeeping ---------- */
/* stride = 7: [context, isn, sn, label, min_acl, script, last_seen_unix] */
list    PluginMap   = [];
list    AddQueue    = [];
list    DeregQueue  = [];
integer NextIsn     = 1;
integer Registering = FALSE;
integer Dereging    = FALSE;

integer LastPingUnix    = 0;
integer LastSweepUnix   = 0;
key     CachedOwner     = NULL_KEY;

/* ---------- Helpers ---------- */
integer logd(string msg){ if (DEBUG) llOwnerSay("[KERNEL] " + msg); return FALSE; }
integer now(){ return llGetUnixTime(); }
integer stride(){ return 7; }

integer json_has(string j, list path){ if (llJsonGetValue(j, path) == JSON_INVALID) return FALSE; return TRUE; }

integer map_index_from_context(string ctx){
    integer s = stride();
    integer i = 0;
    integer n = llGetListLength(PluginMap);
    while (i < n){
        if (llList2String(PluginMap, i) == ctx) return i;
        i += s;
    }
    return -1;
}

integer map_touch(string ctx, integer when){
    integer idx = map_index_from_context(ctx);
    if (idx == -1) return FALSE;
    PluginMap = llListReplaceList(PluginMap, [
        llList2String (PluginMap, idx),
        llList2Integer(PluginMap, idx + 1),
        llList2Integer(PluginMap, idx + 2),
        llList2String (PluginMap, idx + 3),
        llList2Integer(PluginMap, idx + 4),
        llList2String (PluginMap, idx + 5),
        when
    ], idx, idx + 6);
    return TRUE;
}

integer queue_register(string ctx, integer sn, string label, integer min_acl, string script){
    if (ctx == "") return FALSE;
    integer existing = llListFindList(AddQueue, [ctx]);
    if (existing != -1){
        AddQueue = llListReplaceList(AddQueue, [ctx, sn, label, min_acl, script], existing, existing + 4);
        Registering = TRUE;
        return TRUE;
    }
    integer pending_drop = llListFindList(DeregQueue, [ctx]);
    if (pending_drop != -1){
        DeregQueue = llDeleteSubList(DeregQueue, pending_drop, pending_drop);
        if (llGetListLength(DeregQueue) == 0) Dereging = FALSE;
    }
    AddQueue += [ctx, sn, label, min_acl, script];
    Registering = TRUE;
    return TRUE;
}

integer queue_deregister(string ctx){
    if (ctx == "") return FALSE;
    if (map_index_from_context(ctx) == -1) return FALSE;
    if (llListFindList(DeregQueue, [ctx]) != -1) return FALSE;
    DeregQueue += [ctx];
    Dereging = TRUE;
    return TRUE;
}

integer process_next_add(){
    if (llGetListLength(AddQueue) == 0){
        if (Registering){
            Registering = FALSE;
            broadcast_plugin_list();
        }
        return FALSE;
    }
    string  ctx     = llList2String (AddQueue, 0);
    integer sn      = llList2Integer(AddQueue, 1);
    string  label   = llList2String (AddQueue, 2);
    integer min_acl = llList2Integer(AddQueue, 3);
    string  script  = llList2String (AddQueue, 4);
    AddQueue = llDeleteSubList(AddQueue, 0, 4);

    if (ctx == "") return TRUE;
    integer idx = map_index_from_context(ctx);
    integer ts  = now();
    if (script == "") script = ctx;

    if (idx == -1){
        integer isn = NextIsn;
        NextIsn += 1;
        PluginMap += [ctx, isn, sn, label, min_acl, script, ts];
        logd("Registered " + ctx + " isn=" + (string)isn);
    } else {
        integer old_isn = llList2Integer(PluginMap, idx + 1);
        PluginMap = llListReplaceList(PluginMap, [ctx, old_isn, sn, label, min_acl, script, ts], idx, idx + 6);
        logd("Refreshed " + ctx);
    }
    return TRUE;
}

integer process_next_dereg(){
    if (llGetListLength(DeregQueue) == 0){
        if (Dereging){
            Dereging = FALSE;
            broadcast_plugin_list();
        }
        return FALSE;
    }
    string ctx = llList2String(DeregQueue, 0);
    DeregQueue = llDeleteSubList(DeregQueue, 0, 0);
    integer idx = map_index_from_context(ctx);
    if (idx == -1) return TRUE;

    string j = llList2Json(JSON_OBJECT, []);
    j = llJsonSetValue(j, ["type"], MSG_DEREGISTER);
    j = llJsonSetValue(j, ["context"], ctx);
    llMessageLinked(LINK_SET, K_PLUGIN_DEREG, j, NULL_KEY);
    PluginMap = llDeleteSubList(PluginMap, idx, idx + 6);
    logd("Deregistered " + ctx);
    return TRUE;
}

integer broadcast_plugin_list(){
    integer s = stride();
    integer i = 0;
    integer n = llGetListLength(PluginMap);
    list arr = [];
    while (i < n){
        string ctx     = llList2String (PluginMap, i);
        integer isn    = llList2Integer(PluginMap, i + 1);
        integer sn     = llList2Integer(PluginMap, i + 2);
        string label   = llList2String (PluginMap, i + 3);
        integer min_acl= llList2Integer(PluginMap, i + 4);
        string payload = llList2Json(JSON_OBJECT, []);
        payload = llJsonSetValue(payload, ["context"], ctx);
        payload = llJsonSetValue(payload, ["isn"], (string)isn);
        payload = llJsonSetValue(payload, ["sn"], (string)sn);
        payload = llJsonSetValue(payload, ["label"], label);
        payload = llJsonSetValue(payload, ["min_acl"], (string)min_acl);
        arr += [payload];
        i += s;
    }
    string j = llList2Json(JSON_OBJECT, []);
    j = llJsonSetValue(j, ["type"], MSG_PLUGIN_LIST);
    j = llJsonSetValue(j, ["plugins"], llList2Json(JSON_ARRAY, arr));
    llMessageLinked(LINK_SET, K_PLUGIN_LIST, j, NULL_KEY);
    return llGetListLength(arr);
}

integer solicit_plugin_register(){
    integer count = llGetInventoryNumber(INVENTORY_SCRIPT);
    integer i = 0;
    while (i < count){
        string script_name = llGetInventoryName(INVENTORY_SCRIPT, i);
        if (script_name != llGetScriptName()){
            if (llSubStringIndex(script_name, "ds_collar_plugin_") == 0){
                string j = llList2Json(JSON_OBJECT, []);
                j = llJsonSetValue(j, ["type"], MSG_REGISTER_NOW);
                j = llJsonSetValue(j, ["script"], script_name);
                llMessageLinked(LINK_SET, K_PLUGIN_REG_QUERY, j, NULL_KEY);
            }
        }
        i += 1;
    }
    return TRUE;
}

integer send_ping_all(){
    integer s = stride();
    integer i = 0;
    integer n = llGetListLength(PluginMap);
    integer ts = now();
    while (i < n){
        string ctx = llList2String(PluginMap, i);
        string j = llList2Json(JSON_OBJECT, []);
        j = llJsonSetValue(j, ["type"], MSG_PING);
        j = llJsonSetValue(j, ["context"], ctx);
        j = llJsonSetValue(j, ["ts"], (string)ts);
        llMessageLinked(LINK_SET, K_PLUGIN_PING, j, NULL_KEY);
        i += s;
    }
    return TRUE;
}

integer prune_dead_plugins(){
    integer s = stride();
    integer i = 0;
    integer n = llGetListLength(PluginMap);
    integer ts = now();
    integer removed = FALSE;
    while (i < n){
        string ctx    = llList2String (PluginMap, i);
        integer seen  = llList2Integer(PluginMap, i + 6);
        string script = llList2String (PluginMap, i + 5);
        if (script == "") script = ctx;
        integer in_inv = (llGetInventoryType(script) == INVENTORY_SCRIPT);
        integer fresh  = ((ts - seen) <= PING_TIMEOUT_SEC);
        if (!in_inv && !fresh){
            PluginMap = llDeleteSubList(PluginMap, i, i + 6);
            n -= s;
            removed = TRUE;
            logd("Pruned " + ctx);
        } else {
            i += s;
        }
    }
    if (removed) broadcast_plugin_list();
    return removed;
}

integer handle_soft_reset(string payload){
    PluginMap = [];
    AddQueue = [];
    DeregQueue = [];
    NextIsn = 1;
    Registering = FALSE;
    Dereging = FALSE;
    LastPingUnix = now();
    LastSweepUnix = LastPingUnix;
    broadcast_plugin_list();
    solicit_plugin_register();
    return TRUE;
}

integer owner_changed(){
    key cur = llGetOwner();
    if (cur == NULL_KEY) return FALSE;
    if (cur != CachedOwner){
        CachedOwner = cur;
        return TRUE;
    }
    return FALSE;
}

/* ---------- Events ---------- */
default
{
    state_entry(){
        CachedOwner = llGetOwner();
        PluginMap = [];
        AddQueue = [];
        DeregQueue = [];
        NextIsn = 1;
        Registering = FALSE;
        Dereging = FALSE;
        LastPingUnix = now();
        LastSweepUnix = LastPingUnix;
        llSetTimerEvent(TIMER_TICK_SEC);
        solicit_plugin_register();
    }

    on_rez(integer start_param){
        if (owner_changed()) llResetScript();
    }

    attach(key id){
        if (id == NULL_KEY) return;
        if (owner_changed()) llResetScript();
    }

    changed(integer change){
        if (change & CHANGED_OWNER){
            if (owner_changed()) llResetScript();
        }
        if (change & CHANGED_INVENTORY){
            prune_dead_plugins();
            solicit_plugin_register();
        }
    }

    link_message(integer sender, integer num, string str, key id){
        if (num == K_PLUGIN_LIST_REQUEST){
            broadcast_plugin_list();
            return;
        }
        if (num == K_SOFT_RESET){
            integer accept = FALSE;
            if (str == MSG_KERNEL_SOFT_RST) accept = TRUE;
            else if (json_has(str, ["type"])){
                if (llJsonGetValue(str, ["type"]) == MSG_KERNEL_SOFT_RST) accept = TRUE;
            }
            if (accept){
                handle_soft_reset(str);
            }
            return;
        }
        if (num == K_PLUGIN_SOFT_RESET){
            if (!json_has(str, ["type"])) return;
            if (llJsonGetValue(str, ["type"]) != MSG_SOFT_RESET) return;
            string ctx = "";
            if (json_has(str, ["context"])) ctx = llJsonGetValue(str, ["context"]);
            if (ctx != ""){
                map_touch(ctx, now());
                if (map_index_from_context(ctx) == -1){
                    string script = ctx;
                    if (json_has(str, ["script"])) script = llJsonGetValue(str, ["script"]);
                    string j = llList2Json(JSON_OBJECT, []);
                    j = llJsonSetValue(j, ["type"], MSG_REGISTER_NOW);
                    j = llJsonSetValue(j, ["script"], script);
                    llMessageLinked(LINK_SET, K_PLUGIN_REG_QUERY, j, NULL_KEY);
                }
            }
            return;
        }
        if (num == K_PLUGIN_REG_REPLY){
            if (!json_has(str, ["type"])) return;
            if (llJsonGetValue(str, ["type"]) != MSG_REGISTER) return;
            if (!json_has(str, ["context"])) return;
            string ctx = llJsonGetValue(str, ["context"]);
            integer sn = 0;
            string label = "";
            integer min_acl = 0;
            if (json_has(str, ["sn"])) sn = (integer)llJsonGetValue(str, ["sn"]);
            if (json_has(str, ["label"])) label = llJsonGetValue(str, ["label"]);
            if (json_has(str, ["min_acl"])) min_acl = (integer)llJsonGetValue(str, ["min_acl"]);
            string script = "";
            if (json_has(str, ["script"])) script = llJsonGetValue(str, ["script"]);
            queue_register(ctx, sn, label, min_acl, script);
            return;
        }
        if (num == K_PLUGIN_DEREG){
            if (!json_has(str, ["type"])) return;
            if (llJsonGetValue(str, ["type"]) != MSG_DEREGISTER) return;
            if (!json_has(str, ["context"])) return;
            queue_deregister(llJsonGetValue(str, ["context"]));
            return;
        }
        if (num == K_PLUGIN_PONG){
            if (!json_has(str, ["type"])) return;
            if (llJsonGetValue(str, ["type"]) != MSG_PONG) return;
            if (!json_has(str, ["context"])) return;
            map_touch(llJsonGetValue(str, ["context"]), now());
            return;
        }
    }

    timer(){
        if (Registering){
            process_next_add();
            return;
        }
        if (Dereging){
            process_next_dereg();
            return;
        }
        integer ts = now();
        if ((ts - LastPingUnix) >= (integer)PING_INTERVAL){
            send_ping_all();
            LastPingUnix = ts;
        }
        if ((ts - LastSweepUnix) >= (integer)INV_SWEEP_SEC){
            prune_dead_plugins();
            LastSweepUnix = ts;
        }
    }
}
