// Package kc is a thin Keycloak admin/token client. Every call runs curl
// inside the cluster's toolbox pod (same transport as golden-path.sh), so no
// port-forwards are needed.
package kc

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strings"

	"7k-inari/inari-release-bundle/scripts/e2e/stack/internal/kube"
)

// Client talks to the realm `inari` on keycloak-service.<ns>.svc:8080.
type Client struct {
	NS      string // stack namespace (e.g. "inari")
	Toolbox string // toolbox pod name (curl host)
}

func (c *Client) base() string { return "http://keycloak-service:8080" }

func (c *Client) get(path, token string, out any) error {
	var args []string
	if token != "" {
		args = append(args, "-H", "Authorization: Bearer "+token)
	}
	args = append(args, c.base()+path)
	body, err := kube.Curl(c.NS, c.Toolbox, args...)
	if err != nil {
		return err
	}
	return json.Unmarshal([]byte(body), out)
}

// RealmIssuer returns the issuer advertised by the realm's OIDC discovery
// document. Issuer convergence after the hostname patch is observable ONLY
// this way — no k8s condition exists for it.
func (c *Client) RealmIssuer() (string, error) {
	var doc struct {
		Issuer string `json:"issuer"`
	}
	if err := c.get("/realms/inari/.well-known/openid-configuration", "", &doc); err != nil {
		return "", err
	}
	return doc.Issuer, nil
}

func (c *Client) tokenEndpoint(form ...string) (string, error) {
	args := []string{c.base() + "/realms/inari/protocol/openid-connect/token"}
	for _, f := range form {
		args = append(args, "-d", f)
	}
	body, err := kube.Curl(c.NS, c.Toolbox, args...)
	if err != nil {
		return "", err
	}
	var resp struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return "", fmt.Errorf("decoding token response: %w (%s)", err, body)
	}
	if resp.AccessToken == "" {
		return "", fmt.Errorf("token response carried no access_token")
	}
	return resp.AccessToken, nil
}

// AdminToken fetches a client-credentials token for inari-platform-admin;
// the client secret comes from the inari-keycloak-admin k8s secret.
func (c *Client) AdminToken() (string, error) {
	secB64, err := kube.Kubectl("-n", c.NS, "get", "secret", "inari-keycloak-admin",
		"-o", "jsonpath={.data.client-secret}")
	if err != nil {
		return "", err
	}
	sec, err := base64.StdEncoding.DecodeString(strings.TrimSpace(secB64))
	if err != nil {
		return "", fmt.Errorf("decoding inari-keycloak-admin client-secret: %w", err)
	}
	return c.tokenEndpoint(
		"grant_type=client_credentials",
		"client_id=inari-platform-admin",
		"client_secret="+string(sec),
	)
}

// UserToken is the dev-admin password grant with the organization scope.
func (c *Client) UserToken() (string, error) {
	return c.PasswordToken("dev-admin", "dev-admin", "openid organization:*")
}

// PasswordToken fetches a direct-grant token for an arbitrary user/scope.
func (c *Client) PasswordToken(username, password, scope string) (string, error) {
	return c.tokenEndpoint(
		"grant_type=password",
		"client_id=inari-server",
		"username="+username,
		"password="+password,
		"scope="+scope,
	)
}

// ClientSecret returns the current secret of the OIDC client with the given
// clientId (e.g. the per-cluster agent client).
func (c *Client) ClientSecret(adminToken, clientID string) (string, error) {
	var clients []struct {
		ID string `json:"id"`
	}
	if err := c.get("/admin/realms/inari/clients?clientId="+clientID, adminToken, &clients); err != nil {
		return "", err
	}
	if len(clients) == 0 {
		return "", fmt.Errorf("keycloak client %q not found", clientID)
	}
	var sec struct {
		Value string `json:"value"`
	}
	if err := c.get("/admin/realms/inari/clients/"+clients[0].ID+"/client-secret", adminToken, &sec); err != nil {
		return "", err
	}
	return sec.Value, nil
}

// Claims decodes the payload of a JWT without verifying it (the suite trusts
// the cluster-internal issuer; it only inspects claims).
func Claims(jwt string) (map[string]any, error) {
	parts := strings.Split(jwt, ".")
	if len(parts) != 3 {
		return nil, fmt.Errorf("not a JWT (%d segments)", len(parts))
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, fmt.Errorf("decoding JWT payload: %w", err)
	}
	var claims map[string]any
	if err := json.Unmarshal(payload, &claims); err != nil {
		return nil, fmt.Errorf("parsing JWT payload: %w", err)
	}
	return claims, nil
}
