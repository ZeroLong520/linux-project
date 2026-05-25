# Checker 模块使用说明

## 概述

Checker 模块（`lib/checker.sh`）是作业规范自检器，在提交作业前自动检查多项规范要求，确保作业符合提交标准。

## 功能特性

### 检查项列表

| 检查项 | 描述 | 严重级别 |
|--------|------|----------|
| 必交文件检查 | 验证配置中指定的必交文件是否齐全 | FAIL |
| 执行权限检查 | 检查 Shell 脚本是否有可执行权限 | FAIL |
| 语法检查 | 使用 `bash -n` 检查脚本语法 | FAIL |
| 换行结尾检查 | 检查文本文件是否以换行符结尾 | WARN |
| 绝对路径检查 | 检测文件中是否包含绝对路径引用 | FAIL |
| UTF-8 编码检查 | 验证文件编码是否为 UTF-8 | WARN |

## 使用方法

### 命令行调用

```bash
# 对指定课程执行自检
./guardian.sh verify <课程名>

# 对所有课程执行自检
./guardian.sh verify --all
```

### 示例

```bash
# 检查 linux 课程的作业规范
./guardian.sh verify linux

# 检查所有课程
./guardian.sh verify --all
```

## API 接口

### checker_verify(course, target_dir)

对指定课程执行规范自检。

**参数:**
- `course`: 课程标识（如 linux, db, ds）
- `target_dir`: 检查目录，默认为当前目录

**返回值:**
- 0: 全部检查通过
- >0: 有检查项未通过

```bash
# 示例
source lib/checker.sh
checker_verify "linux" "/path/to/assignment"
```

### checker_verify_all(target_dir)

对所有课程执行自检。

**参数:**
- `target_dir`: 检查目录，默认为当前目录

**返回值:**
- 0: 全部检查通过
- >0: 有检查项未通过

## 配置说明

在 `config/courses.conf` 中配置必交文件：

```ini
[linux]
required_files = report.pdf, src/*.sh, README.md
```

支持通配符匹配，多个文件用逗号分隔。

## 检查结果解读

### 状态标识

- `[PASS]`: 检查通过
- `[FAIL]`: 检查失败，阻止上传
- `[WARN]`: 警告，建议修复但不阻止上传

### 输出示例

```
========== 作业规范自检: linux ==========

  [PASS] 必交文件: report.pdf → ./report.pdf
  [PASS] 必交文件: src/*.sh → ./src/main.sh
  [PASS] 可执行权限: ./main.sh
  [PASS] 语法检查: ./main.sh
  [PASS] 换行结尾: ./README.md
  [PASS] 无绝对路径引用
  [PASS] 编码正确: ./README.md (utf-8)

-----------------------------------
  通过: 7
  总计: 7
```

## 常见问题

### Q: 如何修复"缺少执行权限"错误？

```bash
chmod +x your_script.sh
```

### Q: 如何修复"语法错误"？

使用 `bash -n script.sh` 定位具体错误位置，检查语法问题。

### Q: 如何修复"缺少末尾换行"警告？

在文件末尾添加换行符即可。

### Q: 如何修复"包含绝对路径"错误？

将绝对路径改为相对路径，例如：
- 错误: `/home/user/project/file.txt`
- 正确: `./file.txt` 或 `file.txt`

### Q: 如何修复"非 UTF-8 编码"警告？

使用 `iconv` 或文本编辑器转换文件编码为 UTF-8：

```bash
iconv -f GBK -t UTF-8 input.txt > output.txt
```

## 与 Uploader 的集成

Checker 模块与 Uploader 模块自动集成：

- **默认行为**: 执行 `upload` 命令时，会自动先执行 `verify` 检查
- **检查通过**: 继续执行打包上传流程
- **检查失败**: 阻止上传并提示错误
- **跳过检查**: 使用 `--skip-verify` 参数跳过验证

```bash
# 自动执行验证（推荐）
./guardian.sh upload linux

# 跳过验证直接上传（谨慎使用）
./guardian.sh upload --skip-verify linux
```

## 注意事项

1. 检查范围默认只包含当前目录下的文件（maxdepth=1）
2. Shell 脚本检查只针对 `.sh` 后缀文件
3. 编码检查针对 `.sh`, `.md`, `.txt` 文件
4. 检查结果会记录到日志文件 `logs/guardian.log`
