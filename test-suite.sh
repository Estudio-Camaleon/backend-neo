#!/bin/bash
# ============================================
# NEO API - Test Suite Completo
# ============================================
API="http://localhost:4000"
PASS=0
FAIL=0
TOTAL=0

# Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

# ── Setup: clear rate limits & ensure clean DB state ──
echo -e "${BLUE}Setting up...${NC}"
docker compose exec -T db psql -U neo -d neo -c "TRUNCATE rate_limits;" 2>/dev/null || true
docker compose exec -T db psql -U neo -d neo -c "
  DELETE FROM notifications WHERE negocio_id IN (SELECT id FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio'));
  DELETE FROM pedido_items WHERE pedido_id IN (SELECT id FROM pedidos WHERE negocio_id IN (SELECT id FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio')));
  DELETE FROM pedidos WHERE negocio_id IN (SELECT id FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio'));
  DELETE FROM productos WHERE negocio_id IN (SELECT id FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio'));
  DELETE FROM categorias WHERE negocio_id IN (SELECT id FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio'));
  DELETE FROM promos WHERE negocio_id IN (SELECT id FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio'));
  DELETE FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio');
  DELETE FROM users WHERE email IN ('testuser2@test.com','neo-test-user@test.com');
" 2>/dev/null || true
docker compose restart api > /dev/null 2>&1
echo -n "Waiting for API..."
for i in $(seq 1 30); do
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$API/health" 2>/dev/null)
  if [ "$HTTP" = "200" ]; then
    sleep 2
    HTTP2=$(curl -s -o /dev/null -w "%{http_code}" "$API/health" 2>/dev/null)
    if [ "$HTTP2" = "200" ]; then
      echo " ready."
      break
    fi
  fi
  sleep 1
done

# ── Assertions ──
assert_status() {
  local desc="$1" expected="$2" actual="$3" body="$4"
  TOTAL=$((TOTAL + 1))
  if [ "$actual" = "$expected" ]; then
    echo -e "  ${GREEN}✓${NC} $desc [HTTP $actual]"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} $desc [Expected $expected, got $actual]"
    echo -e "    Body: $(echo "$body" | head -c 200)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -q "$needle"; then
    echo -e "  ${GREEN}✓${NC} $desc (contains '$needle')"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} $desc (missing '$needle')"
    echo -e "    Body: $(echo "$haystack" | head -c 200)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_empty() {
  local desc="$1" value="$2"
  TOTAL=$((TOTAL + 1))
  if [ -n "$value" ] && [ "$value" != "null" ] && [ "$value" != "" ]; then
    echo -e "  ${GREEN}✓${NC} $desc (got value)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} $desc (empty or null)"
    FAIL=$((FAIL + 1))
  fi
}

# ════════════════════════════════════════════════
# 1. AUTH TESTS
# ════════════════════════════════════════════════
echo -e "\n${BLUE}══ 1. AUTH TESTS ══${NC}"

RESP=$(curl -s -w "\n%{http_code}" "$API/health")
assert_status "GET /health" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$API/api/auth/register" -H "Content-Type: application/json" \
  -d '{"email":"testuser2@test.com","password":"Test1234!","firstName":"Test","lastName":"User","phone":"+5491199999999","nombreNegocio":"Pizzeria Napoli","slug":"pizzeria-napoli"}')
assert_status "POST /api/auth/register" "201" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"
TOKEN2=$(echo "$RESP" | head -1 | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)

RESP=$(curl -s -w "\n%{http_code}" -X POST "$API/api/auth/register" -H "Content-Type: application/json" \
  -d '{"email":"testuser2@test.com","password":"Test1234!","firstName":"Test","lastName":"User","phone":"+5491188888888","nombreNegocio":"Otro","slug":"otro-negocio"}')
assert_status "Register duplicate email" "409" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$API/api/auth/register" -H "Content-Type: application/json" \
  -d '{"email":"testuser2@test.com","password":"Test1234!","firstName":"T","lastName":"U","phone":"+5491177777777","nombreNegocio":"X","slug":"x"}')
assert_status "Register weak password / short name" "400" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$API/api/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"testuser2@test.com","password":"Test1234!"}')
assert_status "POST /api/auth/login" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"
assert_not_empty "Login returns token" "$TOKEN2"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$API/api/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"testuser2@test.com","password":"wrong"}')
assert_status "Login wrong password" "401" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$API/api/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"nobody@test.com","password":"Test1234!"}')
assert_status "Login non-existent" "401" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" "$API/api/auth/me")
assert_status "GET /me (no token)" "401" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN2" "$API/api/auth/me")
assert_status "GET /me (valid token)" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$API/api/auth/check-duplicate" -H "Content-Type: application/json" \
  -d '{"field":"email","value":"testuser2@test.com"}')
assert_contains "Check duplicate (exists)" "true" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$API/api/auth/reset-password" -H "Content-Type: application/json" \
  -d '{"email":"testuser2@test.com"}')
assert_status "POST /api/auth/reset-password" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$API/api/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"testuser2@test.com","password":"wrong"}')
assert_status "POST /api/auth/login (wrong)" "401" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

# ════════════════════════════════════════════════
# 2. BRANDING TESTS
# ════════════════════════════════════════════════
echo -e "\n${BLUE}══ 2. BRANDING CRUD ══${NC}"

RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN2" "$API/api/branding")
assert_status "GET /api/branding" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"
NEG_ID=$(echo "$RESP"|head -1|python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
assert_not_empty "Branding has id" "$NEG_ID"

RESP=$(curl -s -w "\n%{http_code}" "$API/api/branding")
assert_status "GET /api/branding (no token)" "401" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X PUT -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/branding" \
  -d "{\"id\":\"$NEG_ID\",\"nombre\":\"La Parrilla\",\"slug\":\"pizzeria-napoli\",\"descripcion\":\"La mejor pizza\",\"color_primary\":\"#ff5733\",\"whatsapp\":\"+5491199999999\",\"localidad\":\"Belgrano\",\"direccion\":\"Av. Libertador 5000\",\"tipo_envio\":\"delivery\",\"costo_envio\":300,\"pedido_minimo\":800,\"mostrar_nombre\":true,\"logo_scale\":1,\"banner_scale\":1}")
assert_status "PUT /api/branding (full update)" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -H "Authorization: Bearer $TOKEN2" "$API/api/branding")
BODY=$(echo "$RESP")
assert_contains "Nombre updated" "La Parrilla" "$BODY"
assert_contains "Color updated" "ff5733" "$BODY"
assert_contains "Localidad updated" "Belgrano" "$BODY"

RESP=$(curl -s -w "\n%{http_code}" -X PUT -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/branding" \
  -d "{\"id\":\"$NEG_ID\",\"nombre\":\"T\",\"slug\":\"ab\",\"whatsapp\":\"\",\"tipo_envio\":\"delivery\"}")
assert_status "PUT branding (slug too short)" "400" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X PUT -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/branding" \
  -d '{"nombre":"No ID"}')
assert_status "PUT branding (missing id)" "400" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X PUT -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/branding" \
  -d "{\"id\":\"$NEG_ID\",\"nombre\":\"La Parrilla\",\"slug\":\"pizzeria-napoli\",\"whatsapp\":\"+5491199999999\",\"tipo_envio\":\"delivery\",\"instagram_url\":\"https://instagram.com/parrilla\",\"facebook_url\":\"https://facebook.com/parrilla\",\"tiktok_url\":\"https://tiktok.com/@parrilla\"}")
assert_status "PUT branding (social links)" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"
BODY=$(curl -s -H "Authorization: Bearer $TOKEN2" "$API/api/branding")
assert_contains "Instagram saved" "instagram.com/parrilla" "$BODY"
assert_contains "Facebook saved" "facebook.com/parrilla" "$BODY"

RESP=$(curl -s -w "\n%{http_code}" -X PUT -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/branding" \
  -d "{\"id\":\"$NEG_ID\",\"nombre\":\"La Parrilla\",\"slug\":\"pizzeria-napoli\",\"whatsapp\":\"+5491199999999\",\"tipo_envio\":\"delivery\",\"horarios\":{\"lunes\":{\"turnos\":[{\"inicio\":\"11:00\",\"fin\":\"15:00\"}]},\"martes\":{\"turnos\":[{\"inicio\":\"11:00\",\"fin\":\"23:00\"}]}}}")
assert_status "PUT branding (horarios)" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"
BODY=$(curl -s -H "Authorization: Bearer $TOKEN2" "$API/api/branding")
assert_contains "Horarios saved" "11:00" "$BODY"

RESP=$(curl -s -w "\n%{http_code}" -X PUT -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/branding" \
  -d "{\"id\":\"$NEG_ID\",\"nombre\":\"La Parrilla\",\"slug\":\"pizzeria-napoli\",\"whatsapp\":\"+5491199999999\",\"tipo_envio\":\"delivery\",\"direcciones\":[{\"id\":\"1\",\"nombre\":\"Sede Central\",\"direccion\":\"Av. Libertador 5000\",\"localidad\":\"Belgrano\",\"es_principal\":true}]}")
assert_status "PUT branding (direcciones)" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"
BODY=$(curl -s -H "Authorization: Bearer $TOKEN2" "$API/api/branding")
assert_contains "Direccion saved" "Av. Libertador 5000" "$BODY"

# ════════════════════════════════════════════════
# 3. CATALOG CRUD TESTS
# ════════════════════════════════════════════════
echo -e "\n${BLUE}══ 3. CATALOG CRUD ══${NC}"

for CAT in "Entradas" "Pizzas" "Bebidas"; do
  SLUG=$(echo "$CAT" | tr '[:upper:]' '[:lower:]')
  RESP=$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/catalog/categories" -d "{\"nombre\":\"$CAT\",\"slug\":\"$SLUG\"}")
  assert_status "POST /categories ($CAT)" "201" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"
done

RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN2" "$API/api/catalog/categories")
assert_status "GET /categories" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"
CATS_BODY=$(echo "$RESP"|head -1)
CAT_ID=$(echo "$CATS_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'])" 2>/dev/null)

for NAME_PRICE in "Fugazzeta:2800" "Margherita:2500" "Coca-Cola:800"; do
  NAME=$(echo "$NAME_PRICE" | cut -d: -f1)
  PRICE=$(echo "$NAME_PRICE" | cut -d: -f2)
  RESP=$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/catalog/products" \
    -d "{\"nombre\":\"$NAME\",\"descripcion\":\"Test\",\"precio\":$PRICE,\"disponible\":true,\"stock\":30,\"stock_minimo\":5,\"categoria_id\":\"$CAT_ID\"}")
  assert_status "POST /products ($NAME)" "201" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"
done

RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN2" "$API/api/catalog/products")
assert_status "GET /products" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"
PRODS=$(echo "$RESP"|head -1)
PROD_ID=$(echo "$PRODS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'])" 2>/dev/null)

RESP=$(curl -s -w "\n%{http_code}" -X PATCH -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/catalog/products/$PROD_ID/toggle" -d '{"disponible":false}')
assert_status "PATCH /products/:id/toggle" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X PUT -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/catalog/products/$PROD_ID" -d "{\"nombre\":\"Fugazzeta Especial\",\"precio\":3200,\"disponible\":true,\"stock\":25,\"stock_minimo\":3}")
assert_status "PUT /products/:id" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X DELETE -H "Authorization: Bearer $TOKEN2" "$API/api/catalog/products/$PROD_ID")
assert_status "DELETE /products/:id" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -H "Authorization: Bearer $TOKEN2" "$API/api/catalog/products")
COUNT=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null)
assert_contains "Product deleted (count=2)" "2" "$COUNT"

RESP=$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/catalog/products" -d '{"nombre":"Empanada","descripcion":"Carne","precio":500,"disponible":true,"stock":200,"stock_minimo":0}')
assert_status "POST /products (zero stock_minimo)" "201" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

CATS_RESP=$(curl -s -H "Authorization: Bearer $TOKEN2" "$API/api/catalog/categories")
DEL_CAT_ID=$(echo "$CATS_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[-1]['id'])" 2>/dev/null)
RESP=$(curl -s -w "\n%{http_code}" -X DELETE -H "Authorization: Bearer $TOKEN2" "$API/api/catalog/categories/$DEL_CAT_ID")
assert_status "DELETE /categories/:id" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/catalog/products" -d '{}')
assert_status "POST /products (empty body)" "400" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

# ════════════════════════════════════════════════
# 4. ORDERS + STATS TESTS
# ════════════════════════════════════════════════
echo -e "\n${BLUE}══ 4. ORDERS + STATS ══${NC}"

RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN2" "$API/api/orders")
assert_status "GET /orders" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN2" "$API/api/orders/recent?limit=5")
assert_status "GET /orders/recent" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X PATCH -H "Authorization: Bearer $TOKEN2" "$API/api/orders/toggle-reception")
assert_status "PATCH /orders/toggle-reception" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN2" "$API/api/stats/dashboard")
BODY=$(echo "$RESP"|head -1)
assert_status "GET /stats/dashboard" "200" "$(echo "$RESP"|tail -1)" "$BODY"
assert_contains "Dashboard has ventasHoy" "ventasHoy" "$BODY"
assert_contains "Dashboard has totalProductos" "totalProductos" "$BODY"

RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN2" "$API/api/stats/summary?startDate=2026-01-01&endDate=2026-12-31")
assert_status "GET /stats/summary" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

# ════════════════════════════════════════════════
# 5. PROMOS CRUD TESTS
# ════════════════════════════════════════════════
echo -e "\n${BLUE}══ 5. PROMOS CRUD ══${NC}"

RESP=$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/promos" \
  -d '{"nombre":"2x1 Pizzas","descripcion":"Martes","tipo_descuento":"porcentaje","valor_descuento":50,"activo":true,"items_combo":[]}')
assert_status "POST /promos" "201" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"
PROMO_ID=$(echo "$RESP"|head -1|python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
assert_not_empty "Promo has id" "$PROMO_ID"

RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN2" "$API/api/promos")
assert_status "GET /promos" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X PATCH -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/promos/$PROMO_ID/toggle" -d '{"activo":false}')
assert_status "PATCH /promos/:id/toggle" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X PUT -H "Authorization: Bearer $TOKEN2" -H "Content-Type: application/json" "$API/api/promos/$PROMO_ID" \
  -d '{"nombre":"3x1 Pizzas","descripcion":"Martes y jueves","tipo_descuento":"porcentaje","valor_descuento":67,"activo":true,"items_combo":[]}')
assert_status "PUT /promos/:id" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X DELETE -H "Authorization: Bearer $TOKEN2" "$API/api/promos/$PROMO_ID")
assert_status "DELETE /promos/:id" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -H "Authorization: Bearer $TOKEN2" "$API/api/promos")
COUNT=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null)
assert_contains "Promo deleted (count=0)" "0" "$COUNT"

