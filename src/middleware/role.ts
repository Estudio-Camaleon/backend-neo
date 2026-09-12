import { Request, Response, NextFunction } from "express";
import { query } from "../lib/db";

export type TeamRole = "admin" | "staff" | "viewer";

export function requireRole(allowedRoles: TeamRole[]) {
  return async (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) {
      return res.status(401).json({ error: "No autenticado" });
    }
    if (!req.negocioId) {
      return res.status(403).json({ error: "Negocio no resuelto" });
    }

    const ownerCheck = await query(
      "SELECT id FROM negocios WHERE id = ? AND user_id = ?",
      [req.negocioId, req.user.userId]
    );
    if (ownerCheck.rows[0]) {
      return next();
    }

    const { rows } = await query(
      "SELECT role FROM team_members WHERE user_id = ? AND negocio_id = ? LIMIT 1",
      [req.user.userId, req.negocioId]
    );

    if (!rows[0]) {
      return res.status(403).json({ error: "No tienes acceso a este negocio" });
    }

    const userRole = rows[0].role as TeamRole;
    if (!allowedRoles.includes(userRole)) {
      return res.status(403).json({ error: "No tienes permisos para esta acción" });
    }

    next();
  };
}
