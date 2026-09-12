import { Request, Response, NextFunction } from "express";
import { query } from "../lib/db";

declare global {
  namespace Express {
    interface Request {
      negocioId?: string;
    }
  }
}

export async function resolveTenant(
  req: Request,
  res: Response,
  next: NextFunction
) {
  if (!req.user) {
    return res.status(401).json({ error: "No autenticado" });
  }

  try {
    const requestedNegocioId = req.query.negocio_id as string | undefined;

    if (requestedNegocioId) {
      const ownerCheck = await query(
        "SELECT id FROM negocios WHERE id = ? AND user_id = ?",
        [requestedNegocioId, req.user.userId]
      );
      if (ownerCheck.rows[0]) {
        req.negocioId = requestedNegocioId;
        return next();
      }

      const memberCheck = await query(
        "SELECT negocio_id FROM team_members WHERE user_id = ? AND negocio_id = ?",
        [req.user.userId, requestedNegocioId]
      );
      if (memberCheck.rows[0]) {
        req.negocioId = requestedNegocioId;
        return next();
      }

      return res.status(403).json({ error: "No tienes acceso a este negocio" });
    }

    const ownerResult = await query(
      "SELECT id FROM negocios WHERE user_id = ? ORDER BY created_at ASC LIMIT 1",
      [req.user.userId]
    );

    if (ownerResult.rows[0]) {
      req.negocioId = ownerResult.rows[0].id;
      return next();
    }

    const memberResult = await query(
      "SELECT negocio_id FROM team_members WHERE user_id = ? ORDER BY created_at ASC LIMIT 1",
      [req.user.userId]
    );

    if (memberResult.rows[0]?.negocio_id) {
      req.negocioId = memberResult.rows[0].negocio_id;
      return next();
    }

    return res.status(403).json({ error: "Negocio no asignado" });
  } catch (err) {
    console.error("[TENANT] Error resolving tenant:", err);
    return res.status(500).json({ error: "Error de servidor" });
  }
}
