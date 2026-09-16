#!/usr/bin/env bash
set -euo pipefail

CTX=k3d-ai-cluster
CLUSTER=ai-cluster
NET=k3d-ai-cluster
SUBNET=172.18.0.0/16
REG_NAME=k3d-sre-registry
REG_PORT=5111
REG_IN_CLUSTER=k3d-sre-registry:5000
GITEA=gitea
GITEA_HTTP_PORT=3001
GITEA_SSH_PORT=2222
GITEA_OWNER=fei232401
GITEA_REPO=sre-lab
GITEA_IN_CLUSTER=http://gitea:3000
JENKINS_NP=30080
K3S_IMAGE=rancher/k3s:v1.31.5-k3s1
CERTDIR=/var/lib/rancher/k3s/agent/etc/containerd/certs.d

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITOPS="$SRC/sre-lab-gitops"
SECRETS_DIR="$HOME/.sre-lab-secrets"

say()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '   \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '   \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '   \033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }

jenkins_url() { echo "http://$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' k3d-ai-cluster-server-0 | tr ' ' '\n' | grep '^172\.'):${JENKINS_NP}"; }
jenkins_pw()  { kubectl --context "$CTX" -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d; }
jenkins_user(){ kubectl --context "$CTX" -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-user}' | base64 -d; }

phase_check() {
  say "0 前置检查"
  need docker; need kubectl; need helm; need k3d; need curl
  docker info >/dev/null 2>&1 || die "docker 不可用"
  ok "docker / kubectl / helm / k3d / curl 齐备"
  for p in "$REG_PORT" "$GITEA_HTTP_PORT" "$GITEA_SSH_PORT"; do
    if docker ps --format '{{.Ports}}' | grep -q ":${p}->"; then die "宿主机端口 $p 已被占用"; fi
  done
  ok "端口 $REG_PORT / $GITEA_HTTP_PORT / $GITEA_SSH_PORT 空闲"
  for n in "$REG_NAME" "$GITEA"; do
    docker inspect "$n" >/dev/null 2>&1 && warn "容器 $n 已存在,后续步骤会跳过创建"
  done
  k3d cluster list "$CLUSTER" >/dev/null 2>&1 && warn "集群 $CLUSTER 已存在"
  mkdir -p "$SECRETS_DIR" && chmod 700 "$SECRETS_DIR"
  ok "凭据落盘目录 $SECRETS_DIR 就绪(权限 700)"
}

phase_net() {
  say "1 Docker 网络 $NET"
  if docker network inspect "$NET" >/dev/null 2>&1; then
    ok "网络已存在,复用"
  else
    # 待核实: 现场该网络创建于 2026-07-25,早于集群(2026-08-03),且带 label app=k3d。
    # 待核实: 推断它是一个更早的 k3d 集群留下的;全新重建时 k3d cluster create 会自动建同名网络,本步骤可跳过。
    # 待核实: docker network create --driver bridge --subnet "$SUBNET" --label app=k3d "$NET"
    die "网络不存在:请先跑 k3d cluster create(它会自建 $NET),或按 README「网络与 IP 段」一节手动创建"
  fi
  docker network inspect "$NET" -f '{{.IPAM.Config}}' | grep -q '172\.18\.' || die "网络 $NET 的网段不是 172.18.x"
  ok "网段确认: $(docker network inspect "$NET" -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}')"
}

phase_registry() {
  say "2 本地镜像仓库 $REG_NAME"
  if docker inspect "$REG_NAME" >/dev/null 2>&1; then
    ok "已存在,跳过创建"
  else
    # 待核实: 现场容器由 k3d 创建(名字形如 k3d-<name>),创建时间 2026-09-16 02:16,RestartPolicy=unless-stopped。
    # 待核实: k3d registry create sre-registry --port "$REG_PORT"
    # 待核实: 若不用 k3d,等价手工命令: docker run -d --name "$REG_NAME" --restart unless-stopped -p "$REG_PORT":5000 --network "$NET" registry:2
    warn "未创建,请按上面任一方式建 $REG_NAME 后重跑本阶段"
    return 0
  fi
  docker network inspect "$NET" -f '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | grep -qx "$REG_NAME" \
    || { warn "registry 不在 $NET 上,正在连入"; docker network connect "$NET" "$REG_NAME"; }
  ok "registry 已连入 $NET"
  curl -sf "http://localhost:${REG_PORT}/v2/_catalog" >/dev/null || die "registry 未就绪:curl http://localhost:${REG_PORT}/v2/_catalog 失败"
  ok "registry 可访问: http://localhost:${REG_PORT}/v2/_catalog"
}

