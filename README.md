온프레미스 3-Tier 아키텍처 상세 기획서 (v3.0)
1. 인프라 및 네트워크 기본 구성
로드밸런서: MetalLB (L2 모드)를 사용하여 IP Address Pool 10.10.8.200 - 10.10.8.250 대역을 할당합니다.

스토리지: 마스터 노드(10.10.8.130)에 NFS 서버를 구축하고, K8s 내부에 정적(Static) StorageClass를 생성하여 PV/PVC를 통해 DB 데이터의 영속성을 보장합니다.

CNI 및 관측성: Cilium eBPF를 CNI로 사용하며, Hubble Relay 및 UI를 활성화하여 트래픽 맵을 시각화하고 Network Policy에 의해 Drop된 패킷을 실시간 모니터링합니다.

2. 보안 및 네트워크 정책 (Cilium Network Policy)
자격 증명: MySQL 루트 암호(dkagh1.)는 Kustomize의 secretGenerator를 통해 동적으로 Secret을 생성하여 환경 변수에 안전하게 주입합니다.

Default Deny: himedia-3tier 네임스페이스 내의 모든 Ingress 및 Egress 통신을 기본적으로 전면 차단합니다.

Whitelist (허용 정책):

Frontend: 외부(World) IP에서 들어오는 80번 포트 Ingress를 허용하고, Backend(5000번 포트)로 향하는 Egress를 허용합니다.

Backend: Frontend 파드에서 들어오는 5000번 포트 Ingress를 허용하고, Database(3306번 포트)로 향하는 Egress를 허용합니다.

Database: Backend 파드에서 들어오는 3306번 포트 Ingress만을 허용합니다.

공통: 서비스 디스커버리를 위해 Kube-DNS(53번 포트, UDP/TCP)와의 통신을 모든 파드에 허용합니다.

3. 컴포넌트 별 상세 배포 전략
Tier 1: Web Server (Frontend - Nginx)

구조: 단순 HTML 웹 서버입니다. Kustomize configMapGenerator를 활용하여 index.html과 nginx.conf를 동적 생성 및 Nginx 컨테이너에 마운트합니다.

스케줄링: Deployment 리소스를 사용하며, Replicas는 3으로 설정합니다.

고가용성: PodAntiAffinity(topologyKey: kubernetes.io/hostname)를 적용하여 3대의 워커 노드(10.10.8.131~133)에 Nginx 파드가 정확히 1개씩 분산 배치되도록 강제합니다.

안정성:

자원 할당: Request(CPU 100m, Mem 64Mi) / Limit(CPU 200m, Mem 128Mi)

Probes: / 경로로 HTTP GET 요청을 보내는 Liveness/Readiness Probe 구성.

Graceful Shutdown: lifecycle.preStop 훅을 설정하여 파드 종료 시 sleep 명령을 통해 Nginx가 기존 연결을 안전하게 마무리할 시간을 부여합니다.

Tier 2: Application (Backend - Flask)

구조: Python 3.9 환경에서 Flask와 PyMySQL을 사용합니다.

스케줄링 & 고가용성: Deployment (Replicas 3) 및 PodAntiAffinity를 통한 워커 노드 분산 배치.

시작 제어 (InitContainer): 파드 기동 시 메인 컨테이너보다 먼저 실행되는 initContainers를 삽입하여, DB(3306 포트)로 nc -z 통신이 성공할 때까지 대기하도록 설계하여 의존성 충돌을 방지합니다.

안정성:

자원 할당: Request(CPU 200m, Mem 128Mi) / Limit(CPU 500m, Mem 256Mi)

Probes: /health 엔드포인트를 구현하여 Liveness/Readiness Probe 설정.

Graceful Shutdown: SIGTERM 수신 전 preStop 훅을 통해 처리 중인 트랜잭션이 끊기지 않도록 대기 시간을 부여합니다.

확장성(HPA):

metrics-server를 비보안(non-tls, --kubelet-insecure-tls) 기반으로 클러스터에 설치합니다.

CPU 사용량이 70%에 도달할 경우, 파드가 최대 5개까지 스케일 아웃(Scale-out)되도록 HPA를 구성합니다.

Tier 3: Database (MySQL 8.0)

구조: 단일 인스턴스(Replicas: 1) 기반의 StatefulSet을 사용하여 완벽한 데이터 정합성을 보장합니다.

