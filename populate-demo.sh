#!/bin/bash
# Populate demo business: branding, categories, products, orders
set -e

API="https://localhost"
source /tmp/token.env  # TOKEN, NEGOCIO_ID

echo "══ Populando Mi Restaurante Demo ══"

# ── 1. Branding: banner + logo ──
echo ""
echo "── 1. Subiendo imágenes de branding ──"

BANNER=$(curl -sk -X POST "$API/api/uploads/branding-images" \
    -H "Authorization: Bearer $TOKEN" \
    -F "file=@frontend/public/images/portadas/FullcaptureDashboard.png;type=image/png" \
    -F "field=banner_url" 2>/dev/null)
BANNER_URL=$(echo "$BANNER" | grep -o '"publicUrl":"[^"]*"' | cut -d'"' -f4)
echo "  Banner: $BANNER_URL"

LOGO=$(curl -sk -X POST "$API/api/uploads/branding-images" \
    -H "Authorization: Bearer $TOKEN" \
    -F "file=@frontend/public/icons/neo_logo_negro.webp;type=image/webp" \
    -F "field=logo_url" 2>/dev/null)
LOGO_URL=$(echo "$LOGO" | grep -o '"publicUrl":"[^"]*"' | cut -d'"' -f4)
echo "  Logo: $LOGO_URL"

# Update branding with URLs + description + colors
curl -sk -X PUT "$API/api/branding" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"id\": \"$NEGOCIO_ID\",
        \"nombre\": \"Mi Restaurante Demo\",
        \"slug\": \"mi-restaurante-demo\",
        \"descripcion\": \"La mejor parrilla argentina. Cortes premium, pastas caseras y el ambiente que buscás.\",
        \"banner_url\": \"$BANNER_URL\",
        \"logo_url\": \"$LOGO_URL\",
        \"color_primary\": \"#e05e33\",
        \"instagram_url\": \"https://instagram.com/mirestaurantdemo\",
        \"facebook_url\": \"https://facebook.com/mirestaurantdemo\",
        \"costo_envio\": 800,
        \"pedido_minimo\": 2500,
        \"tipo_envio\": \"delivery_takeaway\"
    }" 2>/dev/null | grep -q '"id"' && echo "  ✓ Branding actualizado"

# ── 2. Categories ──
echo ""
echo "── 2. Creando categorías ──"
declare -A CAT_IDS
for CAT in "Entradas:entradas" "Parrilla:parrilla" "Pastas:pastas" "Postres:postres" "Bebidas:bebidas"; do
    NOMBRE="${CAT%%:*}"
    SLUG="${CAT##*:}"
    RESP=$(curl -sk -X POST "$API/api/catalog/categories" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"nombre\":\"$NOMBRE\",\"slug\":\"$SLUG\"}" 2>/dev/null)
    ID=$(echo "$RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    CAT_IDS[$NOMBRE]=$ID
    echo "  ✓ $NOMBRE ($ID)"
done

# ── 3. Products (20) ──
echo ""
echo "── 3. Creando productos ──"

crear_producto() {
    local cat="$1" nombre="$2" desc="$3" precio="$4"
    curl -sk -X POST "$API/api/catalog/products" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"nombre\": \"$nombre\",
            \"descripcion\": \"$desc\",
            \"precio\": $precio,
            \"categoria_id\": \"${CAT_IDS[$cat]}\",
            \"disponible\": true,
            \"stock\": 50,
            \"stock_minimo\": 5
        }" 2>/dev/null | grep -q '"id"' && echo "  ✓ $nombre (\$$precio)"
}

# Entradas (4)
crear_producto "Entradas" "Empanada de Carne" "Empanada criolla de carne cortada a cuchillo" 900
crear_producto "Entradas" "Provolone a la Parrilla" "Queso provolone con orégano y aceite de oliva" 3200
crear_producto "Entradas" "Papas Fritas" "Porción abundante de papas fritas crocantes" 2200
crear_producto "Entradas" "Matambre a la Pizza" "Matambre tierno con salsa, muzzarella y aceitunas" 4800

# Parrilla (6)
crear_producto "Parrilla" "Bife de Chorizo" "Corte premium 400g jugoso a la parrilla" 8500
crear_producto "Parrilla" "Asado de Tira" "Tira de asado 500g al asador" 7200
crear_producto "Parrilla" "Vacío" "Vacío 450g con sus jugos naturales" 7800
crear_producto "Parrilla" "Chorizo Criollo" "Par de chorizos caseros" 2400
crear_producto "Parrilla" "Morcilla" "Par de morcillas ahumadas" 2200
crear_producto "Parrilla" "Pollo a la Brasa" "Medio pollo marinado con limón y hierbas" 5200

# Pastas (4)
crear_producto "Pastas" "Ravioles de Ricotta" "Ravioles caseros con salsa fileto o bolognesa" 5600
crear_producto "Pastas" "Ñoquis Sorrentinos" "Sorrentinos de jamón y queso con salsa mixta" 5800
crear_producto "Pastas" "Fettuccine Alfredo" "Fettuccine fresco con crema y parmesano" 5400
crear_producto "Pastas" "Lasagna de la Casa" "Lasagna de carne con bechamel gratinada" 6400

# Postres (3)
crear_producto "Postres" "Flan Casero" "Flan con dulce de leche o crema" 1800
crear_producto "Postres" "Cheesecake" "Cheesecake con coulis de frutos rojos" 2800
crear_producto "Postres" "Helado Artesanal" "Tres bochas a elección con crema chantilly" 2400

# Bebidas (3)
crear_producto "Bebidas" "Coca-Cola 500ml" "Gaseosa en botella" 1200
crear_producto "Bebidas" "Vino Malbec (botella)" "Malbec reserva 750ml" 6500
crear_producto "Bebidas" "Cerveza Artesanal IPA" "Pinta de IPA local 500ml" 2600

echo ""
echo "✅ 20 productos cargados"