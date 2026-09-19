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
  echo "     -p ${HTTP_PORT}:3000 -p ${SSH_PORT}:22 --network $NET \\"
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
  warn "刻意【不】写 --ip：容器 IP 由 docker 按创建顺序分配，写死它反而会和 k3s 节点撞号"
  warn "（172.18.0.8 现在是 k3d-ai-cluster-server-0）。集群侧走网关 $NET 的 .1，不需要固定容器 IP"
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
  # 集群侧走的是「k3d 网络网关 + 宿主发布端口」，不是容器 IP。
  # 这两个值都从活体 docker 读，不写死 —— 网络重建换了网段/端口也能自动跟上。
  gw=$(docker network inspect "$NET" -f '{{(index .IPAM.Config 0).Gateway}}')
  pub=$(docker inspect "$GITEA" -f '{{(index (index .NetworkSettings.Ports "3000/tcp") 0).HostPort}}')
  ok "网关 = $gw   宿主发布端口 = $pub"

  kubectl --context "$CTX" apply -f "$MANIFESTS/gitea-endpoints.yaml" 2>&1 | sed 's/^/   /'
  kubectl --context "$CTX" apply -f "$MANIFESTS/buildah-storage-pvc.yaml" 2>&1 | sed 's/^/   /'

  for ns in argocd jenkins; do
    eip=$(kubectl --context "$CTX" -n "$ns" get endpoints gitea \
      -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo '?')
    ept=$(kubectl --context "$CTX" -n "$ns" get endpoints gitea \
      -o jsonpath='{.subsets[0].ports[0].port}' 2>/dev/null || echo '?')
    if [ "$eip" = "$gw" ] && [ "$ept" = "$pub" ]; then
      ok "Endpoints $ns/gitea -> $eip:$ept（与活体网关/端口一致）"
    else
      warn "Endpoints $ns/gitea -> $eip:$ept，但活体是 $gw:$pub —— 不一致，需人工看一眼"
    fi
  done

  # 声明式对象长得对 ≠ 真的通。这一步从集群**内部**实测，把静默失效变成红字。
  say "4b 集群内实测 http://gitea:3000（这才是 ArgoCD/Jenkins 走的路径）"
  probe=ok
  for ns in argocd jenkins; do
    out=$(kubectl --context "$CTX" -n "$ns" run "gitea-probe-$RANDOM" --rm -i --restart=Never \
      --image=busybox:1.36 --timeout=45s --quiet -- \
      wget -q -O- -T 8 http://gitea:3000/api/v1/version 2>/dev/null || true)
    if printf '%s' "$out" | grep -q '"version"'; then
      ok "$ns 内可达：$out"
    else
      probe=fail
      warn "$ns 内**不可达** —— ArgoCD/Jenkins 会 connection refused，去查上面两步"
    fi
  done
  [ "$probe" = ok ] || die "集群内 gitea 解析对象没通，别急着往下走"

  echo
  warn "记住这条路径的失效条件：Gitea 一旦不再发布宿主端口 $pub，上面的 Endpoints 立刻失效"
  warn "（集群侧不报错，只有消费方 connection refused）。改了端口/网络就重跑本脚本。"
else
  warn "kubectl 不可用，跳过。集群内 gitea 的名字解析会退回宿主机 docker DNS（能用，但那是跨层副作用）"
fi

say "5 我要用的值（请把这一段贴回给我）"
printf '   gitea_ip     = %s（仅供参考，**没有任何声明式对象依赖它**）\n' "$ip"
printf '   restart      = %s\n' "$(docker inspect "$GITEA" -f '{{.HostConfig.RestartPolicy.Name}}')"
printf '   host_url     = http://localhost:%s\n' "$HTTP_PORT"
printf '   in_cluster   = http://gitea:3000（Service 端口 3000 → 网关:宿主端口）\n'
printf '   volume       = %s (%s)\n' "$VOLUME" "$(docker volume inspect "$VOLUME" -f '{{.Mountpoint}}' 2>/dev/null || echo '?')"

echo
ok "脚本跑完"
