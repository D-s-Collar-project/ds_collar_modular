/* =============================================================
   MODULE: ds_collar_kmod_auth.lsl
   ROLE  : Authorization authority.
           - Consumes settings snapshots and resolves ACL levels.
           - Replies to AUTH queries with policy flags and wearer context.
           - Caches lookups and replays queued requests once settings are ready.
   ============================================================= */

integer DEBUG = FALSE;

/* ---------- Message Types ---------- */
string MSG_SETTINGS_GET   = "settings_get";
string MSG_SETTINGS_SYNC  = "settings_sync";
string MSG_AUTH_QUERY     = "acl_query";
string MSG_AUTH_RESULT    = "acl_result";

/* ---------- Link numbers ---------- */
integer SETTINGS_QUERY_NUM = 800;
integer SETTINGS_SYNC_NUM  = 870;
integer AUTH_QUERY_NUM     = 700;
integer AUTH_RESULT_NUM    = 710;

/* ---------- Settings keys ---------- */
string KEY_OWNER_KEY     = "owner_key";
string KEY_TRUSTEES      = "trustees";
string KEY_BLACKLIST     = "blacklist";
string KEY_PUBLIC_ACCESS = "public_mode";
string KEY_TPE_MODE      = "tpe_mode";

/* ---------- ACL levels ---------- */
integer ACL_BLACKLIST     = -1;
integer ACL_NOACCESS      = 0;
integer ACL_PUBLIC        = 1;
integer ACL_OWNED         = 2;
integer ACL_TRUSTEE       = 3;
integer ACL_UNOWNED       = 4;
integer ACL_PRIMARY_OWNER = 5;

/* ---------- Cached state ---------- */
key     OwnerKey       = NULL_KEY;
list    TrusteeList    = [];
list    BlacklistList  = [];
integer PublicMode     = FALSE;
integer TpeMode        = FALSE;
integer SettingsReady  = FALSE;
list    PendingQueries = [];
key     LastOwner      = NULL_KEY;

/* ---------- Helpers ---------- */
integer logd(string msg){ if (DEBUG) llOwnerSay("[AUTH] " + msg); return FALSE; }
integer json_has(string j, list path){ if (llJsonGetValue(j, path) == JSON_INVALID) return FALSE; return TRUE; }
integer is_json_obj(string s){ if (llGetSubString(s, 0, 0) == "{") return TRUE; return FALSE; }
integer is_json_arr(string s){ if (llGetSubString(s, 0, 0) == "[") return TRUE; return FALSE; }

list json_arr_to_list(string s){ if (!is_json_arr(s)) return []; return llJson2List(s); }
integer list_has(list L, string s){ if (llListFindList(L, [s]) != -1) return TRUE; return FALSE; }

integer queue_acl_request(key av){
    if (av == NULL_KEY) return FALSE;
    PendingQueries += [(string)av];
    return TRUE;
}

integer request_settings(){
    string payload = llList2Json(JSON_OBJECT, []);
    payload = llJsonSetValue(payload, ["type"], MSG_SETTINGS_GET);
    llMessageLinked(LINK_SET, SETTINGS_QUERY_NUM, payload, NULL_KEY);
    return TRUE;
}

integer compute_acl(key av){
    key wearer = llGetOwner();
    integer owner_set = FALSE;
    if (OwnerKey != NULL_KEY) owner_set = TRUE;

    integer is_owner = FALSE;
    integer is_wearer = FALSE;
    integer is_trustee = FALSE;
    integer is_black = FALSE;

    if (owner_set && av == OwnerKey) is_owner = TRUE;
    if (av == wearer) is_wearer = TRUE;
    if (!is_owner && !is_wearer){
        if (list_has(TrusteeList, (string)av)) is_trustee = TRUE;
        if (list_has(BlacklistList, (string)av)) is_black = TRUE;
    }

    if (is_owner) return ACL_PRIMARY_OWNER;
    if (is_wearer){
        if (TpeMode) return ACL_NOACCESS;
        if (owner_set) return ACL_OWNED;
        return ACL_UNOWNED;
    }
    if (is_trustee) return ACL_TRUSTEE;
    if (is_black) return ACL_BLACKLIST;
    if (PublicMode) return ACL_PUBLIC;
    return ACL_BLACKLIST;
}

