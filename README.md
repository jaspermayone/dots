# Jasper's Dotfiles

NixOS and nix-darwin configurations for the Hogwarts network.

## Status

<img src="https://img.shields.io/website?label=alastor&up_color=green&up_message=online&down_message=offline&url=https%3A%2F%2Falastor.hogwarts.channel%2Fstatus%2Falastor">

*Status badges run through alastor — if all badges are red, alastor is probably down.*

## Hosts

| Host | Domain | Type | Description |
|------|--------|------|-------------|
| **alastor** | `alastor.hogwarts.channel` | NixOS (x86_64) | VPS hub - tunnels, status, reverse proxy (Mad-Eye Moody) |
| **remus** | `remus.hogwarts.channel` | Darwin (aarch64) | MacBook Pro M4 - My daily driver |
| **dippet** | `dippet.hogwarts.channel` | Darwin (aarch64) | Mac Mini - assorted services |

### Domain Structure

- `tun.hogwarts.channel` — bore/frp tunnels only
- `*.tun.hogwarts.channel` — dynamic tunnel subdomains
- `alastor.hogwarts.channel` — alastor services (status API, etc.)
- `remus.hogwarts.channel` — reverse proxy to remus via Tailscale
- `dippet.hogwarts.channel` — reverse proxy to dippet via Tailscale
- `knot.jaspermayone.com` — Tangled Knot git server
- `atuin.hogwarts.dev` - Atuin server


## Secrets Management (agenix)

This repo uses [agenix](https://github.com/ryantm/agenix) for secrets. Secrets are encrypted with age using SSH keys and stored in git.

### Initial Setup

1. Get your SSH public key:
```bash
cat ~/.ssh/id_ed25519.pub
```

2. Edit `secrets/secrets.nix` and add your public key:
```nix
let
  jsp = "ssh-ed25519 AAAA... jasper@remus";
  # ...
```

3. After provisioning alastor, get its host key:
```bash
ssh-keyscan -t ed25519 tun.hogwarts.channel
```

4. Add the host key to `secrets/secrets.nix`

### Creating Secrets

```bash
# From the repo root
cd secrets

# Create/edit a secret (opens $EDITOR)
agenix -e frps-token.age

# For frps-token, just paste a random token:
# openssl rand -hex 32

# For cloudflare-credentials.age:
# CF_DNS_API_TOKEN=your-token-here

# For bore-token.age, use the same value as frps-token
```

### Re-keying Secrets

If you add new keys to `secrets.nix`:
```bash
cd secrets
agenix -r  # Re-encrypt all secrets with new keys
```

## Quick Start

### Setting up Remus (Mac)

1. Install Nix (using Determinate Systems installer):
```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

2. Clone this repo:
```bash
git clone https://github.com/jaspermayone/dots.git ~/dots
cd ~/dots
```

3. Create the secrets (see Secrets Management above):
```bash
cd secrets
agenix -e bore-token.age
cd ..
```

4. Build and switch:
```bash
nix run nix-darwin -- switch --flake .#remus
```

After the first build, use:
```bash
darwin-rebuild switch --flake ~/dots#remus
```

### Setting up Alastor (Server)

1. Provision a VPS with NixOS (Hetzner has this in marketplace)

2. SSH in and clone:
```bash
git clone https://github.com/jaspermayone/dots.git /etc/nixos
cd /etc/nixos
```

3. Generate hardware config:
```bash
nixos-generate-config --show-hardware-config > hosts/alastor/hardware-configuration.nix
```

4. Get the host's SSH public key and add to `secrets/secrets.nix`:
```bash
cat /etc/ssh/ssh_host_ed25519_key.pub
```

5. On your local machine, re-key secrets with the new host key:
```bash
cd secrets && agenix -r && cd ..
git add . && git commit -m "Add alastor host key"
git push
```

6. Back on the server, pull and build:
```bash
git pull
nixos-rebuild switch --flake .#alastor
```

### Remote Deployment

From your Mac:
```bash
nixos-rebuild switch --flake .#alastor --target-host root@tun.hogwarts.channel
```

## DNS Setup (Cloudflare)

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | tun | server-ip | Off (gray) |
| A | *.tun | server-ip | Off (gray) |
| A | alastor | server-ip | Off (gray) |
| A | remus | server-ip | Off (gray) |

**Create Cloudflare API Token:**
1. https://dash.cloudflare.com/profile/api-tokens
2. Create Token → Custom Token
3. Permissions: `Zone - DNS - Edit`
4. Zone Resources: `Include - Specific zone - hogwarts.channel`

## Usage

### Creating a tunnel

```bash
# Interactive
bore

# Quick tunnel
bore myapp 3000

# With options
bore api 8080 --protocol http --label dev --save
```

### Listing tunnels

```bash
bore --list     # Active tunnels on server
bore --saved    # Saved tunnels in bore.toml
```

## Structure

```
dots/
├── flake.nix                 # Entry point
├── secrets/
│   ├── secrets.nix           # Declares keys and secrets
│   ├── frps-token.age        # Encrypted frp auth token
│   ├── cloudflare-credentials.age
│   └── bore-token.age        # Client token (same as frps-token)
├── common/
│   ├── bore.nix              # Bore client config
│   ├── git.nix               # Git configuration
│   └── shell.nix             # Shell configuration
├── darwin/
│   └── default.nix           # macOS-specific settings
├── home/
│   └── default.nix           # Home Manager config
├── hosts/
│   ├── alastor/              # NixOS server (Mad-Eye Moody)
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   └── remus/                # Mac laptop
│       └── default.nix
└── modules/
    ├── bore/                 # Bore client module
    │   ├── default.nix
    │   ├── bore.1.md
    │   └── completions/
    ├── frps/                 # Frp server module
    │   └── default.nix
    └── status/               # Status monitoring module
        └── default.nix
```

## Adding New Hosts

### NixOS
1. Create `hosts/hostname/configuration.nix`
2. Create `hosts/hostname/hardware-configuration.nix`
3. Add host key to `secrets/secrets.nix` and re-key
4. Add to `flake.nix`:
```nix
nixosConfigurations.hostname = mkNixos "hostname" "x86_64-linux";
```

### Darwin (Mac)
1. Create `hosts/hostname/default.nix`
2. Add user key to `secrets/secrets.nix` and re-key
3. Add to `flake.nix`:
```nix
darwinConfigurations.hostname = mkDarwin "hostname" "aarch64-darwin";
```

## Useful Commands

```bash
# Edit a secret
agenix -e secrets/frps-token.age

# Re-key all secrets (after adding new keys)
cd secrets && agenix -r

# Check flake
nix flake check

# Update flake inputs
nix flake update

# Garbage collect old generations
nix-collect-garbage -d
```