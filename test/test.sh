#!/usr/bin/env bash
# Test suite for SAP RAP OData V4 Service
# Mirrors test/test.sh for the SAP RAP Architecture
#
# Usage:
#   bash test/test.sh <url> <client> <user> <password>
#
# Needs: curl, python3.
set -uo pipefail

if [ "$#" -ne 4 ]; then
  echo "Error: Invalid number of arguments." >&2
  echo "Usage: bash test/test.sh <url> <client> <user> <password>" >&2
  exit 1
fi

BASE="$1"
SAP_CLIENT="$2"
SAP_USER="$3"
SAP_PASSWORD="$4"

ODATA_PATH="${ODATA_PATH:-/sap/opu/odata4/sap/z12d_feed_srvb_o4/srvd_a2x/sap/z12d_feed_srvd/0001}"
BASE="${BASE%/}"
ODATA_PATH="/${ODATA_PATH#/}"
SERVICE_URL="${BASE}${ODATA_PATH}"

ACTION_NAME="${ACTION_NAME:-com.sap.gateway.srvd_a2x.z12d_feed_srvd.v0001.likePost}"
GOLDEN="$(cd "$(dirname "$0")" && pwd)/golden"

TMP="$(mktemp -d)"
COOKIE_JAR="$TMP/cookies"
CSRF_TOKEN=""
CREATED_POST_ID=""

cleanup() {
  if [ -n "$CREATED_POST_ID" ]; then
    fetch_csrf > /dev/null 2>&1 || true
    curl -s -o /dev/null -u "$SAP_USER:$SAP_PASSWORD" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
      -H "sap-client: $SAP_CLIENT" -H "x-csrf-token: $CSRF_TOKEN" -H "Accept: application/json" \
      -X DELETE "${SERVICE_URL}/Post(${CREATED_POST_ID})?sap-client=${SAP_CLIENT}" > /dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

pass=0; fail=0
ok()  { echo "  ok   $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; [ -n "${2:-}" ] && echo "       $2"; fail=$((fail+1)); }

# Helper to query json values via python3
py_get() {
  local json_str="$1"
  local expr="$2"
  python3 -c '
import sys, json
try:
  d = json.loads(sys.argv[1])
  expr = sys.argv[2]
  res = eval(expr, {"d": d, "len": len})
  if res is None:
    print("")
  elif isinstance(res, bool):
    print("true" if res else "false")
  else:
    print(res)
except Exception:
  print("")
' "$json_str" "$expr"
}

fetch_csrf() {
  local full_url="${SERVICE_URL}/Post?\$top=1&sap-client=${SAP_CLIENT}"
  local args=(-s -o "$TMP/csrf_body" -D "$TMP/csrf_headers" -X GET)
  args+=(-b "$COOKIE_JAR" -c "$COOKIE_JAR")
  [ -n "$SAP_USER" ] && args+=(-u "$SAP_USER:$SAP_PASSWORD")
  args+=(-H "sap-client: $SAP_CLIENT")
  args+=(-H "x-csrf-token: fetch")
  args+=(-H "Accept: application/json")

  curl "${args[@]}" "$full_url" > /dev/null 2>&1 || true
  CSRF_TOKEN="$(grep -i '^x-csrf-token:' "$TMP/csrf_headers" 2>/dev/null | head -1 | cut -d' ' -f2- | tr -d '\r\n')"
}

# req <method> <path> [json-data]
req() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local args=(-s -o "$TMP/body" -D "$TMP/headers" -w '%{http_code}' -X "$method")
  args+=(-b "$COOKIE_JAR" -c "$COOKIE_JAR")
  [ -n "$SAP_USER" ] && args+=(-u "$SAP_USER:$SAP_PASSWORD")
  args+=(-H "sap-client: $SAP_CLIENT")
  args+=(-H "Accept: application/json")

  if [ "$method" = "POST" ] || [ "$method" = "PUT" ] || [ "$method" = "PATCH" ] || [ "$method" = "DELETE" ]; then
    fetch_csrf
    [ -n "$CSRF_TOKEN" ] && args+=(-H "x-csrf-token: $CSRF_TOKEN")
    args+=(-H "Content-Type: application/json")
    [ -n "$data" ] && args+=(--data-binary "$data")
  fi

  local sep="?"
  [[ "$path" == *"?"* ]] && sep="&"
  local full_url="${SERVICE_URL}${path}${sep}sap-client=${SAP_CLIENT}"

  STATUS="$(curl "${args[@]}" "$full_url")"
  BODY="$(cat "$TMP/body")"
  CTYPE="$(grep -i '^content-type:' "$TMP/headers" 2>/dev/null | head -1 | cut -d' ' -f2- | tr -d '\r')"
}

expect_status() {
  local label="$1"
  local want_status="$2"
  if [ "$STATUS" = "$want_status" ]; then
    ok "$label -> $STATUS"
  else
    bad "$label" "want HTTP $want_status, got $STATUS\n       Body: $(echo "$BODY" | head -c 200)"
  fi
}

expect_golden() {
  local label="$1"
  local want_status="$2"
  local golden_file="$3"

  if [ "$STATUS" != "$want_status" ]; then
    bad "$label" "want HTTP $want_status, got $STATUS\n       Body: $(echo "$BODY" | head -c 200)"
    return
  fi

  if [ ! -f "$golden_file" ]; then
    bad "$label" "golden file not found: $golden_file"
    return
  fi

  local match
  match="$(python3 -c '
import sys, json
try:
  g = json.load(open(sys.argv[1]))
  b = json.loads(sys.argv[2])
  # Remove volatile metadata etags for reliable comparison
  g.pop("@odata.metadataEtag", None)
  b.pop("@odata.metadataEtag", None)
  if g == b:
    print("OK")
  else:
    diffs = []
    g_val = g.get("value", [g]) if isinstance(g, dict) else g
    b_val = b.get("value", [b]) if isinstance(b, dict) else b
    if isinstance(g_val, list) and isinstance(b_val, list):
      if len(g_val) != len(b_val):
        diffs.append(f"count mismatch: golden={len(g_val)}, actual={len(b_val)}")
      for idx in range(min(len(g_val), len(b_val))):
        if g_val[idx] != b_val[idx]:
          p_id = g_val[idx].get("Id", idx)
          diff_fields = [k for k in set(list(g_val[idx].keys()) + list(b_val[idx].keys())) if g_val[idx].get(k) != b_val[idx].get(k)]
          diff_detail = ", ".join([f"{k}: golden={g_val[idx].get(k)} actual={b_val[idx].get(k)}" for k in diff_fields])
          diffs.append(f"Post ID {p_id} ({diff_detail})")
    else:
      diff_fields = [k for k in set(list(g.keys()) + list(b.keys())) if g.get(k) != b.get(k)]
      diffs = [f"{k}: golden={g.get(k)} actual={b.get(k)}" for k in diff_fields]
    print("MISMATCH: " + "; ".join(diffs[:3]))
except Exception as e:
  print("ERROR: " + str(e))
' "$golden_file" "$BODY")"

  if [ "$match" = "OK" ]; then
    ok "$label -> $STATUS"
  else
    bad "$label" "Response does not match golden file $(basename "$golden_file")\n       $match"
  fi
}

json_ctype() {
  case "$CTYPE" in
    application/json*) ok "$1 content-type ($CTYPE)" ;;
    *) bad "$1 content-type" "got '$CTYPE'" ;;
  esac
}