integer send_acl_result(key av, integer level){
    key wearer = llGetOwner();
    integer is_wearer = FALSE;
    if (av == wearer) is_wearer = TRUE;
    integer owner_set = FALSE;
    if (OwnerKey != NULL_KEY) owner_set = TRUE;

    integer policy_tpe            = 0;
    integer policy_public_only    = 0;
    integer policy_owned_only     = 0;
    integer policy_trustee_access = 0;
    integer policy_wearer_unowned = 0;
    integer policy_primary_owner  = 0;

    if (is_wearer){
        if (TpeMode) policy_tpe = 1;
        else {
            if (owner_set) policy_owned_only = 1;
            else policy_wearer_unowned = 1;
        }
        if (!owner_set) policy_trustee_access = 1;
    } else {
        if (PublicMode) policy_public_only = 1;
        if (level == ACL_TRUSTEE) policy_trustee_access = 1;
        if (level == ACL_PRIMARY_OWNER) policy_primary_owner = 1;
    }

    string payload = llList2Json(JSON_OBJECT, []);
    payload = llJsonSetValue(payload, ["type"], MSG_AUTH_RESULT);
    payload = llJsonSetValue(payload, ["avatar"], (string)av);
    payload = llJsonSetValue(payload, ["level"], (string)level);
    payload = llJsonSetValue(payload, ["is_wearer"], (string)is_wearer);
    payload = llJsonSetValue(payload, ["owner_set"], (string)owner_set);
    payload = llJsonSetValue(payload, ["policy_tpe"], (string)policy_tpe);
    payload = llJsonSetValue(payload, ["policy_public_only"], (string)policy_public_only);
    payload = llJsonSetValue(payload, ["policy_owned_only"], (string)policy_owned_only);
    payload = llJsonSetValue(payload, ["policy_trustee_access"], (string)policy_trustee_access);
    payload = llJsonSetValue(payload, ["policy_wearer_unowned"], (string)policy_wearer_unowned);
    payload = llJsonSetValue(payload, ["policy_primary_owner"], (string)policy_primary_owner);
    llMessageLinked(LINK_SET, AUTH_RESULT_NUM, payload, av);
    return TRUE;
}

integer apply_settings(string payload){
    if (!json_has(payload, ["type"])) return FALSE;
    if (llJsonGetValue(payload, ["type"]) != MSG_SETTINGS_SYNC) return FALSE;
    if (!json_has(payload, ["kv"])) return FALSE;
    string kv = llJsonGetValue(payload, ["kv"]);
    if (!is_json_obj(kv)) return FALSE;

    OwnerKey      = NULL_KEY;
    TrusteeList   = [];
    BlacklistList = [];
    PublicMode    = FALSE;
    TpeMode       = FALSE;

    if (json_has(kv, [KEY_OWNER_KEY])) OwnerKey = (key)llJsonGetValue(kv, [KEY_OWNER_KEY]);
    if (json_has(kv, [KEY_TRUSTEES])) TrusteeList = json_arr_to_list(llJsonGetValue(kv, [KEY_TRUSTEES]));
    if (json_has(kv, [KEY_BLACKLIST])) BlacklistList = json_arr_to_list(llJsonGetValue(kv, [KEY_BLACKLIST]));
    if (json_has(kv, [KEY_PUBLIC_ACCESS])) PublicMode = (integer)llJsonGetValue(kv, [KEY_PUBLIC_ACCESS]);
    if (json_has(kv, [KEY_TPE_MODE])) TpeMode = (integer)llJsonGetValue(kv, [KEY_TPE_MODE]);

    SettingsReady = TRUE;
    logd("settings applied");

    integer i = 0;
    integer n = llGetListLength(PendingQueries);
    while (i < n){
        key av = (key)llList2String(PendingQueries, i);
        if (av != NULL_KEY){
            integer lvl = compute_acl(av);
            send_acl_result(av, lvl);
        }
        i += 1;
    }
    PendingQueries = [];
    return TRUE;
}

/* ---------- Events ---------- */
default
{
    state_entry(){
        LastOwner = llGetOwner();
        SettingsReady = FALSE;
        PendingQueries = [];
        request_settings();
    }

    on_rez(integer start_param){
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
    }

    link_message(integer sender, integer num, string str, key id){
        if (num == SETTINGS_SYNC_NUM){
            apply_settings(str);
            return;
        }
        if (num == AUTH_QUERY_NUM){
            if (!json_has(str, ["type"])) return;
            if (llJsonGetValue(str, ["type"]) != MSG_AUTH_QUERY) return;
            if (!json_has(str, ["avatar"])) return;
            key av = (key)llJsonGetValue(str, ["avatar"]);
            if (SettingsReady){
                integer level = compute_acl(av);
                send_acl_result(av, level);
            } else {
                queue_acl_request(av);
                request_settings();
            }
            return;
        }
        if (num == SETTINGS_QUERY_NUM){
            if (!json_has(str, ["type"])) return;
            if (llJsonGetValue(str, ["type"]) != MSG_SETTINGS_SYNC) return;
            apply_settings(str);
            return;
        }
    }
}
