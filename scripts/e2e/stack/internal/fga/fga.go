// Package fga is a minimal OpenFGA HTTP client (stores + check), running
// curl inside the toolbox pod like every other suite HTTP call.
package fga

import (
	"encoding/json"
	"fmt"

	"7k-inari/inari-release-bundle/scripts/e2e/stack/internal/kube"
)

// Client talks to openfga.<ns>.svc:8080 (no auth in the e2e stack).
type Client struct {
	NS      string
	Toolbox string
}

// Stores returns all OpenFGA stores as (id, name) pairs.
func (c *Client) Stores() ([]struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}, error,
) {
	body, err := kube.Curl(c.NS, c.Toolbox, "http://openfga:8080/stores")
	if err != nil {
		return nil, err
	}
	var resp struct {
		Stores []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		} `json:"stores"`
	}
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return nil, fmt.Errorf("decoding /stores: %w", err)
	}
	return resp.Stores, nil
}

// StoreID returns the id of the first store (the script's stores[0]
// semantics); CountStores lets HA tests assert exactly one store exists.
func (c *Client) StoreID() (string, error) {
	stores, err := c.Stores()
	if err != nil {
		return "", err
	}
	if len(stores) == 0 {
		return "", fmt.Errorf("no OpenFGA stores")
	}
	return stores[0].ID, nil
}

// CountStores returns how many stores carry the given name.
func (c *Client) CountStores(name string) (int, error) {
	stores, err := c.Stores()
	if err != nil {
		return 0, err
	}
	n := 0
	for _, s := range stores {
		if s.Name == name {
			n++
		}
	}
	return n, nil
}

// Check runs an OpenFGA check and returns the allowed flag.
func (c *Client) Check(storeID, user, relation, object string) (bool, error) {
	payload := fmt.Sprintf(
		`{"tuple_key":{"user":%q,"relation":%q,"object":%q}}`, user, relation, object)
	body, err := kube.Curl(c.NS, c.Toolbox,
		"-X", "POST", "-H", "Content-Type: application/json",
		"-d", payload, "http://openfga:8080/stores/"+storeID+"/check")
	if err != nil {
		return false, err
	}
	var resp struct {
		Allowed bool `json:"allowed"`
	}
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return false, fmt.Errorf("decoding check response: %w", err)
	}
	return resp.Allowed, nil
}