초기화 (Init.sql): Kustomize configMapGenerator로 DDL/DML 초기화 스크립트를 주입하고, /docker-entrypoint-initdb.d/에 마운트합니다.

departments 테이블: department_id (PK), dept_name

employees 테이블: employee_id (PK), last_name, first_name, phone, address, salary, department_id (FK)

초기 데이터 적재: 애플리케이션 테스트를 즉시 수행할 수 있도록, departments 테이블에 10개, employees 테이블에 10개의 적합한 레코드를 INSERT 하는 구문을 명시적으로 포함합니다.

안정성:

자원 할당: Request(CPU 500m, Mem 512Mi) / Limit(CPU 1000m, Mem 1Gi)

Probes: mysqladmin ping 헬스 체크 구성.

4. 관측성 (Observability)
코드 출력 시, Cilium CLI를 통해 Hubble Relay 및 UI를 활성화하고 브라우저로 접속하여 트래픽 및 Drop 패킷을 모니터링하는 명확한 가이드 명령어를 함께 제공합니다.

5. Kustomize 기반 선언적 배포 아키텍처
모든 매니페스트 파일은 분리되어 작성되며, kustomization.yaml을 진입점으로 하여 통합 관리됩니다. 특히 환경 변수(Secret)나 설정 파일(ConfigMap)이 변경될 경우, Kustomize Generator가 해시값을 재생성하여 연관된 파드들의 롤링 업데이트를 자동으로 트리거하는 최적의 배포 파이프라인을 구축합니다.



manifest codes
작업 디렉터리 생성
mkdir himedia-3tier && cd himedia-3tier
NFS 서버 설치
install-nfs.sh
#!/bin/bash

# 1. 패키지 업데이트 및 NFS 커널 서버 설치
echo "NFS 서버 패키지를 설치합니다..."
sudo apt-get update
sudo apt-get install -y nfs-kernel-server

# 2. NFS 마운트 포인트 디렉토리 생성
echo "NFS 마운트 경로(/srv/nfs/himedia)를 생성합니다..."
sudo mkdir -p /srv/nfs/himedia

# 3. 디렉토리 소유권 및 권한 설정 (K8s 파드 접근 허용)
echo "디렉토리 권한을 설정합니다..."
sudo chown nobody:nogroup /srv/nfs/himedia
sudo chmod 777 /srv/nfs/himedia

# 4. /etc/exports 파일에 공유 설정 추가
echo "NFS 공유 설정을 적용합니다..."
# 기존 설정과 중복되지 않도록 처리 후 추가
sudo sed -i '/\/srv\/nfs\/himedia/d' /etc/exports
echo "/srv/nfs/himedia 10.10.8.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports

# 5. NFS 서비스 재시작 및 설정 반영
echo "NFS 서비스를 재시작합니다..."
sudo systemctl restart nfs-kernel-server
sudo exportfs -a

# 6. 최종 검증
echo "구축 완료. 현재 마운트 가능 상태를 확인합니다:"
showmount -e 127.0.0.1

네임 스페이스 생성

00-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: himedia-3tier
  labels:
    name: himedia-3tier

메트릭 서버 설치

01-metrics-server.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:aggregated-metrics-reader
  labels:
    rbac.authorization.k8s.io/aggregate-to-admin: "true"
    rbac.authorization.k8s.io/aggregate-to-edit: "true"
    rbac.authorization.k8s.io/aggregate-to-view: "true"
