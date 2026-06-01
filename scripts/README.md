# Release Checks

Run the Supabase license smoke test after every Edge Function deployment:

```powershell
.\scripts\test-supabase-license.cmd
```

The test verifies that:

- `validate-license` and `register-store-v2` are configured with `verify_jwt = false`.
- The configured Supabase project is reachable.
- A publishable-key request reaches `validate-license`.
- The server returns the expected application-level invalid-device response.
- A gateway `401 Invalid JWT` failure stops the release.

Build a release APK through the guarded wrapper:

```powershell
.\scripts\build-release-apk.cmd
```

The wrapper runs the smoke test first and builds the APK only when cloud
license communication is healthy.
