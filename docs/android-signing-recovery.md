# Recover the Android signing key

The release workflow reconstructs the signing keystore from `ANDROID_KEYSTORE_BASE64`. If the local copy is lost, the manual `Recover Android signing key` workflow exports the keystore and signing credentials in a GPG-encrypted artifact. The private recovery key stays on your computer, so downloading the artifact alone does not reveal the signing key.

The workflow requires the four existing `ANDROID_*` signing secrets, GitHub Actions access, and a GPG public key. Locally, install GPG and GitHub CLI, then authenticate with `gh auth login`. The workflow must be present on the repository's default branch before it can be dispatched.

## Generate a local recovery key

Run from the repository root. Use an empty directory for each recovery so an older backup is not overwritten. These commands create an unprotected private key inside a directory accessible only to your user.

```bash
umask 077
recovery_dir="$HOME/.local/share/biomass-signing-recovery/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$recovery_dir/gnupg"
chmod 700 "$recovery_dir" "$recovery_dir/gnupg"
gpg --homedir "$recovery_dir/gnupg" --batch --pinentry-mode loopback \
  --passphrase '' --quick-generate-key 'Biomass signing recovery' rsa3072 encr 0
gpg --homedir "$recovery_dir/gnupg" --armor --export > "$recovery_dir/public.asc"
gpg --homedir "$recovery_dir/gnupg" --batch --pinentry-mode loopback \
  --passphrase '' --armor --export-secret-keys > "$recovery_dir/private.asc"
```

Keep the recovery directory outside the repository. Back up `private.asc` securely until the signing key has been recovered.

## Run the recovery and download the backup

```bash
gh workflow run recover-android-signing.yml \
  -f recovery_public_key="$(cat "$recovery_dir/public.asc")"
gh run list --workflow recover-android-signing.yml --limit 5
```

Copy the new run's numeric ID into `recovery_run_id`, then download its artifact:

```bash
recovery_run_id=123456789
gh run watch "$recovery_run_id" --exit-status
gh run download "$recovery_run_id" \
  --name "android-signing-backup-$recovery_run_id" --dir "$recovery_dir/download"
gpg --homedir "$recovery_dir/gnupg" --batch \
  --output "$recovery_dir/signing-backup.tar.gz" \
  --decrypt "$recovery_dir/download/android-signing-backup.tar.gz.gpg"
mkdir -m 700 "$recovery_dir/recovered"
tar -xzf "$recovery_dir/signing-backup.tar.gz" -C "$recovery_dir/recovered"
chmod 600 "$recovery_dir/recovered/"*
```

The recovered files are `release.jks` and `signing-credentials.json`. The JSON contains `storePassword`, `keyPassword`, and `keyAlias` with their original values. Store both files in a secure backup. The [mobile app guide](mobile-app.md) describes the release process that uses the same GitHub signing secrets.

## Verify and clean up

Run `keytool -list -keystore "$recovery_dir/recovered/release.jks"` and enter the recovered store password when prompted. If an older signed APK is available, compare its signing certificate with the recovered keystore's certificate to confirm the secrets still contain the original key.

The workflow fails if a signing secret is missing, the base64 is invalid, or the store password or alias cannot open the keystore. It cannot recover a deleted or overwritten secret. A successful run verifies the store password and alias; it preserves the key password without independently testing it.

The encrypted artifact expires after one day. Once the local backup is verified, delete the workflow run with `gh run delete "$recovery_run_id"` and remove the recovery workflow if it is no longer needed. The runner deletes its temporary plaintext files when the encryption step exits; the local decrypted files remain until you remove them.
