# Releasing Klinote

## Who signs it

**Klinote is a product of DataDab LLP, and every release is signed as DataDab
LLP: team `THC77ZVYVB`.**

That is not cosmetic. The signature is what macOS shows the clinician, it
decides which entity a notarization ticket is issued to, and it is what an
IT department reads when it checks the app. A release signed by a different
team is attributed to a different legal entity, and nothing in the build output
would say so.

`scripts/release.sh` therefore selects the Developer ID **for that team** rather
than whichever one happens to be first in the keychain, and refuses to build if
that team's certificate is absent. If the product ever genuinely moves, set
`RELEASE_TEAM_ID`, move the certificate, and update this file in the same
commit.

## Cutting a release

```bash
scripts/release.sh                       # build, sign, verify, package
NOTARY_PROFILE=klinote scripts/release.sh   # ...and notarize
```

It reads `MARKETING_VERSION` from `apps/Klinote/project.yml`, regenerates the
project, builds Release, verifies the signature, and writes
`dist/Klinote-<version>.zip`. `build/` and `dist/` are ignored by git, so a
packaged app cannot be committed by accident.

To publish:

```bash
git tag -a v0.1.0 -m "Klinote 0.1.0"
git push origin v0.1.0
gh release create v0.1.0 dist/Klinote-0.1.0.zip --notes-file <notes>
```

## Notarization

A Developer ID signature alone is not enough. Gatekeeper answers

```
spctl -a -t exec Klinote.app
  → rejected, source=Unnotarized Developer ID
```

and a clinician who downloads it sees "Apple could not verify". Store the
credentials once — they are per Apple ID and per team, not per project:

```bash
xcrun notarytool store-credentials klinote \
  --apple-id <apple-id> --team-id THC77ZVYVB --password <app-specific-password>
```

Then `NOTARY_PROFILE=klinote scripts/release.sh` submits, waits, staples the
ticket to the app, and re-packages so the zip contains the stapled build.

**Until this is done, every release needs the user to right-click → Open**, or:

```bash
xattr -d com.apple.quarantine /Applications/Klinote.app
```

## Things a local build gets wrong

Both were found by writing this script rather than by reading about it:

- **`get-task-allow`.** Xcode injects this debugging entitlement into anything
  it signs without a distribution profile. It lets a debugger attach to the
  shipped app. `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` turns it off.
- **Ad-hoc signatures work only where they were made.** `CODE_SIGN_IDENTITY=-`
  is what the local build uses and it is fine for development, which is exactly
  why it is easy to ship by mistake.

## Testing a sandboxed build

**Test the signed release build, not a local one.** Keychain access is tied to
the code signature: an item written by the Developer ID build cannot be read by
an ad-hoc build signed with `-`. Because the store key lives in the Keychain, an
ad-hoc sandboxed build therefore cannot open the encrypted database at all — it
shows an empty window with no consults, and it looks exactly like a broken store
rather than a signing mismatch.

So when checking anything to do with the store, the Keychain, or the sandbox,
build with `scripts/release.sh` and test `/Applications/Klinote.app` from that.
`xcodebuild` straight to a derived-data folder will produce an app that cannot
see the data.

A related consequence, since it will bite during development: a debug build
cannot read a release build's key, so the two do not share a database. That is
the signature doing its job, not a bug to work around.

**`defaults delete <bundle-id>` is not the way to remove old preferences.** For a
sandboxed app, cfprefsd resolves that domain to the app's *container*, so the
command wipes the settings the app is actually using — clinician name, whether
setup finished, retention — while leaving the pre-sandbox plist in
`~/Library/Preferences` exactly where it was. It reports success either way. Use
`rm` on the file you actually mean.

Restoring afterwards has to go through cfprefsd too (`defaults write …`); writing
the plist file directly is undone by the cache. After any such command, run
`./scripts/observe.sh` and read the container prefs it prints — that is what the
app will load, and it is the only way to know the command hit the file you meant.

## Architecture

`ARCHS=arm64`, because the Rust engine is compiled by cargo for the host. A
universal build needs a second cargo target, not a second arch flag.

## Models

The app ships **no models**. The first run downloads the note model into
`~/Library/Application Support/Klinote/Models/`; speech recognition needs no
model at all, because it is the system's `SpeechAnalyzer`. A release artifact is
therefore under 20 MB rather than 2.5 GB, and nothing in the repository or the
release carries model weights.
