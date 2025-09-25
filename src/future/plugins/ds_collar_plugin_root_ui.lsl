/* =============================================================
   PLUGIN: ds_collar_plugin_root_ui.lsl
   ROLE  : Root UI plugin for DS Collar future kernel.
           - Registers with kernel and tracks plugin registry snapshots.
           - Presents paginated root menu dialogs with ACL enforcement.
           - Routes plugin selections, denies unauthorized access, and
             reopens the menu on plugin return.
   ============================================================= */

integer DEBUG = FALSE;

/* ---------- Protocol strings ---------- */
string MSG_REGISTER        = "register";
string MSG_REGISTER_NOW    = "register_now";
string MSG_PLUGIN_LIST     = "plugin_list";
string MSG_PLUGIN_START    = "plugin_start";
string MSG_PLUGIN_RETURN   = "plugin_return";
string MSG_PLUGIN_SOFT_RST = "plugin_soft_reset";
string MSG_PLUGIN_PING     = "plugin_ping";
string MSG_PLUGIN_PONG     = "plugin_pong";
string MSG_AUTH_QUERY      = "acl_query";
string MSG_AUTH_RESULT     = "acl_result";

/* ---------- Link numbers ---------- */
integer K_PLUGIN_REG_QUERY     = 500;
integer K_PLUGIN_REG_REPLY     = 501;
integer K_PLUGIN_DEREG         = 502;
integer K_PLUGIN_SOFT_RESET    = 504;
integer K_PLUGIN_LIST          = 600;
integer K_PLUGIN_LIST_REQUEST  = 601;
integer K_PLUGIN_PING          = 650;
integer K_PLUGIN_PONG          = 651;
integer K_PLUGIN_START         = 900;
integer K_PLUGIN_RETURN        = 901;
integer AUTH_QUERY_NUM         = 700;
integer AUTH_RESULT_NUM        = 710;

/* ---------- Plugin identity ---------- */
string PLUGIN_CONTEXT = "core_root";
string PLUGIN_LABEL   = "Root Menu";
integer PLUGIN_SN     = 100;
integer PLUGIN_MIN_ACL= 1;

/* ---------- UI configuration ---------- */
integer PAGE_SIZE       = 8;
float   SESSION_TIMEOUT = 60.0;
float   TOUCH_RANGE_M   = 5.0;
string  BTN_PREV        = "<<";
string  BTN_NEXT        = ">>";
string  BTN_CLOSE       = "Close";
string  MODAL_OK        = "OK";
string  TITLE           = "• DS Collar •";

/* ---------- Session states ---------- */
integer SESSION_NONE = 0;
integer SESSION_WAIT = 1;
integer SESSION_MENU = 2;
integer SESSION_MODAL = 3;

/* ---------- Globals ---------- */
list    Registry       = []; /* stride 3: [context,label,min_acl] */
key     SessionUser    = NULL_KEY;
integer SessionAcl     = -1;
integer SessionMode    = 0;
integer SessionPage    = 0;
integer SessionListen  = 0;
integer SessionChan    = 0;
list    SessionMap     = [];
key     LastOwner      = NULL_KEY;

/* ---------- Helpers ---------- */
integer logd(string msg){ if (DEBUG) llOwnerSay("[UI] " + msg); return TRUE; }

integer json_has(string j, list path){ if (llJsonGetValue(j, path) == JSON_INVALID) return FALSE; return TRUE; }

integer random_channel(){ return -200000 - (integer)llFrand(8000000.0); }

integer within_range(key av){
    if (av == NULL_KEY) return FALSE;
    list data = llGetObjectDetails(av, [OBJECT_POS]);
    if (llGetListLength(data) < 1) return FALSE;
    vector pos = llList2Vector(data, 0);
    if (pos == ZERO_VECTOR) return FALSE;
    float dist = llVecDist(llGetPos(), pos);
    if (dist > TOUCH_RANGE_M) return FALSE;
    return TRUE;
}

integer registry_index(string ctx){
    integer stride = 3;
    integer i = 0;
    integer n = llGetListLength(Registry);
    while (i < n){
        if (llList2String(Registry, i) == ctx) return i;
        i += stride;
    }
    return -1;
}

