# APT Repository

This directory contains a Debian/Ubuntu APT repository structure.

## Hosting the Repository

### Option 1: Simple HTTP Server (for testing)

```bash
# Python 3
cd apt-repo
python3 -m http.server 8080

# Then access at: http://localhost:8080
```

### Option 2: Nginx

```nginx
server {
    listen 80;
    server_name packages.example.com;
    root /path/to/apt-repo;
    
    location / {
        autoindex on;
    }
}
```

### Option 3: Apache

```apache
<VirtualHost *:80>
    ServerName packages.example.com
    DocumentRoot /path/to/apt-repo
    
    <Directory /path/to/apt-repo>
        Options +Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
```

## Using the Repository

Add the repository to your system:

```bash
# Add repository (replace URL with your server)
echo "deb [arch=arm64] http://your-server-url/apt-repo stable main" | \
    sudo tee /etc/apt/sources.list.d/custom-packages.list

# If you have a GPG key (optional but recommended):
# wget -qO - http://your-server-url/apt-repo/KEY.gpg | sudo apt-key add -

# Update package list
sudo apt-get update

# Install packages
sudo apt-get install package-name
```

## Repository Structure

```
apt-repo/
├── dists/
│   └── stable/
│       ├── Release
│       └── main/
│           └── binary-arm64/
│               ├── Packages
│               └── Packages.gz
└── pool/
    └── main/
        └── [a-z]/
            └── package-name/
                └── package_version_arch.deb
```

## Updating the Repository

After adding new .deb files, regenerate the index:

```bash
./scripts/create-apt-repository.sh arm64 apt-repo
```

## Signing the Repository (Recommended for Production)

To sign the repository with GPG:

```bash
# Generate a GPG key if you don't have one
gpg --gen-key

# Export the public key
gpg --armor --export YOUR_EMAIL > apt-repo/KEY.gpg

# Sign the Release file
cd apt-repo/dists/stable
gpg --clearsign -o InRelease Release
gpg -abs -o Release.gpg Release
```

Clients will then need to add your public key before trusting the repository.
