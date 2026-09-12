import { query } from "./db";

type AuditAccion = "create" | "update" | "delete";
type AuditEntidad =
  | "producto"
  | "categoria"
  | "pedido"
  | "negocio"
  | "configuracion"
  | "cliente";

export async function logAuditEvent(params: {
  negocio_id: string;
  user_id: string;
  accion: AuditAccion;
  entidad: AuditEntidad;
  entidad_id?: string;
  cambios_previos?: Record<string, unknown> | null;
  cambios_nuevos?: Record<string, unknown> | null;
  ip_address?: string;
}) {
  try {
    await query(
      `INSERT INTO audit_logs (negocio_id, user_id, accion, entidad, entidad_id, cambios_previos, cambios_nuevos, ip_address)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        params.negocio_id,
        params.user_id,
        params.accion,
        params.entidad,
        params.entidad_id || null,
        params.cambios_previos ? JSON.stringify(params.cambios_previos) : null,
        params.cambios_nuevos ? JSON.stringify(params.cambios_nuevos) : null,
        params.ip_address || null,
      ]
    );
  } catch {
    // audit logging never blocks the main flow
  }
}
