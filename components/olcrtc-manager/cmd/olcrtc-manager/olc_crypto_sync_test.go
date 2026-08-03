package main

import "testing"

func TestOlcDesiredCryptoStatePerClientTypes(t *testing.T) {
	for _, randType := range []int{1, 2} {
		cfg := Config{
			RandomizationSecret: "secret",
			GlobalSettings: &GlobalSettings{Subscription: &SubscriptionSettings{RandScope: "both"}},
			Clients: []Client{{
				ClientID: "client-a",
				Randomization: &ClientRandomization{Enabled: true, RandType: randType},
			}},
		}
		state := olcDesiredCryptoState(cfg)
		got, ok := state.Clients["client-a"]
		if !ok || !got.Enabled || got.RandType != randType || state.Secret != "secret" {
			t.Fatalf("type=%d state=%+v", randType, state)
		}
	}
}

func TestOlcDesiredCryptoStateClientIDScopeDisablesCrypto(t *testing.T) {
	cfg := Config{
		RandomizationSecret: "secret",
		GlobalSettings: &GlobalSettings{Subscription: &SubscriptionSettings{
			RandScope: "client_id", RandomizationEnabled: true, RandType: 2,
		}},
		Clients: []Client{{
			ClientID: "client-a",
			Randomization: &ClientRandomization{Enabled: true, RandType: 2},
		}},
	}
	state := olcDesiredCryptoState(cfg)
	if state.Global.Enabled || len(state.Clients) != 0 {
		t.Fatalf("crypto remained enabled: %+v", state)
	}
}

func TestOlcDesiredCryptoStateGlobalType2(t *testing.T) {
	cfg := Config{
		RandomizationSecret: "secret",
		GlobalSettings: &GlobalSettings{Subscription: &SubscriptionSettings{
			RandScope: "crypto", RandomizationEnabled: true, RandType: 2,
		}},
		Clients: []Client{{ClientID: "client-a"}},
	}
	state := olcDesiredCryptoState(cfg)
	if !state.Global.Enabled || state.Global.RandType != 2 {
		t.Fatalf("global type2 not mirrored: %+v", state)
	}
}
