# sui-interaction-scripts
TS scripts for deploying and calling Sui packages.

### Get Started
- rename `.env.example` to `.env` and modify the variables
- install bun: `curl -fsSL https://bun.sh/install | bash`
- run `bun install`
- deploy: `bun run publish`
- call: `bun run call`

### Commands
Modify `package.json` scripts according to the interaction files you create.
You can create a separate call_function_name file for each of the functions in your package.

### Publish Behavior (New Package Manager)
- Uses `sui client publish`, which updates `Published.toml`
- Avoids editing `Move.toml` named addresses or deleting `Move.lock`

### Get Object IDs
The publish script writes object IDs to `./src/data/<package-name>.json` (for example, `account-actions.json`).
You can read IDs with `getId("module_name::type_name")` from `./utils`.