phase_cluster() {
  say "3 k3d 集群 $CLUSTER"
  if k3d cluster list "$CLUSTER" >/dev/null 2>&1; then
    ok "集群已存在,跳过创建"
  else
    # 待核实: 集群创建命令在仓库与本地文档中均无记录(现场 k3d version v5.8.3)。
    # 待核实: 以下为按现场容器反推的重建命令,含推测成分,执行前请人工确认。
    # 待核实: k3d cluster create "$CLUSTER" \
    # 待核实:   --image "$K3S_IMAGE" \
    # 待核实:   --agents 2 --gpus all \
    # 待核实:   --api-port 0.0.0.0:46121 \
    # 待核实:   --network "$NET"
    warn "未创建,请人工确认上面反推的命令后执行,再重跑本阶段"
    return 0
  fi
  kubectl --context "$CTX" get nodes --no-headers >/dev/null || die "kubectl 连不上 $CTX"
  local n
  n=$(kubectl --context "$CTX" get nodes --no-headers | wc -l)
  [ "$n" -eq 3 ] || warn "节点数 $n,现场为 3(1 server + 2 agent)"
  ok "节点: $(kubectl --context "$CTX" get nodes --no-headers | awk '{print $1}' | tr '\n' ' ')"
}

phase_labels() {
  say "4 节点标签(所有 nodeSelector 的前提)"
  local gpu cpu
  gpu=$(kubectl --context "$CTX" get nodes -l nvidia.com/gpu=true --no-headers | awk '{print $1}' | head -1)
  cpu=$(kubectl --context "$CTX" get nodes -l node-role=cpu --no-headers | awk '{print $1}' | head -1)
  if [ -z "$gpu" ]; then
    # 待核实: 现场 agent-0 带 nvidia.com/gpu=true,agent-1 带 node-role=cpu,server-0 无这两个标签。
    kubectl --context "$CTX" label node k3d-ai-cluster-agent-0 nvidia.com/gpu=true --overwrite
    ok "已打 nvidia.com/gpu=true"
  else
    ok "nvidia.com/gpu=true 已在 $gpu"
  fi
  if [ -z "$cpu" ]; then
    kubectl --context "$CTX" label node k3d-ai-cluster-agent-1 node-role=cpu --overwrite
    ok "已打 node-role=cpu"
  else
    ok "node-role=cpu 已在 $cpu"
  fi
  kubectl --context "$CTX" get nodes --show-labels --no-headers | awk '{print "     "$1" "$6}' | grep -E 'node-role|nvidia' || true
}

