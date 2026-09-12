import express from "express";
import cors from "cors";
import path from "path";

// Routes
import authRoutes from "./routes/auth";
import catalogRoutes from "./routes/catalog";
import ordersRoutes from "./routes/orders";
import brandingRoutes from "./routes/branding";
import clientsRoutes from "./routes/clients";
import promosRoutes from "./routes/promos";
import notificationsRoutes from "./routes/notifications";
import statsRoutes from "./routes/stats";
import uploadsRoutes from "./routes/uploads";
import mercadopagoRoutes from "./routes/mercadopago";
import publicMenuRoutes from "./routes/public-menu";

const app = express();
const PORT = process.env.PORT || 4000;
const CORS_ORIGIN = process.env.CORS_ORIGIN || "http://localhost:3000";

// Middleware
app.use(cors({ origin: CORS_ORIGIN, credentials: true }));
app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true }));

// Serve uploaded files statically
app.use("/uploads", express.static(path.join(__dirname, "../uploads")));

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

// API Routes
app.use("/api/auth", authRoutes);
app.use("/api/catalog", catalogRoutes);
app.use("/api/orders", ordersRoutes);
app.use("/api/branding", brandingRoutes);
app.use("/api/clients", clientsRoutes);
app.use("/api/promos", promosRoutes);
app.use("/api/notifications", notificationsRoutes);
app.use("/api/stats", statsRoutes);
app.use("/api/uploads", uploadsRoutes);
app.use("/api/mercadopago", mercadopagoRoutes);
app.use("/api/public-menu", publicMenuRoutes);

// 404 handler
app.use((_req, res) => {
  res.status(404).json({ error: "Ruta no encontrada" });
});

// Error handler
app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error("[API] Unhandled error:", err);
  res.status(500).json({ error: "Error interno del servidor" });
});

app.listen(PORT, () => {
  console.log(`[NEO API] Running on http://localhost:${PORT}`);
});

export default app;
