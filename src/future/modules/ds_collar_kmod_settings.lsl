/* =============================================================
   MODULE: ds_collar_kmod_settings.lsl
   ROLE  : Settings authority for DS Collar.
           - Stores collar configuration in JSON (kv + lists).
           - Responds to get/set/list mutations and broadcasts snapshots.
           - Enforces mutual exclusivity between owner, trustees, and blacklist.
   ============================================================= */

integer DEBUG = FALSE;

/* ---------- Message Types ---------- */
string TYPE_SETTINGS_GET   = "settings_get";
string TYPE_SETTINGS_SYNC  = "settings_sync";
string TYPE_SET            = "set";
string TYPE_LIST_ADD       = "list_add";
string TYPE_LIST_REMOVE    = "list_remove";

/* ---------- Link numbers ---------- */
integer SETTINGS_QUERY_NUM = 800;
integer SETTINGS_SYNC_NUM  = 870;

/* ---------- Keys ---------- */
string KEY_OWNER_KEY        = "owner_key";
string KEY_OWNER_HON        = "owner_hon";
string KEY_TRUSTEES         = "trustees";
string KEY_TRUSTEE_HONS     = "trustee_honorifics";
string KEY_BLACKLIST        = "blacklist";
string KEY_PUBLIC_ACCESS    = "public_mode";
string KEY_TPE_MODE         = "tpe_mode";
string KEY_LOCKED           = "locked";
string KEY_CHAT_PREFIX      = "chat_prefix";

/* ---------- State ---------- */
key     LastOwner   = NULL_KEY;
string  KvJson      = "{}";
integer MaxListSize = 64;
integer LastGetTs   = 0;

/* ---------- Helpers ---------- */
integer logd(string msg){ if (DEBUG) llOwnerSay("[SETTINGS] " + msg); return FALSE; }
integer json_has(string j, list path){ if (llJsonGetValue(j, path) == JSON_INVALID) return FALSE; return TRUE; }
integer is_json_obj(string s){ if (llGetSubString(s, 0, 0) == "{") return TRUE; return FALSE; }
integer is_json_arr(string s){ if (llGetSubString(s, 0, 0) == "[") return TRUE; return FALSE; }

string kv_get(string key_str){
    string v = llJsonGetValue(KvJson, [key_str]);
    if (v == JSON_INVALID) return "";
    return v;
}

integer kv_set_scalar(string key_str, string value){
    string oldv = kv_get(key_str);
    if (oldv == value) return FALSE;
    KvJson = llJsonSetValue(KvJson, [key_str], value);
    logd("SET " + key_str + "=" + value);
    return TRUE;
}

integer kv_set_list(string key_str, list values){
    string next = llList2Json(JSON_ARRAY, values);
    string oldv = kv_get(key_str);
    if (oldv == next) return FALSE;
    KvJson = llJsonSetValue(KvJson, [key_str], next);
    logd("SET " + key_str + " count=" + (string)llGetListLength(values));
    return TRUE;
}

list json_array_to_list(string arr_json){
    if (!is_json_arr(arr_json)) return [];
    list out = llJson2List(arr_json);
    integer n = llGetListLength(out);
    if (n <= MaxListSize) return out;
    return llList2List(out, 0, MaxListSize - 1);
}

integer list_contains(list L, string s){ if (llListFindList(L, [s]) != -1) return TRUE; return FALSE; }

list list_remove_all(list L, string s){
    integer idx = llListFindList(L, [s]);
    while (idx != -1){
        L = llDeleteSubList(L, idx, idx);
        idx = llListFindList(L, [s]);
    }
    return L;
}

list list_unique(list L){
    list out = [];
    integer i = 0;
    integer n = llGetListLength(L);
    while (i < n){
        string item = llList2String(L, i);
        if (!list_contains(out, item)) out += [item];
        i += 1;
    }
    return out;
}

integer is_allowed_key(string key_str){
    if (key_str == KEY_OWNER_KEY) return TRUE;
    if (key_str == KEY_OWNER_HON) return TRUE;
    if (key_str == KEY_TRUSTEES) return TRUE;
    if (key_str == KEY_TRUSTEE_HONS) return TRUE;
    if (key_str == KEY_BLACKLIST) return TRUE;
    if (key_str == KEY_PUBLIC_ACCESS) return TRUE;
    if (key_str == KEY_TPE_MODE) return TRUE;
    if (key_str == KEY_LOCKED) return TRUE;
    if (key_str == KEY_CHAT_PREFIX) return TRUE;
    return FALSE;
}

