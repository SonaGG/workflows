# workflows

Shared GitHub Actions workflows for SonaGG.

## sign-windows

Signs Windows binaries with Azure Artifact Signing.

```yaml
jobs:
  sign:
    needs: build
    permissions:
      id-token: write
      contents: read
    uses: SonaGG/workflows/.github/workflows/sign-windows.yml@main
    with:
      artifact-name: app-windows-x64
```

| Input | Default |
|---|---|
| `artifact-name` | required |
| `files-filter` | `exe,dll,sys,msi,msix,appx,cab,cat,ps1,psm1` |
| `replace-artifact` | `true` |
| `description` | |
| `description-url` | |