rules:
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods", "nodes"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:metrics-server
rules:
- apiGroups: [""]
  resources: ["nodes/metrics", "pods", "nodes"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: metrics-server-auth-reader
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: extension-apiserver-authentication-reader
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: metrics-server:system:auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:metrics-server
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:metrics-server
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
---
apiVersion: v1
kind: Service
metadata:
  name: metrics-server
  namespace: kube-system
spec:
  ports:
  - name: https
    port: 443
    targetPort: https
  selector:
    k8s-app: metrics-server
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-server
  namespace: kube-system
  labels:
    k8s-app: metrics-server
spec:
  selector:
    matchLabels:
      k8s-app: metrics-server
  template:
    metadata:
      labels:
        k8s-app: metrics-server
    spec:
      serviceAccountName: metrics-server
      containers:
      - name: metrics-server
        image: registry.k8s.io/metrics-server/metrics-server:v0.6.4
        args:
        - --cert-dir=/tmp
        - --secure-port=4443
        - --kubelet-insecure-tls
        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
        ports:
        - name: https
          containerPort: 4443
          protocol: TCP
---
apiVersion: apiregistration.k8s.io/v1
kind: APIService
metadata:
  name: v1beta1.metrics.k8s.io
spec:
  service:
    name: metrics-server
    namespace: kube-system
  group: metrics.k8s.io
  version: v1beta1
  insecureSkipTLSVerify: true
  groupPriorityMinimum: 100
  versionPriority: 100



Metallb 설치 (기존 설치된 경우 건너띄기)

02-metallb.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: himedia-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.10.8.240-10.10.8.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: himedia-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - himedia-pool

스토리지 생성

03-storage.yaml

apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-static
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: himedia-mysql-pv
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs-static
  nfs:
    path: /srv/nfs/himedia
    server: 10.10.8.130
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
  namespace: himedia-3tier
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nfs-static
  resources:
    requests:
      storage: 10Gi

데이타베이스

04-database.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: mysql-init-config
  namespace: himedia-3tier
data:
  init.sql: |
    CREATE DATABASE IF NOT EXISTS himedia;
    USE himedia;

    CREATE TABLE IF NOT EXISTS departments (
        department_id INT AUTO_INCREMENT PRIMARY KEY,
        dept_name VARCHAR(100) NOT NULL
    );

    CREATE TABLE IF NOT EXISTS employees (
        employee_id INT AUTO_INCREMENT PRIMARY KEY,
        last_name VARCHAR(50) NOT NULL,
        first_name VARCHAR(50) NOT NULL,
        phone VARCHAR(20),
        address VARCHAR(200),
        salary DECIMAL(10,2),
        department_id INT,
        FOREIGN KEY (department_id) REFERENCES departments(department_id)
    );

    INSERT INTO departments (dept_name) VALUES
    ('Engineering'), ('Human Resources'), ('Sales'), ('Marketing'), ('Finance'),
    ('IT Support'), ('Legal'), ('Research & Development'), ('Customer Success'), ('Operations');

    INSERT INTO employees (last_name, first_name, phone, address, salary, department_id) VALUES
    ('Kim', 'Kubernet', '010-1111-1111', 'Seoul', 100000.00, 1),
    ('Lee', 'Flask', '010-2222-2222', 'Busan', 85000.00, 2),
    ('Park', 'Nginx', '010-3333-3333', 'Incheon', 90000.00, 3),
    ('Choi', 'Cilium', '010-4444-4444', 'Daegu', 95000.00, 4),
    ('Jung', 'Hubble', '010-5555-5555', 'Gwangju', 88000.00, 5),
    ('Kang', 'MetalLB', '010-6666-6666', 'Daejeon', 92000.00, 6),
    ('Cho', 'Docker', '010-7777-7777', 'Ulsan', 87000.00, 7),
    ('Yoon', 'Linux', '010-8888-8888', 'Sejong', 91000.00, 8),
    ('Jang', 'Python', '010-9999-9999', 'Jeju', 89000.00, 9),
    ('Lim', 'Cloud', '010-0000-0000', 'Seoul', 105000.00, 10);
---
apiVersion: v1
kind: Service
metadata:
  name: mysql-svc
  namespace: himedia-3tier
spec:
  clusterIP: None
  ports:
  - port: 3306
  selector:
    app: mysql
    tier: database
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql-sts
  namespace: himedia-3tier
spec:
  serviceName: "mysql-svc"
  replicas: 1
  selector:
    matchLabels:
      app: mysql
      tier: database
  template:
    metadata:
      labels:
        app: mysql
        tier: database
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: ROOT_PASSWORD
        - name: MYSQL_DATABASE
          value: "himedia"
        ports:
        - containerPort: 3306
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        livenessProbe:
          exec:
            command: ["mysqladmin", "ping", "-h", "localhost", "-uroot", "-pdkagh1."]
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command: ["mysqladmin", "ping", "-h", "localhost", "-uroot", "-pdkagh1."]
          initialDelaySeconds: 15
          periodSeconds: 5
        volumeMounts:
        - name: mysql-storage
          mountPath: /var/lib/mysql
        - name: init-script
          mountPath: /docker-entrypoint-initdb.d
      volumes:
      - name: mysql-storage
        persistentVolumeClaim:
          claimName: mysql-pvc
      - name: init-script
        configMap:
          name: mysql-init-config

백엔드

05-backend.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: flask-config
  namespace: himedia-3tier
data:
  app.py: |
    from flask import Flask, jsonify
    import pymysql, os, time, signal, sys

    app = Flask(__name__)

    def get_db():
        return pymysql.connect(
            host=os.environ.get('DB_HOST', 'mysql-svc'),
            user='root',
            password=os.environ.get('DB_PASSWORD'),
            database=os.environ.get('DB_NAME', 'himedia'),
            cursorclass=pymysql.cursors.DictCursor
        )

    @app.route('/health')
    def health(): return jsonify({"status": "UP"}), 200

    @app.route('/api/employees')
    def employees():
        try:
            conn = get_db()
            with conn.cursor() as cursor:
                cursor.execute("SELECT e.last_name, e.first_name, d.dept_name, e.salary FROM employees e JOIN departments d ON e.department_id = d.department_id")
                res = cursor.fetchall()
            conn.close()
            return jsonify({"status": "success", "data": res})
        except Exception as e:
            return jsonify({"status": "error", "message": str(e)}), 500

    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=5000)
