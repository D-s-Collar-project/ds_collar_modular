/* =============================================================
   MODULE: ds_collar_kmod_bootstrap.lsl
   ROLE  : Bootstrapper and liveness supervisor for DS Collar.
           - Drives initial kernel/module synchronization on rez/attach.
           - Waits for plugin list, settings, and auth readiness with single timer.
           - Retries via kernel soft reset when acknowledgements stall.
   ============================================================= */

integer DEBUG = FALSE;

/* ---------- Link numbers ---------- */
integer K_SOFT_RESET          = 503;
integer K_PLUGIN_LIST         = 600;
integer K_PLUGIN_LIST_REQUEST = 601;
integer K_PLUGIN_PING         = 650;
integer K_PLUGIN_PONG         = 651;
integer K_PLUGIN_START        = 900;
integer K_PLUGIN_RETURN       = 901;
integer SETTINGS_QUERY_NUM    = 800;
integer SETTINGS_SYNC_NUM     = 870;
integer AUTH_QUERY_NUM        = 700;
integer AUTH_RESULT_NUM       = 710;

/* ---------- Message types ---------- */
string MSG_KERNEL_SOFT_RST = "kernel_soft_reset";
string MSG_PLUGIN_LIST     = "plugin_list";
string MSG_SETTINGS_SYNC   = "settings_sync";
string MSG_AUTH_QUERY      = "acl_query";
string MSG_AUTH_RESULT     = "acl_result";
string MSG_PLUGIN_START    = "plugin_start";

/* ---------- Timing ---------- */
float   TIMER_TICK_SEC      = 0.5;
integer BOOT_RETRY_SEC      = 10;
integer HEARTBEAT_TIMEOUT   = 60;

/* ---------- State ---------- */
integer BootActive      = FALSE;
integer WaitPluginList  = FALSE;
integer WaitSettings    = FALSE;
integer WaitAuth        = FALSE;
integer BootDeadline    = 0;
integer BootAttempts    = 0;
integer MaxBootAttempts = 3;
integer LastKernelPing  = 0;
key     LastOwner       = NULL_KEY;

/* ---------- Helpers ---------- */
integer logd(string msg){ if (DEBUG) llOwnerSay("[BOOT] " + msg); return FALSE; }
integer now(){ return llGetUnixTime(); }

integer json_has(string j, list path){ if (llJsonGetValue(j, path) == JSON_INVALID) return FALSE; return TRUE; }

integer send_kernel_soft_reset(){
    string payload = llList2Json(JSON_OBJECT, []);
    payload = llJsonSetValue(payload, ["type"], MSG_KERNEL_SOFT_RST);
    llMessageLinked(LINK_SET, K_SOFT_RESET, payload, NULL_KEY);
    logd("kernel soft reset requested");
    return TRUE;
}

integer request_plugin_list(){
    llMessageLinked(LINK_SET, K_PLUGIN_LIST_REQUEST, "", NULL_KEY);
    logd("plugin list requested");
    return TRUE;
}

integer request_settings_sync(){
    string payload = llList2Json(JSON_OBJECT, []);
    payload = llJsonSetValue(payload, ["type"], "settings_get");
    llMessageLinked(LINK_SET, SETTINGS_QUERY_NUM, payload, NULL_KEY);
    logd("settings snapshot requested");
    return TRUE;
}

integer request_wearer_acl(){
    key wearer = llGetOwner();
    if (wearer == NULL_KEY) return FALSE;
    string payload = llList2Json(JSON_OBJECT, []);
    payload = llJsonSetValue(payload, ["type"], MSG_AUTH_QUERY);
    payload = llJsonSetValue(payload, ["avatar"], (string)wearer);
    llMessageLinked(LINK_SET, AUTH_QUERY_NUM, payload, wearer);
    logd("wearer ACL requested");
    return TRUE;
}

integer finish_bootstrap(){
    BootActive = FALSE;
    WaitPluginList = FALSE;
    WaitSettings = FALSE;
    WaitAuth = FALSE;
    BootDeadline = 0;
    BootAttempts = 0;
    llSetTimerEvent(0.0);
    string payload = llList2Json(JSON_OBJECT, []);
    payload = llJsonSetValue(payload, ["type"], MSG_PLUGIN_START);
    llMessageLinked(LINK_SET, K_PLUGIN_START, payload, NULL_KEY);
    logd("bootstrap complete");
    return TRUE;
}

