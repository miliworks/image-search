# Semantic Image Search

一个基于语义的 macOS 图像搜索应用，使用本地部署的向量模型对图像进行检索。

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## ✨ 功能特性

### 🔍 语义搜索
- **自然语言搜索**: 使用自然语言描述来搜索图像，如 "日落时的海滩"、"微笑的人们"
- **向量嵌入**: 使用 Vision 框架的神经网络特征提取生成图像向量
- **本地处理**: 所有处理都在本地完成，保护您的隐私

### 📝 OCR 文本识别
- **文字提取**: 自动识别图像中的文字内容
- **多语言支持**: 支持英文、简体中文、繁体中文、日文、韩文
- **全文检索**: 支持 FTS5 全文搜索

### 📂 文件夹管理
- **多文件夹**: 可添加多个文件夹进行监控
- **自动扫描**: 递归扫描文件夹中的所有图像
- **增量更新**: 只处理新增或修改的图像
- **安全访问**: 使用安全书签保持对文件夹的持久访问

### 💾 高效存储
- **SQLite 数据库**: 轻量级本地存储
- **压缩缩略图**: JPEG 压缩减少存储空间
- **向量索引**: SIMD 加速的向量相似度搜索
- **WAL 模式**: 高性能数据库写入

## 🏗️ 项目架构

```
SemanticImageSearch/
├── SemanticImageSearchApp.swift    # 应用入口
├── AppState.swift                  # 全局状态管理
├── Models/                         # 数据模型
│   ├── ImageItem.swift            # 图像数据模型
│   ├── FolderItem.swift           # 文件夹数据模型
│   └── SearchResult.swift         # 搜索结果模型
├── Services/                       # 服务层
│   ├── DatabaseService.swift      # SQLite 数据库服务
│   ├── VectorService.swift        # 向量嵌入服务
│   ├── VectorIndex.swift          # 向量索引
│   ├── OCRService.swift           # OCR 文字识别
│   ├── ImageProcessingService.swift # 图像处理
│   ├── SearchEngine.swift         # 搜索引擎
│   └── FolderManager.swift        # 文件夹管理
├── ViewModels/                     # 视图模型
│   └── MainViewModel.swift        # 主视图模型
├── Views/                          # 视图层
│   ├── ContentView.swift          # 主内容视图
│   ├── SidebarView.swift          # 侧边栏
│   ├── SearchResultsView.swift    # 搜索结果
│   ├── ImageDetailView.swift      # 图像详情
│   ├── FolderListView.swift       # 文件夹管理
│   ├── SettingsView.swift         # 设置
│   ├── StatusBarView.swift        # 状态栏
│   └── Components/                # UI 组件
│       └── ImageGridItem.swift    # 图像网格项
├── Extensions/                     # 扩展
│   ├── Array+Extensions.swift     # 数组扩展
│   ├── Data+Extensions.swift      # 数据扩展
│   └── NSImage+Extensions.swift   # 图像扩展
└── Resources/                      # 资源文件
    └── Assets.xcassets            # 应用资源
```

## 🔧 技术栈

| 组件 | 技术 |
|------|------|
| UI 框架 | SwiftUI |
| 向量模型 | Vision FeaturePrint |
| OCR | Vision VNRecognizeTextRequest |
| 数据库 | SQLite3 + FTS5 |
| 向量搜索 | 自定义 SIMD 加速索引 |
| 并发 | Swift Concurrency (async/await) |

## 📱 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Apple Silicon 或 Intel 处理器
- 至少 4GB RAM

## 🚀 快速开始

### 构建项目

1. 使用 Xcode 15 或更高版本打开项目：
```bash
cd SemanticImageSearch
open SemanticImageSearch.xcodeproj
```

2. 选择目标设备为 "My Mac"

3. 按 `Cmd + R` 运行项目

### 使用应用

1. **添加文件夹**: 点击侧边栏的 "+" 按钮或使用 `Cmd + O`
2. **等待索引**: 应用会自动扫描并索引图像
3. **开始搜索**: 在搜索框中输入描述性文字
4. **选择搜索模式**:
   - **Semantic**: 基于图像内容的语义搜索
   - **Text (OCR)**: 基于图像中文字的搜索
   - **Combined**: 综合两种搜索方式

## 🔍 搜索模式详解

### 语义搜索 (Semantic)
使用 Vision 框架的神经网络特征提取，将图像和搜索文本都转换为向量，然后计算余弦相似度。

**适用场景**:
- 描述性搜索："蓝天白云"
- 场景搜索："办公室环境"
- 物体搜索："红色汽车"

### 文本搜索 (Text/OCR)
使用 Vision 框架的 OCR 功能提取图像中的文字，然后使用 FTS5 全文搜索。

**适用场景**:
- 文档截图搜索
- 带文字的图像
- 名片、标签等

### 综合搜索 (Combined)
结合语义搜索和文本搜索的结果，使用加权算法得出最终排名。

默认权重: 语义 70% + 文本 30%

## 💡 优化策略

### 存储优化
- **缩略图压缩**: 使用 JPEG 压缩，质量 70%
- **向量存储**: 使用 Float32，每张图像 2KB
- **增量索引**: 只处理新文件

### 内存优化
- **懒加载缩略图**: 只在需要时加载
- **分批处理**: 大文件夹分批扫描
- **缓存策略**: 合理使用内存缓存

### 搜索优化
- **SIMD 加速**: 使用 Accelerate 框架
- **索引预加载**: 启动时加载向量索引
- **搜索防抖**: 300ms 防抖减少请求

## 🛠️ 扩展指南

### 添加新的图像格式

编辑 `ImageProcessingService.swift`:

```swift
static let supportedExtensions: Set<String> = [
    "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", 
    "heic", "heif", "webp",
    "your_new_format"  // 添加新格式
]
```

### 自定义搜索权重

编辑 `SettingsView.swift` 中的设置，或修改 `SearchEngine.swift`:

```swift
private let semanticWeight: Float = 0.7  // 调整此值
```

### 添加 CLIP 模型支持

1. 下载 CLIP Core ML 模型
2. 添加到 `Resources/` 文件夹
3. 修改 `VectorService.swift` 使用 Core ML 模型

## 📄 许可证

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📞 联系

如有问题，请提交 GitHub Issue。
