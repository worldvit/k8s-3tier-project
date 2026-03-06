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
