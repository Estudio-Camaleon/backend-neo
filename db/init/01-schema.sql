-- NEO Database Schema
-- Migrated from Supabase to vanilla PostgreSQL

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ═══════════════════════════════════════════════════════════
-- ENUMS
-- ═══════════════════════════════════════════════════════════

DO $$ BEGIN
  CREATE TYPE estado_pedido AS ENUM ('pendiente', 'en_preparacion', 'entregado', 'cancelado');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE team_role AS ENUM ('admin', 'staff', 'viewer');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ═══════════════════════════════════════════════════════════
-- TABLES
-- ═══════════════════════════════════════════════════════════

-- Users (replaces Supabase Auth)
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  first_name TEXT,
  last_name TEXT,
  phone TEXT,
  email_confirmed BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Negocios (tenants)
CREATE TABLE IF NOT EXISTS negocios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  nombre TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  phone TEXT,
  descripcion TEXT,
  direccion TEXT,
  localidad TEXT,
  direccion_notas TEXT,
  direcciones JSONB DEFAULT '[]'::jsonb,
  horarios JSONB,
  whatsapp TEXT,
  whatsapp_mensajes JSONB,
  color_primary TEXT,
  logo_url TEXT,
  logo_scale NUMERIC(5,2) DEFAULT 1,
  logo_posicion TEXT DEFAULT 'centro',
  logo_fit TEXT DEFAULT 'cover',
  logo_shape TEXT DEFAULT 'rectangulo',
  banner_url TEXT,
  banner_posicion TEXT DEFAULT 'centro',
  banner_height TEXT DEFAULT '200px',
  banner_scale NUMERIC(5,2) DEFAULT 1,
  mostrar_nombre BOOLEAN DEFAULT true,
  instagram_url TEXT,
  facebook_url TEXT,
  tiktok_url TEXT,
  twitter_url TEXT,
  youtube_url TEXT,
  tripadvisor_url TEXT,
  redes_principales JSONB,
  floating_shapes JSONB,
  tipo_envio TEXT DEFAULT 'delivery',
  moneda_simbolo TEXT DEFAULT '$',
  pedido_minimo NUMERIC(10,2) DEFAULT 0,
  costo_envio NUMERIC(10,2) DEFAULT 0,
  recepcion_pausada BOOLEAN DEFAULT false,
  plan_tier TEXT DEFAULT 'free',
  subscription_status TEXT,
  mp_subscription_id TEXT,
  mp_customer_id TEXT,
  mp_status TEXT,
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  current_period_ends_at TIMESTAMPTZ,
  trial_ends_at TIMESTAMPTZ,
  referral_source TEXT,
  deletion_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_negocios_user_id ON negocios(user_id);
CREATE INDEX IF NOT EXISTS idx_negocios_slug ON negocios(slug);
CREATE INDEX IF NOT EXISTS idx_negocios_mp_subscription ON negocios(mp_subscription_id);
CREATE INDEX IF NOT EXISTS idx_negocios_mp_customer ON negocios(mp_customer_id);