string normalize_mode01(string s){
    integer v = (integer)s;
    if (v != 0) v = 1;
    return (string)v;
}

string sanitize_roles(string source){
    string kv = source;

    key owner = NULL_KEY;
    string owner_str = llJsonGetValue(kv, [KEY_OWNER_KEY]);
    if (owner_str != JSON_INVALID) owner = (key)owner_str;

    list trustees = [];
    string t_arr = llJsonGetValue(kv, [KEY_TRUSTEES]);
    if (t_arr != JSON_INVALID && is_json_arr(t_arr)) trustees = llJson2List(t_arr);

    list blacklist = [];
    string b_arr = llJsonGetValue(kv, [KEY_BLACKLIST]);
    if (b_arr != JSON_INVALID && is_json_arr(b_arr)) blacklist = llJson2List(b_arr);

    trustees = list_unique(trustees);
    blacklist = list_unique(blacklist);

    if (owner != NULL_KEY){
        trustees = list_remove_all(trustees, (string)owner);
        if (list_contains(blacklist, (string)owner)) owner = NULL_KEY;
    }

    list clean_trustees = [];
    integer i = 0;
    integer n = llGetListLength(trustees);
    while (i < n){
        string who = llList2String(trustees, i);
        if (!list_contains(blacklist, who)) clean_trustees += [who];
        i += 1;
    }
    trustees = clean_trustees;

    kv = llJsonSetValue(kv, [KEY_OWNER_KEY], (string)owner);
    kv = llJsonSetValue(kv, [KEY_TRUSTEES], llList2Json(JSON_ARRAY, trustees));
    kv = llJsonSetValue(kv, [KEY_BLACKLIST], llList2Json(JSON_ARRAY, blacklist));
    return kv;
}

integer broadcast_sync(){
    KvJson = sanitize_roles(KvJson);
    string payload = llList2Json(JSON_OBJECT, []);
    payload = llJsonSetValue(payload, ["type"], TYPE_SETTINGS_SYNC);
    payload = llJsonSetValue(payload, ["kv"], KvJson);
    llMessageLinked(LINK_SET, SETTINGS_SYNC_NUM, payload, NULL_KEY);
    logd("sync broadcast");
    return TRUE;
}

integer maybe_broadcast_on_get(){
    integer ts = llGetUnixTime();
    if (ts == LastGetTs) return FALSE;
    LastGetTs = ts;
    broadcast_sync();
    return TRUE;
}

integer apply_owner_guard(string owner_str){
    if (owner_str == "" || owner_str == (string)NULL_KEY) return FALSE;
    string trustees = kv_get(KEY_TRUSTEES);
    if (is_json_arr(trustees)){
        list t = llJson2List(trustees);
        t = list_remove_all(t, owner_str);
        kv_set_list(KEY_TRUSTEES, t);
    }
    string blacklist = kv_get(KEY_BLACKLIST);
    if (is_json_arr(blacklist)){
        list b = llJson2List(blacklist);
        b = list_remove_all(b, owner_str);
        kv_set_list(KEY_BLACKLIST, b);
    }
    return TRUE;
}

integer apply_trustee_add_guard(string trustee){
    string owner = kv_get(KEY_OWNER_KEY);
    if (owner != "" && owner != JSON_INVALID){
        if (trustee == owner) return FALSE;
    }
    string blacklist = kv_get(KEY_BLACKLIST);
    if (is_json_arr(blacklist)){
        list b = llJson2List(blacklist);
        b = list_remove_all(b, trustee);
        kv_set_list(KEY_BLACKLIST, b);
    }
    return TRUE;
}

integer apply_blacklist_add_guard(string who){
    string trustees = kv_get(KEY_TRUSTEES);
    if (is_json_arr(trustees)){
        list t = llJson2List(trustees);
        t = list_remove_all(t, who);
        kv_set_list(KEY_TRUSTEES, t);
    }
    string owner = kv_get(KEY_OWNER_KEY);
    if (owner != "" && owner != JSON_INVALID){
        if (who == owner){
            kv_set_scalar(KEY_OWNER_KEY, (string)NULL_KEY);
        }
    }
    return TRUE;
}

