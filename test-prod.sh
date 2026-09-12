#!/bin/bash
# Production test suite - runs through nginx on HTTPS
set -e

API="https://localhost"
PASS=0
FAIL=0

test_endpoint() {
    local desc="$1" method="$2" url="$3" expect="$4" body="$5"
    local RESP HTTP BODY

    local -a headers=()
    [ -n "$TOKEN" ] && headers+=(-H "Authorization: Bearer $TOKEN")

    if [ -n "$body" ]; then
        RESP=$(curl -sk --max-redirs 0 -X "$method" "$API$url" \
            -H "Content-Type: application/json" \
            "${headers[@]}" \
            -d "$body" -w "\n%{http_code}" 2>/dev/null)
    else
        RESP=$(curl -sk --max-redirs 0 -X "$method" "$API$url" \
            "${headers[@]}" \
            -w "\n%{http_code}" 2>/dev/null)
    fi
    HTTP=$(echo "$RESP" | tail -1)
    BODY=$(echo "$RESP" | head -n -1)

    if echo "$expect" | grep -q "|"; then
        EXPECTED=$(echo "$expect" | tr '|' '\n')
        FOUND=false
        while IFS= read -r code; do
            [ "$HTTP" = "$code" ] && FOUND=true
        done <<< "$EXPECTED"
        if $FOUND; then
            echo "  ✓ $desc [HTTP $HTTP]"
            PASS=$((PASS+1))
        else
            echo "  ✗ $desc — expected $expect, got $HTTP"
            FAIL=$((FAIL+1))
        fi
    elif [ "$HTTP" = "$expect" ]; then
        echo "  ✓ $desc [HTTP $HTTP]"
        PASS=$((PASS+1))
    else
        echo "  ✗ $desc — expected $expect, got $HTTP ($BODY)"
        FAIL=$((FAIL+1))
    fi
}

# Cleanup first
docker compose -f docker-compose.prod.yml exec -T db psql -U neo -d neo -c \
    "DELETE FROM negocios WHERE slug='prod-test-business'; DELETE FROM users WHERE email='prod-test@test.com'; DELETE FROM negocios WHERE slug='prod-test-2'; DELETE FROM users WHERE email='prod-test2@test.com';" 2>/dev/null || true

echo "══ PRODUCTION TESTS (via Nginx HTTPS) ══"

echo ""
echo "── 1. SSL & Redirects ──"
HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" --max-redirs 0 http://localhost/ 2>/dev/null)
if [ "$HTTP_STATUS" = "301" ]; then
    echo "  ✓ HTTP→HTTPS redirect [HTTP $HTTP_STATUS]"
    PASS=$((PASS+1))
else
    echo "  ✗ HTTP→HTTPS redirect — expected 301, got $HTTP_STATUS"
    FAIL=$((FAIL+1))
fi
test_endpoint "HTTPS web" GET "/" "200"
test_endpoint "Health check" GET "/health" "200"

echo ""
echo "── 2. Auth ──"
test_endpoint "Register" POST "/api/auth/register" "201" '{"email":"prod-test@test.com","password":"Test1234!","firstName":"Prod","lastName":"User","phone":"+5491155556789","nombreNegocio":"Test Business","slug":"prod-test-business"}'
test_endpoint "Login" POST "/api/auth/login" "200" '{"email":"prod-test@test.com","password":"Test1234!"}'
test_endpoint "Wrong password" POST "/api/auth/login" "401" '{"email":"prod-test@test.com","password":"WrongPass!"}'
test_endpoint "Login nonexistent" POST "/api/auth/login" "401" '{"email":"nobody@test.com","password":"x"}'

TOKEN=$(curl -sk --max-time 10 -X POST "$API/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"prod-test@test.com","password":"Test1234!"}' 2>/dev/null | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo "  ⚠️  Could not get token — skipping auth tests"
else
    echo "  ✓ Token obtained"
    PASS=$((PASS+1))

    echo ""
    echo "── 3. Protected Routes (with auth) ──"
    test_endpoint "GET branding" GET "/api/branding" "200"
    test_endpoint "GET products" GET "/api/catalog/products" "200"
    test_endpoint "GET orders" GET "/api/orders" "200"
    test_endpoint "GET stats dashboard" GET "/api/stats/dashboard" "200"
    test_endpoint "GET stats summary" GET "/api/stats/summary?startDate=2026-01-01&endDate=2026-12-31" "200"
    test_endpoint "GET promos" GET "/api/promos" "200"
    test_endpoint "GET clients" GET "/api/clients" "200"
    test_endpoint "GET notifications" GET "/api/notifications" "200"
    test_endpoint "GET recent orders" GET "/api/orders/recent" "200"
fi

echo ""
echo "── 4. Auth Without Token (401) ──"
OLD_TOKEN="$TOKEN"
TOKEN=""
test_endpoint "GET branding (no auth)" GET "/api/branding" "401"
test_endpoint "GET products (no auth)" GET "/api/catalog/products" "401"
test_endpoint "GET orders (no auth)" GET "/api/orders" "401"
test_endpoint "GET stats (no auth)" GET "/api/stats/dashboard" "401"
test_endpoint "GET promos (no auth)" GET "/api/promos" "401"
test_endpoint "GET clients (no auth)" GET "/api/clients" "401"
TOKEN="$OLD_TOKEN"

echo ""
echo "── 5. Public Routes ──"
test_endpoint "Public menu (nonexistent)" GET "/api/public-menu/does-not-exist" "404"
test_endpoint "Health (no auth)" GET "/health" "200"

echo ""
echo "── 6. Security ──"
test_endpoint "SQL injection" POST "/api/auth/login" "400" '{"email":"'\'' OR 1=1--","password":"x"}'

echo ""
echo "═════════════════════════════════════════"
echo " RESULTS"
echo "═════════════════════════════════════════"
echo ""
echo "  Total:  $((PASS+FAIL))"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

# Cleanup
docker compose -f docker-compose.prod.yml exec -T db psql -U neo -d neo -c \
    "DELETE FROM negocios WHERE slug='prod-test-business'; DELETE FROM users WHERE email='prod-test@test.com';" 2>/dev/null || true

if [ "$FAIL" -eq 0 ]; then
    echo "  🎉 ALL TESTS PASSED!"
else
    echo "  ⚠️  Some tests failed"
    exit 1
fi
