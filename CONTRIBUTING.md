# Contributing to verify-uv-build-action

Thank you for your interest in contributing to verify-uv-build-action! This
document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Code Standards](#code-standards)
- [Submitting Changes](#submitting-changes)
- [Release Process](#release-process)

## Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inclusive experience for everyone.
We pledge to make participation in our project a harassment-free experience for
everyone, regardless of age, body size, disability, ethnicity, gender identity
and expression, level of experience, nationality, personal appearance, race,
religion, or sexual identity and orientation.

### Expected Behavior

- Use welcoming and inclusive language
- Be respectful of differing viewpoints and experiences
- Gracefully accept constructive criticism
- Focus on what is best for the community
- Show empathy towards other community members

### Unacceptable Behavior

- Trolling, insulting/derogatory comments, and personal or political attacks
- Public or private harassment
- Publishing others' private information without explicit permission
- Other conduct which could reasonably be considered inappropriate in a
  professional setting

## Getting Started

### Prerequisites

- Git
- Node.js (for markdownlint)
- Python 3.10 or higher (for testing)
- [uv](https://github.com/astral-sh/uv) package manager
- yamllint (for YAML validation)

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:

   ```bash
   git clone https://github.com/YOUR_USERNAME/verify-uv-build-action.git
   cd verify-uv-build-action
   ```

3. Add the upstream repository:

   ```bash
   git remote add upstream https://github.com/durandtibo/verify-uv-build-action.git
   ```

## Development Setup

### Install Development Dependencies

```bash
# Install markdownlint for Markdown linting
npm install -g markdownlint-cli

# Install yamllint for YAML validation
# On Ubuntu/Debian
sudo apt-get install yamllint

# On macOS
brew install yamllint

# Install uv for package management
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Repository Structure

```text
verify-uv-build-action/
├── .github/
│   ├── workflows/        # GitHub Actions workflows
│   └── dependabot.yml    # Dependabot configuration
├── dev/
│   └── package/          # Optional validation scripts
├── src/
│   └── myproject/        # Example test package
├── tests/                # Test files
├── action.yaml           # Main action definition
├── Makefile             # Development commands
├── pyproject.toml       # Python project configuration
├── README.md            # Main documentation
├── CONTRIBUTING.md      # This file
├── SECURITY.md          # Security policy
└── LICENSE              # License file
```

## Making Changes

### Create a Branch

Create a feature branch for your changes:

```bash
git checkout -b feature/your-feature-name
```

Use descriptive branch names:

- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation changes
- `refactor/` - Code refactoring
- `test/` - Test additions or modifications

### Make Your Changes

1. Make your changes in your feature branch
2. Follow the [Code Standards](#code-standards)
3. Add or update tests as needed
4. Update documentation to reflect your changes

## Testing

### Run Format Checks

The repository includes formatting checks for Markdown and YAML files:

```bash
# Run all format checks
make format

# Or run individually
markdownlint **/*.md
yamllint -f colored .
```

### Test the Action Locally

The action includes comprehensive test workflows:

```bash
# Test with local version of the action
# This is automatically done via GitHub Actions when you push
```

### Test Workflows

The repository includes several test workflows:

- **CI (`ci.yaml`)**: Runs on all pull requests and pushes to main
- **Format (`format.yaml`)**: Validates Markdown and YAML formatting
- **Test Local (`test-local.yaml`)**: Tests the action using local code
- **Test Stable (`test-stable.yaml`)**: Tests the latest stable release
- **Nightly Tests (`nightly-tests.yaml`)**: Runs tests daily

To trigger tests:

1. Push your branch to GitHub
2. Create a pull request
3. CI will automatically run all tests

## Code Standards

### GitHub Actions / YAML

- Use consistent indentation (2 spaces)
- Keep lines under 100 characters when possible
- Use meaningful job and step names
- Add comments for complex logic
- Follow yamllint configuration (`.yamllint.yaml`)

### Shell Scripts

- Use `#!/usr/bin/env bash` shebang
- Always include `set -euo pipefail` for error handling
- Add header comments explaining the script's purpose
- Use meaningful variable names in UPPERCASE
- Add cleanup traps for temporary files
- Quote variables to prevent word splitting
- Provide clear error messages

Example:

```bash
#!/usr/bin/env bash

# Description: Validate package metadata
# Usage: ./check_metadata.sh
# Requirements: uv must be installed

set -euo pipefail

METADATA=$(uv pip show myproject)
echo "$METADATA" | grep -q "Name: myproject"
```

### Markdown

- Follow markdownlint rules (`.markdownlint.json`)
- Maximum line length: 100 characters
- Use ATX-style headers (`#` syntax)
- Include blank lines around code blocks and headers
- Use reference-style links for better readability

### Commit Messages

Write clear, descriptive commit messages:

```text
Short summary (50 chars or less)

More detailed explanation if needed. Wrap at 72 characters.
Explain what changed and why, not how.

- Bullet points are okay
- Use imperative mood: "Add feature" not "Added feature"
```

## Submitting Changes

### Pull Request Process

1. Update your branch with the latest upstream changes:

   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. Push your changes to your fork:

   ```bash
   git push origin feature/your-feature-name
   ```

3. Create a pull request on GitHub with:
   - Clear title describing the change
   - Detailed description of what changed and why
   - Reference any related issues
   - Screenshots for UI changes (if applicable)

4. Ensure all CI checks pass

5. Wait for review and address feedback

### Pull Request Guidelines

- Keep pull requests focused on a single concern
- Write clear descriptions
- Update documentation for new features
- Add tests for new functionality
- Ensure all tests pass
- Keep commits clean and logically organized
- Respond to review feedback promptly

### Review Process

- At least one maintainer approval is required
- All CI checks must pass
- Address all review comments
- Maintainers may request changes or ask questions
- Be patient and respectful during review

## Release Process

Releases are managed by maintainers:

1. Version is updated in relevant files
2. Git tag is created (e.g., `v0.0.3`)
3. GitHub release is created with changelog
4. Action Marketplace is updated automatically

## Getting Help

If you need help:

- Check existing [issues](https://github.com/durandtibo/verify-uv-build-action/issues)
- Read the [README](README.md) documentation
- Open a new issue with your question
- Be clear and provide relevant details

## Recognition

Contributors are recognized in:

- Git commit history
- GitHub contributors page
- Release notes (for significant contributions)

Thank you for contributing to verify-uv-build-action!
