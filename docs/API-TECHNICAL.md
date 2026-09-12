# NEO Backend - Documentación Técnica

## 1. Visión General

**NEO Backend** es una API REST multi-tenant para gestión de negocios de comida/restaurantes. Permite a los dueños administrar catálogos de productos, pedidos, promociones, clientes y branding, con integración a MercadoPago para pagos por suscripción.

### Arquitectura

- **Runtime**: Node.js 20 (Alpine)
- **Framework**: Express 4.21
- **Lenguaje**: TypeScript 5.6 (strict mode)
- **Base de Datos**: PostgreSQL 15+ (via `pg` driver)
- **Auth**: JWT (Bearer tokens, expiración 7d)
- **Validación**: Zod schemas
- **Pagos**: MercadoPago SDK v3 (suscripciones pre-aprobadas)

### Multi-Tenancy

El sistema es **multi-tenant por diseño**. Cada `negocio` es un tenant aislado. Todas las queries administrativas filtran por `negocio_id` extraído del token JWT vía middleware `resolveTenant`.

---

## 2. Estructura del Proyecto

```
backend-neo/
├── db/
│   └── init/
│       └── 01-schema.sql          # Schema PostgreSQL completo
├── src/
│   ├── index.ts                   # Entry point Express
│   ├── middleware/
│   │   ├── auth.ts                # JWT auth + requireAuth middleware
│   │   └── tenant.ts              # resolveTenant middleware
│   ├── lib/
│   │   ├── db.ts                  # Pool PostgreSQL + query helper
│   │   ├── schemas.ts             # Zod validation schemas
│   │   ├── rate-limit.ts          # Rate limiting (DB + in-memory fallback)
│   │   ├── audit.ts               # Audit logging
│   │   └── mercadopago.ts         # MP webhook signature verification
│   └── routes/
│       ├── auth.ts                # Login, register, reset-password, me
│       ├── catalog.ts             # CRUD productos y categorías
│       ├── orders.ts              # Pedidos (admin + público)
│       ├── branding.ts            # Configuración del negocio
│       ├── clients.ts             # Gestión de clientes
│       ├── promos.ts              # Promociones y descuentos
│       ├── notifications.ts       # Sistema de notificaciones
│       ├── stats.ts               # Estadísticas y dashboard
│       ├── uploads.ts             # Upload de imágenes
│       ├── mercadopago.ts         # Integración MercadoPago
│       └── public-menu.ts         # Menú público (sin auth)
├── Dockerfile                     # Multi-stage build
├── package.json
└── tsconfig.json
```

---

## 3. Variables de Entorno

| Variable | Default | Descripción |
|----------|---------|-------------|
| `DATABASE_URL` | `postgres://neo:neo_secret@db:5432/neo` | URL de conexión PostgreSQL |
| `JWT_SECRET` | `neo_jwt_secret` | Secreto para firmar JWT |
| `PORT` | `4000` | Puerto del servidor |
| `CORS_ORIGIN` | `http://localhost:3000` | Origen permitido CORS |
| `MERCADO_PAGO_ACCESS_TOKEN` | _(vacío)_ | Token de acceso MP |
| `MERCADO_PAGO_WEBHOOK_SECRET` | _(vacío)_ | Secreto para verificar webhooks MP |
| `MERCADO_PAGO_BACK_URL` | `http://localhost:3000` | URL de retorno MP |
| `UPLOAD_DIR` | `./uploads` | Directorio de uploads |
| `MAX_FILE_SIZE` | `5242880` (5MB) | Tamaño máximo de archivo |

---

## 4. Base de Datos

### 4.1 Diagrama de Entidades

```
users ──────────────────┐
  │                     │
  │ (user_id)           │ (user_id)
  ▼                     ▼
negocios ──────────► team_members
  │
  ├── categorias ──► productos
  ├── clientes
  ├── pedidos ──► pedido_items
  ├── promos
  ├── notifications
  ├── notification_preferences
  ├── audit_logs
  └── rate_limits
```

### 4.2 Tablas Principales