/* ---------- Events ---------- */
default
{
    state_entry(){
        LastOwner = llGetOwner();
        broadcast_sync();
    }

    on_rez(integer param){
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
        if (num != SETTINGS_QUERY_NUM) return;
        if (!json_has(str, ["type"])) return;
        string t = llJsonGetValue(str, ["type"]);

        if (t == TYPE_SETTINGS_GET){
            maybe_broadcast_on_get();
            return;
        }

        if (t == TYPE_SET){
            if (!json_has(str, ["key"])) return;
            string key_str = llJsonGetValue(str, ["key"]);
            if (!is_allowed_key(key_str)) return;
            integer changed_scalar = FALSE;

            if (json_has(str, ["values"])){
                string arr = llJsonGetValue(str, ["values"]);
                if (is_json_arr(arr)){
                    list values = json_array_to_list(arr);
                    values = list_unique(values);
                    if (key_str == KEY_TRUSTEES){
                        string owner = kv_get(KEY_OWNER_KEY);
                        if (owner != "" && owner != JSON_INVALID){
                            values = list_remove_all(values, owner);
                        }
                        string blacklist = kv_get(KEY_BLACKLIST);
                        if (is_json_arr(blacklist)){
                            list b = llJson2List(blacklist);
                            integer i = 0;
                            while (i < llGetListLength(values)){
                                string who = llList2String(values, i);
                                b = list_remove_all(b, who);
                                i += 1;
                            }
                            kv_set_list(KEY_BLACKLIST, b);
                        }
                    }
                    if (key_str == KEY_BLACKLIST){
                        string owner = kv_get(KEY_OWNER_KEY);
                        if (owner != "" && owner != JSON_INVALID){
                            if (list_contains(values, owner)) kv_set_scalar(KEY_OWNER_KEY, (string)NULL_KEY);
                        }
                        string trustees = kv_get(KEY_TRUSTEES);
                        if (is_json_arr(trustees)){
                            list tlist = llJson2List(trustees);
                            integer i2 = 0;
                            while (i2 < llGetListLength(values)){
                                string who2 = llList2String(values, i2);
                                tlist = list_remove_all(tlist, who2);
                                i2 += 1;
                            }
                            kv_set_list(KEY_TRUSTEES, tlist);
                        }
                    }
                    changed_scalar = kv_set_list(key_str, values);
                }
            }
            else if (json_has(str, ["value"])){
                string value = llJsonGetValue(str, ["value"]);
                if (value != JSON_INVALID){
                    if (key_str == KEY_PUBLIC_ACCESS) value = normalize_mode01(value);
                    if (key_str == KEY_TPE_MODE) value = normalize_mode01(value);
                    if (key_str == KEY_LOCKED) value = normalize_mode01(value);
                    if (key_str == KEY_OWNER_KEY){
                        apply_owner_guard(value);
                    }
                    changed_scalar = kv_set_scalar(key_str, value);
                }
            }

            if (changed_scalar) broadcast_sync();
            return;
        }

        if (t == TYPE_LIST_ADD || t == TYPE_LIST_REMOVE){
            if (!json_has(str, ["key"])) return;
            if (!json_has(str, ["elem"])) return;
            string key_str = llJsonGetValue(str, ["key"]);
            string elem = llJsonGetValue(str, ["elem"]);
            if (!is_allowed_key(key_str)) return;
            integer changed_list = FALSE;

            if (t == TYPE_LIST_ADD){
                list existing = json_array_to_list(kv_get(key_str));
                if (list_contains(existing, elem)) return;
                if (llGetListLength(existing) >= MaxListSize) return;

                if (key_str == KEY_TRUSTEES){
                    if (!apply_trustee_add_guard(elem)) return;
                    existing += [elem];
                    existing = list_unique(existing);
                    changed_list = kv_set_list(KEY_TRUSTEES, existing);
                }
                else if (key_str == KEY_BLACKLIST){
                    apply_blacklist_add_guard(elem);
                    existing += [elem];
                    existing = list_unique(existing);
                    changed_list = kv_set_list(KEY_BLACKLIST, existing);
                }
                else {
                    existing += [elem];
                    existing = list_unique(existing);
                    changed_list = kv_set_list(key_str, existing);
                }
            } else {
                list existing = json_array_to_list(kv_get(key_str));
                list next = list_remove_all(existing, elem);
                changed_list = kv_set_list(key_str, next);
            }

            if (changed_list) broadcast_sync();
            return;
        }
    }
}