integer register_self(){
    string payload = llList2Json(JSON_OBJECT, []);
    payload = llJsonSetValue(payload, ["type"], MSG_REGISTER);
    payload = llJsonSetValue(payload, ["context"], PLUGIN_CONTEXT);
    payload = llJsonSetValue(payload, ["label"], PLUGIN_LABEL);
    payload = llJsonSetValue(payload, ["min_acl"], (string)PLUGIN_MIN_ACL);
    payload = llJsonSetValue(payload, ["sn"], (string)PLUGIN_SN);
    payload = llJsonSetValue(payload, ["script"], llGetScriptName());
    llMessageLinked(LINK_SET, K_PLUGIN_REG_REPLY, payload, NULL_KEY);
    logd("register sent");
    return TRUE;
}

integer send_plugin_pong(){
    string payload = llList2Json(JSON_OBJECT, []);
    payload = llJsonSetValue(payload, ["type"], MSG_PLUGIN_PONG);
    payload = llJsonSetValue(payload, ["context"], PLUGIN_CONTEXT);
    llMessageLinked(LINK_SET, K_PLUGIN_PONG, payload, NULL_KEY);
    return TRUE;
}

integer request_registry(){
    llMessageLinked(LINK_SET, K_PLUGIN_LIST_REQUEST, "", NULL_KEY);
    return TRUE;
}

integer request_acl(key av){
    if (av == NULL_KEY) return FALSE;
    string payload = llList2Json(JSON_OBJECT, []);
    payload = llJsonSetValue(payload, ["type"], MSG_AUTH_QUERY);
    payload = llJsonSetValue(payload, ["avatar"], (string)av);
    llMessageLinked(LINK_SET, AUTH_QUERY_NUM, payload, NULL_KEY);
    logd("acl requested for " + (string)av);
    return TRUE;
}

integer close_listener(){
    if (SessionListen != 0){
        llListenRemove(SessionListen);
        SessionListen = 0;
    }
    SessionChan = 0;
    return TRUE;
}

integer open_listener(key av){
    close_listener();
    SessionChan = random_channel();
    SessionListen = llListen(SessionChan, "", av, "");
    return TRUE;
}

integer close_session(){
    close_listener();
    SessionUser = NULL_KEY;
    SessionAcl = -1;
    SessionMode = SESSION_NONE;
    SessionPage = 0;
    SessionMap = [];
    llSetTimerEvent(0.0);
    return TRUE;
}

string map_command(string label){
    integer idx = llListFindList(SessionMap, [label]);
    if (idx == -1) return "";
    return llList2String(SessionMap, idx + 1);
}

integer show_modal(string body, string command){
    if (SessionUser == NULL_KEY) return FALSE;
    SessionMap = [MODAL_OK, command];
    SessionMode = SESSION_MODAL;
    llDialog(SessionUser, body, [MODAL_OK], SessionChan);
    llSetTimerEvent(SESSION_TIMEOUT);
    return TRUE;
}

integer show_menu(){
    if (SessionUser == NULL_KEY) return FALSE;
    integer total = llGetListLength(Registry) / 3;
    if (total <= 0){
        show_modal("No installed plugins.", "modal_close");
        return TRUE;
    }
    integer pages = (total + PAGE_SIZE - 1) / PAGE_SIZE;
    if (pages <= 0) pages = 1;
    if (SessionPage < 0) SessionPage = 0;
    if (SessionPage >= pages) SessionPage = pages - 1;

    integer start = SessionPage * PAGE_SIZE;
    integer end = start + PAGE_SIZE;
    if (end > total) end = total;

    list buttons = [];
    list map = [];
    integer i = start;
    while (i < end){
        integer base = i * 3;
        string ctx = llList2String(Registry, base);
        string label = llList2String(Registry, base + 1);
        buttons += [label];
        map += [label, "plugin:" + ctx];
        i += 1;
    }

    if (pages > 1){
        if (SessionPage > 0){
            buttons += [BTN_PREV];
            map += [BTN_PREV, "nav:prev"];
        }
        if (SessionPage < (pages - 1)){
            buttons += [BTN_NEXT];
            map += [BTN_NEXT, "nav:next"];
        }
    }

    buttons += [BTN_CLOSE];
    map += [BTN_CLOSE, "menu:close"];

    SessionMap = map;
    SessionMode = SESSION_MENU;

    list bodyParts = ["Select a plugin (Page ", (string)(SessionPage + 1), "/", (string)pages, ")"];
    string body = llDumpList2String(bodyParts, "");
    llDialog(SessionUser, body, buttons, SessionChan);
    llSetTimerEvent(SESSION_TIMEOUT);
    return TRUE;
}

