package main

import "testing"

func TestExplicitOperationRequired(t *testing.T) {
	for _, tc := range []struct{ initialize, check bool }{{false, false}, {true, true}, {true, false}, {false, true}} {
		if run("", tc.initialize, tc.check, "", "") == nil {
			t.Fatal("missing private config or operation accepted")
		}
	}
	if run("missing.json", true, false, "", "") == nil {
		t.Fatal("initialization accepted runtime credentials")
	}
}
