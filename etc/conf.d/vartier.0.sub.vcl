vcl 4.0;
import var;

# synthetic classic json
sub deliver_json_200_ok {
	set resp.http.Content-Type = "application/json; charset=utf-8";
	set resp.reason = "OK";
	set resp.status = 200;
	return(deliver);
}

sub vcl_init {
	var.global_set("X-Apis", "Vartier=core-${Version}");
}

sub vcl_deliver {
	set resp.http.X-Vartier-Apis = var.global_get("X-Apis");
}
