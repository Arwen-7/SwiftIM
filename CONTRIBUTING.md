# Contributing to SwiftIM

First off, thank you for considering contributing to SwiftIM! 🎉

It's people like you that make SwiftIM such a great tool for the iOS community.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Commit Message Guidelines](#commit-message-guidelines)
- [Testing Guidelines](#testing-guidelines)

---

## 📜 Code of Conduct

This project and everyone participating in it is governed by our Code of Conduct. By participating, you are expected to uphold this code.

### Our Pledge

- Be respectful and inclusive
- Welcome newcomers
- Focus on what is best for the community
- Show empathy towards other community members

---

## 🤝 How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates.

**When reporting a bug, please include:**
- A clear and descriptive title
- Steps to reproduce the issue
- Expected behavior vs actual behavior
- Screenshots or code snippets (if applicable)
- iOS version and device information
- SwiftIM version

**Example:**
```markdown
**Bug Description**
Message status not updating after reconnection

**Steps to Reproduce**
1. Send a message
2. Turn on airplane mode
3. Turn off airplane mode
4. Observe message status

**Expected Behavior**
Message status should update to "delivered" after reconnection

**Actual Behavior**
Message status remains "sending"

**Environment**
- SwiftIM: 1.0.0
- iOS: 16.0
- Device: iPhone 14 Pro
```

### Suggesting Features

We love feature suggestions! Please create an issue with:
- Clear description of the feature
- Use cases and benefits
- Possible implementation approach (optional)
- Examples from other SDKs (optional)

### Improving Documentation

Documentation improvements are always welcome:
- Fix typos or grammar
- Add missing examples
- Clarify confusing sections
- Translate documentation

---

## 💻 Development Setup

### Prerequisites

- Xcode 15.0+
- Swift 5.9+
- Git

### Clone and Build

```bash
# Clone the repository
git clone https://github.com/SwiftIM/SwiftIM-iOS.git
cd SwiftIM-iOS

# Open in Xcode
open Package.swift

# Or build via command line
swift build

# Run tests
swift test
```

### Project Structure

```
SwiftIM-iOS/
├── Sources/
│   └── IMSDK/           # Main source code
│       ├── Foundation/  # Models, extensions
│       ├── Core/        # Transport, database, network
│       ├── Business/    # Message, conversation, user managers
│       └── IMClient.swift  # Main SDK entry point
├── Tests/
│   └── IMSDKTests/      # Unit tests
├── Examples/            # Usage examples
├── docs/                # Documentation
└── Package.swift        # SPM manifest
```

---

## 🔄 Pull Request Process

### 1. Fork and Create Branch

```bash
# Fork the repository on GitHub, then:
git clone https://github.com/YOUR_USERNAME/SwiftIM-iOS.git
cd SwiftIM-iOS

# Create a feature branch
git checkout -b feature/amazing-feature

# Or for bug fixes
git checkout -b fix/issue-123
```

### 2. Make Your Changes

- Write clean, readable code
- Follow existing code style
- Add tests for new features
- Update documentation

### 3. Test Your Changes

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter SwiftIMTests.YourTestSuite

# Check code coverage
swift test --enable-code-coverage
```

### 4. Commit Your Changes

```bash
git add .
git commit -m "feat: add amazing feature"
```

See [Commit Message Guidelines](#commit-message-guidelines) below.

### 5. Push and Create PR

```bash
git push origin feature/amazing-feature
```

Then create a Pull Request on GitHub with:
- Clear title describing the change
- Description of what changed and why
- Link to related issues (if any)
- Screenshots (if UI-related)

### 6. Code Review

- Respond to review comments
- Make requested changes
- Keep the PR up to date with main branch

---

## 📝 Coding Standards

### Swift Style Guide

We follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).

**Key points:**
- Use meaningful variable and function names
- Prefer `let` over `var` when possible
- Use `guard` for early returns
- Add documentation comments for public APIs
- Keep functions focused and short

**Example:**

```swift
/// Sends a text message to the specified conversation.
///
/// - Parameters:
///   - conversationID: The unique identifier of the conversation
///   - text: The text content to send
///   - completion: Called when the operation completes
/// - Returns: The created message object
@discardableResult
public func sendTextMessage(
    conversationID: String,
    text: String,
    completion: @escaping (Result<Void, IMError>) -> Void
) -> IMMessage {
    // Implementation
}
```

### Code Organization

- Group related functionality using `// MARK: -`
- Keep files focused (< 500 lines when possible)
- Use extensions for protocol conformance
- Separate public API from internal implementation

**Example:**

```swift
// MARK: - Lifecycle

// MARK: - Public API

// MARK: - Private Methods

// MARK: - IMMessageListener
extension YourClass: IMMessageListener {
    // ...
}
```

### Error Handling

- Use `Result<Success, Failure>` for async operations
- Define clear error types
- Provide meaningful error messages

```swift
public enum IMError: Error {
    case notConnected
    case invalidParameter(String)
    case networkError(Error)
    
    var description: String {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .invalidParameter(let message):
            return "Invalid parameter: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
```

### Concurrency

- Use appropriate `DispatchQueue` for operations
- Protect shared state with locks (`NSLock`, `NSRecursiveLock`)
- Prefer async/await for new code (Swift 5.5+)

---

## 📬 Commit Message Guidelines

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification.

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, no logic change)
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Adding or updating tests
- `chore`: Build process or auxiliary tool changes

### Examples

```bash
# Feature
feat(message): add message loss detection

# Bug fix
fix(database): resolve crash when saving large batch

# Documentation
docs(readme): update installation instructions

# Performance
perf(sync): optimize incremental sync algorithm

# Multiple changes
feat(message): add message reactions

- Add reaction model
- Implement reaction manager
- Add unit tests

Closes #123
```

---

## 🧪 Testing Guidelines

### Writing Tests

- Write tests for all new features
- Maintain or improve code coverage
- Use descriptive test names

**Example:**

```swift
final class IMMessageManagerTests: XCTestCase {
    
    func testSendMessage_WithValidData_ShouldSucceed() {
        // Given
        let manager = IMMessageManager(database: mockDatabase, userID: "test_user")
        let message = IMMessage()
        message.content = "Hello"
        
        // When
        var result: Result<Void, IMError>?
        manager.sendMessage(message) { res in
            result = res
        }
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isSuccess ?? false)
    }
    
    func testSendMessage_WhenNotConnected_ShouldFail() {
        // Test implementation
    }
}
```

### Test Coverage Goals

- **Core functionality**: 80%+ coverage
- **Business logic**: 70%+ coverage
- **Overall**: 60%+ coverage

### Running Tests

```bash
# All tests
swift test

# Specific test
swift test --filter IMMessageManagerTests.testSendMessage_WithValidData_ShouldSucceed

# With coverage
swift test --enable-code-coverage
```

---

## 🎯 Good First Issues

Looking for a place to start? Check out issues labeled:
- `good first issue`
- `help wanted`
- `documentation`

---

## 📞 Getting Help

- 💬 Join our [Discussions](https://github.com/SwiftIM/SwiftIM-iOS/discussions)
- 📧 Email: support@swiftim.io
- 📖 Check the [Documentation](docs/)

---

## 🏆 Recognition

Contributors will be:
- Listed in our [Contributors](https://github.com/SwiftIM/SwiftIM-iOS/graphs/contributors) page
- Mentioned in release notes (for significant contributions)
- Invited to our contributor community

---

## 📄 License

By contributing to SwiftIM, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing! 🙏