integer bootstrap_check(){
    if (!BootActive) return FALSE;
    if (!WaitPluginList && !WaitSettings && !WaitAuth){
        finish_bootstrap();
        return TRUE;
    }
    return FALSE;
}

integer start_bootstrap(){
    BootActive = TRUE;
    BootAttempts = 0;
    WaitPluginList = TRUE;
    WaitSettings = TRUE;
    WaitAuth = (llGetOwner() != NULL_KEY);
    BootDeadline = now() + BOOT_RETRY_SEC;
    llSetTimerEvent(TIMER_TICK_SEC);
    send_kernel_soft_reset();
    request_plugin_list();
    request_settings_sync();
    if (WaitAuth) request_wearer_acl();
    return TRUE;
}

integer rebootstrap(){
    if (!BootActive){
        BootActive = TRUE;
        BootAttempts = 0;
    }
    BootAttempts += 1;
    if (BootAttempts > MaxBootAttempts){
        BootActive = FALSE;
        llSetTimerEvent(0.0);
        logd("bootstrap aborted (max attempts)");
        return FALSE;
    }
    WaitPluginList = TRUE;
    WaitSettings = TRUE;
    WaitAuth = (llGetOwner() != NULL_KEY);
    BootDeadline = now() + BOOT_RETRY_SEC;
    send_kernel_soft_reset();
    request_plugin_list();
    request_settings_sync();
    if (WaitAuth) request_wearer_acl();
    return TRUE;
}

integer handle_plugin_list(string payload){
    if (!json_has(payload, ["type"])) return FALSE;
    if (llJsonGetValue(payload, ["type"]) != MSG_PLUGIN_LIST) return FALSE;
    WaitPluginList = FALSE;
    bootstrap_check();
    return TRUE;
}

integer handle_settings_sync(string payload){
    if (!json_has(payload, ["type"])) return FALSE;
    if (llJsonGetValue(payload, ["type"]) != MSG_SETTINGS_SYNC) return FALSE;
    WaitSettings = FALSE;
    bootstrap_check();
    return TRUE;
}

integer handle_auth_result(string payload, key id){
    if (!WaitAuth) return FALSE;
    if (!json_has(payload, ["type"])) return FALSE;
    if (llJsonGetValue(payload, ["type"]) != MSG_AUTH_RESULT) return FALSE;
    key wearer = llGetOwner();
    if (id != wearer) return FALSE;
    WaitAuth = FALSE;
    bootstrap_check();
    return TRUE;
}

integer owner_changed(){
    key cur = llGetOwner();
    if (cur == NULL_KEY) return FALSE;
    if (cur != LastOwner){
        LastOwner = cur;
        return TRUE;
    }
    return FALSE;
}

/* ---------- Events ---------- */
default
{
    state_entry(){
        LastOwner = llGetOwner();
        BootActive = FALSE;
        WaitPluginList = FALSE;
        WaitSettings = FALSE;
        WaitAuth = FALSE;
        LastKernelPing = now();
        start_bootstrap();
    }

    on_rez(integer param){
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
        if (change & (CHANGED_REGION | CHANGED_TELEPORT)){
            rebootstrap();
        }
    }

    link_message(integer sender, integer num, string str, key id){
        if (num == K_PLUGIN_LIST){
            handle_plugin_list(str);
            return;
        }
        if (num == SETTINGS_SYNC_NUM){
            handle_settings_sync(str);
            return;
        }
        if (num == AUTH_RESULT_NUM){
            handle_auth_result(str, id);
            return;
        }
        if (num == K_PLUGIN_PING){
            LastKernelPing = now();
            return;
        }
        if (num == K_PLUGIN_PONG){
            LastKernelPing = now();
            return;
        }
    }

    timer(){
        if (BootActive){
            integer ts = now();
            if (ts >= BootDeadline){
                rebootstrap();
                return;
            }
        }
        if ((now() - LastKernelPing) > HEARTBEAT_TIMEOUT){
            logd("heartbeat stale → reboot");
            rebootstrap();
        }
    }
}
