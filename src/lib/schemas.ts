import { z } from "zod";

const passwordSchema = z
  .string()
  .min(8, "La contraseña debe tener al menos 8 caracteres")
  .regex(/[A-Z]/, "Debe incluir al menos una mayúscula")
  .regex(/[0-9]/, "Debe incluir al menos un número")
  .regex(/[^A-Za-z0-9]/, "Debe incluir al menos un símbolo especial");

export const loginSchema = z.object({
  email: z
    .string()
    .min(1, "El correo es obligatorio")
    .email("El correo no tiene un formato válido")
    .transform((v) => v.trim().toLowerCase()),
  password: z
    .string()
    .min(1, "La contraseña es obligatoria")
    .transform((v) => v.trim()),
});

export const registerSchema = z.object({
  email: z
    .string()
    .email("El correo no tiene un formato válido")
    .transform((v) => v.trim().toLowerCase()),
  password: passwordSchema,
  firstName: z
    .string()
    .min(2, "El nombre debe tener al menos 2 caracteres")
    .max(60, "El nombre es demasiado largo")
    .transform((v) => v.trim()),
  lastName: z
    .string()
    .min(2, "El apellido debe tener al menos 2 caracteres")
    .max(60, "El apellido es demasiado largo")
    .transform((v) => v.trim()),
  phone: z
    .string()
    .regex(/^\+?\d{7,15}$/, "Ingresa un número válido con código de país"),
  referralSource: z.string().optional(),
  nombreNegocio: z
    .string()
    .min(2, "El nombre debe tener al menos 2 caracteres")
    .max(100, "El nombre es demasiado largo")
    .transform((v) => v.trim()),
  slug: z
    .string()
    .min(2, "El slug debe tener al menos 2 caracteres")
    .max(60, "El slug es demasiado largo")
    .regex(/^[a-z0-9-]+$/, "Solo minúsculas, números y guiones")
    .transform((v) => v.trim().toLowerCase()),
  whatsapp: z
    .string()
    .regex(/^\+?\d{7,15}$/, "Ingresa un número válido con código de país")
    .optional()
    .or(z.literal("")),
});

const productVariantSchema = z.object({
  nombre: z.string().min(1),
  precio: z.number().min(0),
});

const extraItemSchema = z.object({
  id: z.string(),
  nombre: z.string(),
  precio: z.number(),
  icono: z.string().optional(),
});

const extraGroupSchema = z.object({
  id: z.string(),
  titulo: z.string(),
  requerido: z.boolean(),
  multiple: z.boolean(),
  items: z.array(extraItemSchema),
});

const productConfigSchema = z.object({
  variantes: z.array(productVariantSchema).default([]),
  grupos_opciones: z.array(extraGroupSchema).default([]),
  imagenes_extra: z.array(z.string()).default([]),
});

export const upsertProductSchema = z.object({
  nombre: z.string().min(1, "El nombre del producto es requerido").max(200),
  descripcion: z.string().nullable().optional(),
  precio: z.number().min(0, "El precio no puede ser negativo"),
  imagen_url: z.string().nullable().optional(),
  categoria_id: z.string().nullable().optional(),
  disponible: z.boolean(),
  stock: z.number().int().min(0).default(0),
  stock_minimo: z.number().int().min(0).default(5),
  configuracion: productConfigSchema.optional(),
});

const comboItemSchema = z.object({
  producto_id: z.string().min(1),
  nombre_producto: z.string().min(1),
  cantidad: z.number().int().positive(),
  precio: z.number().min(0),
});

export const upsertPromoSchema = z.object({
  nombre: z.string().min(1).max(100),
  descripcion: z.string().max(300).nullable().optional(),
  imagen_url: z.string().nullable().optional(),
  tipo_descuento: z.enum(["porcentaje", "monto_fijo", "combo"]),
  valor_descuento: z.number().min(0).max(999999),
  codigo: z.string().max(30).regex(/^[A-Za-z0-9_-]+$/).nullable().optional(),
  activo: z.boolean().default(true),
  fecha_inicio: z.string().nullable().optional(),
  fecha_fin: z.string().nullable().optional(),
  items_combo: z.array(comboItemSchema).default([]),
  aplicar_a: z
    .object({
      productos: z.array(z.string()).default([]),
      categorias: z.array(z.string()).default([]),
    })
    .nullable()
    .optional()
    .default(null),
});

export const updateOrderStatusSchema = z.object({
  pedidoId: z.string().min(1),
  nuevoEstado: z.enum(["pendiente", "en_preparacion", "entregado", "cancelado"]),
});

export const submitOrderSchema = z.object({
  negocio_id: z.string().min(1),
  cliente_nombre: z.string().min(1),
  cliente_whatsapp: z.string().min(1),
  es_delivery: z.boolean(),
  direccion_entrega: z.string().nullable().optional(),
  metodo_pago: z.enum(["efectivo", "transferencia"]),
  notas: z.string().nullable().optional(),
  items: z
    .array(
      z.object({
        producto_id: z.string().min(1),
        cantidad: z.number().int().positive(),
        detalles: z.string().nullable().optional(),
      })
    )
    .min(1),
});

export type LoginInput = z.infer<typeof loginSchema>;
export type RegisterInput = z.infer<typeof registerSchema>;
export type UpsertProductInput = z.infer<typeof upsertProductSchema>;
export type UpsertPromoInput = z.infer<typeof upsertPromoSchema>;
export type UpdateOrderStatusInput = z.infer<typeof updateOrderStatusSchema>;
export type SubmitOrderInput = z.infer<typeof submitOrderSchema>;
