package authprivacyruntime

import "testing"

func TestDatabaseDiagnosticsRejectMissingAndUnsafeSettings(t *testing.T) {
	safe := func() map[string]string {
		settings := make(map[string]string, len(privateDatabaseDiagnosticSettings))
		for name, value := range privateDatabaseDiagnosticSettings {
			settings[name] = value
		}
		return settings
	}
	if !privateDatabaseDiagnostics(safe()) || privateDatabaseDiagnostics(nil) {
		t.Fatal("database diagnostics safe/missing boundary failed")
	}
	unsafe := map[string]string{
		"log_statement": "all", "log_min_messages": "error",
		"log_min_error_statement": "error", "log_error_verbosity": "default",
		"log_parameter_max_length": "-1", "log_parameter_max_length_on_error": "-1",
		"log_min_duration_statement": "0", "log_min_duration_sample": "0",
		"log_transaction_sample_rate": "1", "log_duration": "on",
	}
	for name, value := range unsafe {
		t.Run(name, func(t *testing.T) {
			settings := safe()
			settings[name] = value
			if privateDatabaseDiagnostics(settings) {
				t.Fatal("unsafe diagnostic configuration accepted")
			}
			delete(settings, name)
			if privateDatabaseDiagnostics(settings) {
				t.Fatal("missing diagnostic configuration accepted")
			}
		})
	}
}
