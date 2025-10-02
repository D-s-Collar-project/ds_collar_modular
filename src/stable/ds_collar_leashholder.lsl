// ds_leash_holder_point.lsl — JSON leash target (with simple owner gating)
integer DEBUG = FALSE;
integer CHAN  = -192837465;  // must match collar

// Emits leash holder debug chatter when enabled.
integer logd(string s){ if (DEBUG) llOwnerSay("[HOLDER] " + s); return TRUE; }

// Returns the link key of the leash target prim named "Leash Holder Origin Prim".
key leashPrimKey(){
    integer n = llGetNumberOfPrims();
    integer i = 1;
    integer name_match = 0;
    integer desc_match = 0;
    string target = "leash holder origin prim";
    while (i <= n){
        list params = llGetLinkPrimitiveParams(i,[PRIM_NAME, PRIM_DESC]);
        string nm = llToLower(llStringTrim(llList2String(params,0), STRING_TRIM));
        string desc = llToLower(llStringTrim(llList2String(params,1), STRING_TRIM));
        if (nm == target && desc == target) return llGetLinkKey(i);
        if (nm == target && name_match == 0) name_match = i;
        if (desc == target && desc_match == 0) desc_match = i;
        i = i + 1;
    }
    if (name_match != 0) return llGetLinkKey(name_match);
    if (desc_match != 0) return llGetLinkKey(desc_match);
    return llGetLinkKey(llGetLinkNumber()); /* this prim (child or root) */
}

default{
    // Opens the fixed listen channel and reports readiness.
    state_entry(){
        llListen(CHAN,"",NULL_KEY,"");
        logd("listening on " + (string)CHAN);
    }

    // Answers leash_req messages with this prim's leash target data.
    listen(integer ch, string name, key src, string msg){
        if (ch != CHAN) return;
        if (llJsonGetValue(msg,["type"]) != "leash_req") return;

        /* If broadcast from collar, optional controller gate for worn items */
        key controller = NULL_KEY;
        if (llJsonValueType(msg,["controller"]) != JSON_INVALID) controller = (key)llJsonGetValue(msg,["controller"]);

        /* If attachment: only respond when controller == llGetOwner() */
        integer isAttach = FALSE;
        if (llGetAttached()) isAttach = TRUE;
        if (isAttach){
            if (controller != llGetOwner()) return;
        }

        /* OK to answer */
        integer session = 0;
        if (llJsonValueType(msg,["session"]) != JSON_INVALID) session = (integer)llJsonGetValue(msg,["session"]);
        key collar = (key)llJsonGetValue(msg,["collar"]);
        key prim = leashPrimKey();

        string reply = llList2Json(JSON_OBJECT,[]);
        reply = llJsonSetValue(reply,["type"],"leash_target");
        reply = llJsonSetValue(reply,["ok"],"1");
        reply = llJsonSetValue(reply,["holder"],(string)prim);
        reply = llJsonSetValue(reply,["name"],llGetObjectName());
        reply = llJsonSetValue(reply,["session"],(string)session);

        /* reply direct if we know collar id; else broadcast back */
        if (collar != NULL_KEY) llRegionSayTo(collar,CHAN,reply);
        else llRegionSay(CHAN,reply);

        logd("sent target " + (string)prim + " session=" + (string)session);
    }
}