---
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
  namespace: himedia-3tier
spec:
  ports:
  - port: 5000
    targetPort: 5000
  selector:
    app: flask
    tier: backend
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-deploy
  namespace: himedia-3tier
spec:
  replicas: 3
  selector:
    matchLabels:
      app: flask
      tier: backend
  template:
    metadata:
      labels:
        app: flask
        tier: backend
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector: { matchExpressions: [{ key: app, operator: In, values: [flask] }] }
            topologyKey: "kubernetes.io/hostname"
      initContainers:
      - name: wait-for-db
        image: busybox:1.28
        command: ['sh', '-c', 'until nc -z mysql-svc 3306; do echo waiting for db; sleep 2; done;']
      containers:
      - name: flask
        image: python:3.9-slim
        command: ["/bin/bash", "-c"]
        # 에러 해결을 위해 cryptography 패키지가 추가된 부분입니다.
        args: ["pip install flask pymysql cryptography && python /app/app.py"]
        lifecycle:
          preStop:
            exec: { command: ["sleep", "5"] }
        env:
        - name: DB_HOST
          value: "mysql-svc"
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: ROOT_PASSWORD
        - name: DB_NAME
          value: "himedia"
        ports:
        - containerPort: 5000
        resources:
          requests: { cpu: 200m, memory: 128Mi }
          limits: { cpu: 500m, memory: 256Mi }
        livenessProbe:
          httpGet: { path: /health, port: 5000 }
          initialDelaySeconds: 15
          periodSeconds: 10
        readinessProbe:
          httpGet: { path: /health, port: 5000 }
          initialDelaySeconds: 5
          periodSeconds: 5
        volumeMounts:
        - name: code-volume
          mountPath: /app
      volumes:
      - name: code-volume
        configMap:
          name: flask-config
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-hpa
  namespace: himedia-3tier
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend-deploy
  minReplicas: 3
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
vagrant@k8s-master-01:~/himedia-3tier$

프론트엔드

06-frontend.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: frontend-config
  namespace: himedia-3tier
