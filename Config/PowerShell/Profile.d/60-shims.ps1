function tailscale {
    Push-Location "/Applications/Tailscale.app/Contents/MacOS"
    try {
        ./tailscale $args
    }
    finally {
        Pop-Location
    }
}
