// Thin inari-server REST client for setup/assertion READS.
//
// Authenticates with a direct-grant token via the public `inari-server`
// Keycloak client (directAccessGrantsEnabled + audience mapper are
// provisioned by golden-path.sh — same token the golden path itself uses).
// Never use this client to mutate what a spec is supposed to exercise
// through the UI.

import { API_BASE, KC_REALM, KC_URL } from "./env";
import { PERSONAS } from "../fixtures/auth";

interface TokenResponse {
  access_token: string;
  expires_in: number;
}

/** Direct-grant token for a persona (default dev-admin). */
export async function getToken(
  username = PERSONAS.devAdmin.username,
  password = PERSONAS.devAdmin.password,
): Promise<string> {
  const res = await fetch(
    `${KC_URL}/realms/${KC_REALM}/protocol/openid-connect/token`,
    {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "password",
        client_id: "inari-server",
        username,
        password,
        scope: "openid organization:*",
      }),
    },
  );
  if (!res.ok) {
    throw new Error(`api: token request failed: ${res.status} ${await res.text()}`);
  }
  return ((await res.json()) as TokenResponse).access_token;
}

/** Minimal authenticated REST client against the inari-server API. */
export class ApiClient {
  private constructor(
    readonly base: string,
    private readonly token: string,
  ) {}

  static async forPersona(username?: string, password?: string): Promise<ApiClient> {
    return new ApiClient(API_BASE, await getToken(username, password));
  }

  private async request<T>(method: string, path: string): Promise<T> {
    const res = await fetch(`${this.base}${path}`, {
      method,
      headers: { authorization: `Bearer ${this.token}` },
    });
    if (!res.ok) {
      throw new Error(`api: ${method} ${path} failed: ${res.status} ${await res.text()}`);
    }
    return (await res.json()) as T;
  }

  get<T>(path: string): Promise<T> {
    return this.request<T>("GET", path);
  }

  post<T>(path: string): Promise<T> {
    return this.request<T>("POST", path);
  }
}
