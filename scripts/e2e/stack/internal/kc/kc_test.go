package kc

import (
	"encoding/base64"
	"testing"
)

func jwtWithPayload(payload string) string {
	enc := base64.RawURLEncoding
	return enc.EncodeToString([]byte(`{"alg":"none"}`)) + "." +
		enc.EncodeToString([]byte(payload)) + "." +
		enc.EncodeToString([]byte("sig"))
}

func TestClaimsDecodesPayload(t *testing.T) {
	tok := jwtWithPayload(`{"sub":"u1","groups":["/tenant-e2e-org/viewers"]}`)
	claims, err := Claims(tok)
	if err != nil {
		t.Fatalf("Claims: %v", err)
	}
	if claims["sub"] != "u1" {
		t.Fatalf("sub = %v, want u1", claims["sub"])
	}
	groups, ok := claims["groups"].([]any)
	if !ok || len(groups) != 1 || groups[0] != "/tenant-e2e-org/viewers" {
		t.Fatalf("groups = %v, want [/tenant-e2e-org/viewers]", claims["groups"])
	}
}

func TestClaimsRejectsMalformed(t *testing.T) {
	if _, err := Claims("not-a-jwt"); err == nil {
		t.Fatal("Claims(not-a-jwt) succeeded, want error")
	}
	bad := jwtWithPayload("%%%")
	if _, err := Claims(bad); err == nil {
		t.Fatal("Claims with invalid payload encoding succeeded, want error")
	}
	notJSON := jwtWithPayload("aGVsbG8") // "hello", not a JSON object
	if _, err := Claims(notJSON); err == nil {
		t.Fatal("Claims with non-JSON payload succeeded, want error")
	}
}