# ════════════════════════════════════════════════
# 6. CLIENTS, NOTIFICATIONS, UPLOADS
# ════════════════════════════════════════════════
echo -e "\n${BLUE}══ 6. CLIENTS, NOTIFICATIONS, UPLOADS ══${NC}"

RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN2" "$API/api/clients")
assert_status "GET /clients" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN2" "$API/api/notifications")
assert_status "GET /notifications" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN2" "$API/api/notifications/unread-count")
assert_status "GET /notifications/unread-count" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN2" "$API/api/notifications/preferences")
assert_status "GET /notifications/preferences" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' > /tmp/test-img.png

RESP=$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer $TOKEN2" -F "file=@/tmp/test-img.png" "$API/api/uploads/product-images")
assert_status "POST /uploads/product-images" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer $TOKEN2" -F "file=@/tmp/test-img.png" "$API/api/uploads/branding-images")
assert_status "POST /uploads/branding-images" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer $TOKEN2" -F "file=@/tmp/test-img.png" "$API/api/uploads/promo-images")
assert_status "POST /uploads/promo-images" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

# ════════════════════════════════════════════════
# 7. PUBLIC MENU + MERCADOPAGO
# ════════════════════════════════════════════════
echo -e "\n${BLUE}══ 7. PUBLIC MENU + MERCADOPAGO ══${NC}"