#### `users`
| Campo | Tipo | Constraints |
|-------|------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() |
| email | TEXT | UNIQUE NOT NULL |
| password_hash | TEXT | NOT NULL |
| first_name | TEXT | |
| last_name | TEXT | |
| phone | TEXT | |
| email_confirmed | BOOLEAN | DEFAULT false |
| created_at | TIMESTAMPTZ | DEFAULT now() |
| updated_at | TIMESTAMPTZ | DEFAULT now() |

#### `negocios` (Tenant principal)
| Campo | Tipo | Constraints |
|-------|------|-------------|
| id | UUID | PK |
| user_id | UUID | FK → users(id) ON DELETE SET NULL |
| nombre | TEXT | NOT NULL |
| slug | TEXT | UNIQUE NOT NULL |
| phone | TEXT | |
| descripcion | TEXT | |
| direccion | TEXT | |
| localidad | TEXT | |
| direcciones | JSONB | DEFAULT '[]' |
| horarios | JSONB | |
| whatsapp | TEXT | |
| whatsapp_mensajes | JSONB | |
| color_primary | TEXT | |
| logo_url | TEXT | |
| logo_scale | NUMERIC(5,2) | DEFAULT 1 |
| logo_posicion | TEXT | DEFAULT 'centro' |
| logo_fit | TEXT | DEFAULT 'cover' |
| logo_shape | TEXT | DEFAULT 'rectangulo' |
| banner_url | TEXT | |
| banner_posicion | TEXT | DEFAULT 'centro' |
| banner_height | TEXT | DEFAULT '200px' |
| banner_scale | NUMERIC(5,2) | DEFAULT 1 |
| mostrar_nombre | BOOLEAN | DEFAULT true |
| instagram_url | TEXT | |
| facebook_url | TEXT | |
| tiktok_url | TEXT | |
| twitter_url | TEXT | |
| youtube_url | TEXT | |
| tripadvisor_url | TEXT | |
| tipo_envio | TEXT | DEFAULT 'delivery' |
| moneda_simbolo | TEXT | DEFAULT '$' |
| pedido_minimo | NUMERIC(10,2) | DEFAULT 0 |
| costo_envio | NUMERIC(10,2) | DEFAULT 0 |
| recepcion_pausada | BOOLEAN | DEFAULT false |
| plan_tier | TEXT | DEFAULT 'free' |
| subscription_status | TEXT | |
| mp_subscription_id | TEXT | |
| mp_customer_id | TEXT | |
| mp_status | TEXT | |
| current_period_ends_at | TIMESTAMPTZ | |
| created_at | TIMESTAMPTZ | DEFAULT now() |
| updated_at | TIMESTAMPTZ | DEFAULT now() |

**Índices**: `user_id`, `slug`, `mp_subscription_id`, `mp_customer_id`

#### `productos`
| Campo | Tipo | Constraints |
|-------|------|-------------|
| id | UUID | PK |
| negocio_id | UUID | FK → negocios, ON DELETE CASCADE |
| categoria_id | UUID | FK → categorias, ON DELETE SET NULL |
| nombre | TEXT | NOT NULL |
| descripcion | TEXT | |
| precio | NUMERIC(10,2) | DEFAULT 0 |
| imagen_url | TEXT | |
| disponible | BOOLEAN | DEFAULT true |
| stock | INTEGER | DEFAULT 0 |
| stock_minimo | INTEGER | DEFAULT 5 |
| configuracion | JSONB | (variantes, grupos_opciones, imagenes_extra) |
| created_at | TIMESTAMPTZ | DEFAULT now() |

#### `pedidos`
| Campo | Tipo | Constraints |
|-------|------|-------------|
| id | UUID | PK |
| negocio_id | UUID | FK → negocios, ON DELETE CASCADE |
| cliente_id | UUID | FK → clientes, ON DELETE SET NULL |
| cliente_nombre | TEXT | |
| cliente_whatsapp | TEXT | |
| estado | estado_pedido | DEFAULT 'pendiente' |
| total | NUMERIC(10,2) | DEFAULT 0 |
| es_delivery | BOOLEAN | DEFAULT false |
| direccion_entrega | TEXT | |
| metodo_pago | TEXT | |
| notas | TEXT | |
| created_at | TIMESTAMPTZ | DEFAULT now() |