phase_containerd() {
  say "5 containerd 私有仓库信任($CERTDIR)"
  local node
  for node in $(k3d node list -o json | python3 -c "import json,sys;[print(n['name']) for n in json.load(sys.stdin) if n.get('role') in ('server','agent')]"); do
    docker exec "$node" mkdir -p "$CERTDIR/$REG_IN_CLUSTER"
    docker exec "$node" sh -c "cat > '$CERTDIR/$REG_IN_CLUSTER/hosts.toml' <<'EOF'
server = \"http://$REG_IN_CLUSTER\"

[host.\"http://$REG_IN_CLUSTER\"]
  capabilities = [\"pull\", \"resolve\", \"push\"]
EOF"
    ok "$node 已写 hosts.toml"
  done
  docker exec k3d-ai-cluster-server-0 cat "$CERTDIR/$REG_IN_CLUSTER/hosts.toml" | grep -q 'capabilities' || die "hosts.toml 内容不对"
  ok "三节点一致,无需重启 k3s"
}

phase_coredns() {
  say "6 CoreDNS"
  kubectl --context "$CTX" -n kube-system get cm coredns >/dev/null || die "找不到 coredns ConfigMap"
  local h
  h=$(kubectl --context "$CTX" -n kube-system get cm coredns -o jsonpath='{.data.NodeHosts}')
  if echo "$h" | grep -q 'github.com'; then
    warn "NodeHosts 里仍有 140.82.112.3 github.com —— 这是一处已知未清理的历史残留(见 07_标本教学/02_接缝D-F)"
    warn "重建时请直接不要把它带进来"
  else
    ok "NodeHosts 无 github.com 残留"
  fi
  ok "NodeHosts: $(echo "$h" | tr '\n' ' ')"
}

phase_gitea() {
  say "7 Gitea 容器(不在 K8s 里)"
  if docker inspect "$GITEA" >/dev/null 2>&1; then
    ok "容器已存在"
  else
    # 待核实: 现场容器 gitea/gitea:1.22,创建于 2026-09-16 02:46,挂 named volume gitea-data:/data。
    # 待核实: docker run -d --name "$GITEA" \
    # 待核实:   --restart unless-stopped \
    # 待核实:   -p "$GITEA_HTTP_PORT":3000 -p "$GITEA_SSH_PORT":22 \
    # 待核实:   --network "$NET" \
    # 待核实:   -e GITEA__database__DB_TYPE=sqlite3 \
    # 待核实:   -e GITEA__server__DOMAIN=gitea \
    # 待核实:   -e GITEA__server__ROOT_URL=$GITEA_IN_CLUSTER/ \
    # 待核实:   -e GITEA__server__SSH_DOMAIN=gitea \
    # 待核实:   -e GITEA__server__SSH_PORT=22 \
    # 待核实:   -e GITEA__security__INSTALL_LOCK=true \
    # 待核实:   -e GITEA__service__DISABLE_REGISTRATION=true \
    # 待核实:   -v gitea-data:/data \
    # 待核实:   gitea/gitea:1.22
    warn "未创建,请人工确认上面反推的命令后执行,再重跑本阶段"
    return 0
  fi
  docker network inspect "$NET" -f '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | grep -qx "$GITEA" \
    || { warn "gitea 不在 $NET 上,正在连入"; docker network connect "$NET" "$GITEA"; }
  local rp
  rp=$(docker inspect "$GITEA" -f '{{.HostConfig.RestartPolicy.Name}}')
  if [ "$rp" = "no" ]; then
    warn "RestartPolicy=no —— 宿主重启后 Gitea 不会自己回来。现场就是这个值,是已知缺陷"
    warn "重建时建议改成 unless-stopped(会偏离现场,但更正确):docker update --restart unless-stopped $GITEA"
  else
    ok "RestartPolicy=$rp"
  fi
  curl -sf "http://localhost:${GITEA_HTTP_PORT}/api/v1/version" >/dev/null || die "Gitea HTTP 未就绪"
  ok "Gitea 可访问: http://localhost:${GITEA_HTTP_PORT}"
}

phase_gitea_ini() {
  say "8 Gitea app.ini 的 webhook 白名单"
  local ini=/data/gitea/conf/app.ini
  if docker exec "$GITEA" cat "$ini" | grep -q '^ALLOWED_HOST_LIST'; then
    ok "ALLOWED_HOST_LIST 已存在"
  else
    docker exec "$GITEA" sh -c "cp '$ini' '$ini.bak'"
    docker exec "$GITEA" sh -c "printf '\n[webhook]\nALLOWED_HOST_LIST = $SUBNET\n' >> '$ini'"
    ok "已追加 [webhook] ALLOWED_HOST_LIST = $SUBNET(备份在 $ini.bak)"
  fi
  docker restart "$GITEA" >/dev/null
  sleep 5
  docker exec "$GITEA" grep -A1 '^\[webhook\]' "$ini" | sed 's/^/     /'
  curl -sf "http://localhost:${GITEA_HTTP_PORT}/api/v1/version" >/dev/null || die "Gitea 重启后未恢复"
  ok "Gitea 已重启并就绪"
}

phase_gitea_repo() {
  say "9 Gitea 仓库与 webhook 定义"
  local token repo_url
  read -rsp "   请输入 Gitea 访问令牌(scope 需含 write:repository): " token; echo
  [ -n "$token" ] || die "令牌为空"
  local api="http://localhost:${GITEA_HTTP_PORT}/api/v1"
  if curl -sf -H "Authorization: token $token" "$api/repos/$GITEA_OWNER/$GITEA_REPO" >/dev/null; then
    ok "仓库 $GITEA_OWNER/$GITEA_REPO 已存在"
  else
    curl -sf -H "Authorization: token $token" -H 'Content-Type: application/json' \
      -X POST "$api/user/repos" \
      -d "{\"name\":\"$GITEA_REPO\",\"private\":false,\"auto_init\":false}" >/dev/null
    ok "已创建仓库 $GITEA_OWNER/$GITEA_REPO"
  fi
  local jurl; jurl="$(jenkins_url)/generic-webhook-trigger/invoke"
  if curl -sf -H "Authorization: token $token" "$api/repos/$GITEA_OWNER/$GITEA_REPO/hooks" | grep -q 'generic-webhook-trigger'; then
    ok "webhook 已存在"
  else
    read -rsp "   请输入 Jenkins 凭据 gitea-webhook-token 的值: " wh; echo
    [ -n "$wh" ] || die "webhook token 为空"
    curl -sf -H "Authorization: token $token" -H 'Content-Type: application/json' \
      -X POST "$api/repos/$GITEA_OWNER/$GITEA_REPO/hooks" \
      -d "{\"type\":\"gitea\",\"active\":true,\"events\":[\"push\"],\"config\":{\"url\":\"$jurl?token=$wh\",\"content_type\":\"json\"}}" >/dev/null
    ok "webhook 已创建 -> $jurl"
  fi
  warn "这两项都在 Gitea 数据库里,不在 Git 里 —— 集群重建会丢"
}

phase_argocd() {
  say "10 ArgoCD(必须先于所有 Application)"
  if helm --kube-context "$CTX" status argocd -n argocd >/dev/null 2>&1; then
    ok "release 已存在,跳过安装"
  else
    helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
    helm repo update argo >/dev/null
    # 待核实: 现场 chart argo-cd-10.9.1 / app v3.5.3,revision 1,values 取自 production/argocd/argocd-values.yaml(现场比对该文件一致)。
    # 待核实: helm --kube-context "$CTX" install argocd argo/argo-cd -n argocd --create-namespace \
    # 待核实:   --version 10.9.1 -f "$GITOPS/production/argocd/argocd-values.yaml"
    warn "未安装,请人工确认上面命令后执行,再重跑本阶段"
    return 0
  fi
  kubectl --context "$CTX" -n argocd rollout status deploy/argocd-server --timeout=300s
  ok "argocd-server 就绪"
  kubectl --context "$CTX" -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1 \
    && warn "初始管理员密码在 secret argocd-initial-admin-secret(改密后此 secret 应删除)"
}

phase_jenkins() {
  say "11 Jenkins"
  if helm --kube-context "$CTX" status jenkins -n jenkins >/dev/null 2>&1; then
    ok "release 已存在,跳过安装"
  else
    helm repo add jenkins https://charts.jenkins.io >/dev/null 2>&1 || true
    helm repo update jenkins >/dev/null
    # 待核实: 现场 chart jenkins-5.9.62 / app 2.568.3,revision 4,values 取自 production/helm-values/jenkins-values.yaml(现场比对该文件一致)。
    # 待核实: helm --kube-context "$CTX" install jenkins jenkins/jenkins -n jenkins --create-namespace \
    # 待核实:   --version 5.9.62 -f "$GITOPS/production/helm-values/jenkins-values.yaml"
    warn "未安装,请人工确认上面命令后执行,再重跑本阶段"
    return 0
  fi
  kubectl --context "$CTX" -n jenkins wait --for=condition=ready pod -l app.kubernetes.io/component=jenkins-controller --timeout=1200s \
    || warn "Jenkins 未就绪:init 容器在重下插件,分钟级,不是故障(见 03_Jenkins_运行手册.md 第四节)"
  ok "Jenkins: $(jenkins_url)"
  k3d node list >/dev/null
}

phase_jenkins_job() {
  say "12 Jenkins 任务与凭据"
  local JH; JH="$(jenkins_url)"
  local JU; JU="$(jenkins_user)"
  local JP; JP="$(jenkins_pw)"
  local jar=/tmp/sre-rebuild-cookies
  local crumb
  crumb=$(curl -s -c "$jar" -u "$JU:$JP" "$JH/crumbIssuer/api/json" | grep -o '"crumb":"[^"]*"' | cut -d'"' -f4)
  [ -n "$crumb" ] || die "取 crumb 失败(403 先看 cookie,见 03_Jenkins_运行手册.md 第三节)"
  ok "crumb 已取(与 cookie jar 绑定)"

  if curl -sf -u "$JU:$JP" "$JH/job/sre-lab-ci/api/json" >/dev/null 2>&1; then
    ok "任务 sre-lab-ci 已存在"
  else
    cat > /tmp/sre-lab-ci.config.xml <<'XML'
<?xml version="1.1" encoding="UTF-8"?>
<flow-definition plugin="workflow-job">
  <description>sre-lab 容器镜像构建流水线</description>
  <keepDependencies>false</keepDependencies>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition">
    <scm class="hudson.plugins.git.GitSCM">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>http://gitea:3000/fei232401/sre-lab.git</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <extensions/>
    </scm>
    <scriptPath>ci/Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <disabled>false</disabled>
</flow-definition>
XML
    curl -s -b "$jar" -u "$JU:$JP" -H "Jenkins-Crumb: $crumb" -X POST \
      "$JH/createItem?name=sre-lab-ci" \
      --data-urlencode "xml@/tmp/sre-lab-ci.config.xml" >/dev/null
    ok "任务 sre-lab-ci 已创建(triggers 由 Jenkinsfile 提供,首次需手动跑一次)"
  fi

  if curl -s -u "$JU:$JP" "$JH/credentials/store/system/domain/_/api/json?tree=credentials%5Bid%5D" | grep -q 'gitea-webhook-token'; then
    ok "凭据 gitea-webhook-token 已存在"
  else
    read -rsp "   请输入要写入 Jenkins 凭据 gitea-webhook-token 的值: " wh; echo
    cat > /tmp/sre-cred.json <<JSON
{"credentials":{"scope":"GLOBAL","id":"gitea-webhook-token","description":"Gitea push webhook token for sre-lab-ci","\$class":"org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl","secret":"$wh"}}
JSON
    curl -s -b "$jar" -u "$JU:$JP" -H "Jenkins-Crumb: $crumb" -X POST \
      "$JH/credentials/store/system/domain/_/createCredentials" \
      --data-urlencode "json@/tmp/sre-cred.json" >/dev/null
    rm -f /tmp/sre-cred.json
    ok "凭据已创建"
  fi

  kubectl --context "$CTX" apply -f "$GITOPS/production/ci/buildah-registries.yaml"
  ok "configmap buildah-registries 已应用(构建 Pod 靠它认 insecure 仓库)"
}

phase_apps() {
  say "13 六个 ArgoCD Application"
  local d="$GITOPS/production/bootstrap"
  local f
  for f in ai-platform-app loki monitoring-app nginx-app promtail sealed-secrets-app; do
    kubectl --context "$CTX" apply -f "$d/$f.yaml" >/dev/null
    ok "已应用 $f"
  done
  warn "root-app.yaml 在 Git 里存在,但现场并未 apply —— 这 6 个 Application 是手工 kubectl apply 的,不受 ArgoCD 自管"
  warn "若要改用 root-app 自管,注意它带 prune: true,会删掉不在 bootstrap 目录里的资源;先读 README 再决定"
  kubectl --context "$CTX" -n argocd annotate application --all argocd.argoproj.io/refresh=hard --overwrite >/dev/null
  ok "已请求硬刷新"
  sleep 15
  kubectl --context "$CTX" -n argocd get applications \
    -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' --no-headers | sed 's/^/     /'
}

phase_snapshot() {
  say "S 拆除前导出(在动手删任何东西之前跑)"
  helm --kube-context "$CTX" get values monitoring -n monitoring -o yaml > "$SECRETS_DIR/monitoring-live-values.yaml"
  chmod 600 "$SECRETS_DIR/monitoring-live-values.yaml"
  warn "$SECRETS_DIR/monitoring-live-values.yaml 含 grafana 管理员密码,严禁入 Git"
  helm --kube-context "$CTX" get values jenkins -n jenkins -o yaml > "$SECRETS_DIR/jenkins-live-values.yaml"
  chmod 600 "$SECRETS_DIR/jenkins-live-values.yaml"
  helm --kube-context "$CTX" get values argocd -n argocd -o yaml > "$SECRETS_DIR/argocd-live-values.yaml"
  chmod 600 "$SECRETS_DIR/argocd-live-values.yaml"
  kubectl --context "$CTX" -n kube-system get secret \
    -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > "$SECRETS_DIR/sealed-secrets.key.yaml"
  chmod 600 "$SECRETS_DIR/sealed-secrets.key.yaml"
  warn "$SECRETS_DIR/sealed-secrets.key.yaml 是 Sealed Secrets 私钥,丢了所有 SealedSecret 都解不开"
  ok "已导出到 $SECRETS_DIR"
}

check_build_cause() {
  local JH; JH="$(jenkins_url)"; local JU; JU="$(jenkins_user)"; local JP; JP="$(jenkins_pw)"
  local last
  last=$(curl -sf -u "$JU:$JP" "$JH/job/sre-lab-ci/api/json?tree=lastBuild%5Bnumber%5D" | python3 -c 'import json,sys;print(json.load(sys.stdin)["lastBuild"]["number"])' 2>/dev/null || echo '')
  [ -n "$last" ] || { echo "   ✗ 取不到构建号"; return 1; }
  local cause
  cause=$(curl -sf -u "$JU:$JP" "$JH/job/sre-lab-ci/$last/api/json?tree=actions%5Bcauses%5BshortDescription%5D%5D" \
    | python3 -c 'import json,sys
for a in json.load(sys.stdin)["actions"]:
    for c in a.get("causes",[]): print(c["shortDescription"])' 2>/dev/null | head -1)
  echo "   #$last 触发原因: $cause"
  case "$cause" in
    "Gitea push"*) echo "   ✓ (a) 由 Gitea push 触发,链路通"; return 0 ;;
    "Started by user"*) echo "   ✗ (a) 是手动触发的 —— 这一条不能证明链路"; return 1 ;;
    *) echo "   ✗ (a) 触发原因不是 Gitea push: $cause"; return 1 ;;
  esac
}