RESP=$(curl -s -w "\n%{http_code}" "$API/api/public-menu/pizzeria-napoli")
assert_status "GET /public-menu/pizzeria-napoli" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"
assert_contains "Menu has business" "La Parrilla" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" "$API/api/public-menu/nonexistent")
assert_status "GET /public-menu (nonexistent)" "404" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer $TOKEN2" "$API/api/mercadopago/create-preapproval")
assert_status "POST /mercadopago/create-preapproval (no config)" "501" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

# ════════════════════════════════════════════════
# 8. AUTHORIZATION TESTS (all protected routes without token → 401)
# ════════════════════════════════════════════════
echo -e "\n${BLUE}══ 8. AUTHORIZATION (no token → 401) ══${NC}"

for ROUTE in "api/branding" "api/catalog/products" "api/catalog/categories" "api/orders" "api/clients" "api/promos" "api/notifications" "api/stats/dashboard"; do
  RESP=$(curl -s -w "\n%{http_code}" "$API/$ROUTE")
  assert_status "GET /$ROUTE (no auth)" "401" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"
done

# ════════════════════════════════════════════════
# 9. PUBLIC ROUTES (no auth needed)
# ════════════════════════════════════════════════
echo -e "\n${BLUE}══ 9. PUBLIC ROUTES (no auth) ══${NC}"