integer start_session(key av){
    if (av == NULL_KEY) return FALSE;
    close_session();
    SessionUser = av;
    SessionAcl = -1;
    SessionPage = 0;
    SessionMode = SESSION_WAIT;
    SessionMap = [];
    open_listener(av);
    llSetTimerEvent(SESSION_TIMEOUT);
    request_acl(av);
    if (llGetListLength(Registry) == 0) request_registry();
    return TRUE;
}

integer ensure_registry(string payload){
    if (!json_has(payload, ["type"])) return FALSE;
    if (llJsonGetValue(payload, ["type"]) != MSG_PLUGIN_LIST) return FALSE;

    list next = [];
    integer i = 0;
    while (llJsonValueType(payload, ["plugins", i]) != JSON_INVALID){
        string ctx = llJsonGetValue(payload, ["plugins", i, "context"]);
        string label = llJsonGetValue(payload, ["plugins", i, "label"]);
        string minStr = llJsonGetValue(payload, ["plugins", i, "min_acl"]);
        if (ctx == PLUGIN_CONTEXT){
            i += 1;
            continue;
        }
        if (ctx == "" || label == "" || minStr == JSON_INVALID){
            i += 1;
            continue;
        }
        integer min_acl = (integer)minStr;
        next += [ctx, label, min_acl];
        i += 1;
    }

    Registry = next;
    logd("registry updated count=" + (string)(llGetListLength(Registry) / 3));

    if (SessionMode == SESSION_MENU){
        show_menu();
    }
    return TRUE;
}

integer handle_acl_result(string payload, key av){
    if (!json_has(payload, ["type"])) return FALSE;
    if (llJsonGetValue(payload, ["type"]) != MSG_AUTH_RESULT) return FALSE;
    if (!json_has(payload, ["avatar"])) return FALSE;
    if ((key)llJsonGetValue(payload, ["avatar"]) != av) return FALSE;

    integer level = -1;
    if (json_has(payload, ["level"])) level = (integer)llJsonGetValue(payload, ["level"]);

    if (SessionUser != av) return TRUE;

    SessionAcl = level;
    if (SessionAcl < PLUGIN_MIN_ACL){
        show_modal("Access denied.", "modal_close");
        return TRUE;
    }
    show_menu();
    return TRUE;
}

integer handle_plugin_start(string payload, key who){
    if (!json_has(payload, ["type"])) return FALSE;
    if (llJsonGetValue(payload, ["type"]) != MSG_PLUGIN_START) return FALSE;
    string ctx = "";
    if (json_has(payload, ["context"])) ctx = llJsonGetValue(payload, ["context"]);
    if (ctx != "" && ctx != PLUGIN_CONTEXT) return FALSE;

    key target = who;
    if (target == NULL_KEY) target = llGetOwner();
    if (target == NULL_KEY) return FALSE;
    start_session(target);
    return TRUE;
}

integer handle_plugin_return(string payload, key who){
    if (!json_has(payload, ["type"])) return FALSE;
    if (llJsonGetValue(payload, ["type"]) != MSG_PLUGIN_RETURN) return FALSE;
    if (json_has(payload, ["context"])){
        string ctx = llJsonGetValue(payload, ["context"]);
        if (ctx != "" && ctx != PLUGIN_CONTEXT) return FALSE;
    }
    if (who == NULL_KEY) return FALSE;
    start_session(who);
    return TRUE;
}

