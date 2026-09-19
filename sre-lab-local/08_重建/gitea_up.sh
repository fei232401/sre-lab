#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MANIFESTS="$SCRIPT_DIR/manifests"
CTX=k3d-ai-cluster

GITEA=gitea
NET=k3d-ai-cluster
HTTP_PORT=3001
SSH_PORT=2222
IMAGE=gitea/gitea:1.22
VOLUME=gitea-data
SUBNET=172.18.0.0/16
GITEA_IP=172.18.0.8
INI=/data/gitea/conf/app.ini

say()  { printf '\n== %s ==\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
warn() { printf '   warn  %s\n' "$*"; }
die()  { printf '   FAIL  %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker 不可用"
docker info >/dev/null 2>&1 || die "docker 守护进程不可用"

say "0 前置：网络"
docker network inspect "$NET" >/dev/null 2>&1 || die "网络 $NET 不存在（集群没起来？）"
ok "网络 $NET 在位"

say "1 Gitea 容器"
if docker inspect "$GITEA" >/dev/null 2>&1; then
  ok "容器存在，state=$(docker inspect "$GITEA" -f '{{.State.Status}}')"
else
  warn "容器 $GITEA 不存在 —— 需要用下面这条重建"
  echo
  echo "   docker run -d --name $GITEA --restart unless-stopped \\"
  echo "     -p ${HTTP_PORT}:3000 -p ${SSH_PORT}:22 --network $NET --ip $GITEA_IP \\"
  echo "     -e GITEA__database__DB_TYPE=sqlite3 \\"
  echo "     -e GITEA__server__DOMAIN=$GITEA \\"
  echo "     -e GITEA__server__ROOT_URL=http://$GITEA:3000/ \\"
  echo "     -e GITEA__server__SSH_DOMAIN=$GITEA \\"
  echo "     -e GITEA__server__SSH_PORT=22 \\"
  echo "     -e GITEA__security__INSTALL_LOCK=true \\"
  echo "     -e GITEA__service__DISABLE_REGISTRATION=true \\"
  echo "     -v $VOLUME:/data \\"
  echo "     $IMAGE"
  echo
  warn "--ip $GITEA_IP 是刻意固定的：k8s 里 gitea 的 Endpoints 指向它，IP 一漂移就失联"
  warn "数据在卷 $VOLUME 里。卷还在 → 仓库/webhook/app.ini 都会原样回来；卷没了 → 什么都回不来"
  warn "确认上面的命令后手动跑一次，再重跑本脚本"
  exit 1
fi

docker start "$GITEA" >/dev/null 2>&1 || true
sleep 3

if ! docker network inspect "$NET" -f '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | grep -qx "$GITEA"; then
  warn "不在 $NET 上，正在连入"
  docker network connect "$NET" "$GITEA"
fi

rp=$(docker inspect "$GITEA" -f '{{.HostConfig.RestartPolicy.Name}}')
if [ "$rp" != "unless-stopped" ]; then
  docker update --restart unless-stopped "$GITEA" >/dev/null
  ok "RestartPolicy: $rp -> unless-stopped（这条是本次事故的根因之一）"
else
  ok "RestartPolicy: unless-stopped"
fi

ip=$(docker inspect "$GITEA" -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
ok "容器 IP = $ip"

say "2 等 Gitea 就绪"
ready=no
for i in $(seq 1 40); do
  if curl -sf "http://localhost:${HTTP_PORT}/api/v1/version" >/dev/null 2>&1; then
    ok "就绪，版本 $(curl -s "http://localhost:${HTTP_PORT}/api/v1/version")"
    ready=yes
    break
  fi
  sleep 2
done
if [ "$ready" != "yes" ]; then
  die "80 秒内未就绪，看一眼 docker logs --tail 50 $GITEA"
fi

say "3 app.ini 的 webhook 白名单"
if docker exec "$GITEA" sh -c "grep -q '^ALLOWED_HOST_LIST' $INI" 2>/dev/null; then
  ok "ALLOWED_HOST_LIST 已存在"
else
  docker exec "$GITEA" sh -c "cp '$INI' '$INI.bak'"
  docker exec "$GITEA" sh -c "printf '\n[webhook]\nALLOWED_HOST_LIST = $SUBNET\n' >> '$INI'"
  docker restart "$GITEA" >/dev/null
  sleep 10
  ok "已追加 [webhook] ALLOWED_HOST_LIST = $SUBNET 并重启"
fi
docker exec "$GITEA" sh -c "grep -A1 '^\[webhook\]' $INI" | sed 's/^/   /'

curl -sf "http://localhost:${HTTP_PORT}/api/v1/version" >/dev/null 2>&1 || die "改完 app.ini 后 Gitea 没回来"

say "4 集群侧的声明式解析对象（gitea 短名 + 构建缓存）"
if command -v kubectl >/dev/null 2>&1; then
  tmp=$(mktemp)
  sed -E "s/^([[:space:]]*- )ip: .*/\1ip: $ip/" "$MANIFESTS/gitea-endpoints.yaml" > "$tmp"
  kubectl --context "$CTX" apply -f "$tmp" 2>&1 | sed 's/^/   /'
  rm -f "$tmp"
  kubectl --context "$CTX" apply -f "$MANIFESTS/buildah-storage-pvc.yaml" 2>&1 | sed 's/^/   /'
  for ns in argocd jenkins; do
    live=$(kubectl --context "$CTX" -n "$ns" get endpoints gitea \
      -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo '?')
    if [ "$live" = "$ip" ]; then
      ok "Endpoints $ns/gitea -> $live（与实际容器 IP 一致）"
    else
      warn "Endpoints $ns/gitea -> $live，与实际 IP $ip 不一致，需要人工看一眼"
    fi
  done
else
  warn "kubectl 不可用，跳过。集群内 gitea 的名字解析会退回宿主机 docker DNS（能用，但那是跨层副作用）"
fi

say "5 我要用的值（请把这一段贴回给我）"
printf '   gitea_ip     = %s\n' "$ip"
printf '   restart      = %s\n' "$(docker inspect "$GITEA" -f '{{.HostConfig.RestartPolicy.Name}}')"
printf '   host_url     = http://localhost:%s\n' "$HTTP_PORT"
printf '   in_cluster   = http://gitea:3000\n'
printf '   volume       = %s (%s)\n' "$VOLUME" "$(docker volume inspect "$VOLUME" -f '{{.Mountpoint}}' 2>/dev/null || echo '?')"

echo
ok "脚本跑完"
