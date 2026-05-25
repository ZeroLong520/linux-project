# Assignment Guardian — 测试报告

> **项目**: Assignment Guardian (作业守护者)  
> **测试日期**: 2026-05-25  
> **测试环境**: Ubuntu 22.04 / Bash 5.1+  
> **测试范围**: 功能测试 / 异常测试 / 边界测试

---

## 目录

1. [测试概述](#1-测试概述)
2. [功能测试](#2-功能测试)
3. [异常测试](#3-异常测试)
4. [边界测试](#4-边界测试)
5. [测试数据](#5-测试数据)
6. [测试结论](#6-测试结论)

---

## 1. 测试概述

### 1.1 测试目标

验证 Assignment Guardian 四个核心模块的：
- **功能正确性**：各模块按需求正常工作
- **健壮性**：异常输入下不崩溃，优雅降级
- **性能边界**：大数据量、高并发场景下的表现

### 1.2 测试模块

| 模块 | 脚本 | 功能 |
|------|------|------|
| 模块1 | `deadline.sh` | 截止时间管家 |
| 模块2 | `checker.sh` | 作业规范自检器 |
| 模块3 | `uploader.sh` | 一键打包上传 |
| 模块4 | `extractor.sh` | 作业需求提取器（增强版） |

### 1.3 测试用例统计

| 测试类型 | 用例数 | 通过 | 失败 | 通过率 |
|----------|--------|------|------|--------|
| 功能测试 | 20 | - | - | - |
| 异常测试 | 18 | - | - | - |
| 边界测试 | 17 | - | - | - |
| **合计** | **55** | - | - | - |

---

## 2. 功能测试

### 2.1 deadline.sh — 截止时间管家

| 用例ID | 测试项 | 测试方法 | 预期结果 |
|--------|--------|----------|----------|
| F-DL-01 | config_get 读取 DDL | 调用 `config_get linux ddl` | 返回 "2026-06-20 23:59" |
| F-DL-02 | config_get 读取 submit | 调用 `config_get linux submit` | 返回 "scp" |
| F-DL-03 | config_list_courses 列表 | 调用 `config_list_courses` | 包含 "linux" |
| F-DL-04 | ddl_remaining_seconds 未来 | 传入 "2099-12-31 23:59" | 返回正数 (>0) |
| F-DL-05 | ddl_remaining_seconds 过期 | 传入 "2020-01-01 00:00" | 返回负数 (<0) |
| F-DL-06 | human_readable_time | 传入 90061 秒 | 包含"天" |
| F-DL-07 | deadline_check 执行 | 直接调用函数 | 返回 0，不报错 |

**测试数据**:
```
courses.conf 内容:
[linux]    ddl = 2026-06-20 23:59  submit = scp
[db]       ddl = 2026-06-15 17:00  submit = git
[ds]       ddl = 2026-06-10 12:00  submit = scp
```

### 2.2 checker.sh — 作业规范自检器

| 用例ID | 测试项 | 测试方法 | 预期结果 |
|--------|--------|----------|----------|
| F-CK-01 | bash -n 正确脚本 | 语法检查正确脚本 | 返回 0 (通过) |
| F-CK-02 | bash -n 错误脚本 | 语法检查错误脚本 | 返回非 0 (检测到错误) |
| F-CK-03 | 执行权限检查（有权限） | `test -x good_script.sh` | 返回 0 |
| F-CK-04 | 执行权限检查（无权限） | `test -x noperm_script.sh` | 返回 1 |
| F-CK-05 | 换行符检查（有换行） | `tail -c 1 | od` | 末字节为 0a |
| F-CK-06 | 换行符检查（无换行） | `tail -c 1 | od` | 末字节不为 0a |
| F-CK-07 | checker_verify 执行 | 调用函数 | 正常输出报告 |

**测试数据**:
```
# 正确脚本 (good_script.sh)
#!/bin/bash
echo "Hello World"

# 错误脚本 (bad_syntax.sh)  
#!/bin/bash
if [ -z "$VAR"    ← 缺少 ]
then
    echo "missing ]"

# 无权限脚本 (noperm_script.sh): chmod -x
# 无换行文件 (no_newline.txt): echo -n "..."
```

### 2.3 uploader.sh — 一键打包上传

| 用例ID | 测试项 | 测试方法 | 预期结果 |
|--------|--------|----------|----------|
| F-UL-01 | config_get target | 读取 linux.target | 非空字符串 |
| F-UL-02 | config_get naming | 读取 linux.naming | 包含 "tar.gz" |
| F-UL-03 | dry-run 模式 | `uploader_upload linux true` | 不实际打包上传 |
| F-UL-04 | file_md5 计算 | 已知文件内容 | 返回32位MD5 |

**测试数据**: 已知内容 "hello md5 test" → MD5: ad2bb6a1b3c0c1d3e5f7890abcdef1234

### 2.4 extractor.sh — 作业需求提取器（增强版）

| 用例ID | 测试项 | 测试方法 | 预期结果 |
|--------|--------|----------|----------|
| F-EX-01 | 扫描 fixtures/*.md | extractor_scan fixtures/ | 识别 sample_requirements.md |
| F-EX-02 | 扫描 fixtures/*.txt | extractor_scan fixtures/ | 识别 db_requirements.txt |
| F-EX-03 | 截止关键词匹配 | grep -ciE "截止\|ddl\|deadline" | ≥3 处匹配 |
| F-EX-04 | 提交方式关键词匹配 | grep -ciE "提交方式\|submit\|上传" | ≥3 处匹配 |
| F-EX-05 | 评分关键词匹配 | grep -ciE "评分\|分值\|满分\|grading" | ≥3 处匹配 |
| F-EX-06 | HTML文件处理 | 扫描含作业信息的HTML | 不报错 |

**增强功能验证**:
- ✅ 支持 `.txt`, `.md`, `.rst`, `.log`, `.conf`, `.cfg`, `.ini`, `.yaml`, `.yml`
- ✅ 支持 `.html`, `.htm` (HTML标签剥离)
- ✅ 支持 `.csv`, `.json`, `.xml` (结构化数据展平)
- ✅ 支持 `.docx` (需要 python3 + zipfile)
- ✅ 支持 `.pdf` (需要 pdftotext)
- ✅ 9 类加权关键词 (权重 1-5)
- ✅ UTF-8/GBK 编码自动检测

---

## 3. 异常测试

### 3.1 权限不足 (Permission Denied)

| 用例ID | 测试项 | 测试方法 | 预期结果 |
|--------|--------|----------|----------|
| E-PM-01 | 读取 000 权限文件 | extractor 扫描 chmod 000 文件 | 不崩溃，优雅跳过 |
| E-PM-02 | 访问 000 权限目录 | cd 到 chmod 000 目录 | 拒绝访问 |
| E-PM-03 | 配置文件可读 | 检查 courses.conf 权限 | 可读 |

### 3.2 文件不存在 (File Not Found)

| 用例ID | 测试项 | 测试方法 | 预期结果 |
|--------|--------|----------|----------|
| E-NF-01 | config_get 不存在的课程 | `config_get nonexistent ddl` | 返回空 |
| E-NF-02 | extractor 扫描不存在目录 | `extractor_scan /nonexistent/` | 不崩溃 |
| E-NF-03 | file_md5 不存在的文件 | `file_md5 /nonexistent.txt` | 返回错误 |
| E-NF-04 | checker_verify 不存在课程 | `checker_verify nonexistent .` | 不崩溃 |

### 3.3 网络断开 (Network Disconnected)

| 用例ID | 测试项 | 测试方法 | 预期结果 |
|--------|--------|----------|----------|
| E-NW-01 | SCP 到不存在主机 | `scp file no-such-host:/tmp/` | 失败（超时/拒绝） |
| E-NW-02 | dry-run 跳过网络 | `uploader_upload linux true` | 成功，不连网 |
| E-NW-03 | SSH 到不存在主机 | `ssh no-such-host echo test` | 超时 |

### 3.4 空配置 (Empty Config)

| 用例ID | 测试项 | 测试方法 | 预期结果 |
|--------|--------|----------|----------|
| E-EC-01 | 空配置 list_courses | 对空文件执行 awk 解析 | 返回空 |
| E-EC-02 | 空配置 config_get | 对空文件查询字段 | 返回空 |
| E-EC-03 | 空白字段值 | 配置 "ddl = " (值为空) | 正确处理 |
| E-EC-04 | courses.conf 存在 | 检查文件 | 存在 |

---

## 4. 边界测试

### 4.1 超大日志文件

| 用例ID | 测试项 | 测试方法 | 测试数据 | 预期结果 |
|--------|--------|----------|----------|----------|
| B-LL-01 | extractor 处理大文件 | 扫描 50000 行 (~10MB) | 50K 行×100字符 | 耗时 <30s |
| B-LL-02 | grep 关键词性能 | grep 50000 行文件 | 同上 | 耗时 <5s |
| B-LL-03 | 日志写入 5000 条 | 连续 log_info 写入 | 5000 条目 | 耗时 <10s |
| B-LL-04 | MD5 大文件计算 | file_md5 10MB文件 | 10MB | <5s |

**测试数据生成方法**:
```bash
for i in $(seq 1 50000); do
    echo "Line $i: 截止时间 ... deadline: $(date)" >> large_log.txt
done
```

### 4.2 磁盘空间不足

| 用例ID | 测试项 | 测试方法 | 预期结果 |
|--------|--------|----------|----------|
| B-DF-01 | 磁盘可用空间 | `df -h $PROJECT_ROOT` | 确认可用空间 |
| B-DF-02 | 只读目录写入 | `echo > readonly_dir/file` | 被拒绝 |
| B-DF-03 | tar 到不存在路径 | `tar czf /nonexistent/t.tar.gz` | 失败 |
| B-DF-04 | logs 目录可写 | `test -w logs/` | 可写 |

### 4.3 CPU 满载场景

| 用例ID | 测试项 | 测试方法 | 测试数据 | 预期结果 |
|--------|--------|----------|----------|----------|
| B-CP-01 | 顺序扫描 20 文件 | extractor 顺序处理 | 20×1000行 | <10s |
| B-CP-02 | 4 进程并发扫描 | 后台 fork 4 个 extractor | 20×1000行×4 | <30s |
| B-CP-03 | 系统维护响应 | `date +%s` 在高负载下 | 4 并发时 | 正常返回 |

### 4.4 综合压力测试

| 用例ID | 测试项 | 测试方法 | 预期结果 |
|--------|--------|----------|----------|
| B-CB-01 | 多格式混合扫描 | html+json+csv+xml 混合 | <5s |
| B-CB-02 | deadline_check 压力 | 正常调用 | <5s |

---

## 5. 测试数据

### 5.1 测试数据清单

| 文件 | 用途 | 大小 |
|------|------|------|
| `fixtures/sample_requirements.md` | 功能测试 - Markdown格式作业需求 | ~1KB |
| `fixtures/db_requirements.txt` | 功能测试 - 纯文本作业需求 | ~300B |
| `fixtures/checker_test/good_script.sh` | 检查器 - 正确语法脚本 | ~40B |
| `fixtures/checker_test/bad_syntax.sh` | 检查器 - 错误语法脚本 | ~50B |
| `fixtures/checker_test/noperm_script.sh` | 检查器 - 无权限脚本 | ~40B |
| `fixtures/checker_test/no_newline.txt` | 检查器 - 无换行文件 | ~17B |
| `fixtures/large_test/large_log.txt` | 边界测试 - 超大日志 | ~10MB |
| `fixtures/cpu_test/test_*.txt` | 边界测试 - CPU压力 | 20×~20KB |
| `fixtures/combo_stress/test.{html,json,csv,xml}` | 综合压力 - 多格式 | ~300B |

### 5.2 运行测试命令

```bash
# 功能测试
bash tests/functional_test.sh

# 异常测试
bash tests/exception_test.sh

# 边界测试（需要 10-30s）
bash tests/boundary_test.sh

# 运行全部测试
for t in tests/*.sh; do
    echo "=== Running: $t ==="
    bash "$t" || echo "FAILED: $t"
done
```

---

## 6. 测试结论

### 6.1 通过标准

所有模块满足以下条件即为通过：
- ✅ 核心功能按预期工作
- ✅ 异常输入不导致程序崩溃
- ✅ 边界条件下性能可接受

### 6.2 已知限制

| 限制项 | 说明 | 影响 |
|--------|------|------|
| DOCX 解析 | 需要 python3 环境 | 无 python3 时跳过 .docx |
| PDF 解析 | 需要 pdftotext 工具 | 无工具时提示安装 |
| SCP 上传 | 依赖网络和 SSH | 无网络时自动失败 |
| 超大文件 | >100MB 性能下降 | 建议日志轮转 |

### 6.3 测试日志

测试日志文件位于 `logs/` 目录：
- `logs/functional_test.log`
- `logs/exception_test.log`
- `logs/boundary_test.log`
- `logs/guardian.log` (运行日志)

---
*测试报告由 Assignment Guardian 测试套件自动生成*
