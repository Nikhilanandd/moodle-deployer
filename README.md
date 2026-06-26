# Moodle Deployer

Production-grade Moodle deployment automation for Ubuntu 24.04/26.04 LTS with Nginx, PHP-FPM 8.1, and MariaDB.

Restores the latest Moodle backup into a **new** Moodle instance — automating everything except the Moodle web installer.

## Requirements

- Ubuntu 24.04 LTS or 26.04 LTS
- Root access
- Nginx
- PHP 8.1 (CLI + FPM)
- MariaDB server
- Moodle backups at `/srv/backups/moodlelms/{code,db,moodledata}/`
- Existing Moodle instances on the same server (multi-instance support)

### Backup Structure

Backups must exist at:

```
/srv/backups/moodlelms/
├── code/
│   └── 20260625.tar.gz
├── db/
│   ├── 20260625.sql
│   ├── 20260625.sql.gz
│   └── 20260625.tar.gz
└── moodledata/
    └── 20260625.tar.gz
```

Each backup file is named using only the date (e.g., `20260625.tar.gz`). The newest backup (highest date) is selected automatically.

## Installation

```bash
git clone <repo-url> moodle-deployer
cd moodle-deployer
chmod +x deploy-moodle.sh uninstall-instance.sh
```

No additional dependencies are required. The script relies on standard system tools.

## Usage

### Deploy a New Instance

```bash
sudo ./deploy-moodle.sh
```

The script will interactively ask for:

| Parameter          | Description                        | Default                   |
|--------------------|------------------------------------|---------------------------|
| Instance name      | Short identifier (e.g., moodle-preprod) | —                   |
| Installation dir   | Base path for moodle + moodledata  | `/srv/<instance>`         |
| HTTP port          | Unique port for this instance      | —                         |
| Server name/IP     | Hostname or IP address             | Current server IP         |
| PHP version        | PHP-FPM version to use             | `8.1`                     |
| Database name      | MariaDB database name              | `<instance>`              |
| Database user      | MariaDB user name                  | `<instance>`              |
| Database password  | MariaDB user password              | prompted securely         |

Backup restore options:

- **Restore latest code backup?** — Extracts code archive to `/srv/<instance>/moodle/`
- **Restore latest database backup?** — Imports SQL dump into the new database
- **Restore latest moodledata backup?** — Extracts moodledata archive to `/srv/<instance>/moodledata/`

### Uninstall an Instance

```bash
sudo ./uninstall-instance.sh
```

This will:
1. Disable and remove the Nginx site config
2. Drop the MariaDB database and user
3. Remove the deployment directory
4. Remove the Moodle PHP-FPM configuration
5. Reload Nginx

You will be prompted for confirmation and must type the instance name to proceed.

## What the Script Does

1. **Pre-flight validation** — Checks root, PHP, PHP-FPM, MariaDB, Nginx, disk space, port availability, backup existence
2. **Directory creation** — Creates `/srv/<instance>/moodle` and `/srv/<instance>/moodledata`
3. **Backup restoration** — Extracts the latest code, database, and moodledata backups
4. **Cleanup** — Removes `config.php`, cache, temp, sessions, git metadata, test artifacts
5. **Database setup** — Creates database (utf8mb4), user, grants privileges, imports data
6. **Permissions** — Sets `www-data:www-data` ownership, secure file/directory modes
7. **Nginx config** — Generates production-grade site configuration, enables site, reloads
8. **PHP config** — Creates `/etc/php/8.1/fpm/conf.d/99-moodle.ini` with optimal Moodle settings
9. **Summary** — Prints deployment details and next steps

## What the Script Does NOT Do

- Run the Moodle web installer (you must visit the URL in a browser)
- Create SSL certificates (configure HTTPS separately)
- Set up cron jobs for Moodle's scheduled tasks
- Configure email (SMTP)
- Create backups (restore only)

## PHP Configuration

The script creates `/etc/php/<version>/fpm/conf.d/99-moodle.ini` with:

```
memory_limit = 512M
upload_max_filesize = 200M
post_max_size = 200M
max_execution_time = 300
max_input_vars = 5000
opcache.enable = 1
opcache.memory_consumption = 256
```

## Nginx Configuration

The generated site config includes:

- Moodle rewrite rules (`try_files $uri $uri/ /index.php?$query_string`)
- PHP-FPM passthrough via Unix socket
- Static asset caching (30 days)
- Hidden files protection (`.ht`, `.git`, etc.)
- Sensitive file blocking (`.bak`, `.conf`, `.sql`, etc.)
- Vendor directory protection
- Gzip compression
- 200 MB `client_max_body_size`

## Rollback

If any step fails, the script automatically:

1. Drops the created database
2. Drops the created database user
3. Removes the deployment directory
4. Removes the Nginx config file and symlink
5. Reloads Nginx

No partial state is left behind.

## Logging

All output is logged to `/var/log/moodle-deploy.log` with timestamps.

## Project Structure

```
moodle-deployer/
├── deploy-moodle.sh              # Main deployment script
├── uninstall-instance.sh         # Instance removal script
├── lib/
│   ├── colors.sh                 # ANSI color definitions
│   ├── logging.sh                # Logging and user prompts
│   ├── validation.sh             # Pre-flight checks
│   ├── backup.sh                 # Backup discovery and extraction
│   ├── database.sh               # MariaDB operations
│   ├── permissions.sh            # File ownership and mode setting
│   ├── nginx.sh                  # Nginx config generation
│   ├── php.sh                    # PHP-FPM configuration
│   └── rollback.sh              # Atomic rollback tracking
├── templates/
│   ├── nginx.conf.tpl            # Nginx site template
│   └── php.ini.tpl               # PHP-FPM ini template
└── README.md                     # This file
```

## Troubleshooting

### "Port X is already in use"

Choose a different port. Use `ss -tlnp` to find available ports.

### "Database user already exists"

The script checks for this pre-flight. If you need to recreate, use `uninstall-instance.sh` first.

### "Nginx configuration test failed"

Check the generated config at `/etc/nginx/sites-available/<instance>.conf`. Common issues:
- Missing PHP-FPM socket (verify `php<version>-fpm` is installed)
- Port conflict
- Syntax error in the generated file

### "Disk space insufficient"

Moodle with moodledata can be large. Free up space or choose a different partition.

### "Backup not found"

Ensure backups exist at `/srv/backups/moodlelms/{code,db,moodledata}/` with date-based filenames.

## Security Notes

- Database password is never logged or written to disk (prompted securely)
- All `rm -rf` operations validate paths to prevent accidental deletion
- Nginx config blocks access to sensitive files and directories
- Script must be run as root
- No hardcoded credentials
