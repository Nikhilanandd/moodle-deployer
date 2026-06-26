server {
    listen __PORT__;
    server_name __SERVER_NAME__;

    root __MOODLE_DIR__;

    index index.php index.html index.htm;

    client_max_body_size 200M;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ [^/]\.php(/|$) {
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        if (!-f $document_root$fastcgi_script_name) {
            return 404;
        }
        fastcgi_pass unix:/run/php/php__PHP_VERSION__-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
    }

    location ~* \.(jpg|jpeg|gif|png|css|js|ico|xml|svg|webp|avif|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~ /(?:vendor|node_modules) {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~* (?:composer\.(json|lock)) {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~* \.(?:bak|conf|dist|fla|inc|log|psd|sh|sql|swp|sqlite|backup|old|orig)$ {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~* /(?:\.git|\.svn|\.hg) {
        deny all;
        access_log off;
        log_not_found off;
    }

    gzip on;
    gzip_types text/css text/xml application/javascript image/svg+xml;
    gzip_vary on;
    gzip_proxied any;
    gzip_min_length 1000;
}