check_guard_branches() {
  local JH; JH="$(jenkins_url)"; local JU; JU="$(jenkins_user)"; local JP; JP="$(jenkins_pw)"
  local last hit=0 skip=0 n body
  last=$(curl -sf -u "$JU:$JP" "$JH/job/sre-lab-ci/api/json?tree=lastBuild%5Bnumber%5D" | python3 -c 'import json,sys;print(json.load(sys.stdin)["lastBuild"]["number"])' 2>/dev/null || echo '')
  [ -n "$last" ] || { echo "   ✗ 取不到构建号"; return 1; }
  for n in $(seq $((last>8?last-7:1)) "$last"); do
    body=$(curl -sf -u "$JU:$JP" "$JH/job/sre-lab-ci/$n/consoleText" 2>/dev/null || true)
    echo "$body" | grep -q '命中构建路径,继续流水线' && { echo "   #$n 闸门=命中(构建)"; hit=1; }
    echo "$body" | grep -q '跳过构建' && { echo "   #$n 闸门=跳过"; skip=1; }
  done
  if [ "$hit" = 1 ] && [ "$skip" = 1 ]; then echo "   ✓ (b) 两个分支都出现过"; return 0; fi
  echo "   ✗ (b) 分支未覆盖:命中=$hit 跳过=$skip"; return 1
}

