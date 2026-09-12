import { Router, Request, Response } from "express";
import { query } from "../lib/db";
import { requireAuth } from "../middleware/auth";
import { resolveTenant } from "../middleware/tenant";
import { requireRole } from "../middleware/role";
import { upsertProductSchema } from "../lib/schemas";
import { logAuditEvent } from "../lib/audit";

const router = Router();

// Read routes: any authenticated user with tenant access
router.use(requireAuth, resolveTenant);

// ── Products (Read) ─────────────────────────────────────

router.get("/products", async (req: Request, res: Response) => {
  try {
    const { rows } = await query(
      "SELECT * FROM productos WHERE negocio_id = $1 ORDER BY nombre",
      [req.negocioId]
    );
    return res.json(rows);
  } catch (err) {
    console.error("[CATALOG] Error fetching products:", err);
    return res.status(500).json({ error: "Error al obtener productos" });
  }
});

router.get("/products/:id", async (req: Request, res: Response) => {
  try {
    const { rows } = await query(
      "SELECT * FROM productos WHERE id = $1 AND negocio_id = $2",
      [req.params.id, req.negocioId]
    );
    if (!rows[0]) return res.status(404).json({ error: "Producto no encontrado" });
    return res.json(rows[0]);
  } catch (err) {
    return res.status(500).json({ error: "Error al obtener producto" });
  }
});

// ── Categories (Read) ───────────────────────────────────

router.get("/categories", async (req: Request, res: Response) => {
  try {
    const { rows } = await query(
      "SELECT * FROM categorias WHERE negocio_id = $1 ORDER BY nombre",
      [req.negocioId]
    );
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ error: "Error al obtener categorías" });
  }
});

// ── Write routes (admin/staff only) ──────────────────────

router.post("/products", requireRole(["admin", "staff"]), async (req: Request, res: Response) => {
  try {
    const parsed = upsertProductSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: `Datos inválidos: ${parsed.error.issues[0]?.message}` });
    }

    // Check plan limits
    const countResult = await query(
      "SELECT COUNT(*) as count FROM productos WHERE negocio_id = $1",
      [req.negocioId]
    );
    const currentCount = parseInt(countResult.rows[0].count);

    const tierResult = await query("SELECT plan_tier FROM negocios WHERE id = $1", [req.negocioId]);
    const tier = tierResult.rows[0]?.plan_tier || "free";
    const maxProducts = tier === "pro" ? 9999 : 50;

    if (currentCount >= maxProducts) {
      return res.status(403).json({ error: "Alcanzaste el límite de productos de tu plan. Actualizá a PRO." });
    }

    const { rows } = await query(
      `INSERT INTO productos (nombre, descripcion, precio, imagen_url, categoria_id, disponible, stock, stock_minimo, configuracion, negocio_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       RETURNING *`,
      [
        parsed.data.nombre,
        parsed.data.descripcion || null,
        parsed.data.precio,
        parsed.data.imagen_url || null,
        parsed.data.categoria_id || null,
        parsed.data.disponible,
        parsed.data.stock || 0,
        parsed.data.stock_minimo || 5,
        JSON.stringify(parsed.data.configuracion),
        req.negocioId,
      ]
    );

    logAuditEvent({
      negocio_id: req.negocioId!,
      user_id: req.user!.userId,
      accion: "create",
      entidad: "producto",
      entidad_id: rows[0].id,
      cambios_nuevos: parsed.data as unknown as Record<string, unknown>,
    });

    return res.status(201).json(rows[0]);
  } catch (err) {
    console.error("[CATALOG] Error creating product:", err);
    return res.status(500).json({ error: "Error al crear producto" });
  }
});

router.put("/products/:id", requireRole(["admin", "staff"]), async (req: Request, res: Response) => {
  try {
    const parsed = upsertProductSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: `Datos inválidos: ${parsed.error.issues[0]?.message}` });
    }

    // Get old data for audit
    const oldResult = await query(
      "SELECT nombre, precio, disponible FROM productos WHERE id = $1 AND negocio_id = $2",
      [req.params.id, req.negocioId]
    );

    const { rows } = await query(
      `UPDATE productos SET
        nombre = $1, descripcion = $2, precio = $3, imagen_url = $4,
        categoria_id = $5, disponible = $6, stock = $7, stock_minimo = $8,
        configuracion = $9
       WHERE id = $10 AND negocio_id = $11
       RETURNING *`,
      [
        parsed.data.nombre,
        parsed.data.descripcion || null,
        parsed.data.precio,
        parsed.data.imagen_url || null,
        parsed.data.categoria_id || null,
        parsed.data.disponible,
        parsed.data.stock || 0,
        parsed.data.stock_minimo || 5,
        JSON.stringify(parsed.data.configuracion),
        req.params.id,
        req.negocioId,
      ]
    );

    if (!rows[0]) return res.status(404).json({ error: "Producto no encontrado" });

    logAuditEvent({
      negocio_id: req.negocioId!,
      user_id: req.user!.userId,
      accion: "update",
      entidad: "producto",
      entidad_id: req.params.id,
      cambios_previos: oldResult.rows[0],
      cambios_nuevos: parsed.data as unknown as Record<string, unknown>,
    });

    return res.json(rows[0]);
  } catch (err) {
    console.error("[CATALOG] Error updating product:", err);
    return res.status(500).json({ error: "Error al actualizar producto" });
  }
});