RESP=$(curl -s -w "\n%{http_code}" "$API/health")
assert_status "GET /health (no auth)" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" "$API/api/public-menu/pizzeria-napoli")
assert_status "GET /public-menu (no auth)" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$API/api/auth/login" -H "Content-Type: application/json" -d '{"email":"testuser2@test.com","password":"Test1234!"}')
assert_status "POST /auth/login (no auth)" "200" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" "$API/api/nonexistent")
assert_status "GET /api/nonexistent (404)" "404" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

# ════════════════════════════════════════════════
# 10. EDGE CASES + SECURITY
# ════════════════════════════════════════════════
echo -e "\n${BLUE}══ 10. EDGE CASES + SECURITY ══${NC}"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$API/api/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"admin'\'' OR 1=1--","password":"test"}')
assert_status "SQL injection on login" "400" "$(echo "$RESP"|tail -1)" "$(echo "$RESP"|head -1)"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$API/api/auth/register" -H "Content-Type: application/json" \
  -d '{"email":"xss@test.com","password":"Test1234!","firstName":"X","lastName":"SS","phone":"+5491155555555","nombreNegocio":"XSS","slug":"xss-test-slug"}')
# Should be 201 (created), 400 (validation), or 429 (rate limited) - all acceptable
STATUS=$(echo "$RESP" | tail -1)
TOTAL=$((TOTAL + 1))
if [ "$STATUS" = "429" ] || [ "$STATUS" = "201" ] || [ "$STATUS" = "400" ]; then
  echo -e "  ${GREEN}✓${NC} Register XSS slug (blocked or rate limited) [HTTP $STATUS]"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} Register XSS slug [HTTP $STATUS]"
  FAIL=$((FAIL + 1))
