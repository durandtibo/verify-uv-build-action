# Security Policy

## Supported Versions

The following versions of verify-uv-build-action are currently supported with
security updates:

| Version | Supported          |
| ------- | ------------------ |
| 0.0.x   | :white_check_mark: |

As this is a GitHub Action, we recommend always using the latest stable version
or pinning to a specific commit SHA for maximum security and reproducibility.

## Version Pinning Recommendations

For maximum security in your workflows:

### Option 1: Pin to a Specific Release (Recommended for Stability)

```yaml
- uses: durandtibo/verify-uv-build-action@v0.0.6
```

### Option 2: Pin to a Commit SHA (Maximum Security)

```yaml
- uses: durandtibo/verify-uv-build-action@a1b2c3d4 # Pin to specific commit
```

### Option 3: Use Latest (Not Recommended for Production)

```yaml
- uses: durandtibo/verify-uv-build-action@main # Gets latest changes
```

**Warning**: Using `@main` can introduce unexpected changes. Only use in
non-critical environments or for testing.

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue,
please report it responsibly.

### How to Report

**Please DO NOT create a public GitHub issue for security vulnerabilities.**

Instead, please report security vulnerabilities by:

1. **Email**: Send a detailed report to the repository owner (see GitHub profile
   for contact information)
2. **GitHub Security Advisory**: Use GitHub's private vulnerability reporting
   feature at
   <https://github.com/durandtibo/verify-uv-build-action/security/advisories/new>

### What to Include

Please include the following information in your report:

- Type of vulnerability
- Full paths of affected source file(s)
- Location of the affected code (tag/branch/commit or direct URL)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit it
- Any potential mitigations you've identified

### Response Timeline

- **Initial Response**: Within 48 hours
- **Status Update**: Within 1 week
- **Fix Timeline**: Depends on severity
  - **Critical**: Within 7 days
  - **High**: Within 14 days
  - **Medium**: Within 30 days
  - **Low**: Within 60 days

### After Reporting

1. We will acknowledge receipt of your report
2. We will investigate and validate the vulnerability
3. We will work on a fix and keep you updated on progress
4. Once fixed, we will:
   - Release a patched version
   - Credit you in the security advisory (unless you prefer to remain anonymous)
   - Publicly disclose the vulnerability (after the fix is available)

## Security Best Practices

### For Action Users

When using this action in your workflows:

1. **Pin to Specific Versions**: Avoid using `@main` in production
2. **Use Commit SHAs**: For maximum security, pin to specific commit SHAs
3. **Review Dependencies**: This action uses:
   - `actions/checkout@v6`
   - `astral-sh/setup-uv@v7`
4. **Limit Permissions**: Use minimal required permissions in workflows:

   ```yaml
   permissions:
     contents: read # Only what's needed
   ```

5. **Review Changes**: Check changelogs before updating versions
6. **Use Dependabot**: Enable Dependabot to track action updates:

   ```yaml
   # .github/dependabot.yml
   version: 2
   updates:
     - package-ecosystem: "github-actions"
       directory: "/"
       schedule:
         interval: "weekly"
   ```

### For Contributors

When contributing to this action:

1. **No Secrets in Code**: Never commit secrets, tokens, or credentials
2. **Validate Inputs**: Always validate and sanitize user inputs
3. **Minimal Permissions**: Request only necessary permissions
4. **Dependency Security**: Keep dependencies updated and review for
   vulnerabilities
5. **Code Review**: All changes must be reviewed before merging
6. **Shell Injection**: Avoid direct shell injection vulnerabilities
   - Use proper quoting in shell scripts
   - Validate inputs before using in commands
7. **Secure Defaults**: Use secure defaults (e.g., `set -euo pipefail` in bash)

### Known Security Considerations

This action:

- Runs shell commands with user-provided inputs (package names)
- Installs Python packages during verification
- Executes custom scripts from the repository (optional)

To mitigate risks:

- All operations run in isolated GitHub Actions runners

## Security Features

This action includes several security features:

1. **Input Validation**: The `dist-type` input is strictly validated
2. **Explicit Script Detection**: Optional scripts must be explicitly present
3. **Isolated Execution**: Runs in GitHub Actions' isolated environments
4. **Dependency Pinning**: Uses pinned versions of actions dependencies
5. **Minimal Permissions**: Requests only necessary permissions

## Dependency Security

This action depends on:

- **astral-sh/setup-uv**: Regularly updated for security patches
- **actions/checkout**: Official GitHub action, regularly updated
- **Python/uv**: Uses latest stable releases

We monitor these dependencies and update them regularly via Dependabot.

## Compliance

This action:

- Does not collect or store any user data
- Does not send data to external services (except GitHub and package indexes)
- Operates entirely within GitHub Actions infrastructure
- Respects GitHub's security and privacy policies

## Questions?

If you have questions about security that don't involve reporting a
vulnerability, please:

- Open a GitHub issue for general security questions
- Review our [Contributing Guidelines](CONTRIBUTING.md)
- Check existing documentation in [README.md](README.md)

Thank you for helping keep verify-uv-build-action secure!
