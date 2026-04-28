$extraPathVariables = @(
    "${env:HOME}/.local/bin",
    "${env:HOME}/Library/pnpm"
)

foreach ($path in $extraPathVariables) {
    if ($path -and (Test-Path $path)) {
        $env:PATH = "${path}:${env:PATH}"
    }
}

$global:mem = "--filter=@world50/member-app"
$global:gl = "--filter=@world50/group-leader-app"
$global:pro = "--filter=@world50/prospector-app"
$global:auth = "--filter=@world50/authentication-app"
$global:petl = "--filter=@world50/prospector-etl"
$global:psha = "--filter=@world50/prospector-shared"

$env:PNPM_HOME = "${env:HOME}/Library/pnpm"
