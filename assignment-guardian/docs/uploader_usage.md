# Uploader 模块使用说明

## 概述

Uploader 模块（`lib/uploader.sh`）提供一键打包上传功能，支持多种上传策略和异常处理机制。

## 功能特性

### 核心功能

- **自动打包**: 根据配置规则生成 tar.gz 压缩包
- **多种上传方式**: 支持 SCP、rsync 断点续传
- **超大文件处理**: 自动分片上传（>500MB）
- **完整性校验**: MD5 校验确保上传完整
- **试运行模式**: `--dry` 参数预览操作不执行实际上传

### 异常处理

| 异常类型 | 处理方式 |
|----------|----------|
| 认证失败 | 立即返回错误，提示检查 SSH 配置 |
| 网络超时 | 自动重试（最多3次），指数退避 |
| 目录不存在 | 自动尝试创建远程目录 |
| 网络中断 | rsync 断点续传，支持恢复 |

### 上传策略

```
文件大小判断:
    > 500MB  → 分片上传（50MB/片）
    <= 500MB → rsync（断点续传）
                ↓ 失败
                SCP（带超时重试）
```

## 使用方法

### 命令行调用

```bash
# 基本上传（自动先执行 verify）
./guardian.sh upload <课程名>

# 试运行模式（只展示，不上传）
./guardian.sh upload --dry <课程名>

# 跳过验证直接上传
./guardian.sh upload --skip-verify <课程名>

# 仅打包不上传
./guardian.sh package <课程名>
```

### 示例

```bash
# 上传 linux 课程作业
./guardian.sh upload linux

# 预览上传操作
./guardian.sh upload --dry linux

# 跳过验证直接上传
./guardian.sh upload --skip-verify linux

# 仅打包
./guardian.sh package linux
```

## 配置说明

在 `config/courses.conf` 中配置上传参数：

```ini
[linux]
ddl = 2026-06-20 23:59
submit = scp
target = student@192.168.1.100:/home/teacher/submit/linux/
required_files = report.pdf, src/*.sh, README.md
naming = linux_学号_姓名.tar.gz
notes = 脚本必须有可执行权限
```

### 配置字段

| 字段 | 说明 | 示例 |
|------|------|------|
| `submit` | 提交方式 | scp, git, local |
| `target` | 目标地址 | user@host:/path |
| `naming` | 打包命名格式 | linux_学号.tar.gz |

### 命名格式变量

打包命名支持以下变量替换：

| 变量 | 说明 | 示例 |
|------|------|------|
| `学号` | 学生学号（通过环境变量设置） | 2021001 |
| `姓名` | 学生姓名（通过环境变量设置） | ZhangSan |

设置环境变量：

```bash
export STUDENT_ID=2021001
export STUDENT_NAME=ZhangSan
```

## API 接口

### uploader_upload(course, dry_run, skip_verify)

打包并上传指定课程作业。

**参数:**
- `course`: 课程标识
- `dry_run`: 是否试运行模式（true/false）
- `skip_verify`: 是否跳过验证（true/false）

**返回值:**
- 0: 上传成功
- 1: 上传失败

```bash
source lib/uploader.sh
uploader_upload "linux" "false" "false"
```

### uploader_package_only(course)

仅打包不上传。

**参数:**
- `course`: 课程标识

**返回值:**
- 0: 打包成功
- 1: 打包失败

## 执行流程

```
uploader_upload 执行流程:
    1. 解析配置（target, naming）
    2. [可选] 执行 verify 检查
       ├─ 通过 → 继续
       └─ 失败 → 终止并报错
    3. 生成打包文件名（替换学号等变量）
    4. 执行 tar 打包
    5. 检查远程目录（不存在则创建）
    6. 根据文件大小选择上传策略
    7. 执行上传
    8. MD5 校验
    9. 输出结果
```

## 异常处理机制

### 超时处理

- **SCP 超时**: 300秒（可通过 `SCP_TIMEOUT` 环境变量修改）
- **SSH 连接超时**: 10秒
- **重试次数**: 最多3次，指数退避等待

### 错误提示

| 错误类型 | 提示信息 | 解决建议 |
|----------|----------|----------|
| 认证失败 | `SCP 认证失败或连接拒绝` | 检查 SSH 密钥配置 |
| 超时 | `SCP 超时，重试...` | 检查网络连接 |
| 目录不存在 | `远程目录不存在，尝试创建...` | 自动处理，无需干预 |
| MD5 不匹配 | `无法校验远程MD5` | 手动验证文件完整性 |

## 断点续传

### rsync 断点续传

当系统安装了 `rsync` 时，自动使用断点续传功能：

```bash
rsync -avz --progress --partial --timeout=300 local_file user@host:/path
```

### 分片上传

对于超过 500MB 的大文件，自动启用分片上传：

1. 将文件分割为 50MB 的分片
2. 逐个上传分片
3. 在远程服务器合并分片
4. 删除临时分片文件

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `STUDENT_ID` | 学号，用于打包命名 | unknown |
| `SCP_TIMEOUT` | SCP 超时时间（秒） | 300 |
| `MAX_RETRY` | 最大重试次数 | 3 |

## 日志记录

所有操作记录到 `logs/guardian.log`：

```
[2026-05-25 10:30:00] INFO  uploader: linux → student@192.168.1.100:/home/teacher/submit/linux/  tarball=linux_2021001.tar.gz  md5=abc123...
```

## 注意事项

1. 确保 SSH 免密登录已配置，否则需要手动输入密码
2. 大文件上传建议在网络稳定时进行
3. 分片上传需要远程服务器有足够的临时空间
4. 打包时自动排除 `logs/`, `.git/`, `*.tar.gz`, `*.zip`
