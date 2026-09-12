import { Router, Request, Response } from "express";
import bcrypt from "bcrypt";
import { v4 as uuidv4 } from "uuid";
import { query } from "../lib/db";
import { generateToken, verifyToken } from "../middleware/auth";
import { loginSchema, registerSchema } from "../lib/schemas";
import { checkRateLimit } from "../lib/rate-limit";

const router = Router();

function getClientIP(req: Request): string {
  return (req.headers["x-forwarded-for"] as string) || req.ip || "unknown";
}

router.post("/login", async (req: Request, res: Response) => {
  try {
    const ip = getClientIP(req);
    if (!(await checkRateLimit(`login:${ip}`))) {
      return res.status(429).json({ error: "Demasiados intentos. Inténtalo de nuevo en un minuto." });
    }

    const parsed = loginSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: parsed.error.issues[0]?.message || "Datos inválidos" });
    }

    const { email, password } = parsed.data;

    const { rows } = await query(
      "SELECT id, email, password_hash, first_name, last_name FROM users WHERE email = ?",
      [email]
    );

    const user = rows[0];
    if (!user) {
      return res.status(401).json({ error: "El correo electrónico o la contraseña son incorrectos." });
    }

    const validPassword = await bcrypt.compare(password, user.password_hash);
    if (!validPassword) {
      return res.status(401).json({ error: "El correo electrónico o la contraseña son incorrectos." });
    }

    // Update last login
    await query("UPDATE users SET updated_at = NOW() WHERE id = ?", [user.id]);

    const token = generateToken({ userId: user.id, email: user.email });

    return res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        firstName: user.first_name,
        lastName: user.last_name,
      },
    });
  } catch (err) {
    console.error("[AUTH] Login error:", err);
    return res.status(500).json({ error: "Error interno del servidor" });
  }
});

router.post("/register", async (req: Request, res: Response) => {
  try {
    const ip = getClientIP(req);
    if (!(await checkRateLimit(`register:${ip}`, 20))) {
      return res.status(429).json({ error: "Demasiados intentos. Inténtalo de nuevo en un minuto." });
    }

    const parsed = registerSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: parsed.error.issues[0]?.message || "Datos inválidos" });
    }

    const { email, password, firstName, lastName, phone, referralSource, nombreNegocio, slug, whatsapp } = parsed.data;

    // Check duplicate email
    const emailCheck = await query("SELECT id FROM users WHERE email = ?", [email]);
    if (emailCheck.rows[0]) {
      return res.status(409).json({ error: "El correo electrónico ya está registrado." });
    }

    // Check duplicate slug
    const slugCheck = await query("SELECT id FROM negocios WHERE slug = ?", [slug]);
    if (slugCheck.rows[0]) {
      return res.status(409).json({ error: "El slug ya está en uso. Elegí otro." });
    }

    // Check duplicate business name
    const nameCheck = await query("SELECT id FROM negocios WHERE nombre = ?", [nombreNegocio]);
    if (nameCheck.rows[0]) {
      return res.status(409).json({ error: "El nombre del negocio ya está registrado." });
    }

    // Check duplicate phone
    const phoneCheck = await query("SELECT id FROM negocios WHERE phone = ?", [phone]);
    if (phoneCheck.rows[0]) {
      return res.status(409).json({ error: "El celular ya está registrado por otro usuario." });
    }

    // Hash password
    const passwordHash = await bcrypt.hash(password, 12);

    // Create user
    const userId = uuidv4();
    await query(
      `INSERT INTO users (id, email, password_hash, first_name, last_name, phone, email_confirmed)
       VALUES (?, ?, ?, ?, ?, ?, true)`,
      [userId, email, passwordHash, firstName, lastName, phone]
    );

    const userResult = await query(
      "SELECT id, email, first_name, last_name FROM users WHERE id = ?",
      [userId]
    );
    const newUser = userResult.rows[0];

    // Create negocio
    await query(
      `INSERT INTO negocios (user_id, nombre, slug, phone, referral_source, whatsapp)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [newUser.id, nombreNegocio, slug, phone, referralSource || null, whatsapp || null]
    );

    const token = generateToken({ userId: newUser.id, email: newUser.email });

    return res.status(201).json({
      token,
      user: {
        id: newUser.id,
        email: newUser.email,
        firstName: newUser.first_name,
        lastName: newUser.last_name,
      },
    });
  } catch (err) {
    console.error("[AUTH] Register error:", err);
    return res.status(500).json({ error: "Error interno del servidor" });
  }
});

router.post("/check-duplicate", async (req: Request, res: Response) => {
  try {
    const ip = getClientIP(req);
    if (!(await checkRateLimit(`check:${ip}`, 30))) {
      return res.status(429).json({ error: "Demasiadas solicitudes" });
    }

    const { field, value } = req.body;
    if (!field || !value) {
      return res.json({ exists: false });
    }

    const cleanValue = String(value).replace(/\s+/g, " ").trim();
    if (!cleanValue) return res.json({ exists: false });

    if (field === "email") {
      const { rows } = await query("SELECT id FROM users WHERE LOWER(email) = LOWER(?)", [cleanValue]);
      return res.json({ exists: rows.length > 0 });
    }

    const allowed = ["nombre", "slug", "phone"];
    if (!allowed.includes(field)) return res.json({ exists: false });

    const { rows } = await query(
      `SELECT id, nombre FROM negocios WHERE ${field} LIKE ? LIMIT 1`,
      [cleanValue]
    );
    return res.json({ exists: rows.length > 0 });
  } catch {
    return res.json({ exists: false });
  }
});

router.post("/reset-password", async (req: Request, res: Response) => {
  try {
    const ip = getClientIP(req);
    if (!(await checkRateLimit(`reset:${ip}`, 3))) {
      return res.status(429).json({ error: "Demasiados intentos" });
    }

    const { email } = req.body;
    if (!email) {
      return res.status(400).json({ error: "Email requerido" });
    }

    // In a full implementation, you'd send a reset email here
    // For now, just return success to prevent email enumeration
    return res.json({ success: true });
  } catch {
    return res.json({ success: true });
  }
});

router.get("/me", async (req: Request, res: Response) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith("Bearer ")) {
    return res.status(401).json({ error: "No autenticado" });
  }

  try {
    const token = authHeader.split(" ")[1];
    const payload = verifyToken(token);

    const { rows } = await query(
      "SELECT id, email, first_name, last_name, phone FROM users WHERE id = ?",
      [payload.userId]
    );

    if (!rows[0]) {
      return res.status(404).json({ error: "Usuario no encontrado" });
    }

    return res.json({ user: rows[0] });
  } catch {
    return res.status(401).json({ error: "Token inválido" });
  }
});

export default router;
