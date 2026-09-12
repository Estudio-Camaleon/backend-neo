import { Router, Request, Response } from "express";
import multer from "multer";
import path from "path";
import fs from "fs";
import { requireAuth } from "../middleware/auth";
import { resolveTenant } from "../middleware/tenant";

const UPLOAD_DIR = process.env.UPLOAD_DIR || "./uploads";
const MAX_FILE_SIZE = parseInt(process.env.MAX_FILE_SIZE || "5242880");
if (isNaN(MAX_FILE_SIZE)) {
  console.error("[UPLOADS] MAX_FILE_SIZE is not a valid number");
  process.exit(1);
}

// Ensure upload directories exist
for (const dir of ["products", "branding", "promos"]) {
  fs.mkdirSync(path.join(UPLOAD_DIR, dir), { recursive: true });
}

const storage = multer.diskStorage({
  destination: (_req, file, cb) => {
    const type = _req.path.includes("product") ? "products" :
                 _req.path.includes("branding") ? "branding" : "promos";
    cb(null, path.join(UPLOAD_DIR, type));
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || ".webp";
    const tenantId = req.negocioId || "unknown";
    cb(null, `${tenantId}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: MAX_FILE_SIZE },
  fileFilter: (_req, file, cb) => {
    const allowedMimes = ["image/jpeg", "image/png", "image/gif", "image/webp"];
    if (!allowedMimes.includes(file.mimetype)) {
      return cb(new Error("Solo se permiten archivos de imagen (JPEG, PNG, GIF, WebP)"));
    }
    cb(null, true);
  },
});

const router = Router();

router.post(
  "/product-images",
  requireAuth,
  resolveTenant,
  upload.single("file"),
  async (req: Request, res: Response) => {
    try {
      if (!req.file) {
        return res.status(400).json({ error: "No se recibió archivo" });
      }

      const publicUrl = `/uploads/products/${req.file.filename}`;
      return res.json({ publicUrl });
    } catch (err) {
      return res.status(500).json({ error: "Error al subir imagen" });
    }
  }
);

router.post(
  "/branding-images",
  requireAuth,
  resolveTenant,
  upload.single("file"),
  async (req: Request, res: Response) => {
    try {
      if (!req.file) {
        return res.status(400).json({ error: "No se recibió archivo" });
      }

      const publicUrl = `/uploads/branding/${req.file.filename}`;
      return res.json({ publicUrl });
    } catch (err) {
      return res.status(500).json({ error: "Error al subir imagen" });
    }
  }
);

router.post(
  "/promo-images",
  requireAuth,
  resolveTenant,
  upload.single("file"),
  async (req: Request, res: Response) => {
    try {
      if (!req.file) {
        return res.status(400).json({ error: "No se recibió archivo" });
      }

      const publicUrl = `/uploads/promos/${req.file.filename}`;
      return res.json({ publicUrl });
    } catch (err) {
      return res.status(500).json({ error: "Error al subir imagen" });
    }
  }
);

router.delete("/image", requireAuth, resolveTenant, async (req: Request, res: Response) => {
  try {
    const { filePath } = req.body;
    if (!filePath) return res.status(400).json({ error: "Ruta requerida" });

    const resolved = path.resolve(filePath);
    const uploadsBase = path.resolve(UPLOAD_DIR);

    if (!resolved.startsWith(uploadsBase)) {
      return res.status(403).json({ error: "Acceso denegado" });
    }

    // Verify file belongs to the requesting tenant
    const relativePath = path.relative(uploadsBase, resolved);
    if (!relativePath.startsWith(req.negocioId!)) {
      return res.status(403).json({ error: "Acceso denegado" });
    }

    // Reject symlinks
    try {
      const stat = fs.lstatSync(resolved);
      if (stat.isSymbolicLink()) {
        return res.status(403).json({ error: "Acceso denegado" });
      }
    } catch {
      // File doesn't exist — return success (idempotent delete)
      return res.json({ success: true });
    }

    fs.unlinkSync(resolved);
    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: "Error al eliminar" });
  }
});

export default router;