**Enum `estado_pedido`**: `pendiente`, `en_preparacion`, `entregado`, `cancelado`

#### `pedido_items`
| Campo | Tipo | Constraints |
|-------|------|-------------|
| id | UUID | PK |
| pedido_id | UUID | FK → pedidos, ON DELETE CASCADE |
| producto_id | UUID | FK → productos, ON DELETE SET NULL |
| nombre_producto | TEXT | NOT NULL |
| cantidad | INTEGER | NOT NULL |
| precio_unitario | NUMERIC(10,2) | NOT NULL |
| detalles | TEXT | |

#### `promos`
| Campo | Tipo | Constraints |
|-------|------|-------------|
| id | UUID | PK |
| negocio_id | UUID | FK → negocios, ON DELETE CASCADE |
| nombre | TEXT | NOT NULL |
| descripcion | TEXT | |
| imagen_url | TEXT | |
| tipo_descuento | TEXT | NOT NULL (porcentaje/monto_fijo/combo) |
| valor_descuento | NUMERIC(10,2) | NOT NULL |
| codigo | TEXT | |
| activo | BOOLEAN | DEFAULT true |
| items_combo | JSONB | DEFAULT '[]' |
| aplicar_a | JSONB | (productos, categorías) |
| fecha_inicio | TIMESTAMPTZ | |
| fecha_fin | TIMESTAMPTZ | |
| created_at | TIMESTAMPTZ | DEFAULT now() |
| updated_at | TIMESTAMPTZ | DEFAULT now() |

### 4.3 Funciones PostgreSQL

#### `submit_order_atomic()`
Función atómica para crear pedidos. Valida disponibilidad, upsert de cliente, crea el pedido y sus items, calcula el total.

**Parámetros**:
- `p_negocio_id UUID`
- `p_cliente_nombre TEXT`
- `p_cliente_whatsapp TEXT`
- `p_es_delivery BOOLEAN`
- `p_direccion_entrega TEXT`
- `p_metodo_pago TEXT`
- `p_notas TEXT`
- `p_items JSONB` — Array de `{producto_id, cantidad, detalles}`

**Retorna**: UUID del pedido creado.

#### `eliminar_negocio_completo(p_negocio_id UUID)`
Eliminación en cascada de todos los datos de un negocio.

### 4.4 Vista

#### `view_resumen_clientes`
Resumen de pedidos por cliente (nombre, total pedidos, total gastado).

---

## 5. Endpoints API

### 5.1 Health Check

```
GET /health
```
**Response**: `{ status: "ok", timestamp: "ISO string" }`

---

### 5.2 Auth (`/api/auth`)

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| POST | `/login` | No | Login con email/password |
| POST | `/register` | No | Registro de usuario + negocio |
| POST | `/check-duplicate` | No | Verificar duplicados (email, slug, nombre) |
| POST | `/reset-password` | No | Solicitud de reset (stub) |
| GET | `/me` | Bearer | Obtener perfil del usuario autenticado |

#### POST `/api/auth/login`
**Request**:
```json
{
  "email": "user@example.com",
  "password": "Password1!"
}
```
**Response 200**:
```json
{
  "token": "eyJhbG...",
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "firstName": "Juan",
    "lastName": "Pérez"
  }
}
```
**Rate Limit**: 10 intentos/min por IP.

#### POST `/api/auth/register`
**Request**:
```json
{
  "email": "user@example.com",
  "password": "Password1!",
  "firstName": "Juan",
  "lastName": "Pérez",
  "phone": "+5491155551234",
  "nombreNegocio": "Mi Restaurante",
  "slug": "mi-restaurante",
  "whatsapp": "+5491155551234",
  "referralSource": "instagram"
}
```
**Validaciones**:
- Password: min 8 chars, 1 mayúscula, 1 número, 1 símbolo
- Slug: solo minúsculas, números y guiones
- Phone: formato internacional (+código + número)

