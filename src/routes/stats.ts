import { Router, Request, Response } from "express";
import { query } from "../lib/db";
import { requireAuth } from "../middleware/auth";
import { resolveTenant } from "../middleware/tenant";

const router = Router();
router.use(requireAuth, resolveTenant);

router.get("/dashboard", async (req: Request, res: Response) => {
  try {
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);

    const [pedidosRes, clientesRes, productosRes, categoriasRes] = await Promise.all([
      query(
        "SELECT id, estado, total, cliente_nombre, created_at, es_delivery FROM pedidos WHERE negocio_id = $1 AND created_at >= $2 ORDER BY created_at DESC",
        [req.negocioId, todayStart.toISOString()]
      ),
      query("SELECT COUNT(*) as count FROM clientes WHERE negocio_id = $1", [req.negocioId]),
      query("SELECT COUNT(*) as count FROM productos WHERE negocio_id = $1", [req.negocioId]),
      query("SELECT COUNT(*) as count FROM categorias WHERE negocio_id = $1", [req.negocioId]),
    ]);

    const pedidos = pedidosRes.rows;
    const ventasHoy = pedidos
      .filter((p: any) => p.estado !== "cancelado")
      .reduce((sum: number, p: any) => sum + (Number(p.total) || 0), 0);

    return res.json({
      pedidos,
      ventasHoy,
      totalClientes: parseInt(clientesRes.rows[0].count),
      totalProductos: parseInt(productosRes.rows[0].count),
      totalCategorias: parseInt(categoriasRes.rows[0].count),
    });
  } catch (err) {
    console.error("[STATS] Dashboard error:", err);
    return res.status(500).json({ error: "Error al obtener estadísticas" });
  }
});

router.get("/summary", async (req: Request, res: Response) => {
  try {
    const { startDate, endDate } = req.query;
    if (!startDate || !endDate) {
      return res.status(400).json({ error: "Fechas requeridas" });
    }

    if (isNaN(Date.parse(startDate as string))) {
      return res.status(400).json({ error: "startDate no es una fecha válida" });
    }
    if (isNaN(Date.parse(endDate as string))) {
      return res.status(400).json({ error: "endDate no es una fecha válida" });
    }

    const { rows: orders } = await query(
      `SELECT id, total, estado, metodo_pago, created_at, es_delivery, cliente_nombre
       FROM pedidos WHERE negocio_id = $1 AND created_at >= $2 AND created_at <= $3
       ORDER BY created_at DESC LIMIT 5000`,
      [req.negocioId, startDate, endDate]
    );

    const lista = orders;
    const activeOrders = lista.filter((o: any) => o.estado !== "cancelado");
    const totalRevenue = activeOrders.reduce((s: number, o: any) => s + (Number(o.total) || 0), 0);

    return res.json({
      totalRevenue,
      totalOrders: lista.length,
      avgTicket: activeOrders.length > 0 ? totalRevenue / activeOrders.length : 0,
      pedidos: lista,
    });
  } catch (err) {
    return res.status(500).json({ error: "Error al obtener resumen" });
  }
});

export default router;
