import { Router, Request, Response } from "express";
import { query } from "../lib/db";
import { requireAuth } from "../middleware/auth";

const router = Router();
router.use(requireAuth);

router.get("/", async (req: Request, res: Response) => {
  try {
    const { rows: negocios } = await query(
      "SELECT * FROM negocios WHERE user_id = ? LIMIT 1",
      [req.user!.userId]
    );
    if (!negocios[0]) return res.status(404).json({ error: "Negocio no encontrado" });
    return res.json(negocios[0]);
  } catch (err) {
    return res.status(500).json({ error: "Error al obtener configuración" });
  }
});

router.put("/", async (req: Request, res: Response) => {
  try {
    const {
      id, nombre, slug, whatsapp, descripcion, direccion, localidad, direccion_notas,
      color_primary, logo_url, logo_scale, logo_posicion, logo_fit, logo_shape,
      banner_url, banner_posicion, banner_height, banner_scale, mostrar_nombre,
      instagram_url, facebook_url, tiktok_url, twitter_url, youtube_url,
      horarios, direcciones, whatsapp_mensajes, tipo_envio, costo_envio, pedido_minimo, moneda_simbolo,
    } = req.body;

    if (!id) return res.status(400).json({ error: "ID requerido" });

    // Verify ownership
    const { rows: current } = await query(
      "SELECT id, logo_url, banner_url FROM negocios WHERE id = ? AND user_id = ?",
      [id, req.user!.userId]
    );
    if (!current[0]) return res.status(403).json({ error: "Acceso denegado" });

    // Generate clean slug
    const cleanSlug = (slug || "")
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9-]/g, "-")
      .replace(/-+/g, "-")
      .replace(/(^-|-$)/g, "");

    if (cleanSlug.length < 3) {
      return res.status(400).json({ error: "El slug es demasiado corto" });
    }

    // Check slug uniqueness
    const slugCheck = await query(
      "SELECT id FROM negocios WHERE slug = ? AND id != ?",
      [cleanSlug, id]
    );
    if (slugCheck.rows[0]) {
      return res.status(409).json({ error: "El slug ya está en uso por otra marca." });
    }

    const result = await query(
      `UPDATE negocios SET
        nombre = ?, slug = ?, whatsapp = ?, descripcion = ?, direccion = ?,
        localidad = ?, direccion_notas = ?, color_primary = ?, logo_url = ?,
        logo_scale = ?, logo_posicion = ?, logo_fit = ?, logo_shape = ?,
        banner_url = ?, banner_posicion = ?, banner_height = ?, banner_scale = ?,
        mostrar_nombre = ?, instagram_url = ?, facebook_url = ?, tiktok_url = ?,
        twitter_url = ?, youtube_url = ?, horarios = ?, direcciones = ?,
        whatsapp_mensajes = ?, tipo_envio = ?, costo_envio = ?, pedido_minimo = ?,
        moneda_simbolo = ?, updated_at = NOW()
       WHERE id = ? AND user_id = ?`,
      [
        nombre?.trim(), cleanSlug, whatsapp?.trim(), descripcion?.trim(),
        direccion?.trim(), localidad?.trim(), direccion_notas?.trim(), color_primary,
        logo_url, logo_scale || 1, logo_posicion || 'centro', logo_fit || 'cover', logo_shape || 'rectangulo',
        banner_url, banner_posicion || 'centro', banner_height || '200px', banner_scale || 1,
        mostrar_nombre !== false,
        instagram_url?.trim() || '', facebook_url?.trim() || '', tiktok_url?.trim() || '',
        twitter_url?.trim() || '', youtube_url?.trim() || '',
        horarios ? JSON.stringify(horarios) : null,
        direcciones ? JSON.stringify(direcciones) : '[]',
        whatsapp_mensajes ? JSON.stringify(whatsapp_mensajes) : null,
        tipo_envio || 'delivery', costo_envio || 0, pedido_minimo || 0,
        moneda_simbolo || '$',
        id, req.user!.userId,
      ]
    );

    if (result.affectedRows === 0) return res.status(500).json({ error: "Error al actualizar" });

    const { rows: updatedNegocio } = await query(
      "SELECT * FROM negocios WHERE id = ? AND user_id = ?",
      [id, req.user!.userId]
    );
    return res.json({ success: true, slug: cleanSlug, negocio: updatedNegocio[0] });
  } catch (err) {
    console.error("[BRANDING] Error:", err);
    return res.status(500).json({ error: "Error al actualizar branding" });
  }
});

// Delete business
router.delete("/", async (req: Request, res: Response) => {
  try {
    const { id, reason } = req.body;
    if (!id) return res.status(400).json({ error: "ID requerido" });

    const { rows: current } = await query(
      "SELECT id, slug FROM negocios WHERE id = ? AND user_id = ?",
      [id, req.user!.userId]
    );
    if (!current[0]) return res.status(403).json({ error: "Acceso denegado" });

    // Save deletion reason
    if (reason) {
      await query("UPDATE negocios SET deletion_reason = ? WHERE id = ? AND user_id = ?", [reason, id, req.user!.userId]);
    }

    // Use atomic deletion function
    await query("CALL eliminar_negocio_completo(?)", [id]);

    return res.json({ success: true });
  } catch (err) {
    console.error("[BRANDING] Delete error:", err);
    return res.status(500).json({ error: "Error al eliminar negocio" });
  }
});

export default router;
