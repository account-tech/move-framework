# Contributing to account.tech

Thank you for your interest in contributing to **account.tech**! We welcome community contributions to improve and 
expand its functionality. Please follow the guidelines below for a smooth process.

## Getting Started

### 1. Fork and Clone
Fork the repository on GitHub and clone it locally:

```sh
git clone https://github.com/account-tech/move-framework.git
cd move-framework
```

### 2. Create a Branch
Create a new branch from `main` for your changes:

```sh
git checkout -b feature-branch-name
```

### 3. Publish Packages

> **Note:**
> Publishing is **only necessary** if your development environment does **not** have `account.tech` published (e.g., on 
> `localnet` or `devnet`).
> If you’re working on `testnet` or `mainnet`, you can use the already published packages on `testnet`. For `mainnet`, 
> you can use them once they have been published.

### Prerequisites
1. [Install Sui](https://docs.sui.io/guides/developer/getting-started/sui-install) and ensure it's running.
2. Publish the [Kiosk Package](https://github.com/MystenLabs/apps).
3. Update its address in the account_actions package manifest [file](/packages/actions/Move.toml).

Set the required environment variables in [scripts](/scripts)/.env (create from `.env.example`) or provide them when prompted.

To publish **account_extensions**, **account_protocol**, and **account_actions** packages, simply execute:

```sh
./publish
```

This will publish all packages. 

## Contribution Guidelines

### Code Contributions
- Follow the [standard Move Conventions](https://docs.sui.io/concepts/sui-move-concepts/conventions)
- Write clear, concise, and well-documented code.
- Ensure new features or fixes do not break existing functionality.
- Add comments where necessary and write tests if applicable.

### Commit Messages
Follow this format for clear commit messages:

```sh
feat: Add new feature
fix: Resolve bug in feature X
chore: Update dependencies
```

## Submitting a Pull Request
1. Push your changes to your fork:
   ```sh
   git push origin feature-branch-name
   ```
2. Create a pull request:
    - Go to the original repository on GitHub.
    - Click on `Pull Requests` > `New pull request`.
    - Select your branch and compare it with `main`.
    - Provide a descriptive title and summary.
    - Submit for review.

## Reporting Issues
If you find a bug or have a feature request, open an issue with:
- A clear description of the issue or feature.
- Steps to reproduce the issue if applicable.
- Suggested fixes if available.

## License
By contributing, you agree that your contributions will be licensed under the project's existing license.

Thank you for contributing! 🚀

