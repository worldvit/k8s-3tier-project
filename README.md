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
