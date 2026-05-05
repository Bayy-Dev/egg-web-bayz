#!/bin/bash
cd /home/container

# Secret key di-inject oleh install script egg
WEBHOOK_SECRET="${WEBHOOK_SECRET:-__WEBHOOK_SECRET__}"

echo "======================================"
echo "   WEB HOSTING - BY BAYYZ"
echo "======================================"
[ -n "${CUSTOM_DOMAIN}" ] && echo " Domain : ${CUSTOM_DOMAIN}" || echo " Domain : (IP:Port)"
echo " Port   : ${SERVER_PORT}"
echo "======================================"

# ===== AUTO UPDATE =====
if [ "${AUTO_UPDATE}" = "1" ] && [ -n "${GIT_URL}" ]; then
    echo "Auto update: git pull..."
    git pull || true
fi

# ===== INJECT DATABASE KE .env =====
if [ -n "${DB_HOST}" ] && [ -n "${DB_NAME}" ]; then
    echo "Injecting database config ke .env..."
    touch .env
    _set_env() {
        if grep -q "^${1}=" .env 2>/dev/null; then
            sed -i "s|^${1}=.*|${1}=${2}|" .env
        else
            echo "${1}=${2}" >> .env
        fi
    }
    _set_env DB_HOST "${DB_HOST}"
    _set_env DB_PORT "${DB_PORT:-3306}"
    _set_env DB_DATABASE "${DB_NAME}"
    _set_env DB_NAME "${DB_NAME}"
    _set_env DB_USERNAME "${DB_USER}"
    _set_env DB_USER "${DB_USER}"
    _set_env DB_PASSWORD "${DB_PASS}"
    _set_env DB_PASS "${DB_PASS}"
    _set_env DB_CONNECTION "mysql"
    [ -n "${CUSTOM_DOMAIN}" ] && _set_env APP_URL "https://${CUSTOM_DOMAIN}"
    echo ".env updated!"
fi

# ===== AUTO DETECT FRAMEWORK =====
FW="${WEB_TYPE:-auto}"
if [ "${FW}" = "auto" ]; then
    echo "Detecting framework..."
    if   [ -f "next.config.js" ] || [ -f "next.config.mjs" ] || [ -f "next.config.ts" ]; then FW="nextjs"
    elif [ -f "nuxt.config.js" ] || [ -f "nuxt.config.ts" ] || [ -f "nuxt.config.mjs" ]; then FW="nuxt"
    elif [ -f "artisan" ]; then FW="laravel"
    elif [ -f "vite.config.js" ] || [ -f "vite.config.ts" ]; then
        grep -q '"vue"' package.json 2>/dev/null && FW="vue" || FW="react-vite"
    elif [ -f "package.json" ]; then
        if   grep -q '"next"' package.json 2>/dev/null;          then FW="nextjs"
        elif grep -q '"nuxt"' package.json 2>/dev/null;          then FW="nuxt"
        elif grep -q '"express"' package.json 2>/dev/null;       then FW="express"
        elif grep -q '"react-scripts"' package.json 2>/dev/null; then FW="react-cra"
        else FW="node"; fi
    elif ls *.php 2>/dev/null | head -1 | grep -q "."; then FW="php"
    else FW="static"; fi
fi
echo " Framework : ${FW}"
echo "======================================"

# ===== CUSTOM DOMAIN + SSL =====
if [ -n "${CUSTOM_DOMAIN}" ] && [ -n "${WEBHOOK_SECRET}" ]; then
    echo "Setup custom domain + SSL..."
    curl -s --max-time 10 -X POST http://172.18.0.1:3500 \
        -H "Content-Type: application/json" \
        -d "{\"secret\":\"${WEBHOOK_SECRET}\",\"action\":\"add\",\"domain\":\"${CUSTOM_DOMAIN}\",\"port\":${SERVER_PORT}}" || true
fi

# ===== HELPER =====
_pm() {
    corepack enable >/dev/null 2>&1 || true
    if [ -f pnpm-lock.yaml ]; then echo pnpm
    elif [ -f yarn.lock ]; then echo yarn
    else echo npm; fi
}
_install() {
    local PM=$(_pm)
    echo "Install deps ($PM)..."
    if [ "$PM" = "pnpm" ]; then pnpm install
    elif [ "$PM" = "yarn" ]; then yarn install
    else npm install; fi
}
_run() {
    local PM=$(_pm)
    if [ "$PM" = "pnpm" ]; then pnpm run $1
    elif [ "$PM" = "yarn" ]; then yarn $1
    else npm run $1; fi
}

# ===== RUN =====
case "${FW}" in

    nextjs)
        _install
        if [ "${NODE_RUN_ENV}" = "start" ]; then
            echo "Building Next.js..."
            _run build
            $(_pm) run start -- -p ${SERVER_PORT}
        else
            $(_pm) run dev -- -p ${SERVER_PORT}
        fi
        ;;

    nuxt)
        _install
        if [ "${NODE_RUN_ENV}" = "start" ]; then
            NITRO_PORT=${SERVER_PORT} _run build
            node .output/server/index.mjs
        else
            $(_pm) run dev -- --port ${SERVER_PORT}
        fi
        ;;

    react-vite|vue)
        _install
        if [ "${NODE_RUN_ENV}" = "start" ]; then
            _run build
            npx serve dist -l ${SERVER_PORT} -s
        else
            $(_pm) run dev -- --port ${SERVER_PORT} --host
        fi
        ;;

    react-cra)
        _install
        if [ "${NODE_RUN_ENV}" = "start" ]; then
            _run build
            npx serve build -l ${SERVER_PORT} -s
        else
            PORT=${SERVER_PORT} $(_pm) start
        fi
        ;;

    express|node)
        _install
        START_FILE="index.js"
        [ -f "server.js" ] && START_FILE="server.js"
        [ -f "app.js" ]    && START_FILE="app.js"
        grep -q '"main"' package.json 2>/dev/null && \
            START_FILE=$(node -e "console.log(require('./package.json').main||'index.js')" 2>/dev/null || echo "index.js")
        if grep -q '"start"' package.json 2>/dev/null; then
            PORT=${SERVER_PORT} npm start
        else
            PORT=${SERVER_PORT} node ${START_FILE}
        fi
        ;;



    static)
        echo "Serving static files..."
        npx --yes serve . -l ${SERVER_PORT} -s
        ;;

    *)
        echo "ERROR: WEB_TYPE '${FW}' tidak dikenali!"
        echo "Pilihan: auto nextjs nuxt react-vite vue react-cra express node static"
        exit 1
        ;;
esac
