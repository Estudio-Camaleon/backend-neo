#!/bin/bash
# Fix orphan parrilla products + simulate a full day of orders
source /tmp/token.env
API="https://localhost"
PARRILLA_ID="99dfe30e-fb8c-4263-893a-a814b27627ac"

echo "── Asignando categoría Parrilla ──"
fix_product() {
    curl -sk --max-time 8 -X PUT "$API/api/catalog/products/$1" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"nombre\":\"$2\",\"precio\":$3,\"categoria_id\":\"$PARRILLA_ID\",\"disponible\":true,\"stock\":50}" 2>/dev/null | grep -q '"id"' && echo "  ✓ $2 → Parrilla"
}
fix_product "faaff699-3581-47a5-9ae2-56818cbbde5c" "Asado de Tira" 7200 &
fix_product "09acefe7-0073-4a04-ac19-f032a9557fd9" "Bife de Chorizo" 8500 &
fix_product "ed51eab8-b0a7-4c9b-a495-6084de81a0eb" "Chorizo Criollo" 2400 &
fix_product "9aa379c6-ece0-4e4a-927d-80e8ae6ea3b8" "Morcilla" 2200 &
fix_product "1149009d-3bbd-4961-9586-24c935e862e8" "Pollo a la Brasa" 5200 &
wait

# Vacío might not exist - check and create if needed
VACIO=$(curl -sk --max-time 8 -H "Authorization: Bearer $TOKEN" "$API/api/catalog/products" 2>/dev/null | grep -o '"id":"[^"]*","negocio_id":"[^"]*","categoria_id":"[^"]*","nombre":"Vacío"' | grep -o '^"id":"[^"]*' | cut -d'"' -f4)
if [ -z "$VACIO" ]; then
    echo "  + Creando Vacío..."
    curl -sk --max-time 8 -X POST "$API/api/catalog/products" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"nombre\":\"Vacío\",\"descripcion\":\"Vacío 450g con sus jugos naturales\",\"precio\":7800,\"categoria_id\":\"$PARRILLA_ID\",\"disponible\":true,\"stock\":50}" 2>/dev/null | grep -q '"id"' && echo "  ✓ Vacío creado → Parrilla"
fi

# ── Get product IDs for orders ──
echo ""
echo "── Obteniendo IDs de productos ──"
curl -sk --max-time 8 -H "Authorization: Bearer $TOKEN" "$API/api/catalog/products" 2>/dev/null > products_temp.json
python3 -c "
import json
products = json.load(open('products_temp.json'))
for p in products:
    print(p['id'], p['precio'], p['nombre'].replace(' ', '_'))
" > product_ids.txt
rm -f products_temp.json
wc -l < /tmp/product_ids.txt | xargs echo "Productos totales:"

# ── Simulate a full day of orders ──
echo ""
echo "── Simulando un día completo de pedidos ──"

CLIENTES=("Juan Perez" "Maria Gomez" "Carlos Lopez" "Ana Martinez" "Luis Rodriguez" "Sofia Fernandez" "Diego Torres" "Valeria Sanchez" "Martin Alvarez" "Lucia Romero")
WHATSAPPS=("+5491155550001" "+5491155550002" "+5491155550003" "+5491155550004" "+5491155550005" "+5491155550006" "+5491155550007" "+5491155550008" "+5491155550009" "+5491155550010")

crear_pedido() {
    local cliente_idx=$1 prod_id=$2 cantidad=$3 es_delivery=$4 metodo=$5 estado=$6 notas="$7"
    local nombre="${CLIENTES[$((cliente_idx % 10))]}"
    local wapp="${WHATSAPPS[$((cliente_idx % 10))]}"
    local dir=""
    [ "$es_delivery" = "true" ] && dir="Av. Siempre Viva $((RANDOM % 500 + 100)), CABA"

    curl -sk --max-time 8 -X POST "$API/api/orders/public/submit" \
        -H "Content-Type: application/json" \
        -d "{
            \"negocio_id\": \"$NEGOCIO_ID\",
            \"cliente_nombre\": \"$nombre\",
            \"cliente_whatsapp\": \"$wapp\",
            \"es_delivery\": $es_delivery,
            \"direccion_entrega\": \"$dir\",
            \"metodo_pago\": \"$metodo\",
            \"notas\": \"$notas\",
            \"items\": [{\"producto_id\": \"$prod_id\", \"cantidad\": $cantidad}]
        }" 2>/dev/null | grep -q '"pedidoId"' && return 0
    return 1
}

TOTAL=0
i=0
while IFS=' ' read -r pid precio nombre; do
    i=$((i+1))
    # Skip some products randomly to make it realistic (not every product sells)
    if [ $((RANDOM % 3)) -eq 0 ]; then continue; fi

    # Random quantity 1-3
    CANT=$((RANDOM % 3 + 1))
    # 70% delivery, 30% takeaway
    DELIVERY="false"; [ $((RANDOM % 10)) -lt 7 ] && DELIVERY="true"
    # Random payment method
    METODO="efectivo"; [ $((RANDOM % 2)) -eq 0 ] && METODO="transferencia"

    CLIENTE_IDX=$((i % 10))
    NOTAS="Sin notas"
    [ $((RANDOM % 5)) -eq 0 ] && NOTAS="Sin cebolla, por favor"
    [ $((RANDOM % 7)) -eq 0 ] && NOTAS="Toc timbre 2B"

    if crear_pedido $CLIENTE_IDX "$pid" $CANT "$DELIVERY" "$METODO" "pendiente" "$NOTAS"; then
        TOTAL=$((TOTAL+1))
        echo "  ✓ Pedido #$TOTAL: ${nombre//_/ } x$CANT ($METODO, delivery=$DELIVERY)"
    fi
done < product_ids.txt
rm -f product_ids.txt

echo ""
echo "✅ Día simulado: $TOTAL pedidos creados"

# ── Verify dashboard ──
echo ""
echo "── Dashboard final ──"
curl -sk --max-time 8 -H "Authorization: Bearer $TOKEN" "$API/api/stats/dashboard" 2>/dev/null | head -c 300