echo "Testing SAP RAP OData V4 Service at: $SERVICE_URL"
echo "SAP Client: $SAP_CLIENT | SAP User: $SAP_USER"
echo ""

# ------------------------------------------------------------------------------
# 1. Metadata check
# ------------------------------------------------------------------------------
echo "-- 1. Service Metadata Check"
META_STATUS="$(curl -s -o "$TMP/meta" -w '%{http_code}' -u "$SAP_USER:$SAP_PASSWORD" "${SERVICE_URL}/\$metadata?sap-client=${SAP_CLIENT}")"
if [ "$META_STATUS" = 200 ] && grep -qi "EntityType Name=\"PostType\"" "$TMP/meta" 2>/dev/null; then
  ok "GET \$metadata -> 200 (Contains EntityType PostType)"
elif [ "$META_STATUS" = 200 ] && grep -qi "Post" "$TMP/meta" 2>/dev/null; then
  ok "GET \$metadata -> 200 (Contains Post entity)"
else
  bad "GET \$metadata" "got status $META_STATUS (Make sure the service is published and URL is reachable)"
fi

# ------------------------------------------------------------------------------
# 2. Golden reads (fresh database)
# ------------------------------------------------------------------------------
echo "-- 2. Golden Reads (Fresh / Seeded State)"
req GET "/Post?\$top=20&\$orderby=CreatedAt%20desc,Id%20desc"
expect_golden "GET /Post (Feed) == golden" 200 "$GOLDEN/feed.json"
json_ctype "GET /Post (Feed)"

feed_len="$(py_get "$BODY" "len(d.get('value', []))")"
if [ "$feed_len" = 20 ]; then
  ok "Feed contains 20 posts"
else
  bad "Feed count" "want 20 posts, got $feed_len"
fi

for f in "$GOLDEN"/post-*.json; do
  id="$(basename "$f" .json)"; id="${id#post-}"
  req GET "/Post($id)"
  expect_golden "GET /Post($id) == golden" 200 "$f"
done
json_ctype "GET /Post(:id)"

# ------------------------------------------------------------------------------
# 3. Error handling / 404
# ------------------------------------------------------------------------------
echo "-- 3. Non-Existent Post (404 Not Found)"
req GET "/Post(999999999)"
expect_status "GET /Post(999999999)" 404

# ------------------------------------------------------------------------------
# 4. Create a new post
# ------------------------------------------------------------------------------
echo "-- 4. Create Post via OData V4"
TS_NOW="$(date +%s)"
NEW_BODY="Automated test post from SAP test.sh (ts $TS_NOW)"
req POST "/Post" "{\"UserId\":1,\"Body\":\"$NEW_BODY\"}"
expect_status "POST /Post (Create)" 201

