import { Request, Response, NextFunction } from "express";
import { query } from "../lib/db";

declare global {
  namespace Express {
    interface Request {
      negocioId?: string;
    }
  }
}

/**
 * Resolves the authenticated user's negocio (tenant).
 * Supports explicit negocio_id query param for users who are owners of one
 * negocio AND team_members of another. Falls back to the first owned negocio.
 */
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
      // Validate the user has access to this specific negocio
      const ownerCheck = await query(
        "SELECT id FROM negocios WHERE id = $1 AND user_id = $2",
        [requestedNegocioId, req.user.userId]
      );
      if (ownerCheck.rows[0]) {
        req.negocioId = requestedNegocioId;
        return next();
      }

      const memberCheck = await query(
        "SELECT negocio_id FROM team_members WHERE user_id = $1 AND negocio_id = $2",
        [req.user.userId, requestedNegocioId]
      );
      if (memberCheck.rows[0]) {
        req.negocioId = requestedNegocioId;
        return next();
      }

      return res.status(403).json({ error: "No tienes acceso a este negocio" });
    }

    // Default: resolve to owned negocio first (most common case)
    const ownerResult = await query(
      "SELECT id FROM negocios WHERE user_id = $1 ORDER BY created_at ASC LIMIT 1",
      [req.user.userId]
    );

    if (ownerResult.rows[0]) {
      req.negocioId = ownerResult.rows[0].id;
      return next();
    }

    // Fallback: first team membership (with deterministic ordering)
    const memberResult = await query(
      "SELECT negocio_id FROM team_members WHERE user_id = $1 ORDER BY created_at ASC LIMIT 1",
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