check_build_info() {
  local pod tag rev
  pod=$(kubectl --context "$CTX" -n ai-platform get pods --no-headers \
        | awk '$3=="Running"{print $1}' | grep '^ollama-exporter' | head -1)
  [ -n "$pod" ] || { echo "   ✗ 找不到 Running 的 ollama-exporter Pod"; return 1; }
  tag=$(kubectl --context "$CTX" -n ai-platform get pod "$pod" -o jsonpath='{.spec.containers[0].image}' | awk -F: '{print $NF}')
  rev=$(kubectl --context "$CTX" -n ai-platform exec "$pod" -- python -c "
import urllib.request, re
t = urllib.request.urlopen('http://127.0.0.1:9101/metrics', timeout=10).read().decode()
m = [l for l in t.splitlines() if l.startswith('sre_lab_build_info{')]
print(re.search(r'revision=\"([^\"]*)\"', m[0]).group(1) if m else '')" 2>/dev/null || true)
  echo "   Pod=$pod  镜像 tag=$tag  自报 revision=$rev"
  [ -n "$rev" ] || { echo "   ✗ (c) 指标为空 —— 注意采样时要看清采的是哪个 Pod,滚动期会有新旧两代并存"; return 1; }
  [ "$rev" = "$tag" ] && { echo "   ✓ (c) 运行时自报版本与镜像 tag 一致"; return 0; }
  echo "   ✗ (c) 不一致: tag=$tag revision=$rev"; return 1
}

phase_verify() {
  say "14 三项静默失败验收"
  local rc=0
  curl -sf "http://localhost:${REG_PORT}/v2/${GITEA_REPO}/ollama-exporter/tags/list" >/dev/null 2>&1 \
    && ok "registry 有 sre-lab/ollama-exporter" || true
  check_build_cause    || rc=1
  check_guard_branches || rc=1
  check_build_info     || rc=1
  echo
  [ "$rc" = 0 ] && ok "三项全过" || warn "有未通过项 —— 这三项都是「不报错但没在工作」的那一类,必须逐条查清"
  return "$rc"
}

usage() {
  cat <<EOF
用法: 重建.sh <阶段>

  check       0  前置检查
  net         1  Docker 网络
  registry    2  本地镜像仓库
  cluster     3  k3d 集群
  labels      4  节点标签
  containerd  5  containerd 私有仓库信任
  coredns     6  CoreDNS
  gitea       7  Gitea 容器
  gitea-ini   8  app.ini webhook 白名单
  gitea-repo  9  Gitea 仓库 + webhook 定义
  argocd      10 ArgoCD
  jenkins     11 Jenkins
  jenkins-job 12 Jenkins 任务 + 凭据 + configmap
  apps        13 六个 Application
  verify      14 三项验收
  snapshot    S  拆除前导出(先跑这个)

  all         0..14 依序执行(不含 snapshot)
EOF
}

case "${1:-}" in
  check|"")    phase_check ;;
  1|net)       phase_net ;;
  2|registry)  phase_registry ;;
  3|cluster)   phase_cluster ;;
  4|labels)    phase_labels ;;
  5|containerd) phase_containerd ;;
  6|coredns)   phase_coredns ;;
  7|gitea)     phase_gitea ;;
  8|gitea-ini) phase_gitea_ini ;;
  9|gitea-repo) phase_gitea_repo ;;
  10|argocd)   phase_argocd ;;
  11|jenkins)  phase_jenkins ;;
  12|jenkins-job) phase_jenkins_job ;;
  13|apps)     phase_apps ;;
  14|verify)   phase_verify ;;
  S|snapshot)  phase_snapshot ;;
  all)
    phase_check; phase_net; phase_registry; phase_cluster; phase_labels
    phase_containerd; phase_coredns; phase_gitea; phase_gitea_ini; phase_gitea_repo
    phase_argocd; phase_jenkins; phase_jenkins_job; phase_apps; phase_verify
    ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
