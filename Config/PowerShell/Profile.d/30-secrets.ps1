$secretsPath = Join-Path $HOME 'secrets.ps1'

if (Test-Path $secretsPath) {
    . $secretsPath
}
