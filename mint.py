import sys, json, urllib.request, urllib.parse, urllib.error
d = json.load(sys.stdin)
body = urllib.parse.urlencode({
    "client_id":     d["client_id"],
    "client_secret": d["client_secret"],
    "refresh_token": d["refresh_token"],
    "grant_type":    "refresh_token",
}).encode()
try:
    resp = urllib.request.urlopen("https://oauth2.googleapis.com/token", body, timeout=10)
    r = json.load(resp)
    print(r["access_token"])
    print(r.get("expires_in", 3600))
except urllib.error.HTTPError as e:
    msg = e.read().decode("utf-8", "replace")
    sys.stderr.write("[gcloud-op] token error: " + msg + "\n")
    sys.exit(2 if "invalid_grant" in msg else 1)