**Rate Limit**: 20 intentos/min por IP.

#### POST `/api/auth/check-duplicate`
**Request**: `{ "field": "email|nombre|slug", "value": "..." }`
**Response**: `{ "exists": boolean }`

---

### 5.3 Catálogo (`/api/catalog`) — Auth + Tenant

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/products` | Listar productos del negocio |
| GET | `/products/:id` | Obtener producto por ID |
| POST | `/products` | Crear producto |
| PUT | `/products/:id` | Actualizar producto |
| PATCH | `/products/:id/toggle` | Toggle disponibilidad |
| DELETE | `/products/:id` | Eliminar producto |
| GET | `/categories` | Listar categorías |
| POST | `/categories` | Crear categoría |
| DELETE | `/categories/:id` | Eliminar categoría |

**Límites por plan**:
- Free: 50 productos, 15 categorías
- Pro: 9999 productos, 999 categorías

**Schema producto** (`upsertProductSchema`):
```typescript
{
  nombre: string,           // required, max 200
  descripcion?: string | null,
  precio: number,           // min 0
  imagen_url?: string | null,
  categoria_id?: string | null,
  disponible: boolean,
  stock: number,            // default 0
  stock_minimo: number,     // default 5
  configuracion?: {
    variantes: Array<{nombre, precio}>,
    grupos_opciones: Array<{
      id, titulo, requerido, multiple,
      items: Array<{id, nombre, precio, icono?}>
    }>,
    imagenes_extra: string[]
  }
}
```

---

### 5.4 Pedidos (`/api/orders`)

#### Admin (Auth + Tenant)
| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/recent?limit=10` | Pedidos recientes (max 50) |
| GET | `/` | Pedidos con filtros (startDate, endDate, status) |
| PATCH | `/:id/status` | Cambiar estado del pedido |
| PATCH | `/toggle-reception` | Pausar/reanudar recepción de pedidos |

#### Público (sin auth)
| Método | Ruta | Descripción |
|--------|------|-------------|
| POST | `/public/submit` | Crear pedido público |
| GET | `/public/menu/:slug` | Menú del negocio por slug |

#### POST `/api/orders/public/submit`
**Request**:
```json
{
  "negocio_id": "uuid",
  "cliente_nombre": "Juan Pérez",
  "cliente_whatsapp": "+5491155551234",
  "es_delivery": true,
  "direccion_entrega": "Av. Corrientes 1234",
  "metodo_pago": "efectivo",
  "notas": "Sin cebolla",
  "items": [
    {
      "producto_id": "uuid",
      "cantidad": 2,
      "detalles": "Extra queso"
    }
  ]
}
```
**Validaciones de negocio**:
- El negocio debe existir
- `recepcion_pausada` debe ser `false`
- Los productos deben existir, estar disponibles y pertenecer al negocio

**Response 201**: `{ "pedidoId": "uuid" }`

---

### 5.5 Branding (`/api/branding`) — Auth

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/` | Obtener configuración del negocio |
| PUT | `/` | Actualizar branding/configuración |
| DELETE | `/` | Eliminar negocio completo |

**PUT `/api/branding/`** — Campos actualizables:
- `nombre`, `slug`, `whatsapp`, `descripcion`
- `direccion`, `localidad`, `direccion_notas`, `direcciones` (JSONB)
- `color_primary`, `logo_url`, `logo_scale`, `logo_posicion`, `logo_fit`, `logo_shape`
- `banner_url`, `banner_posicion`, `banner_height`, `banner_scale`
- `mostrar_nombre`
- Redes sociales: `instagram_url`, `facebook_url`, `tiktok_url`, `twitter_url`, `youtube_url`
- `horarios` (JSONB), `whatsapp_mensajes` (JSONB)
- `tipo_envio`, `costo_envio`, `pedido_minimo`, `moneda_simbolo`

**Slug auto-generado**: Se normaliza (sin tildes, lowercase, guiones).

---

### 5.6 Clientes (`/api/clients`) — Auth + Tenant

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/` | Listar clientes |
| PUT | `/:id/notes` | Actualizar notas del cliente |
| DELETE | `/:id` | Eliminar cliente |

