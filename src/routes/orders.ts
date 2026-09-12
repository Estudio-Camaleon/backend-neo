import { Router, Request, Response } from "express";
import { query } from "../lib/db";
import { requireAuth } from "../middleware/auth";
import { resolveTenant } from "../middleware/tenant";
import { requireRole } from "../middleware/role";
import { logAuditEvent } from "../lib/audit";
import { submitOrderSchema } from "../lib/schemas";
import { checkRateLimit } from "../lib/rate-limit";

const router = Router();

// ── Admin routes (require auth) ─────────────────────────

const adminRouter = Router();
adminRouter.use(requireAuth, resolveTenant, requireRole(["admin", "staff"]));

adminRouter.get("/recent", async (req: Request, res: Response) => {
  try {
    const limit = Math.min(parseInt(req.query.limit as string) || 10, 50);
    const { rows } = await query(
      `SELECT p.*,
        IFNULL(
          (SELECT JSON_ARRAYAGG(JSON_OBJECT(
            'id', pi.id, 'producto_id', pi.producto_id, 'nombre_producto', pi.nombre_producto,
            'cantidad', pi.cantidad, 'precio_unitario', pi.precio_unitario, 'detalles', pi.detalles
          )) FROM pedido_items pi WHERE pi.pedido_id = p.id),
          '[]'
        ) as pedido_items
       FROM pedidos p
       WHERE p.negocio_id = ?
       ORDER BY p.created_at DESC LIMIT ?`,
      [req.negocioId, limit]
    );
    return res.json(rows);
  } catch (err) {
    console.error("[ORDERS] Error fetching recent orders:", err);
    return res.status(500).json({ error: "Error al obtener pedidos recientes" });
  }
});

adminRouter.get("/", async (req: Request, res: Response) => {
  try {
    const { startDate, endDate, status } = req.query;

    // Validate dates
    if (startDate && isNaN(Date.parse(startDate as string))) {
      return res.status(400).json({ error: "startDate no es una fecha válida" });
    }
    if (endDate && isNaN(Date.parse(endDate as string))) {
      return res.status(400).json({ error: "endDate no es una fecha válida" });
    }

    const validStatuses = ["pendiente", "en_preparacion", "entregado", "cancelado"];
    if (status && !validStatuses.includes(status as string)) {
      return res.status(400).json({ error: "Estado no válido" });
    }

    let sql = `
      SELECT p.*,
        IFNULL(
          (SELECT JSON_ARRAYAGG(JSON_OBJECT(
            'id', pi.id, 'producto_id', pi.producto_id, 'nombre_producto', pi.nombre_producto,
            'cantidad', pi.cantidad, 'precio_unitario', pi.precio_unitario, 'detalles', pi.detalles
          )) FROM pedido_items pi WHERE pi.pedido_id = p.id),
          '[]'
        ) as pedido_items
      FROM pedidos p
      WHERE p.negocio_id = ?
    `;
    const params: string[] = [req.negocioId!];

    if (startDate) {
      sql += ` AND p.created_at >= ?`;
      params.push(startDate as string);
    }
    if (endDate) {
      sql += ` AND p.created_at <= ?`;
      params.push(endDate as string);
    }
    if (status) {
      sql += ` AND p.estado = ?`;
      params.push(status as string);
    }

    sql += " ORDER BY p.created_at DESC";

    const { rows } = await query(sql, params);
    return res.json(rows);
  } catch (err) {
    console.error("[ORDERS] Error fetching orders:", err);
    return res.status(500).json({ error: "Error al obtener pedidos" });
  }
});

adminRouter.patch("/:id/status", async (req: Request, res: Response) => {
  try {
    const { nuevoEstado } = req.body;
    const validStates = ["pendiente", "en_preparacion", "entregado", "cancelado"];
    if (!validStates.includes(nuevoEstado)) {
      return res.status(400).json({ error: "Estado de pedido inválido" });
    }

    const oldResult = await query(
      "SELECT estado FROM pedidos WHERE id = ? AND negocio_id = ?",
      [req.params.id, req.negocioId]
    );

    const result = await query(
      "UPDATE pedidos SET estado = ? WHERE id = ? AND negocio_id = ?",
      [nuevoEstado, req.params.id, req.negocioId]
    );

    if (!result.affectedRows) return res.status(404).json({ error: "Pedido no encontrado" });

    const { rows } = await query(
      "SELECT * FROM pedidos WHERE id = ? AND negocio_id = ?",
      [req.params.id, req.negocioId]
    );

    logAuditEvent({
      negocio_id: req.negocioId!,
      user_id: req.user!.userId,
      accion: "update",
      entidad: "pedido",
      entidad_id: req.params.id,
      cambios_previos: oldResult.rows[0],
      cambios_nuevos: { estado: nuevoEstado },
    });

    return res.json(rows[0]);
  } catch (err) {
    return res.status(500).json({ error: "Error al actualizar pedido" });
  }
});

adminRouter.patch("/toggle-reception", async (req: Request, res: Response) => {
  try {
    const { rows: current } = await query(
      "SELECT recepcion_pausada FROM negocios WHERE id = ?",
      [req.negocioId]
    );

    if (!current[0]) return res.status(404).json({ error: "Negocio no encontrado" });

    const nuevoEstado = !current[0].recepcion_pausada;

    await query(
      "UPDATE negocios SET recepcion_pausada = ?, updated_at = NOW() WHERE id = ?",
      [nuevoEstado, req.negocioId]
    );

    return res.json({ success: true, recepcion_pausada: nuevoEstado });
  } catch (err) {
    return res.status(500).json({ error: "Error al actualizar recepción" });
  }
});

// ── Public routes (no auth) ─────────────────────────────

const publicRouter = Router();

publicRouter.post("/submit", async (req: Request, res: Response) => {
  try {
    const ip = (req.headers["x-forwarded-for"] as string) || req.ip || "unknown";
    if (!(await checkRateLimit(`order-submit:${ip}`, 10, 60000))) {
      return res.status(429).json({ error: "Demasiados intentos. Inténtalo de nuevo en un minuto." });
    }

    const parsed = submitOrderSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: `Datos inválidos: ${parsed.error.issues[0]?.message}` });
    }

    const { negocio_id, cliente_nombre, cliente_whatsapp, es_delivery, direccion_entrega, metodo_pago, notas, items } = parsed.data;

    // Check business accepts orders
    const { rows: negocio } = await query(
      "SELECT recepcion_pausada FROM negocios WHERE id = ?",
      [negocio_id]
    );

    if (!negocio[0]) {
      return res.status(404).json({ error: "Negocio no encontrado" });
    }

    if (negocio[0].recepcion_pausada) {
      return res.status(403).json({ error: "La recepción de pedidos está pausada." });
    }

    // Use atomic procedure
    const { rows } = await query(
      "CALL submit_order_atomic(?, ?, ?, ?, ?, ?, ?, ?)",
      [
        negocio_id,
        cliente_nombre,
        cliente_whatsapp,
        es_delivery || false,
        direccion_entrega || "",
        metodo_pago || "efectivo",
        notas || "",
        JSON.stringify(items),
      ]
    );

    return res.status(201).json({ pedidoId: rows[0].pedido_id });
  } catch (err) {
    console.error("[ORDERS] Submit error:", err);
    return res.status(500).json({ error: "No pudimos procesar tu pedido. Intentá de nuevo." });
  }
});

router.use("/", adminRouter);
router.use("/public", publicRouter);

export default router;
