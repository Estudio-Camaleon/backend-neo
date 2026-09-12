import { Router, Request, Response } from "express";
import { query } from "../lib/db";
import { requireAuth } from "../middleware/auth";
import { resolveTenant } from "../middleware/tenant";
import { requireRole } from "../middleware/role";
import { upsertPromoSchema } from "../lib/schemas";

const router = Router();
router.use(requireAuth, resolveTenant, requireRole(["admin", "staff"]));

router.get("/", async (req: Request, res: Response) => {
  try {
    const { rows } = await query(
      "SELECT * FROM promos WHERE negocio_id = ? ORDER BY created_at DESC",
      [req.negocioId]
    );
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ error: "Error al obtener promos" });
  }
});

router.get("/products", async (req: Request, res: Response) => {
  try {
    const [prodRes, catRes] = await Promise.all([
      query("SELECT id, nombre, precio FROM productos WHERE negocio_id = ? AND disponible = true ORDER BY nombre", [req.negocioId]),
      query("SELECT id, nombre FROM categorias WHERE negocio_id = ? ORDER BY nombre", [req.negocioId]),
    ]);
    return res.json({ productos: prodRes.rows, categorias: catRes.rows });
  } catch (err) {
    return res.status(500).json({ error: "Error al obtener productos" });
  }
});

router.post("/", async (req: Request, res: Response) => {
  try {
    const parsed = upsertPromoSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: `Datos inválidos: ${parsed.error.issues[0]?.message}` });
    }

    const {
      nombre, descripcion, imagen_url, tipo_descuento, valor_descuento,
      codigo, activo, fecha_inicio, fecha_fin, items_combo, aplicar_a,
    } = parsed.data;

    if (codigo) {
      const codeCheck = await query(
        "SELECT id FROM promos WHERE negocio_id = ? AND codigo = ?",
        [req.negocioId, codigo]
      );
      if (codeCheck.rows[0]) {
        return res.status(409).json({ error: "Ya existe una promoción con ese código" });
      }
    }

    const { insertId } = await query(
      `INSERT INTO promos (negocio_id, nombre, descripcion, imagen_url, tipo_descuento, valor_descuento, codigo, activo, fecha_inicio, fecha_fin, items_combo, aplicar_a)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        req.negocioId, nombre, descripcion || null, imagen_url || null,
        tipo_descuento, valor_descuento, codigo || null, activo !== false,
        fecha_inicio || null, fecha_fin || null,
        items_combo ? JSON.stringify(items_combo) : '[]',
        aplicar_a ? JSON.stringify(aplicar_a) : null,
      ]
    );

    const { rows } = await query("SELECT * FROM promos WHERE id = ?", [insertId]);
    return res.status(201).json(rows[0]);
  } catch (err) {
    console.error("[PROMOS] Create error:", err);
    return res.status(500).json({ error: "Error al crear promo" });
  }
});

router.put("/:id", async (req: Request, res: Response) => {
  try {
    const parsed = upsertPromoSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: `Datos inválidos: ${parsed.error.issues[0]?.message}` });
    }

    const {
      nombre, descripcion, imagen_url, tipo_descuento, valor_descuento,
      codigo, activo, fecha_inicio, fecha_fin, items_combo, aplicar_a,
    } = parsed.data;

    if (codigo) {
      const codeCheck = await query(
        "SELECT id FROM promos WHERE negocio_id = ? AND codigo = ? AND id != ?",
        [req.negocioId, codigo, req.params.id]
      );
      if (codeCheck.rows[0]) {
        return res.status(409).json({ error: "Ya existe una promoción con ese código" });
      }
    }

    const { affectedRows } = await query(
      `UPDATE promos SET
        nombre = ?, descripcion = ?, imagen_url = ?, tipo_descuento = ?,
        valor_descuento = ?, codigo = ?, activo = ?, fecha_inicio = ?,
        fecha_fin = ?, items_combo = ?, aplicar_a = ?, updated_at = NOW()
       WHERE id = ? AND negocio_id = ?`,
      [
        nombre, descripcion || null, imagen_url || null, tipo_descuento,
        valor_descuento, codigo || null, activo, fecha_inicio || null,
        fecha_fin || null,
        items_combo ? JSON.stringify(items_combo) : '[]',
        aplicar_a ? JSON.stringify(aplicar_a) : null,
        req.params.id, req.negocioId,
      ]
    );

    if (!affectedRows) return res.status(404).json({ error: "Promo no encontrada" });

    const { rows } = await query("SELECT * FROM promos WHERE id = ?", [req.params.id]);
    return res.json(rows[0]);
  } catch (err) {
    return res.status(500).json({ error: "Error al actualizar promo" });
  }
});

router.patch("/:id/toggle", async (req: Request, res: Response) => {
  try {
    const { activo } = req.body;
    if (typeof activo !== "boolean") {
      return res.status(400).json({ error: "activo debe ser boolean" });
    }
    const { affectedRows } = await query(
      "UPDATE promos SET activo = ?, updated_at = NOW() WHERE id = ? AND negocio_id = ?",
      [activo, req.params.id, req.negocioId]
    );
    if (!affectedRows) return res.status(404).json({ error: "Promo no encontrada" });

    const { rows } = await query("SELECT * FROM promos WHERE id = ?", [req.params.id]);
    return res.json(rows[0]);
  } catch (err) {
    return res.status(500).json({ error: "Error al actualizar promo" });
  }
});

router.delete("/:id", async (req: Request, res: Response) => {
  try {
    const { affectedRows } = await query(
      "DELETE FROM promos WHERE id = ? AND negocio_id = ?",
      [req.params.id, req.negocioId]
    );
    if (!affectedRows) return res.status(404).json({ error: "Promo no encontrada" });
    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: "Error al eliminar promo" });
  }
});

export default router;
