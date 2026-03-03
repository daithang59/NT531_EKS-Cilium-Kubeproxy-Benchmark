# 🤝 Hướng dẫn Làm việc với Repository

> Tài liệu dành cho **tất cả thành viên** nhóm NT531.
> Đọc kỹ trước khi bắt đầu làm việc để đảm bảo quy trình nhất quán.

---

## Mục lục

1. [Yêu cầu môi trường](#1-yêu-cầu-môi-trường)
2. [Clone repository](#2-clone-repository)
3. [Quy tắc branching](#3-quy-tắc-branching)
4. [Quy trình làm việc (Workflow)](#4-quy-trình-làm-việc-workflow)
5. [Quy tắc commit](#5-quy-tắc-commit)
6. [Tạo Pull Request (PR)](#6-tạo-pull-request-pr)
7. [Code Review](#7-code-review)
8. [Sync với upstream](#8-sync-với-upstream-main)
9. [Cấu trúc thư mục](#9-cấu-trúc-thư-mục)
10. [Lưu ý quan trọng](#10-lưu-ý-quan-trọng)
11. [Xử lý sự cố](#11-xử-lý-sự-cố)

---

## 1. Yêu cầu môi trường

Đảm bảo máy đã cài đặt:

| Công cụ | Phiên bản tối thiểu | Ghi chú |
|---------|---------------------|---------|
| **Git** | >= 2.30 | [Download](https://git-scm.com/downloads) |
| **AWS CLI** | >= 2.x | `aws configure` để thiết lập credentials |
| **kubectl** | >= 1.28 | Tương thích EKS cluster |
| **Helm** | >= 3.x | Quản lý Cilium & monitoring stack |
| **Terraform** | >= 1.5 | Provision hạ tầng AWS |
| **Bash** | >= 4.0 | Trên WSL hoặc Linux |
| **jq** | (optional) | Xử lý JSON output |
| **hubble** CLI | (optional) | Thu thập Cilium flow data |

> **Windows users:** Nên sử dụng **WSL2** (Ubuntu) hoặc Git Bash để chạy scripts.

---

## 2. Clone repository

### Lần đầu tiên

```bash
# Clone repo về máy
git clone https://github.com/daithang59/NT531_EKS-Cilium-Kubeproxy-Benchmark.git

# Di chuyển vào thư mục dự án
cd NT531_EKS-Cilium-Kubeproxy-Benchmark

# Kiểm tra remote
git remote -v
# origin  https://github.com/daithang59/NT531_EKS-Cilium-Kubeproxy-Benchmark.git (fetch)
# origin  https://github.com/daithang59/NT531_EKS-Cilium-Kubeproxy-Benchmark.git (push)
```

### Nếu sử dụng SSH (khuyến nghị)

```bash
git clone git@github.com:daithang59/NT531_EKS-Cilium-Kubeproxy-Benchmark.git
```

> **Tip:** Nếu chưa thiết lập SSH key, xem hướng dẫn:
> [GitHub SSH Setup](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)

---

## 3. Quy tắc branching

### Nhánh chính

| Nhánh | Mục đích |
|-------|----------|
| `main` | Nhánh ổn định, chỉ merge qua PR đã review |

### Đặt tên nhánh

Sử dụng format: `<loại>/<mô-tả-ngắn>`

| Prefix | Sử dụng khi | Ví dụ |
|--------|-------------|-------|
| `feature/` | Thêm tính năng mới | `feature/add-s2-script` |
| `fix/` | Sửa lỗi | `fix/fortio-connection-timeout` |
| `docs/` | Cập nhật tài liệu | `docs/update-runbook` |
| `infra/` | Thay đổi hạ tầng (Terraform, Helm) | `infra/update-eks-node-count` |
| `script/` | Thêm/sửa scripts | `script/refactor-common-sh` |
| `config/` | Thay đổi cấu hình | `config/cilium-values-tuning` |

> ⚠️ **Không bao giờ** commit trực tiếp lên `main`. Luôn tạo nhánh riêng.

---

## 4. Quy trình làm việc (Workflow)

### Tổng quan quy trình

```
main ──────────────────────────────────────────────►
  │                                    ▲
  │ (1) Tạo nhánh                      │ (6) Merge PR
  ▼                                    │
  feature/xxx ──► commit ──► push ──► PR ──► Review ──► Merge
                   (2)       (3)     (4)      (5)        (6)
```

### Bước 1 — Cập nhật `main` mới nhất

```bash
git checkout main
git pull origin main
```

### Bước 2 — Tạo nhánh mới

```bash
git checkout -b feature/ten-nhanh-cua-ban
```

### Bước 3 — Làm việc & commit

```bash
# Chỉnh sửa files...
# Kiểm tra thay đổi
git status
git diff

# Stage files
git add <file1> <file2>
# Hoặc stage tất cả
git add .

# Commit
git commit -m "feat: mô tả ngắn gọn thay đổi"
```

### Bước 4 — Push nhánh lên remote

```bash
# Lần đầu push nhánh mới
git push -u origin feature/ten-nhanh-cua-ban

# Các lần sau
git push
```

### Bước 5 — Tạo Pull Request

Xem [mục 6](#6-tạo-pull-request-pr) để biết chi tiết.

### Bước 6 — Sau khi merge

```bash
# Quay về main
git checkout main
git pull origin main

# Xóa nhánh cũ (local)
git branch -d feature/ten-nhanh-cua-ban

# Xóa nhánh cũ (remote, nếu cần)
git push origin --delete feature/ten-nhanh-cua-ban
```

---

## 5. Quy tắc commit

### Format message

Sử dụng [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <mô tả ngắn gọn>
```

### Các loại commit

| Type | Khi nào dùng | Ví dụ |
|------|-------------|-------|
| `feat` | Thêm tính năng mới | `feat: add run_s2.sh benchmark script` |
| `fix` | Sửa lỗi | `fix: correct Fortio QPS calculation` |
| `docs` | Thay đổi documentation | `docs: update runbook with S3 steps` |
| `infra` | Thay đổi infrastructure | `infra: increase EKS node count to 3` |
| `refactor` | Tái cấu trúc code | `refactor: extract common functions to common.sh` |
| `config` | Thay đổi config | `config: tune Cilium eBPF values` |
| `chore` | Việc lặt vặt | `chore: update .gitignore` |

### Quy tắc

- ✅ Viết bằng **tiếng Anh**
- ✅ Mô tả ngắn gọn, rõ ràng (< 72 ký tự)
- ✅ Mỗi commit làm **một việc** cụ thể
- ❌ Không dùng message chung chung: `update`, `fix bug`, `abc`

---

## 6. Tạo Pull Request (PR)

### Cách tạo PR trên GitHub

1. Truy cập repo trên GitHub
2. Nhấn **"Compare & pull request"** (xuất hiện sau khi push nhánh mới)
3. Hoặc vào tab **Pull requests** → **New pull request**

### Template PR

Khi tạo PR, hãy điền nội dung theo template sau:

```markdown
## Mô tả

<!-- Mô tả ngắn gọn thay đổi -->

## Loại thay đổi

- [ ] Feature (thêm tính năng mới)
- [ ] Fix (sửa lỗi)
- [ ] Docs (cập nhật tài liệu)
- [ ] Infra (thay đổi hạ tầng)
- [ ] Config (thay đổi cấu hình)

## Checklist

- [ ] Code/config đã tự review
- [ ] Đã test trên môi trường local (nếu áp dụng)
- [ ] Đã cập nhật tài liệu liên quan (nếu áp dụng)
- [ ] Không chứa credentials hoặc sensitive data

## Files thay đổi chính

<!-- Liệt kê các files quan trọng bị thay đổi -->

## Screenshots / Logs (nếu có)

<!-- Attach screenshots hoặc paste log output -->
```

### Quy tắc PR

| Quy tắc | Chi tiết |
|---------|----------|
| **Base branch** | Luôn là `main` |
| **Reviewers** | Assign ít nhất 1 thành viên khác review |
| **Size** | Giữ PR nhỏ, tập trung vào 1 mục đích |
| **Conflict** | Resolve conflict trước khi request review |
| **CI check** | Đảm bảo không có lỗi trước khi merge |

---

## 7. Code Review

### Người review

- Kiểm tra code/config có hợp lý không
- Chạy thử nếu thay đổi liên quan đến scripts/terraform (nếu có thể)
- Comment góp ý trực tiếp trên GitHub
- Approve hoặc Request changes

### Người tạo PR

- Phản hồi tất cả comments
- Sửa code theo góp ý và push commit mới
- **Không force-push** lên nhánh đang review (giữ lịch sử review)

### Merge

- Chỉ merge khi có **ít nhất 1 approval**
- Sử dụng **"Squash and merge"** hoặc **"Create a merge commit"** (thống nhất trong nhóm)
- Xóa nhánh sau khi merge

---

## 8. Sync với upstream (`main`)

Nếu nhánh của bạn bị **behind `main`** (có người khác đã merge PR trước):

### Cách 1: Merge (khuyến nghị cho beginner)

```bash
# Đang ở trên nhánh feature
git checkout feature/ten-nhanh-cua-ban

# Fetch và merge main vào nhánh hiện tại
git fetch origin
git merge origin/main

# Resolve conflicts nếu có, sau đó:
git add .
git commit -m "chore: merge main into feature branch"
git push
```

### Cách 2: Rebase (cho người quen Git)

```bash
git checkout feature/ten-nhanh-cua-ban
git fetch origin
git rebase origin/main

# Resolve conflicts nếu có (cho từng commit)
# Sau khi resolve xong mỗi conflict:
git add .
git rebase --continue

# Force push (vì rebase thay đổi history)
git push --force-with-lease
```

> ⚠️ **Chú ý:** Chỉ dùng rebase nếu bạn là **người duy nhất** làm việc trên nhánh đó.

---

## 9. Cấu trúc thư mục

Nắm rõ cấu trúc trước khi thay đổi:

```
thesis-cilium-eks-benchmark/
├── docs/               # Tài liệu thiết kế & vận hành
├── terraform/           # IaC — provision hạ tầng AWS (VPC + EKS)
├── helm/                # Helm values (Cilium CNI + Monitoring)
├── workload/            # K8s manifests (echo server, Fortio, policies)
├── scripts/             # Shell scripts chạy benchmark
├── results/             # Output artifacts (gitignored, chỉ giữ template)
└── report/              # Tài liệu báo cáo, bảng, hình ảnh
```

> ⚠️ **Không commit** vào `results/` (trừ README & template).  
> Xem `.gitignore` để biết chi tiết.

---

## 10. Lưu ý quan trọng

### 🔒 Bảo mật

- **KHÔNG** commit credentials, access keys, `.pem`, `.key` lên repo
- **KHÔNG** commit `terraform.tfstate` — đã được gitignore
- Nếu vô tình commit sensitive data, **báo ngay** để xử lý  
  (cần xóa khỏi Git history, không chỉ xóa file)

### 📝 Tài liệu

- Khi thay đổi scripts hoặc config, **cập nhật README** tương ứng
- Khi thay đổi thí nghiệm, cập nhật `docs/experiment_spec.md`
- Khi thay đổi quy trình chạy, cập nhật `docs/runbook.md`

### 🐧 Scripts

- Trên Linux/WSL, cần cấp quyền thực thi:

  ```bash
  chmod +x scripts/*.sh
  ```

- **Luôn test scripts** trên môi trường dev trước khi push

### 📐 Coding Style

- **Terraform:** Chạy `make fmt` trước khi commit để format code
- **YAML:** Indent 2 spaces, không dùng tabs
- **Shell scripts:** Follow POSIX conventions, thêm `set -euo pipefail` ở đầu script

---

## 11. Xử lý sự cố

### Conflict khi merge/rebase

```bash
# 1. Xem danh sách files bị conflict
git status

# 2. Mở file, tìm markers và sửa
#    <<<<<<< HEAD
#    (code hiện tại)
#    =======
#    (code từ main)
#    >>>>>>> origin/main

# 3. Sau khi sửa xong
git add <file-da-resolve>
git commit -m "chore: resolve merge conflict"
```

### Push bị reject

```bash
# Do nhánh remote có thay đổi mới hơn
git pull origin feature/ten-nhanh-cua-ban
# Resolve conflict nếu có, rồi push lại
git push
```

### Commit nhầm file

```bash
# Reset commit gần nhất (giữ lại thay đổi trong working dir)
git reset --soft HEAD~1

# Hoặc chỉ unstage 1 file
git reset HEAD <file-khong-muon>
```

### Commit nhầm lên `main`

```bash
# Tạo nhánh mới từ commit hiện tại
git branch feature/ten-nhanh-moi

# Reset main về trạng thái trước
git checkout main
git reset --hard origin/main

# Chuyển sang nhánh mới và push
git checkout feature/ten-nhanh-moi
git push -u origin feature/ten-nhanh-moi
```

### Muốn bỏ tất cả thay đổi chưa commit

```bash
# ⚠️ Cẩn thận — không thể undo!
git checkout -- .
# Hoặc
git restore .
```

---

## Tóm tắt quy trình

```
1. git pull origin main                    # Cập nhật main
2. git checkout -b feature/xxx             # Tạo nhánh mới
3. <chỉnh sửa files>                      # Làm việc
4. git add . && git commit -m "feat: ..."  # Commit
5. git push -u origin feature/xxx          # Push lên remote
6. Tạo PR trên GitHub                      # Request review  
7. Review & Approve                        # Đồng đội review
8. Merge PR                                # Merge vào main
9. git checkout main && git pull            # Cập nhật lại main
10. git branch -d feature/xxx              # Dọn dẹp nhánh cũ
```

---

## ❓ Cần hỗ trợ?

Nếu gặp vấn đề với Git hoặc quy trình:
- Hỏi trong group chat nhóm
- Tham khảo [GitHub Docs](https://docs.github.com)
- Tham khảo [Git Cheatsheet](https://education.github.com/git-cheat-sheet-education.pdf)

---

> **Cập nhật lần cuối:** 2026-03-03
