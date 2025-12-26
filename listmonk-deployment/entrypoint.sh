#!/bin/bash
set -e

echo "=========================================="
echo "MOYD Listmonk Initialization"
echo "=========================================="

# Wait for database
echo "Waiting for database..."
sleep 5

# Run install/upgrade (idempotent)
./listmonk --config /listmonk/config.toml --install --idempotent --yes

echo "Configuring S3 storage..."

# S3 Storage Configuration (Supabase Storage)
./listmonk --config /listmonk/config.toml --query 'UPDATE settings SET value = '\''"s3"'\'' WHERE key = '\''upload.provider'\'';'
./listmonk --config /listmonk/config.toml --query 'UPDATE settings SET value = '\''"https://faajpcarasilbfndzkmd.supabase.co/storage/v1/s3"'\'' WHERE key = '\''upload.s3.url'\'';'
./listmonk --config /listmonk/config.toml --query 'UPDATE settings SET value = '\''"listmonk-media"'\'' WHERE key = '\''upload.s3.bucket'\'';'
./listmonk --config /listmonk/config.toml --query 'UPDATE settings SET value = '\''""'\'' WHERE key = '\''upload.s3.bucket_path'\'';'
./listmonk --config /listmonk/config.toml --query 'UPDATE settings SET value = '\''"us-east-1"'\'' WHERE key = '\''upload.s3.aws_default_region'\'';'
./listmonk --config /listmonk/config.toml --query 'UPDATE settings SET value = '\''"5e472de71e10241068e2c13b76ddf2f8"'\'' WHERE key = '\''upload.s3.aws_access_key_id'\'';'
./listmonk --config /listmonk/config.toml --query 'UPDATE settings SET value = '\''$S3_SECRET_KEY'\'' WHERE key = '\''upload.s3.aws_secret_access_key'\'';'
./listmonk --config /listmonk/config.toml --query 'UPDATE settings SET value = '\''"public"'\'' WHERE key = '\''upload.s3.bucket_type'\'';'
./listmonk --config /listmonk/config.toml --query 'UPDATE settings SET value = '\''"https://faajpcarasilbfndzkmd.supabase.co/storage/v1/object/public/listmonk-media"'\'' WHERE key = '\''upload.s3.public_url'\'';'

echo "Configuring admin appearance..."

# Admin appearance CSS for MOYD branding - comprehensive text visibility fix
./listmonk --config /listmonk/config.toml --query 'UPDATE settings SET value = '\''
/* MOYD Admin Branding - Complete Text Visibility Fix */

/* Main navigation - white text on navy */
.navbar.is-primary,
.navbar.is-primary .navbar-brand,
.navbar.is-primary .navbar-menu,
.navbar.is-primary .navbar-start,
.navbar.is-primary .navbar-end {
    background-color: #273351 !important;
}

.navbar.is-primary .navbar-item,
.navbar.is-primary .navbar-link,
.navbar.is-primary a.navbar-item,
.navbar.is-primary .navbar-burger,
.navbar.is-primary .navbar-burger span {
    color: #ffffff !important;
}

.navbar.is-primary .navbar-item:hover,
.navbar.is-primary .navbar-link:hover,
.navbar.is-primary a.navbar-item:hover {
    background-color: #32A6DE !important;
    color: #ffffff !important;
}

.navbar.is-primary .navbar-item.has-dropdown:hover .navbar-link {
    background-color: #32A6DE !important;
    color: #ffffff !important;
}

/* Dropdown menus */
.navbar.is-primary .navbar-dropdown {
    background-color: #ffffff !important;
    border-top: 2px solid #32A6DE !important;
}

.navbar.is-primary .navbar-dropdown .navbar-item {
    color: #273351 !important;
}

.navbar.is-primary .navbar-dropdown .navbar-item:hover {
    background-color: #f5f7fa !important;
    color: #32A6DE !important;
}

/* Hero sections */
.hero.is-primary {
    background-color: #273351 !important;
}

.hero.is-primary .title,
.hero.is-primary .subtitle,
.hero.is-primary .hero-body .title,
.hero.is-primary .hero-body .subtitle {
    color: #ffffff !important;
}

/* Page headers with dark background */
.hero.is-primary .hero-body * {
    color: #ffffff !important;
}

/* Buttons */
.button.is-primary {
    background-color: #32A6DE !important;
    border-color: #32A6DE !important;
    color: #ffffff !important;
}

.button.is-primary:hover {
    background-color: #2890c4 !important;
    border-color: #2890c4 !important;
}

/* Tags and labels */
.tag.is-primary {
    background-color: #32A6DE !important;
    color: #ffffff !important;
}

/* Progress bars */
.progress.is-primary::-webkit-progress-value {
    background-color: #32A6DE !important;
}

/* Links */
a {
    color: #32A6DE;
}

a:hover {
    color: #273351;
}

/* Box shadows for depth */
.box {
    box-shadow: 0 2px 8px rgba(39, 51, 81, 0.08);
}
'\'' WHERE key = '\''appearance.admin.custom_css'\'';'

echo "Configuration complete!"
echo "Starting Listmonk..."

# Start listmonk with custom static directory
exec ./listmonk --config /listmonk/config.toml --static-dir=/listmonk/static "$@"
