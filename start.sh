#!/bin/bash
cd /home/container

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

# ===== AUTO DETECT FRAMEWORK =====
FW="${WEB_TYPE:-auto}"
if [ "${FW}" = "auto" ]; then
    echo "Detecting framework..."
    if   [ -f "next.config.js" ] || [ -f "next.config.mjs" ] || [ -f "next.config.ts" ]; then FW="nextjs"
    elif [ -f "nuxt.config.js" ] || [ -f "nuxt.config.ts" ] || [ -f "nuxt.config.mjs" ]; then FW="nuxt"
    elif [ -f "vite.config.js" ] || [ -f "vite.config.ts" ]; then
        grep -q '"vue"' package.json 2>/dev/null && FW="vue" || FW="react-vite"
    elif [ -f "package.json" ]; then
        if   grep -q '"next"' package.json 2>/dev/null;          then FW="nextjs"
        elif grep -q '"nuxt"' package.json 2>/dev/null;          then FW="nuxt"
        elif grep -q '"express"' package.json 2>/dev/null;       then FW="express"
        elif grep -q '"react-scripts"' package.json 2>/dev/null; then FW="react-cra"
        else FW="node"; fi
    else FW="static"; fi
fi
echo " Framework : ${FW}"
echo "======================================"

# ===== CUSTOM DOMAIN + SSL =====
if [ -n "${CUSTOM_DOMAIN}" ] && [ -n "${WEBHOOK_SECRET}" ]; then
    echo "Setup custom domain + SSL..."
    RESULT=$(curl -s --max-time 15 -X POST http://172.18.0.1:3500 \
        -H "Content-Type: application/json" \
        -d "{\"secret\":\"${WEBHOOK_SECRET}\",\"action\":\"add\",\"domain\":\"${CUSTOM_DOMAIN}\",\"port\":${SERVER_PORT}}")
    echo "Webhook: $RESULT"
else
    echo "Skip webhook (domain/secret kosong)."
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
            npx --yes serve dist -l ${SERVER_PORT} -s
        else
            $(_pm) run dev -- --port ${SERVER_PORT} --host
        fi
        ;;

    react-cra)
        _install
        if [ "${NODE_RUN_ENV}" = "start" ]; then
            _run build
            npx --yes serve build -l ${SERVER_PORT} -s
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

    php|laravel|python)
        echo "======================================"
        echo " ERROR: Framework '${FW}' tidak didukung!"
        echo " PHP, Laravel, Python membutuhkan"
        echo " konfigurasi database tambahan."
        echo " Gunakan framework Node.js atau Static."
        echo "======================================"
        exit 1
        ;;

    *)
        echo "ERROR: WEB_TYPE '${FW}' tidak dikenali!"
        echo "Pilihan: auto nextjs nuxt react-vite vue react-cra express node static"
        exit 1
        ;;
esac
