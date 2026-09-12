import { Router, Request, Response } from "express";
import { query } from "../lib/db";
import { requireAuth } from "../middleware/auth";
import { resolveTenant } from "../middleware/tenant";

const router = Router();
router.use(requireAuth, resolveTenant);

router.get("/", async (req: Request, res: Response) => {
  try {
    const { rows } = await query(
      "SELECT * FROM notifications WHERE negocio_id = $1 ORDER BY created_at DESC LIMIT 50",
      [req.negocioId]
    );
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ error: "Error al obtener notificaciones" });
  }
});

router.get("/unread-count", async (req: Request, res: Response) => {
  try {
    const { rows } = await query(
      "SELECT COUNT(*) as count FROM notifications WHERE negocio_id = $1 AND read = false",
      [req.negocioId]
    );
    return res.json({ count: parseInt(rows[0].count) });
  } catch (err) {
    return res.status(500).json({ count: 0 });
  }
});

router.patch("/:id/read", async (req: Request, res: Response) => {
  try {
    await query(
      "UPDATE notifications SET read = true WHERE id = $1 AND negocio_id = $2",
      [req.params.id, req.negocioId]
    );
    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: "Error al marcar notificación" });
  }
});

router.patch("/read-all", async (req: Request, res: Response) => {
  try {
    await query(
      "UPDATE notifications SET read = true WHERE negocio_id = $1 AND read = false",
      [req.negocioId]
    );
    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: "Error al marcar notificaciones" });
  }
});

// Preferences
router.get("/preferences", async (req: Request, res: Response) => {
  try {
    const { rows } = await query(
      "SELECT * FROM notification_preferences WHERE negocio_id = $1",
      [req.negocioId]
    );
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ error: "Error al obtener preferencias" });
  }
});

router.put("/preferences", async (req: Request, res: Response) => {
  try {
    const { notification_type, enabled } = req.body;
    if (!notification_type || typeof enabled !== "boolean") {
      return res.status(400).json({ error: "notification_type y enabled requeridos" });
    }
    await query(
      `INSERT INTO notification_preferences (negocio_id, notification_type, enabled)
       VALUES ($1, $2, $3)
       ON CONFLICT (negocio_id, notification_type) DO UPDATE SET enabled = $3`,
      [req.negocioId, notification_type, enabled]
    );
    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: "Error al actualizar preferencias" });
  }
});

export default router;