router.patch("/products/:id/toggle", requireRole(["admin", "staff"]), async (req: Request, res: Response) => {
  try {
    const { disponible } = req.body;
    if (typeof disponible !== "boolean") {
      return res.status(400).json({ error: "disponible debe ser boolean" });
    }

    const { rows } = await query(
      "UPDATE productos SET disponible = $1 WHERE id = $2 AND negocio_id = $3 RETURNING *",
      [disponible, req.params.id, req.negocioId]
    );

    if (!rows[0]) return res.status(404).json({ error: "Producto no encontrado" });
    return res.json(rows[0]);
  } catch (err) {
    return res.status(500).json({ error: "Error al actualizar producto" });
  }
});

router.delete("/products/:id", requireRole(["admin", "staff"]), async (req: Request, res: Response) => {
  try {
    const oldResult = await query(
      "SELECT nombre FROM productos WHERE id = $1 AND negocio_id = $2",
      [req.params.id, req.negocioId]
    );

    const { rowCount } = await query(
      "DELETE FROM productos WHERE id = $1 AND negocio_id = $2",
      [req.params.id, req.negocioId]
    );

    if (!rowCount) return res.status(404).json({ error: "Producto no encontrado" });

    logAuditEvent({
      negocio_id: req.negocioId!,
      user_id: req.user!.userId,
      accion: "delete",
      entidad: "producto",
      entidad_id: req.params.id,
      cambios_previos: oldResult.rows[0],
    });

    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: "Error al eliminar producto" });
  }
});

router.post("/categories", requireRole(["admin", "staff"]), async (req: Request, res: Response) => {
  try {
    const { nombre, slug } = req.body;
    if (!nombre || !slug) {
      return res.status(400).json({ error: "Nombre y slug requeridos" });
    }

    // Check plan limits
    const countResult = await query(
      "SELECT COUNT(*) as count FROM categorias WHERE negocio_id = $1",
      [req.negocioId]
    );
    const currentCount = parseInt(countResult.rows[0].count);

    const tierResult = await query("SELECT plan_tier FROM negocios WHERE id = $1", [req.negocioId]);
    const tier = tierResult.rows[0]?.plan_tier || "free";
    const maxCategories = tier === "pro" ? 999 : 15;

    if (currentCount >= maxCategories) {
      return res.status(403).json({ error: "Alcanzaste el límite de categorías de tu plan." });
    }

    // Check duplicate slug within tenant
    const slugCheck = await query(
      "SELECT id FROM categorias WHERE slug = $1 AND negocio_id = $2",
      [slug, req.negocioId]
    );
    if (slugCheck.rows[0]) {
      return res.status(409).json({ error: "Ya existe una sección con ese identificador." });
    }

    const { rows } = await query(
      "INSERT INTO categorias (nombre, slug, negocio_id) VALUES ($1, $2, $3) RETURNING *",
      [nombre, slug, req.negocioId]
    );

    logAuditEvent({
      negocio_id: req.negocioId!,
      user_id: req.user!.userId,
      accion: "create",
      entidad: "categoria",
      entidad_id: rows[0].id,
      cambios_nuevos: { nombre, slug },
    });

    return res.status(201).json(rows[0]);
  } catch (err) {
    console.error("[CATALOG] Error creating category:", err);
    return res.status(500).json({ error: "Error al crear categoría" });
  }
});

router.delete("/categories/:id", requireRole(["admin", "staff"]), async (req: Request, res: Response) => {
  try {
    const oldResult = await query(
      "SELECT nombre FROM categorias WHERE id = $1 AND negocio_id = $2",
      [req.params.id, req.negocioId]
    );

    const { rowCount } = await query(
      "DELETE FROM categorias WHERE id = $1 AND negocio_id = $2",
      [req.params.id, req.negocioId]
    );

    if (!rowCount) return res.status(404).json({ error: "Categoría no encontrada" });

    logAuditEvent({
      negocio_id: req.negocioId!,
      user_id: req.user!.userId,
      accion: "delete",
      entidad: "categoria",
      entidad_id: req.params.id,
      cambios_previos: oldResult.rows[0],
    });

    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: "Error al eliminar categoría" });
  }
});

export default router;