data:
  default.conf: |
    server {
        listen 80;
        server_name localhost;
        location / { root /usr/share/nginx/html; index index.html; }
        location /api/ { proxy_pass http://backend-svc:5000/api/; }
    }
  index.html: |
    <!DOCTYPE html>
    <html lang="ko">
    <head><meta charset="UTF-8"><title>Himedia Enterprise</title></head>
    <body style="font-family: Arial; text-align: center; padding: 50px;">
        <h2>Himedia 사원 정보 시스템 (v3.0)</h2>
        <button onclick="fetchData()" style="padding: 10px 20px; font-size: 16px;">사원 데이터 10건 불러오기</button>
        <table border="1" width="80%" style="margin: 20px auto; border-collapse: collapse;">
            <thead><tr><th>Last Name</th><th>First Name</th><th>Department</th><th>Salary</th></tr></thead>
            <tbody id="table-body"><tr><td colspan="4">대기 중...</td></tr></tbody>
        </table>
        <script>
            function fetchData() {
                document.getElementById('table-body').innerHTML = '<tr><td colspan="4">요청 중...</td></tr>';
                fetch('/api/employees').then(r => r.json()).then(res => {
                    if(res.status === 'success') {
                        let rows = res.data.map(e => `<tr><td>${e.last_name}</td><td>${e.first_name}</td><td>${e.dept_name}</td><td>$${e.salary}</td></tr>`).join('');
                        document.getElementById('table-body').innerHTML = rows;
                    } else document.getElementById('table-body').innerHTML = `<tr><td colspan="4" style="color:red;">에러: ${res.message}</td></tr>`;
                }).catch(err => document.getElementById('table-body').innerHTML = `<tr><td colspan="4" style="color:red;">통신 오류</td></tr>`);
            }
        </script>
    </body>
    </html>
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
  namespace: himedia-3tier
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: nginx
    tier: frontend
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-deploy
  namespace: himedia-3tier
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
      tier: frontend
  template:
    metadata:
      labels:
        app: nginx
        tier: frontend
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector: { matchExpressions: [{ key: app, operator: In, values: [nginx] }] }
            topologyKey: "kubernetes.io/hostname"
      containers:
      - name: nginx
        image: nginx:alpine
        lifecycle:
          preStop:
            exec: { command: ["sleep", "5"] }
        ports:
        - containerPort: 80
        resources:
          requests: { cpu: 100m, memory: 64Mi }
          limits: { cpu: 200m, memory: 128Mi }
        livenessProbe:
          httpGet: { path: /, port: 80 }
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet: { path: /, port: 80 }
          initialDelaySeconds: 5
          periodSeconds: 5
        volumeMounts:
        - name: frontend-vol
          mountPath: /etc/nginx/conf.d/default.conf
          subPath: default.conf
        - name: frontend-vol
          mountPath: /usr/share/nginx/html/index.html
          subPath: index.html
      volumes:
      - name: frontend-vol
        configMap:
          name: frontend-config
vagrant@k8s-master-01:~/himedia-3tier$

네트워크 정책

07-network-policy.yaml

apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: strict-policy
  namespace: himedia-3tier
spec:
  endpointSelector: {}
  ingress:
  - {} # Default Deny All Ingress
  egress:
  - {} # Default Deny All Egress
---
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: allow-dns
  namespace: himedia-3tier
spec:
  endpointSelector: {}
  egress:
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
        k8s:k8s-app: kube-dns
    toPorts:
    - ports: [{port: "53", protocol: ANY}]
---
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: 3tier-flow
  namespace: himedia-3tier
spec:
  # 1. Frontend: World Ingress(80) / Backend Egress(5000)
  endpointSelector: { matchLabels: { tier: frontend } }
  ingress:
  - fromEntities: [world, cluster]
    toPorts: [{ ports: [{ port: "80", protocol: TCP }] }]
  egress:
  - toEndpoints: [{ matchLabels: { tier: backend } }]
    toPorts: [{ ports: [{ port: "5000", protocol: TCP }] }]
---
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: backend-flow
  namespace: himedia-3tier
spec:
  # 2. Backend: Frontend Ingress(5000) / DB Egress(3306) + World Egress(443, 80)
  endpointSelector: { matchLabels: { tier: backend } }
  ingress:
  - fromEndpoints: [{ matchLabels: { tier: frontend } }]
    toPorts: [{ ports: [{ port: "5000", protocol: TCP }] }]
  egress:
  - toEndpoints: [{ matchLabels: { tier: database } }]
    toPorts: [{ ports: [{ port: "3306", protocol: TCP }] }]
  # pip install을 위한 외부 인터넷 통신 허용 추가
  - toEntities: [world]
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
      - port: "80"
        protocol: TCP
---
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: database-flow
  namespace: himedia-3tier
spec:
  # 3. Database: Backend Ingress(3306)
  endpointSelector: { matchLabels: { tier: database } }
  ingress:
  - fromEndpoints: [{ matchLabels: { tier: backend } }]
    toPorts: [{ ports: [{ port: "3306", protocol: TCP }] }]
vagrant@k8s-master-01:~/himedia-3tier$

Kustomize

kustomization.yaml

apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - 00-namespace.yaml
  - 01-metrics-server.yaml
# - 02-metallb.yaml
  - 03-storage.yaml
  - 04-database.yaml
  - 05-backend.yaml
  - 06-frontend.yaml
  - 07-network-policy.yaml

secretGenerator:
  - name: mysql-secret
    namespace: himedia-3tier
    literals:
      - ROOT_PASSWORD=dkagh1.


생성
kubectl apply -k .
Watching
k get pod -n himedia-3tier -w
결과 페이지

