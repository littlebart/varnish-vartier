vcl 4.0;
import xkey;

/**
 * to invalidate objects by key/keys with soft or purge :
 *    curl -v -H "keys: item94 item20" localhost:6081/vartier:xkey/soft
 */

acl vartier_purge {
	"localhost";
	"10.0.0.0/8";
	"172.16.0.0/12";
	"192.168.0.0/16";
	"127.0.0.1";
}

sub vcl_init {
	var.global_set("X-Apis", var.global_get("X-Apis") + "; vartier:xkey=local");
}

sub vcl_recv {
	if (req.url ~ "^/vartier:xkey/") {
		if (client.ip !~ vartier_purge) {
			return (synth(403, "Forbidden"));
		}
		if (!req.http.keys) {
			return (synth(699, {"Header "key" not present"}));
		}
		if (req.url ~ "/soft") {
			# softpurge only to invalidate after user requests, but allow grace with current stored data
			return (synth(698, xkey.softpurge(req.http.keys)));
		} else {
			# purge can clean memory immediately, but always require backend hit to return any purged data
			return (synth(697, xkey.purge(req.http.keys)));
		}
	}
}

sub vcl_synth {
	if (resp.status == 699) {
		synthetic( {"{
	"app": "Vartier",
	"api":  "vartier:xkey",
	"error": ""} + resp.reason + {""
}"} );
		set resp.status = 400;
		set resp.reason = "Bad request";
		return(deliver);
	}
	if (resp.status == 698) {
		set resp.http.softpurged = resp.reason;
		synthetic( {"{
	"app": "Vartier",
	"api":  "vartier:xkey",
	"method": "softpurge",
	"objects": ""} + resp.reason + {""
}"} );
		call deliver_json_200_ok;
	}
	if (resp.status == 697) {
		set resp.http.purged = resp.reason;
		synthetic( {"{
	"app": "Vartier",
	"api":  "vartier:xkey",
	"method": "purge",
	"objects": ""} + resp.reason + {""
}"} );
		call deliver_json_200_ok;
	}
}
