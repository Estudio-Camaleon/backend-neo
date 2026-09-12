-- NEO Database Schema
-- MySQL 8.0

SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;

-- ═══════════════════════════════════════════════════════════
-- TABLES
-- ═══════════════════════════════════════════════════════════

-- Users
CREATE TABLE IF NOT EXISTS users (
  id CHAR(36) PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  first_name VARCHAR(255),
  last_name VARCHAR(255),
  phone VARCHAR(50),
  email_confirmed BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Negocios (tenants)
CREATE TABLE IF NOT EXISTS negocios (
  id CHAR(36) PRIMARY KEY,
  user_id CHAR(36),
  nombre VARCHAR(255) NOT NULL,
  slug VARCHAR(255) UNIQUE NOT NULL,
  phone VARCHAR(50),
  descripcion TEXT,
  direccion TEXT,
  localidad VARCHAR(255),
  direccion_notas TEXT,
  direcciones JSON,
  horarios JSON,
  whatsapp VARCHAR(50),
  whatsapp_mensajes JSON,
  color_primary VARCHAR(50),
  logo_url TEXT,
  logo_scale DECIMAL(5,2) DEFAULT 1,
  logo_posicion VARCHAR(50) DEFAULT 'centro',
  logo_fit VARCHAR(50) DEFAULT 'cover',
  logo_shape VARCHAR(50) DEFAULT 'rectangulo',
  banner_url TEXT,
  banner_posicion VARCHAR(50) DEFAULT 'centro',
  banner_height VARCHAR(20) DEFAULT '200px',
  banner_scale DECIMAL(5,2) DEFAULT 1,
  mostrar_nombre BOOLEAN DEFAULT true,
  instagram_url TEXT,
  facebook_url TEXT,
  tiktok_url TEXT,
  twitter_url TEXT,
  youtube_url TEXT,
  tripadvisor_url TEXT,
  redes_principales JSON,
  floating_shapes JSON,
  tipo_envio VARCHAR(50) DEFAULT 'delivery',
  moneda_simbolo VARCHAR(10) DEFAULT '$',
  pedido_minimo DECIMAL(10,2) DEFAULT 0,
  costo_envio DECIMAL(10,2) DEFAULT 0,
  recepcion_pausada BOOLEAN DEFAULT false,
  plan_tier VARCHAR(50) DEFAULT 'free',
  subscription_status VARCHAR(50),
  mp_subscription_id VARCHAR(255),
  mp_customer_id VARCHAR(255),
  mp_status VARCHAR(50),
  stripe_customer_id VARCHAR(255),
  stripe_subscription_id VARCHAR(255),
  current_period_ends_at TIMESTAMP NULL,
  trial_ends_at TIMESTAMP NULL,
  referral_source VARCHAR(255),
  deletion_reason TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_negocios_user_id ON negocios(user_id);
CREATE INDEX idx_negocios_slug ON negocios(slug);
CREATE INDEX idx_negocios_mp_subscription ON negocios(mp_subscription_id);
CREATE INDEX idx_negocios_mp_customer ON negocios(mp_customer_id);

-- Categorias
CREATE TABLE IF NOT EXISTS categorias (
  id CHAR(36) PRIMARY KEY,
  negocio_id CHAR(36) NOT NULL,
  nombre VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  icono VARCHAR(255),
  FOREIGN KEY (negocio_id) REFERENCES negocios(id) ON DELETE CASCADE,
  UNIQUE KEY uq_categorias_negocio_slug (negocio_id, slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_categorias_negocio ON categorias(negocio_id);

-- Productos
CREATE TABLE IF NOT EXISTS productos (
  id CHAR(36) PRIMARY KEY,
  negocio_id CHAR(36) NOT NULL,
  categoria_id CHAR(36),
  nombre VARCHAR(255) NOT NULL,
  descripcion TEXT,
  precio DECIMAL(10,2) DEFAULT 0,
  imagen_url TEXT,
  disponible BOOLEAN DEFAULT true,
  stock INT DEFAULT 0,
  stock_minimo INT DEFAULT 5,
  configuracion JSON,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (negocio_id) REFERENCES negocios(id) ON DELETE CASCADE,
  FOREIGN KEY (categoria_id) REFERENCES categorias(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_productos_negocio ON productos(negocio_id);
CREATE INDEX idx_productos_categoria ON productos(categoria_id);

-- Clientes
CREATE TABLE IF NOT EXISTS clientes (
  id CHAR(36) PRIMARY KEY,
  negocio_id CHAR(36) NOT NULL,
  nombre VARCHAR(255) NOT NULL,
  telefono VARCHAR(50),
  email VARCHAR(255),
  direccion TEXT,
  notas TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (negocio_id) REFERENCES negocios(id) ON DELETE CASCADE,
  UNIQUE KEY uq_clientes_negocio_telefono (negocio_id, telefono)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_clientes_negocio ON clientes(negocio_id);

-- Pedidos
CREATE TABLE IF NOT EXISTS pedidos (
  id CHAR(36) PRIMARY KEY,
  negocio_id CHAR(36) NOT NULL,
  cliente_id CHAR(36),
  cliente_nombre VARCHAR(255),
  cliente_whatsapp VARCHAR(50),
  estado ENUM('pendiente', 'en_preparacion', 'entregado', 'cancelado') DEFAULT 'pendiente',
  total DECIMAL(10,2) DEFAULT 0,
  es_delivery BOOLEAN DEFAULT false,
  direccion_entrega TEXT,
  metodo_pago VARCHAR(50),
  notas TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (negocio_id) REFERENCES negocios(id) ON DELETE CASCADE,
  FOREIGN KEY (cliente_id) REFERENCES clientes(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_pedidos_negocio ON pedidos(negocio_id);
CREATE INDEX idx_pedidos_created ON pedidos(negocio_id, created_at DESC);

-- Pedido Items
CREATE TABLE IF NOT EXISTS pedido_items (
  id CHAR(36) PRIMARY KEY,
  pedido_id CHAR(36) NOT NULL,
  producto_id CHAR(36),
  nombre_producto VARCHAR(255) NOT NULL,
  cantidad INT NOT NULL,
  precio_unitario DECIMAL(10,2) NOT NULL,
  detalles TEXT,
  FOREIGN KEY (pedido_id) REFERENCES pedidos(id) ON DELETE CASCADE,
  FOREIGN KEY (producto_id) REFERENCES productos(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_pedido_items_pedido ON pedido_items(pedido_id);

-- Promos
CREATE TABLE IF NOT EXISTS promos (
  id CHAR(36) PRIMARY KEY,
  negocio_id CHAR(36) NOT NULL,
  nombre VARCHAR(255) NOT NULL,
  descripcion TEXT,
  imagen_url TEXT,
  tipo_descuento VARCHAR(50) NOT NULL,
  valor_descuento DECIMAL(10,2) NOT NULL,
  codigo VARCHAR(100),
  activo BOOLEAN DEFAULT true,
  items_combo JSON DEFAULT (JSON_ARRAY()),
  aplicar_a JSON,
  fecha_inicio TIMESTAMP NULL,
  fecha_fin TIMESTAMP NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (negocio_id) REFERENCES negocios(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_promos_negocio ON promos(negocio_id);

-- Team Members
CREATE TABLE IF NOT EXISTS team_members (
  id CHAR(36) PRIMARY KEY,
  negocio_id CHAR(36) NOT NULL,
  user_id CHAR(36) NOT NULL,
  role ENUM('admin', 'staff', 'viewer') DEFAULT 'staff',
  invited_by CHAR(36),
  accepted_at TIMESTAMP NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (negocio_id) REFERENCES negocios(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (invited_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_team_members_user ON team_members(user_id);
CREATE INDEX idx_team_members_negocio ON team_members(negocio_id);

-- Notifications
CREATE TABLE IF NOT EXISTS notifications (
  id CHAR(36) PRIMARY KEY,
  negocio_id CHAR(36) NOT NULL,
  type VARCHAR(100) NOT NULL,
  title VARCHAR(255) NOT NULL,
  body TEXT,
  data JSON DEFAULT (JSON_OBJECT()),
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (negocio_id) REFERENCES negocios(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_notifications_negocio ON notifications(negocio_id, created_at DESC);
CREATE INDEX idx_notifications_unread ON notifications(negocio_id, is_read);

-- Notification Preferences
CREATE TABLE IF NOT EXISTS notification_preferences (
  id CHAR(36) PRIMARY KEY,
  negocio_id CHAR(36) NOT NULL,
  notification_type VARCHAR(100) NOT NULL,
  enabled BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (negocio_id) REFERENCES negocios(id) ON DELETE CASCADE,
  UNIQUE KEY uq_notification_pref (negocio_id, notification_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Audit Logs
CREATE TABLE IF NOT EXISTS audit_logs (
  id CHAR(36) PRIMARY KEY,
  negocio_id CHAR(36) NOT NULL,
  user_id VARCHAR(255) NOT NULL,
  accion VARCHAR(255) NOT NULL,
  entidad VARCHAR(255) NOT NULL,
  entidad_id VARCHAR(255),
  cambios_previos JSON,
  cambios_nuevos JSON,
  ip_address VARCHAR(50),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (negocio_id) REFERENCES negocios(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_audit_logs_negocio ON audit_logs(negocio_id, created_at DESC);

-- Rate Limits
CREATE TABLE IF NOT EXISTS rate_limits (
  id CHAR(36) PRIMARY KEY,
  `key` VARCHAR(255) NOT NULL,
  `count` INT DEFAULT 1,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_rate_limits_key ON rate_limits(`key`);

-- ═══════════════════════════════════════════════════════════
-- STORED PROCEDURES
-- ═══════════════════════════════════════════════════════════

DELIMITER //

-- Cleanup expired rate limits
CREATE PROCEDURE IF NOT EXISTS cleanup_rate_limits()
BEGIN
  DELETE FROM rate_limits WHERE expires_at < NOW();
END //

-- Submit order atomically
CREATE PROCEDURE IF NOT EXISTS submit_order_atomic(
  IN p_negocio_id CHAR(36),
  IN p_cliente_nombre VARCHAR(255),
  IN p_cliente_whatsapp VARCHAR(50),
  IN p_es_delivery BOOLEAN,
  IN p_direccion_entrega TEXT,
  IN p_metodo_pago VARCHAR(50),
  IN p_notas TEXT,
  IN p_items JSON
)
BEGIN
  DECLARE v_pedido_id CHAR(36);
  DECLARE v_cliente_id CHAR(36);
  DECLARE v_total DECIMAL(10,2) DEFAULT 0;
  DECLARE v_item_idx INT DEFAULT 0;
  DECLARE v_item_count INT;
  DECLARE v_producto_id CHAR(36);
  DECLARE v_cantidad INT;
  DECLARE v_producto_nombre VARCHAR(255);
  DECLARE v_producto_precio DECIMAL(10,2);
  DECLARE v_producto_stock INT;
  DECLARE v_detalles TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    RESIGNAL;
  END;

  START TRANSACTION;

  -- Validate business exists and accepts orders
  IF NOT EXISTS (
    SELECT 1 FROM negocios
    WHERE id = p_negocio_id AND (recepcion_pausada IS NULL OR recepcion_pausada = false)
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El negocio no esta aceptando pedidos';
  END IF;

  -- Upsert client
  INSERT INTO clientes (id, negocio_id, nombre, telefono)
  VALUES (UUID(), p_negocio_id, p_cliente_nombre, p_cliente_whatsapp)
  ON DUPLICATE KEY UPDATE nombre = VALUES(nombre);
  
  SELECT id INTO v_cliente_id FROM clientes
  WHERE negocio_id = p_negocio_id AND telefono = p_cliente_whatsapp LIMIT 1;

  -- Create order
  SET v_pedido_id = UUID();
  INSERT INTO pedidos (id, negocio_id, cliente_id, cliente_nombre, cliente_whatsapp, es_delivery, direccion_entrega, metodo_pago, notas)
  VALUES (v_pedido_id, p_negocio_id, v_cliente_id, p_cliente_nombre, p_cliente_whatsapp, p_es_delivery, p_direccion_entrega, p_metodo_pago, p_notas);

  -- Process items
  SET v_item_count = JSON_LENGTH(p_items);

  WHILE v_item_idx < v_item_count DO
    SET v_producto_id = JSON_UNQUOTE(JSON_EXTRACT(p_items, CONCAT('$[', v_item_idx, '].producto_id')));
    SET v_cantidad = CAST(JSON_UNQUOTE(JSON_EXTRACT(p_items, CONCAT('$[', v_item_idx, '].cantidad'))) AS UNSIGNED);
    SET v_detalles = JSON_UNQUOTE(JSON_EXTRACT(p_items, CONCAT('$[', v_item_idx, '].detalles')));

    -- Get product info
    SELECT nombre, precio, stock INTO v_producto_nombre, v_producto_precio, v_producto_stock
    FROM productos
    WHERE id = v_producto_id AND negocio_id = p_negocio_id AND disponible = true;

    IF v_producto_nombre IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Producto no encontrado o no disponible';
    END IF;

    -- Check stock (stock = 0 means unlimited)
    IF v_producto_stock > 0 AND v_producto_stock < v_cantidad THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock insuficiente';
    END IF;

    -- Decrement stock (skip if stock = 0)
    IF v_producto_stock > 0 THEN
      UPDATE productos SET stock = stock - v_cantidad WHERE id = v_producto_id;
    END IF;

    -- Calculate total
    SET v_total = v_total + (v_producto_precio * v_cantidad);

    INSERT INTO pedido_items (id, pedido_id, producto_id, nombre_producto, cantidad, precio_unitario, detalles)
    VALUES (UUID(), v_pedido_id, v_producto_id, v_producto_nombre, v_cantidad, v_producto_precio, v_detalles);

    SET v_item_idx = v_item_idx + 1;
  END WHILE;

  -- Update order total
  UPDATE pedidos SET total = v_total WHERE id = v_pedido_id;

  COMMIT;

  SELECT v_pedido_id AS pedido_id;
END //

-- Delete business completely
CREATE PROCEDURE IF NOT EXISTS eliminar_negocio_completo(IN p_negocio_id CHAR(36))
BEGIN
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

  SELECT JSON_OBJECT('success', true) AS result;
END //

DELIMITER ;
