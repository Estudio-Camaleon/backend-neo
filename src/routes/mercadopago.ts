import { Router, Request, Response } from "express";
import { query } from "../lib/db";
import { requireAuth } from "../middleware/auth";
import { resolveTenant } from "../middleware/tenant";
import { verifyMercadoPagoSignature, getMercadoPagoNotificationId } from "../lib/mercadopago";

const router = Router();

const MP_ACCESS_TOKEN = process.env.MERCADO_PAGO_ACCESS_TOKEN;
const MP_WEBHOOK_SECRET = process.env.MERCADO_PAGO_WEBHOOK_SECRET;

function getMPClient() {
  if (!MP_ACCESS_TOKEN) return null;
  // Dynamic import to avoid errors if mercadopago is not installed
  try {
    const { MercadoPagoConfig, PreApproval } = require("mercadopago");
    const client = new MercadoPagoConfig({ accessToken: MP_ACCESS_TOKEN });
    return { client, PreApproval };
  } catch {
    return null;
  }
}

// Create preapproval (requires auth)
router.post("/create-preapproval", requireAuth, resolveTenant, async (req: Request, res: Response) => {
  const mp = getMPClient();
  if (!mp) {
    return res.status(501).json({ error: "Mercado Pago no configurado" });
  }

  try {
    const { rows: negocios } = await query(
      "SELECT id, mp_customer_id FROM negocios WHERE id = $1",
      [req.negocioId]
    );

    const negocio = negocios[0];
    if (!negocio) {
      return res.status(404).json({ error: "Negocio no encontrado" });
    }

    const backUrl = process.env.MERCADO_PAGO_BACK_URL || "http://localhost:3000";

    const preApproval = new mp.PreApproval(mp.client);
    const result = await preApproval.create({
      body: {
        reason: "NEO PRO - Plan Mensual",
        auto_recurring: {
          frequency: 1,
          frequency_type: "months",
          transaction_amount: 15,
          currency_id: "ARS",
        },
        back_url: `${backUrl}/configuracion`,
        external_reference: negocio.id,
      },
    });

    if (!result.id) {
      throw new Error("No se obtuvo ID de preaprobación");
    }

    await query(
      "UPDATE negocios SET mp_subscription_id = $1, mp_status = 'pending', subscription_status = 'pending' WHERE id = $2",
      [result.id, negocio.id]
    );

    return res.json({ url: (result as any).init_point });
  } catch (err) {
    console.error("[MP CREATE PREAPPROVAL]", err);
    return res.status(500).json({ error: "Error al crear suscripción" });
  }
});

// Webhook (no auth - verified by signature)
router.post("/webhook", async (req: Request, res: Response) => {
  try {
    const bodyText = JSON.stringify(req.body);
    const contentType = req.headers["content-type"] || "";

    if (!MP_WEBHOOK_SECRET) {
      console.error("[MP WEBHOOK] MERCADO_PAGO_WEBHOOK_SECRET not configured — rejecting webhook");
      return res.status(501).json({ error: "Webhook not configured" });
    }

    const xSignature = req.headers["x-signature"] as string;
    const xRequestId = req.headers["x-request-id"] as string;

    if (!xSignature || !xRequestId) {
      return res.status(401).json({ error: "Missing webhook signature" });
    }

    const isValid = verifyMercadoPagoSignature({
      signature: xSignature,
      requestId: xRequestId,
      secret: MP_WEBHOOK_SECRET,
    });

    if (!isValid) {
      console.error("[MP WEBHOOK] Invalid signature");
      return res.status(401).json({ error: "Invalid signature" });
    }

    const notificationId = getMercadoPagoNotificationId(contentType, bodyText);
    const topic = req.body?.type || req.body?.topic;
    const dataId = req.body?.data?.id || notificationId;

    if (topic === "subscription_preapproval" && dataId) {
      await handlePreApprovalNotification(String(dataId));
    }

    return res.json({ received: true });
  } catch (err) {
    console.error("[MP WEBHOOK]", err);
    return res.status(500).json({ error: "Webhook error" });
  }
});

async function handlePreApprovalNotification(preapprovalId: string) {
  const mp = getMPClient();
  if (!mp) return;

  try {
    const preApproval = new mp.PreApproval(mp.client);
    const sub = await preApproval.get({ id: preapprovalId });

    const mpStatus = sub.status || "unknown";
    const planTier = mpStatus === "authorized" ? "pro" : "free";
    const subscriptionStatus = mpStatus === "authorized" ? "active" :
      mpStatus === "cancelled" ? "canceled" : mpStatus;

    await query(
      `UPDATE negocios SET
        mp_subscription_id = $1, mp_status = $2, subscription_status = $3,
        plan_tier = $4, mp_customer_id = $5,
        current_period_ends_at = $6
       WHERE mp_subscription_id = $1`,
      [
        preapprovalId, mpStatus, subscriptionStatus, planTier,
        sub.payer_id?.toString() || null,
        mpStatus === "authorized" ? new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString() : null,
      ]
    );
  } catch (err) {
    console.error("[MP] Error handling preapproval:", err);
  }
}

export default router;