NEW_ID="$(py_get "$BODY" "d.get('Id')")"
CREATED_POST_ID="$NEW_ID"
CREATED_AT="$(py_get "$BODY" "d.get('CreatedAt')")"
INIT_LIKES="$(py_get "$BODY" "d.get('LikeCount', 0)")"
INIT_LIKES="${INIT_LIKES:-0}"

if [ -n "$NEW_ID" ] && [ "$NEW_ID" -gt 0 ]; then
  ok "Created post assigned ID: $NEW_ID"
else
  bad "Post ID creation" "got invalid ID $NEW_ID"
fi

if [ -n "$CREATED_AT" ]; then
  ok "Created post has timestamp: $CREATED_AT"
else
  bad "Post CreatedAt" "timestamp is missing or empty"
fi

# ------------------------------------------------------------------------------
# 5. Verify feed ordering (new post at the top)
# ------------------------------------------------------------------------------
echo "-- 5. Verify Feed Top Entry"
req GET "/Post?\$top=20&\$orderby=CreatedAt%20desc,Id%20desc"
top_feed_id="$(py_get "$BODY" "d.get('value', [{}])[0].get('Id')")"
if [ "$top_feed_id" = "$NEW_ID" ]; then
  ok "Newly created post ($NEW_ID) is at the top of the feed"
else
  bad "Feed top entry" "want $NEW_ID, got $top_feed_id"
fi

# ------------------------------------------------------------------------------
# 6. Action: likePost (First time - Unique User)
# ------------------------------------------------------------------------------
echo "-- 6. Action: likePost (First Time)"
TEST_USER=$(( 800000 + (RANDOM * 100) + (RANDOM % 100) ))
req POST "/Post($NEW_ID)/$ACTION_NAME" "{\"UserId\":$TEST_USER}"
if [ "$STATUS" = 200 ] || [ "$STATUS" = 201 ] || [ "$STATUS" = 204 ]; then
  ok "likePost action (first) -> $STATUS"
else
  bad "likePost action (first)" "got status $STATUS ($BODY)"
fi

is_already="$(py_get "$BODY" "d.get('ALREADY_LIKED', d.get('already_liked'))")"
if [ "$is_already" = "false" ]; then
  ok "Action result confirmed: already_liked == false"
else
  bad "Action result" "want already_liked == false, got $is_already"
fi

# ------------------------------------------------------------------------------
# 7. Action: likePost (Repeat / Idempotency)
# ------------------------------------------------------------------------------
echo "-- 7. Action: likePost (Repeat Idempotency)"
req POST "/Post($NEW_ID)/$ACTION_NAME" "{\"UserId\":$TEST_USER}"
if [ "$STATUS" = 200 ] || [ "$STATUS" = 201 ] || [ "$STATUS" = 204 ]; then
  ok "likePost action (repeat) -> $STATUS"
else
  bad "likePost action (repeat)" "got status $STATUS ($BODY)"
fi

is_already_repeat="$(py_get "$BODY" "d.get('ALREADY_LIKED', d.get('already_liked'))")"
if [ "$is_already_repeat" = "true" ]; then
  ok "Action result confirmed idempotent: already_liked == true"
else
  bad "Action result" "want already_liked == true, got $is_already_repeat"
fi

# ------------------------------------------------------------------------------
# 8. Read back the post & verify like count increment
# ------------------------------------------------------------------------------
echo "-- 8. Read Back Post & Verify Like Count"
req GET "/Post($NEW_ID)"
expect_status "GET /Post($NEW_ID)" 200
read_likes="$(py_get "$BODY" "d.get('LikeCount')")"
expected_likes=$(( INIT_LIKES + 1 ))
if [ "$read_likes" = "$expected_likes" ]; then
  ok "Post $NEW_ID like_count incremented ($INIT_LIKES -> $read_likes)"
else
  bad "Post $NEW_ID like_count" "want $expected_likes, got $read_likes"
fi

# ------------------------------------------------------------------------------
# 9. Clean up created post (Repeatability)
# ------------------------------------------------------------------------------
echo "-- 9. Cleanup Created Post (Repeatability)"
req DELETE "/Post($NEW_ID)"
if [ "$STATUS" = 200 ] || [ "$STATUS" = 204 ]; then
  ok "DELETE /Post($NEW_ID) -> $STATUS"
  CREATED_POST_ID=""
else
  bad "DELETE /Post($NEW_ID)" "got status $STATUS ($BODY)"
fi

req GET "/Post($NEW_ID)"
expect_status "Verify GET /Post($NEW_ID) after delete" 404

# ------------------------------------------------------------------------------
# 10. Re-verify golden feed (Feed restored to initial state)
# ------------------------------------------------------------------------------
echo "-- 10. Re-verify Golden Feed After Cleanup"
req GET "/Post?\$top=20&\$orderby=CreatedAt%20desc,Id%20desc"
expect_golden "GET /Post (Feed restored) == golden" 200 "$GOLDEN/feed.json"

echo ""
echo "=================================================="
echo "Test Results: passed=$pass failed=$fail"
echo "=================================================="
[ "$fail" = 0 ]