integer handle_plugin_selection(string ctx){
    integer idx = registry_index(ctx);
    if (idx == -1){
        show_modal("Plugin unavailable.", "modal_return");
        return FALSE;
    }
    integer required = llList2Integer(Registry, idx + 2);
    if (SessionAcl < required){
        show_modal("Access denied.", "modal_return");
        return FALSE;
    }
    string payload = llList2Json(JSON_OBJECT, []);
    payload = llJsonSetValue(payload, ["type"], MSG_PLUGIN_START);
    payload = llJsonSetValue(payload, ["context"], ctx);
    llMessageLinked(LINK_SET, K_PLUGIN_START, payload, SessionUser);
    close_session();
    return TRUE;
}

/* ==================== Events ==================== */

default
{
    state_entry(){
        LastOwner = llGetOwner();
        register_self();
        request_registry();
    }

    on_rez(integer sp){
        if (llGetOwner() != LastOwner) llResetScript();
    }

    attach(key id){
        if (id == NULL_KEY) return;
        if (llGetOwner() != LastOwner) llResetScript();
    }

    changed(integer change){
        if (change & CHANGED_OWNER){
            if (llGetOwner() != LastOwner) llResetScript();
        }
        if (change & CHANGED_INVENTORY){
            request_registry();
        }
    }

    touch_start(integer count){
        integer i = 0;
        while (i < count){
            key av = llDetectedKey(i);
            if (within_range(av)){
                start_session(av);
                return;
            }
            i += 1;
        }
    }

    listen(integer channel, string name, key id, string message){
        if (channel != SessionChan) return;
        if (id != SessionUser) return;
        string command = map_command(message);
        if (command == "") return;

        if (command == "menu:close"){
            close_session();
            return;
        }
        if (command == "nav:prev"){
            SessionPage -= 1;
            show_menu();
            return;
        }
        if (command == "nav:next"){
            SessionPage += 1;
            show_menu();
            return;
        }
        if (command == "modal_return"){
            show_menu();
            return;
        }
        if (command == "modal_close"){
            close_session();
            return;
        }
        if (llSubStringIndex(command, "plugin:") == 0){
            string ctx = llGetSubString(command, 7, -1);
            handle_plugin_selection(ctx);
            return;
        }
    }

    link_message(integer sender, integer num, string str, key id){
        if (num == K_PLUGIN_PING){
            if (json_has(str, ["type"]) && llJsonGetValue(str, ["type"]) == MSG_PLUGIN_PING){
                string ctx = "";
                if (json_has(str, ["context"])) ctx = llJsonGetValue(str, ["context"]);
                if (ctx == "" || ctx == PLUGIN_CONTEXT){
                    send_plugin_pong();
                }
            }
            return;
        }
        if (num == K_PLUGIN_REG_QUERY){
            if (json_has(str, ["type"]) && llJsonGetValue(str, ["type"]) == MSG_REGISTER_NOW){
                if (json_has(str, ["script"])){
                    string want = llJsonGetValue(str, ["script"]);
                    if (want != "" && want != llGetScriptName()) return;
                }
                register_self();
            }
            return;
        }
        if (num == K_PLUGIN_SOFT_RESET){
            if (json_has(str, ["type"]) && llJsonGetValue(str, ["type"]) == MSG_PLUGIN_SOFT_RST){
                if (json_has(str, ["context"])){
                    string ctx = llJsonGetValue(str, ["context"]);
                    if (ctx != "" && ctx != PLUGIN_CONTEXT) return;
                }
                register_self();
                request_registry();
            }
            return;
        }
        if (num == K_PLUGIN_LIST){
            ensure_registry(str);
            return;
        }
        if (num == AUTH_RESULT_NUM){
            handle_acl_result(str, id);
            return;
        }
        if (num == K_PLUGIN_START){
            if (handle_plugin_start(str, id)) return;
            return;
        }
        if (num == K_PLUGIN_RETURN){
            if (handle_plugin_return(str, id)) return;
            return;
        }
    }

    timer(){
        if (SessionMode != SESSION_NONE){
            close_session();
        }
    }
}