---

### 5.7 Promos (`/api/promos`) — Auth + Tenant

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/` | Listar promos |
| GET | `/products` | Productos y categorías disponibles |
| POST | `/` | Crear promo |
| PUT | `/:id` | Actualizar promo |
| PATCH | `/:id/toggle` | Activar/desactivar promo |
| DELETE | `/:id` | Eliminar promo |

**Tipos de descuento**:
- `porcentaje` — Descuento porcentual
- `monto_fijo` — Descuento en monto fijo
- `combo` — Combo con items específicos

**Schema promo** (`upsertPromoSchema`):
```typescript
{
  nombre: string,              // required, max 100
  descripcion?: string | null,
  imagen_url?: string | null,
  tipo_descuento: "porcentaje" | "monto_fijo" | "combo",
  valor_descuento: number,     // 0-999999
  codigo?: string | null,      // Alfanumérico, guiones, underscores
  activo: boolean,
  fecha_inicio?: string | null,
  fecha_fin?: string | null,
  items_combo: Array<{
    producto_id, nombre_producto, cantidad, precio
  }>,
  aplicar_a?: {
    productos: string[],
    categorias: string[]
  } | null
}
```

---

### 5.8 Notificaciones (`/api/notifications`) — Auth + Tenant

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/` | Últimas 50 notificaciones |
| GET | `/unread-count` | Contador de no leídas |
| PATCH | `/:id/read` | Marcar como leída |
| PATCH | `/read-all` | Marcar todas como leídas |
| GET | `/preferences` | Preferencias de notificación |
| PUT | `/preferences` | Actualizar preferencia |

---