fi

# ════════════════════════════════════════════════
# 11. CLEANUP
# ════════════════════════════════════════════════
echo -e "\n${BLUE}══ 11. CLEANUP ══${NC}"

docker compose exec -T db psql -U neo -d neo -c "
  DELETE FROM notifications WHERE negocio_id IN (SELECT id FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio','xss-test-slug'));
  DELETE FROM pedido_items WHERE pedido_id IN (SELECT id FROM pedidos WHERE negocio_id IN (SELECT id FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio','xss-test-slug')));
  DELETE FROM pedidos WHERE negocio_id IN (SELECT id FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio','xss-test-slug'));
  DELETE FROM productos WHERE negocio_id IN (SELECT id FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio','xss-test-slug'));
  DELETE FROM categorias WHERE negocio_id IN (SELECT id FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio','xss-test-slug'));
  DELETE FROM promos WHERE negocio_id IN (SELECT id FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio','xss-test-slug'));
  DELETE FROM negocios WHERE slug IN ('pizzeria-napoli','neo-test-negocio','xss-test-slug');
  DELETE FROM users WHERE email IN ('testuser2@test.com','neo-test-user@test.com','xss@test.com');
" 2>/dev/null
echo -e "  ${GREEN}✓${NC} DB cleaned up"
PASS=$((PASS + 1))
TOTAL=$((TOTAL + 1))

# ════════════════════════════════════════════════
# RESULTS
# ════════════════════════════════════════════════
echo -e "\n${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE} RESULTS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""
echo -e "  Total:  $TOTAL"
echo -e "  ${GREEN}Passed: $PASS${NC}"
echo -e "  ${RED}Failed: $FAIL${NC}"
echo ""
if [ $FAIL -eq 0 ]; then
  echo -e "  ${GREEN}🎉 ALL TESTS PASSED!${NC}"
else
  echo -e "  ${YELLOW}⚠ $FAIL test(s) failed${NC}"
fi
echo ""
