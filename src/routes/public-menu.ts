import { Router, Request, Response } from "express";
import { query } from "../lib/db";

const router = Router();

router.get("/:slug", async (req: Request, res: Response) => {
  try {
    const { slug } = req.params;
    if (!slug) return res.status(400).json({ error: "Slug requerido" });

    const { rows: negocios } = await query(
      `SELECT id, nombre, descripcion, slug, color_primary, banner_url,
              banner_posicion, banner_height, banner_scale,
              logo_url, logo_scale, logo_posicion, logo_fit, logo_shape,
              mostrar_nombre, direccion, localidad, direccion_notas, direcciones,
              whatsapp, instagram_url, facebook_url, tiktok_url, twitter_url,
              youtube_url, tripadvisor_url, horarios, recepcion_pausada,
              tipo_envio, costo_envio, pedido_minimo, moneda_simbolo,
              whatsapp_mensajes
       FROM negocios WHERE LOWER(slug) = LOWER(?) LIMIT 1`,
      [slug]
    );

    if (!negocios[0]) return res.status(404).json({ error: "Negocio no encontrado" });

    const negocio = negocios[0];

    const { rows: categorias } = await query(
      `SELECT c.id, c.nombre, c.slug,
  IFNULL(
    (SELECT JSON_ARRAYAGG(JSON_OBJECT(
      'id', p.id, 'nombre', p.nombre, 'descripcion', p.descripcion,
      'precio', p.precio, 'imagen_url', p.imagen_url,
      'disponible', p.disponible, 'configuracion', p.configuracion
    ) ORDER BY p.nombre) FROM productos p WHERE p.categoria_id = c.id AND p.disponible = true),
    '[]'
  ) AS productos
FROM categorias c
WHERE c.negocio_id = ?
ORDER BY c.nombre`,
      [negocio.id]
    );

    const { rows: uncategorized } = await query(
      `SELECT id, nombre, descripcion, precio, imagen_url, disponible, configuracion
       FROM productos
       WHERE negocio_id = ? AND categoria_id IS NULL AND disponible = true
       ORDER BY nombre`,
      [negocio.id]
    );

    const { rows: promos } = await query(
      `SELECT * FROM promos
       WHERE negocio_id = ? AND activo = true
       ORDER BY created_at DESC`,
      [negocio.id]
    );

    return res.json({
      negocio,
      categorias,
      uncategorizedProducts: uncategorized,
      promos,
    });
  } catch (err) {
    console.error("[PUBLIC-MENU] Error:", err);
    return res.status(500).json({ error: "Error al obtener menú" });
  }
});

export default router;