-- Categorías
CREATE TABLE IF NOT EXISTS categorias (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id UUID REFERENCES negocios(id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  slug TEXT NOT NULL,
  icono TEXT
);

CREATE INDEX IF NOT EXISTS idx_categorias_negocio ON categorias(negocio_id);
ALTER TABLE categorias ADD CONSTRAINT fk_categorias_negocio FOREIGN KEY (negocio_id) REFERENCES negocios(id);

-- Productos
CREATE TABLE IF NOT EXISTS productos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id UUID NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
  categoria_id UUID REFERENCES categorias(id) ON DELETE SET NULL,
  nombre TEXT NOT NULL,
  descripcion TEXT,
  precio NUMERIC(10,2) DEFAULT 0,
  imagen_url TEXT,
  disponible BOOLEAN DEFAULT true,
  stock INTEGER DEFAULT 0,
  stock_minimo INTEGER DEFAULT 5,
  configuracion JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_productos_negocio ON productos(negocio_id);
CREATE INDEX IF NOT EXISTS idx_productos_categoria ON productos(categoria_id);
ALTER TABLE productos ADD CONSTRAINT fk_productos_negocio FOREIGN KEY (negocio_id) REFERENCES negocios(id);

-- Clientes
CREATE TABLE IF NOT EXISTS clientes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id UUID NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  telefono TEXT,
  email TEXT,
  direccion TEXT,
  notas TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_clientes_negocio ON clientes(negocio_id);
ALTER TABLE clientes ADD CONSTRAINT fk_clientes_negocio FOREIGN KEY (negocio_id) REFERENCES negocios(id);

-- Pedidos
CREATE TABLE IF NOT EXISTS pedidos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id UUID NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
  cliente_id UUID REFERENCES clientes(id) ON DELETE SET NULL,
  cliente_nombre TEXT,
  cliente_whatsapp TEXT,
  estado estado_pedido DEFAULT 'pendiente',
  total NUMERIC(10,2) DEFAULT 0,
  es_delivery BOOLEAN DEFAULT false,
  direccion_entrega TEXT,
  metodo_pago TEXT,
  notas TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pedidos_negocio ON pedidos(negocio_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_created ON pedidos(negocio_id, created_at DESC);
ALTER TABLE pedidos ADD CONSTRAINT fk_pedidos_negocio FOREIGN KEY (negocio_id) REFERENCES negocios(id);

-- Pedido Items
CREATE TABLE IF NOT EXISTS pedido_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id UUID REFERENCES pedidos(id) ON DELETE CASCADE,
  producto_id UUID REFERENCES productos(id) ON DELETE SET NULL,
  nombre_producto TEXT NOT NULL,
  cantidad INTEGER NOT NULL,
  precio_unitario NUMERIC(10,2) NOT NULL,
  detalles TEXT
);

CREATE INDEX IF NOT EXISTS idx_pedido_items_pedido ON pedido_items(pedido_id);
ALTER TABLE pedido_items ADD CONSTRAINT fk_pedido_items_pedido FOREIGN KEY (pedido_id) REFERENCES pedidos(id);

-- Promos
CREATE TABLE IF NOT EXISTS promos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id UUID NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  descripcion TEXT,
  imagen_url TEXT,
  tipo_descuento TEXT NOT NULL,
  valor_descuento NUMERIC(10,2) NOT NULL,
  codigo TEXT,
  activo BOOLEAN DEFAULT true,
  items_combo JSONB DEFAULT '[]'::jsonb,
  aplicar_a JSONB,
  fecha_inicio TIMESTAMPTZ,
  fecha_fin TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_promos_negocio ON promos(negocio_id);
CREATE INDEX IF NOT EXISTS idx_promos_fecha_fin ON promos(fecha_fin) WHERE fecha_fin IS NOT NULL;

-- Team Members
CREATE TABLE IF NOT EXISTS team_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id UUID NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role team_role DEFAULT 'staff',
  invited_by UUID REFERENCES users(id),
  accepted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_team_members_user ON team_members(user_id);
CREATE INDEX IF NOT EXISTS idx_team_members_negocio ON team_members(negocio_id);

-- Notifications
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id UUID NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  data JSONB DEFAULT '{}'::jsonb,
  read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_negocio ON notifications(negocio_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(negocio_id, read) WHERE read = false;

-- Notification Preferences
CREATE TABLE IF NOT EXISTS notification_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id UUID NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
  notification_type TEXT NOT NULL,
  enabled BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT uq_notification_pref UNIQUE (negocio_id, notification_type)
);

-- Audit Logs
CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id UUID NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  accion TEXT NOT NULL,
  entidad TEXT NOT NULL,
  entidad_id TEXT,
  cambios_previos JSONB,
  cambios_nuevos JSONB,
  ip_address TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_negocio ON audit_logs(negocio_id, created_at DESC);

-- Rate Limits
CREATE TABLE IF NOT EXISTS rate_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT NOT NULL,
  count INTEGER DEFAULT 1,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_key ON rate_limits(key);

-- ═══════════════════════════════════════════════════════════
-- FUNCTIONS
-- ═══════════════════════════════════════════════════════════

-- Cleanup expired rate limits
CREATE OR REPLACE FUNCTION cleanup_rate_limits()
RETURNS void AS $$
BEGIN
  DELETE FROM rate_limits WHERE expires_at < now();
END;
$$ LANGUAGE plpgsql;

-- Submit order atomically (replaces Supabase RPC)
CREATE OR REPLACE FUNCTION submit_order_atomic(
  p_negocio_id UUID,
  p_cliente_nombre TEXT,
  p_cliente_whatsapp TEXT,
  p_es_delivery BOOLEAN,
  p_direccion_entrega TEXT,
  p_metodo_pago TEXT,
  p_notas TEXT,
  p_items JSONB
)
RETURNS UUID AS $$
DECLARE
  v_pedido_id UUID;
  v_item JSONB;
  v_producto RECORD;
  v_total NUMERIC(10,2) := 0;
  v_cliente_id UUID;
  v_cantidad INTEGER;
BEGIN
  -- Validate business exists and accepts orders
  IF NOT EXISTS (
    SELECT 1 FROM negocios
    WHERE id = p_negocio_id AND (recepcion_pausada IS NULL OR recepcion_pausada = false)
  ) THEN
    RAISE EXCEPTION 'El negocio no está aceptando pedidos';
  END IF;

  -- Upsert client
  INSERT INTO clientes (negocio_id, nombre, telefono)
  VALUES (p_negocio_id, p_cliente_nombre, p_cliente_whatsapp)
  ON CONFLICT (negocio_id, telefono)
  DO UPDATE SET nombre = EXCLUDED.nombre
  RETURNING id INTO v_cliente_id;

  -- Create order
  INSERT INTO pedidos (negocio_id, cliente_id, cliente_nombre, cliente_whatsapp, es_delivery, direccion_entrega, metodo_pago, notas)
  VALUES (p_negocio_id, v_cliente_id, p_cliente_nombre, p_cliente_whatsapp, p_es_delivery, p_direccion_entrega, p_metodo_pago, p_notas)
  RETURNING id INTO v_pedido_id;

  -- Process items with row-level locking to prevent overselling
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_cantidad := (v_item->>'cantidad')::INTEGER;

    -- Lock product row and verify availability
    SELECT id, nombre, precio, stock INTO v_producto
    FROM productos
    WHERE id = (v_item->>'producto_id')::UUID
      AND negocio_id = p_negocio_id
      AND disponible = true
    FOR UPDATE;

    IF v_producto IS NULL THEN
      RAISE EXCEPTION 'Producto no encontrado o no disponible: %', v_item->>'producto_id';
    END IF;

    -- Check stock (stock = 0 means unlimited, stock > 0 means limited)
    IF v_producto.stock > 0 AND v_producto.stock < v_cantidad THEN
      RAISE EXCEPTION 'Stock insuficiente para: % (disponible: %)', v_producto.nombre, v_producto.stock;
    END IF;

    -- Decrement stock (skip if stock = 0, which means unlimited)
    IF v_producto.stock > 0 THEN
      UPDATE productos SET stock = stock - v_cantidad WHERE id = v_producto.id;
    END IF;

    -- Calculate total including extras from detalles JSON
    v_total := v_total + (v_producto.precio * v_cantidad);

    INSERT INTO pedido_items (pedido_id, producto_id, nombre_producto, cantidad, precio_unitario, detalles)
    VALUES (
      v_pedido_id,
      v_producto.id,
      v_producto.nombre,
      v_cantidad,
      v_producto.precio,
      v_item->>'detalles'
    );
  END LOOP;

  -- Update order total
  UPDATE pedidos SET total = v_total WHERE id = v_pedido_id;

  RETURN v_pedido_id;
END;
$$ LANGUAGE plpgsql;

-- Delete business completely
CREATE OR REPLACE FUNCTION eliminar_negocio_completo(p_negocio_id UUID)
RETURNS JSONB AS $$
BEGIN
  -- Delete in cascade order
  DELETE FROM pedido_items WHERE pedido_id IN (SELECT id FROM pedidos WHERE negocio_id = p_negocio_id);
  DELETE FROM pedidos WHERE negocio_id = p_negocio_id;
  DELETE FROM clientes WHERE negocio_id = p_negocio_id;
  DELETE FROM productos WHERE negocio_id = p_negocio_id;
  DELETE FROM categorias WHERE negocio_id = p_negocio_id;
  DELETE FROM promos WHERE negocio_id = p_negocio_id;
  DELETE FROM notifications WHERE negocio_id = p_negocio_id;
  DELETE FROM notification_preferences WHERE negocio_id = p_negocio_id;
  DELETE FROM audit_logs WHERE negocio_id = p_negocio_id;
  DELETE FROM team_members WHERE negocio_id = p_negocio_id;
  DELETE FROM negocios WHERE id = p_negocio_id;

  RETURN '{"success": true}'::jsonb;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════
-- VIEWS
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW view_resumen_clientes AS
SELECT
  p.negocio_id,
  p.cliente_nombre,
  COUNT(*) AS total_pedidos,
  SUM(p.total) AS total_gasto
FROM pedidos p
WHERE p.estado != 'cancelado'
GROUP BY p.negocio_id, p.cliente_nombre;

-- ═══════════════════════════════════════════════════════════
-- ADDITIONAL CONSTRAINTS
-- ═══════════════════════════════════════════════════════════

-- Unique constraint for clientes (negocio_id, telefono) for upsert
DO $$ BEGIN
  ALTER TABLE clientes ADD CONSTRAINT uq_clientes_negocio_telefono UNIQUE (negocio_id, telefono);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
