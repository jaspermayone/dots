# Spindle Setup Guide

This document outlines the Spindle CI/CD runner setup for alastor and dippet.

## Overview

Spindles are configured on two hosts:
- **alastor** (NixOS, aarch64-linux): `1.alastor.spindle.hogwarts.dev`
- **dippet** (macOS, aarch64-darwin): `1.dippet.spindle.hogwarts.dev`

Both spindles are configured to run under the DID: `did:plc:abgthiqrd7tczkafjm4ennbo`

## Alastor Setup (NixOS)

### Configuration
The alastor spindle is configured using the official Tangled nixosModule:

- **Service**: `services.tangled.spindle`
- **Listen Address**: `127.0.0.1:6555`
- **Database**: `/var/lib/spindle/spindle.db` (default)
- **Logs**: `/var/log/spindle` (default)
- **Public URL**: `https://1.alastor.spindle.hogwarts.dev`

### Deployment
To deploy to alastor:

```bash
# From macOS (using deploy-rs)
deploy .#alastor --skip-checks

# Or via SSH
ssh alastor
cd ~/dots
sudo nixos-rebuild switch --flake .#alastor
```

### Reverse Proxy
Caddy is configured to proxy the spindle service with:
- TLS via Cloudflare DNS challenge
- HSTS headers
- Proxying from port 443 to local port 6555

### Monitoring
The spindle service (`tangled-spindle`) is included in the status monitoring dashboard at `alastor.hogwarts.channel`.

## Dippet Setup (macOS)

### Configuration
The dippet spindle is configured as a launchd daemon:

- **Service**: `launchd.daemons.tangled-spindle`
- **Listen Address**: `127.0.0.1:6556`
- **Database**: `/Users/jsp/Library/Application Support/spindle/spindle.db`
- **Logs**: `/Users/jsp/Library/Logs/spindle/`
- **Public URL**: `https://1.dippet.spindle.hogwarts.dev` (requires tunnel setup)

### Prerequisites
1. **Docker Desktop**: Added to homebrew casks - install with:
   ```bash
   brew install --cask docker
   ```

2. **Cloudflare Tunnel**: Required for public access (see below)

### Deployment
To deploy to dippet:

```bash
# From dippet
darwin-rebuild switch --flake ~/dev/dots#dippet

# Or from remote
ssh dippet 'cd ~/dev/dots && darwin-rebuild switch --flake .#dippet'
```

### Cloudflare Tunnel Setup (Using Existing Tunnel)

Since you already have a running Cloudflare tunnel on dippet, you just need to add a route for the spindle service.

#### Option 1: Using cloudflared CLI
```bash
# Add DNS route to your existing tunnel
cloudflared tunnel route dns <your-tunnel-id> 1.dippet.spindle.hogwarts.dev
```

#### Option 2: Update tunnel config file
If you're using a config file (usually at `~/.cloudflared/config.yml`), add the spindle ingress rule:

```yaml
tunnel: <your-tunnel-id>
credentials-file: /path/to/credentials.json

ingress:
  # Add this entry
  - hostname: 1.dippet.spindle.hogwarts.dev
    service: http://localhost:6556

  # Keep your existing rules here

  # Catch-all rule (must be last)
  - service: http_status:404
```

Then restart cloudflared:
```bash
sudo launchctl restart <your-cloudflared-service-name>
```

#### Option 3: Using Cloudflare Dashboard
1. Go to Zero Trust > Networks > Tunnels
2. Select your tunnel
3. Go to Public Hostname tab
4. Click "Add a public hostname"
5. Set:
   - Subdomain: `1.dippet.spindle`
   - Domain: `hogwarts.dev`
   - Service: `http://localhost:6556`
6. Save

### Verifying the tunnel
After setup, verify the tunnel is running:

```bash
# Check tunnel status
sudo launchctl list | grep cloudflared

# Check logs
tail -f ~/Library/Logs/cloudflared-spindle.log
```

## Service Management

### Alastor (NixOS)
```bash
# Check status
sudo systemctl status tangled-spindle

# View logs
sudo journalctl -u tangled-spindle -f

# Restart
sudo systemctl restart tangled-spindle

# Stop
sudo systemctl stop tangled-spindle
```

### Dippet (macOS)
```bash
# Check status
sudo launchctl list | grep tangled-spindle

# View logs
tail -f ~/Library/Logs/spindle.log

# Restart
sudo launchctl kickstart -k system/org.nixos.tangled-spindle

# Stop
sudo launchctl stop org.nixos.tangled-spindle
```

## Testing

Once both spindles are running and accessible, test them:

```bash
# Test alastor spindle
curl https://1.alastor.spindle.hogwarts.dev

# Test dippet spindle (after tunnel setup)
curl https://1.dippet.spindle.hogwarts.dev
```

## Adding Spindles to Repositories

To use these spindles for your repositories:

1. Go to your repository settings on Tangled
2. Navigate to the Spindles section
3. Add the spindle hostnames:
   - `1.alastor.spindle.hogwarts.dev`
   - `1.dippet.spindle.hogwarts.dev`

## Troubleshooting

### Docker not available
**Symptom**: Spindle fails to start containers

**Solution**:
- On alastor: Docker is managed by NixOS, check `sudo systemctl status docker`
- On dippet: Ensure Docker Desktop is installed and running

### Connection refused
**Symptom**: Cannot connect to spindle endpoint

**Solution**:
- Check if the service is running
- Verify firewall rules (alastor: port 443 should be open)
- For dippet: Verify Cloudflare tunnel is active

### Pipeline failures
**Symptom**: Pipelines fail to execute

**Solution**:
- Check spindle logs for errors
- Verify Docker is running and accessible
- Check disk space: `df -h`
- Verify Nixery is accessible: `curl https://nixery.tangled.sh`

### Database corruption
**Symptom**: Spindle fails to start with database errors

**Solution**:
- Backup the database
- On alastor: `/var/lib/spindle/spindle.db`
- On dippet: `~/Library/Application Support/spindle/spindle.db`
- Delete and restart the service (will create fresh database)

## OpenBao Secrets (Optional)

If you want to use OpenBao for secrets management instead of the default SQLite backend, refer to the [Tangled Spindle documentation](https://docs.tangled.org/spindles.html#secrets-with-openbao) for setup instructions.

## Next Steps

1. ✅ Deploy to alastor
2. ⏳ Install Docker Desktop on dippet
3. ⏳ Set up Cloudflare tunnel for dippet
4. ⏳ Deploy to dippet
5. ⏳ Test both spindles
6. ⏳ Add spindles to your repositories

## References

- [Tangled Spindle Documentation](https://docs.tangled.org/spindles.html)
- [Spindle Self-hosting Guide](https://docs.tangled.org/spindles.html#self-hosting-guide)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
