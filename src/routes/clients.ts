import { Router, Request, Response } from "express";
import { query } from "../lib/db";
import { requireAuth } from "../middleware/auth";
import { resolveTenant } from "../middleware/tenant";

const router = Router();
router.use(requireAuth, resolveTenant);

router.get("/", async (req: Request, res: Response) => {
  try {
    const { rows } = await query(
      "SELECT * FROM clientes WHERE negocio_id = $1 ORDER BY nombre",
      [req.negocioId]
    );
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ error: "Error al obtener clientes" });
  }
});

router.put("/:id/notes", async (req: Request, res: Response) => {
  try {
    const { notas } = req.body;
    const { rowCount } = await query(
      "UPDATE clientes SET notas = $1 WHERE id = $2 AND negocio_id = $3",
      [notas?.trim() || "", req.params.id, req.negocioId]
    );
    if (!rowCount) return res.status(404).json({ error: "Cliente no encontrado" });
    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: "Error al actualizar notas" });
  }
});

router.delete("/:id", async (req: Request, res: Response) => {
  try {
    const { rowCount } = await query(
      "DELETE FROM clientes WHERE id = $1 AND negocio_id = $2",
      [req.params.id, req.negocioId]
    );
    if (!rowCount) return res.status(404).json({ error: "Cliente no encontrado" });
    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: "Error al eliminar cliente" });
  }
});

export default router;