### 5.9 Estadísticas (`/api/stats`) — Auth + Tenant

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/dashboard` | Datos del dashboard (hoy) |
| GET | `/summary?startDate=&endDate=` | Resumen por rango de fechas |

**Dashboard response**:
```json
{
  "pedidos": [...],
  "ventasHoy": 15000,
  "totalClientes": 45,
  "totalProductos": 30,
  "totalCategorias": 8
}
```

**Summary response**:
```json
{
  "totalRevenue": 150000,
  "totalOrders": 120,
  "avgTicket": 1250,
  "pedidos": [...]
}
```

---

### 5.10 Uploads (`/api/uploads`) — Auth + Tenant

| Método | Ruta | Descripción |
|--------|------|-------------|
| POST | `/product-images` | Subir imagen de producto |
| POST | `/branding-images` | Subir imagen de branding (logo/banner) |
| POST | `/promo-images` | Subir imagen de promo |
| DELETE | `/image` | Eliminar imagen |

**Configuración**:
- Directorio: `./uploads/{products,branding,promos}/`
- Tamaño máximo: 5MB (configurable)
- Tipos permitidos: Solo imágenes (`image/*`)
- Nombre: `{timestamp}-{random}{ext}`

**Response upload**: `{ "publicUrl": "/uploads/products/...", "filePath": "..." }`

---

### 5.11 MercadoPago (`/api/mercadopago`)

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| POST | `/create-preapproval` | Bearer + Tenant | Crear suscripción pre-aprobada |
| POST | `/webhook` | Verificación HMAC | Webhook de notificaciones MP |

#### Flujo de Suscripción
1. Usuario llama `POST /create-preapproval`
2. Se crea `PreApproval` en MercadoPago (ARS 15/mes)
3. Se retorna `init_point` (URL de pago)
4. Usuario completa el pago
5. MP envía webhook a `POST /webhook`
6. Se verifica firma HMAC con `MERCADO_PAGO_WEBHOOK_SECRET`
7. Se actualiza `plan_tier` a `"pro"` si status es `"authorized"`

---

### 5.12 Menú Público (`/api/public-menu`)

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| GET | `/:slug` | No | Menú completo del negocio |

**Response**:
```json
{
  "negocio": { /* config completa */ },
  "categorias": [
    {
      "id": "uuid",
      "nombre": "Pizzas",
      "slug": "pizzas",
      "productos": [
        {
          "id": "uuid",
          "nombre": "Muzzarella",
          "descripcion": "...",
          "precio": 2500,
          "imagen_url": "...",
          "disponible": true,
          "configuracion": { /* variantes, opciones */ }
        }
      ]
    }
  ],
  "uncategorizedProducts": [...],
  "promos": [...]
}
```

---

## 6. Middleware

### 6.1 `requireAuth` (`src/middleware/auth.ts`)
Extrae el token Bearer del header `Authorization`, lo verifica con JWT y carga `req.user` con `{ userId, email }`.

**Errores**:
- 401: Token no proporcionado
- 401: Token inválido o expirado

### 6.2 `resolveTenant` (`src/middleware/tenant.ts`)
Resuelve el `negocio_id` del usuario autenticado:
1. Primero busca en `negocios.user_id` (propietario)
2. Si no, busca en `team_members.user_id` (miembro del equipo)
3. Asigna `req.negocioId`

**Errores**:
- 401: No autenticado
- 403: Negocio no asignado

---

## 7. Seguridad

### 7.1 Rate Limiting
Implementado vía tabla `rate_limits` con fallback in-memory.

| Endpoint | Límite |
|----------|--------|
| Login | 10/min por IP |
| Register | 20/min por IP |
| Check duplicate | 30/min por IP |
| Reset password | 3/min por IP |

### 7.2 Validación
Todos los inputs se validan con **Zod schemas** (`src/lib/schemas.ts`):
- `loginSchema`, `registerSchema`
- `upsertProductSchema`, `upsertPromoSchema`
- `updateOrderStatusSchema`, `submitOrderSchema`

### 7.3 Audit Logging
Operaciones CRUD en productos, categorías y pedidos se registran en `audit_logs` con:
- `negocio_id`, `user_id`
- `accion` (create/update/delete)
- `entidad` (producto/categoria/pedido)
- `cambios_previos`, `cambios_nuevos` (JSONB)

### 7.4 Webhook Verification
MercadoPago webhooks se verifican con HMAC-SHA256 usando el header `x-signature` y `x-request-id`.

### 7.5 Upload Security
- Solo archivos de imagen (`image/*`)
- Tamaño máximo configurable
- Path traversal protection: se verifica que la ruta esté dentro de `UPLOAD_DIR`
- Nombre aleatorio (timestamp + random)

---

## 8. Deploy con Docker

### Dockerfile (Multi-stage)

```dockerfile
# Stage 1: Dependencias de producción
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

# Stage 2: Build TypeScript
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npx tsc

# Stage 3: Producción
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup -g 1001 -S nodejs && adduser -S nodeuser -u 1001 -G nodejs
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY package.json ./
USER root
RUN mkdir -p uploads/products uploads/branding uploads/promos && chown -R nodeuser:nodejs uploads
USER nodeuser
EXPOSE 4000
CMD ["node", "dist/index.js"]
```

### Comandos

```bash
# Desarrollo
npm run dev          # tsx watch src/index.ts

# Build
npm run build        # tsc
npm start            # node dist/index.js

# Type check
npm run typecheck    # tsc --noEmit
```

---

## 9. Scripts de Utilidad

| Script | Descripción |
|--------|-------------|
| `populate-demo.sh` | Poblar base de datos con datos de demostración |
| `simulate-day.sh` | Simular actividad de un día completo |
| `test-suite.sh` | Suite de tests de la API |
| `test-prod.sh` | Tests contra entorno de producción |

---

## 10. Planes y Limitaciones

| Recurso | Free | Pro |
|---------|------|-----|
| Productos | 50 | 9999 |
| Categorías | 15 | 999 |
| Precio mensual | $0 | ARS 15 |

---

## 11. Enums

### `estado_pedido`
- `pendiente`
- `en_preparacion`
- `entregado`
- `cancelado`

### `team_role`
- `admin`
- `staff`
- `viewer`

### `tipo_descuento` (promo)
- `porcentaje`
- `monto_fijo`
- `combo`
