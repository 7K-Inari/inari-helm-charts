// Shared env contract for the UI e2e suite. Names and defaults mirror the
// former scripts/e2e/ui-smoke.mjs so the workflow and local runs behave the
// same.

/** Console entry URL (through lib/ui-proxy.mjs; single origin). */
export const UI_BASE = process.env.UI_BASE || "http://127.0.0.1:8080";

/** host:port the browser is redirected to for the Keycloak login. */
export const KC_HOST = process.env.KC_HOST || "127.0.0.1:18091";

/** Base URL for direct-grant tokens / KC admin calls (non-browser). */
export const KC_URL = process.env.KC_URL || `http://${KC_HOST}`;

/** Keycloak realm. */
export const KC_REALM = process.env.KC_REALM || "inari";

/** inari-server API base (single-origin via ui-proxy by default). */
export const API_BASE = process.env.API_BASE || UI_BASE;

/** Tenant card display name the smoke spec clicks. */
export const TENANT_NAME = process.env.TENANT_NAME || "E2E Org";

/** Tenant slug used in API paths (same env name/default as seed-personas.mjs). */
export const TENANT_SLUG = process.env.TENANT || "e2e-org";
