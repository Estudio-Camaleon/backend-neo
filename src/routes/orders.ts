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
        json_agg(json_build_object(
          'id', pi.id, 'producto_id', pi.producto_id, 'nombre_producto', pi.nombre_producto,
          'cantidad', pi.cantidad, 'precio_unitario', pi.precio_unitario, 'detalles', pi.detalles
        )) FILTER (WHERE pi.id IS NOT NULL) as pedido_items
       FROM pedidos p
       LEFT JOIN pedido_items pi ON pi.pedido_id = p.id
       WHERE p.negocio_id = $1
       GROUP BY p.id ORDER BY p.created_at DESC LIMIT $2`,
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
        json_agg(json_build_object(
          'id', pi.id, 'producto_id', pi.producto_id, 'nombre_producto', pi.nombre_producto,
          'cantidad', pi.cantidad, 'precio_unitario', pi.precio_unitario, 'detalles', pi.detalles
        )) FILTER (WHERE pi.id IS NOT NULL) as pedido_items
      FROM pedidos p
      LEFT JOIN pedido_items pi ON pi.pedido_id = p.id
      WHERE p.negocio_id = $1
    `;
    const params: string[] = [req.negocioId!];
    let paramIdx = 2;

    if (startDate) {
      sql += ` AND p.created_at >= $${paramIdx++}`;
      params.push(startDate as string);
    }
    if (endDate) {
      sql += ` AND p.created_at <= $${paramIdx++}`;
      params.push(endDate as string);
    }
    if (status) {
      sql += ` AND p.estado = $${paramIdx++}`;
      params.push(status as string);
    }

    sql += " GROUP BY p.id ORDER BY p.created_at DESC";

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
      "SELECT estado FROM pedidos WHERE id = $1 AND negocio_id = $2",
      [req.params.id, req.negocioId]
    );

    const { rows, rowCount } = await query(
      "UPDATE pedidos SET estado = $1 WHERE id = $2 AND negocio_id = $3 RETURNING *",
      [nuevoEstado, req.params.id, req.negocioId]
    );

    if (!rowCount) return res.status(404).json({ error: "Pedido no encontrado" });

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
      "SELECT recepcion_pausada FROM negocios WHERE id = $1",
      [req.negocioId]
    );

    if (!current[0]) return res.status(404).json({ error: "Negocio no encontrado" });

    const nuevoEstado = !current[0].recepcion_pausada;

    await query(
      "UPDATE negocios SET recepcion_pausada = $1, updated_at = now() WHERE id = $2",
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
      "SELECT recepcion_pausada FROM negocios WHERE id = $1",
      [negocio_id]
    );

    if (!negocio[0]) {
      return res.status(404).json({ error: "Negocio no encontrado" });
    }

    if (negocio[0].recepcion_pausada) {
      return res.status(403).json({ error: "La recepción de pedidos está pausada." });
    }

    // Use atomic RPC
    const { rows } = await query(
      "SELECT submit_order_atomic($1, $2, $3, $4, $5, $6, $7, $8) as pedido_id",
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
