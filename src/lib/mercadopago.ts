import { createHmac, timingSafeEqual } from "crypto";

export function parseMercadoPagoSignature(signature: string | null): Record<string, string> | null {
  if (!signature) return null;

  const parts = signature.split(",").reduce<Record<string, string>>((acc, part) => {
    const eqIdx = part.indexOf("=");
    if (eqIdx <= 0) return acc;

    const key = part.slice(0, eqIdx).trim();
    const value = part.slice(eqIdx + 1).trim();

    if (key && value) {
      acc[key] = value;
    }

    return acc;
  }, {});

  return Object.keys(parts).length > 0 ? parts : null;
}

export function verifyMercadoPagoSignature(params: {
  signature: string | null;
  requestId: string | null;
  secret: string;
}): boolean {
  const { signature, requestId, secret } = params;
  if (!signature || !requestId || !secret) return false;

  const parsed = parseMercadoPagoSignature(signature);
  if (!parsed) return false;

  const ts = parsed["ts"];
  const v1 = parsed["v1"];
  if (!ts || !v1) return false;

  const payload = `id:${requestId};request-id:${requestId};ts:${ts};`;
  const expected = createHmac("sha256", secret).update(payload).digest("hex");

  const expectedBuf = Buffer.from(expected, "hex");
  const v1Buf = Buffer.from(v1, "hex");
  return expectedBuf.length === v1Buf.length && timingSafeEqual(expectedBuf, v1Buf);
}

export function getMercadoPagoNotificationId(contentType: string, body: string): string | null {
  if (contentType.includes("application/x-www-form-urlencoded")) {
    const params = new URLSearchParams(body);
    return params.get("id");
  }

  try {
    const json = JSON.parse(body) as {
      data?: { id?: string };
      id?: string;
    } | null;

    return json?.data?.id ?? json?.id ?? null;
  } catch {
    return null;
  }
}
